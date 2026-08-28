// cashflowTarget.test.ts — unit coverage for the pfin.cashflow_target read helper (SELF-252
// read side / AC2, AC9). Pure-TS server test (node env per vitest.config). Mocks the
// supabase-js chain:
//   .schema('pfin').from('cashflow_target').select('income_target_annual, expense_target_monthly').maybeSingle()
//   → { data, error }
//
// Proves: a present row is returned unmodified; an absent row (never provisioned) and a
// returned error both degrade to the SAME "unset" shape ({ income_target_annual: null,
// expense_target_monthly: null }) — matching 090's own READER OBLIGATION that row-absent and
// one-row-of-NULLs must never carry different meanings to a consumer.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadCashflowTarget } from './cashflowTarget';

const UNSET = { income_target_annual: null, expense_target_monthly: null };

/** read-path stub: .schema().from().select().maybeSingle() → { data, error }. */
function makeReadSupabase(data: unknown, error: { message: string } | null = null) {
	const maybeSingle = vi.fn(async () => ({ data, error }));
	const select = vi.fn(() => ({ maybeSingle }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, maybeSingle, select, from, schema };
}

describe('loadCashflowTarget', () => {
	it('returns the stored row unmodified when present', async () => {
		const row = { income_target_annual: 120000, expense_target_monthly: 4000 };
		const { client, schema, from, select } = makeReadSupabase(row);
		await expect(loadCashflowTarget(client)).resolves.toEqual(row);
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('cashflow_target');
		expect(select).toHaveBeenCalledWith('income_target_annual, expense_target_monthly');
	});

	it('returns a partially-set row unmodified (one target set, one NULL)', async () => {
		const row = { income_target_annual: 120000, expense_target_monthly: null };
		const { client } = makeReadSupabase(row);
		await expect(loadCashflowTarget(client)).resolves.toEqual(row);
	});

	it('row-absent (never provisioned) → UNSET shape, RLS scoping is implicit via maybeSingle()', async () => {
		const { client } = makeReadSupabase(null);
		await expect(loadCashflowTarget(client)).resolves.toEqual(UNSET);
	});

	it('a one-row-of-NULLs read is indistinguishable from row-absent to the caller (both → UNSET-shaped)', async () => {
		const { client } = makeReadSupabase({ income_target_annual: null, expense_target_monthly: null });
		await expect(loadCashflowTarget(client)).resolves.toEqual(UNSET);
	});

	it('read error → UNSET (fail-soft, logs, never throws)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeReadSupabase(null, { message: 'boom' });
		await expect(loadCashflowTarget(client)).resolves.toEqual(UNSET);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('thrown chain → UNSET (fail-soft)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(loadCashflowTarget(client)).resolves.toEqual(UNSET);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});
