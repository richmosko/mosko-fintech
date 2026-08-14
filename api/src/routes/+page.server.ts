// +page.server.ts — root route = the §2.1.1 headline Net Worth dashboard (SELF-211).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): resolves the validated session (safeGetSession → getUser()-verified user),
//    then reads the caller's NAV via loadNetWorthView (RLS-scoped anon client — NOT
//    service_role; RT-26 fence passes). Unauthenticated → /login (same pattern as
//    accounts/new + accounts/[account_id]).
//
// V1.0 Option A (F/CTO-ratified): SINGLE trustworthy number. Composition table = V1.1
// (§2.1.5 / SELF-225). No new DB function — fn_compute_nav (019) IS the aggregation.

import { redirect } from '@sveltejs/kit';
import { loadNetWorthView } from '$lib/server/queries/netWorth';
import { loadNavComposition } from '$lib/server/queries/navComposition';
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
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import type { PageServerLoad } from './$types';


export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, '/login');

	// serverTodayAsOf() replaces the former bare-string todayIso(): the as-of is now a BRANDED
	// ZoneResolvedAsOf, so a plain string cannot reach loadNetWorthView's p_as_of at all. The
	// brand describes the GUARANTEE (the zone question is resolved), not the provenance.
	const asOf = serverTodayAsOf();
	// accountPresence is THREE-VALUED ('some' | 'none' | 'unknown') — 'unknown' means the count
	// read FAILED and is emphatically not 'none'. Passed through verbatim, never collapsed to a
	// boolean here: collapsing is what this change exists to undo, and doing it at the loader
	// would just move the lie one file closer to the render.
	const { netWorth, accountPresence } = await loadNetWorthView(locals.supabase, asOf);

	// D1 non-silent staleness marker (SELF-208 §2.4.4.c). FAIL-SOFT is load-bearing: a
	// staleness-read failure must NEVER break or block the NAV number — degrade to an empty
	// staleness (badge simply doesn't render), mirroring the NAV's degrade-never-wrong-number
	// posture. loadStaleness() already fails soft internally; this try/catch is the belt-and-
	// suspenders boundary so an unexpected throw can never take down the NAV surface.
	let staleness = EMPTY_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[+page.server] staleness load threw; degrading to empty staleness:', err);
		staleness = EMPTY_STALENESS;
	}

	// §2.1.5 NAV-composition table (V1.1 / SELF-226). Same FAIL-SOFT posture as staleness above:
	// a composition-read failure must NEVER take down the §2.1.1 headline netWorth — degrade to
	// `null` (the table just doesn't render; the headline still shows). loadNavComposition() fails
	// soft internally; this try/catch is the belt-and-suspenders boundary so an unexpected throw
	// can't take down the NAV surface. asOf is passed explicitly so the composition foots to the
	// headline's fn_compute_nav(asOf, true) by construction (051 FOOT-TO-NAV EXACT).
	let composition = null;
	try {
		composition = await loadNavComposition(locals.supabase, asOf);
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
