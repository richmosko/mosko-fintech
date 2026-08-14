// nav-composition.ts — browser-safe types + presentation helpers for the §2.1.5
// NAV-composition table (SELF-226 · V1.1 "Net worth full").
//
// NON-server module (ships to the browser). It is the single browser-side definition of the
// payload shape returned by the Architect's `fn_nav_composition` (migration 051), which Backend
// threads through the `+page.server.ts` loader as `data.composition`. NavCompositionTable.svelte
// stays purely presentational over these types + the buildup-ladder ordering here.
//
// CONTRACT (051 JSONB-SHAPE / A4 — F/CTO-ratified 2026-08-02):
//   { groups: [ { category, accounts: [ { account_id, account_name,
//                 current_market_value, unrealized_gl } ], subtotal } ],
//     buildups: { total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab },
//     nav }
//
// RATIFIED QUIRKS designed-around:
//   • Empty categories are OMITTED from groups[] (a 0-active-account category simply is absent) —
//     the table just doesn't render them (ratified D3; no "0 accounts" affordance).
//   • `buildups.debt` is a POSITIVE MAGNITUDE; the liability leaf `current_market_value` + the
//     liability group `subtotal` carry 049's NATURAL-NEGATIVE sign. The Debt ladder row therefore
//     renders the magnitude as a SUBTRACTION (−debt) so `nav = gross_total − debt` reads literally
//     (ratified D5). buildupRows() below owns that single sign flip.
//   • `unrealized_gl` is NULL for non-investment accounts → rendered as `—` (AC#3).
//   • Tax placeholders are 0 in V1.1 (Option A / ratify record A5) → rendered `$0` + a V1.4 caption
//     (ratified D7/D8; the wireframe "incomplete-NAV" state is deferred to V1.4, not built here).
//   • `nav` foots EXACT to the §2.1.1 headline (051 FOOT-TO-NAV) — rendered whole-dollar to match
//     the headline so the foot reads identical to it (ratified D9).
//
// Per-row STALENESS (SELF-229, ratified D4) is modelled as `NavCompositionLeaf.is_stale` below.
// The 051 JSONB itself still carries none of this — the loader computes it via a server-side
// linked_source_id↔account_id join over `pfin.account` and attaches it per leaf before this
// shape ever reaches the browser (see api/src/lib/server/queries/navComposition.ts). ADR-013 D1:
// the staleness-marking surface list at PRD §2.4.4 is illustrative-not-exhaustive; further
// surfaces ramp at V1.2-V1.5 milestones (§2.2/§2.3/§2.5/§2.6).
//
// is_stale IS TRI-STATE (boolean | null), not a plain boolean — see the field's own doc comment.
// This is a REWORK: the first cut collapsed a join-query failure to `false`, which is the exact
// silent-fresh-on-failure shape SELF-220 Sec round 2 rejected on the chart. Render `null` as an
// explicit "staleness unknown" state on the affected row — NEVER as "confirmed not stale."

/** One account leaf row — mirrors a 051 groups[].accounts[] element. */
export interface NavCompositionLeaf {
	/** pfin.account PK. Typed loosely (number | string) for a safe href coercion, mirroring
	 *  StaleConstituentItem.linked_source_id — never re-derived from it. */
	account_id: number | string;
	account_name: string;
	current_market_value: number;
	/** NULL for non-investment accounts (straight from 049). */
	unrealized_gl: number | null;
	/**
	 * SELF-229 (ratified D4): TRI-STATE.
	 *   true  = this leaf's owning `pfin.account.linked_source_id` IS currently in the caller's
	 *           `046` stale_items[].
	 *   false = CONFIRMED not stale (join succeeded; not in that set, or a manual/unlinked account).
	 *   null  = UNKNOWN — the server-side join couldn't run. Render an explicit "staleness unknown"
	 *           affordance, never treat this the same as `false` (SELF-220 precedent).
	 */
	is_stale: boolean | null;
}

/** One category group — mirrors a 051 groups[] element. Empty categories are omitted upstream. */
export interface NavCompositionGroup {
	/** The account_type discriminator (depository | investment | retirement | crypto |
	 *  manual_other | real_estate | liability) — display label via account-display.ts. */
	category: string;
	accounts: NavCompositionLeaf[];
	/** Σ of the group's leaf current_market_value (liability groups are naturally negative). */
	subtotal: number;
}

/** The buildup ladder magnitudes — mirrors 051 buildups. `debt` is a POSITIVE magnitude. */
export interface NavCompositionBuildups {
	total_non_re: number;
	gross_total: number;
	debt: number;
	realized_tax_liab: number;
	unrealized_tax_liab: number;
}

/** The full §2.1.5 composition payload — mirrors the 051 top-level JSONB. */
export interface NavComposition {
	groups: NavCompositionGroup[];
	buildups: NavCompositionBuildups;
	nav: number;
}

/** A single rendered buildup-ladder row (excludes the NAV foot, rendered separately). */
export interface BuildupRow {
	key: string;
	label: string;
	/** Value already sign-adjusted for the ladder: Debt is shown as a subtraction (−magnitude). */
	displayValue: number;
	/** Tax placeholders render `$0` + the V1.4 caption (AC#6 / ratified D7). */
	isTaxPlaceholder: boolean;
}

/**
 * The buildup ladder in the EXACT ratified order (AC#4):
 *   Total Non-RE → Gross Total → Debt → Realized Tax Liab → Unrealized Tax Liab.
 * (NAV is the foot row, rendered separately by the component.)
 *
 * Debt is the ONLY sign flip: `buildups.debt` arrives as a positive magnitude and the ladder
 * subtracts it, so displayValue = −debt (D5). Tax rows are flagged placeholders (value 0, V1.4).
 */
export function buildupRows(b: NavCompositionBuildups): BuildupRow[] {
	return [
		{ key: 'total_non_re', label: 'Total Non-RE', displayValue: b.total_non_re, isTaxPlaceholder: false },
		{ key: 'gross_total', label: 'Gross Total', displayValue: b.gross_total, isTaxPlaceholder: false },
		// buildups.debt is a positive magnitude; the ladder subtracts it (D5).
		{ key: 'debt', label: 'Debt', displayValue: -b.debt, isTaxPlaceholder: false },
		{ key: 'realized_tax_liab', label: 'Realized Tax Liab', displayValue: b.realized_tax_liab, isTaxPlaceholder: true },
		{ key: 'unrealized_tax_liab', label: 'Unrealized Tax Liab', displayValue: b.unrealized_tax_liab, isTaxPlaceholder: true }
	];
}
