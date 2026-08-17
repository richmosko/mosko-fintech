// subcatMarketValue.test.ts — SELF-238 I/O coverage for the shared 076-consumer join logic.
// Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_subcat_market_value', { p_as_of, p_include_real_estate }) → {data,error}
//   .schema('pfin').from('planning_target').select(...)                              → {data,error}
//
// Proves: p_include_real_estate is ALWAYS false (never parameterized, never true); both reads'
// results merge correctly into the shared shape; a failure on EITHER read degrades the WHOLE
// result to ok:false (never a partial result), matching the fail-soft discipline every other
// query module in this directory follows.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadSubcatMarketValueAndTargets } from './subcatMarketValue';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

function makeSupabase(opts: {
	rpcData?: unknown;
	rpcError?: { message: string } | null;
	targetData?: unknown;
	targetError?: { message: string } | null;
}) {
	const rpc = vi.fn(async () => ({ data: opts.rpcData ?? null, error: opts.rpcError ?? null }));
	const select = vi.fn(async () => ({ data: opts.targetData ?? null, error: opts.targetError ?? null }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, from, select, schema };
}

describe('loadSubcatMarketValueAndTargets', () => {
	it('always calls the RPC with p_include_real_estate: false — never parameterized, never true', async () => {
		const { client, rpc } = makeSupabase({ rpcData: [], targetData: [] });
		await loadSubcatMarketValueAndTargets(client, AS_OF);
		expect(rpc).toHaveBeenCalledWith('fn_subcat_market_value', {
			p_as_of: AS_OF,
			p_include_real_estate: false
		});
	});

	it('merges the RPC rows and the planning_target rows into the shared shape', async () => {
		const { client } = makeSupabase({
			rpcData: [
				{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
				{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 200 }
			],
			targetData: [{ sub_cat_id: 1, target_percent: 20 }]
		});
		const result = await loadSubcatMarketValueAndTargets(client, AS_OF);
		expect(result.ok).toBe(true);
		if (!result.ok) throw new Error('unreachable');
		expect(result.rows).toEqual([
			{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
			{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 200 }
		]);
		expect(result.targetBySubCatId.get(1)).toBe(20);
		expect(result.targetBySubCatId.has(2)).toBe(false);
	});

	it('an empty 076 return (AC7) is a valid, non-error result — zero rows, ok:true', async () => {
		const { client } = makeSupabase({ rpcData: [], targetData: [] });
		const result = await loadSubcatMarketValueAndTargets(client, AS_OF);
		expect(result).toEqual({ ok: true, rows: [], targetBySubCatId: new Map() });
	});

	it('degrades to ok:false, empty rows, on an RPC error', async () => {
		const { client } = makeSupabase({ rpcError: { message: 'boom' }, targetData: [] });
		const result = await loadSubcatMarketValueAndTargets(client, AS_OF);
		expect(result.ok).toBe(false);
		expect(result.rows).toEqual([]);
	});

	it('degrades to ok:false on a planning_target read error, even though the RPC succeeded', async () => {
		const { client } = makeSupabase({ rpcData: [{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1 }], targetError: { message: 'boom' } });
		const result = await loadSubcatMarketValueAndTargets(client, AS_OF);
		expect(result.ok).toBe(false);
		expect(result.rows).toEqual([]);
	});
});
