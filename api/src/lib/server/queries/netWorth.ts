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
// CURRENT-STATE SCOPE (SELF-322 / ADR-039, migration 050): the headline calls the 2-arg
// fn_compute_nav(p_as_of, p_active_only => true) so the NAV EXCLUDES soft-deleted (inactive)
// accounts (PRD §2.4.2; the 012 is_active current-state convention) and reconciles EXACTLY
// with the §2.1.5 composition (049, active-only). The 019/1-arg wrapper (all-accounts) is
// reserved for the book/GL memo (037) + historical trend — NOT the current-state headline.
// TEMPORAL FENCE (load-bearing, ADR-039 N3): p_active_only => true is sound ONLY at
// p_as_of = current_date (is_active is a current-state boolean, not temporal — filtering it
// into a past as_of would rewrite history). The sole caller (+page.server.ts) passes
// todayIso() = current_date, so the fence holds by construction. A future §2.1.2 trajectory /
// historical NAV must NOT reuse this active-only path with a past date — derive history from
// frozen precomputed checkpoints instead.
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
	 * Whether the caller owns any ACTIVE account (is_active = TRUE). Distinguishes the
	 * zero-account empty-state ("connect your first account") from a real $0 net worth —
	 * fn_compute_nav returns 0 in BOTH cases, so the count is the disambiguator.
	 */
	hasAccounts: boolean;
};

/**
 * Load the §2.1.1 headline view for the caller, RLS-scoped via the per-request anon client.
 * Two independent reads (both fail soft, logged): the NAV compute + an active-account count.
 * `asOf` is an ISO date string (YYYY-MM-DD) — the LOCF valuation date passed to fn_compute_nav.
 */
export async function loadNetWorthView(
	supabase: SupabaseClient,
	asOf: string
): Promise<NetWorthView> {
	// ── NAV compute (INVOKER; RLS-scoped to auth.uid()) ───────────────────────────
	// fn_compute_nav(p_as_of date, p_active_only boolean) RETURNS numeric. p_active_only:true
	// = current-state headline scope (active accounts only; SELF-322 / ADR-039). asOf is
	// current_date at this call site (the ADR-039 N3 temporal fence — see header). supabase-js
	// returns a scalar RPC as the raw value; a Postgres numeric may arrive as number OR string
	// → coerce. A NaN coercion (should never happen — the DB NaN-fences price) degrades to
	// null, not a poisoned render.
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

	// ── active-account presence (empty-state disambiguator) ───────────────────────
	// head:true + count:'exact' → no rows shipped, just the RLS-scoped count. is_active
	// filter mirrors the NAV/current-state CONTRACT (api/CLAUDE.md: filter is_active).
	const { count, error: countErr } = await supabase
		.schema('pfin')
		.from('account')
		.select('account_id', { count: 'exact', head: true })
		.eq('is_active', true);
	if (countErr) {
		console.error('[netWorth] active-account count failed:', countErr.message);
	}
	const hasAccounts = !countErr && (count ?? 0) > 0;

	return { netWorth, hasAccounts };
}
