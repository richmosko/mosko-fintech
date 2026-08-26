// transactions.reverseAndReplace.test.ts — SELF-340 regression coverage for `reverseAndReplaceTrans`
// (a supabase-js/PostgREST batch `.insert([reversal, corrected])` that sent the `corrected` row an
// EXPLICIT NULL for `quantity` — a key the sibling `reversal` object carried and `corrected` used
// to omit — unconditionally violating the `quantity NOT NULL DEFAULT 0` constraint on EVERY §2.4.3
// fact edit, live on `main` since d6b41cd5/SELF-204, ~1 month, found by SELF-249's walk gate).
//
// WHAT THIS FILE CAN AND CANNOT PROVE (read before trusting a green run here):
//   CAN observe — the actual JS objects `reverseAndReplaceTrans` constructs and hands to
//     `.insert([...])`: their key sets and the specific values on the fields SELF-340 touched
//     (quantity, security_id, replaces_trans_id, import_hash). The "identical key sets" test below
//     is a STRUCTURAL PRECONDITION guard: it does not know or simulate PostgREST's real
//     UNION-of-keys wire behavior — it instead makes that behavior IRRELEVANT by proving the two
//     objects never diverge in which keys they carry, so there is no key for the union to be
//     asymmetric over. This is deliberately NOT a mock that "restates the intended payload shape"
//     (the failure mode QA's finding names, docs/... qa-249-critical-finding): a shape-restating
//     mock would assert e.g. "corrected.quantity is sent as 0" without ever checking whether a
//     DIFFERENT field on the OTHER object could reintroduce the same class of bug. The key-set
//     identity check is falsifiable by a future edit that adds a field to one side only — it is a
//     mechanism-precondition guard, not an outcome restatement.
//   CANNOT observe — whether supabase-js/PostgREST actually implements the UNION-of-keys → explicit
//     NULL wire behavior as described (an external library/wire-protocol fact, unfalsifiable from a
//     mock); whether the DB schema's NOT NULL/CHECK constraints on the now-explicit values are
//     satisfied (e.g. that `0` really passes 017's cash CHECK on `quantity`, that `null` is a legal
//     `security_id`); or whether the real PostgREST endpoint accepts this exact payload end-to-end.
//     Those require a live DB round-trip. No such lane exists yet under `/api` (searched; none
//     found), `/tests` is QA's surface, and `supabase db reset` is banned for this session — so this
//     file's mocked coverage is deliberately paired with a live walk on THIS SAME PR (per the Linear
//     issue's own "the fix's own PR needs a walk leg" note) rather than claiming to close that gap
//     itself.
//
// INVERSION DISCIPLINE: the identical-key-set test is designed to be RED-provable by reverting the
// fix (see the backend engineer's own inversion run in the PR report) — reintroducing the
// heterogeneous key sets makes `Object.keys(reversal)` and `Object.keys(corrected)` differ, which
// this test catches mechanically, without needing to know WHICH field regressed.
//
// MEASURED, not assumed: an earlier draft of the "quantity" regression guard below asserted
// `corrected.quantity).not.toBeNull()`. Reverting the fix on a scratch copy did NOT redden that
// assertion — a genuinely-OMITTED key reads as JS `undefined`, and `undefined !== null`, so a
// value-equality check on a key that might not exist at all is not the same check as presence. The
// guard now uses the `in` operator (`'quantity' in corrected`), which DOES redden pre-fix — kept
// here as a concrete instance of "a leg that cannot fail is the tell", caught by inversion-running
// this file against the pre-fix code before trusting it.

import { describe, it, expect } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { reverseAndReplaceTrans } from './transactions';
import type { ManualTransEdit } from '$lib/server/schemas/transaction';

type OrigRow = {
	trans_id: number;
	account_id: number;
	transaction_date: string;
	amount: number;
	vendor: string | null;
	description: string | null;
	transaction_type: string;
	security_id: number | null;
	quantity: number | null;
	is_reverse: boolean;
	source_provider: string | null;
};

const CASH_ORIG: OrigRow = {
	trans_id: 1,
	account_id: 7,
	transaction_date: '2026-01-01',
	amount: 50,
	vendor: 'Coffee Shop',
	description: 'Latte',
	transaction_type: 'standard',
	security_id: null,
	quantity: 0,
	is_reverse: false,
	source_provider: null
};

const EDIT: ManualTransEdit = {
	orig_trans_id: 1,
	transaction_date: '2026-01-02',
	amount: 55,
	vendor: 'Coffee Shop',
	description: 'Latte + tip',
	sub_cat_id: null,
	note: null
};

/**
 * A supabase-js test double dispatched by table + call shape (mirrors the house pattern in
 * transactions.classify.test.ts / transactions.upsertAnnotation.test.ts). `account_trans` is
 * touched three ways by `reverseAndReplaceTrans`: the (1) orig read (`select(...).eq().eq()
 * .maybeSingle()`), (2) the already-reversed count (`select(...,{count}).eq().eq()`), and (3) the
 * batch insert (`insert([...]).select(...)`) — differentiated below by whether `select()` receives
 * a `{count}` opts object, and by which method (`insert` vs `select`) is called first off `from()`.
 */
function makeSupabase(opts: {
	orig?: { data: OrigRow | null };
	reversedCount?: { count: number | null };
	insertResult?: {
		data: Array<{ trans_id: number; is_reverse: boolean }> | null;
		error: { message: string; code?: string } | null;
	};
	captured?: { insertedRows: unknown[] | null };
}) {
	const orig = opts.orig ?? { data: CASH_ORIG };
	const reversedCount = opts.reversedCount ?? { count: 0 };
	const insertResult =
		opts.insertResult ??
		({
			data: [
				{ trans_id: 2, is_reverse: true },
				{ trans_id: 3, is_reverse: false }
			],
			error: null
		} as const);

	return {
		schema: (_schemaName: string) => ({
			from: (table: string) => {
				if (table !== 'account_trans') throw new Error(`unexpected table in test double: ${table}`);
				return {
					select: (_cols: string, selOpts?: { count?: string; head?: boolean }) => {
						if (selOpts?.count) {
							// (2) the already-reversed count.
							return {
								eq: (_c1: string, _v1: unknown) => ({
									eq: (_c2: string, _v2: unknown) => Promise.resolve(reversedCount)
								})
							};
						}
						// (1) the orig read.
						return {
							eq: (_c1: string, _v1: unknown) => ({
								eq: (_c2: string, _v2: unknown) => ({
									maybeSingle: () => Promise.resolve(orig)
								})
							})
						};
					},
					insert: (rows: unknown[]) => {
						if (opts.captured) opts.captured.insertedRows = rows;
						return { select: (_cols: string) => Promise.resolve(insertResult) };
					}
				};
			}
		})
	} as unknown as SupabaseClient;
}

describe('reverseAndReplaceTrans — SELF-340 batch-insert key-set regression', () => {
	it('STRUCTURAL GUARD: the two inserted objects carry IDENTICAL key sets — the mechanism precondition that makes PostgREST\'s real UNION-of-keys behavior harmless regardless of which fields differ in VALUE', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const supabase = makeSupabase({ captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result.ok).toBe(true);
		expect(captured.insertedRows).not.toBeNull();
		const [reversal, corrected] = captured.insertedRows as [Record<string, unknown>, Record<string, unknown>];
		expect(Object.keys(reversal).sort()).toEqual(Object.keys(corrected).sort());
	});

	it('the corrected row\'s quantity is the explicit number 0, never null or omitted (the exact field SELF-340 broke)', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const supabase = makeSupabase({ captured });
		await reverseAndReplaceTrans(supabase, 7, EDIT);
		const [, corrected] = captured.insertedRows as [Record<string, unknown>, Record<string, unknown>];
		expect('quantity' in corrected).toBe(true);
		expect(corrected.quantity).toBe(0);
		expect(corrected.quantity).not.toBeNull();
	});

	it('REGRESSION GUARD: quantity is a genuinely PRESENT key on both rows, not merely non-null (an omitted key and an explicit non-null value are indistinguishable by `!== null` alone — `undefined` is also `!== null` — so this checks presence with the `in` operator, the actual shape the bug\'s repro needs)', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const supabase = makeSupabase({ captured });
		await reverseAndReplaceTrans(supabase, 7, EDIT);
		const [reversal, corrected] = captured.insertedRows as [Record<string, unknown>, Record<string, unknown>];
		expect('quantity' in reversal).toBe(true);
		expect('quantity' in corrected).toBe(true);
	});

	it('a security-linked original (non-zero quantity) still reverses correctly, and the corrected row is still cash-flow-shaped (manualTransEditSchema carries no quantity/security_id fields to edit a trade by)', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const securityOrig: OrigRow = { ...CASH_ORIG, security_id: 42, quantity: 10 };
		const supabase = makeSupabase({ orig: { data: securityOrig }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result.ok).toBe(true);
		const [reversal, corrected] = captured.insertedRows as [Record<string, unknown>, Record<string, unknown>];
		// The reversal mirrors the original's security_id/quantity, negated.
		expect(reversal.security_id).toBe(42);
		expect(reversal.quantity).toBe(-10);
		// The corrected row is a fresh MANUAL cash-flow fact (manualTransEditSchema has no
		// security_id/quantity fields) — always security_id null, quantity 0, regardless of what
		// the original was. This is documented/existing behavior, not new to this fix — asserted
		// here so the SELF-340 fix does not silently change it.
		expect(corrected.security_id).toBeNull();
		expect(corrected.quantity).toBe(0);
	});

	it('both rows land — the insert succeeds instead of a NOT NULL violation (the end-to-end symptom QA repro\'d)', async () => {
		const supabase = makeSupabase({});
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: true, transId: 3 });
	});
});
