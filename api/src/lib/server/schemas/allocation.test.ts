// allocation.test.ts — SELF-238/240 coverage for the shared as_of Zod schema + resolution
// function (AC8/AC6).

import { describe, it, expect } from 'vitest';
import { allocationAsOfSchema, resolveAllocationAsOf } from './allocation';

describe('allocationAsOfSchema', () => {
	it('accepts an absent as_of (optional)', () => {
		const r = allocationAsOfSchema.safeParse({});
		expect(r.success).toBe(true);
	});

	it('accepts a well-formed real calendar date', () => {
		const r = allocationAsOfSchema.safeParse({ as_of: '2026-07-20' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.as_of).toBe('2026-07-20');
	});

	it('rejects a non-existent calendar date', () => {
		expect(allocationAsOfSchema.safeParse({ as_of: '2026-02-31' }).success).toBe(false);
	});

	it('rejects a malformed date shape (no coercion)', () => {
		expect(allocationAsOfSchema.safeParse({ as_of: '07/20/2026' }).success).toBe(false);
		expect(allocationAsOfSchema.safeParse({ as_of: 20260720 }).success).toBe(false);
	});

	it('rejects the numeric-battery-adjacent garbage the AC names', () => {
		expect(allocationAsOfSchema.safeParse({ as_of: 'NaN' }).success).toBe(false);
		expect(allocationAsOfSchema.safeParse({ as_of: 'Infinity' }).success).toBe(false);
		expect(allocationAsOfSchema.safeParse({ as_of: '9'.repeat(1000) }).success).toBe(false);
	});

	it('AC8(b) mass-assignment: .strict() rejects any unrecognized key', () => {
		expect(allocationAsOfSchema.safeParse({ as_of: '2026-07-20', users_id: 'x' }).success).toBe(false);
		expect(allocationAsOfSchema.safeParse({ p_as_of: '2026-07-20' }).success).toBe(false); // wrong key name too
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
