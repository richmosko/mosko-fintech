// navComposition.test.ts — unit coverage for the §2.1.5 NAV-composition read (SELF-226).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_nav_composition', { p_as_of }) → { data, error }
//   .schema('pfin').from('account').select(...).in(...)    → { data, error }  (SELF-229 join)
//
// Proves: the scalar-jsonb tree passes through unchanged (raw shape = Frontend's contract),
// asOf is threaded explicitly (so it foots to the headline), the fail-soft degrade-to-null
// on both an RPC error and a null payload — the composition read must never take down the
// §2.1.1 headline netWorth — and the SELF-229 per-row staleness join, including its REWORKED
// tri-state degrade (join failure → is_stale=null, never false; team-lead catch, mirrors the
// SELF-220 Sec round 2 silent-fresh-on-failure rejection).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
	loadNavComposition,
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
		realized_tax_liab: 0,
		unrealized_tax_liab: 0
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
		// asOf passed explicitly (not left to the fn's current_date default) so the composition
		// foots to the headline's fn_compute_nav(asOf, true) by construction (051 FOOT-TO-NAV).
		expect(rpc).toHaveBeenCalledWith('fn_nav_composition', { p_as_of: AS_OF });
	});

	it('zero-account tenant: well-formed empty tree passes through (NOT null)', async () => {
		const empty: NavComposition = {
			groups: [],
			buildups: {
				total_non_re: 0,
				gross_total: 0,
				debt: 0,
				realized_tax_liab: 0,
				unrealized_tax_liab: 0
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
});
