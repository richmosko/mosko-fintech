// netWorth.test.ts — unit coverage for the §2.1.1 headline read (SELF-211).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_compute_nav', { p_as_of, p_active_only }) → { data, error }
//   .schema('pfin').from('account').select(...).eq(...)    → { count, error }
//
// Proves: numeric coercion (number + Postgres-numeric-as-string), the $0-with-accounts
// vs zero-account-empty-state disambiguation, and fail-soft degrade on either read.

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
	const rpc = vi.fn(async () => ({ data: opts.navData ?? null, error: opts.navError ?? null }));
	const eq = vi.fn(async () => ({ count: opts.count ?? null, error: opts.countError ?? null }));
	const select = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, eq, select, from, schema };
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
