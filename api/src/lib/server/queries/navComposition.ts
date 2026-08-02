// navComposition.ts — server-side read for the §2.1.5 NAV-composition table (V1.1; SELF-226).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's `051` pfin.fn_nav_composition(p_as_of date default current_date) — a
// SECURITY INVOKER read-composition helper (Lock 11; prosecdef=f) — through the per-request
// anon/authenticated client so the caller's RLS context propagates (users_id = auth.uid()),
// NEVER service_role (RT-26 / Lock 11). 051 composes on `049` (fn_account_unrealized_gl, itself
// INVOKER) + a direct-owner read of pfin.account, so owner-isolation is INHERITED at the DB: a
// cross-tenant caller sees no leaf rows → empty groups / nav 0 (fails closed).
//
// fn_nav_composition RETURNS jsonb (a SCALAR jsonb, NOT set-returning) — supabase-js hands the
// parsed object straight back (contrast staleness.ts, whose RPC is set-returning → array[0]).
// The returned tree foots EXACT to fn_compute_nav(p_as_of, true) BY CONSTRUCTION (051 header
// FOOT-TO-NAV EXACT), so we pass the SAME asOf the §2.1.1 headline passes (see call site) to keep
// the composition and the headline number reconciled.
//
// Fail-soft is load-bearing (mirrors netWorth.ts / staleness.ts): any error degrades to `null`
// (logged server-side, never thrown). `null` = "composition unavailable" (the table simply
// doesn't render) — it must NEVER take down the §2.1.1 headline NAV. A genuine zero-account
// tenant still gets a well-formed tree ({ groups: [], buildups: {…0…}, nav: 0 }), not null.

import type { SupabaseClient } from '@supabase/supabase-js';

/** One per-account leaf row inside a category group (straight from 051 → 049, naturally signed). */
export type NavCompositionAccount = {
	/** pfin.account.account_id — bigint, arrives as a JSON number in the jsonb projection. */
	account_id: number;
	account_name: string;
	/** 049 current_market_value; liability leaves are naturally negative (051 DEBT-SIGN D-1). */
	current_market_value: number;
	/** 049 unrealized G/L; NULL for non-investment accounts (051 AC#3). */
	unrealized_gl: number | null;
};

/** One category group — canonical order, empty categories omitted (051 A4). */
export type NavCompositionGroup = {
	/** pfin.account.account_type discriminator (depository/investment/…/real_estate/liability). */
	category: string;
	accounts: NavCompositionAccount[];
	/** Σ current_market_value in-category (natural sign; liability subtotal is negative). */
	subtotal: number;
};

/** Buildup subtotals over the FULL active-account set (051 A3 / FOOT-TO-NAV EXACT). */
export type NavCompositionBuildups = {
	total_non_re: number;
	gross_total: number;
	/** −(liability subtotal) = a positive magnitude, so nav = gross_total − debt reads literally. */
	debt: number;
	/** Option A V1.1 placeholder = 0; V1.4 ramp (051 A5). */
	realized_tax_liab: number;
	/** Option A V1.1 placeholder = 0; V1.4 ramp (051 A5). */
	unrealized_tax_liab: number;
};

/** The full §2.1.5 composition tree — the raw shape of the 051 jsonb return. */
export type NavComposition = {
	groups: NavCompositionGroup[];
	buildups: NavCompositionBuildups;
	nav: number;
};

/**
 * Load the caller's §2.1.5 NAV-composition tree, RLS-scoped via the per-request anon client.
 * `asOf` is an ISO date string (YYYY-MM-DD) — passed explicitly (not left to the fn default) so
 * the composition foots to the §2.1.1 headline's fn_compute_nav(asOf, true) by construction.
 * Fail-soft: any error (read failure, unexpected null) degrades to `null` — logged, never thrown.
 */
export async function loadNavComposition(
	supabase: SupabaseClient,
	asOf: string
): Promise<NavComposition | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_nav_composition', { p_as_of: asOf });

	if (error) {
		console.error('[navComposition] fn_nav_composition failed:', error.message);
		return null;
	}

	// Scalar jsonb RPC → the parsed object directly. A null/undefined payload is not an expected
	// state (the fn always returns a well-formed tree) — degrade rather than assert a shape.
	if (data === null || data === undefined) {
		console.error('[navComposition] fn returned no jsonb payload; degrading to null');
		return null;
	}

	return data as NavComposition;
}
