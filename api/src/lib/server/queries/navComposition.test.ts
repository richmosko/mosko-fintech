// navComposition.test.ts — unit coverage for the §2.1.5 NAV-composition read (SELF-226).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_nav_composition', { p_as_of }) → { data, error }
//   .schema('pfin').from('account').select(...).in(...)    → { data, error }  (SELF-229 join)
//
// Proves: the scalar-jsonb tree passes through unchanged (raw shape = Frontend's contract),
// asOf is threaded explicitly (so it foots to the §2.1.1 headline, which now reads this SAME
// composed value — SELF-268 / R3 rider 0), the fail-soft degrade-to-null on both an RPC error
// and a null payload, and the SELF-229 per-row staleness join, including its REWORKED tri-state
// degrade. TWO independent causes of is_stale=null are both covered here: the caller's root
// staleness read being unknown (staleLinkedSourceIds === null, passed straight through without
// querying), and the per-row join itself failing — neither may ever collapse to `false`
// (team-lead catch, mirrors the SELF-220 Sec round 2 silent-fresh-on-failure rejection).
//
// ALSO covers `fetchNavComposition` (SELF-268) and `loadNavComposition`'s `precomputed` 4th
// parameter, extracted so a caller serving BOTH the headline and this foot on one page load
// (root `+page.server.ts`) makes exactly ONE `fn_nav_composition` RPC call, not two — see
// `nav-composition-flip.server.test.ts` for the page-level "one call, one shared value" proof.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
	fetchNavComposition,
	loadNavComposition,
	loadExcludedTaxLedgers,
	EMPTY_STALE_LINKED_SOURCE_IDS,
	type NavComposition
} from './navComposition';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

type MockOpts = {
	data?: unknown;
	error?: { message: string } | null;
	/** SELF-229: the `pfin.account` join leg. Only reachable when a non-empty stale set is
	 *  passed in — most tests below pass EMPTY_STALE_LINKED_SOURCE_IDS and never touch this. */
	accountJoin?: { data?: unknown; error?: { message: string } | null };
};

/**
 * Minimal supabase-js stub covering BOTH chains `loadNavComposition` can touch:
 *   .schema('pfin').rpc('fn_nav_composition', { p_as_of })        — the 051 read
 *   .schema('pfin').from('account').select(...).in(...)           — SELF-229's stale-account join
 * `schema()` returns one object exposing both `rpc` and `from`, since real supabase-js does too.
 */
function makeSupabase(opts: MockOpts) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const inFn = vi.fn(async () => ({
		data: opts.accountJoin?.data ?? [],
		error: opts.accountJoin?.error ?? null
	}));
	const select = vi.fn(() => ({ in: inFn }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema, from, select, in: inFn };
}

/** Raw pre-join account-leaf shape — mirrors exactly what 051's JSONB returns (no is_stale). */
type RawLeaf = {
	account_id: number;
	account_name: string;
	current_market_value: number;
	unrealized_gl: number | null;
};

const SAMPLE_TREE_RAW: {
	groups: { category: string; accounts: RawLeaf[]; subtotal: number }[];
	buildups: NavComposition['buildups'];
	nav: number;
} = {
	groups: [
		{
			category: 'depository',
			accounts: [
				{ account_id: 1, account_name: 'Checking', current_market_value: 5000, unrealized_gl: null }
			],
			subtotal: 5000
		},
		{
			category: 'liability',
			accounts: [
				{ account_id: 9, account_name: 'Card', current_market_value: -1200, unrealized_gl: null }
			],
			subtotal: -1200
		}
	],
	buildups: {
		total_non_re: 5000,
		gross_total: 5000,
		debt: 1200,
		// SELF-268 / E41-E42: envelopes, not plain numbers — the bootstrap-default 'unavailable'
		// shape (no bracket schedule seeded), the common real-world case for a fresh tenant.
		realized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' },
		unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' }
	},
	nav: 3800
};

describe('loadNavComposition', () => {
	it('happy path: threads asOf explicitly + attaches is_stale=false to every leaf (empty stale set)', async () => {
		const { client, rpc, schema } = makeSupabase({ data: SAMPLE_TREE_RAW });
		const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);

		// Raw values preserved; is_stale attached false everywhere — no stale linked_source_ids
		// were passed in, so resolveStaleAccountIds never even queries pfin.account, and an empty
		// (but SUCCESSFUL) join is a KNOWN "nothing is stale," not the UNKNOWN case below.
		expect(tree).toEqual({
			...SAMPLE_TREE_RAW,
			groups: SAMPLE_TREE_RAW.groups.map((g) => ({
				...g,
				accounts: g.accounts.map((a) => ({ ...a, is_stale: false }))
			}))
		});
		expect(schema).toHaveBeenCalledWith('pfin');
		// asOf passed explicitly (not left to the fn's current_date default) so this reads the
		// SAME day the §2.1.1 headline's netWorth.ts call passes (R3 rider 4).
		expect(rpc).toHaveBeenCalledWith('fn_nav_composition', { p_as_of: AS_OF });
	});

	it('zero-account tenant: well-formed empty tree passes through (NOT null)', async () => {
		const empty: NavComposition = {
			groups: [],
			buildups: {
				total_non_re: 0,
				gross_total: 0,
				debt: 0,
				// A COMPUTED envelope here, deliberately different from SAMPLE_TREE_RAW's
				// 'unavailable' — a zero-account tenant can still have a designated ledger + a
				// seeded bracket schedule; a genuinely computed $0 tax liability is a real value,
				// not a placeholder, and this fixture exercises that shape too.
				realized_tax_liab: { status: 'computed', amount: 0 },
				unrealized_tax_liab: { status: 'computed', amount: 0 }
			},
			nav: 0
		};
		const { client } = makeSupabase({ data: empty });
		const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(tree).toEqual(empty);
	});

	it('RPC error → null (fail-soft; headline must survive)', async () => {
		const { client } = makeSupabase({ error: { message: 'permission denied' } });
		const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(tree).toBeNull();
	});

	it('null payload (unexpected) → null (degrade, do not assert a shape)', async () => {
		const { client } = makeSupabase({ data: null });
		const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
		expect(tree).toBeNull();
	});

	// ── SELF-229: per-row stale-account join ──────────────────────────────────────────────
	describe('per-row staleness join', () => {
		it('non-empty stale set: only the matching leaf is marked, by account_id — not by position', async () => {
			const { client, from, select, in: inFn } = makeSupabase({
				data: SAMPLE_TREE_RAW,
				// linked_source_id 42 maps to account_id 9 (the Card liability leaf) — the OTHER
				// leaf (account_id 1) must stay false even though it comes first in the tree.
				accountJoin: { data: [{ account_id: 9, linked_source_id: 42 }] }
			});
			const tree = await loadNavComposition(client, AS_OF, new Set(['42']));

			expect(tree?.groups[0].accounts[0].is_stale).toBe(false); // account_id 1 (Checking)
			expect(tree?.groups[1].accounts[0].is_stale).toBe(true); // account_id 9 (Card)
			// The join actually ran, scoped to schema('pfin').from('account').
			expect(from).toHaveBeenCalledWith('account');
			expect(select).toHaveBeenCalledWith('account_id, linked_source_id');
			expect(inFn).toHaveBeenCalledWith('linked_source_id', ['42']);
		});

		it('empty stale set skips the join entirely — no pfin.account query at all', async () => {
			const { client, from } = makeSupabase({ data: SAMPLE_TREE_RAW });
			await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
			expect(from).not.toHaveBeenCalled();
		});

		// ── SELF-229 REWORK (team-lead catch, mirrors SELF-220 Sec round 2): a join-query
		// failure must degrade to is_stale=null (UNKNOWN) on every leaf, NEVER to false. `false`
		// would be indistinguishable from a successful join that confirmed the account healthy —
		// the exact silent-fresh-on-a-read-failure shape Sec rejected on the chart. This is the
		// discriminating leg QA's error-injection battery exercises.
		it('join query error degrades to is_stale=NULL (unknown) everywhere — never false, composition itself still renders', async () => {
			const { client } = makeSupabase({
				data: SAMPLE_TREE_RAW,
				accountJoin: { error: { message: 'connection reset' } }
			});
			const tree = await loadNavComposition(client, AS_OF, new Set(['42']));

			// Degrade is per-row-detail only — the tree is NOT nulled by a join-leg failure.
			expect(tree).not.toBeNull();
			const allLeaves = tree?.groups.flatMap((g) => g.accounts) ?? [];
			expect(allLeaves.every((a) => a.is_stale === null)).toBe(true);
			// The negative assertion is the point of this test: NOT false.
			expect(allLeaves.some((a) => a.is_stale === false)).toBe(false);
		});

		it('bigint round-trip: a numeric account_id from the join still matches a numeric leaf id (String() coercion both sides)', async () => {
			const { client } = makeSupabase({
				data: SAMPLE_TREE_RAW,
				accountJoin: { data: [{ account_id: 1, linked_source_id: 7 }] }
			});
			const tree = await loadNavComposition(client, AS_OF, new Set(['7']));
			expect(tree?.groups[0].accounts[0].is_stale).toBe(true);
		});
	});

	// ── SELF-229 SECOND REWORK: the CALLER's own root staleness read can itself be unknown
	// (staleness.is_stale === null, e.g. the 046 RPC failed upstream in +page.server.ts). That
	// propagates here as `staleLinkedSourceIds === null` — a THIRD input distinct from both
	// EMPTY_STALE_LINKED_SOURCE_IDS (known: nothing stale) and a populated Set (known: some stale).
	describe('root staleness unknown (staleLinkedSourceIds === null)', () => {
		it('null input → every leaf is_stale=NULL, and the pfin.account join is never attempted', async () => {
			const { client, from } = makeSupabase({ data: SAMPLE_TREE_RAW });
			const tree = await loadNavComposition(client, AS_OF, null);

			expect(tree).not.toBeNull();
			const allLeaves = tree?.groups.flatMap((g) => g.accounts) ?? [];
			expect(allLeaves.every((a) => a.is_stale === null)).toBe(true);
			expect(allLeaves.some((a) => a.is_stale === false)).toBe(false);
			// No point querying pfin.account when we don't even know what to look up.
			expect(from).not.toHaveBeenCalled();
		});
	});

	// ── fetchNavComposition (SELF-268) — the extracted low-level RPC-only fetch ───────────────
	describe('fetchNavComposition', () => {
		it('returns the raw tree unchanged on success', async () => {
			const { client, rpc } = makeSupabase({ data: SAMPLE_TREE_RAW });
			const raw = await fetchNavComposition(client, AS_OF);
			expect(raw).toEqual(SAMPLE_TREE_RAW);
			expect(rpc).toHaveBeenCalledWith('fn_nav_composition', { p_as_of: AS_OF });
		});

		it('RPC error → null, logged, never thrown', async () => {
			const { client } = makeSupabase({ error: { message: 'permission denied' } });
			const raw = await fetchNavComposition(client, AS_OF);
			expect(raw).toBeNull();
		});

		it('null payload (unexpected) → null', async () => {
			const { client } = makeSupabase({ data: null });
			const raw = await fetchNavComposition(client, AS_OF);
			expect(raw).toBeNull();
		});
	});

	// ── `precomputed` 4th param (SELF-268 / R3 rider 0) — the shared-single-RPC-call path ─────
	describe('loadNavComposition with a precomputed raw composition', () => {
		it('an already-fetched value is used DIRECTLY — fn_nav_composition is NEVER called again', async () => {
			const { client, rpc } = makeSupabase({ data: null }); // would fail if the RPC ran
			const tree = await loadNavComposition(
				client,
				AS_OF,
				EMPTY_STALE_LINKED_SOURCE_IDS,
				SAMPLE_TREE_RAW
			);

			expect(tree).toEqual({
				...SAMPLE_TREE_RAW,
				groups: SAMPLE_TREE_RAW.groups.map((g) => ({
					...g,
					accounts: g.accounts.map((a) => ({ ...a, is_stale: false }))
				}))
			});
			expect(rpc).not.toHaveBeenCalled();
		});

		it('an explicit `null` precomputed value (caller already tried and failed) degrades to null — no retry RPC', async () => {
			const { client, rpc } = makeSupabase({ data: SAMPLE_TREE_RAW }); // would succeed if retried
			const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS, null);

			expect(tree).toBeNull();
			expect(rpc).not.toHaveBeenCalled();
		});

		it('omitting the 4th argument entirely still self-fetches (back-compat default)', async () => {
			const { client, rpc } = makeSupabase({ data: SAMPLE_TREE_RAW });
			const tree = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);

			expect(tree).not.toBeNull();
			expect(rpc).toHaveBeenCalledWith('fn_nav_composition', { p_as_of: AS_OF });
		});
	});
});

// ── loadExcludedTaxLedgers (SELF-268 AC 10a / R3 rider 6) ──────────────────────────────────────
describe('loadExcludedTaxLedgers', () => {
	type LedgersMockOpts = {
		ledgers?: unknown;
		ledgersError?: { message: string } | null;
		accounts?: unknown;
		accountsError?: { message: string } | null;
	};

	/**
	 * Minimal supabase-js stub covering the TWO chains this loader touches:
	 *   .schema('pfin').rpc('fn_tax_authority_ledgers')                — 102's designation reader
	 *   .schema('pfin').from('account').select(...).in(...)            — the account-name join
	 * Deliberately SEPARATE from the composition suite's `makeSupabase` above — this loader never
	 * touches `fn_nav_composition`, and entangling the two mocks would obscure that.
	 */
	function makeSupabase(opts: LedgersMockOpts) {
		const rpc = vi.fn(async () => ({
			data: opts.ledgers ?? null,
			error: opts.ledgersError ?? null
		}));
		const inFn = vi.fn(async () => ({
			data: opts.accounts ?? [],
			error: opts.accountsError ?? null
		}));
		const select = vi.fn(() => ({ in: inFn }));
		const from = vi.fn(() => ({ select }));
		const schema = vi.fn(() => ({ rpc, from }));
		const client = { schema } as unknown as SupabaseClient;
		return { client, rpc, from, select, in: inFn };
	}

	it('happy path: joins the designation rows to account names, VERBATIM jurisdiction values', async () => {
		const { client, rpc, from, in: inFn } = makeSupabase({
			ledgers: [
				{ account_id: 7, tax_jurisdiction: 'irs' },
				{ account_id: 9, tax_jurisdiction: 'ftb' }
			],
			accounts: [
				{ account_id: 7, name: 'IRS Payments' },
				{ account_id: 9, name: 'FTB Payments' }
			]
		});

		const result = await loadExcludedTaxLedgers(client);

		expect(result).toEqual([
			{ account_id: 7, account_name: 'IRS Payments', jurisdiction: 'irs' },
			{ account_id: 9, account_name: 'FTB Payments', jurisdiction: 'ftb' }
		]);
		expect(rpc).toHaveBeenCalledWith('fn_tax_authority_ledgers');
		expect(from).toHaveBeenCalledWith('account');
		expect(inFn).toHaveBeenCalledWith('account_id', [7, 9]);
	});

	it('no designations: a KNOWN empty result ([]), not null — the common bootstrap-default state', async () => {
		const { client, from } = makeSupabase({ ledgers: [] });
		const result = await loadExcludedTaxLedgers(client);

		expect(result).toEqual([]);
		// Nothing to join against — the account-name lookup is skipped entirely, same discipline
		// as resolveStaleAccountIds' own empty-set short-circuit above.
		expect(from).not.toHaveBeenCalled();
	});

	it('fn_tax_authority_ledgers RPC error → null (fail-soft; the §2.1.1/§2.1.5 surfaces must survive)', async () => {
		const { client } = makeSupabase({ ledgersError: { message: 'permission denied' } });
		const result = await loadExcludedTaxLedgers(client);
		expect(result).toBeNull();
	});

	it('account-name join error → null (KNOWN which accounts, unknown what to call them — degrade the whole result rather than guess a label)', async () => {
		const { client } = makeSupabase({
			ledgers: [{ account_id: 7, tax_jurisdiction: 'irs' }],
			accountsError: { message: 'connection reset' }
		});
		const result = await loadExcludedTaxLedgers(client);
		expect(result).toBeNull();
	});
});
