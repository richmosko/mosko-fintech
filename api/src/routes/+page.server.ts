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
import { loadNavHistory, resolveNavHistoryWindow } from '$lib/server/queries/navHistory';
import { navHistoryParamsSchema } from '$lib/server/schemas/navHistory';
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

	// §2.1.2.c NAV-over-time chart (SELF-220), mounted below the composition
	// table (SELF-211/226). Query-param boundary: Zod `.strict()` REJECTS an
	// unrecognized key or an unparseable value with a clean 400 — this is Lock
	// 14's actual security boundary (input validation), a DIFFERENT failure
	// class from a DB-read failure, and it is deliberately NOT fail-soft the
	// way the reads below it are. A malformed chart param is caller error
	// (or a deliberately hand-edited URL — normal UI interaction goes through
	// Frontend's client-side mirror guard first and never sends one), and
	// Lock 14's posture on caller error is REJECT OUTRIGHT, not silently
	// coerce or default around it. Every OTHER read on this route degrades on
	// FAILURE (network/DB), which is a different kind of problem this route
	// has always chosen to survive; this 400 is not a departure from that
	// posture, it is upstream of it — bad input never reaches a "read failed"
	// state at all, because it never becomes a read.
	const rawNavHistoryParams = Object.fromEntries(url.searchParams);
	const parsedNavHistoryParams = navHistoryParamsSchema.safeParse(rawNavHistoryParams);
	if (!parsedNavHistoryParams.success) {
		throw error(
			400,
			`Invalid nav-history query parameters: ${parsedNavHistoryParams.error.issues
				.map((issue) => `${issue.path.join('.') || '(root)'}: ${issue.message}`)
				.join('; ')}`
		);
	}
	const navHistoryGranularity = parsedNavHistoryParams.data.granularity ?? 'monthly';
	const { start: navHistoryStart, end: navHistoryEnd } = resolveNavHistoryWindow(
		parsedNavHistoryParams.data.start,
		parsedNavHistoryParams.data.end
	);
	if (navHistoryStart > navHistoryEnd) {
		// Only reachable when BOTH were caller-supplied and inverted —
		// resolveNavHistoryWindow's own derivation can never produce this
		// (a defaulted start is computed AS an offset before its own end).
		// 067 would itself RAISE on this (062's argument validation), but
		// failing here is a clean 400 naming the actual mistake rather than
		// a Postgres exception surfacing through the RPC error path.
		throw error(
			400,
			`Invalid nav-history query parameters: start (${navHistoryStart}) is after end (${navHistoryEnd}).`
		);
	}

	// Same FAIL-SOFT posture as staleness/composition above: a chart-data
	// read failure must never take down the §2.1.1 headline NAV or any other
	// section of this dashboard. loadNavHistory() already fails soft
	// internally (degrades to []); this try/catch is the belt-and-suspenders
	// boundary so an unexpected throw can't take down the whole route either.
	let navHistory: Awaited<ReturnType<typeof loadNavHistory>> = [];
	try {
		navHistory = await loadNavHistory(
			locals.supabase,
			navHistoryGranularity,
			navHistoryStart,
			navHistoryEnd
		);
	} catch (err) {
		console.error('[+page.server] nav-history load threw; degrading to empty series:', err);
		navHistory = [];
	}

	return {
		netWorth,
		accountPresence,
		asOf,
		staleness,
		composition,
		navHistory,
		navHistoryParams: {
			granularity: navHistoryGranularity,
			start: navHistoryStart,
			end: navHistoryEnd
		}
	};
};
