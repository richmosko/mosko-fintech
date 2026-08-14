// navComposition.staleness.test.ts — QA-owned. The SELF-229 AC#2 per-leaf staleness JOIN
// (e7b8da9): behavioural coverage of loadNavComposition()'s tri-state is_stale degrade path.
//
// SEPARATE FILE ON PURPOSE, same reasoning as netWorth.boundary.test.ts:
//   1. `navComposition.test.ts` is Backend's own file and is CURRENTLY BROKEN (out of sync with
//      the new 3-arg loadNavComposition signature — per e7b8da9's own commit message, Backend's
//      rework of that file is pending hand-off, requested twice). Not touched here.
//   2. This file asserts BEHAVIOUR (the degrade path under a real join failure), which is a
//      different instrument from a fixture/shape test and should read as one.
//
// THE LEG THIS FILE EXISTS FOR (brief item 4, ⚠ RED-then-GREEN required): "on composition-join
// failure, per-leaf staleness must NOT silently render as not-stale." e7b8da9's own commit
// message documents a FIRST CUT that collapsed a join failure to `false` — the exact
// silent-fresh-on-failure shape SELF-220 Sec round 2 rejected on the chart — reworked to `null`
// (UNKNOWN) before it was ever committed. There is therefore no red commit in this repo's history
// to run this file against literally; what follows is written to CATCH THE OUTCOME (every leaf's
// is_stale ends up null, never false, on a join failure) rather than the mechanism, so it goes
// RED again immediately if the fail-to-false shape ever regresses — which is the whole point of
// having this test exist as a permanent fence, not a one-time repro.
//
// MOCK IDIOM: reuses netWorth.boundary.test.ts's `makeSupabase` pattern — a minimal stub
// SupabaseClient built with vi.fn() chains, typed via `as unknown as SupabaseClient` (the
// established house convention for this test tier; see that file's header for why a behavioural
// mock beats a call-shape assertion here too).
//
// @vitest-environment node

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNavComposition, EMPTY_STALE_LINKED_SOURCE_IDS } from './navComposition';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-08-14');

const COMPOSITION_TREE = {
	groups: [
		{
			category: 'investment',
			subtotal: 590_000,
			accounts: [
				{ account_id: 1, account_name: 'Brokerage', current_market_value: 500_000, unrealized_gl: 42_000 },
				{ account_id: 7, account_name: 'Old IRA', current_market_value: 90_000, unrealized_gl: -3_500 }
			]
		}
	],
	buildups: { total_non_re: 590_000, gross_total: 590_000, debt: 0, realized_tax_liab: 0, unrealized_tax_liab: 0 },
	nav: 590_000
};

/**
 * Supabase stub covering BOTH calls `loadNavComposition` makes: the `fn_nav_composition` RPC
 * (always succeeds here — this file is about the SEPARATE join, not the composition read itself)
 * and the `pfin.account` join select, whose outcome the caller controls via `joinResult`.
 */
function makeSupabase(joinResult: { data: unknown; error: { message: string } | null }) {
	const rpc = vi.fn(async () => ({ data: COMPOSITION_TREE, error: null }));
	const inFn = vi.fn(async () => joinResult);
	const select = vi.fn(() => ({ in: inFn }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	return { client: { schema } as unknown as SupabaseClient, inFn, from };
}

describe('loadNavComposition — per-leaf is_stale degrade path (behavioural, catches the OUTCOME not the mechanism)', () => {
	it('⚠ join query FAILS (error): every leaf is_stale is null (UNKNOWN) — NEVER false', async () => {
		const { client } = makeSupabase({ data: null, error: { message: 'connection reset' } });
		const result = await loadNavComposition(client, AS_OF, new Set(['42']));

		expect(result).not.toBeNull();
		const leaves = result!.groups.flatMap((g) => g.accounts);
		expect(leaves.length).toBeGreaterThan(0); // non-vacuous: the fixture has 2 leaves
		for (const leaf of leaves) {
			// The failure-mode assertion, stated positively AND negatively so a fixture change that
			// accidentally makes every leaf pass one form without the other is still caught: null
			// is required, and false (the historical bug's exact wrong answer) is explicitly ruled
			// out rather than merely "not asserted".
			expect(leaf.is_stale).toBeNull();
			expect(leaf.is_stale).not.toBe(false);
		}
	});

	it('join query SUCCEEDS with a real match: the matching leaf is true, the rest are false (not null)', async () => {
		// account_id 1 (Brokerage) resolves to a row in the join result; account_id 7 does not.
		const { client } = makeSupabase({ data: [{ account_id: 1, linked_source_id: '42' }], error: null });
		const result = await loadNavComposition(client, AS_OF, new Set(['42']));

		const brokerage = result!.groups[0].accounts.find((a) => a.account_id === 1)!;
		const oldIra = result!.groups[0].accounts.find((a) => a.account_id === 7)!;
		expect(brokerage.is_stale).toBe(true);
		expect(oldIra.is_stale).toBe(false);
	});

	it('caller has NOTHING stale (EMPTY_STALE_LINKED_SOURCE_IDS): the join is skipped and every leaf is false, not null', async () => {
		const { client, from } = makeSupabase({ data: [], error: null });
		const result = await loadNavComposition(client, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);

		// The zero-cost fast path: no `pfin.account` join query is issued at all.
		expect(from).not.toHaveBeenCalled();
		for (const leaf of result!.groups.flatMap((g) => g.accounts)) {
			expect(leaf.is_stale).toBe(false);
		}
	});

	it('the base fn_nav_composition read itself fails: still degrades to null (composition unavailable), the join is never reached', async () => {
		const rpc = vi.fn(async () => ({ data: null, error: { message: 'rpc down' } }));
		const inFn = vi.fn();
		const select = vi.fn(() => ({ in: inFn }));
		const from = vi.fn(() => ({ select }));
		const schema = vi.fn(() => ({ rpc, from }));
		const client = { schema } as unknown as SupabaseClient;

		const result = await loadNavComposition(client, AS_OF, new Set(['42']));
		expect(result).toBeNull();
		expect(inFn).not.toHaveBeenCalled();
	});
});
