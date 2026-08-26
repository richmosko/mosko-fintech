// load.server.test.ts — the account-detail load() watcher, for the SELF-325 selectableAssets /
// defaultSubCatId / defaultSubCatLabel fields (round 5), plus the pass-through of
// heldSecurities[].priced (round 8 — the P-b read-side signal).
//
// WHY THIS FILE EXISTS: the round-5 fields landed FOUR ROUNDS after actions.createPurchase did
// (Frontend caught the gap by hand-diffing) — load() had no test of its own, so nothing red when
// the fields were simply absent from the return. This is the watcher that gap needed: it fails if
// any of the round-5 fields regresses, disappears, or stops fail-soft-degrading. It does NOT
// re-verify the rest of load()'s long-standing behavior (account 404, transaction shaping,
// dupCandidates/syncHistory/connection) — those are unchanged and exercised by the existing
// action tests + QA's RLS battery.
//
// The `priced` PREDICATE ITSELF (no eod_price row / zero-valued row at the max date / a normal
// price) is NOT re-tested here — that is transactions.priced.test.ts's job, inversion-tested
// there against the actual query logic. This file only proves load() FORWARDS whatever
// loadHeldSecurities returns without dropping or reshaping the field — a thinner claim, but the
// one this file's own layer can make honestly (its loadHeldSecurities dependency is mocked).
//
// Query-module dependencies are mocked (not the raw supabase table chain) — each module already
// has its own unit tests (selectableAssets.test.ts, taxonomy.test.ts, transactions.priced.test.ts,
// reconciliation/connectionState equivalents); re-deriving their internals here would test the
// mock, not this file's wiring.

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

type HeldSecurityLike = { security_id: number; symbol: string | null; name: string | null; quantity: number; priced: boolean };
const loadHeldSecuritiesMock = vi.fn(async (): Promise<HeldSecurityLike[]> => []);
// SELF-249: loadVendorSuggestions is mocked (the test double's `schema()` has no `.rpc`, and this
// file's job is to prove load() WIRES the batch call correctly, not to re-verify
// loadVendorSuggestions's own batching/normalization — that's transactions.vendorSuggestions.test.ts's
// job). classifiabilityOf/vendorKey stay REAL (`...actual`) — this file's classifiable/
// classifiableReason/provider_category coverage below exercises the genuine predicate.
const loadVendorSuggestionsMock = vi.fn(async (): Promise<Map<string, number | null>> => new Map());
vi.mock('$lib/server/queries/transactions', async (importOriginal) => {
	const actual = await importOriginal<typeof import('$lib/server/queries/transactions')>();
	return { ...actual, loadHeldSecurities: loadHeldSecuritiesMock, loadVendorSuggestions: loadVendorSuggestionsMock };
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
type TransactionViewLike = {
	trans_id: number;
	vendor: string | null;
	category: { cat: string | null; sub_cat: string } | null;
	sub_cat_id?: number | null;
	provider_category?: string | null;
	classifiable?: boolean;
	classifiableReason?: string | null;
	suggested_sub_cat_id?: number | null;
};
type LoadResult = {
	selectableAssets: unknown[];
	defaultSubCatId: number | null;
	defaultSubCatLabel: string | null;
	heldSecurities: Array<{ security_id: number; priced: boolean }>;
	transactions: TransactionViewLike[];
};
async function loadData(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

/** A raw account_trans row shaped as PostgREST would return it for TRANSACTION_COLUMNS — the
 *  RAW wire shape load() destructures, not the TransactionView it produces. */
function transRow(overrides: {
	trans_id?: number;
	transaction_type?: string;
	security_id?: number | null;
	is_reverse?: boolean;
	vendor?: string | null;
	provider_category?: string | null;
	annotation?: { sub_cat_id?: number; note?: string | null; journal_id?: number | null; posting_prototype?: { cat: string; sub_cat: string } | null } | null;
	splits?: unknown[];
} = {}) {
	return {
		trans_id: overrides.trans_id ?? 1,
		transaction_date: '2026-01-01',
		amount: 10,
		vendor: overrides.vendor ?? null,
		description: null,
		transaction_type: overrides.transaction_type ?? 'standard',
		security_id: overrides.security_id ?? null,
		is_reverse: overrides.is_reverse ?? false,
		replaces_trans_id: null,
		created_at: '2026-01-01T00:00:00Z',
		provider_category: overrides.provider_category ?? null,
		account_trans_annotation: overrides.annotation ?? null,
		account_trans_split: overrides.splits ?? []
	};
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

describe('load() — SELF-325 P-b: heldSecurities[].priced pass-through (round 8)', () => {
	beforeEach(() => {
		vi.clearAllMocks();
	});

	it('forwards priced VERBATIM from loadHeldSecurities — load() must not drop, default, or reshape it', async () => {
		loadCashflowSubCatsMock.mockResolvedValueOnce([]);
		loadSelectableAssetsMock.mockResolvedValueOnce({ assets: [], error: false });
		loadHeldSecuritiesMock.mockResolvedValueOnce([
			{ security_id: 501, symbol: 'AAPL', name: 'Apple Inc', quantity: 10, priced: true },
			{ security_id: 502, symbol: null, name: 'Rental House', quantity: 1, priced: false }
		]);
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [] });
		const data = await loadData(makeEvent(supabase));
		expect(data.heldSecurities).toEqual([
			{ security_id: 501, symbol: 'AAPL', name: 'Apple Inc', quantity: 10, priced: true },
			{ security_id: 502, symbol: null, name: 'Rental House', quantity: 1, priced: false }
		]);
	});
});

// ── SELF-249: classifiable / classifiableReason / provider_category / suggested_sub_cat_id ────
//
// Frontend's TransactionView carries these as an EXPECTED CONTRACT (transaction-util.ts); this is
// Backend's half — the loader must actually populate them or the shipped picker degrades to
// all-classifiable/no-hints (team-lead's dispatch). classifiabilityOf/vendorKey run FOR REAL here
// (not mocked) — this is the genuine predicate, fed the loader's own query fields, exercising the
// same code checkClassifiable uses at write time (transactions.classify.test.ts covers that side).
//
// INVERSION DISCIPLINE: each non-classifiable leg gets its own test asserting the SPECIFIC reason,
// not just "classifiable: false" — a test that only checks the boolean can't tell M1 from a typo.
describe('load() — SELF-249 classifiable/classifiableReason (one leg per test)', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		loadCashflowSubCatsMock.mockResolvedValue([]);
		loadSelectableAssetsMock.mockResolvedValue({ assets: [], error: false });
	});

	it('all legs pass → classifiable: true, classifiableReason: null', async () => {
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [transRow({ trans_id: 1 })] });
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiable).toBe(true);
		expect(data.transactions[0].classifiableReason).toBeNull();
	});

	it('M1 — transaction_type <> standard → not_standard', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, transaction_type: 'trade' })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiable).toBe(false);
		expect(data.transactions[0].classifiableReason).toBe('not_standard');
	});

	it('M2 — security_id IS NOT NULL → has_security', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, security_id: 42 })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiableReason).toBe('has_security');
	});

	it('E1 — is_reverse = true → is_reversal (the SAME leg the recategorize-path fix (upsertAnnotation) refuses at write time)', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, is_reverse: true })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiableReason).toBe('is_reversal');
	});

	it('M4 — split_count > 0 (a split parent) → split_parent', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [
				transRow({
					trans_id: 1,
					splits: [{ id: 1, amount: 10, sub_cat_id: 5, note: null, display_order: 0, posting_prototype: { cat: 'Trade', sub_cat: 'BTO' } }]
				})
			]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiableReason).toBe('split_parent');
	});

	it('M3 — annotation.journal_id IS NOT NULL → journaled', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, annotation: { sub_cat_id: 5, note: null, journal_id: 55, posting_prototype: { cat: 'Revenue', sub_cat: 'Salary' } } })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiableReason).toBe('journaled');
	});

	it('an annotation with journal_id NULL is still classifiable (M3 only fires when journal_id is set)', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, annotation: { sub_cat_id: 5, note: null, journal_id: null, posting_prototype: { cat: 'Revenue', sub_cat: 'Salary' } } })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].classifiable).toBe(true);
		expect(data.transactions[0].classifiableReason).toBeNull();
	});
});

describe('load() — SELF-249 Sec FLAG-D (PR #564): a note-only annotation is UNCLASSIFIED via sub_cat_id, not via category', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		loadCashflowSubCatsMock.mockResolvedValue([]);
		loadSelectableAssetsMock.mockResolvedValue({ assets: [], error: false });
	});

	// Frontend's own parallel FLAG-D fix (commit e21c9fe) settled the contract shape: `category`'s
	// computation is UNCHANGED (subCatLabel's Unsorted-label object still surfaces for a note-only
	// row — other consumers may still want "does ANY annotation exist"), and a NEW raw `sub_cat_id`
	// field is what SubCatPicker's `classified` state and this loader's own vendor-suggestion
	// filter both key on instead.
	it('an annotation row with sub_cat_id NULL (note-only — reachable via recategorize\'s nullable subCatIdField) → sub_cat_id is null even though category is still the non-null Unsorted-label object', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, annotation: { sub_cat_id: undefined, note: 'ask about this later', journal_id: null, posting_prototype: null } })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].sub_cat_id).toBeNull();
		expect(data.transactions[0].category).toEqual({ cat: null, sub_cat: 'Unsorted' });
	});

	it('a note-only row is therefore treated as UNCLASSIFIED by the vendor-suggestion batch (keyed on sub_cat_id, the same field Frontend\'s SubCatPicker binds on)', async () => {
		loadVendorSuggestionsMock.mockResolvedValueOnce(new Map());
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, vendor: 'Starbucks', annotation: { sub_cat_id: undefined, note: 'ask about this later', journal_id: null, posting_prototype: null } })]
		});
		await loadData(makeEvent(supabase));
		// Before the fix, keying on `category !== null` (the Unsorted-label object) meant this
		// vendor was never sent for a suggestion at all.
		expect(loadVendorSuggestionsMock).toHaveBeenCalledWith(expect.anything(), ['Starbucks']);
	});

	it('a real category (sub_cat_id set) still reads as classified via BOTH fields — this fix narrows the null case, it does not widen it', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, annotation: { sub_cat_id: 9, note: null, journal_id: null, posting_prototype: { cat: 'Food', sub_cat: 'Dining' } } })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].sub_cat_id).toBe(9);
		expect(data.transactions[0].category).toEqual({ cat: 'Food', sub_cat: 'Dining' });
	});

	it('no annotation row at all → sub_cat_id is null (same as note-only, from the caller\'s perspective)', async () => {
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [transRow({ trans_id: 1 })] });
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].sub_cat_id).toBeNull();
		expect(data.transactions[0].category).toBeNull();
	});
});

describe('load() — SELF-249 provider_category pass-through', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		loadCashflowSubCatsMock.mockResolvedValue([]);
		loadSelectableAssetsMock.mockResolvedValue({ assets: [], error: false });
	});

	it('forwards provider_category verbatim', async () => {
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [transRow({ trans_id: 1, provider_category: 'Groceries' })]
		});
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].provider_category).toBe('Groceries');
	});

	it('null when the provider never supplied one', async () => {
		const supabase = makeSupabase({ account: ACCOUNT_ROW, transRows: [transRow({ trans_id: 1 })] });
		const data = await loadData(makeEvent(supabase));
		expect(data.transactions[0].provider_category).toBeNull();
	});
});

describe('load() — SELF-249 AC7/AC8 vendor suggestions: batched by DISTINCT vendor, unclassified rows only', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		loadCashflowSubCatsMock.mockResolvedValue([]);
		loadSelectableAssetsMock.mockResolvedValue({ assets: [], error: false });
	});

	it('one loadVendorSuggestions call for the whole page, with only unclassified vendors, mapped back per row', async () => {
		loadVendorSuggestionsMock.mockResolvedValueOnce(new Map([['starbucks', 77]]));
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [
				transRow({ trans_id: 1, vendor: 'Starbucks' }), // unclassified
				transRow({
					trans_id: 2,
					vendor: 'Starbucks',
					annotation: { sub_cat_id: 9, note: null, journal_id: null, posting_prototype: { cat: 'Food', sub_cat: 'Dining' } }
				}) // ALREADY classified — its vendor must not be sent, and it gets no suggestion
			]
		});
		const data = await loadData(makeEvent(supabase));

		// Batched, not per-row: exactly one loadVendorSuggestions call for the whole page.
		expect(loadVendorSuggestionsMock).toHaveBeenCalledTimes(1);
		// Only the unclassified row's vendor is sent — the classified row's vendor is excluded
		// (AC7: an existing override always wins over a suggestion).
		expect(loadVendorSuggestionsMock).toHaveBeenCalledWith(expect.anything(), ['Starbucks']);

		const unclassified = data.transactions.find((t) => t.trans_id === 1)!;
		const classified = data.transactions.find((t) => t.trans_id === 2)!;
		expect(unclassified.suggested_sub_cat_id).toBe(77);
		expect(classified.suggested_sub_cat_id).toBeNull();
	});

	it('no unclassified rows → loadVendorSuggestions is still called once, with an empty list (never skipped silently)', async () => {
		loadVendorSuggestionsMock.mockResolvedValueOnce(new Map());
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [
				transRow({
					trans_id: 1,
					vendor: 'Starbucks',
					annotation: { sub_cat_id: 9, note: null, journal_id: null, posting_prototype: { cat: 'Food', sub_cat: 'Dining' } }
				})
			]
		});
		await loadData(makeEvent(supabase));
		expect(loadVendorSuggestionsMock).toHaveBeenCalledWith(expect.anything(), []);
	});

	it('a repeat vendor across two UNCLASSIFIED rows is still one batched call carrying both — mapping back is per-row, not per-call', async () => {
		loadVendorSuggestionsMock.mockResolvedValueOnce(new Map([['starbucks', 77]]));
		const supabase = makeSupabase({
			account: ACCOUNT_ROW,
			transRows: [
				transRow({ trans_id: 1, vendor: 'Starbucks' }),
				transRow({ trans_id: 2, vendor: 'STARBUCKS' })
			]
		});
		const data = await loadData(makeEvent(supabase));
		expect(loadVendorSuggestionsMock).toHaveBeenCalledTimes(1);
		expect(loadVendorSuggestionsMock).toHaveBeenCalledWith(expect.anything(), ['Starbucks', 'STARBUCKS']);
		expect(data.transactions[0].suggested_sub_cat_id).toBe(77);
		expect(data.transactions[1].suggested_sub_cat_id).toBe(77);
	});
});
