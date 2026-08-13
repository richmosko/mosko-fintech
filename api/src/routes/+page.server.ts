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

import { error, redirect } from '@sveltejs/kit';
import { loadNetWorthView } from '$lib/server/queries/netWorth';
import { loadNavComposition } from '$lib/server/queries/navComposition';
import { loadStaleness } from '$lib/server/queries/staleness';
import { loadNavSeries, resolveNavSeriesWindow } from '$lib/server/queries/nav-series';
import { navSeriesParamsSchema } from '$lib/server/schemas/nav-series-params';
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
	// table (SELF-211/226). Query-param boundary: Zod `.strict()` REJECTS an
	// unrecognized key, an unparseable value, or an inverted start/end (the
	// schema's own `.refine()`) with a clean 400 — this is Lock 14's actual
	// security boundary (input validation), a DIFFERENT failure class from a
	// DB-read failure, and it is deliberately NOT fail-soft the way the reads
	// below it are. A malformed chart param is caller error (or a
	// deliberately hand-edited URL — normal UI interaction goes through
	// Frontend's client-side mirror guard first and never sends one), and
	// Lock 14's posture on caller error is REJECT OUTRIGHT, not silently
	// coerce or default around it. Every OTHER read on this route degrades on
	// FAILURE (network/DB), which is a different kind of problem this route
	// has always chosen to survive; this 400 is not a departure from that
	// posture, it is upstream of it — bad input never reaches a "read failed"
	// state at all, because it never becomes a read.
	const rawNavSeriesParams = Object.fromEntries(url.searchParams);
	const parsedNavSeriesParams = navSeriesParamsSchema.safeParse(rawNavSeriesParams);
	if (!parsedNavSeriesParams.success) {
		throw error(
			400,
			`Invalid nav-series query parameters: ${parsedNavSeriesParams.error.issues
				.map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
				.join('; ')}`
		);
	}
	const navSeriesGranularity = parsedNavSeriesParams.data.granularity ?? 'monthly';
	const { start: navSeriesStart, end: navSeriesEnd } = resolveNavSeriesWindow(
		parsedNavSeriesParams.data.start,
		parsedNavSeriesParams.data.end
	);
	// No post-resolve inversion check needed here: the schema's own
	// `.refine()` above already rejects an inverted CALLER-SUPPLIED range,
	// and resolveNavSeriesWindow can never PRODUCE one from defaulting (a
	// defaulted start is computed as an offset before its own resolved end).

	// §2.1.2.d fail-soft posture DIFFERS from staleness/composition above on
	// PURPOSE: `null` = the read failed (logged, never thrown); `[]` = the
	// read succeeded and found no points in range — a real, distinguishable
	// state. Collapsing both into `[]` would make an RPC failure render the
	// SAME "Collect data over time" empty-state copy (AC6) as a genuine
	// zero-row series — the same class of hazard netWorth.ts's own header
	// names at length for the old boolean `hasAccounts`. loadNavSeries()
	// already fails soft internally to `null`; this try/catch is the
	// belt-and-suspenders boundary so an unexpected throw degrades to the
	// SAME `null` rather than taking down the whole route.
	let navSeries: Awaited<ReturnType<typeof loadNavSeries>> = null;
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

	return {
		netWorth,
		accountPresence,
		asOf,
		staleness,
		composition,
		navSeries,
		navSeriesParams: {
			granularity: navSeriesGranularity,
			start: navSeriesStart,
			end: navSeriesEnd
		}
	};
};
