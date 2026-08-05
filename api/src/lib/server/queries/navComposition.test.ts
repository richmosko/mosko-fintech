// navComposition.test.ts — unit coverage for the §2.1.5 NAV-composition read (SELF-226).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_nav_composition', { p_as_of }) → { data, error }
//
// Proves: the scalar-jsonb tree passes through unchanged (raw shape = Frontend's contract),
// asOf is threaded explicitly (so it foots to the headline), and the fail-soft degrade-to-null
// on both an RPC error and a null payload — the composition read must never take down the
// §2.1.1 headline netWorth.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNavComposition, type NavComposition } from './navComposition';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

type MockOpts = {
	data?: unknown;
	error?: { message: string } | null;
};

/** Minimal supabase-js stub: the single .schema('pfin').rpc(...) chain the helper touches. */
function makeSupabase(opts: MockOpts) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

const SAMPLE_TREE: NavComposition = {
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
	it('happy path: passes the jsonb tree through unchanged + threads asOf explicitly', async () => {
		const { client, rpc, schema } = makeSupabase({ data: SAMPLE_TREE });
		const tree = await loadNavComposition(client, AS_OF);

		// Raw shape preserved — no transform (the raw JSONB IS Frontend's contract).
		expect(tree).toEqual(SAMPLE_TREE);
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
		const tree = await loadNavComposition(client, AS_OF);
		expect(tree).toEqual(empty);
	});

	it('RPC error → null (fail-soft; headline must survive)', async () => {
		const { client } = makeSupabase({ error: { message: 'permission denied' } });
		const tree = await loadNavComposition(client, AS_OF);
		expect(tree).toBeNull();
	});

	it('null payload (unexpected) → null (degrade, do not assert a shape)', async () => {
		const { client } = makeSupabase({ data: null });
		const tree = await loadNavComposition(client, AS_OF);
		expect(tree).toBeNull();
	});
});
