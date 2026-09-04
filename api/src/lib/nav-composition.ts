// nav-composition.ts — browser-safe types + presentation helpers for the §2.1.5
// NAV-composition table (SELF-226 · V1.1 "Net worth full").
//
// NON-server module (ships to the browser). It is the single browser-side definition of the
// payload shape returned by the Architect's `fn_nav_composition` (migration 051), which Backend
// threads through the `+page.server.ts` loader as `data.composition`. NavCompositionTable.svelte
// stays purely presentational over these types + the buildup-ladder ordering here.
//
// CONTRACT (051 JSONB-SHAPE / A4 — F/CTO-ratified 2026-08-02; V1.4 FLIP — SELF-268, sitting-log R3
// (A′) + E41-E42 + Sec P-18, migration 105 LANDED — real tax ENVELOPES replace the two 0::numeric
// literals, and the leaf set excludes tax-authority-designated accounts, AC 3a):
//   { groups: [ { category, accounts: [ { account_id, account_name,
//                 current_market_value, unrealized_gl } ], subtotal } ],
//     buildups: { total_non_re, gross_total, debt,
//                 realized_tax_liab: {status:'computed',amount}|{status:'unavailable',reason},
//                 unrealized_tax_liab: {status:'computed',amount}|{status:'unavailable',reason} },
//     nav }
// `excluded_tax_ledgers` is NOT part of this JSONB — see the separate note below.
//
// RATIFIED QUIRKS designed-around:
//   • Empty categories are OMITTED from groups[] (a 0-active-account category simply is absent) —
//     the table just doesn't render them (ratified D3; no "0 accounts" affordance).
//   • `buildups.debt` is a POSITIVE MAGNITUDE; the liability leaf `current_market_value` + the
//     liability group `subtotal` carry 049's NATURAL-NEGATIVE sign. The Debt ladder row therefore
//     renders the magnitude as a SUBTRACTION (−debt) so `nav = gross_total − debt` reads literally
//     (ratified D5). buildupRows() below owns this sign flip — SELF-268 (E44) extends the SAME
//     flip site to the two tax rows too; see buildupRows()'s own comment.
//   • `unrealized_gl` is NULL for non-investment accounts → rendered as `—` (AC#3).
//   • `nav` foots EXACT to the §2.1.1 headline (051 FOOT-TO-NAV) — rendered whole-dollar to match
//     the headline so the foot reads identical to it (ratified D9).
//
// SELF-268 FLIP (R3 riders 0 / 3a / 7; AC 2 / AC 7) — E41-E42 RULED SHAPE, Sec P-18: the V1.1
// tax-placeholder shape (`isTaxPlaceholder`, rendered `$0` + a "V1.4 ramp" caption) is REMOVED, and
// `buildups.realized_tax_liab` / `unrealized_tax_liab` THEMSELVES BECOME ENVELOPE OBJECTS — this is
// `TaxLiabilityEnvelope` below, REUSING (not re-spelling) `tax-quarterly.ts`'s shipped
// `FundsDueEnvelope` shape (SELF-264/266) — verbatim 104's own `nav_components` shape, no separate
// availability sidecar. `amount` is sourced from SELF-262's `pfin.fn_compute_tax_liability` (104),
// composed into 105 at read time (one composed reader — rider 0). This IS the canonical browser-side
// home for this type (Sec P-18: "export it from nav-composition.ts and import it server-side, so
// the two modules declare it once") — Backend's `api/src/lib/server/queries/navComposition.ts`
// carries its own local copy as a stopgap with a TODO to import this one instead; not done here
// (outside this role's write boundary).
//
// ⚠ SIGN — SELF-268 RULING UPDATE (team-lead under F/CTO delegation, E44 — Sec freeze F-2 option
// (A), which also closes F-1; supersedes the "rendered UNFLIPPED" convention this comment
// originally described): a computed envelope's raw `amount` STILL carries 104's sign UNCHANGED at
// the `NavCompositionBuildups` / `TaxLiabilityEnvelope` level — nothing at THIS type layer mutates
// it. The negation now happens ONE step later, in the RENDERED ladder row, at the single flip site
// inside taxRow() (~:218–227) — the SAME site that already flips `debt` in buildupRows()
// (~:246–254). That site now negates ALL THREE subtractive rows, not Debt alone: a computed row's
// `displayValue = −amount`. An underpaid realized liability (a POSITIVE `amount`) therefore renders
// as a NEGATIVE displayValue — reduces NAV, reading the same direction as Debt. An OVERPAID one (a
// NEGATIVE `amount`, a genuine receivable) renders as a POSITIVE displayValue — adds back.
// `unrealized_tax_liab.amount` is clamped at zero by 104 (R9 / Sec M-2), always ≥ 0, so its
// displayValue is always ≤ 0. `realized_tax_liab.amount` remains SIGNED and NOT clamped — see
// NavCompositionBuildups's own comment; NEVER abs() or clamp the raw `amount`, here or in taxRow().
// The sign convention stays "exactly one negation in exactly one place" (D5's original invariant,
// 105's header, verbatim in substance) — that ONE place now negates three rows instead of one; a
// SECOND flip site anywhere else in this file or NavCompositionTable.svelte is still the exact
// double-negation / signal-loss defect Sec's M-3 names. See taxRow() / buildupRows()'s own comments
// + nav-composition.test.ts's regressions (including the footing identity) for the arithmetic.
// NEVER read an unavailable envelope's implicit 0-for-arithmetic as a determination — the
// envelope's `status` is the ONLY place "genuinely zero" and "unavailable, arithmetic-only 0" are
// told apart, and buildupRows() below routes an unavailable envelope to a `displayValue: null` row
// variant (Sec P-18: `status` REQUIRED, not optional — an optional status is a prop default away
// from fail-open) so there is no numeric value to accidentally render as `$0` (a type-level guard,
// not merely a runtime check).
//
// SELF-268 NAV-FOOT THREE-STATE BASIS (Sec P-5 / option (C)) — the two envelopes are INDEPENDENT
// and can disagree, so the composed NAV has THREE possible bases, never a single
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
// SELF-268 AC 10a / R3 riders 0b + 6 — `excludedTaxLedgers` (the accounts AC 3a's exclusion removed
// from the leaf set) is NOT part of the `NavComposition` JSONB above — 051/105 doesn't carry this
// list at all (team-lead confirmed against the landed 105). Backend's ROOT loader
// (`+page.server.ts`'s `loadExcludedTaxLedgers`, `api/src/lib/server/queries/navComposition.ts`)
// returns it as a SEPARATE sibling field beside `composition`: `excludedTaxLedgers:
// ExcludedTaxLedger[] | null`. TWO READS behind it (102's `fn_tax_authority_ledgers()` +
// pfin.account name lookup) — `ExcludedTaxLedger` below MIRRORS Backend's server-side type
// key-for-key (this file never imports it — frontend-engineer never imports from
// `src/lib/server/**`). THREE STATES, all real and all rendered distinctly (never collapsed):
//   `undefined` — this component's own defensive prop default (the prop wasn't passed at all);
//   `null`      — the loader's reads FAILED (RPC error or the account-name join failed) — "could
//                 not determine which ledgers are excluded," NEVER silently treated as `[]`;
//   `[]`        — a KNOWN, confirmed "no ledgers are currently designated" (the common
//                 bootstrap-default state) — rendering this is what makes an UNMARKED
//                 tax-authority account visible as "not excluded" (rider 0b's default-state
//                 failure has no other observer; PRD §2.4.4 / ADR-013, never ADR-049).
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

import type { FundsDueEnvelope } from './tax-quarterly';
import type { TaxJurisdiction } from '$lib/schemas/account-constants';

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

/**
 * SELF-268 / E41-E42 (Sec P-18, refined): the tax-liability envelope carried VERBATIM off 104's
 * own `nav_components.{realized_tax_liab,unrealized_tax_liab}` into 051/105's `buildups` keys.
 * REUSES the ALREADY-SHIPPED discriminated union (`tax-quarterly.ts`'s `FundsDueEnvelope`,
 * SELF-264/266) rather than inventing a second spelling of "envelope" — same fields, same
 * discriminant, same reason `amount` may be NEGATIVE (an overpayment is a genuine receivable; see
 * 105's own SIGN CONVENTION comment). A required-`status`-with-optional-siblings shape
 * (`{status, amount?, reason?}`) would let `amount` type-check as `undefined` while `status ===
 * 'unavailable'` — a `NaN` waiting to happen; this union makes `amount` and `reason` each
 * UNREACHABLE without narrowing on `status` first, so `usd.format(envelope)` (the whole envelope,
 * not its `.amount`) is a COMPILE ERROR rather than a silently-rendered `$NaN`/`$0`.
 *
 * THIS IS THE CANONICAL HOME (Sec P-18: "export it from nav-composition.ts and import it
 * server-side, so the two modules declare it once"). `api/src/lib/server/queries/navComposition.ts`
 * (Backend) currently carries a LOCAL `TaxLiabilityEnvelope` definition of the identical shape as a
 * stopgap (their own TODO names this file as the thing to import once it lands) — that duplicate
 * should be deleted and replaced with `import type { TaxLiabilityEnvelope } from '$lib/nav-composition'`
 * once this lands; not done here (outside this role's write boundary — `src/lib/server/**` is
 * Backend's).
 */
export type TaxLiabilityEnvelope = FundsDueEnvelope;

/** The buildup ladder magnitudes — mirrors 051/105 buildups (E41-E42 shape). `debt` is a POSITIVE
 * magnitude (AC 7 / M-3, unchanged). `realized_tax_liab` / `unrealized_tax_liab` are ENVELOPES, not
 * plain numbers. ⚠ SIGN (105's own comment, verbatim in substance): a computed envelope's raw
 * `amount` carries 104's sign UNCHANGED AT THIS TYPE LEVEL — `unrealized_tax_liab` is clamped at
 * zero by 104 (R9 / Sec M-2) and so is always ≥ 0, but `realized_tax_liab` is SIGNED and NOT
 * clamped: an overpayment is a genuine receivable, so `amount` goes NEGATIVE (R3 / E-2 option (A)).
 * Never abs() or clamp the raw `amount` here — the ladder's presentational negation (SELF-268
 * ruling, E44: all three subtractive rows flip at buildupRows()'s single site) happens ONLY in the
 * rendered `BuildupRow.displayValue`, never on this raw field. See taxRow() / buildupRows()'s own
 * comments + their regression tests. */
export interface NavCompositionBuildups {
	total_non_re: number;
	gross_total: number;
	debt: number;
	realized_tax_liab: TaxLiabilityEnvelope;
	unrealized_tax_liab: TaxLiabilityEnvelope;
}

/** The full §2.1.5 composition payload — mirrors the 051/105 top-level JSONB. ⚠ `excluded_tax_ledgers`
 * is NOT part of this payload — Backend's ROOT loader (`+page.server.ts`) returns it as a SEPARATE
 * sibling field beside `composition`, not nested in it; see `ExcludedTaxLedger` / `+page.svelte`
 * below. */
export interface NavComposition {
	groups: NavCompositionGroup[];
	buildups: NavCompositionBuildups;
	/** Already net of 0 for any unavailable tax line (105 cannot subtract a JSON null) — this
	 * field alone cannot distinguish "fully tax-adjusted" from "partial" from "unadjusted"; read
	 * `navFootBasis(buildups)` for that (Sec P-5 / option (C)). */
	nav: number;
}

/** One account excluded from the §2.1.5 buildup leaf set under AC 3a (SELF-268 AC 10a). MIRRORS
 * `api/src/lib/server/queries/navComposition.ts`'s own `ExcludedTaxLedger` key-for-key (this file
 * never imports it — frontend-engineer never imports from `src/lib/server/**`). `jurisdiction` is
 * the SAME `pfin.tax_jurisdiction_enum` vocabulary ('irs' | 'ftb') the §2.4.2 account form already
 * uses (`$lib/schemas/account-constants`'s `TaxJurisdiction`) — display via
 * `$lib/account-display`'s existing `taxJurisdictionLabel()`, never a second translation table. */
export interface ExcludedTaxLedger {
	account_id: number;
	account_name: string;
	jurisdiction: TaxJurisdiction;
}

/** A single rendered buildup-ladder row (excludes the NAV foot, rendered separately). Sec P-18: the
 * two tax rows carry `status` REQUIRED (a discriminant, not an optional field an unwary caller
 * could omit and fail open) and a UNIFORM `displayValue: number | null` — `null` on `unavailable`,
 * never a fabricated `$0` (AC 6). */
export type BuildupRow =
	| { key: 'total_non_re' | 'gross_total' | 'debt'; label: string; displayValue: number }
	| { key: 'realized_tax_liab' | 'unrealized_tax_liab'; label: string; status: 'computed'; displayValue: number }
	| { key: 'realized_tax_liab' | 'unrealized_tax_liab'; label: string; status: 'unavailable'; displayValue: null; reason: string };

function taxRow(key: 'realized_tax_liab' | 'unrealized_tax_liab', label: string, envelope: TaxLiabilityEnvelope): BuildupRow {
	// SELF-268 RULING UPDATE (team-lead under F/CTO delegation, E44 — Sec freeze F-2 option (A),
	// which also closes F-1): the ladder's ONE flip site now negates all three subtractive rows, not
	// Debt alone — a computed envelope's raw `amount` (104's sign, unchanged at the buildups/type
	// level; see NavCompositionBuildups's own comment) is negated HERE, once, the same as Debt's
	// magnitude below in buildupRows(). An underpaid liability (a positive `amount`) becomes a
	// NEGATIVE displayValue (reduces NAV, reading the same direction as Debt); an overpaid one (a
	// negative `amount`, a genuine receivable) becomes a POSITIVE displayValue (adds back). This is
	// NOT the double-negation defect the pre-SELF-268-ruling revision of this comment warned
	// against — that warning described a DIFFERENT (now-superseded) UI convention where the raw,
	// signed amount was rendered unflipped and any further negation here would have doubled the
	// sign against 105's own nav arithmetic. The ruling changes the LADDER's presentational
	// convention, not 105's underlying nav arithmetic (unchanged) or this envelope's raw `amount`
	// (unchanged) — see buildupRows()'s own comment for the full footing identity.
	if (envelope.status === 'computed') {
		return { key, label, status: 'computed', displayValue: -envelope.amount };
	}
	return { key, label, status: 'unavailable', displayValue: null, reason: envelope.reason };
}

/**
 * The buildup ladder in the EXACT ratified order (AC#4):
 *   Total Non-RE → Gross Total → Debt → Realized Tax Liab → Unrealized Tax Liab.
 * (NAV is the foot row, rendered separately by the component.)
 *
 * SELF-268 RULING (team-lead under F/CTO delegation, E44 — Sec freeze F-2 option (A), which also
 * closes F-1): this ONE site negates ALL THREE subtractive rows — Debt, Realized Tax Liab,
 * Unrealized Tax Liab — not Debt alone (supersedes the earlier "Debt is the ladder's ONLY sign
 * flip" convention this comment used to state). `buildups.debt` arrives as a positive magnitude and
 * is subtracted (displayValue = −debt, D5's original convention, unchanged). A computed tax
 * envelope's raw `amount` carries 104's sign UNCHANGED at the buildups level (see
 * NavCompositionBuildups's own comment) and is ALSO negated here, once, by taxRow(): an underpaid
 * liability (a positive `amount`) renders as a negative displayValue (reduces NAV, same reading as
 * Debt); an overpaid one (a negative `amount`, a genuine receivable) renders as a positive
 * displayValue (adds back). An unavailable envelope routes to the `displayValue: null` row variant
 * (see BuildupRow) — the component renders its `reason`, never a fabricated `$0`, and contributes
 * nothing to the footing below.
 *
 * FOOTING IDENTITY: the rendered ladder foots to the composed NAV —
 *   gross_total + debt.displayValue + realized_tax_liab.displayValue + unrealized_tax_liab.displayValue === nav
 * i.e. gross_total − |debt| − realized_amount − unrealized_amount, using 0 for any unavailable
 * envelope — the SAME arithmetic 105's own `nav` expression performs (this ruling changes only the
 * ladder's PRESENTATIONAL convention, never 105's underlying nav arithmetic). `total_non_re` is NOT
 * a term in this footing — it's an informational sub-total row, not part of the NAV sum. See
 * nav-composition.test.ts's footing regression (both an underpaid and an overpaid fixture).
 *
 * The sign convention stays "exactly one negation in exactly one place" (D5's original invariant);
 * that one place now negates three rows instead of one — there is still never a second flip site
 * anywhere else in this file or NavCompositionTable.svelte. See nav-composition.test.ts's "exactly
 * one flip site" + "signed realized, flipped" regressions.
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

// Stable machine `reason` codes → user-facing copy. `nav_components` (104) emits exactly TWO
// reason codes (verified live in 104's SQL): `no_schedule_any_year` (both scalars can carry this)
// and `ytd_paid_unavailable` (realized only — depends on YTD Paid, which unrealized never reads).
// EXACT COPY per team-lead 2026-09-04, forwarding Architect's 105-landing note — no longer
// placeholder V1.4 wording for these two codes.
// ⚠ `ytd_paid_unavailable`'s copy was CORRECTED post-walk (team-lead, same day): the realized line
// is the COMBINED Federal + California figure, so this reason also fires in the PARTIAL case —
// one jurisdiction's ledger designated, the other's not — not only the "neither designated" case
// the earlier wording implied. "designate one" reads as though a single ledger suffices; the
// corrected copy covers both the none-designated and the one-missing sub-cases without claiming
// which one it is.
const UNAVAILABLE_REASON_COPY: Record<string, string> = {
	no_schedule_any_year: 'no tax bracket schedule on file — enter it in Settings',
	ytd_paid_unavailable: 'a tax-authority ledger is not designated for every jurisdiction — designate the missing one in Accounts'
};
/** Exported so NavCompositionTable.svelte's per-row "Unavailable" cell uses the SAME copy as the
 * foot's label, rather than rendering 104's raw machine code directly — one mapping, two render
 * sites. The fallback string covers a reason code outside the two above (none reachable today —
 * defensive only, so an unrecognized future code degrades to something readable rather than
 * `undefined`). */
export function unavailableReasonCopy(reason: string): string {
	return UNAVAILABLE_REASON_COPY[reason] ?? 'see Settings';
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
			return `Net Assets Value (${basis.unavailableLine} tax not yet deducted — ${unavailableReasonCopy(basis.reason)})`;
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
