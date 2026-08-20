// taxonomy.test.ts — unit coverage for provisionDefaultTaxonomy (SELF-311 / migration 041,
// reworked at 084 / ADR-058 Decision 1's asymmetric split) AND isAssignableAssetSubCat
// (SELF-235 / ADR-013 H1, QA-added). Pure-TS server test (node env per vitest.config).
//
// POST-084 shape: provisionDefaultTaxonomy runs TWO INDEPENDENT branches — provisionAssetTaxonomy
// (pfin.user_taxonomy from pfin.taxonomy_default) and provisionCashflowPrototypes
// (pfin.posting_prototype from pfin.posting_prototype_default) — each with its OWN existence
// guard and its OWN try/catch, per Sec F3 condition (b): a row on ONE table must never suppress
// provisioning on the OTHER. The mock below dispatches on table name across all four tables:
//   user_taxonomy:             .select('id').limit(1).maybeSingle() → guard; .upsert(rows, opts) → write
//   taxonomy_default:          .select(cols) (awaited)               → the asset-side default read
//   posting_prototype:         .select('id').limit(1).maybeSingle() → guard; .upsert(rows, opts) → write
//   posting_prototype_default: .select(cols) (awaited)               → the cashflow-side default read
//
// Proves: EACH branch's existence guard independently SKIPS its own default-read + upsert when
// the caller already has a row on THAT table (and only that table — Sec F3's central regression:
// a row on one table must not suppress provisioning on the other); each branch is independently
// FAIL-SOFT (logs, never throws, and never aborts its sibling); and each branch's upsert carries
// the session-derived users_id with the post-084 (users_id, cat, sub_cat) conflict target.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { provisionDefaultTaxonomy, isAssignableAssetSubCat } from './taxonomy';

const USER_ID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

const ASSET_DEFAULTS = [
	{ cat: 'Cash', sub_cat: 'FDIC', tax_relevant: false, tax_character: null, display_order: 1, notes: null }
];
const CASHFLOW_DEFAULTS = [
	{ cat: 'Income', sub_cat: 'Salary', tax_relevant: true, tax_character: 'ordinary', display_order: 2, notes: 'W-2' }
];

type TableOpts = {
	existing?: unknown;
	existingErr?: { message: string } | null;
	defaults?: unknown;
	defaultsErr?: { message: string } | null;
	upsertErr?: { message: string } | null;
};

/**
 * Table-dispatching supabase stub covering all four tables the two provisioning branches touch.
 * `asset` configures `user_taxonomy` + `taxonomy_default`; `cashflow` configures
 * `posting_prototype` + `posting_prototype_default`. Each table's guard/default-read/upsert is an
 * INDEPENDENT mock so a test can prove one branch's failure never reaches the other's calls.
 */
function makeSupabase(opts: { asset?: TableOpts; cashflow?: TableOpts } = {}) {
	const asset = opts.asset ?? {};
	const cashflow = opts.cashflow ?? {};

	function makeGuardAndUpsert(o: TableOpts) {
		const maybeSingle = vi.fn(async () => ({ data: o.existing ?? null, error: o.existingErr ?? null }));
		const limit = vi.fn(() => ({ maybeSingle }));
		const selectGuard = vi.fn(() => ({ limit }));
		const upsert = vi.fn(async (_rows: unknown, _upsertOpts: unknown) => ({ error: o.upsertErr ?? null }));
		return { selectGuard, upsert };
	}
	function makeDefaultsSelect(o: TableOpts) {
		return vi.fn(async () => ({ data: o.defaults ?? null, error: o.defaultsErr ?? null }));
	}

	const userTaxonomy = makeGuardAndUpsert(asset);
	const taxonomyDefaultSelect = makeDefaultsSelect(asset);
	const postingPrototype = makeGuardAndUpsert(cashflow);
	const postingPrototypeDefaultSelect = makeDefaultsSelect(cashflow);

	const from = vi.fn((table: string) => {
		if (table === 'user_taxonomy') return { select: userTaxonomy.selectGuard, upsert: userTaxonomy.upsert };
		if (table === 'taxonomy_default') return { select: taxonomyDefaultSelect };
		if (table === 'posting_prototype')
			return { select: postingPrototype.selectGuard, upsert: postingPrototype.upsert };
		if (table === 'posting_prototype_default') return { select: postingPrototypeDefaultSelect };
		return {};
	});
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return {
		client,
		from,
		userTaxonomyUpsert: userTaxonomy.upsert,
		taxonomyDefaultSelect,
		postingPrototypeUpsert: postingPrototype.upsert,
		postingPrototypeDefaultSelect
	};
}

describe('provisionDefaultTaxonomy — post-084 two-independent-branches shape', () => {
	it('SKIPS both branches when the caller already has rows on BOTH tables', async () => {
		const s = makeSupabase({ asset: { existing: { id: 1 } }, cashflow: { existing: { id: 37 } } });
		await provisionDefaultTaxonomy(s.client, USER_ID);

		expect(s.from).toHaveBeenCalledWith('user_taxonomy');
		expect(s.from).toHaveBeenCalledWith('posting_prototype');
		expect(s.from).not.toHaveBeenCalledWith('taxonomy_default');
		expect(s.from).not.toHaveBeenCalledWith('posting_prototype_default');
		expect(s.userTaxonomyUpsert).not.toHaveBeenCalled();
		expect(s.postingPrototypeUpsert).not.toHaveBeenCalled();
	});

	it('provisions BOTH tables on a fresh user (no rows on either) — the direct fresh-user proof (Sec F3 condition (c))', async () => {
		const s = makeSupabase({
			asset: { existing: null, defaults: ASSET_DEFAULTS },
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS }
		});
		await provisionDefaultTaxonomy(s.client, USER_ID);

		expect(s.userTaxonomyUpsert).toHaveBeenCalledTimes(1);
		const [assetRows, assetOpts] = s.userTaxonomyUpsert.mock.calls[0];
		expect(assetRows).toEqual([{ users_id: USER_ID, ...ASSET_DEFAULTS[0] }]);
		expect(assetOpts).toEqual({ onConflict: 'users_id,cat,sub_cat', ignoreDuplicates: true });

		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1);
		const [cashflowRows, cashflowOpts] = s.postingPrototypeUpsert.mock.calls[0];
		expect(cashflowRows).toEqual([{ users_id: USER_ID, ...CASHFLOW_DEFAULTS[0] }]);
		expect(cashflowOpts).toEqual({ onConflict: 'users_id,cat,sub_cat', ignoreDuplicates: true });
	});

	it('THE KEY REGRESSION TEST (Sec F3 condition (b)): a user with EXISTING user_taxonomy rows but ZERO posting_prototype rows still gets posting_prototype provisioned — the guard does NOT short-circuit across tables', async () => {
		const s = makeSupabase({
			asset: { existing: { id: 1 } }, // already provisioned — this branch must skip
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS } // NOT provisioned — must still run
		});
		await provisionDefaultTaxonomy(s.client, USER_ID);

		expect(s.userTaxonomyUpsert).not.toHaveBeenCalled(); // asset branch correctly skipped
		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1); // cashflow branch reached anyway
		const [cashflowRows] = s.postingPrototypeUpsert.mock.calls[0];
		expect(cashflowRows).toEqual([{ users_id: USER_ID, ...CASHFLOW_DEFAULTS[0] }]);
	});

	it('the mirror of the key regression test: existing posting_prototype rows but ZERO user_taxonomy rows still provisions user_taxonomy', async () => {
		const s = makeSupabase({
			asset: { existing: null, defaults: ASSET_DEFAULTS },
			cashflow: { existing: { id: 37 } }
		});
		await provisionDefaultTaxonomy(s.client, USER_ID);

		expect(s.postingPrototypeUpsert).not.toHaveBeenCalled();
		expect(s.userTaxonomyUpsert).toHaveBeenCalledTimes(1);
		const [assetRows] = s.userTaxonomyUpsert.mock.calls[0];
		expect(assetRows).toEqual([{ users_id: USER_ID, ...ASSET_DEFAULTS[0] }]);
	});

	it('BRANCH INDEPENDENCE: a hard failure (guard read error) on the posting_prototype branch does not prevent the user_taxonomy branch from completing', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const s = makeSupabase({
			asset: { existing: null, defaults: ASSET_DEFAULTS },
			cashflow: { existingErr: { message: 'rls denied' } }
		});
		await expect(provisionDefaultTaxonomy(s.client, USER_ID)).resolves.toBeUndefined();

		expect(s.userTaxonomyUpsert).toHaveBeenCalledTimes(1); // unaffected sibling still ran
		expect(s.postingPrototypeUpsert).not.toHaveBeenCalled(); // its own guard errored, fail-soft
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('BRANCH INDEPENDENCE, the mirror: a hard failure on the user_taxonomy branch does not prevent posting_prototype from completing', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const s = makeSupabase({
			asset: { existingErr: { message: 'rls denied' } },
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS }
		});
		await expect(provisionDefaultTaxonomy(s.client, USER_ID)).resolves.toBeUndefined();

		expect(s.userTaxonomyUpsert).not.toHaveBeenCalled();
		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('does not upsert a branch whose default set is empty (independently per branch)', async () => {
		const s = makeSupabase({
			asset: { existing: null, defaults: [] },
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS }
		});
		await provisionDefaultTaxonomy(s.client, USER_ID);
		expect(s.userTaxonomyUpsert).not.toHaveBeenCalled();
		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1);
	});

	it('is fail-soft on a default-read error, per branch (logs, no upsert for that branch, sibling unaffected)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const s = makeSupabase({
			asset: { existing: null, defaultsErr: { message: 'boom' } },
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS }
		});
		await expect(provisionDefaultTaxonomy(s.client, USER_ID)).resolves.toBeUndefined();
		expect(s.userTaxonomyUpsert).not.toHaveBeenCalled();
		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	// Sec positive-verification (SELF-311, carried forward at 084): the RLS WITH-CHECK RAISE on
	// EITHER upsert must be caught → logged → graceful degrade, NOT a hard 500 on every nav.
	// Scenario: a pre-041-shape aal2 backstop rejects the write with 42501 (returned by
	// supabase-js as { error }, not thrown). Asserts the upsert WAS reached (so the try/catch scope
	// genuinely covers the provision write) and the raise is swallowed fail-soft, on EACH branch
	// independently.
	it('is fail-soft on an RLS WITH-CHECK raise from EITHER upsert (aal2-at-aal1 42501) — logs, reaches upsert, never throws, sibling unaffected', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const s = makeSupabase({
			asset: {
				existing: null,
				defaults: ASSET_DEFAULTS,
				upsertErr: { message: 'new row violates row-level security policy for table "user_taxonomy" (42501)' }
			},
			cashflow: { existing: null, defaults: CASHFLOW_DEFAULTS }
		});
		await expect(provisionDefaultTaxonomy(s.client, USER_ID)).resolves.toBeUndefined();
		expect(s.userTaxonomyUpsert).toHaveBeenCalledTimes(1); // reached; its error was caught
		expect(s.postingPrototypeUpsert).toHaveBeenCalledTimes(1); // sibling unaffected, succeeded
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('is fail-soft when the chain itself throws before either branch runs (never blocks the load)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(provisionDefaultTaxonomy(client, USER_ID)).resolves.toBeUndefined();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});

// ============================================================================
// isAssignableAssetSubCat — SELF-235 / ADR-013 H1 (QA-added), reworked at 084. classify.server.
// test.ts already proves the classify ACTION returns 403 when the pre-check returns false, via a
// canned `preValidate: { found: false }` mock — but that never calls the REAL
// isAssignableAssetSubCat, so it cannot catch a regression to the function's OWN query
// construction.
//
// POST-084: `user_taxonomy` has no `domain` column any more — it IS the storage-classification
// (asset-only) table by construction (ADR-058 Decision 1's split). The pre-084 app-layer domain
// fence (`.eq('domain','asset')`) is now REDUNDANT-BY-CONSTRUCTION rather than removed-and-
// unreplaced: a `posting_prototype` id lives in a DISJOINT id-space (Decision 2's reserved-range
// construction) and simply cannot resolve a row in `user_taxonomy`'s table at all, which is a
// STRONGER guarantee than a column filter (a filter can be dropped by accident; table identity
// cannot). The stub below is a small predicate-accumulating fake (not a canned true/false): each
// .eq() call narrows a filter set, and .maybeSingle() evaluates the accumulated filters against
// ONE fixed candidate row — so these tests exercise the REAL query chain's filtering semantics,
// not a mock that already knows the answer.
// ============================================================================

type CandidateRow = { id: number; is_active: boolean } | null;

function makeSubCatQueryStub(row: CandidateRow) {
	const filters: Record<string, unknown> = {};
	const eqCalls: Array<[string, unknown]> = [];
	const maybeSingle = vi.fn(async () => {
		const matches =
			row !== null && Object.entries(filters).every(([k, v]) => (row as Record<string, unknown>)[k] === v);
		return { data: matches ? { id: row!.id } : null, error: null };
	});
	// eq() returns itself so the real chain shape (.eq().eq().maybeSingle()) resolves regardless
	// of call order/count — the ACCUMULATED filter set is what's evaluated.
	const chain: { eq: ReturnType<typeof vi.fn>; maybeSingle: typeof maybeSingle } = {
		eq: vi.fn((col: string, val: unknown) => {
			filters[col] = val;
			eqCalls.push([col, val]);
			return chain;
		}),
		maybeSingle
	};
	const select = vi.fn(() => chain);
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, eqCalls, maybeSingle, from };
}

/** A read stub whose maybeSingle unconditionally errors — for the fail-closed leg. */
function makeErroringSubCatQueryStub(message: string) {
	const maybeSingle = vi.fn(async () => ({ data: null, error: { message } }));
	const chain: { eq: ReturnType<typeof vi.fn>; maybeSingle: typeof maybeSingle } = {
		eq: vi.fn(() => chain),
		maybeSingle
	};
	const select = vi.fn(() => chain);
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client };
}

describe('isAssignableAssetSubCat — post-084 app-layer check (SELF-235)', () => {
	it('accepts a same-tenant, active sub_cat_id resolving in user_taxonomy', async () => {
		const { client } = makeSubCatQueryStub({ id: 55, is_active: true });
		await expect(isAssignableAssetSubCat(client, 55)).resolves.toBe(true);
	});

	it('TEETH: the query chain filters on id AND is_active — proves both fences are IN the query, not coincidentally passing', async () => {
		const { client, eqCalls } = makeSubCatQueryStub({ id: 55, is_active: true });
		await isAssignableAssetSubCat(client, 55);
		expect(eqCalls).toContainEqual(['id', 55]);
		expect(eqCalls).toContainEqual(['is_active', true]);
	});

	it('NO domain filter is issued post-084 — the column no longer exists, and asserting one would break this test the day the split lands', async () => {
		const { client, eqCalls } = makeSubCatQueryStub({ id: 55, is_active: true });
		await isAssignableAssetSubCat(client, 55);
		expect(eqCalls.some(([col]) => col === 'domain')).toBe(false);
	});

	it('rejects a RETIRED (is_active=false) sub_cat_id', async () => {
		const { client } = makeSubCatQueryStub({ id: 55, is_active: false });
		await expect(isAssignableAssetSubCat(client, 55)).resolves.toBe(false);
	});

	it('rejects a nonexistent id — the shape a cross-tenant OR a cross-table (posting_prototype, disjoint id-space per Decision 2) id resolves to under RLS/table-identity', async () => {
		const { client } = makeSubCatQueryStub(null);
		await expect(isAssignableAssetSubCat(client, 999)).resolves.toBe(false);
	});

	it('fails CLOSED on a read error (an unverifiable check is never treated as "valid")', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeErroringSubCatQueryStub('connection reset');
		await expect(isAssignableAssetSubCat(client, 55)).resolves.toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});
