// netWorth.test.ts — unit coverage for the §2.1.1 headline read (SELF-211).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_compute_nav', { p_as_of, p_active_only }) → { data, error }
//   .schema('pfin').from('account').select(...).or(...)    → { count, error }
//
// Proves: numeric coercion (number + Postgres-numeric-as-string), the $0-with-accounts
// vs zero-account-empty-state disambiguation, and fail-soft degrade on either read.
//
// ⚠ THIS FILE IS §7.9 AC 4's INSTANCE, and it is worth knowing how it hid. Before 059 it
// stubbed `.eq()` and asserted NOTHING about the predicate — so it named no column, was
// INVISIBLE to a grep for `is_active`, and would have gone on passing while the production
// query 400'd against a dropped column. A fully-mocked test that pins the CHAIN SHAPE but not
// the PREDICATE cannot fail for the reason you would want it to. The predicate assertion below
// is the fix: it is now impossible for this file to stay green while the real filter drifts.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNetWorthView } from './netWorth';

const AS_OF = '2026-07-20';

type MockOpts = {
	navData?: unknown;
	navError?: { message: string } | null;
	count?: number | null;
	countError?: { message: string } | null;
};

/** Minimal supabase-js stub: the two chains loadNetWorthView touches, nothing else. */
function makeSupabase(opts: MockOpts) {
	// Params are TYPED, not `() =>`: without them `.mock.calls[0]` is the empty tuple and the
	// predicate assertion below cannot index it — which is how a chain-shape-only mock stays
	// green through a predicate change in the first place.
	const rpc = vi.fn(async (_fn: string, _args: Record<string, unknown>) => ({
		data: opts.navData ?? null,
		error: opts.navError ?? null
	}));
	const or = vi.fn(async (_filter: string) => ({
		count: opts.count ?? null,
		error: opts.countError ?? null
	}));
	const select = vi.fn(() => ({ or }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, or, select, from, schema };
}

describe('loadNetWorthView', () => {
	it('happy path: numeric NAV + active accounts → number + hasAccounts', async () => {
		const { client, rpc, schema } = makeSupabase({ navData: 123456.78, count: 3 });
		const view = await loadNetWorthView(client, AS_OF);

		expect(view).toEqual({ netWorth: 123456.78, hasAccounts: true });
		// Called the INVOKER helper in the pfin schema with the as-of date + the current-state
		// active-only scope (SELF-322 / ADR-039 — the 2-arg fn_compute_nav; p_active_only:true
		// excludes soft-deleted accounts so the headline reconciles with §2.1.5 composition).
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_compute_nav', { p_as_of: AS_OF, p_active_only: true });
	});

	// THE PREDICATE, PINNED — the assertion whose absence let this file survive a dropped column.
	it('the account count uses the AS-OF closure predicate, at the SAME asOf as the NAV', async () => {
		const { client, or, rpc } = makeSupabase({ navData: 1, count: 1 });
		await loadNetWorthView(client, AS_OF);

		// Mirrors fn_compute_nav's `closed_at is null or closed_at > p_as_of` (059 / ADR-042).
		expect(or).toHaveBeenCalledWith(`closed_at.is.null,closed_at.gt.${AS_OF}`);

		// ⚠ NOT `.eq('closed_at', null)`. The current-state form is behaviourally IDENTICAL at
		// today's date — 058's gate refuses a future closed_at, so nothing satisfies
		// `closed_at > today` — which means no data-driven test can separate them and the wrong
		// re-point would be chosen silently. 059's own fn_compute_nav comment names this as its
		// dependency (4), "the one with no footprint". This assertion IS that footprint.
		//
		// And the date must be the SAME one the NAV used: the count exists to disambiguate the
		// empty-state from a real $0 AGAINST THAT NAV, so two dates would make the disambiguator
		// disagree with the thing it disambiguates the first time a past asOf is passed — which
		// 059 has just made legal by striking the ADR-039 N3 temporal fence.
		const navArgs = rpc.mock.calls[0][1];
		const orArg = or.mock.calls[0][0];
		expect(orArg).toContain(String(navArgs.p_as_of));
	});

	it('coerces a Postgres numeric returned as a string', async () => {
		const { client } = makeSupabase({ navData: '987654.3210', count: 1 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view.netWorth).toBe(987654.321);
		expect(view.hasAccounts).toBe(true);
	});

	it('$0 WITH accounts is a real zero, not the empty-state', async () => {
		const { client } = makeSupabase({ navData: 0, count: 2 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view).toEqual({ netWorth: 0, hasAccounts: true });
	});

	it('zero accounts → hasAccounts false (empty-state), even though NAV computes 0', async () => {
		const { client } = makeSupabase({ navData: 0, count: 0 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view).toEqual({ netWorth: 0, hasAccounts: false });
	});

	it('negative net worth passes through (liabilities > assets)', async () => {
		const { client } = makeSupabase({ navData: -5000, count: 1 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view.netWorth).toBe(-5000);
	});

	it('NULL NAV (no priced positions) → 0, not null', async () => {
		const { client } = makeSupabase({ navData: null, count: 1 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view.netWorth).toBe(0);
	});

	it('compute error → netWorth null (degrade), account presence still read', async () => {
		const { client } = makeSupabase({ navError: { message: 'permission denied' }, count: 2 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view).toEqual({ netWorth: null, hasAccounts: true });
	});

	it('non-finite coercion (NaN) → null, never a poisoned render', async () => {
		const { client } = makeSupabase({ navData: 'not-a-number', count: 1 });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view.netWorth).toBeNull();
	});

	it('count error → hasAccounts false (fail-soft)', async () => {
		const { client } = makeSupabase({ navData: 100, countError: { message: 'boom' } });
		const view = await loadNetWorthView(client, AS_OF);
		expect(view.hasAccounts).toBe(false);
		expect(view.netWorth).toBe(100);
	});
});
