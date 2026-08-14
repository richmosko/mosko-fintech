// nav-series-params.test.ts — unit battery for the client-side NAV-chart URL-param mirror
// (SELF-220). Proves the schema stays as strict as its posture claims: unknown keys WITHIN the
// chart_ namespace rejected (.strict()), bad enum/date values rejected, inverted ranges
// rejected, a malformed URL degrades to {} (the surface's default) rather than throwing — AND
// (the F/CTO-ratified 2026-08-13 fix) that a stray param OUTSIDE the namespace never disables
// the chart, while an unknown key INSIDE it still trips the fence.

import { describe, it, expect } from 'vitest';
import { navSeriesParamsSchema, parseNavSeriesParams, NAV_SERIES_PARAM_PREFIX } from './nav-series-params';

describe('NAV_SERIES_PARAM_PREFIX', () => {
	it('is the chart_ namespace', () => {
		expect(NAV_SERIES_PARAM_PREFIX).toBe('chart_');
	});
});

describe('navSeriesParamsSchema — well-formed input', () => {
	it('accepts all-absent (the default-window case)', () => {
		expect(navSeriesParamsSchema.safeParse({}).success).toBe(true);
	});

	it('accepts a well-formed granularity + non-inverted range', () => {
		const r = navSeriesParamsSchema.safeParse({
			chart_granularity: 'weekly',
			chart_start: '2026-01-01',
			chart_end: '2026-06-30'
		});
		expect(r.success).toBe(true);
	});

	it('accepts start === end (a single-day zoom)', () => {
		expect(
			navSeriesParamsSchema.safeParse({ chart_start: '2026-01-01', chart_end: '2026-01-01' })
				.success
		).toBe(true);
	});
});

describe('navSeriesParamsSchema — rejects, mirroring 062s posture', () => {
	it('rejects a granularity outside {monthly,weekly,daily}', () => {
		expect(navSeriesParamsSchema.safeParse({ chart_granularity: 'yearly' }).success).toBe(false);
	});

	it('rejects a non-calendar date (2026-02-31)', () => {
		expect(navSeriesParamsSchema.safeParse({ chart_start: '2026-02-31' }).success).toBe(false);
	});

	it('rejects a malformed date string', () => {
		expect(navSeriesParamsSchema.safeParse({ chart_start: '01/01/2026' }).success).toBe(false);
	});

	it('rejects an inverted range (start after end)', () => {
		expect(
			navSeriesParamsSchema.safeParse({ chart_start: '2026-06-30', chart_end: '2026-01-01' })
				.success
		).toBe(false);
	});

	it('rejects an unknown key WITHIN the chart_ namespace (.strict() — the mass-assignment fence, still live inside the namespace)', () => {
		expect(
			navSeriesParamsSchema.safeParse({ chart_granularity: 'monthly', chart_extra: 'x' }).success
		).toBe(false);
	});

	it('rejects a bare (unprefixed) key — the old field names are no longer recognized at all', () => {
		expect(navSeriesParamsSchema.safeParse({ granularity: 'monthly' }).success).toBe(false);
	});
});

describe('parseNavSeriesParams — degrades a malformed URL to the default, never throws', () => {
	it('parses a well-formed query string', () => {
		const search = new URLSearchParams(
			'chart_granularity=daily&chart_start=2026-01-01&chart_end=2026-03-31'
		);
		expect(parseNavSeriesParams(search)).toEqual({
			chart_granularity: 'daily',
			chart_start: '2026-01-01',
			chart_end: '2026-03-31'
		});
	});

	it('degrades an invalid granularity to {} rather than dropping only that field', () => {
		const search = new URLSearchParams(
			'chart_granularity=yearly&chart_start=2026-01-01&chart_end=2026-03-31'
		);
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('degrades an inverted range to {} rather than swapping/clamping it', () => {
		const search = new URLSearchParams('chart_start=2026-06-30&chart_end=2026-01-01');
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('degrades a hand-edited garbage query string to {} without throwing', () => {
		const search = new URLSearchParams('chart_granularity=<script>&chart_start=nope');
		expect(() => parseNavSeriesParams(search)).not.toThrow();
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('returns {} for an empty query string', () => {
		expect(parseNavSeriesParams(new URLSearchParams(''))).toEqual({});
	});

	// ⭐ F/CTO-ratified 2026-08-13 (Sec's param-fence finding, option A) — the two properties
	// the fix exists to prove. Before this fix, parseNavSeriesParams/navSeriesParamsSchema
	// strict-parsed the WHOLE page's query string, so a completely unrelated param anywhere on
	// `/` tripped the unknown-key rejection and disabled the chart (page-scoped blast radius for
	// chart-scoped input). The namespace fixes this WITHOUT loosening the fence itself.
	it('⭐ a stray param OUTSIDE the chart_ namespace does NOT disable the chart — the exact defect this fix closes', () => {
		const search = new URLSearchParams(
			'utm_source=newsletter&chart_granularity=daily&chart_start=2026-01-01&chart_end=2026-03-31'
		);
		expect(parseNavSeriesParams(search)).toEqual({
			chart_granularity: 'daily',
			chart_start: '2026-01-01',
			chart_end: '2026-03-31'
		});
	});

	it('a totally unrelated query string (no chart_ keys at all) degrades cleanly to {} — the default window, not an error', () => {
		const search = new URLSearchParams('utm_source=newsletter&ref=email&fbclid=abc123');
		expect(parseNavSeriesParams(search)).toEqual({});
	});

	it('⭐ an unknown key INSIDE the chart_ namespace still trips the fence — the namespace narrows scope, not strictness', () => {
		const search = new URLSearchParams(
			'chart_granularity=monthly&chart_bogus=anything&utm_source=newsletter'
		);
		expect(parseNavSeriesParams(search)).toEqual({});
	});
});
