// navHistory.test.ts — unit coverage for the §2.1.2.c chart's query-param
// Zod boundary (SELF-220). Proves: every field is independently optional,
// `.strict()` rejects an unrecognized key, the granularity enum is exactly
// the 062/067 vocabulary and rejects anything else, and the date guard
// rejects a calendar-impossible date the same way account.ts's isoDate() does.

import { describe, it, expect } from 'vitest';
import { navHistoryParamsSchema, NAV_HISTORY_GRANULARITIES } from './navHistory';

describe('navHistoryParamsSchema', () => {
	it('accepts an empty object — every field is independently optional', () => {
		const result = navHistoryParamsSchema.safeParse({});
		expect(result.success).toBe(true);
	});

	it('accepts a well-formed full set', () => {
		const result = navHistoryParamsSchema.safeParse({
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
		const result = navHistoryParamsSchema.safeParse({ start: '2020-01-01' });
		expect(result.success).toBe(true);
	});

	for (const g of NAV_HISTORY_GRANULARITIES) {
		it(`accepts granularity=${g} (the exact 062/067 vocabulary)`, () => {
			const result = navHistoryParamsSchema.safeParse({ granularity: g });
			expect(result.success).toBe(true);
		});
	}

	it('rejects a granularity value outside the vocabulary', () => {
		const result = navHistoryParamsSchema.safeParse({ granularity: 'yearly' });
		expect(result.success).toBe(false);
	});

	it('rejects an UNRECOGNIZED key — the .strict() mass-assignment fence (Lock 14 mod #2)', () => {
		const result = navHistoryParamsSchema.safeParse({
			granularity: 'monthly',
			bogus: 'anything'
		});
		expect(result.success).toBe(false);
	});

	it('rejects a calendar-impossible date (2026-02-31) the same way account.ts does', () => {
		const result = navHistoryParamsSchema.safeParse({ start: '2026-02-31' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-YYYY-MM-DD date shape', () => {
		const result = navHistoryParamsSchema.safeParse({ end: '01/31/2026' });
		expect(result.success).toBe(false);
	});

	it('rejects a non-string value for a date field (type-confusion fence, Lock 14 mod #1)', () => {
		// URLSearchParams always hands back strings, but the schema must not rely on that alone —
		// Object.fromEntries on a crafted body could still carry a non-string, and .strict() plus
		// per-field validation is what actually closes it, not the caller's transport shape.
		const result = navHistoryParamsSchema.safeParse({ start: 20260101 });
		expect(result.success).toBe(false);
	});
});
