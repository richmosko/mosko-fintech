// nav-reference-dates.ts — SELF-223 client-side shape + predicates for the §2.1.4 NAV-at-
// three-reference-dates panel (frontend-owned, non-server). Mirrors migration 073's applied
// CONTRACT (merged 2026-08-14) for `pfin.fn_nav_reference_dates()` — originally built against
// the ratified contract text (temp/pm-self223-ac-rewrite.md v3) ahead of 073 landing, per
// team-lead's routing; reconciled against the live migration below.
//
// SHAPE CROSS-CHECKED AGAINST BACKEND'S SELF-223 HAND-OFF (2026-08-14, their
// $lib/nav-reference-dates.ts drafted independently from the same ratified contract, THEN
// re-verified by Backend against the applied 073 DDL): the two files' NavReferenceDateRow
// interfaces matched FIELD-FOR-FIELD except ONE nullability call, corrected post-merge —
// cpi_any_carried / cpi_unavailable are NEVER NULL (073's own contract: every row of this
// surface is CPI-eligible, so there is no not-applicable case; confirmed by Backend both from
// the function body — v_carried/v_unavail are always real booleans by construction — and a live
// shape smoke returning real true/false on all three rows). Every other field matched, including
// reference_date / cpi_basis_period non-null and reference_checkpoint_date / nav /
// nav_prior_yr_dollars / cpi_period nullable. Two semantic notes folded in from backend's text:
//   · cpi_period is per-row — the specific CPI observation THIS row's own deflation used (This
//     Month: 066's coverage_through print; Prior Month: first-of-month of the calendar anchor;
//     Prior Year-End: December of the prior year) — not a shared/panel-wide value. Nulls only on
//     the this_month row when the global CPI store has no coverage at all.
//   · cpi_any_carried is a TWO-leg OR per row (this row's own cpi_period leg + the shared
//     cpi_basis_period leg) — NOT a three-leg OR identically shared across all three rows the
//     way 071/072's panel-wide flag was. Do not assume it is the same value on all three rows.
//
// STRUCTURAL RENDERING ONLY — AC5's TWO discriminated NULL causes (there is no third
// "not-applicable" horizon here, unlike SELF-221/222's month/ytd: every one of the three
// reference-date rows always wants a prior-Yr-$ figure):
//   INSUFFICIENT HISTORY   no checkpoint at-or-before reference_date exists for this caller
//                          -> reference_checkpoint_date NULL, nav AND nav_prior_yr_dollars
//                             BOTH NULL. UI renders "Insufficient history" for the row.
//   CPI UNRESOLVABLE       cpi_unavailable = true -> nav STILL RENDERS (never depended on CPI);
//                          only nav_prior_yr_dollars is NULL.
// These render DIFFERENTLY (AC5 verbatim: "the two causes render differently") — a row-level
// badge for the first, a cell-level label for the second — never collapsed into one shape.
//
// NEVER INFERRED CLIENT-SIDE, NEVER BORROWED FROM THE ADJACENT DELTA PANEL (AC5 verbatim,
// F/CTO-ratified 2026-08-13 own-staleness-signal ruling): this module reads only the columns
// this contract returns for THIS row; it never reaches into $lib/nav-delta-panel.ts's rows or
// reuses NavDeltaPanel's current_checkpoint_date disclosure.
//
// §2.4.4 INFORMATIONAL-TIER MARKER RENDERING (SELF-229 — the framework ramp this file's own
// predecessor comment deferred to). cpi_any_carried is a PER-ROW two-leg OR (see the interface
// doc below) — NOT the panel-wide flag NavDeltaPanel's anyCpiCarried() reads off row[0], so this
// file exposes a PER-ROW predicate (isRowCpiCarried) rather than a whole-rows-array one. Vocabulary
// harmonized with NavDeltaPanel's carried-note ("Carried forward — …no action needed") — same
// leading phrase, adapted to a per-row cell marker instead of a panel-wide basis line since the
// underlying signal here varies row-to-row.
//
// THE JANUARY-FAMILY COPY PROBLEM (PM comment 775fb0d1; SELF-229 owns WORDS ONLY, never shape —
// three rows always render, no de-duplication, no structural special-casing):
//   (ii) DUPLICATE ROWS — in January, prior_month's reference_date IS prior_year_end's reference_date
//        (both December of the prior year), so the SAME checkpoint serves both rows and every column
//        matches by construction. Detected here via reference_checkpoint_date equality (a plain
//        comparison of two already-server-supplied dates — not a staleness inference, not a client
//        clock check) so the explanatory caption below the table appears ONLY when the coincidence
//        is actually present, never as a permanent disclaimer.
//   (iii) DUPLICATE COLUMNS — under CPI-U arrears, THIS row's own cpi_period lands on the SAME
//        month as the shared cpi_basis_period for every one of the three rows, so NAV and
//        NAV — Prior Yr $ read identically across the whole table. Detected via cpi_period ===
//        cpi_basis_period on every row (again a plain per-row column comparison, not inference).
// Both predicates read ONLY columns this contract already returns; neither compares against a
// client-side clock or infers a connection-health state — that axis stays exclusively on `046`
// fn_aggregation_has_stale_constituent() via the StaleConstituentBadge the component also renders.
//
// VALUE-COLOR FENCE (design-system-spec §5 fence 1) — THE OPPOSITE SCOPING FROM
// $lib/nav-delta-panel.ts: `nav` / `nav_prior_yr_dollars` are NAV LEVELS (positions, PRD §2.1.4:
// "NAV (nominal dollars)"), not deltas — same category as the §2.1.1 headline and
// NavCompositionTable's "current value" column, NEITHER of which take --c-pos/--c-neg. This file
// therefore does NOT export a signed-delta formatter or a sign-class helper; formatUsd below is
// the same plain, unsigned, neutral-ink convention the headline NAV already uses (a negative
// value renders with the locale's ordinary minus glyph, not U+2212 — that convention is scoped to
// SELF-222's delta cells, not to a NAV level).

export type NavReferenceLabel = 'this_month' | 'prior_month' | 'prior_year_end';

export interface NavReferenceDateRow {
	reference: NavReferenceLabel;
	/** The CALENDAR reference date (a month-end). Treated as NOT NULL, by direct analogy to
	 * 071/072's anchor_date — a computed calendar label, not a lookup that could fail to
	 * resolve. Reconcile against the real migration when it lands. */
	reference_date: string;
	/** The checkpoint that actually served this row; NULL when no checkpoint at-or-before
	 * reference_date exists for this caller (AC5's insufficient-history discriminator). */
	reference_checkpoint_date: string | null;
	nav: number | null;
	/** `nav` expressed in prior-Year-End dollars. NULL when reference_checkpoint_date is NULL
	 * (insufficient history) OR when cpi_unavailable is true — see the module header. */
	nav_prior_yr_dollars: number | null;
	/** The CPI observation THIS row's own deflation used (This Month: 066's coverage_through
	 * print; Prior Month: first-of-month of the calendar anchor; Prior Year-End: December of the
	 * prior year) — per-row, not shared across rows. Nullable (AC3 gives cpi_basis_period an
	 * explicit non-NULL guarantee it does NOT extend to this column). */
	cpi_period: string | null;
	/** December of the prior calendar year — a pure calendar label (AC3: "non-NULL on all three
	 * rows even when cpi_unavailable is true"). Not exposed via any predicate in this file
	 * (SELF-229 scope); carried for completeness and future reconciliation. */
	cpi_basis_period: string;
	/** OR over this row's TWO CPI legs (its own cpi_period leg + the shared cpi_basis_period
	 * leg) — NOT a three-leg OR identically shared across all three rows the way 071/072's
	 * panel-wide flag was; each row's own reference-date leg can differ. NEVER NULL — 073's own
	 * contract: every row here is CPI-eligible, so there is no not-applicable case the way
	 * 071/072 have on month/ytd. No predicate exposed here (SELF-229 scope). */
	cpi_any_carried: boolean;
	/** True when this row's real-terms figure could not be formed (a non-positive CPI leg); nav
	 * still stands in that case. NEVER NULL, same reason as cpi_any_carried above. */
	cpi_unavailable: boolean;
}

// Fixed row order per AC1 ("EXACTLY three rows, always, fixed order").
export const REFERENCE_ORDER: NavReferenceLabel[] = ['this_month', 'prior_month', 'prior_year_end'];

// PRD §2.1.4 verbatim row labels.
export const REFERENCE_LABEL: Record<NavReferenceLabel, string> = {
	this_month: 'This Month',
	prior_month: 'Prior Month',
	prior_year_end: 'Prior Year-End'
};

/** Re-orders a possibly-scrambled row set to REFERENCE_ORDER, dropping any row whose `reference`
 * isn't recognized — same defensive posture as $lib/nav-delta-panel.ts's orderRows. */
export function orderReferenceRows(rows: NavReferenceDateRow[]): NavReferenceDateRow[] {
	return REFERENCE_ORDER.map((r) => rows.find((row) => row.reference === r)).filter(
		(row): row is NavReferenceDateRow => row != null
	);
}

// AC5 discriminator #1: no checkpoint reached this row's reference_date at all. Both value
// columns NULL — the whole row renders as unavailable, not just a cell.
export function isInsufficientHistory(row: NavReferenceDateRow): boolean {
	return row.reference_checkpoint_date === null;
}

// AC5 discriminator #2: the nominal figure stands; only the prior-Yr-$ conversion is unformed.
// No isCpiApplicable gate here (unlike NavDeltaPanel's Month/YTD) — every reference-date row
// always wants a prior-Yr-$ figure, so there is no "not applicable" horizon to gate against.
export function isCpiUnresolvable(row: NavReferenceDateRow): boolean {
	return row.cpi_unavailable;
}

// Plain, UNSIGNED whole-dollar formatting — a NAV LEVEL, not a delta (see the module header's
// VALUE-COLOR FENCE note). Same convention as the §2.1.1 headline / NavCompositionTable's
// current-value column: Intl's ordinary locale minus glyph on a negative value, no leading '+'
// on a positive one, no pos/neg color class.
const usd = new Intl.NumberFormat('en-US', {
	style: 'currency',
	currency: 'USD',
	minimumFractionDigits: 0,
	maximumFractionDigits: 0
});

export function formatUsd(n: number): string {
	return usd.format(n);
}

// ── SELF-229 §2.4.4 informational-tier + January-family predicates ──────────────────────────

// PER-ROW carried-CPI marker (see module header — NOT NavDeltaPanel's panel-wide anyCpiCarried).
// Gated by the caller on !isCpiUnresolvable(row): a carried note attaches to a rendered figure,
// never to an already-"CPI unavailable" cell.
export function isRowCpiCarried(row: NavReferenceDateRow): boolean {
	return row.cpi_any_carried;
}

// (ii) DUPLICATE ROWS — prior_month and prior_year_end are served by the identical checkpoint
// (both non-null and equal). Both rows must have resolved (not insufficient-history) for the
// coincidence to be a real, renderable fact rather than two absent rows trivially "matching".
export function priorMonthDuplicatesPriorYearEnd(rows: NavReferenceDateRow[]): boolean {
	const priorMonth = rows.find((r) => r.reference === 'prior_month');
	const priorYearEnd = rows.find((r) => r.reference === 'prior_year_end');
	if (!priorMonth || !priorYearEnd) return false;
	if (priorMonth.reference_checkpoint_date === null || priorYearEnd.reference_checkpoint_date === null) {
		return false;
	}
	return priorMonth.reference_checkpoint_date === priorYearEnd.reference_checkpoint_date;
}

// (iii) DUPLICATE COLUMNS — every row's own cpi_period lands on the same month as the shared
// cpi_basis_period, so NAV and NAV — Prior Yr $ read identically across the whole table. A row
// with cpi_period === null (This Month, no CPI coverage at all) is NOT a match — that is the
// CPI-unresolvable state, a different fact, so it fails this predicate rather than vacuously
// passing it.
export function columnsCollapseUnderArrears(rows: NavReferenceDateRow[]): boolean {
	if (rows.length === 0) return false;
	return rows.every((r) => r.cpi_period !== null && r.cpi_period === r.cpi_basis_period);
}
