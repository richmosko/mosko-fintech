// cashflow-target.test.ts — verifies the CLIENT Zod mirror (schemas/cashflow-target.ts)
// tracks the server schema's posture: omitted vs `null` vs number stay distinguishable,
// `.strict()` rejects mass-assignment, and a negative amount is refused (the shared
// battery has no sign stance for this shape; the refine is owed here, mirroring the
// server's `nonNegativeCurrencyAmount`).

import { describe, it, expect } from 'vitest';
import { cashflowTargetUpsertSchema } from './cashflow-target';

describe('cashflowTargetUpsertSchema', () => {
	it('an omitted key parses to undefined (leave alone)', () => {
		const r = cashflowTargetUpsertSchema.safeParse({ income_annual: 1000 });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.expense_monthly).toBeUndefined();
	});

	it('an explicit null parses to null (clear)', () => {
		const r = cashflowTargetUpsertSchema.safeParse({ income_annual: null, expense_monthly: null });
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.income_annual).toBeNull();
			expect(r.data.expense_monthly).toBeNull();
		}
	});

	it('a valid number parses through', () => {
		const r = cashflowTargetUpsertSchema.safeParse({ income_annual: 90000.5 });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.income_annual).toBe(90000.5);
	});

	it('rejects a negative amount (no sign stance in the shared battery — refined here)', () => {
		const r = cashflowTargetUpsertSchema.safeParse({ income_annual: -1 });
		expect(r.success).toBe(false);
	});

	it('rejects NaN/Infinity/scientific-notation/currency-string shapes', () => {
		for (const bad of ['NaN', 'Infinity', '1e21', '$1,000']) {
			const r = cashflowTargetUpsertSchema.safeParse({ income_annual: bad });
			expect(r.success).toBe(false);
		}
	});

	it('.strict() rejects mass-assignment of a stray field (e.g. users_id)', () => {
		const r = cashflowTargetUpsertSchema.safeParse({ income_annual: 1000, users_id: 'abc' });
		expect(r.success).toBe(false);
	});

	it('an empty object is valid (both fields omitted — a legal no-op payload shape)', () => {
		const r = cashflowTargetUpsertSchema.safeParse({});
		expect(r.success).toBe(true);
	});
});
