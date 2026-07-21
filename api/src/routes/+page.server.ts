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

	return { netWorth, hasAccounts, asOf };
};
