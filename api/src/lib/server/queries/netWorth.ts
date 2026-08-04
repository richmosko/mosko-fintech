// netWorth.ts — server-side read for the §2.1.1 headline Net Worth surface (SELF-211).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// The §2.1.1 read is a SINGLE trustworthy number: pfin.fn_compute_nav, the Architect-authored
// SECURITY INVOKER uniform-valuation helper landed at migration 019 (SELF-277). INVOKER means
// the caller's RLS context propagates — we call it through the per-request anon client
// (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11). fn_compute_nav takes NO
// users_id/scope param (tenancy is auth.uid()); the Wave-1 issue's fn_nav(users_id, scope[])
// contract predates the substrate and is superseded (SELF-210 reconciled to a verification
// note — the substrate absorbed the aggregation).
//
// OPEN-AS-OF SCOPE (SELF-322 / ADR-039, migration 050; re-pointed at 059 per ADR-042): the
// headline calls the 2-arg fn_compute_nav(p_as_of, p_active_only => true) so the NAV counts only
// accounts OPEN AS OF p_as_of, and reconciles EXACTLY with the §2.1.5 composition (049). The
// 019/1-arg wrapper (all accounts, including closed) is reserved for the book/GL memo (037) +
// historical trend — NOT the headline.
//
// ⛔ THE ADR-039 N3 TEMPORAL FENCE THAT STOOD HERE IS STRUCK, NOT RELAXED — and it is called out
//    rather than deleted, because the deletion is the part nobody can review. It read:
//    "p_active_only => true is sound ONLY at p_as_of = current_date … a future §2.1.2 trajectory /
//    historical NAV must NOT reuse this active-only path with a past date."
//    That was TRUE of is_active and is FALSE of closed_at. It rested entirely on the filter being
//    a CURRENT-STATE boolean, so filtering it into a past as_of rewrote history. 059's predicate
//    is `closed_at is null or closed_at > p_as_of` — temporal — and 059's own catalog comment
//    states the strike verbatim: the path is now sound at ANY p_as_of. Left standing, this comment
//    would forbid exactly the path 059 made correct, and A FALSE PROHIBITION LEAVES NO ARTIFACT:
//    nobody tests the path they were told not to take, so nothing ever fails to reveal it.
//    A §2.1.2 trajectory MAY now call this path with a past date. (Whether it SHOULD, versus
//    reading frozen nav_daily checkpoints, is a cost/consistency question — not a soundness one.)
//
// The composition breakdown (GAV / Debt / tax lines) is §2.1.5 = V1.1 (SELF-225); V1.0
// renders the single number only, per PRD §2.1.1 verbatim + F/CTO Option A.

import type { SupabaseClient } from '@supabase/supabase-js';

export type NetWorthView = {
	/**
	 * USD net worth as of the requested date, from pfin.fn_compute_nav. `null` iff the
	 * compute failed (the surface degrades to an "unavailable" state, never throws / never
	 * renders a wrong number). A genuine $0 position returns `0`, not `null`.
	 */
	netWorth: number | null;
	/**
	 * Whether the caller owns any account OPEN AS OF the same `asOf` the NAV was computed at.
	 * Distinguishes the zero-account empty-state ("connect your first account") from a real $0
	 * net worth — fn_compute_nav returns 0 in BOTH cases, so the count is the disambiguator.
	 *
	 * "As of the SAME asOf" is the load-bearing half: this count and the NAV are two reads that
	 * must describe one population. Scoping them differently makes the disambiguator disagree with
	 * the thing it disambiguates.
	 */
	hasAccounts: boolean;
};

/**
 * Load the §2.1.1 headline view for the caller, RLS-scoped via the per-request anon client.
 * Two independent reads (both fail soft, logged): the NAV compute + an open-account count, BOTH
 * scoped to the same `asOf`. `asOf` is an ISO date string (YYYY-MM-DD) — the LOCF valuation date
 * passed to fn_compute_nav.
 */
export async function loadNetWorthView(
	supabase: SupabaseClient,
	asOf: string
): Promise<NetWorthView> {
	// ── NAV compute (INVOKER; RLS-scoped to auth.uid()) ───────────────────────────
	// fn_compute_nav(p_as_of date, p_active_only boolean) RETURNS numeric. p_active_only:true =
	// the headline scope — accounts OPEN AS OF p_as_of (SELF-322 / ADR-039, re-pointed at 059).
	// ⚠ p_active_only is a PROVABLE NO-OP ON VALUE post-059 (a closed account holds zero at and
	// after closure by the 058 gate + transfer-in fence), so `true` and `false` return the same
	// number for every date. It is passed explicitly ANYWAY, and NOT because the value differs:
	// TRUE and FALSE remain different QUESTIONS ("open as of d" vs "all accounts, closed
	// included"), and 059's comment enumerates four fences in other files whose weakening
	// restores a real divergence this argument would then be selecting between. Dropping it
	// because "it makes no difference today" discards the only record of which question we asked.
	// supabase-js returns a scalar RPC as the raw value; a Postgres numeric may arrive as number
	// OR string → coerce. A NaN coercion (should never happen — the DB NaN-fences price) degrades
	// to null, not a poisoned render.
	let netWorth: number | null = null;
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_compute_nav', { p_as_of: asOf, p_active_only: true });
	if (error) {
		console.error('[netWorth] fn_compute_nav failed:', error.message);
	} else {
		const n = data === null || data === undefined ? 0 : Number(data);
		netWorth = Number.isFinite(n) ? n : null;
	}

	// ── open-account presence (empty-state disambiguator) ─────────────────────────
	// head:true + count:'exact' → no rows shipped, just the RLS-scoped count.
	//
	// THE PREDICATE MIRRORS fn_compute_nav's, DELIBERATELY LITERALLY (059 / ADR-042):
	//   SQL:       (acc.closed_at is null or acc.closed_at > p_as_of)
	//   PostgREST: closed_at.is.null,closed_at.gt.<asOf>
	// It is written AS-OF and not as the shorter `.is('closed_at', null)`, and THAT CHOICE IS THE
	// WHOLE POINT OF THIS COMMENT. The two forms are behaviourally IDENTICAL at asOf = today —
	// 058's gate refuses a future closed_at, so no row can satisfy `closed_at > today` — which
	// means a current-state re-point here would be indistinguishable from a correct one under
	// every test we can write today, and would diverge silently the first time a caller passes a
	// past date. 059 has just made that legal (the ADR-039 N3 fence is struck — see the header),
	// so "the sole caller passes today" is no longer a property anyone may build on.
	// 059's own fn_compute_nav comment names this same trap as its dependency (4), "the one with
	// no footprint". This is that dependency, one layer up.
	//
	// asOf is the SAME value passed to fn_compute_nav above. Do not re-derive it from a clock
	// here: two reads that must describe one population must not read two different dates.
	const { count, error: countErr } = await supabase
		.schema('pfin')
		.from('account')
		.select('account_id', { count: 'exact', head: true })
		.or(`closed_at.is.null,closed_at.gt.${asOf}`);
	if (countErr) {
		console.error('[netWorth] active-account count failed:', countErr.message);
	}
	const hasAccounts = !countErr && (count ?? 0) > 0;

	return { netWorth, hasAccounts };
}
