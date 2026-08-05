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
	//
	// ⚠ AND THE FIRST VERSION OF THIS ASSERTION WAS ITSELF THE DEFECT IT WAS ADDED TO CATCH.
	//   It pinned the literal string `closed_at.gt.${AS_OF}` — the BARE form, which 059 measures
	//   and rejects: `closed_at` is timestamptz, so `.gt.<date>` promotes to midnight and an
	//   account closed at 14:00 on asOf still counts as open. The assertion passed because it
	//   asserted THE CALL WE MADE rather than THE BEHAVIOUR WE NEEDED, and its comment repeated
	//   the same false reasoning the production comment did. Caught by Sec (#319 F1), not here.
	//   The cases below therefore test the DERIVATION — that the bound is the day AFTER asOf —
	//   with expected values written out by hand. A test that recomputes the bound with the same
	//   helper the production code uses would agree with it while both were wrong.
	it('the count bound is the DAY AFTER asOf, at the SAME asOf as the NAV', async () => {
		const { client, or, rpc } = makeSupabase({ navData: 1, count: 1 });
		await loadNetWorthView(client, AS_OF); // 2026-07-20

		// PostgREST cannot express `closed_at::date > p_as_of`, so the equivalent 059 rules
		// "behaviourally EQUIVALENT and therefore safe" is a half-open bound on the next day.
		expect(or).toHaveBeenCalledWith('closed_at.is.null,closed_at.gte.2026-07-21');

		// NOT `.gt.2026-07-20` (the bare form — includes an account closed at 14:00 that day) and
		// NOT `.eq('closed_at', null)` (current-state; drops the as-of question entirely).
		const orArg = or.mock.calls[0][0];
		expect(orArg).not.toContain(`gt.${AS_OF}`);

		// The NAV and the count must read ONE population: same date, and post-059 the same
		// GRANULARITY. The count's bound is derived FROM the NAV's date, so read it back out of
		// the recorded call rather than from a shared constant.
		const navArgs = rpc.mock.calls[0][1];
		expect(String(navArgs.p_as_of)).toBe(AS_OF);
	});

	// The +1-day arithmetic is where a hand-rolled bound goes wrong, so the boundaries are named
	// cases with hand-written expectations rather than a loop over a helper.
	const boundaries: Array<[string, string]> = [
		['2026-02-28', '2026-03-01'], // non-leap February end
		['2028-02-28', '2028-02-29'], // leap February, the day that only sometimes exists
		['2026-12-31', '2027-01-01'], // year end
		['2026-07-31', '2026-08-01'] // month end
	];
	for (const [asOf, expected] of boundaries) {
		it(`count bound rolls ${asOf} -> ${expected}`, async () => {
			const { client, or } = makeSupabase({ navData: 1, count: 1 });
			await loadNetWorthView(client, asOf);
			expect(or).toHaveBeenCalledWith(`closed_at.is.null,closed_at.gte.${expected}`);
		});
	}

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
