// nav-composition.ts — browser-safe types + presentation helpers for the §2.1.5
// NAV-composition table (SELF-226 · V1.1 "Net worth full").
//
// NON-server module (ships to the browser). It is the single browser-side definition of the
// payload shape returned by the Architect's `fn_nav_composition` (migration 051), which Backend
// threads through the `+page.server.ts` loader as `data.composition`. NavCompositionTable.svelte
// stays purely presentational over these types + the buildup-ladder ordering here.
//
// CONTRACT (051 JSONB-SHAPE / A4 — F/CTO-ratified 2026-08-02; V1.4 FLIP — SELF-268,
// sitting-log R3 (A′), migration 105 — real tax scalars replace the two 0::numeric
// literals, and the leaf set excludes tax-authority-designated accounts, AC 3a):
//   { groups: [ { category, accounts: [ { account_id, account_name,
//                 current_market_value, unrealized_gl } ], subtotal } ],
//     buildups: { total_non_re, gross_total, debt, realized_tax_liab, unrealized_tax_liab },
//     nav,
//     tax_components?, excluded_tax_ledgers? }         <- SELF-268 EXPECTED, see below
//
// RATIFIED QUIRKS designed-around:
//   • Empty categories are OMITTED from groups[] (a 0-active-account category simply is absent) —
//     the table just doesn't render them (ratified D3; no "0 accounts" affordance).
//   • `buildups.debt` is a POSITIVE MAGNITUDE; the liability leaf `current_market_value` + the
//     liability group `subtotal` carry 049's NATURAL-NEGATIVE sign. The Debt ladder row therefore
//     renders the magnitude as a SUBTRACTION (−debt) so `nav = gross_total − debt` reads literally
//     (ratified D5). buildupRows() below owns that single sign flip.
//   • `unrealized_gl` is NULL for non-investment accounts → rendered as `—` (AC#3).
//   • `nav` foots EXACT to the §2.1.1 headline (051 FOOT-TO-NAV) — rendered whole-dollar to match
//     the headline so the foot reads identical to it (ratified D9).
//
// SELF-268 FLIP (R3 riders 0 / 3a / 7; AC 2 / AC 7): the V1.1 tax-placeholder shape
// (`isTaxPlaceholder`, rendered `$0` + a "V1.4 ramp" caption) is REMOVED. `buildups.realized_tax_liab`
// / `unrealized_tax_liab` now carry REAL values sourced from SELF-262's
// `pfin.fn_compute_tax_liability` (104) `nav_components` scalars, composed into 051/105 at read
// time (one composed reader — rider 0). ⚠ SIGN (AC 7 / M-3): both arrive as POSITIVE magnitudes
// (like `debt`) and are rendered UNFLIPPED — `debt` stays the ladder's ONLY negation. The instinct
// to mirror Debt's `−magnitude` treatment here is exactly the double-negation defect Sec's M-3
// names: 105's own `nav` expression already subtracts them, so a second flip here would render a
// correct value with the wrong sign. See buildupRows()'s own comment + its test for the regression
// this guards.
//
// SELF-268 EXPECTED CONTRACT (PROVISIONAL — migration 105 not yet on the tree as of this build;
// Architect-268 is landing it in parallel). Two payload additions are anticipated and typed
// defensively OPTIONAL/nullable below so this component degrades to "not rendered" rather than
// crashing if 105 lands without one of them — confirm the exact keys with Architect/Backend
// before relying on either in a way that would break silently:
//   (1) `tax_components` (AC 6 / E26 ruling 1) — an availability envelope per tax scalar, mirroring
//       104's own `nav_components` shape ({status:'computed'} | {status:'unavailable',reason}).
//       105 cannot subtract a JSON null inside its `nav` arithmetic, so on an unavailable scalar
//       105 subtracts 0 there — `tax_components` is the ONLY place that fact is visible; a consumer
//       reading `buildups.*_tax_liab` alone cannot tell "genuinely zero" from "unavailable, rendered
//       as zero for the arithmetic" apart. NEVER render `buildups.realized_tax_liab === 0` as a
//       determination when `tax_components` says unavailable (D1-shaped: mark, never silently drop).
//       This is Architect's Option (A) (NAV shown pre-tax + copy) built ahead of the ruling between
//       (A) and (B) NAV NULL — team-lead is forwarding the ruling; (A)'s typed shape is additive and
//       degrades to a no-op render if (B) is taken instead.
//   (2) `excluded_tax_ledgers` (AC 10a / R3 riders 0b + 6) — the accounts AC 3a's exclusion removed
//       from the leaf set, so the §2.1.5 surface can name them (rendering the exclusion is what makes
//       an UNMARKED tax-authority account visible as "not excluded" — rider 0b's default-state
//       failure has no other observer). If 105 does not emit this, the table renders NOTHING for it
//       (never a fabricated "no exclusions" claim from a second query) — this is a real payload gap
//       to close, not a rendering choice, and NavCompositionTable.svelte says so at its own use site.
//
// Per-row STALENESS (SELF-229, ratified D4) is modelled as `NavCompositionLeaf.is_stale` below.
// The 051 JSONB itself still carries none of this — the loader computes it via a server-side
// linked_source_id↔account_id join over `pfin.account` and attaches it per leaf before this
// shape ever reaches the browser (see api/src/lib/server/queries/navComposition.ts). Per ADR-013
// D1 (staleness-marking surface scope is illustrative, not exhaustive), further surfaces ramp
// later — Sec F4 (AMBER round): this is a PARAPHRASE, not D1's own wording; read D1 live rather
// than treating this line as a quote.
//
// is_stale IS TRI-STATE (boolean | null), not a plain boolean — see the field's own doc comment.
// This is a REWORK (F/CTO-ruled, mirrors SELF-220 Sec round 2): the first cut collapsed a
// failure to `false`, which is the exact silent-fresh-on-failure shape Sec rejected on the chart.
// TWO independent things can produce `null` — the root `046` staleness read itself being unknown,
// or just this table's own per-row join failing — both degrade every leaf together. Render `null`
// as an explicit "staleness unknown" state on the affected row — NEVER as "confirmed not stale."

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
	 *   false = CONFIRMED not stale (a KNOWN root read + a successful join; not in that set, or a
	 *           manual/unlinked account).
	 *   null  = UNKNOWN — either the root `046` staleness read failed, or the server-side join
	 *           couldn't run. Render an explicit "staleness unknown" affordance, never treat this
	 *           the same as `false`.
	 * Computed server-side in the loader — NOT a change to 051 — and threaded straight through as
	 * this field. This is the PER-ROW signal (AC4) — distinct from and additional to the rollup
	 * `<StaleConstituentBadge>` the page renders off `data.staleness` directly; both are shown
	 * together (neither replaces the other).
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

/** The buildup ladder magnitudes — mirrors 051/105 buildups. `debt`, `realized_tax_liab` and
 * `unrealized_tax_liab` are all POSITIVE magnitudes (AC 7 / M-3) — none are pre-negated here. */
export interface NavCompositionBuildups {
	total_non_re: number;
	gross_total: number;
	debt: number;
	realized_tax_liab: number;
	unrealized_tax_liab: number;
}

/** One tax-scalar's availability (SELF-268 AC 6 EXPECTED CONTRACT — see module header).
 * Mirrors 104's own `nav_components` envelope shape ({status:'computed'} | {status:'unavailable',
 * reason}), minus `amount` (the amount already lives in `buildups.*_tax_liab`). `reason` is a
 * stable machine code (104's vocabulary: no_schedule_any_year / ytd_paid_unavailable / …), never
 * prose — copy is the surface's, same convention as 104. */
export type TaxComponentStatus = { status: 'computed' } | { status: 'unavailable'; reason: string };

/** SELF-268 AC 6 EXPECTED CONTRACT — PROVISIONAL, see module header. Optional/nullable so a 105
 * that does not (yet) emit this degrades to "no availability notice rendered," never a crash and
 * never a fabricated determination. */
export interface NavTaxComponents {
	realized_tax_liab: TaxComponentStatus;
	unrealized_tax_liab: TaxComponentStatus;
}

/** One account excluded from the buildup leaf set under AC 3a (SELF-268 AC 10a EXPECTED CONTRACT
 * — PROVISIONAL, see module header). */
export interface ExcludedTaxLedger {
	account_id: number | string;
	account_name: string;
}

/** The full §2.1.5 composition payload — mirrors the 051/105 top-level JSONB. */
export interface NavComposition {
	groups: NavCompositionGroup[];
	buildups: NavCompositionBuildups;
	nav: number;
	/** SELF-268 AC 6 EXPECTED CONTRACT — PROVISIONAL (optional/nullable: absent until 105 confirms
	 * the key). See module header. */
	tax_components?: NavTaxComponents | null;
	/** SELF-268 AC 10a EXPECTED CONTRACT — PROVISIONAL (optional/nullable: absent until 105
	 * confirms the key). See module header. */
	excluded_tax_ledgers?: ExcludedTaxLedger[] | null;
}

/** A single rendered buildup-ladder row (excludes the NAV foot, rendered separately). */
export interface BuildupRow {
	key: string;
	label: string;
	/** Value already sign-adjusted for the ladder: Debt is shown as a subtraction (−magnitude);
	 * the two tax rows are rendered UNFLIPPED (AC 7 / M-3 — see module header). */
	displayValue: number;
}

/**
 * The buildup ladder in the EXACT ratified order (AC#4):
 *   Total Non-RE → Gross Total → Debt → Realized Tax Liab → Unrealized Tax Liab.
 * (NAV is the foot row, rendered separately by the component.)
 *
 * Debt is the ladder's ONLY sign flip (D5 / SELF-268 AC 7 / M-3): `buildups.debt` arrives as a
 * positive magnitude and the ladder subtracts it, so displayValue = −debt. The two tax rows also
 * arrive as positive magnitudes but are rendered UNFLIPPED — 105's own `nav` arithmetic already
 * subtracts them, so negating them here a second time would render a correct value with the wrong
 * sign (the double-negation defect Sec's M-3 names). See nav-composition.test.ts's "exactly one
 * flip" regression.
 */
export function buildupRows(b: NavCompositionBuildups): BuildupRow[] {
	return [
		{ key: 'total_non_re', label: 'Total Non-RE', displayValue: b.total_non_re },
		{ key: 'gross_total', label: 'Gross Total', displayValue: b.gross_total },
		// buildups.debt is a positive magnitude; the ladder subtracts it (D5).
		{ key: 'debt', label: 'Debt', displayValue: -b.debt },
		// SELF-268 AC 7 / M-3: positive magnitudes, rendered UNFLIPPED — NO second negation.
		{ key: 'realized_tax_liab', label: 'Realized Tax Liab', displayValue: b.realized_tax_liab },
		{ key: 'unrealized_tax_liab', label: 'Unrealized Tax Liab', displayValue: b.unrealized_tax_liab }
	];
}
