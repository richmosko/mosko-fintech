// nonReAllocation.io.test.ts — SELF-238 I/O-wiring coverage for loadNonReAllocation, separate
// from the pure-core compute tests in nonReAllocation.test.ts. Mocks the full chain:
//   .schema('pfin').rpc('fn_subcat_market_value', {...})        — via subcatMarketValue
//   .schema('pfin').from('planning_target').select(...)         — via subcatMarketValue
//   .schema('pfin').from('user_taxonomy').select(...)           — this module's own read
//
// Proves: a successful, well-formed round trip reaches computeNonReAllocation with the right
// inputs; a failure at ANY of the three reads degrades the WHOLE result to ok:false (never a
// partial/wrong table), matching every other query module's fail-soft discipline.
//
// POST-084 (ADR-058 Decision 1's split): `user_taxonomy` is the storage-classification table
// only now — no `domain` column, no `.eq('domain', 'asset')` clause. The read resolves directly
// at `.select(...)`, same shape as the `planning_target` read.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNonReAllocation } from './nonReAllocation';
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
	// pfin.planning_target: .select(...) resolves directly (no further chaining, matching
	// subcatMarketValue.ts's own call shape).
	const targetSelect = vi.fn(async () => ({ data: opts.targetData ?? [], error: opts.targetError ?? null }));
	// pfin.user_taxonomy: .select(...) resolves directly post-084 — no `.eq('domain', ...)` to
	// chain through, since the table has no `domain` column any more.
	const taxonomySelect = vi.fn(async () => ({ data: opts.taxonomyData ?? [], error: opts.taxonomyError ?? null }));

	const from = vi.fn((table: string) => {
		if (table === 'planning_target') return { select: targetSelect };
		if (table === 'user_taxonomy') return { select: taxonomySelect };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, from, targetSelect, taxonomySelect };
}

describe('loadNonReAllocation — I/O wiring', () => {
	it('a well-formed round trip reaches the compute core with matching values', async () => {
		const { client } = makeSupabase({
			rpcData: [{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 }],
			targetData: [{ sub_cat_id: 1, target_percent: 20 }],
			taxonomyData: [{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10 }]
		});
		const result = await loadNonReAllocation(client, AS_OF);
		expect(result.ok).toBe(true);
		expect(result.data?.total_non_re).toBe(1000);
		const cash = result.data?.groups.find((g) => g.cat === 'Cash');
		expect(cash?.rows[0]).toMatchObject({ sub_cat: 'FDIC', dollar_alloc: 1000, pct_target: 20 });
	});

	it('the user_taxonomy read is UNFILTERED (no domain column post-084 — table identity IS the scope)', async () => {
		const { client, taxonomySelect } = makeSupabase({ rpcData: [], targetData: [], taxonomyData: [] });
		await loadNonReAllocation(client, AS_OF);
		expect(taxonomySelect).toHaveBeenCalledWith('id, cat, sub_cat, display_order');
	});

	it('degrades to ok:false when the shared substrate read fails (RPC error)', async () => {
		const { client } = makeSupabase({ rpcError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when the shared substrate read fails (planning_target error)', async () => {
		const { client } = makeSupabase({ rpcData: [], targetError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when THIS module\'s own user_taxonomy read fails', async () => {
		const { client } = makeSupabase({ rpcData: [], targetData: [], taxonomyError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF);
		expect(result).toEqual({ data: null, ok: false });
	});
});
