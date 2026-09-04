// +page.server.ts — root route = the §2.1.1 headline Net Worth dashboard (SELF-211).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): resolves the validated session (safeGetSession → getUser()-verified user),
//    then reads the caller's NAV via loadNetWorthView (RLS-scoped anon client — NOT
//    service_role; RT-26 fence passes). Unauthenticated → /login (same pattern as
//    accounts/new + accounts/[account_id]).
//
// V1.0 Option A (F/CTO-ratified): SINGLE trustworthy number. Composition table = V1.1
// (§2.1.5 / SELF-225).
//
// ⚠ SELF-268 / ADR-067 Decision 3 (R3 rider 0) — ONE fn_nav_composition RPC CALL SERVES BOTH THE
//   §2.1.1 HEADLINE AND THE §2.1.5 FOOT. `fetchNavComposition` is called ONCE, below, and the same
//   `RawNavComposition` value is threaded into BOTH `loadNetWorthView` (derives `netWorth` from its
//   `nav` key) AND `loadNavComposition` (attaches the per-row staleness join on top of it) — never
//   two separate calls to the same RPC for one page load. `fn_compute_nav` is no longer called from
//   this route at all; it is retained only for `nav_daily` writes (see netWorth.ts's header).

import { redirect } from '@sveltejs/kit';
import { loadNetWorthView } from '$lib/server/queries/netWorth';
import { fetchNavComposition, loadNavComposition } from '$lib/server/queries/navComposition';
import type { RawNavComposition } from '$lib/server/queries/navComposition';
import { loadStaleness } from '$lib/server/queries/staleness';
import { loadNavSeries, resolveNavSeriesWindow } from '$lib/server/queries/nav-series';
import {
	navSeriesParamsSchema,
	extractNamespacedParams,
	NAV_SERIES_PARAM_PREFIX
} from '$lib/server/schemas/nav-series-params';
import { loadNavBoundary } from '$lib/server/queries/nav-boundary';
import { loadNavDeltaPanel } from '$lib/server/queries/nav-delta-panel';
import { loadNavReferenceDates } from '$lib/server/queries/nav-reference-dates';
import type { NavSeriesGranularity } from '$lib/nav-series';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad } from './$types';


export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, '/login');

	// serverTodayAsOf() replaces the former bare-string todayIso(): the as-of is now a BRANDED
	// ZoneResolvedAsOf, so a plain string cannot reach loadNetWorthView's p_as_of at all. The
	// brand describes the GUARANTEE (the zone question is resolved), not the provenance.
	const asOf = serverTodayAsOf();

	// SELF-268 / R3 rider 0: fetch pfin.fn_nav_composition ONCE here — the §2.1.1 headline
	// (loadNetWorthView below) and the §2.1.5 foot (loadNavComposition further down) both derive
	// from THIS SAME value, never two independent RPC calls. Fail-soft to `null`, logged inside
	// fetchNavComposition; this try/catch is the belt-and-suspenders boundary for an unexpected
	// throw, matching every other read's posture on this route.
	let rawComposition: RawNavComposition | null = null;
	try {
		rawComposition = await fetchNavComposition(locals.supabase, asOf);
	} catch (err) {
		console.error('[+page.server] nav-composition fetch threw; degrading to null:', err);
		rawComposition = null;
	}

	// accountPresence is THREE-VALUED ('some' | 'none' | 'unknown') — 'unknown' means the count
	// read FAILED and is emphatically not 'none'. Passed through verbatim, never collapsed to a
	// boolean here: collapsing is what this change exists to undo, and doing it at the loader
	// would just move the lie one file closer to the render.
	const { netWorth, accountPresence } = await loadNetWorthView(locals.supabase, asOf, rawComposition);

	// D1 non-silent staleness marker (SELF-208 §2.4.4.c; ramped to the V1.1 NW surfaces at
	// SELF-229). FAIL-SOFT is load-bearing: a staleness-read failure must NEVER break or block the
	// NAV number — but "fail-soft" does NOT mean "degrade to confirmed-healthy" (SELF-229 REWORK,
	// F/CTO-ruled, mirrors the SELF-220 Sec round 2 catch). loadStaleness() itself now degrades an
	// RPC error to UNKNOWN_STALENESS (never EMPTY_STALENESS — see staleness.ts's own header); this
	// try/catch is the belt-and-suspenders boundary for an unexpected THROW, and degrades to the
	// SAME UNKNOWN_STALENESS for the same reason — an uncaught exception tells us nothing about
	// whether the tenant's data is actually stale.
	//
	// Per ADR-013 D1 (staleness-marking surface scope is illustrative, not exhaustive) — Sec F4
	// (AMBER round): read D1 live rather than treating this line as its wording, this is a
	// paraphrase — every aggregation that consumed stale-account data carries the marker.
	// `staleness` is
	// loaded ONCE here (fn_aggregation_has_stale_constituent() takes no per-surface argument — a
	// whole-tenant read, not a scoped one; SELF-229 corrected a drafted AC that assumed a
	// `p_scope_filter` parameter which does not exist) and is the SAME value every V1.1 NW surface
	// on this route consumes: the §2.1.1 headline badge below, and — once threaded as props by
	// Frontend — the §2.1.2 chart, §2.1.3 delta panel, and §2.1.4 reference-dates panel all read
	// this identical `staleness`, not a re-invocation of the primitive. §2.1.5 composition (below)
	// additionally joins it down to per-row granularity, because its leaves need to know WHICH
	// account is stale, not just THAT something is — and inherits the SAME unknown-vs-healthy
	// distinction (see staleLinkedSourceIds below). Further surfaces ramp later, per D1 — the
	// surface list here is not meant to be exhaustive either.
	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[+page.server] staleness load threw; degrading to unknown staleness:', err);
		staleness = UNKNOWN_STALENESS;
	}

	// SELF-229: the caller's stale linked_source_ids, as the tri-state input
	// loadNavComposition's per-row join expects (SELF-199 bigint convention). Built ONCE here
	// from the SAME `staleness` read above — never a second call to the 046 primitive — so the
	// composition table's per-row markers and the rollup badge can never disagree about what
	// counts as stale.
	//
	// `staleness.is_stale === null` means the ROOT read itself was unknown (see above) — passed
	// through as `null` rather than an empty Set, so loadNavComposition propagates UNKNOWN to
	// every leaf instead of misreading "we don't know" as "we checked and it's empty" (the SAME
	// silent-fresh-on-failure hazard one layer up).
	const staleLinkedSourceIds =
		staleness.is_stale === null
			? null
			: new Set(staleness.stale_items.map((item) => String(item.linked_source_id)));

	// §2.1.5 NAV-composition table (V1.1 / SELF-226; per-row staleness ramped at SELF-229; read
	// source shared with the headline at SELF-268 / R3 rider 0). `rawComposition` (fetched once,
	// above) is threaded in as the 4th argument so this does NOT re-call fn_nav_composition — it
	// only attaches the per-row staleness join on top of the SAME tree the headline's `netWorth`
	// came from. ⚠ Because they now share one underlying read, a composition-fetch failure
	// (`rawComposition === null`) degrades BOTH the §2.1.5 table AND the §2.1.1 headline netWorth
	// to their respective "unavailable" states together — this is no longer a case where the foot
	// can fail alone while the headline stays up, because there is only one read to fail.
	// loadNavComposition() still fails soft internally to `null`; this try/catch is the
	// belt-and-suspenders boundary so an unexpected throw (e.g. from the per-row staleness join)
	// can't take down the whole route. staleLinkedSourceIds threads the per-row join — composition
	// NEVER re-reads staleness itself, only the value computed above. NOTE: `null` here can mean
	// EITHER the whole tree is unavailable (rawComposition was null) OR a narrower failure (the
	// root staleness read or the per-row join alone) — the narrower case instead degrades to
	// `is_stale: null` per leaf (see navComposition.ts), so the composition table can still render
	// with an explicit "staleness unknown" state rather than disappearing over a metadata-only
	// failure.
	let composition = null;
	try {
		composition = await loadNavComposition(
			locals.supabase,
			asOf,
			staleLinkedSourceIds,
			rawComposition
		);
	} catch (err) {
		console.error('[+page.server] composition load threw; degrading to null:', err);
		composition = null;
	}

	// §2.1.2.d NAV-over-time chart (SELF-220), mounted below the composition
	// table (SELF-211/226).
	//
	// QUERY-PARAM VALIDATION IS CHART-SCOPED, NOT PAGE-SCOPED (F/CTO-adjacent
	// team-lead ruling, aligned with Frontend's independent read, 2026-08-12
	// — REVISES this route's earlier page-wide `error(400, ...)` shape). The
	// params gate only the chart's own data window: their blast radius must
	// be the chart, not the §2.1.1 headline or composition table this route
	// also serves. A page-wide 400 turns a hand-edited URL into a dashboard
	// outage, which is a worse posture than the bad param it was rejecting.
	//
	// THE `chart_` NAMESPACE IS THE SAME INVARIANT APPLIED A SECOND TIME, ONE
	// LEVEL DOWN (F/CTO-ratified 2026-08-13, Sec's param-fence finding, option
	// A). `Object.fromEntries(url.searchParams)` strict-parsed the WHOLE
	// page's query string — an unrelated param anywhere on the URL (a
	// tracker's `?utm_source=`) tripped `.strict()`'s unknown-key rejection
	// and disabled the chart, which is the page-scoped-blast-radius defect
	// AGAIN, just triggered by a param instead of a read failure. The fix:
	// extract ONLY the `chart_`-prefixed subset by structural PREFIX
	// MEMBERSHIP (`extractNamespacedParams`), then `.strict()`-parse THAT
	// subset. A key outside the namespace is simply not chart input, never
	// presented to the schema; a key INSIDE the namespace the schema doesn't
	// recognize (`chart_bogus`) still reaches `.strict()` and is still
	// REJECTED — see nav-series-params.ts's header for why this is NOT
	// "pick expected keys then parse" (that shape would hide an unrecognized
	// key WITHIN the namespace from the fence, defeating it).
	//
	// THE REJECTION ITSELF STAYS STRICT WITHIN THAT SCOPE — an invalid
	// granularity/date is NEVER silently coerced into the default window.
	// Lock 14's reject-don't-launder instinct survives at chart scope even
	// though Lock 14 itself is a WRITE-path posture (settings
	// mass-assignment) and this is a READ boundary — route-consistency
	// (soft-degrade, chart-scoped, matching staleness/composition below) is
	// the stronger precedent here, not a page-wide throw. `navSeriesParamsError`
	// carries the REASON as a factual message ("chart_granularity: Invalid
	// enum value...") for Frontend to render as an explicit chart error
	// state — this is the THIRD distinguishable navSeries state, alongside
	// `null` (read failed) and `[]` (read succeeded, nothing in range):
	// invalid params never even reach a read, so `navSeries` stays `null`
	// here too, but `navSeriesParamsError` being non-null is what tells
	// Frontend WHY, rather than leaving "read failed" and "params rejected"
	// indistinguishable.
	const rawNavSeriesParams = extractNamespacedParams(url.searchParams, NAV_SERIES_PARAM_PREFIX);
	const parsedNavSeriesParams = navSeriesParamsSchema.safeParse(rawNavSeriesParams);

	let navSeries: Awaited<ReturnType<typeof loadNavSeries>> = null;
	let navSeriesParamsError: string | null = null;
	let navSeriesGranularity: NavSeriesGranularity = 'monthly';
	let navSeriesStart: string;
	let navSeriesEnd: string;

	if (!parsedNavSeriesParams.success) {
		navSeriesParamsError = parsedNavSeriesParams.error.issues
			.map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
			.join('; ');
		// Params rejected — nothing is queried. The DEFAULT window still
		// resolves so `navSeriesParams` always has a coherent value for
		// Frontend's controls to initialize from, but it is NOT what was
		// requested and NOT what produced `navSeries` (which stays `null`,
		// unattempted) — `navSeriesParamsError` is what marks that gap.
		const defaults = resolveNavSeriesWindow(undefined, undefined);
		navSeriesStart = defaults.start;
		navSeriesEnd = defaults.end;
	} else {
		navSeriesGranularity = parsedNavSeriesParams.data.chart_granularity ?? 'monthly';
		const resolved = resolveNavSeriesWindow(
			parsedNavSeriesParams.data.chart_start,
			parsedNavSeriesParams.data.chart_end
		);
		navSeriesStart = resolved.start;
		navSeriesEnd = resolved.end;
		// No post-resolve inversion check needed here: the schema's own
		// `.refine()` above already rejects an inverted CALLER-SUPPLIED range
		// (caught by the `!parsedNavSeriesParams.success` branch), and
		// resolveNavSeriesWindow can never PRODUCE one from defaulting (a
		// defaulted start is computed as an offset before its own resolved end).

		// §2.1.2.d fail-soft posture DIFFERS from staleness/composition above
		// on PURPOSE: `null` = the read failed (logged, never thrown); `[]` =
		// the read succeeded and found no points in range — a real,
		// distinguishable state. Collapsing both into `[]` would make an RPC
		// failure render the SAME "Collect data over time" empty-state copy
		// (AC6) as a genuine zero-row series — the same class of hazard
		// netWorth.ts's own header names at length for the old boolean
		// `hasAccounts`. loadNavSeries() already fails soft internally to
		// `null`; this try/catch is the belt-and-suspenders boundary so an
		// unexpected throw degrades to the SAME `null` rather than taking
		// down the whole route.
		try {
			navSeries = await loadNavSeries(
				locals.supabase,
				navSeriesGranularity,
				navSeriesStart,
				navSeriesEnd
			);
		} catch (err) {
			console.error('[+page.server] nav-series load threw; degrading to null:', err);
			navSeries = null;
		}
	}

	// §2.1.2 cron/imported boundary signal (SELF-220 / 069), fetched FRESH
	// alongside the series on every load() — no caching, no client-side
	// derivation (the whole reason 069 exists is that this must NOT be
	// inferred from point density — see nav-boundary.ts's module header and
	// $lib/nav-boundary.ts's own header). Independent of the chart's
	// granularity/date-range params — it is a property of the tenant's STORE,
	// not of any requested window — so it is fetched unconditionally, even
	// when navSeriesParamsError is set: Frontend's resolution-disclosure and
	// staleness-suppression logic need it regardless of what range is
	// currently selected.
	//
	// Same fail-soft-to-`null` posture as navSeries, for the SAME reason:
	// `null` = the read failed (logged, never thrown); a genuinely returned
	// `{ first_cron_checkpoint: null, has_cron_rows: false,
	// has_imported_rows: false }` = the read succeeded and this tenant
	// genuinely has no rows yet — 069's own state (a), a REAL row, not an
	// absence. Collapsing the two would be the identical hazard one layer up
	// from what 069's three-field (not scalar) return already prevents at
	// the DB layer. loadNavBoundary() already fails soft internally to
	// `null`; this try/catch is the belt-and-suspenders boundary so an
	// unexpected throw degrades to the SAME `null` rather than taking down
	// the whole route.
	let navBoundary: Awaited<ReturnType<typeof loadNavBoundary>> = null;
	try {
		navBoundary = await loadNavBoundary(locals.supabase);
	} catch (err) {
		console.error('[+page.server] nav-boundary load threw; degrading to null:', err);
		navBoundary = null;
	}

	// §2.1.3.a NAV-delta panel (V1.1 / SELF-221 backend; SELF-222 is the UI
	// consumer). Zero-arg RPC — pfin.fn_nav_delta_panel() derives tenant from
	// session RLS and "today" from pfin.fn_server_today() (070, ADR-044 R2)
	// entirely server-side; nothing is passed in from this loader. Same
	// FAIL-SOFT posture as navBoundary above: `null` = the read failed (RPC
	// error, wrong-shaped payload) — logged, never thrown. A genuine result is
	// passed straight through unreordered and unfiltered — 071's own contract
	// is "EXACTLY FIVE ROWS, ALWAYS, in fixed order", so this loader performs
	// no ordering, filtering, or date arithmetic of its own; that is
	// loadNavDeltaPanel()'s and, downstream, the panel component's job.
	// loadNavDeltaPanel() already fails soft internally to `null`; this
	// try/catch is the belt-and-suspenders boundary so an unexpected throw
	// can't take down the NAV surface.
	let navDeltaPanel: Awaited<ReturnType<typeof loadNavDeltaPanel>> = null;
	try {
		navDeltaPanel = await loadNavDeltaPanel(locals.supabase);
	} catch (err) {
		console.error('[+page.server] nav-delta-panel load threw; degrading to null:', err);
		navDeltaPanel = null;
	}

	// §2.1.4 NAV-at-three-reference-dates panel (V1.1 / SELF-223 backend;
	// SELF-223's own UI is the consumer). Zero-arg RPC — pfin.fn_nav_reference_dates()
	// derives tenant from session RLS and "today" from pfin.fn_server_today()
	// (070, ADR-044 R2) entirely server-side, same as navDeltaPanel above;
	// nothing is passed in from this loader. Same FAIL-SOFT posture: `null` =
	// the read failed (RPC error, wrong-shaped payload) — logged, never
	// thrown. A genuine result is passed straight through unreordered and
	// unfiltered — the ratified contract is "EXACTLY THREE ROWS, ALWAYS, in
	// fixed order", so this loader performs no ordering, filtering, or date
	// arithmetic of its own; that is loadNavReferenceDates()'s and,
	// downstream, the panel component's job. loadNavReferenceDates() already
	// fails soft internally to `null`; this try/catch is the
	// belt-and-suspenders boundary so an unexpected throw can't take down the
	// NAV surface.
	let navReferenceDates: Awaited<ReturnType<typeof loadNavReferenceDates>> = null;
	try {
		navReferenceDates = await loadNavReferenceDates(locals.supabase);
	} catch (err) {
		console.error('[+page.server] nav-reference-dates load threw; degrading to null:', err);
		navReferenceDates = null;
	}

	return {
		netWorth,
		accountPresence,
		asOf,
		staleness,
		composition,
		navSeries,
		navSeriesParamsError,
		navSeriesParams: {
			granularity: navSeriesGranularity,
			start: navSeriesStart,
			end: navSeriesEnd
		},
		navBoundary,
		navDeltaPanel,
		navReferenceDates
	};
};
