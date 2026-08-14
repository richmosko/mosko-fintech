// nav-series-params.test.ts — unit coverage for the §2.1.2.d chart's
// server-side query-param Zod boundary (SELF-220), including the `chart_`
// namespace fix (F/CTO-ratified 2026-08-13, Sec's param-fence finding).
// Proves: every field is independently optional, `.strict()` rejects an
// unrecognized key WITHIN the namespace, the granularity enum is exactly
// 062/067's imported vocabulary and rejects anything else, the date guard
// rejects a calendar-impossible date the same way account.ts's isoDate()
// does, the inverted-range refine mirrors Frontend's client schema (same
// message, same `path: ['chart_start']`), and `extractNamespacedParams`
// implements the two mechanical steps correctly: a key OUTSIDE the
// namespace is excluded before the schema ever sees it (proving the fix for
// the original page-scoped-blast-radius defect), while a key INSIDE the
// namespace the schema doesn't recognize still reaches `.strict()` and is
// still rejected (proving this is NOT the forbidden "pick-then-parse" shape
// that would hide an unrecognized in-namespace key from the fence).

import { describe, it, expect } from 'vitest';
import {
	navSeriesParamsSchema,
	extractNamespacedParams,
	NAV_SERIES_PARAM_PREFIX
} from './nav-series-params';
import { NAV_SERIES_GRANULARITIES } from '$lib/nav-series';

describe('navSeriesParamsSchema (chart_-prefixed fields)', () => {
	it('accepts an empty object — every field is independently optional', () => {
		const result = navSeriesParamsSchema.safeParse({});
		expect(result.success).toBe(true);
	});

	it('accepts a well-formed full set', () => {
		const result = navSeriesParamsSchema.safeParse({
			chart_granularity: 'weekly',
			chart_start: '2020-01-01',
			chart_end: '2025-01-01'
		});
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data).toEqual({
				chart_granularity: 'weekly',
				chart_start: '2020-01-01',
				chart_end: '2025-01-01'
			});
		}
	});

	it('accepts a partial set (e.g. only chart_start) — no field requires its siblings', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_start: '2020-01-01' });
		expect(result.success).toBe(true);
	});

	for (const g of NAV_SERIES_GRANULARITIES) {
		it(`accepts chart_granularity=${g} (the imported 062/067 vocabulary)`, () => {
			const result = navSeriesParamsSchema.safeParse({ chart_granularity: g });
			expect(result.success).toBe(true);
		});
	}

	it('rejects a chart_granularity value outside the vocabulary', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_granularity: 'yearly' });
		expect(result.success).toBe(false);
	});

	it('rejects an UNRECOGNIZED key — the .strict() mass-assignment fence (Lock 14 mod #2)', () => {
		const result = navSeriesParamsSchema.safeParse({
			chart_granularity: 'monthly',
			chart_bogus: 'anything'
		});
		expect(result.success).toBe(false);
	});

	it('rejects the OLD unprefixed field names (proves the rename is real, not additive)', () => {
		const result = navSeriesParamsSchema.safeParse({ granularity: 'monthly' });
		expect(result.success).toBe(false);
	});

	it('rejects a calendar-impossible date (2026-02-31) the same way account.ts does', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_start: '2026-02-31' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-YYYY-MM-DD date shape', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_end: '01/31/2026' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-string value for a date field (type-confusion fence, Lock 14 mod #1)', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_start: 20260101 });
		expect(result.success).toBe(false);
	});

	it('rejects an inverted range (start after end) — mirrors the client schema exactly', () => {
		const result = navSeriesParamsSchema.safeParse({
			chart_start: '2025-01-01',
			chart_end: '2020-01-01'
		});
		expect(result.success).toBe(false);
		if (!result.success) {
			expect(result.error.issues[0].message).toBe('Start date must not be after end date.');
			expect(result.error.issues[0].path).toEqual(['chart_start']);
		}
	});

	it('accepts chart_start === chart_end (a single-day range is not inverted)', () => {
		const result = navSeriesParamsSchema.safeParse({
			chart_start: '2020-01-01',
			chart_end: '2020-01-01'
		});
		expect(result.success).toBe(true);
	});

	it('an inverted range with only ONE side supplied is not reachable — no refine failure', () => {
		const result = navSeriesParamsSchema.safeParse({ chart_start: '2099-01-01' });
		expect(result.success).toBe(true);
	});
});

describe('extractNamespacedParams', () => {
	it('extracts only chart_-prefixed keys, preserving the prefix', () => {
		const search = new URLSearchParams(
			'chart_granularity=monthly&chart_start=2020-01-01&utm_source=newsletter'
		);
		const extracted = extractNamespacedParams(search, NAV_SERIES_PARAM_PREFIX);
		expect(extracted).toEqual({
			chart_granularity: 'monthly',
			chart_start: '2020-01-01'
		});
		expect(extracted).not.toHaveProperty('utm_source');
	});

	it('a non-namespaced key is excluded entirely — never presented to the schema at all', () => {
		const search = new URLSearchParams('utm_source=newsletter&ref=email');
		const extracted = extractNamespacedParams(search, NAV_SERIES_PARAM_PREFIX);
		expect(extracted).toEqual({});
		// And the schema accepts the resulting empty object — an unrelated page
		// param must never disable the chart. This is the actual fix under test.
		const result = navSeriesParamsSchema.safeParse(extracted);
		expect(result.success).toBe(true);
	});

	it('a chart_-prefixed UNRECOGNIZED key still reaches .strict() and is still rejected — NOT pick-then-parse', () => {
		const search = new URLSearchParams('chart_granularity=monthly&chart_bogus=anything');
		const extracted = extractNamespacedParams(search, NAV_SERIES_PARAM_PREFIX);
		// The forbidden shape would filter to ONLY the three known keys here,
		// silently dropping chart_bogus before .strict() ever saw it. This
		// asserts the opposite: chart_bogus survives extraction...
		expect(extracted).toHaveProperty('chart_bogus');
		// ...and .strict() rejects it, because it's genuinely still there.
		const result = navSeriesParamsSchema.safeParse(extracted);
		expect(result.success).toBe(false);
	});

	it('returns {} for an empty search', () => {
		const extracted = extractNamespacedParams(new URLSearchParams(''), NAV_SERIES_PARAM_PREFIX);
		expect(extracted).toEqual({});
	});

	it('a key that merely CONTAINS the prefix, not starting with it, is excluded', () => {
		// e.g. "not_chart_granularity" must not match — startsWith, not includes.
		const search = new URLSearchParams('not_chart_granularity=monthly');
		const extracted = extractNamespacedParams(search, NAV_SERIES_PARAM_PREFIX);
		expect(extracted).toEqual({});
	});
});
