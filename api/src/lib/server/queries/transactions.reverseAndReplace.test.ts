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
 * touched four ways by `reverseAndReplaceTrans`: the (1) orig read (`select(...).eq().eq()
 * .maybeSingle()`), (2) the already-reversed count (`select(...,{count}).eq().eq()`), (2b) the
 * split-parent-refusal count on `account_trans_split` (`select(...,{count}).eq()`, ONE `.eq()`,
 * distinguishing it from (2)'s two), and (3) the batch insert (`insert([...]).select(...)`) —
 * differentiated below by table name + whether `select()` receives a `{count}` opts object.
 */
function makeSupabase(opts: {
	orig?: { data: OrigRow | null };
	reversedCount?: { count: number | null };
	splitCount?: { count: number | null; error?: { message: string } | null };
	insertResult?: {
		data: Array<{ trans_id: number; is_reverse: boolean }> | null;
		error: { message: string; code?: string } | null;
	};
	captured?: { insertedRows: unknown[] | null };
}) {
	const orig = opts.orig ?? { data: CASH_ORIG };
	const reversedCount = opts.reversedCount ?? { count: 0 };
	const splitCount = opts.splitCount ?? { count: 0, error: null };
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
				if (table === 'account_trans_split') {
					// (2b) the split-parent-refusal count — a single `.eq('account_trans_id', ...)`.
					return {
						select: (_cols: string, _selOpts?: { count?: string; head?: boolean }) => ({
							eq: (_c1: string, _v1: unknown) => Promise.resolve(splitCount)
						})
					};
				}
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

	it('a security-linked original (non-zero quantity) is REFUSED, not silently reversed — see the security-row-refusal describe block below for the full battery. (Sec veto: an earlier draft of this test asserted `ok: true` here, reasoning from a "documented/existing behavior" premise the SELF-340 joint options brief later measured false — that comment and premise are gone.)', async () => {
		const securityOrig: OrigRow = { ...CASH_ORIG, security_id: 42, quantity: 10 };
		const supabase = makeSupabase({ orig: { data: securityOrig } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result.ok).toBe(false);
	});

	it('both rows land — the insert succeeds instead of a NOT NULL violation (the end-to-end symptom QA repro\'d)', async () => {
		const supabase = makeSupabase({});
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: true, transId: 3 });
	});
});

// ── Split-parent refusal (SELF-248 AC5 / V1.3 pre-flight sitting item 9a + 10a) ────────────────
//
// QA's SELF-340 walk on THIS fix measured the ruling as missing: editing a split parent silently
// ORPHANED its children (the dead original kept rendering "Split · N"; the live corrected row
// rendered as a plain single line) — reverseAndReplaceTrans selected `orig` WITHOUT split_count
// and carried no split guard at all. AC5's ruled message, quoted verbatim with N substituted: "this
// transaction is split; removing the split will discard its N line categories, which cannot be
// recovered."
describe('reverseAndReplaceTrans — split-parent refusal (SELF-248 AC5, item 9a/10a)', () => {
	it('a split parent (split_count > 0) refuses BEFORE any write, states the REAL count, and never touches account_trans', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const supabase = makeSupabase({ splitCount: { count: 3, error: null }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({
			ok: false,
			status: 409,
			message:
				'This transaction is split; removing the split will discard its 3 line categories, which cannot be recovered. Unsplit it first, then edit.'
		});
		expect(captured.insertedRows).toBeNull();
	});

	it('a DIFFERENT split parent (split_count = 1) states ITS real count, not a hardcoded number — proves the count is read, not templated', async () => {
		const supabase = makeSupabase({ splitCount: { count: 1, error: null } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.message).toContain('discard its 1 line categories');
	});

	it('split_count = 0 (not a split parent) is UNAFFECTED — the existing edit flow still succeeds', async () => {
		const supabase = makeSupabase({ splitCount: { count: 0, error: null } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: true, transId: 3 });
	});

	it('a split-count read error fails CLOSED (500), never silently proceeding to a write that could orphan children', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const supabase = makeSupabase({ splitCount: { count: null, error: { message: 'connection reset' } }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 500, message: 'Could not verify this transaction. Please try again.' });
		expect(captured.insertedRows).toBeNull();
	});

	it('the double-edit guard (already-reversed) still wins BEFORE the split-count read fires, when both would refuse — order is preserved', async () => {
		const supabase = makeSupabase({ reversedCount: { count: 1 }, splitCount: { count: 5, error: null } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: 'This transaction has already been edited.' });
	});
});

// ── Security-row refusal (SELF-340 F/CTO ruling 2026-08-26 — Option A+C-deferred, PR #567) ─────
//
// A security-linked row carries four coupled numbers (quantity/cost_basis/amount/security_id)
// read by two different consumers (holdings vs GL); this cash-only edit path can only touch
// `amount`, so reversing one silently diverges holdings from the GL with no watcher. Refused
// across THREE fact-kinds by ONE predicate (`security_id IS NOT NULL OR transaction_type ===
// 'corp_action'`) — each gets its OWN fixture below per the ruled battery shape ("a single
// standard fixture leaves the others unproven").
const SECURITY_REFUSAL_MESSAGE = "A recorded security transaction can't be edited or removed in V1. A correction surface is planned.";

describe('reverseAndReplaceTrans — security-row refusal (SELF-340 F/CTO ruling, one leg per fact-kind)', () => {
	it('standard + security_id (088 manual purchase / provider ingest) → refused, zero rows inserted', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const orig: OrigRow = { ...CASH_ORIG, transaction_type: 'standard', security_id: 42, quantity: 10 };
		const supabase = makeSupabase({ orig: { data: orig }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: SECURITY_REFUSAL_MESSAGE });
		expect(captured.insertedRows).toBeNull();
	});

	it('acct_setup + security_id (087 opening position) → refused, zero rows inserted', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const orig: OrigRow = { ...CASH_ORIG, transaction_type: 'acct_setup', security_id: 99, quantity: 5, amount: 0 };
		const supabase = makeSupabase({ orig: { data: orig }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: SECURITY_REFUSAL_MESSAGE });
		expect(captured.insertedRows).toBeNull();
	});

	it('corp_action (039 stock split, security_id present — the realistic shape 039 always produces) → refused, zero rows inserted', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const orig: OrigRow = { ...CASH_ORIG, transaction_type: 'corp_action', security_id: 7, quantity: 50, amount: 0 };
		const supabase = makeSupabase({ orig: { data: orig }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: SECURITY_REFUSAL_MESSAGE });
		expect(captured.insertedRows).toBeNull();
	});

	it('corp_action with security_id NULL (the hypothetical/defensive leg — no V1 writer produces this, but the predicate must not rely on security_id alone for this fact-kind) → STILL refused', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const orig: OrigRow = { ...CASH_ORIG, transaction_type: 'corp_action', security_id: null, quantity: 0, amount: 0 };
		const supabase = makeSupabase({ orig: { data: orig }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: SECURITY_REFUSAL_MESSAGE });
		expect(captured.insertedRows).toBeNull();
	});

	it('the cash path (standard, security_id NULL) is UNAFFECTED — still succeeds', async () => {
		const supabase = makeSupabase({});
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: true, transId: 3 });
	});

	it('GUARD PRECEDENCE: the is_reverse guard still wins first (a reversal row is refused for BEING a reversal, before its security_id is even relevant)', async () => {
		const orig: OrigRow = { ...CASH_ORIG, security_id: 42, quantity: 10, is_reverse: true };
		const supabase = makeSupabase({ orig: { data: orig } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: 'A reversal row cannot be edited.' });
	});

	it('GUARD PRECEDENCE: the double-edit guard still wins BEFORE the security-row check fires, when both would refuse', async () => {
		const orig: OrigRow = { ...CASH_ORIG, security_id: 42, quantity: 10 };
		const supabase = makeSupabase({ orig: { data: orig }, reversedCount: { count: 1 } });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: 'This transaction has already been edited.' });
	});

	it('GUARD PRECEDENCE: the security-row refusal wins BEFORE the split-parent read, when both would refuse — a row that is BOTH security-linked AND has split children gets the security message, not the split message (proves order, not just outcome: if split ran first, the message would differ)', async () => {
		const captured: { insertedRows: unknown[] | null } = { insertedRows: null };
		const orig: OrigRow = { ...CASH_ORIG, security_id: 42, quantity: 10 };
		const supabase = makeSupabase({ orig: { data: orig }, splitCount: { count: 5, error: null }, captured });
		const result = await reverseAndReplaceTrans(supabase, 7, EDIT);
		expect(result).toEqual({ ok: false, status: 409, message: SECURITY_REFUSAL_MESSAGE });
		expect(captured.insertedRows).toBeNull();
	});
});
