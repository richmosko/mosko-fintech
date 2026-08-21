// usEquityAllocation.io.test.ts — SELF-240 I/O-wiring coverage for loadUsEquityAllocation,
// separate from the pure-core compute tests in usEquityAllocation.test.ts. Mocks the chain:
//   .schema('pfin').rpc('fn_subcat_market_value', {...})       — via subcatMarketValue
//   .schema('pfin').from('planning_target').select(...)        — via subcatMarketValue
//   .schema('pfin').from('user_taxonomy').select(...).in(...)  — this module's own read
//
// Proves: the taxonomy read is scoped to the twelve US-equity labels (AC1/AC2); a successful
// round trip reaches the compute core with the right inputs; a failure at ANY of the three reads
// degrades to ok:false.
//
// POST-084 (ADR-058 Decision 1's split): `user_taxonomy` is the storage-classification table
// only now — no `domain` column, no `.eq('domain', 'asset')` link in the chain. `.select(...)`
// returns straight to `.in(...)`, which resolves the read.
//
// SELF-243 (Sec-flagged, 7084aca): `loadUsEquityAllocation`'s third parameter,
// `staleLinkedSourceIds`, is now REQUIRED — no default — matching `loadNonReAllocation`'s own
// SELF-330 shape exactly (nonReAllocation.ts:538-542). A default would mask a caller genuinely
// forgetting to thread staleness (Sec's finding, ratified by team-lead); the compiler is the
// watcher for a future ramp site that forgets. Every call site below passes
// `EMPTY_STALE_LINKED_SOURCE_IDS` explicitly, mirroring `nonReAllocation.io.test.ts`'s own
// convention verbatim — these tests exercise the SUBSTRATE wiring, not the staleness bridge, so a
// known-empty (not null/unknown) root keeps that bridge's own behavior out of scope here.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadUsEquityAllocation } from './usEquityAllocation';
import { EMPTY_STALE_LINKED_SOURCE_IDS } from './navComposition';
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
	// Typed params (name, args) — not because the body reads them (it returns the same canned
	// response regardless of which RPC name was called, unchanged behavior), but so `rpc.mock.calls`
	// infers as `[string, unknown][]` rather than `[][]`; the SELF-244 null-arm test below indexes
	// into a call's first element to distinguish `fn_subcat_market_value` from
	// `fn_subcat_contributors`, which an untyped zero-arg mock can't express.
	const rpc = vi.fn(async (_fnName: string, _args?: unknown) => ({ data: opts.rpcData ?? [], error: opts.rpcError ?? null }));
	const targetSelect = vi.fn(async () => ({ data: opts.targetData ?? [], error: opts.targetError ?? null }));
	const taxonomyIn = vi.fn(async () => ({ data: opts.taxonomyData ?? [], error: opts.taxonomyError ?? null }));
	const taxonomySelect = vi.fn(() => ({ in: taxonomyIn }));

	const from = vi.fn((table: string) => {
		if (table === 'planning_target') return { select: targetSelect };
		if (table === 'user_taxonomy') return { select: taxonomySelect };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, from, targetSelect, taxonomySelect, taxonomyIn };
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
		const result = await loadUsEquityAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result.ok).toBe(true);
		expect(result.data?.total.dollar_alloc).toBe(300);
		const us06 = result.data?.rows.find((r) => r.sub_cat === 'US-06-Financials');
		expect(us06).toMatchObject({ dollar_alloc: 300, pct_target: 100 }); // sole target → 100% renormalized
	});

	it('the user_taxonomy read is scoped to the twelve US-equity labels (AC1/AC2) — no domain column post-084', async () => {
		const { client, taxonomySelect, taxonomyIn } = makeSupabase({});
		await loadUsEquityAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(taxonomySelect).toHaveBeenCalledWith('id, sub_cat');
		expect(taxonomyIn).toHaveBeenCalledWith('sub_cat', US_EQUITY_SUB_CATS);
	});

	// SELF-244 (Sec-flagged at SELF-243 hand-off, booked for the V1.2 close-gate battery):
	// `staleLinkedSourceIds === null` (the caller's OWN root `046` read was itself unknown) must
	// skip the contributor bridge ENTIRELY — `loadSubCatContributors` (hence the
	// `fn_subcat_contributors` RPC, reused verbatim from nonReAllocation.ts) is never invoked.
	// DISTINCT from every other test above passing `EMPTY_STALE_LINKED_SOURCE_IDS`: an
	// empty-but-KNOWN Set still runs `loadSubCatContributors` (`staleLinkedSourceIds !== null` is
	// true for an empty Set — see loadUsEquityAllocation's own `if` guard) — only the ABSENCE of a
	// value (an unknown root) short-circuits before that call. `rpc` is the SAME mock both
	// `fn_subcat_market_value` (substrate, via subcatMarketValue.ts) and `fn_subcat_contributors`
	// (the bridge) call through, so asserting on the CALL NAME (not just a call count) is what
	// proves the right one fired and the other didn't — mirrors nonReAllocation.io.test.ts's own
	// SELF-244 case verbatim in structure.
	it('staleLinkedSourceIds === null skips the contributor bridge entirely — fn_subcat_contributors is NEVER called', async () => {
		const { client, rpc } = makeSupabase({
			rpcData: [
				{ sub_cat_id: 6, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: 300 }
			],
			targetData: [],
			taxonomyData: [{ id: 6, sub_cat: 'US-06-Financials' }]
		});
		const result = await loadUsEquityAllocation(client, AS_OF, null);
		// the substrate read still succeeds — only the staleness bridge is skipped, never the
		// table's actual $/% data.
		expect(result.ok).toBe(true);
		const contributorCalls = rpc.mock.calls.filter(([name]) => name === 'fn_subcat_contributors');
		expect(contributorCalls).toEqual([]);
		// every row's is_stale resolves to null (UNKNOWN) — never a silent false — proving the
		// skip actually propagates through computeUsEquityAllocation's own short-circuit, not just
		// that the RPC call was skipped in isolation.
		const us06 = result.data?.rows.find((r) => r.sub_cat === 'US-06-Financials');
		expect(us06?.is_stale).toBeNull();
	});

	it('degrades to ok:false when the shared substrate read fails (RPC error)', async () => {
		const { client } = makeSupabase({ rpcError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});

	it('degrades to ok:false when the shared substrate read fails (planning_target error)', async () => {
		const { client } = makeSupabase({ targetError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});

	it("degrades to ok:false when THIS module's own user_taxonomy read fails", async () => {
		const { client } = makeSupabase({ taxonomyError: { message: 'boom' } });
		const result = await loadUsEquityAllocation(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(result).toEqual({ data: null, ok: false });
	});
});
