// nav-reference-dates.ts — SELF-223 client-side shape + predicates for the §2.1.4 NAV-at-
// three-reference-dates panel (frontend-owned, non-server). Mirrors the RATIFIED CONTRACT for
// `pfin.fn_nav_reference_dates()` verbatim (temp/pm-self223-ac-rewrite.md v3-final, jointly
// agreed PM/Architect, F/CTO ratify pending only the "Prior Month" product call) — the migration
// itself is being authored in PARALLEL (per team-lead: "don't block on the migration"), so this
// file is built against the ratified AC text, not an applied `supabase/migrations/*.sql` file.
//
// ⚠ NULLABILITY CALLS MARKED BELOW ARE CONTRACT-TEXT INFERENCES, NOT VERIFIED AGAINST A REAL
// MIGRATION — flag prominently at reconciliation time (same shape as the 071→072 reconciliation
// this surface's sibling, $lib/nav-delta-panel.ts, already went through once). Where the AC text
// states a fact explicitly (reference_date, cpi_basis_period are non-NULL), this file follows it;
// where it is silent, this file defaults to the MORE DEFENSIVE (nullable) reading rather than
// assuming a shape that would crash if the real migration is stricter or looser.
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
// §2.4.4 INFORMATIONAL-TIER MARKER RENDERING (the "carried" badge/basis-line vocabulary
// NavDeltaPanel and NavHistoryChart use) IS DELIBERATELY OUT OF SCOPE — SELF-229, per team-lead's
// explicit routing. cpi_any_carried / cpi_period / reference_checkpoint_date are carried in the
// type below (the columns this contract ships now, per AC5's own "the columns that will feed it
// ship in this contract now") but this file exposes NO predicate or basis-line helper for them —
// adding one here would be building the SELF-229 surface early, not a SELF-223 concern.
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
	/** The CPI observation period this row deflated at. Nullable (defensive reading — AC3 gives
	 * cpi_basis_period an explicit non-NULL guarantee it does NOT extend to this column). */
	cpi_period: string | null;
	/** December of the prior calendar year — a pure calendar label (AC3: "non-NULL on all three
	 * rows even when cpi_unavailable is true"). Not exposed via any predicate in this file
	 * (SELF-229 scope); carried for completeness and future reconciliation. */
	cpi_basis_period: string;
	/** Nullable (defensive reading, no predicate exposed here — SELF-229 scope). */
	cpi_any_carried: boolean | null;
	/** Nullable (defensive reading). true → nav_prior_yr_dollars is NULL while nav stands. */
	cpi_unavailable: boolean | null;
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
	return row.cpi_unavailable === true;
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
