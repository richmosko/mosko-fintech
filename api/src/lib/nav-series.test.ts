// nav-series.test.ts — unit battery for the §2.1.2.d NAV-chart presentation helpers
// (SELF-220). Browser-safe, dep-free (node env). Exercises the gap-aware segmenting,
// carried-point detection, CPI-unavailable, and sparse-history derivations deterministically
// without a DOM env — the chart component is a thin presentational shell over these.

import { describe, it, expect } from 'vitest';
import {
	inflationAdjustedSegments,
	isCarriedNavPoint,
	isCpiUnavailable,
	isSparseHistory,
	type NavSeriesPoint
} from './nav-series';

/** Minimal well-formed point builder — fills every column with a safe default. */
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

describe('inflationAdjustedSegments — gap-aware, never interpolated', () => {
	it('returns one segment for an unbroken series', () => {
		const points = [
			point({ point_date: '2026-01-31' }),
			point({ point_date: '2026-02-28' }),
			point({ point_date: '2026-03-31' })
		];
		expect(inflationAdjustedSegments(points)).toHaveLength(1);
		expect(inflationAdjustedSegments(points)[0]).toHaveLength(3);
	});

	it('splits into two segments around a single NULL point, excluding the NULL point itself', () => {
		const points = [
			point({ point_date: '2026-01-31' }),
			point({ point_date: '2026-02-28', nav_inflation_adjusted: null }),
			point({ point_date: '2026-03-31' })
		];
		const segments = inflationAdjustedSegments(points);
		expect(segments).toHaveLength(2);
		expect(segments[0].map((p) => p.point_date)).toEqual(['2026-01-31']);
		expect(segments[1].map((p) => p.point_date)).toEqual(['2026-03-31']);
	});

	it('produces zero segments for an all-NULL series (never a phantom flat segment)', () => {
		const points = [
			point({ point_date: '2026-01-31', nav_inflation_adjusted: null }),
			point({ point_date: '2026-02-28', nav_inflation_adjusted: null })
		];
		expect(inflationAdjustedSegments(points)).toEqual([]);
	});

	it('handles leading and trailing NULL runs without leaking empty segments', () => {
		const points = [
			point({ point_date: '2026-01-31', nav_inflation_adjusted: null }),
			point({ point_date: '2026-02-28' }),
			point({ point_date: '2026-03-31', nav_inflation_adjusted: null })
		];
		const segments = inflationAdjustedSegments(points);
		expect(segments).toHaveLength(1);
		expect(segments[0].map((p) => p.point_date)).toEqual(['2026-02-28']);
	});

	it('returns [] for an empty series', () => {
		expect(inflationAdjustedSegments([])).toEqual([]);
	});
});

describe('isCarriedNavPoint — 062/067 detectability mechanism', () => {
	it('false when checkpoint_date equals point_date', () => {
		expect(isCarriedNavPoint(point({ point_date: '2026-01-31', checkpoint_date: '2026-01-31' }))).toBe(false);
	});

	it('true when checkpoint_date precedes point_date (a carried checkpoint)', () => {
		expect(isCarriedNavPoint(point({ point_date: '2026-01-31', checkpoint_date: '2025-12-15' }))).toBe(true);
	});
});

describe('isCpiUnavailable — 067 fail-quiet empty-CPI-store case', () => {
	it('false for a normal series with adjusted values present', () => {
		expect(isCpiUnavailable([point({}), point({})])).toBe(false);
	});

	it('true only when EVERY point is un-deflatable', () => {
		const points = [
			point({ nav_inflation_adjusted: null, cpi_coverage_through: null }),
			point({ nav_inflation_adjusted: null, cpi_coverage_through: null })
		];
		expect(isCpiUnavailable(points)).toBe(true);
	});

	it('false when only SOME points are un-deflatable (a partial gap, not full unavailability)', () => {
		const points = [point({ nav_inflation_adjusted: null }), point({})];
		expect(isCpiUnavailable(points)).toBe(false);
	});

	it('false for an empty series — empty is its own state, not "unavailable"', () => {
		expect(isCpiUnavailable([])).toBe(false);
	});
});

describe('isSparseHistory — AC6, distinct MONTHS not row count', () => {
	it('false for 12 distinct months at the default threshold', () => {
		const points = Array.from({ length: 12 }, (_, i) =>
			point({ point_date: `2026-${String(i + 1).padStart(2, '0')}-15` })
		);
		expect(isSparseHistory(points)).toBe(false);
	});

	it('true for fewer than 12 distinct months', () => {
		const points = Array.from({ length: 6 }, (_, i) =>
			point({ point_date: `2026-0${i + 1}-15` })
		);
		expect(isSparseHistory(points)).toBe(true);
	});

	it('a DAILY series over 2 sparse months is still sparse — many rows must not read as much history', () => {
		const points: NavSeriesPoint[] = [];
		for (let d = 1; d <= 28; d++) {
			points.push(point({ point_date: `2026-01-${String(d).padStart(2, '0')}` }));
			points.push(point({ point_date: `2026-02-${String(d).padStart(2, '0')}` }));
		}
		expect(points.length).toBeGreaterThan(50);
		expect(isSparseHistory(points)).toBe(true);
	});

	it('false for an empty series — empty is the chart-placeholder `empty` state, not `sparse`', () => {
		expect(isSparseHistory([])).toBe(false);
	});

	it('respects a custom monthsThreshold', () => {
		const points = Array.from({ length: 3 }, (_, i) =>
			point({ point_date: `2026-0${i + 1}-15` })
		);
		expect(isSparseHistory(points, 2)).toBe(false);
		expect(isSparseHistory(points, 4)).toBe(true);
	});
});
