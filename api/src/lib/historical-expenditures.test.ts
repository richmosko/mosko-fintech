// historical-expenditures.test.ts — unit battery for the §2.3.4 chart's presentation helpers
// (SELF-256). Browser-safe, dep-free (node env) — mirrors nav-chart-domain.test.ts's pattern.

import { describe, it, expect } from 'vitest';
import {
	isCpiWhollyUnavailable,
	isAdjustedUnavailable,
	adjustedUnavailableReason,
	carriedCpiPoints,
	carriedCount,
	latestCarriedPoint,
	cpiCoverageThrough,
	rollingAverageSegments,
	sharedYDomain,
	type HistoricalExpenditurePoint
} from './historical-expenditures';

function point(overrides: Partial<HistoricalExpenditurePoint>): HistoricalExpenditurePoint {
	return {
		month_end: '2026-01-31',
		expense_monthly_nominal: 1000,
		expense_monthly_inflation_adjusted: 950,
		rolling_12mo_avg_inflation_adjusted: 900,
		cpi_period: '2026-01-01',
		cpi_value: 300,
		cpi_is_carried: false,
		cpi_carried_from: null,
		cpi_period_was_due: false,
		cpi_nonpublication_on_record: false,
		cpi_coverage_through: '2026-06-01',
		...overrides
	};
}

describe('isCpiWhollyUnavailable', () => {
	it('false for an empty series (a different state — empty, not unavailable)', () => {
		expect(isCpiWhollyUnavailable([])).toBe(false);
	});

	it('false when at least one row has an adjusted figure', () => {
		const points = [
			point({ expense_monthly_inflation_adjusted: null }),
			point({ expense_monthly_inflation_adjusted: 950 })
		];
		expect(isCpiWhollyUnavailable(points)).toBe(false);
	});

	it('true only when EVERY row is unresolvable', () => {
		const points = [
			point({ expense_monthly_inflation_adjusted: null, cpi_coverage_through: null }),
			point({ expense_monthly_inflation_adjusted: null, cpi_coverage_through: null })
		];
		expect(isCpiWhollyUnavailable(points)).toBe(true);
	});
});

describe('isAdjustedUnavailable / adjustedUnavailableReason', () => {
	it('true exactly when the adjusted figure is null', () => {
		expect(isAdjustedUnavailable(point({ expense_monthly_inflation_adjusted: null }))).toBe(true);
		expect(isAdjustedUnavailable(point({ expense_monthly_inflation_adjusted: 0 }))).toBe(false);
	});

	it('reason names the cpi_period, never alarm language', () => {
		const reason = adjustedUnavailableReason(point({ cpi_period: '1913-01-01' }));
		expect(reason).toContain('1913-01-01');
		expect(reason.toLowerCase()).not.toContain('error');
	});
});

describe('carriedCpiPoints / carriedCount / latestCarriedPoint', () => {
	it('excludes a carried point whose period was not due', () => {
		const points = [point({ cpi_is_carried: true, cpi_period_was_due: false })];
		expect(carriedCpiPoints(points)).toHaveLength(0);
		expect(carriedCount(points)).toBe(0);
		expect(latestCarriedPoint(points)).toBeNull();
	});

	it('counts DISTINCT carried periods, not rows', () => {
		const points = [
			point({ month_end: '2026-01-31', cpi_period: '2025-12-01', cpi_is_carried: true, cpi_period_was_due: true }),
			point({ month_end: '2026-02-28', cpi_period: '2025-12-01', cpi_is_carried: true, cpi_period_was_due: true })
		];
		expect(carriedCount(points)).toBe(1);
	});

	it('latestCarriedPoint is the LAST carried point in series order', () => {
		const first = point({ month_end: '2026-01-31', cpi_period: '2025-12-01', cpi_is_carried: true, cpi_period_was_due: true });
		const second = point({ month_end: '2026-02-28', cpi_period: '2026-01-01', cpi_is_carried: true, cpi_period_was_due: true });
		expect(latestCarriedPoint([first, second])).toBe(second);
	});
});

describe('cpiCoverageThrough', () => {
	it('null on an all-unavailable series', () => {
		expect(cpiCoverageThrough([point({ cpi_coverage_through: null })])).toBeNull();
	});

	it('reads the first non-null value', () => {
		expect(cpiCoverageThrough([point({ cpi_coverage_through: '2026-06-01' })])).toBe('2026-06-01');
	});
});

describe('rollingAverageSegments', () => {
	it('AC5: leading null-average rows (first 11 months) contribute no segment', () => {
		const points = [
			point({ month_end: '2026-01-31', rolling_12mo_avg_inflation_adjusted: null }),
			point({ month_end: '2026-02-28', rolling_12mo_avg_inflation_adjusted: null }),
			point({ month_end: '2026-03-31', rolling_12mo_avg_inflation_adjusted: 900 })
		];
		const segments = rollingAverageSegments(points);
		expect(segments).toHaveLength(1);
		expect(segments[0]).toHaveLength(1);
		expect(segments[0][0].month_end).toBe('2026-03-31');
	});

	it('a mid-series null (poisoned rolling window) splits into two runs, never bridged', () => {
		const points = [
			point({ month_end: '2026-01-31', rolling_12mo_avg_inflation_adjusted: 900 }),
			point({ month_end: '2026-02-28', rolling_12mo_avg_inflation_adjusted: null }),
			point({ month_end: '2026-03-31', rolling_12mo_avg_inflation_adjusted: 910 })
		];
		const segments = rollingAverageSegments(points);
		expect(segments).toHaveLength(2);
		expect(segments[0]).toHaveLength(1);
		expect(segments[1]).toHaveLength(1);
	});

	it('empty series produces zero segments', () => {
		expect(rollingAverageSegments([])).toHaveLength(0);
	});
});

describe('sharedYDomain', () => {
	it('spans the active bar field and the rolling overlay together', () => {
		const points = [
			point({ expense_monthly_inflation_adjusted: 950, rolling_12mo_avg_inflation_adjusted: 900 }),
			point({ expense_monthly_inflation_adjusted: 1200, rolling_12mo_avg_inflation_adjusted: 1000 })
		];
		expect(sharedYDomain(points, 'expense_monthly_inflation_adjusted')).toEqual([0, 1200]);
	});

	it('a null bar/overlay value never pulls the domain', () => {
		const points = [
			point({ expense_monthly_inflation_adjusted: null, rolling_12mo_avg_inflation_adjusted: null }),
			point({ expense_monthly_inflation_adjusted: 500, rolling_12mo_avg_inflation_adjusted: 450 })
		];
		expect(sharedYDomain(points, 'expense_monthly_inflation_adjusted')).toEqual([0, 500]);
	});

	it('a refund-dominated NEGATIVE month is included, never abs()-ed away', () => {
		const points = [point({ expense_monthly_inflation_adjusted: -200, rolling_12mo_avg_inflation_adjusted: 100 })];
		expect(sharedYDomain(points, 'expense_monthly_inflation_adjusted')).toEqual([-200, 100]);
	});

	it('falls back to the nominal field under the whole-series-unavailable substitution', () => {
		const points = [point({ expense_monthly_nominal: 800, expense_monthly_inflation_adjusted: null, rolling_12mo_avg_inflation_adjusted: null })];
		expect(sharedYDomain(points, 'expense_monthly_nominal')).toEqual([0, 800]);
	});

	it('inert [0, 1] default for an empty series', () => {
		expect(sharedYDomain([], 'expense_monthly_inflation_adjusted')).toEqual([0, 1]);
	});
});
