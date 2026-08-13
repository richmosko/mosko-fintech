// nav-series-params.test.ts — unit coverage for the §2.1.2.d chart's
// server-side query-param Zod boundary (SELF-220). Proves: every field is
// independently optional, `.strict()` rejects an unrecognized key, the
// granularity enum is exactly 062/067's imported vocabulary and rejects
// anything else, the date guard rejects a calendar-impossible date the same
// way account.ts's isoDate() does, and the inverted-range refine mirrors
// Frontend's client schema (same rejection, same message).

import { describe, it, expect } from 'vitest';
import { navSeriesParamsSchema } from './nav-series-params';
import { NAV_SERIES_GRANULARITIES } from '$lib/nav-series';

describe('navSeriesParamsSchema', () => {
	it('accepts an empty object — every field is independently optional', () => {
		const result = navSeriesParamsSchema.safeParse({});
		expect(result.success).toBe(true);
	});

	it('accepts a well-formed full set', () => {
		const result = navSeriesParamsSchema.safeParse({
			granularity: 'weekly',
			start: '2020-01-01',
			end: '2025-01-01'
		});
		expect(result.success).toBe(true);
		if (result.success) {
			expect(result.data).toEqual({ granularity: 'weekly', start: '2020-01-01', end: '2025-01-01' });
		}
	});

	it('accepts a partial set (e.g. only start) — no field requires its siblings', () => {
		const result = navSeriesParamsSchema.safeParse({ start: '2020-01-01' });
		expect(result.success).toBe(true);
	});

	for (const g of NAV_SERIES_GRANULARITIES) {
		it(`accepts granularity=${g} (the imported 062/067 vocabulary)`, () => {
			const result = navSeriesParamsSchema.safeParse({ granularity: g });
			expect(result.success).toBe(true);
		});
	}

	it('rejects a granularity value outside the vocabulary', () => {
		const result = navSeriesParamsSchema.safeParse({ granularity: 'yearly' });
		expect(result.success).toBe(false);
	});

	it('rejects an UNRECOGNIZED key — the .strict() mass-assignment fence (Lock 14 mod #2)', () => {
		const result = navSeriesParamsSchema.safeParse({
			granularity: 'monthly',
			bogus: 'anything'
		});
		expect(result.success).toBe(false);
	});

	it('rejects a calendar-impossible date (2026-02-31) the same way account.ts does', () => {
		const result = navSeriesParamsSchema.safeParse({ start: '2026-02-31' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-YYYY-MM-DD date shape', () => {
		const result = navSeriesParamsSchema.safeParse({ end: '01/31/2026' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-string value for a date field (type-confusion fence, Lock 14 mod #1)', () => {
		// URLSearchParams always hands back strings, but the schema must not rely on that alone —
		// Object.fromEntries on a crafted body could still carry a non-string, and .strict() plus
		// per-field validation is what actually closes it, not the caller's transport shape.
		const result = navSeriesParamsSchema.safeParse({ start: 20260101 });
		expect(result.success).toBe(false);
	});

	it('rejects an inverted range (start after end) — mirrors the client schema exactly', () => {
		const result = navSeriesParamsSchema.safeParse({ start: '2025-01-01', end: '2020-01-01' });
		expect(result.success).toBe(false);
		if (!result.success) {
			expect(result.error.issues[0].message).toBe('Start date must not be after end date.');
			expect(result.error.issues[0].path).toEqual(['start']);
		}
	});

	it('accepts start === end (a single-day range is not inverted)', () => {
		const result = navSeriesParamsSchema.safeParse({ start: '2020-01-01', end: '2020-01-01' });
		expect(result.success).toBe(true);
	});

	it('an inverted range with only ONE side supplied is not reachable — no refine failure', () => {
		// The refine's own guard (!(v.start && v.end) || ...) short-circuits when either half is
		// absent, matching Frontend's client mirror: a partial range can't be "inverted" by
		// definition, and the missing half is filled in later by resolveNavSeriesWindow, not here.
		const result = navSeriesParamsSchema.safeParse({ start: '2099-01-01' });
		expect(result.success).toBe(true);
	});
});
