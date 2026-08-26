// asOf.test.ts — Backend's own unit coverage for the module's core contract (SELF-247 AC1-4).
// Re-pointed from allocation.test.ts (SELF-238/240 AC8/AC6's original coverage, unchanged in
// intent — the schema's absent/malformed/mass-assignment behavior is identical after the D-6
// move) plus new floor/ceiling boundary legs for the AC4 range bound this ticket adds.
//
// NOT the adversarial battery — QA owns that (route-level watcher on the merged §2.2 route per
// sitting item 12, "reject pre-floor + future" + both-inclusive-boundaries; D-9's created-on-D
// leg; the §7.25 item-3 coverage precedent). This file only proves the schema factory itself
// behaves per its own contract in isolation.

import { describe, it, expect } from 'vitest';
import { asOfSchema, resolveAllocationAsOf, AS_OF_FLOOR } from './asOf';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

// A fixed, far-future ceiling for tests that don't care about the ceiling itself — every date
// literal below predates it comfortably. Never `new Date()` — see asOf.ts's own header on why.
const FAR_CEILING = unsafeAsOfForTest('2099-12-31');

describe('asOfSchema', () => {
	it('accepts an absent as_of (optional)', () => {
		const r = asOfSchema(FAR_CEILING).safeParse({});
		expect(r.success).toBe(true);
	});

	it('accepts a well-formed real calendar date within range', () => {
		const r = asOfSchema(FAR_CEILING).safeParse({ as_of: '2026-07-20' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.as_of).toBe('2026-07-20');
	});

	it('rejects a non-existent calendar date', () => {
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: '2026-02-31' }).success).toBe(false);
	});

	it('rejects a malformed date shape (no coercion)', () => {
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: '07/20/2026' }).success).toBe(false);
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: 20260720 }).success).toBe(false);
	});

	it('rejects the numeric-battery-adjacent garbage the AC names', () => {
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: 'NaN' }).success).toBe(false);
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: 'Infinity' }).success).toBe(false);
		expect(asOfSchema(FAR_CEILING).safeParse({ as_of: '9'.repeat(1000) }).success).toBe(false);
	});

	it('AC8(b) mass-assignment: .strict() rejects any unrecognized key', () => {
		expect(
			asOfSchema(FAR_CEILING).safeParse({ as_of: '2026-07-20', users_id: 'x' }).success
		).toBe(false);
		expect(asOfSchema(FAR_CEILING).safeParse({ p_as_of: '2026-07-20' }).success).toBe(false); // wrong key name too (AC9: p_as_of is NOT this surface's convention)
	});

	describe('AC4 — FLOOR <= as_of <= D, both bounds inclusive', () => {
		it('accepts the floor date itself (inclusive lower bound)', () => {
			expect(asOfSchema(FAR_CEILING).safeParse({ as_of: AS_OF_FLOOR }).success).toBe(true);
		});

		it('rejects one day before the floor', () => {
			const r = asOfSchema(FAR_CEILING).safeParse({ as_of: '2015-11-30' });
			expect(r.success).toBe(false);
			if (!r.success) expect(r.error.issues.some((i) => i.path[0] === 'as_of')).toBe(true);
		});

		it('accepts the ceiling date itself (inclusive upper bound)', () => {
			const ceiling = unsafeAsOfForTest('2026-08-25');
			expect(asOfSchema(ceiling).safeParse({ as_of: '2026-08-25' }).success).toBe(true);
		});

		it('rejects one day after the ceiling', () => {
			const ceiling = unsafeAsOfForTest('2026-08-25');
			const r = asOfSchema(ceiling).safeParse({ as_of: '2026-08-26' });
			expect(r.success).toBe(false);
			if (!r.success) expect(r.error.issues.some((i) => i.path[0] === 'as_of')).toBe(true);
		});

		it('the ceiling is INJECTED per call, not fixed — the same date validates differently against two different ceilings', () => {
			const tightCeiling = unsafeAsOfForTest('2020-01-01');
			expect(asOfSchema(tightCeiling).safeParse({ as_of: '2020-06-15' }).success).toBe(false);
			expect(asOfSchema(FAR_CEILING).safeParse({ as_of: '2020-06-15' }).success).toBe(true);
		});
	});
});

describe('resolveAllocationAsOf', () => {
	it('resolves an absent as_of to today', () => {
		const resolved = resolveAllocationAsOf({});
		// serverTodayAsOf() is UTC-today; just prove it's a well-formed YYYY-MM-DD, not a fixed date.
		expect(resolved).toMatch(/^\d{4}-\d{2}-\d{2}$/);
	});

	it('resolves a present as_of via userSuppliedAsOf (UTC), unchanged', () => {
		expect(resolveAllocationAsOf({ as_of: '2020-01-01' })).toBe('2020-01-01');
	});
});
