// load.server.test.ts — the account-detail load() watcher, specifically for the SELF-325
// selectableAssets / defaultSubCatId / defaultSubCatLabel fields.
//
// WHY THIS FILE EXISTS: those three fields landed FOUR ROUNDS after actions.createPurchase did
// (Frontend caught the gap by hand-diffing) — load() had no test of its own, so nothing red when
// the fields were simply absent from the return. This is the watcher that gap needed: it fails if
// any of the three fields regresses, disappears, or stops fail-soft-degrading. It does NOT
// re-verify the rest of load()'s long-standing behavior (account 404, transaction shaping,
// heldSecurities/dupCandidates/syncHistory/connection) — those are unchanged by this round and
// exercised by the existing action tests + QA's RLS battery.
//
// Query-module dependencies are mocked (not the raw supabase table chain) — each module already
// has its own unit tests (selectableAssets.test.ts, taxonomy.test.ts, transactions.ts's own
// suite, reconciliation/connectionState equivalents); re-deriving their internals here would test
// the mock, not this file's wiring.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

const loadCashflowSubCatsMock = vi.fn();
vi.mock('$lib/server/queries/taxonomy', async (importOriginal) => {
	const actual = await importOriginal<typeof import('$lib/server/queries/taxonomy')>();
	return { ...actual, loadCashflowSubCats: loadCashflowSubCatsMock };
});

const loadSelectableAssetsMock = vi.fn();
vi.mock('$lib/server/queries/selectableAssets', () => ({
	loadSelectableAssets: loadSelectableAssetsMock
}));

const loadHeldSecuritiesMock = vi.fn(async () => []);
vi.mock('$lib/server/queries/transactions', async (importOriginal) => {
	const actual = await importOriginal<typeof import('$lib/server/queries/transactions')>();
	return { ...actual, loadHeldSecurities: loadHeldSecuritiesMock };
});

const loadDupCandidatesMock = vi.fn(async () => []);
const loadSyncHistoryMock = vi.fn(async () => []);
vi.mock('$lib/server/queries/reconciliation', () => ({
	loadDupCandidates: loadDupCandidatesMock,
	loadSyncHistory: loadSyncHistoryMock
}));

const loadConnectionStateMock = vi.fn(async () => null);
vi.mock('$lib/server/queries/connectionState', () => ({
	loadConnectionState: loadConnectionStateMock
}));

const { load } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const ACCOUNT_ROW = {
	account_id: 7,
	name: 'Brokerage',
	account_type: 'investment',
	scope: 'Personal',
	tax_treatment: 'taxable',
	closed_at: null,
	linked_source_id: null,
	created_at: '2026-01-01T00:00:00Z'
};

/** A chainable thenable builder — every hop returns itself; awaiting resolves to `result`
 *  (mirrors the shape selectableAssets.test.ts uses for the same reason: PostgREST's real
 *  builder is PromiseLike). Table-dispatched so account vs account_trans get different results. */
function makeSupabase(opts: { account?: unknown; transRows?: unknown[] }) {
	function builder(result: unknown) {
		const b: Record<string, unknown> = {};
		for (const m of ['eq', 'order']) b[m] = vi.fn(() => b);
		b.maybeSingle = vi.fn(async () => ({ data: opts.account ?? null, error: null }));
		(b as { then: PromiseLike<unknown>['then'] }).then = (onF, onR) =>
			Promise.resolve({ data: result, error: null }).then(onF, onR);
		return b;
	}
	const from = vi.fn((table: string) => {
		if (table === 'account') return { select: () => builder(opts.account ?? null) };
		if (table === 'account_trans') return { select: () => builder(opts.transRows ?? []) };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ from }));
	return { schema } as unknown as SupabaseClient;
}

function makeEvent(supabase: SupabaseClient, user: { id: string } | null = { id: SESSION_UID }) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return {
		locals,
		params: { account_id: '7' },
		url: new URL('http://localhost/accounts/7')
	} as unknown as Parameters<typeof load>[0];
}

/** load()'s inferred return type unions in `void` (the redirect()/error() early-throw paths),
 *  which TS can't rule out statically even though every test here supplies an authed session +
 *  a resolving account row. Narrow to the fields this file actually asserts on rather than
 *  fighting SvelteKit's PageServerLoad inference with a broader cast. */
type LoadResult = { selectableAssets: unknown[]; defaultSubCatId: number | null; defaultSubCatLabel: string | null };
async function loadData(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

describe('load() — SELF-325 selectableAssets / defaultSubCat fields', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('returns selectableAssets from loadSelectableAssets, unwrapped from its {assets,error} envelope', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([]);
		loadSelectableAssetsMock.mockResolvedValueOnce({
			assets: [
				{
					asset_id: 501,
					asset_type: 'equity',
					pricing_source: 'market_feed',
					symbol: 'AAPL',
					cusip: null,
					name: 'Apple Inc',
					currency: 'USD',
					is_global: true
				}
			],
			error: false
		});
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		const data = await loadData(makeEvent(supabase));
		expect(data.selectableAssets).toEqual([
			{
				asset_id: 501,
				asset_type: 'equity',
				pricing_source: 'market_feed',
				symbol: 'AAPL',
				cusip: null,
				name: 'Apple Inc',
				currency: 'USD',
				is_global: true
			}
		]);
	});

	it('fail-soft: selectableAssets is [] (not a throw) when loadSelectableAssets reports error:true', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([]);
		loadSelectableAssetsMock.mockResolvedValueOnce({ assets: [], error: true });
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		await expect(load(makeEvent(supabase))).resolves.toMatchObject({ selectableAssets: [] });
	});

	it('derives defaultSubCatId/defaultSubCatLabel from the caller\'s Trade/BTO row in cashflowSubCats', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([
			{ id: 3, cat: 'Income', sub_cat: 'Salary', display_order: 1 },
			{ id: 42, cat: 'Trade', sub_cat: 'BTO', display_order: 2 }
		]);
		loadSelectableAssetsMock.mockResolvedValueOnce({ assets: [], error: false });
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		const data = await loadData(makeEvent(supabase));
		expect(data.defaultSubCatId).toBe(42);
		expect(data.defaultSubCatLabel).toBe('Trade — BTO');
	});

	it('defaultSubCatId/defaultSubCatLabel are both null when no Trade/BTO row exists (not provisioned/renamed/deactivated)', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([{ id: 3, cat: 'Income', sub_cat: 'Salary', display_order: 1 }]);
		loadSelectableAssetsMock.mockResolvedValueOnce({ assets: [], error: false });
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		const data = await loadData(makeEvent(supabase));
		expect(data.defaultSubCatId).toBeNull();
		expect(data.defaultSubCatLabel).toBeNull();
	});

	it('does NOT call findDefaultBtoSubCatId — the label is derived from the already-loaded cashflowSubCats, no extra round trip', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([{ id: 42, cat: 'Trade', sub_cat: 'BTO', display_order: 2 }]);
		loadSelectableAssetsMock.mockResolvedValueOnce({ assets: [], error: false });
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		await load(makeEvent(supabase));
		// loadCashflowSubCats is called exactly once per load() — a second call would mean a
		// redundant BTO-specific query was reintroduced.
		expect(loadCashflowSubCatsMock).toHaveBeenCalledTimes(1);
	});
});
