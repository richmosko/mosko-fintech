// transactions.recategorize.test.ts — SELF-249 binding option-B unit coverage (F/CTO-ruled at PR
// #561 Sec joint review, 2026-08-25; Linear SELF-249 comment) for the OLD recategorize path's two
// required items:
//   (1) checkNotReversalForRecategorize — the E1 write-side refusal.
//   (2) upsertAnnotation — Sec FLAG-2: the journaled-cat-fence raise must classify AHEAD of the
//       cross-tenant Sub-Cat raise.
//
// Mocked supabase chain, mirroring transactions.classify.test.ts's makeSupabase pattern.
//
// INVERSION DISCIPLINE (memory: "a leg that cannot fail is the tell"): the E1 test is RED-provable
// — reverting checkNotReversalForRecategorize's `is_reverse` guard on a copy makes its own test
// fail, and the FLAG-2 ordering test is RED-provable the same way (swap the two `if` branches and
// the "ahead of" test starts asserting the wrong code).

import { describe, it, expect } from 'vitest';
import { checkNotReversalForRecategorize, upsertAnnotation, REVERSAL_RECATEGORIZE_MESSAGE } from './transactions';

type TransRow = { trans_id: number; is_reverse: boolean };

function makeCheckSupabase(opts: {
	trans?: { data: TransRow | null; error: { message: string } | null };
}) {
	const trans = opts.trans ?? { data: null, error: null };
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
				throw new Error(`unexpected table in test double: ${table}`);
			}
		})
	} as unknown as Parameters<typeof checkNotReversalForRecategorize>[0];
}

describe('checkNotReversalForRecategorize — SELF-249 E1 write-side refusal', () => {
	it('is_reverse = true → refused', async () => {
		const supabase = makeCheckSupabase({ trans: { data: { trans_id: 1, is_reverse: true }, error: null } });
		expect(await checkNotReversalForRecategorize(supabase, 1)).toBe('refused');
	});

	it('is_reverse = false → ok', async () => {
		const supabase = makeCheckSupabase({ trans: { data: { trans_id: 1, is_reverse: false }, error: null } });
		expect(await checkNotReversalForRecategorize(supabase, 1)).toBe('ok');
	});

	it('not found (RLS-invisible or absent) → ok — no existence leak; the write path\'s own fences handle it', async () => {
		const supabase = makeCheckSupabase({ trans: { data: null, error: null } });
		expect(await checkNotReversalForRecategorize(supabase, 1)).toBe('ok');
	});

	it('an unexpected read error → error (fail closed, never silently ok)', async () => {
		const supabase = makeCheckSupabase({ trans: { data: null, error: { message: 'connection reset' } } });
		expect(await checkNotReversalForRecategorize(supabase, 1)).toBe('error');
	});

	it('the message shared with the caller names the remedy (same reason vocabulary as classifyTrans\'s is_reversal leg)', () => {
		expect(REVERSAL_RECATEGORIZE_MESSAGE).toBe(
			'A reversal row cannot be recategorized. Recategorize the original transaction it replaces.'
		);
	});
});

// ── upsertAnnotation FLAG-2 ─────────────────────────────────────────────────────────────────

type AnnotationDeleteResult = { error: { message: string } | null };
type AnnotationUpsertResult = { error: { code?: string; message: string } | null };

function makeAnnotationSupabase(opts: {
	deleteResult?: AnnotationDeleteResult;
	upsertResult?: AnnotationUpsertResult;
	captured?: { calls: unknown[] };
}) {
	const deleteResult = opts.deleteResult ?? { error: null };
	const upsertResult = opts.upsertResult ?? { error: null };
	return {
		schema: (_schemaName: string) => ({
			from: (table: string) => {
				if (table === 'account_trans_annotation') {
					return {
						delete: () => ({
							eq: (_col: string, _val: unknown) => Promise.resolve(deleteResult)
						}),
						upsert: (row: unknown, upsertOpts: unknown) => {
							opts.captured?.calls.push({ row, opts: upsertOpts });
							return Promise.resolve(upsertResult);
						}
					};
				}
				throw new Error(`unexpected table in test double: ${table}`);
			}
		})
	} as unknown as Parameters<typeof upsertAnnotation>[0];
}

describe('upsertAnnotation — SELF-249 Sec FLAG-2 (journaled-cat-fence classifies AHEAD of cross-tenant)', () => {
	it('092\'s verbatim defect-state raise (contains "(sub_cat_id %)", which also matches isCrossTenantSubCat) → journaled_cat_conflict, NOT "That category is not available"', async () => {
		const supabase = makeAnnotationSupabase({
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

	it('the #10/#13 cross-tenant Sub-Cat raise still maps to its own code, unaffected by the FLAG-2 ordering fix', async () => {
		const supabase = makeAnnotationSupabase({
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
		const supabase = makeAnnotationSupabase({
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
