// historical-expenditures.ts — browser-safe types + presentation helpers for the §2.3.4
// Historical Expenditures chart (SELF-256). NON-server module (ships to the browser): mirrors
// the row shape returned by the Architect's `pfin.fn_historical_expenditures` (migration 096,
// merged PR #586), which Backend's loader will thread through as chart data — same
// hand-kept-copy pattern as nav-series.ts (SELF-220) for the sibling §2.1.2 chart. This file is
// the single browser-side definition of the payload shape + the CPI-availability / rolling-line
// / unclassified-window derivations, so the chart component itself stays purely presentational.
//
// CONTRACT MIRRORED (096's header is canonical — read it live before touching this file, it is
// not restated in full here): one row per month_end, ASCENDING, dense interior with no leading
// pad (fewer than 60 rows = less history; ZERO rows = no qualifying expense in the trailing
// 5-year window at all — an empty array, not an error). expense_monthly_nominal is NEVER null
// (096's LEFT JOIN + coalesce(...,0) — an interior month with nothing qualifying is a real $0
// row). expense_monthly_inflation_adjusted and rolling_12mo_avg_inflation_adjusted are NULLABLE
// BY DESIGN — never 0 — when the CPI leg can't be resolved; see isAdjustedUnavailable /
// isCpiWhollyUnavailable below for the two distinguishable reasons a consumer must not conflate.
// SIGN: outflow-positive, already applied server-side (F/CTO-ratified 2026-08-31 comment on
// SELF-256) — render every money field AS DELIVERED; no sign transformation anywhere in this
// module or its consumers.

/** One row of 096's return, as it arrives over PostgREST/supabase-js (dates as ISO strings). */
export interface HistoricalExpenditurePoint {
	month_end: string;
	/** Outflow-positive nominal spend for the month. NEVER null — an interior month with no
	 *  qualifying expense is a real, measured $0 (096's dense-interior rule), and a month past
	 *  the anchor is never emitted at all (no trailing pad beyond the reader's own bound). */
	expense_monthly_nominal: number;
	/** NULLABLE — never zero. Null means "cannot be deflated for this month", not "spent
	 *  nothing real-terms" (096's DIVISION SAFETY). See isAdjustedUnavailable. */
	expense_monthly_inflation_adjusted: number | null;
	/** NULLABLE — never zero. Null for the first 11 rows of any series (fewer than 12
	 *  constituent months in frame) OR whenever any of its 12 constituent months is itself
	 *  un-deflatable (096's ROLLING WINDOW: never averaged over the survivors). */
	rolling_12mo_avg_inflation_adjusted: number | null;
	cpi_period: string;
	/** NULLABLE. Null is the TRUE "cannot resolve at all" case (no stored value, no carry
	 *  candidate) — distinct from cpi_is_carried, which means a value WAS resolved (via
	 *  carry-forward). See isAdjustedUnavailable. */
	cpi_value: number | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	/** Store-scoped, identical on every row when resolvable — null only when the CPI-U store
	 *  has no coverage at all (see isCpiWhollyUnavailable). */
	cpi_coverage_through: string | null;
}

/** Zero-value for a failed/absent series load (mirrors EMPTY_NAV_SERIES's convention). */
export const EMPTY_HISTORICAL_EXPENDITURES: HistoricalExpenditurePoint[] = [];

/**
 * Whole-series CPI-unavailable state (flows/phase-2-flows-2.3-spending.md §6 error/edge states,
 * "CPI-U unavailable... show the nominal series with an explicit note... never fabricate
 * normalized values" — the SAME rule §2.1.2/NavHistoryChart applies via nav-series.ts's
 * isCpiUnavailable, generalized here to a bar series). True only when EVERY row's adjusted
 * figure is null — i.e. the CPI-U store has no usable coverage at all (096's v_cpi_basis guard).
 * A single unresolvable month within an otherwise-normal series is a DIFFERENT, per-row state —
 * see isAdjustedUnavailable — and must not trip this fallback.
 */
export function isCpiWhollyUnavailable(points: HistoricalExpenditurePoint[]): boolean {
	return points.length > 0 && points.every((p) => p.expense_monthly_inflation_adjusted === null);
}

/**
 * Per-row 066-consumer rendering rule (carried from 066/067's established contract, NOT
 * re-derived here — SELF-256 brief AC6): cpi_value IS NULL means the CPI leg could not be
 * resolved for this month at all (no stored value, no carry candidate) — "uncomputable is not
 * stale" (§2.4.4). This is the reason expense_monthly_inflation_adjusted is null for the row.
 * Distinct from cpi_is_carried (a value WAS resolved, just from an earlier period).
 */
export function isAdjustedUnavailable(point: HistoricalExpenditurePoint): boolean {
	return point.expense_monthly_inflation_adjusted === null;
}

/** The reason text for a single UNAVAILABLE month (AC6/AC8) — a factual, non-alarming statement,
 *  never "error" language: this is an operator-axis data gap, not a fault of the user's data. */
export function adjustedUnavailableReason(point: HistoricalExpenditurePoint): string {
	return `No CPI-U data on record for ${point.cpi_period} — this month can't be shown in inflation-adjusted terms.`;
}

/**
 * The series-level informational-marker inputs (PRD §2.4.4: "one series-level mark, not one per
 * point" — 096's own header states the per-row cpi_* columns are INPUTS to this OR-reduction,
 * never an instruction to mark each bar). Mirrors NavHistoryChart's carriedCpiPoints /
 * carriedCount / latestCarried inline derivations, extracted here as pure/testable helpers.
 * A month that is BOTH unavailable (cpi_value null) and "carried" is impossible by construction —
 * cpi_is_carried can only be true when a value WAS resolved (096/066's contract) — so this filter
 * and isAdjustedUnavailable are mutually exclusive per row, not overlapping.
 */
export function carriedCpiPoints(points: HistoricalExpenditurePoint[]): HistoricalExpenditurePoint[] {
	return points.filter((p) => p.cpi_is_carried && p.cpi_period_was_due);
}

export function carriedCount(points: HistoricalExpenditurePoint[]): number {
	const periods = new Set(carriedCpiPoints(points).map((p) => p.cpi_period));
	return periods.size;
}

/** Most recent carried point in the series, or null when none — the one the badge names when
 *  carriedCount === 1 (mirrors InformationalMarkerBadge's single-span message branch). */
export function latestCarriedPoint(points: HistoricalExpenditurePoint[]): HistoricalExpenditurePoint | null {
	const carried = carriedCpiPoints(points);
	return carried.length > 0 ? carried[carried.length - 1] : null;
}

/** The store-scoped coverage-through date for the basis line ("CPI-U through {date}") — the
 *  first non-null value across the series (identical on every resolvable row; null only under
 *  isCpiWhollyUnavailable). */
export function cpiCoverageThrough(points: HistoricalExpenditurePoint[]): string | null {
	return points.find((p) => p.cpi_coverage_through !== null)?.cpi_coverage_through ?? null;
}

/**
 * Splits a series into contiguous runs where `rolling_12mo_avg_inflation_adjusted` is non-null,
 * for gap-aware line rendering — the SAME pattern as nav-series.ts's inflationAdjustedSegments,
 * generalized to this surface's rolling-average field. Naturally satisfies AC5 (first 11 months
 * render bars but no line): those rows are simply outside every segment, never a fabricated
 * zero-length line at the start. Never a client-side interpolation across a gap.
 */
export function rollingAverageSegments(
	points: HistoricalExpenditurePoint[]
): HistoricalExpenditurePoint[][] {
	const segments: HistoricalExpenditurePoint[][] = [];
	let current: HistoricalExpenditurePoint[] = [];
	for (const p of points) {
		if (p.rolling_12mo_avg_inflation_adjusted === null) {
			if (current.length > 0) segments.push(current);
			current = [];
		} else {
			current.push(p);
		}
	}
	if (current.length > 0) segments.push(current);
	return segments;
}

/**
 * The shared y-domain across whichever bar field is active (adjusted normally, nominal under
 * the isCpiWhollyUnavailable fallback) PLUS the rolling-average overlay when present — one
 * linear y-scale must fit both. Nulls never contribute (matches nav-chart-domain.ts's
 * sharedYDomain — a NULL must never pull the domain toward 0). `[0, 1]` inert default for an
 * empty series, never actually rendered against (the empty-state branch takes over instead).
 */
export function sharedYDomain(
	points: HistoricalExpenditurePoint[],
	barField: 'expense_monthly_inflation_adjusted' | 'expense_monthly_nominal'
): [number, number] {
	const values: number[] = [];
	for (const p of points) {
		const bar = p[barField];
		if (bar !== null) values.push(bar);
		if (p.rolling_12mo_avg_inflation_adjusted !== null) values.push(p.rolling_12mo_avg_inflation_adjusted);
	}
	if (values.length === 0) return [0, 1];
	// A bar chart's y-axis conventionally includes 0 (an unanchored band would make bar HEIGHT
	// misread as magnitude-from-zero when it isn't) — SIGN CONVENTION notes a refund-dominated
	// month is reachable and renders negative, so the domain must not assume non-negative either.
	return [Math.min(0, ...values), Math.max(0, ...values)];
}
