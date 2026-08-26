// transactions.classify.test.ts — SELF-248 unit coverage for checkClassifiable / classifyTrans
// (V1.3 pre-flight re-derived ACs; docs/records/v13-preflight/rederived-acs.md). Mocked supabase
// chain, one behavior per table read/write. Companion to the endpoint-orchestration test at
// ../../../routes/api/transactions/[trans_id]/classify/classify.server.test.ts.
//
// INVERSION DISCIPLINE (memory: "a leg that cannot fail is the tell"): each classifiability rule
// gets its OWN test that flips ONLY that rule's field and asserts the SPECIFIC reason code — not
// just "some 409". A test asserting only `ok === false` cannot distinguish M1 from M4 from a typo
// in the predicate order, so every leg names its own refusal reason.

import { describe, it, expect } from 'vitest';
import { checkClassifiable, classifyTrans } from './transactions';

type TransRow = {
	trans_id: number;
	transaction_type: string;
	security_id: number | null;
	is_reverse: boolean;
};
type AnnotationRow = { trans_id: number; journal_id: number | null };

function makeSupabase(opts: {
	trans?: { data: TransRow | null; error: { message: string } | null };
	splitCount?: { count: number | null; error: { message: string } | null };
	annotation?: { data: AnnotationRow | null; error: { message: string } | null };
	upsertError?: { code?: string; message: string } | null;
	captured?: { calls: unknown[] };
}) {
	const trans = opts.trans ?? { data: null, error: null };
	const splitCount = opts.splitCount ?? { count: 0, error: null };
	const annotation = opts.annotation ?? { data: null, error: null };
	const upsertError = opts.upsertError ?? null;

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
				if (table === 'account_trans_split') {
					return {
						select: (_cols: string, _selOpts: unknown) => ({
							eq: (_col: string, _val: unknown) => Promise.resolve(splitCount)
						})
					};
				}
				if (table === 'account_trans_annotation') {
					return {
						select: (_cols: string) => ({
							eq: (_col: string, _val: unknown) => ({
								maybeSingle: () => Promise.resolve(annotation)
							})
						}),
						upsert: (row: unknown, upsertOpts: unknown) => {
							opts.captured?.calls.push({ row, opts: upsertOpts });
							return Promise.resolve({ error: upsertError });
						}
					};
				}
				throw new Error(`unexpected table in test double: ${table}`);
			}
		})
	} as unknown as Parameters<typeof checkClassifiable>[0];
}

const CLASSIFIABLE_TRANS: TransRow = {
	trans_id: 1,
	transaction_type: 'standard',
	security_id: null,
	is_reverse: false
};

describe('checkClassifiable — S-1/S-4 predicate, one leg per test', () => {
	it('not found (RLS-invisible or absent) → not_found, no existence leak', async () => {
		const supabase = makeSupabase({ trans: { data: null, error: null } });
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'not_found' });
	});

	it('M1 — transaction_type <> standard → not_standard', async () => {
		const supabase = makeSupabase({
			trans: { data: { ...CLASSIFIABLE_TRANS, transaction_type: 'trade' }, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'not_standard' });
	});

	it('M2 — security_id IS NOT NULL → has_security', async () => {
		const supabase = makeSupabase({
			trans: { data: { ...CLASSIFIABLE_TRANS, security_id: 42 }, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'has_security' });
	});

	it('E1 — is_reverse = true → is_reversal', async () => {
		const supabase = makeSupabase({
			trans: { data: { ...CLASSIFIABLE_TRANS, is_reverse: true }, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'is_reversal' });
	});

	it('M4 — split_count > 0 (a split parent) → split_parent', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			splitCount: { count: 2, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'split_parent' });
	});

	it('M3 — annotation.journal_id IS NOT NULL → journaled', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			annotation: { data: { trans_id: 1, journal_id: 55 }, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'refused', reason: 'journaled' });
	});

	it('all five legs pass, no annotation yet → classifiable, annotationExists=false', async () => {
		const supabase = makeSupabase({ trans: { data: CLASSIFIABLE_TRANS, error: null } });
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'classifiable', annotationExists: false });
	});

	it('all five legs pass, annotation exists with journal_id NULL → classifiable, annotationExists=true', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			annotation: { data: { trans_id: 1, journal_id: null }, error: null }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'classifiable', annotationExists: true });
	});

	it('an unexpected read error on any leg → status error (never silently classifiable)', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			splitCount: { count: null, error: { message: 'connection reset' } }
		});
		const result = await checkClassifiable(supabase, 1);
		expect(result).toEqual({ status: 'error' });
	});
});

describe('classifyTrans — write path', () => {
	it('refused (not classifiable) → typed 409 with the reason code, upsert never called', async () => {
		const captured = { calls: [] as unknown[] };
		const supabase = makeSupabase({
			trans: { data: { ...CLASSIFIABLE_TRANS, is_reverse: true }, error: null },
			captured
		});
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'is_reversal',
			message: 'A reversal row cannot be classified. Classify the original transaction it replaces.'
		});
		expect(captured.calls).toHaveLength(0);
	});

	it('not_found → plain 404, no code, upsert never called', async () => {
		const captured = { calls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: null, error: null }, captured });
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({ ok: false, status: 404, message: 'Transaction not found.' });
		expect(captured.calls).toHaveLength(0);
	});

	it('a verification read error → 500, upsert never called (fail closed, never a silent write)', async () => {
		const captured = { calls: [] as unknown[] };
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			annotation: { data: null, error: { message: 'timeout' } },
			captured
		});
		const result = await classifyTrans(supabase, 1, 7);
		expect(result.ok).toBe(false);
		expect((result as { status: number }).status).toBe(500);
		expect(captured.calls).toHaveLength(0);
	});

	it('classifiable, no prior annotation → INSERT-shaped upsert, sub_cat_id ONLY (note/metadata/journal_id omitted)', async () => {
		const captured = { calls: [] as unknown[] };
		const supabase = makeSupabase({ trans: { data: CLASSIFIABLE_TRANS, error: null }, captured });
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({ ok: true, transId: 1 });
		expect(captured.calls).toEqual([{ row: { trans_id: 1, sub_cat_id: 7 }, opts: { onConflict: 'trans_id' } }]);
	});

	it('classifiable, prior annotation exists → SAME sub_cat_id-only payload (an existing note must not be clobbered)', async () => {
		const captured = { calls: [] as unknown[] };
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			annotation: { data: { trans_id: 1, journal_id: null }, error: null },
			captured
		});
		const result = await classifyTrans(supabase, 1, 9);
		expect(result).toEqual({ ok: true, transId: 1 });
		expect(captured.calls).toEqual([{ row: { trans_id: 1, sub_cat_id: 9 }, opts: { onConflict: 'trans_id' } }]);
	});

	it('DB raise: the #10 cross-tenant/cross-vocab Sub-Cat fence → 400 invalid_sub_cat_id', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: { code: 'P0001', message: 'Sub-Cat reference rejected: sub_cat_id 999 is not a taxonomy row...' }
		});
		const result = await classifyTrans(supabase, 1, 999);
		expect(result).toEqual({
			ok: false,
			status: 400,
			field: 'sub_cat_id',
			code: 'invalid_sub_cat_id',
			message: 'That category is not available.'
		});
	});

	it('FK violation (23503, defensive fallback) → 400 invalid_sub_cat_id', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: { code: '23503', message: 'foreign key violation' }
		});
		const result = await classifyTrans(supabase, 1, 999);
		expect(result.ok).toBe(false);
		expect((result as { status: number; code?: string }).status).toBe(400);
		expect((result as { code?: string }).code).toBe('invalid_sub_cat_id');
	});

	it('D-8 condition 6 — DB raise: 092s "rejected" leg (verbatim prefix) → 409 journaled_cat_conflict, DISTINCT from the app-level `journaled` code', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			// Verbatim prefix from 092 (fn_account_trans_annotation_journaled_cat_fence): "journaled-leg
			// classification rejected: trans_id % is attached to journal % and so cannot carry a %
			// classification (sub_cat_id %) — a journaled leg must post to Journal Clearing, ..."
			upsertError: {
				code: 'P0001',
				message:
					'journaled-leg classification rejected: trans_id 1 is attached to journal 55 and so cannot carry a Revenue classification (sub_cat_id 7) — a journaled leg must post to Journal Clearing, and this class would post it as income or spending instead. Reclassify the leg (Transfer or Trade), or detach it from the journal first (SELF-248 AC10 / ADR-058 084 P3)'
			}
		});
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'journaled_cat_conflict',
			message:
				'This leg is now posted to a journal as Revenue, Expense, or Equity — reclassifying it that way is blocked to protect the journal. Detach it, then classify.'
		});
		// The two codes must never collide — this is the whole point of D-8 condition 6.
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).not.toBe('journaled');
	});

	it('D-8 condition 6 — DB raise: 092s "fence" leg (unresolvable prototype, verbatim prefix) → also 409 journaled_cat_conflict', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			// Verbatim prefix from 092: "journaled-leg classification fence: cannot resolve class
			// (sub_cat_id %) for trans_id % attached to journal % — not found or not visible under
			// current AAL; fail-closed (SELF-248 AC10)"
			upsertError: {
				code: 'P0001',
				message:
					'journaled-leg classification fence: cannot resolve class (sub_cat_id 999) for trans_id 1 attached to journal 55 — not found or not visible under current AAL; fail-closed (SELF-248 AC10)'
			}
		});
		const result = await classifyTrans(supabase, 1, 999);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).toBe('journaled_cat_conflict');
		expect(result.status).toBe(409);
	});

	it('COLLISION GUARD — the #12 journal-ATTACH fence (033, "journal attach rejected: ... matched-tenant ...") is NOT miscoded as journaled_cat_conflict; a loose /journal/i test would have collided here', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			// Verbatim from 033 (fn_account_trans_annotation_matched_journal) — a DIFFERENT write
			// (attaching journal_id) this endpoint never performs, but the raise text contains the
			// word "journal" just like 092's fence does, so the classifier MUST key off the prefix.
			upsertError: {
				code: 'P0001',
				message:
					'journal attach rejected: journal_id 3 is not a journal owned by and visible to the tenant of trans_id 1 — not found, not visible under current AAL, or cross-tenant (ADR-011 Decision 3 canonical instance #12 / matched-tenant leg fence, hybrid-resolved; M2 / SELF-295)'
			}
		});
		const result = await classifyTrans(supabase, 1, 7);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).not.toBe('journaled_cat_conflict');
		// Falls through to the matched-tenant classifier (it says "matched-tenant") — a generic,
		// still-safe 400, not a security hole; this write path never sets journal_id so the raise is
		// unreachable through THIS endpoint in practice. Recorded so the classification is INTENTIONAL,
		// not accidental.
		expect(result.code).toBe('invalid_sub_cat_id');
		expect(result.status).toBe(400);
	});

	it('an unexpected DB error code → 500, not silently reclassified as a 4xx', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: { code: '53300', message: 'too many connections' }
		});
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({ ok: false, status: 500, message: 'Could not save the category. Please try again.' });
	});

	// SELF-249 Sec FLAG-B (PR #564, option C): 084's trade-constraint raises. Same fix, same
	// collision reason, as upsertAnnotation's mirror coverage in transactions.upsertAnnotation.test.ts.
	it('FLAG-B — the consistency-violation raise (s2a) → 409 trade_constraint, not the generic 500', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: {
				code: 'P0001',
				message:
					"Trade consistency violation (ADR-031 Amendment 1 s2a): security_id 42 and cat=Income must satisfy (security_id present <=> cat='Trade') (M1-evt / SELF-293)"
			}
		});
		const result = await classifyTrans(supabase, 1, 7);
		expect(result).toEqual({
			ok: false,
			status: 409,
			field: 'sub_cat_id',
			code: 'trade_constraint',
			message: 'A Trade category is for security transactions. Pick a cash-flow category instead.'
		});
	});

	it('FLAG-B — the sign-alignment raise (s2b, contains the literal "sub_cat" substring) → also 409 trade_constraint, NOT invalid_sub_cat_id', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: {
				code: 'P0001',
				message: 'Trade sign-alignment (ADR-031 Amendment 1 s2b): sub_cat BTO requires quantity > 0 (buy), got -3 (M1-evt / SELF-293)'
			}
		});
		const result = await classifyTrans(supabase, 1, 7);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).toBe('trade_constraint');
		expect(result.status).toBe(409);
	});

	it('FLAG-B COLLISION GUARD — the fail-closed unresolvable-row raise on the SAME trigger is NOT reclassified as trade_constraint (falls to invalid_sub_cat_id via isCrossTenantSubCat, pre-existing behavior unchanged)', async () => {
		const supabase = makeSupabase({
			trans: { data: CLASSIFIABLE_TRANS, error: null },
			upsertError: {
				code: 'P0001',
				message:
					'Trade constraint: cannot resolve fact (trans_id 1) or class (sub_cat_id 7) — not found or not visible under current AAL; fail-closed (M1-evt / SELF-293)'
			}
		});
		const result = await classifyTrans(supabase, 1, 7);
		if (result.ok) throw new Error('expected a refusal');
		expect(result.code).not.toBe('trade_constraint');
		expect(result.code).toBe('invalid_sub_cat_id');
		expect(result.status).toBe(400);
	});
});
