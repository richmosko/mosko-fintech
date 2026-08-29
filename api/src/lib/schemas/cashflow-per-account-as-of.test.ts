// cashflow-per-account-as-of.test.ts — SELF-254 AC4 unit coverage for the client-side as-of
// mirror. Pure Zod — no DOM, no server import (this file lives in $lib/schemas, browser-safe).

import { describe, it, expect } from 'vitest';
import { cashflowPerAccountAsOfSchema } from './cashflow-per-account-as-of';

const FLOOR = '2015-12-01';
const MAX = '2026-08-27';

describe('cashflowPerAccountAsOfSchema — bounds are INJECTED, both inclusive', () => {
	const schema = cashflowPerAccountAsOfSchema(FLOOR, MAX);

	it('accepts an absent as_of (optional)', () => {
		expect(schema.safeParse({}).success).toBe(true);
	});

	it('accepts exactly the floor (inclusive)', () => {
		expect(schema.safeParse({ as_of: FLOOR }).success).toBe(true);
	});

	it('accepts exactly the ceiling (inclusive) — the off-by-one that would refuse today', () => {
		expect(schema.safeParse({ as_of: MAX }).success).toBe(true);
	});

	it('rejects one day before the floor', () => {
		const result = schema.safeParse({ as_of: '2015-11-30' });
		expect(result.success).toBe(false);
	});

	it('rejects one day after the ceiling', () => {
		const result = schema.safeParse({ as_of: '2026-08-28' });
		expect(result.success).toBe(false);
	});

	it('rejects a malformed date shape', () => {
		expect(schema.safeParse({ as_of: '08/27/2026' }).success).toBe(false);
	});

	it('rejects a non-real calendar date', () => {
		expect(schema.safeParse({ as_of: '2026-02-31' }).success).toBe(false);
	});

	it('rejects an unrecognized key (.strict())', () => {
		expect(schema.safeParse({ as_of: MAX, bogus: '1' }).success).toBe(false);
	});
});

describe('cashflowPerAccountAsOfSchema — the ceiling and floor are PARAMETERS, never embedded', () => {
	it('a value valid under one maxAsOf can be rejected under an earlier one', () => {
		const narrow = cashflowPerAccountAsOfSchema(FLOOR, '2026-01-01');
		expect(narrow.safeParse({ as_of: '2026-06-01' }).success).toBe(false);
	});

	it('a value valid under one floor can be rejected under a later one', () => {
		const narrowed = cashflowPerAccountAsOfSchema('2020-01-01', MAX);
		expect(narrowed.safeParse({ as_of: '2016-01-01' }).success).toBe(false);
	});
});
