// nonReAllocation.io.test.ts — I/O-wiring coverage for loadNonReAllocation, separate from the
// pure-core compute tests in nonReAllocation.test.ts. Originally SELF-238; the `element` column
// in the taxonomy read/fixtures below is SELF-239 (085) — the read is still UNFILTERED (this
// module's own compute core narrows to asset-only, not the read), so the wiring shape is
// otherwise unchanged. Mocks the full chain:
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
import { EMPTY_STALE_LINKED_SOURCE_IDS } from './navComposition';
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
	// Typed params (name, args) — not because the body reads them (it returns the same canned
	// response regardless of which RPC name was called, unchanged behavior), but so `rpc.mock.calls`
	// infers as `[string, unknown][]` rather than `[][]`; the SELF-244 null-arm test below indexes
	// into a call's first element to distinguish `fn_subcat_market_value` from
	// `fn_subcat_contributors`, which an untyped zero-arg mock can't express.
	const rpc = vi.fn(async (_fnName: string, _args?: unknown) => ({ data: opts.rpcData ?? [], error: opts.rpcError ?? null }));
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
			taxonomyData: [{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' }]
		});
		const result = await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result.ok).toBe(true);
		expect(result.data?.total_non_re).toBe(1000);
		const cash = result.data?.groups.find((g) => g.cat === 'Cash');
		expect(cash?.rows[0]).toMatchObject({ sub_cat: 'FDIC', dollar_alloc: 1000, pct_target: 20 });
	});

	it('a liability-element taxonomy row is read (unfiltered query) but never enters the row set or TotalNonRE (SELF-239 AC2/AC3)', async () => {
		const { client } = makeSupabase({
			rpcData: [
				{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
				{ sub_cat_id: 2, cat: 'Liabilities', sub_cat: 'Credit-Balance', market_value: 5000 }
			],
			targetData: [],
			taxonomyData: [
				{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
				{ id: 2, cat: 'Liabilities', sub_cat: 'Credit-Balance', display_order: 290, element: 'liability' }
			]
		});
		const result = await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result.ok).toBe(true);
		expect(result.data?.total_non_re).toBe(1000); // NOT 6000
		expect(result.data?.groups.map((g) => g.cat)).toEqual([
			'Cash',
			'Bonds',
			'Marketable Securities',
			'Alternatives'
		]);
		const anyLiability = result.data?.groups.some((g) => g.rows.some((r) => r.sub_cat_id === 2));
		expect(anyLiability).toBe(false);
	});

	it('the user_taxonomy read is UNFILTERED and selects element (no domain column post-084 — table identity IS the scope; element is 085\'s consumer-side predicate, SELF-239)', async () => {
		const { client, taxonomySelect } = makeSupabase({ rpcData: [], targetData: [], taxonomyData: [] });
		await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(taxonomySelect).toHaveBeenCalledWith('id, cat, sub_cat, display_order, element');
	});

	// SELF-244 (Sec-flagged at SELF-243 hand-off, booked for the V1.2 close-gate battery):
	// `staleLinkedSourceIds === null` (the caller's OWN root `046` read was itself unknown) must
	// skip the contributor bridge ENTIRELY — `loadSubCatContributors` (hence the
	// `fn_subcat_contributors` RPC) is never invoked. DISTINCT from every other test above passing
	// `EMPTY_STALE_LINKED_SOURCE_IDS`: an empty-but-KNOWN Set still runs `loadSubCatContributors`
	// (`staleLinkedSourceIds !== null` is true for an empty Set — see loadNonReAllocation's own
	// `if` guard) — only the ABSENCE of a value (an unknown root) short-circuits before that call.
	// `rpc` is the SAME mock both `fn_subcat_market_value` (substrate, via subcatMarketValue.ts)
	// and `fn_subcat_contributors` (the bridge, via nonReAllocation.ts's own loadSubCatContributors)
	// call through, so asserting on the CALL NAME (not just a call count) is what proves the right
	// one fired and the other didn't — a raw count could pass by coincidence if either RPC's own
	// call count ever changed for an unrelated reason.
	it('staleLinkedSourceIds === null skips the contributor bridge entirely — fn_subcat_contributors is NEVER called', async () => {
		const { client, rpc } = makeSupabase({
			rpcData: [{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 }],
			targetData: [],
			taxonomyData: [{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' }]
		});
		const result = await loadNonReAllocation(client, AS_OF, null);
		// the substrate read still succeeds — only the staleness bridge is skipped, never the
		// table's actual $/% data (mirrors the module's own "fail-soft, but never to
		// confirmed-fresh" posture, applied here to the "root unknown" input rather than a failure).
		expect(result.ok).toBe(true);
		const contributorCalls = rpc.mock.calls.filter(([name]) => name === 'fn_subcat_contributors');
		expect(contributorCalls).toEqual([]);
		// every row's is_stale resolves to null (UNKNOWN) — never a silent false — proving the
		// skip actually propagates through computeNonReAllocation's own short-circuit, not just
		// that the RPC call was skipped in isolation.
		const cash = result.data?.groups.find((g) => g.cat === 'Cash');
		expect(cash?.rows[0]?.is_stale).toBeNull();
	});

	it('degrades to ok:false when the shared substrate read fails (RPC error)', async () => {
		const { client } = makeSupabase({ rpcError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when the shared substrate read fails (planning_target error)', async () => {
		const { client } = makeSupabase({ rpcData: [], targetError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when THIS module\'s own user_taxonomy read fails', async () => {
		const { client } = makeSupabase({ rpcData: [], targetData: [], taxonomyError: { message: 'boom' } });
		const result = await loadNonReAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});
});
