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
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import type { PageServerLoad } from './$types';

/** Today's date as an ISO YYYY-MM-DD string — the as-of/LOCF valuation date. */
function todayIso(): string {
	return new Date().toISOString().slice(0, 10);
}

export const load: PageServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, '/login');

	const asOf = todayIso();
	const { netWorth, hasAccounts } = await loadNetWorthView(locals.supabase, asOf);

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

	return { netWorth, hasAccounts, asOf, staleness, composition };
};
