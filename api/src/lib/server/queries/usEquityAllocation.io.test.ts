// usEquityAllocation.io.test.ts — SELF-240 I/O-wiring coverage for loadUsEquityAllocation,
// separate from the pure-core compute tests in usEquityAllocation.test.ts. Mocks the chain:
//   .schema('pfin').rpc('fn_subcat_market_value', {...})              — via subcatMarketValue
//   .schema('pfin').from('planning_target').select(...)               — via subcatMarketValue
//   .schema('pfin').from('user_taxonomy').select(...).eq(...).in(...) — this module's own read
//
// Proves: the taxonomy read is scoped to domain=asset AND the twelve US-equity labels (AC1/AC2);
// a successful round trip reaches the compute core with the right inputs; a failure at ANY of the
// three reads degrades to ok:false.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

function makeSupabase(opts: {
	rpcData?: unknown;
	rpcError?: { message: string } | null;
	targetData?: unknown;
	targetError?: { message: string } | null;
	taxonomyData?: unknown;
	taxonomyError?: { message: string } | null;
}) {
	const rpc = vi.fn(async () => ({ data: opts.rpcData ?? [], error: opts.rpcError ?? null }));
	const targetSelect = vi.fn(async () => ({ data: opts.targetData ?? [], error: opts.targetError ?? null }));
	const taxonomyIn = vi.fn(async () => ({ data: opts.taxonomyData ?? [], error: opts.taxonomyError ?? null }));
	const taxonomyEq = vi.fn(() => ({ in: taxonomyIn }));
	const taxonomySelect = vi.fn(() => ({ eq: taxonomyEq }));

	const from = vi.fn((table: string) => {
		if (table === 'planning_target') return { select: targetSelect };
		if (table === 'user_taxonomy') return { select: taxonomySelect };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, from, targetSelect, taxonomySelect, taxonomyEq, taxonomyIn };
}

describe('loadUsEquityAllocation — I/O wiring', () => {
	it('a well-formed round trip reaches the compute core with matching values', async () => {
		const { client } = makeSupabase({
			rpcData: [
				{ sub_cat_id: 6, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: 300 }
			],
			targetData: [{ sub_cat_id: 6, target_percent: 10 }],
			taxonomyData: [{ id: 6, sub_cat: 'US-06-Financials' }]
		});
		const result = await loadUsEquityAllocation(client, AS_OF);
		expect(result.ok).toBe(true);
		expect(result.data?.total.dollar_alloc).toBe(300);
		const us06 = result.data?.rows.find((r) => r.sub_cat === 'US-06-Financials');
		expect(us06).toMatchObject({ dollar_alloc: 300, pct_target: 100 }); // sole target → 100% renormalized
	});

	it('the user_taxonomy read is scoped to domain=asset AND the twelve US-equity labels (AC1/AC2)', async () => {
		const { client, taxonomySelect, taxonomyEq, taxonomyIn } = makeSupabase({});
		await loadUsEquityAllocation(client, AS_OF);
		expect(taxonomySelect).toHaveBeenCalledWith('id, sub_cat');
		expect(taxonomyEq).toHaveBeenCalledWith('domain', 'asset');
		expect(taxonomyIn).toHaveBeenCalledWith('sub_cat', US_EQUITY_SUB_CATS);
	});

	it('degrades to ok:false when the shared substrate read fails (RPC error)', async () => {
		const { client } = makeSupabase({ rpcError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when the shared substrate read fails (planning_target error)', async () => {
		const { client } = makeSupabase({ targetError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});

	it("degrades to ok:false when THIS module's own user_taxonomy read fails", async () => {
		const { client } = makeSupabase({ taxonomyError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});
});
