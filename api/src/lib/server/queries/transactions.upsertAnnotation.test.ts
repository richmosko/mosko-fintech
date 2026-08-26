// transactions.upsertAnnotation.test.ts — SELF-249 binding option-B unit coverage (F/CTO-ruled at
// PR #561 Sec joint review, 2026-08-25; Linear SELF-249 comment) for `upsertAnnotation`, the OLD
// recategorize path's only write. Two required items:
//   (1) E1 write-side refusal — an is_reverse row refuses the write, upsert never called.
//   (2) Sec FLAG-2 — the journaled-cat-fence raise must classify AHEAD of the cross-tenant raise.
//
// Test cases (1)/(2)/collision-guard/regression below were drafted by qa-249 (advisory scratch at
// ~/Projects/mosko-fintech-worktrees/qa/temp/self249-walk-plan.md, root-caused independently
// against current main) and adopted here near-verbatim — they mirror transactions.classify.test.ts's
// existing pattern for the NEW path, so the OLD path now gets the same shape of proof. Extended
// with the not-found/read-error/positive-path legs classify.test.ts also carries for checkClassifiable
// (this file's E1 check is a fused pre-check inside upsertAnnotation, not a separate function, so
// those legs get exercised through upsertAnnotation directly instead).
//
// INVERSION DISCIPLINE (memory: "a leg that cannot fail is the tell"): each rule gets its OWN test
// asserting the SPECIFIC status/code — not just "some failure" — and the two refusal paths (E1,
// FLAG-2) each assert the downstream write call never fires.

import { describe, it, expect } from 'vitest';
import { upsertAnnotation, REVERSAL_RECATEGORIZE_MESSAGE } from './transactions';

type TransRow = { trans_id: number; is_reverse: boolean };
type AnnotationUpsertResult = { error: { code?: string; message: string } | null };
type AnnotationDeleteResult = { error: { message: string } | null };

function makeSupabase(opts: {
	trans?: { data: TransRow | null; error: { message: string } | null };
	upsertResult?: AnnotationUpsertResult;
	deleteResult?: AnnotationDeleteResult;
	captured?: { upsertCalls: unknown[]; deleteCalls: unknown[] };
}) {
	const trans = opts.trans ?? { data: { trans_id: 1, is_reverse: false }, error: null };
	const upsertResult = opts.upsertResult ?? { error: null };
	const deleteResult = opts.deleteResult ?? { error: null };
	return {
		schema: (_schemaName: string) => ({
			from: (table: string) => {
				if (table === 'account_trans') {
					return {
						select: (_cols: string) => ({
							eq: (_col: string, _val: unknown) => ({
								maybeSingle: () => Promise.resolve(trans)
							})
						})
					};
				}
				if (table === 'account_trans_annotation') {
					return {
						delete: () => ({
							eq: (_col: string, _val: unknown) => {
								opts.captured?.deleteCalls.push({ transId: _val });
								return Promise.resolve(deleteResult);
							}
						}),
						upsert: (row: unknown, upsertOpts: unknown) => {
							opts.captured?.upsertCalls.push({ row, opts: upsertOpts });
							return Promise.resolve(upsertResult);
						}
					};
				}
				throw new Error(`unexpected table in test double: ${table}`);
			}
		})
	} as unknown as Parameters<typeof upsertAnnotation>[0];
}

describe('upsertAnnotation — SELF-249 E1 write-side refusal', () => {
	it('is_reverse = true → refused (409, is_reversal), upsert never called (qa-249 case 1)', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: { trans_id: 1, is_reverse: true }, error: null }, captured });
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'is_reversal',
			message: REVERSAL_RECATEGORIZE_MESSAGE
		});
		expect(captured.upsertCalls).toHaveLength(0);
	});

	it('is_reverse = true, clearing (both null) → also refused, delete never called', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: { trans_id: 1, is_reverse: true }, error: null }, captured });
		const result = await upsertAnnotation(supabase, 1, null, null);
		expect(result.ok).toBe(false);
		expect((result as { code?: string }).code).toBe('is_reversal');
		expect(captured.deleteCalls).toHaveLength(0);
	});

	it('is_reverse = false → proceeds to the normal upsert', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: { trans_id: 1, is_reverse: false }, error: null }, captured });
		const result = await upsertAnnotation(supabase, 1, 7, 'note');
		expect(result).toEqual({ ok: true, transId: 1 });
		expect(captured.upsertCalls).toEqual([
			{ row: { trans_id: 1, sub_cat_id: 7, note: 'note' }, opts: { onConflict: 'trans_id' } }
		]);
	});

	it('not found (RLS-invisible or absent) → 404, upsert never called (Sec PR #564 FLAG-C: was fail-OPEN — trans?.is_reverse on a null trans is undefined/falsy, so this used to fall through to the write)', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: null, error: null }, captured });
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({ ok: false, status: 404, message: 'Transaction not found.' });
		expect(captured.upsertCalls).toHaveLength(0);
	});

	it('an unexpected reversal-check read error → 500, upsert/delete never called (fail closed)', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: null, error: { message: 'connection reset' } }, captured });
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({ ok: false, status: 500, message: 'Could not verify this transaction. Please try again.' });
		expect(captured.upsertCalls).toHaveLength(0);
		expect(captured.deleteCalls).toHaveLength(0);
	});
});

describe('upsertAnnotation — SELF-249 Sec FLAG-2 (journaled-cat-fence classifies AHEAD of cross-tenant)', () => {
	it('092\'s verbatim defect-state raise (contains "(sub_cat_id %)", which also matches isCrossTenantSubCat) → journaled_cat_conflict, NOT "That category is not available" (qa-249 case 2)', async () => {
		const supabase = makeSupabase({
			// Verbatim prefix from 092 (fn_account_trans_annotation_journaled_cat_fence), same raise
			// shape asserted in transactions.classify.test.ts's D-8 condition 6 coverage.
			upsertResult: {
				error: {
					code: 'P0001',
					message:
						'journaled-leg classification rejected: trans_id 1 is attached to journal 55 and so cannot carry a Revenue classification (sub_cat_id 7) — a journaled leg must post to Journal Clearing, and this class would post it as income or spending instead. Reclassify the leg (Transfer or Trade), or detach it from the journal first (SELF-248 AC10 / ADR-058 084 P3)'
				}
			}
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'journaled_cat_conflict',
			message:
				'This leg is now posted to a journal as Revenue, Expense, or Equity — reclassifying it that way is blocked to protect the journal. Detach it, then classify.'
		});
	});

	it('COLLISION GUARD — the #12 journal-ATTACH fence (033, "journal attach rejected: ... matched-tenant ...") is NOT miscoded as journaled_cat_conflict (qa-249 case 3)', async () => {
		const supabase = makeSupabase({
			// Verbatim from 033 (fn_account_trans_annotation_matched_journal) — a DIFFERENT write
			// (attaching journal_id) this endpoint never performs, but the raise text contains the
			// word "journal" just like 092's fence does, so the classifier MUST key off the prefix.
			upsertResult: {
				error: {
					code: 'P0001',
					message:
						'journal attach rejected: journal_id 3 is not a journal owned by and visible to the tenant of trans_id 1 — not found, not visible under current AAL, or cross-tenant (ADR-011 Decision 3 canonical instance #12 / matched-tenant leg fence, hybrid-resolved; M2 / SELF-295)'
				}
			}
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).not.toBe('journaled_cat_conflict');
		// Falls through to isCrossTenantSubCat (it says "matched-tenant" / "Decision 3") — a generic,
		// still-safe 422, not a security hole; this write path never sets journal_id so the raise is
		// unreachable through THIS endpoint in practice. Recorded so the classification is INTENTIONAL.
		expect(result.status).toBe(422);
		expect(result.message).toBe('That category is not available.');
	});

	it('the #10/#13 cross-tenant Sub-Cat raise still maps to its own message, unaffected by the FLAG-2 ordering fix (qa-249 case 4)', async () => {
		const supabase = makeSupabase({
			upsertResult: {
				error: { code: 'P0001', message: 'Sub-Cat reference rejected: sub_cat_id 999 is not a taxonomy row...' }
			}
		});
		const result = await upsertAnnotation(supabase, 1, 999, null);
		expect(result).toEqual({
			ok: false,
			status: 422,
			field: 'sub_cat_id',
			message: 'That category is not available.'
		});
	});

	it('an unrelated DB error still falls through to the generic message, not either typed code', async () => {
		const supabase = makeSupabase({
			upsertResult: { error: { code: '53300', message: 'too many connections' } }
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({
			ok: false,
			status: 422,
			field: 'sub_cat_id',
			message: 'Could not save the category.'
		});
	});
});

describe('upsertAnnotation — clear path (both null) unaffected by the FLAG-2 fix', () => {
	it('clears the annotation when not a reversal row', async () => {
		const captured = { upsertCalls: [] as unknown[], deleteCalls: [] as unknown[] };
		const supabase = makeSupabase({ captured });
		const result = await upsertAnnotation(supabase, 1, null, null);
		expect(result).toEqual({ ok: true, transId: 1 });
		expect(captured.deleteCalls).toEqual([{ transId: 1 }]);
	});

	it('a delete error still surfaces the existing generic message', async () => {
		const supabase = makeSupabase({ deleteResult: { error: { message: 'timeout' } } });
		const result = await upsertAnnotation(supabase, 1, null, null);
		expect(result).toEqual({ ok: false, status: 422, message: 'Could not clear the category.' });
	});
});

// ── SELF-249 Sec FLAG-B (PR #564, option C) ────────────────────────────────────────────────
//
// 084's fn_account_trans_annotation_trade_constraints trigger raises two DISTINCT prefixes on
// pfin.account_trans_annotation; neither was classified before this fix. The sign-alignment
// raise's text contains "sub_cat %", which collides with isCrossTenantSubCat's regex — the same
// collision shape FLAG-2 already forced for isJournaledCatFenceRejection.
describe('upsertAnnotation — SELF-249 Sec FLAG-B (084 trade-constraint raises classify ahead of cross-tenant)', () => {
	it('the consistency-violation raise (s2a, no "sub_cat" substring — previously fell through to the generic 422) → 409 trade_constraint', async () => {
		const supabase = makeSupabase({
			upsertResult: {
				error: {
					code: 'P0001',
					message:
						"Trade consistency violation (ADR-031 Amendment 1 s2a): security_id 42 and cat=Income must satisfy (security_id present <=> cat='Trade') (M1-evt / SELF-293)"
				}
			}
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'trade_constraint',
			message: 'A Trade category is for security transactions. Pick a cash-flow category instead.'
		});
	});

	it('the sign-alignment raise (s2b — contains the literal "sub_cat" substring, previously miscoded via isCrossTenantSubCat) → also 409 trade_constraint, NOT "That category is not available"', async () => {
		const supabase = makeSupabase({
			upsertResult: {
				error: {
					code: 'P0001',
					message: 'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat BTO requires quantity > 0 (buy), got -3 (M1-evt / SELF-293)'
				}
			}
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'trade_constraint',
			message: 'A Trade category is for security transactions. Pick a cash-flow category instead.'
		});
	});

	it('COLLISION GUARD — the fail-closed unresolvable-row raise on the SAME trigger ("Trade constraint: cannot resolve...") is NOT reclassified as trade_constraint — it is an integrity break, not a user category choice; it falls to isCrossTenantSubCat instead (its "sub_cat_id" substring matches that regex too, pre-existing behavior unchanged by this fix)', async () => {
		const supabase = makeSupabase({
			upsertResult: {
				error: {
					code: 'P0001',
					message:
						'Trade constraint: cannot resolve fact (trans_id 1) or class (sub_cat_id 7) — not found or not visible under current AAL; fail-closed (M1-evt / SELF-293)'
				}
			}
		});
		const result = await upsertAnnotation(supabase, 1, 7, null);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).not.toBe('trade_constraint');
		expect(result.status).toBe(422);
		expect(result.message).toBe('That category is not available.');
	});
});
