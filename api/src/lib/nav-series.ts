// nav-series.ts — browser-safe types + presentation helpers for the §2.1.2.d NAV-over-time
// chart (SELF-220 · V1.1). NON-server module: mirrors the row shape returned by the
// Architect's `pfin.fn_nav_series_inflation_adjusted` (migration 067), which Backend threads
// through the +page.server.ts loader as chart data. This is the single browser-side
// definition of the payload shape + the gap/staleness/availability derivations, so the chart
// component itself stays purely presentational over these — same pattern as
// nav-composition.ts (§2.1.5) and stale-constituent.ts (D1 marker).
//
// CONTRACT MIRRORED (067's header is canonical — read it live before touching this file, it
// is not restated in full here): one row per point, ascending point_date. nav_nominal /
// checkpoint_date are 062's pass-through and are NEVER null. nav_inflation_adjusted is
// NULLABLE BY DESIGN when the CPI leg is absent or non-positive — 067's own header names the
// hazard explicitly: a consumer that SUMs/AVGs/MAXes this column across the series silently
// skips un-deflatable points and reads as though the series were complete. THIS MODULE'S
// ANSWER: never aggregate the column at all — only plot each non-null point, or render a gap
// at each null one (inflationAdjustedSegments below). The cpi_* columns are 066's row,
// prefixed, minus gap_class (066's contract: gap_class is operator-axis and must not reach a
// user-facing read path — this module does not surface it because 067 does not return it).

export const NAV_SERIES_GRANULARITIES = ['monthly', 'weekly', 'daily'] as const;
export type NavSeriesGranularity = (typeof NAV_SERIES_GRANULARITIES)[number];

/** One row of 067's return, as it arrives over PostgREST/supabase-js (dates as ISO strings). */
export interface NavSeriesPoint {
	point_date: string;
	nav_nominal: number;
	checkpoint_date: string;
	/** NULLABLE — never zero. See the module header: plotted-or-gapped, never aggregated. */
	nav_inflation_adjusted: number | null;
	cpi_period: string;
	cpi_value: number | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	cpi_coverage_through: string | null;
}

/** Zero-value for a failed/absent series load (mirrors EMPTY_STALENESS's convention). */
export const EMPTY_NAV_SERIES: NavSeriesPoint[] = [];

/**
 * A carried NAV point (062's detectability mechanism, inherited unchanged through 067):
 * checkpoint_date !== point_date means the plotted value was measured on an earlier date and
 * carried forward across a cron gap. 067's contract states consumers SHOULD surface NAV
 * staleness on exactly this condition, matching 062. This is the chart's ADR-013 INV-1
 * staleness-marker obligation for this surface — design-system-spec.md's `chart-placeholder`
 * component already names a `stale-segment` state for it.
 */
export function isCarriedNavPoint(p: NavSeriesPoint): boolean {
	return p.checkpoint_date !== p.point_date;
}

/**
 * Splits a series into contiguous runs where nav_inflation_adjusted is non-null, for
 * gap-aware dashed-line rendering (PRD §2.1.2 dual-line AC). A run boundary falls at every
 * null point; the null point itself belongs to neither neighboring run (it has no adjusted
 * value to anchor a segment endpoint on). This is the ONLY sanctioned way to consume this
 * column across a series — never a client-side interpolation across the gap, and never a
 * silent skip that would make two runs LOOK continuous when they are not.
 */
export function inflationAdjustedSegments(points: NavSeriesPoint[]): NavSeriesPoint[][] {
	const segments: NavSeriesPoint[][] = [];
	let current: NavSeriesPoint[] = [];
	for (const p of points) {
		if (p.nav_inflation_adjusted === null) {
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
 * True when the ENTIRE series is un-deflatable — 067's fail-quiet empty-CPI-store case.
 * Maps to design-system-spec.md's `chart-placeholder` `cpi-unavailable(nominal-only)` state:
 * render the nominal line only, with a disclosure naming why no inflation-adjusted line is
 * present, rather than an all-gap dashed line that reads as a rendering defect.
 */
export function isCpiUnavailable(points: NavSeriesPoint[]): boolean {
	return points.length > 0 && points.every((p) => p.nav_inflation_adjusted === null);
}

/**
 * AC6 (SELF-220) sparse-history detector: fewer than `monthsThreshold` DISTINCT calendar
 * months of history — not row count. A 'daily' series over two sparse months must not read
 * as "plenty of data" just because it carries many rows. Drives the `chart-placeholder`
 * partial-line + data-density-indicator state. An empty series is its own state (see the
 * `chart-placeholder` `empty` case) and is deliberately NOT reported as sparse here.
 */
export function isSparseHistory(points: NavSeriesPoint[], monthsThreshold = 12): boolean {
	if (points.length === 0) return false;
	const months = new Set(points.map((p) => p.point_date.slice(0, 7)));
	return months.size < monthsThreshold;
}
