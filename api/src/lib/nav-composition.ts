// nav-composition.ts — browser-safe types + presentation helpers for the §2.1.5
// NAV-composition table (SELF-226 · V1.1 "Net worth full").
//
// NON-server module (ships to the browser). It is the single browser-side definition of the
// payload shape returned by the Architect's `fn_nav_composition` (migration 051), which Backend
// threads through the `+page.server.ts` loader as `data.composition`. NavCompositionTable.svelte
// stays purely presentational over these types + the buildup-ladder ordering here.
//
// CONTRACT (051 JSONB-SHAPE / A4 — F/CTO-ratified 2026-08-02; V1.4 FLIP — SELF-268,
// sitting-log R3 (A′) + team-lead's E41 ruling, migration 105 — real tax ENVELOPES replace the
// two 0::numeric literals, and the leaf set excludes tax-authority-designated accounts, AC 3a):
//   { groups: [ { category, accounts: [ { account_id, account_name,
//                 current_market_value, unrealized_gl } ], subtotal } ],
//     buildups: { total_non_re, gross_total, debt,
//                 realized_tax_liab: {status,amount?,reason?}, unrealized_tax_liab: {status,amount?,reason?} },
//     nav,
//     excluded_tax_ledgers? }         <- SELF-268 EXPECTED, see below
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
// SELF-268 FLIP (R3 riders 0 / 3a / 7; AC 2 / AC 7) — E41 RULED SHAPE (team-lead, supersedes an
// earlier draft of this header that typed the two scalars as plain numbers plus a separate
// `tax_components` sidecar): the V1.1 tax-placeholder shape (`isTaxPlaceholder`, rendered `$0` + a
// "V1.4 ramp" caption) is REMOVED, and `buildups.realized_tax_liab` / `unrealized_tax_liab`
// THEMSELVES BECOME ENVELOPE OBJECTS — `{status:'computed', amount} | {status:'unavailable',
// reason}` — verbatim 104's own `nav_components` shape, no separate availability sidecar. `amount`
// is sourced from SELF-262's `pfin.fn_compute_tax_liability` (104), composed into 051/105 at read
// time (one composed reader — rider 0). ⚠ SIGN (AC 7 / M-3): a computed `amount` arrives as a
// POSITIVE magnitude (like `debt`) and is rendered UNFLIPPED — `debt` stays the ladder's ONLY
// negation. The instinct to mirror Debt's `−magnitude` treatment here is exactly the
// double-negation defect Sec's M-3 names: 105's own `nav` expression already subtracts it (as 0 on
// an unavailable envelope — 105 cannot subtract a JSON null), so a second flip here would render a
// correct value with the wrong sign. See buildupRows()'s own comment + its test for the regression
// this guards. NEVER read an unavailable envelope's implicit 0-for-arithmetic as a determination —
// the envelope's `status` is the ONLY place "genuinely zero" and "unavailable, arithmetic-only 0"
// are told apart, and buildupRows() below routes an unavailable envelope to a NO-`displayValue`
// row variant so there is no numeric field to accidentally render as `$0` (a type-level guard, not
// merely a runtime check).
//
// SELF-268 NAV-FOOT THREE-STATE BASIS (Sec P-5 / option (C), team-lead relay) — the two envelopes
// are INDEPENDENT and can disagree, so the composed NAV has THREE possible bases, never a single
// tax-adjusted/pre-tax boolean: (1) 'tax-adjusted' — both computed; (2) 'partial' — exactly one
// envelope unavailable, NAV reads pre-tax for THAT line only until it resolves (e.g. a ledger gets
// designated); (3) 'unadjusted' — both unavailable, NAV reads fully pre-tax. `navFootBasis()` /
// `navFootLabel()` below compute this from `buildups` directly (no separate boolean anywhere), and
// the §2.1.5 foot's OWN label carries it (Sec: not a caption beside the table) — see
// NavCompositionTable.svelte. The §2.1.1 headline reads the same composed value and states the
// same basis in short form (see +page.svelte / navHeadlineBasisNote()) plus the fact that the
// trend chart is gross pre-tax (AC 4a). ⚠ Citation note (Sec D-1): AC 10a's original "rendered, not
// just applied" framing cited ADR-049 — a RETRACTED ATTRIBUTION (E36). The correct cite for
// "an exclusion correct in the arithmetic and invisible in the copy is not fully shipped" is PRD
// §2.4.4 / ADR-013's non-silent-staleness posture, never ADR-049 — used that way throughout this
// file and NavCompositionTable.svelte.
//
// SELF-268 EXPECTED CONTRACT (PROVISIONAL — migration 105 not yet on the tree as of this build;
// Architect-268 is landing it in parallel). `excluded_tax_ledgers` (AC 10a / R3 riders 0b + 6) is
// typed defensively OPTIONAL/nullable below so this component degrades to "not rendered" rather
// than crashing if 105 lands without it yet — confirm the exact key with Architect/Backend before
// relying on it in a way that would break silently. It names the accounts AC 3a's exclusion
// removed from the leaf set, so the §2.1.5 surface can name them (rendering the exclusion is what
// makes an UNMARKED tax-authority account visible as "not excluded" — rider 0b's default-state
// failure has no other observer, PRD §2.4.4 / ADR-013, never ADR-049). If 105 does not emit this,
// the table renders NOTHING for it (never a fabricated "no exclusions" claim from a second query)
// — this is a real payload gap to close, not a rendering choice, and NavCompositionTable.svelte
// says so at its own use site. Frontend needs this field ON THE SAME `composition` object the
// component already receives as a prop — whether 105's JSONB emits it directly or Backend's
// loader augments the composed object with it is immaterial to this file; either lands on
// `NavComposition.excluded_tax_ledgers`.
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

/** One tax scalar's envelope (SELF-268 E41 — verbatim 104's own `nav_components` shape). A
 * discriminated union rather than "{status, amount?, reason?}" with both optional: TypeScript then
 * makes `amount` genuinely unreachable on the `unavailable` branch, so there is no field left to
 * accidentally format as `$0`. `reason` is a stable machine code (104's vocabulary:
 * no_schedule_any_year / ytd_paid_unavailable / no_ledger_designated / …), never prose — copy is
 * the surface's, same convention as 104. */
export type TaxLineEnvelope = { status: 'computed'; amount: number } | { status: 'unavailable'; reason: string };

/** The buildup ladder magnitudes — mirrors 051/105 buildups (E41 shape). `debt` is a POSITIVE
 * magnitude (AC 7 / M-3, unchanged). `realized_tax_liab` / `unrealized_tax_liab` are now ENVELOPES,
 * not plain numbers — a computed envelope's `.amount` is likewise a POSITIVE magnitude, never
 * pre-negated here. */
export interface NavCompositionBuildups {
	total_non_re: number;
	gross_total: number;
	debt: number;
	realized_tax_liab: TaxLineEnvelope;
	unrealized_tax_liab: TaxLineEnvelope;
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
	/** Already net of 0 for any unavailable tax line (105 cannot subtract a JSON null) — this
	 * field alone cannot distinguish "fully tax-adjusted" from "partial" from "unadjusted"; read
	 * `navFootBasis(buildups)` for that (Sec P-5 / option (C)). */
	nav: number;
	/** SELF-268 AC 10a EXPECTED CONTRACT — PROVISIONAL (optional/nullable: absent until 105
	 * confirms the key). See module header. */
	excluded_tax_ledgers?: ExcludedTaxLedger[] | null;
}

/** A single rendered buildup-ladder row (excludes the NAV foot, rendered separately). The two tax
 * rows are a DIFFERENT variant from the three plain-amount rows — no `displayValue` field exists
 * on the `unavailable` variant, so there is nothing to accidentally format as `$0` (AC 6 / Sec:
 * never a silent zero). */
export type BuildupRow =
	| { key: 'total_non_re' | 'gross_total' | 'debt'; label: string; displayValue: number }
	| { key: 'realized_tax_liab' | 'unrealized_tax_liab'; label: string; status: 'computed'; displayValue: number }
	| { key: 'realized_tax_liab' | 'unrealized_tax_liab'; label: string; status: 'unavailable'; reason: string };

function taxRow(key: 'realized_tax_liab' | 'unrealized_tax_liab', label: string, envelope: TaxLineEnvelope): BuildupRow {
	// SELF-268 AC 7 / M-3: a computed envelope's `amount` is a positive magnitude, rendered
	// UNFLIPPED here — NO second negation (105's own `nav` arithmetic already subtracts it).
	if (envelope.status === 'computed') {
		return { key, label, status: 'computed', displayValue: envelope.amount };
	}
	return { key, label, status: 'unavailable', reason: envelope.reason };
}

/**
 * The buildup ladder in the EXACT ratified order (AC#4):
 *   Total Non-RE → Gross Total → Debt → Realized Tax Liab → Unrealized Tax Liab.
 * (NAV is the foot row, rendered separately by the component.)
 *
 * Debt is the ladder's ONLY sign flip (D5 / SELF-268 AC 7 / M-3): `buildups.debt` arrives as a
 * positive magnitude and the ladder subtracts it, so displayValue = −debt. A computed tax
 * envelope's `amount` also arrives as a positive magnitude but is rendered UNFLIPPED — 105's own
 * `nav` arithmetic already subtracts it, so negating it here a second time would render a correct
 * value with the wrong sign (the double-negation defect Sec's M-3 names). See
 * nav-composition.test.ts's "exactly one flip" regression. An unavailable envelope routes to the
 * NO-`displayValue` row variant (see BuildupRow) — the component renders its `reason`, never a
 * fabricated `$0`.
 */
export function buildupRows(b: NavCompositionBuildups): BuildupRow[] {
	return [
		{ key: 'total_non_re', label: 'Total Non-RE', displayValue: b.total_non_re },
		{ key: 'gross_total', label: 'Gross Total', displayValue: b.gross_total },
		// buildups.debt is a positive magnitude; the ladder subtracts it (D5).
		{ key: 'debt', label: 'Debt', displayValue: -b.debt },
		taxRow('realized_tax_liab', 'Realized Tax Liab', b.realized_tax_liab),
		taxRow('unrealized_tax_liab', 'Unrealized Tax Liab', b.unrealized_tax_liab)
	];
}

// ============================================================================
// SELF-268 NAV-FOOT / HEADLINE THREE-STATE BASIS (Sec P-5 / option (C)) — the two tax envelopes
// are independent and can disagree, so the composed NAV has THREE possible bases. The §2.1.5
// foot's OWN label carries this (never a caption beside the table, never a single boolean); the
// §2.1.1 headline states the same basis in short form (see +page.svelte). PRD §2.4.4 / ADR-013 is
// the citation for "state visibly, never silently" here — NEVER ADR-049 (Sec D-1: a retracted
// attribution, E36).
// ============================================================================

/** The composed NAV's tax-adjustment basis, derived from the two envelopes — never a boolean. */
export type NavFootBasis =
	| { state: 'tax-adjusted' }
	| { state: 'unadjusted' }
	| { state: 'partial'; unavailableLine: 'realized' | 'unrealized'; reason: string };

export function navFootBasis(b: NavCompositionBuildups): NavFootBasis {
	const r = b.realized_tax_liab;
	const u = b.unrealized_tax_liab;
	if (r.status === 'computed' && u.status === 'computed') return { state: 'tax-adjusted' };
	if (r.status === 'unavailable' && u.status === 'unavailable') return { state: 'unadjusted' };
	if (r.status === 'unavailable') return { state: 'partial', unavailableLine: 'realized', reason: r.reason };
	// TypeScript can't see it, but the three branches above are exhaustive for two 2-valued
	// statuses except this one: u.status === 'unavailable' with r.status === 'computed'.
	return { state: 'partial', unavailableLine: 'unrealized', reason: (u as { status: 'unavailable'; reason: string }).reason };
}

// Stable machine `reason` codes (104's vocabulary) → short, ACTION-oriented copy for the partial
// state (Sec's own example: "realized tax not yet deducted — designate a tax-authority ledger").
// Minimal V1.4 wording — UX/PM own the final phrasing (bubble-up); the STRUCTURE (three states,
// never a boolean, the foot's own label carries it) is Sec-mandated and is what's under test.
const UNAVAILABLE_ACTION_COPY: Record<string, string> = {
	no_schedule_any_year: 'add a tax bracket schedule',
	ytd_paid_unavailable: 'designate a tax-authority ledger',
	no_ledger_designated: 'designate a tax-authority ledger'
};
/** Exported so NavCompositionTable.svelte's per-row "Unavailable" cell uses the SAME copy as the
 * foot's label, rather than rendering 104's raw machine code (e.g. `no_ledger_designated`)
 * directly — one mapping, two render sites. */
export function unavailableActionCopy(reason: string): string {
	return UNAVAILABLE_ACTION_COPY[reason] ?? 'see Settings';
}

/** The §2.1.5 NAV foot's OWN label (Sec: not a caption beside the table). */
export function navFootLabel(b: NavCompositionBuildups): string {
	const basis = navFootBasis(b);
	switch (basis.state) {
		case 'tax-adjusted':
			return 'Net Assets Value (tax-adjusted)';
		case 'unadjusted':
			return 'Net Assets Value (pre-tax — tax lines unavailable)';
		case 'partial':
			return `Net Assets Value (${basis.unavailableLine} tax not yet deducted — ${unavailableActionCopy(basis.reason)})`;
	}
}

/** A short-form basis note for the §2.1.1 headline (Sec item 3): the same three-state basis, plus
 * the AC 4a fact that the trend chart is a different, permanently-gross basis. Visible-without-hover
 * per this codebase's house discipline (§2.4.4 / ADR-013) — never a `title` attribute alone. */
export function navHeadlineBasisNote(b: NavCompositionBuildups): string {
	const basis = navFootBasis(b);
	const taxPart = (() => {
		switch (basis.state) {
			case 'tax-adjusted':
				return 'tax-adjusted';
			case 'unadjusted':
				return 'pre-tax — tax lines unavailable';
			case 'partial':
				return `${basis.unavailableLine} tax not yet deducted`;
		}
	})();
	return `${taxPart}; the trend chart below is gross, before tax.`;
}
