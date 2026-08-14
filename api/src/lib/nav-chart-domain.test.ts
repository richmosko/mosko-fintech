// nav-chart-domain.test.ts — unit battery for the §12.7 zoom/density-bound math and
// the shared y-domain computation (SELF-220). Browser-safe, dep-free (node env).

import { describe, it, expect } from 'vitest';
import { sharedYDomain, suggestGranularity, autoNarrowWindow } from './nav-chart-domain';
import type { NavSeriesPoint } from './nav-series';

function point(overrides: Partial<NavSeriesPoint>): NavSeriesPoint {
	return {
		point_date: '2026-01-31',
		nav_nominal: 100_000,
		checkpoint_date: '2026-01-31',
		nav_inflation_adjusted: 100_000,
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

describe('sharedYDomain', () => {
	it('spans both lines when both are present', () => {
		const points = [
			point({ nav_nominal: 100_000, nav_inflation_adjusted: 90_000 }),
			point({ nav_nominal: 120_000, nav_inflation_adjusted: 105_000 })
		];
		expect(sharedYDomain(points)).toEqual([90_000, 120_000]);
	});

	it('a NULL inflation-adjusted point never pulls the domain toward 0', () => {
		const points = [
			point({ nav_nominal: 100_000, nav_inflation_adjusted: null }),
			point({ nav_nominal: 120_000, nav_inflation_adjusted: 130_000 })
		];
		expect(sharedYDomain(points)).toEqual([100_000, 130_000]);
	});

	it('a negative nominal NAV is included (a real negative net worth is a valid domain bound)', () => {
		const points = [point({ nav_nominal: -5_000, nav_inflation_adjusted: -4_500 })];
		expect(sharedYDomain(points)).toEqual([-5_000, -4_500]);
	});

	it('returns the inert [0, 1] default for an empty series', () => {
		expect(sharedYDomain([])).toEqual([0, 1]);
	});
});

describe('suggestGranularity — §12.7', () => {
	it('suggests daily for a range under ~3 months', () => {
		expect(suggestGranularity('2026-01-01', '2026-02-01')).toBe('daily');
	});

	it('suggests weekly for a range between ~3 and ~12 months', () => {
		expect(suggestGranularity('2026-01-01', '2026-06-01')).toBe('weekly');
	});

	it('keeps monthly for a range wider than ~12 months', () => {
		expect(suggestGranularity('2020-01-01', '2026-01-01')).toBe('monthly');
	});

	it('boundary: exactly 92 days is still daily', () => {
		expect(suggestGranularity('2026-01-01', '2026-04-03')).toBe('daily'); // 92 days
	});

	it('boundary: exactly 366 days is still weekly', () => {
		expect(suggestGranularity('2025-01-01', '2026-01-01')).toBe('weekly'); // 365 days (leap-safe under 366)
	});
});

describe('autoNarrowWindow — §12.7 density-bounded narrowing', () => {
	it('daily over a wide view narrows to the last 3 months, anchored at the CURRENT end (not "today")', () => {
		const result = autoNarrowWindow('daily', '2020-01-01', '2026-06-01');
		expect(result).toEqual({ start: '2026-03-01', end: '2026-06-01' });
	});

	it('weekly over a wide view narrows to the last 6 months, anchored at the current end', () => {
		const result = autoNarrowWindow('weekly', '2020-01-01', '2026-06-01');
		expect(result).toEqual({ start: '2025-12-01', end: '2026-06-01' });
	});

	it('daily over an already-narrow view (≤3mo) does not narrow further', () => {
		expect(autoNarrowWindow('daily', '2026-04-01', '2026-06-01')).toBeNull();
	});

	it('weekly over an already-narrow view (≤6mo) does not narrow further', () => {
		expect(autoNarrowWindow('weekly', '2026-01-01', '2026-06-01')).toBeNull();
	});

	it('monthly never narrows, regardless of span', () => {
		expect(autoNarrowWindow('monthly', '2000-01-01', '2026-06-01')).toBeNull();
	});
});
