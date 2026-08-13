// nav-boundary.ts — browser-safe types + presentation helpers for the §12.1/§12.6
// cron/imported boundary disposition (SELF-220 · ADR-053 Decision 7, F/CTO-ratified
// 2026-08-12 — flows/phase-2-flows-2.1-net-worth.md §12). Mirrors the row shape
// returned by the Architect's `pfin.fn_first_cron_checkpoint` (migration 069), which
// Backend will thread through the +page.server.ts loader. Same pattern as
// nav-series.ts / nav-composition.ts / stale-constituent.ts: this is the single
// browser-side definition of the payload shape + the classification logic, so the
// chart component stays presentational over these.
//
// WHY THIS EXISTS — §12.1's ratified disposition, restated in code form: `062`'s
// checkpoint-carry treatment (`checkpoint_date <> point_date`) surfaces staleness
// whenever a NAV value was carried forward. That is correct post-boundary (a real
// cron gap) and WRONG pre-boundary — the imported Dec-2015-forward history landed at
// calendar month-end by construction (no cron existed yet), so at weekly/daily chart
// granularity nearly every imported point looks "carried" for a reason that has
// nothing to do with freshness. §12.1's ruling: this is §2.4.4's own
// "fires only where due" rule applied to a second axis — pre-boundary, no
// daily/weekly checkpoint was ever DUE, so the mismatch is explained entirely by the
// edge of the cron era. Suppress the staleness treatment there; render the
// `resolution-disclosure` (§12.6) instead — a factual resolution statement, never
// framed as staleness.
//
// The boundary date is an ARCHITECTURE-EXPOSED VALUE ONLY (069's whole reason for
// existing) — never inferred client-side by scanning point density. Every function
// below takes the 069 row as an explicit argument; none of them re-derive it.

/** One row of 069's return — mirrors pfin.fn_first_cron_checkpoint()'s three fields
 * exactly. See 069's header for the full four-state contract this shape encodes. */
export interface NavBoundary {
	/** Earliest nav_date among cron-classified rows; NULL when the caller has none. */
	first_cron_checkpoint: string | null;
	has_cron_rows: boolean;
	has_imported_rows: boolean;
}

/** Safe zero-value: no rows at all (069's state (a) — NULL/false/false). Matches
 * the "render nothing" case — never used to imply a real boundary. */
export const EMPTY_NAV_BOUNDARY: NavBoundary = {
	first_cron_checkpoint: null,
	has_cron_rows: false,
	has_imported_rows: false
};

/**
 * True when `pointDate` falls strictly before the cron era began — the
 * imported/backfilled era where the checkpoint-carry staleness treatment must NOT
 * fire (§12.1). ADR-053's admissibility rule (an import must precede the first cron
 * checkpoint) guarantees this is a CLEAN split at one date — no per-point flag is
 * needed on top of it. Defensively false when there is no boundary at all (069
 * states (a)/(b) — nothing to be "before").
 */
export function isPreBoundaryPoint(pointDate: string, boundary: NavBoundary): boolean {
	return boundary.first_cron_checkpoint !== null && pointDate < boundary.first_cron_checkpoint;
}

/**
 * True when `pointDate` belongs to the IMPORTED ERA — the broader question
 * `isPreBoundaryPoint` alone cannot answer, and the bug this function exists to
 * fix (Architect, 2026-08-13 contract-conformance flag): "before the boundary
 * date" and "in the imported era" COINCIDE in states (c)/(d), where a real
 * `first_cron_checkpoint` exists, but DIVERGE in state (b) — imported-only, where
 * `first_cron_checkpoint` is NULL because there is no cron era yet at all.
 * `isPreBoundaryPoint` alone returns `false` for every point in state (b) (there
 * is no date to be "before"), which is the CORRECT answer to ITS OWN narrow
 * question but the WRONG one for "is this point imported" — every point in state
 * (b) IS imported, by definition of the state.
 *
 * The correct predicate, covering all four of 069's states:
 *   - (a) no rows: moot, no points exist to ask this of.
 *   - (b) imported-only (`has_cron_rows === false`): TRUE for every point — there
 *     is no cron era to be "post-" anything relative to.
 *   - (c) cron-only: `has_cron_rows === true` and `first_cron_checkpoint` is the
 *     MINIMUM cron nav_date, so no real cron row can be pre-boundary — `false`
 *     for every actual point, same answer `isPreBoundaryPoint` alone would give.
 *   - (d) mixed: `has_cron_rows === true`, so this reduces to `isPreBoundaryPoint`
 *     exactly as before — the case the original (buggy) implementation was
 *     built and tested against, which is why the bug shipped: (d) never
 *     exercises the divergence.
 */
export function isImportedEraPoint(pointDate: string, boundary: NavBoundary): boolean {
	return !boundary.has_cron_rows || isPreBoundaryPoint(pointDate, boundary);
}

/**
 * §12.1/§12.2: whether a point's `checkpoint_date <> point_date` carry should be
 * rendered as staleness (`chart-placeholder`'s `stale-segment`) at all. Outside
 * the imported era this is a pure pass-through of the existing 062/067 signal;
 * inside it, suppressed — the `resolution-disclosure` (§12.6) carries that
 * information instead, and the two must never both fire for the same point (they
 * answer different questions: "is this specific value late" vs. "is this whole
 * span coarser-grained by design"). Delegates to `isImportedEraPoint`, NOT
 * `isPreBoundaryPoint` directly — see that function's header for why the
 * distinction is load-bearing in state (b).
 */
export function shouldSuppressCarryStaleness(pointDate: string, boundary: NavBoundary): boolean {
	return isImportedEraPoint(pointDate, boundary);
}

/**
 * §12.1/§12.6: whether the `resolution-disclosure` fires for the CURRENT VIEW.
 * `points` is whatever the chart currently has in view (the full 60-month default,
 * or a drilled sub-range) — this function does not assume "whole series".
 *
 * Two cases, both from 069's four-state matrix:
 *   - IMPORTED-ONLY (`has_cron_rows === false`, `has_imported_rows === true`):
 *     fires for the WHOLE series unconditionally — there is no boundary date to
 *     compare against (069 state (b), guaranteed to occur between seeding and the
 *     first cron night; the entire visible range is monthly-resolution by
 *     construction). This is intentionally NOT re-derived from an empty `points`
 *     array — a view that happens to have zero points in range must not be
 *     conflated with "no imported history exists" (069 state (a)).
 *   - MIXED (`has_cron_rows === true`, `has_imported_rows === true`): fires only
 *     when at least one point currently in view is pre-boundary.
 * CRON-ONLY and NO-ROWS both never fire — nothing to disclose.
 */
export function resolutionDisclosureFires(
	boundary: NavBoundary,
	points: { point_date: string }[]
): boolean {
	if (!boundary.has_imported_rows) return false;
	if (!boundary.has_cron_rows) return true;
	return points.some((p) => isPreBoundaryPoint(p.point_date, boundary));
}
