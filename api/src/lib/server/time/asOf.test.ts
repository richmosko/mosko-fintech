// asOf.test.ts — SELF-238 coverage for `userSuppliedAsOf`, the second production factory for
// the `ZoneResolvedAsOf` brand. Behavioral coverage; the shape/containment invariants (which
// files may cast to the brand, where `unsafeAsOfForTest` may be imported from) are QA-owned in
// asOfBrand.invariant.test.ts and are not duplicated here.

import { describe, it, expect } from 'vitest';
import { userSuppliedAsOf, serverTodayAsOf } from './asOf';

describe('userSuppliedAsOf', () => {
	it('accepts a well-formed real calendar date and returns it unchanged (structurally a string)', () => {
		expect(userSuppliedAsOf('2026-07-20')).toBe('2026-07-20');
	});

	it('accepts leap-day and month-end boundaries', () => {
		expect(userSuppliedAsOf('2024-02-29')).toBe('2024-02-29'); // 2024 is a leap year
		expect(userSuppliedAsOf('2026-01-31')).toBe('2026-01-31');
	});

	it('rejects a non-existent calendar date (e.g. Feb 31, non-leap Feb 29)', () => {
		expect(() => userSuppliedAsOf('2026-02-31')).toThrow(/real calendar date/);
		expect(() => userSuppliedAsOf('2026-02-29')).toThrow(/real calendar date/); // 2026 is not a leap year
	});

	it('rejects malformed shapes without ever reaching Date parsing', () => {
		expect(() => userSuppliedAsOf('2026/07/20')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('07-20-2026')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('2026-7-20')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('')).toThrow(/YYYY-MM-DD/);
		expect(() => userSuppliedAsOf('not-a-date')).toThrow(/YYYY-MM-DD/);
	});

	it('rejects the adversarial-battery-shaped garbage a Zod bypass could still hand it', () => {
		expect(() => userSuppliedAsOf('NaN')).toThrow();
		expect(() => userSuppliedAsOf('Infinity')).toThrow();
		expect(() => userSuppliedAsOf('2026-07-20T00:00:00Z')).toThrow(); // timestamp, not a bare date
		expect(() => userSuppliedAsOf('9'.repeat(1000))).toThrow();
	});

	it('is a DIFFERENT production path from serverTodayAsOf, both landing on the same branded type', () => {
		// Structural equality is not the point here (they mint different dates); the point is both
		// compile as ZoneResolvedAsOf without a cast at either call site — i.e. this file itself
		// never writes `as ZoneResolvedAsOf` (asOfBrand.invariant.test.ts is the containment proof).
		const today = serverTodayAsOf();
		const chosen = userSuppliedAsOf('2020-01-01');
		expect(typeof today).toBe('string');
		expect(typeof chosen).toBe('string');
	});
});
