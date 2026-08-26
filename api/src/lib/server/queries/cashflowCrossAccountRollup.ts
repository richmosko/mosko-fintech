// cashflowCrossAccountRollup.ts — server-side read for the §2.3.2 cross-account multi-period
// cash-flow rollup (SELF-250). Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's `093` pfin.fn_cashflow_cross_account_rollup(p_as_of date) — a SECURITY
// INVOKER read-composition helper (Lock 11; prosecdef=f) that composes on `093`'s own
// pfin.fn_cashflow_items(p_as_of), which reads pfin.account_trans / account_trans_annotation /
// account_trans_split (RLS-gated on pfin.account_users.rd_access under auth.uid()) and
// pfin.posting_prototype / pfin.cashflow_target (RLS-gated on users_id = auth.uid()) — through
// the per-request anon/authenticated client, exactly the same client netWorth.ts / navComposition.ts
// / nav-delta-panel.ts already use, so the caller's RLS context propagates. NEVER service_role
// (RT-26 / Lock 11). A cross-tenant caller reads zero rows at every leg and fails closed.
//
// `p_as_of` is threaded, NOT defaulted. Mirrors `netWorth.ts` / `navComposition.ts` / the §2.2
// allocation loaders' own discipline (ADR-044 D2, "resolve D once per request, thread everywhere")
// — the caller resolves `asOf` ONCE, from `serverTodayAsOf()` (or, once a client-supplied as-of
// is wired at SELF-253/D-1, from `resolveAllocationAsOf`'s sibling factory), and passes the SAME
// value here and to the S-2 banner count this function's own `unclassified.count_ytd` already is
// — never a second, independently-defaulted call. `093`'s own header states the hazard this
// guards: two PostgREST requests each defaulting `p_as_of` independently can straddle midnight and
// disagree. NO `new Date()` ANYWHERE IN THIS FILE — that is a second, uncoordinated clock.
//
// `093` RETURNS jsonb (a SCALAR jsonb, NOT set-returning) — supabase-js hands the parsed object
// straight back (same contract navComposition.ts's own header documents for `051`; contrast
// staleness.ts / nav-delta-panel.ts, whose RPCs are set-returning -> row array).
//
// AC5 — SECTION LABELS. `093` emits RAW `cat` values only (`'Revenue'` / `'Expense'`) — it is
// SHAPING ONLY and deliberately carries no product-label knowledge (093's own header: "mapping
// them to user-facing captions is an APP-side concern"). This loader attaches the product label
// via `cashflowSectionLabel` (cashflowSections.ts, the shared §2.3 vocabulary module SELF-253's
// drill-down also consumes) — labels are NEVER typed inline here, only looked up. `093`'s
// `sections` array is hard-restricted to `('Revenue','Expense')` in this order, so `sectionKey`
// resolves to `'income'` / `'expenses'` for every row this function can ever emit; `undefined` is
// structurally unreachable today and is handled by falling back to the raw `cat` rather than
// throwing (a fail-soft posture, consistent with every other degrade in this file, over a defect
// this function did not cause).
//
// AC6 — TARGETS. `093`'s own header: row-absent (`pfin.cashflow_target` has no row for this
// tenant) and one-row-of-NULLs (a row exists, both target columns are NULL under the SELF-246
// always-NULL-never-DELETE ruling) are COLLAPSED AT THE SQL LAYER into the identical two-key
// object `{ income_target_annual: null, expense_target_monthly: null }` — a scalar subquery over
// zero rows yields NULL, the same NULL a one-row-of-NULLs subquery yields. `CashflowTargets`
// below has NO row-presence field for exactly that reason: the type cannot represent a
// distinction the data never carries. This file additionally coalesces a missing `targets` key
// on the raw payload itself (see `normalize` below) — defense-in-depth against a malformed or
// future-narrowed RPC response, not a state `093` can currently produce, so a caller can never
// receive `undefined` and branch on presence instead of on the two NULL-able fields.
//
// AC8 — DEGENERATE STATES. Passed through UNCHANGED, never re-derived: a period cell is `null`
// (renders em-dash — the quarter has not started relative to `asOf`) or a real number including
// `0` (a real answer — the quarter started and had no net activity); `unclassified.count_ytd` is
// the S-2 banner's `N`, from the SAME query as every sum (093's own contract), so the banner and
// the totals cannot drift. This file performs NO arithmetic on any of these values — coalescing
// any period cell here would silently re-collapse the exact NULL/0 distinction `093` computes.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { cashflowSectionKey, cashflowSectionLabel, type CashflowSectionKey } from './cashflowSections';

/** One (cat, sub_cat) row inside a section — raw amounts from `093`, unmodified. */
export type CashflowSectionRow = {
	sub_cat: string;
	/** Always a real number (never null) — the current month is, by construction, always started
	 *  relative to `asOf` (093's `bounds.month_start <= p_as_of` always holds for the CONTAINING
	 *  month). `0` is a real answer (no activity this month), never an em-dash state. */
	month: number;
	/** `null` = this quarter has not started relative to `asOf` (renders em-dash); a number
	 *  (including `0`) = the quarter has started (`0` = started, no activity — a real answer). */
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	/** Always a real number — YTD is, by construction, always "started" as of `asOf`. */
	ytd: number;
};

/** The per-section Total — same period-cell semantics as `CashflowSectionRow` above, summed DOWN
 *  each column independently (093's own header: the period columns overlap, so a total is never a
 *  cross-column sum). Present even for a section with zero rows (`093`'s `coalesce(sum(...), 0)`
 *  / `coalesce(..., null)` per column). */
export type CashflowSectionTotal = {
	month: number;
	q1: number | null;
	q2: number | null;
	q3: number | null;
	q4: number | null;
	ytd: number;
};

/** One §2.3.2 section. `cat` is the RAW ratified-vocabulary value `093` emits (`'Revenue'` /
 *  `'Expense'`); `sectionKey` / `label` are attached HERE from the shared `cashflowSections.ts`
 *  module (AC5) — a consumer renders `label` and never re-derives it from `cat`. */
export type CashflowSection = {
	cat: string;
	sectionKey: CashflowSectionKey | undefined;
	label: string;
	rows: CashflowSectionRow[];
	total: CashflowSectionTotal;
};

/** AC6: NO row-presence field, deliberately — see the module header. Both reachable underlying
 *  states (`pfin.cashflow_target` row-absent vs. one-row-of-NULLs) arrive here as this SAME
 *  shape; a caller that only handles one has diverged from the data, not from this type. */
export type CashflowTargets = {
	income_target_annual: number | null;
	expense_target_monthly: number | null;
};

/** AC8: the S-2 banner's `N`, scoped to the rendered year (093's own `in_ytd` filter) — from the
 *  SAME query as every sum above, so the banner and the totals cannot drift apart. */
export type CashflowUnclassified = {
	count_ytd: number;
};

/** The full §2.3.2 rollup — the typed, section-labelled shape of `093`'s jsonb return. */
export type CashflowCrossAccountRollup = {
	as_of: string;
	sections: CashflowSection[];
	targets: CashflowTargets;
	unclassified: CashflowUnclassified;
};

/** Raw shape as it arrives from the RPC — `093`'s jsonb, before section labels are attached. */
type RawCashflowSection = {
	cat: string;
	rows: CashflowSectionRow[];
	total: CashflowSectionTotal;
};
type RawCashflowRollup = {
	as_of: string;
	sections: RawCashflowSection[];
	targets: CashflowTargets | null | undefined;
	unclassified: CashflowUnclassified | null | undefined;
};

/** Attaches AC5 section labels and defensively coalesces `targets` / `unclassified` (AC6 /
 *  AC8) so this function's return type is unconditionally well-formed even if a future `093`
 *  revision ever narrowed the payload — `093`'s CURRENT contract already guarantees both keys,
 *  so this coalesce is defense-in-depth, not a state this function has ever observed. */
function normalize(raw: RawCashflowRollup): CashflowCrossAccountRollup {
	return {
		as_of: raw.as_of,
		sections: raw.sections.map((section) => ({
			cat: section.cat,
			sectionKey: cashflowSectionKey(section.cat),
			// Fall back to the raw `cat` only in the structurally-unreachable case where a future
			// 093 revision emits a class this loader's shared vocabulary hasn't caught up with yet
			// (see the AC5 note above) — never throw over a label gap.
			label: cashflowSectionLabel(section.cat) ?? section.cat,
			rows: section.rows,
			total: section.total
		})),
		targets: raw.targets ?? { income_target_annual: null, expense_target_monthly: null },
		unclassified: raw.unclassified ?? { count_ytd: 0 }
	};
}

/**
 * Load the caller's §2.3.2 cross-account multi-period cash-flow rollup, RLS-scoped via the
 * per-request anon/authenticated client. `asOf` is threaded explicitly — see the module header
 * for why this must be the SAME resolved value the caller's S-2 banner and any sibling §2.3
 * surface on the same request use.
 *
 * Fail-soft on any read error (network, RPC failure, wrong-shaped payload): degrades to `null` —
 * logged server-side, never thrown. Mirrors every other §2.1/§2.2 loader's posture
 * (netWorth.ts / navComposition.ts / nav-delta-panel.ts) — a rollup-read failure must not throw
 * through to the route.
 */
export async function loadCashflowCrossAccountRollup(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<CashflowCrossAccountRollup | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_cashflow_cross_account_rollup', { p_as_of: asOf });

	if (error) {
		console.error('[cashflowCrossAccountRollup] fn_cashflow_cross_account_rollup failed:', error.message);
		return null;
	}

	// Scalar jsonb RPC -> the parsed object directly, same contract navComposition.ts documents
	// for `051`. A null/undefined payload is not an expected state (093 always returns a
	// well-formed document, even for a zero-activity tenant) — degrade rather than assert a shape.
	if (data === null || data === undefined) {
		console.error('[cashflowCrossAccountRollup] fn returned no jsonb payload; degrading to null');
		return null;
	}

	return normalize(data as RawCashflowRollup);
}
