// classify.server.test.ts — SELF-248 orchestration coverage for POST
// /api/transactions/:trans_id/classify. Mocked session + mocked supabase chain (the same shape
// transactions.classify.test.ts uses at the classifyTrans/checkClassifiable layer) — this file
// covers the HTTP-boundary concerns (auth, route-param shape, body validation, status/body
// mapping) that layer cannot see. AC2's `.strict()` mass-assignment fence + the D-8 condition 6
// distinguishable-codes contract are both exercised at this boundary too, end to end.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type Row = { trans_id: number; transaction_type: string; security_id: number | null; is_reverse: boolean };

function makeSupabase(opts: {
	trans?: { data: Row | null; error: unknown };
	splitCount?: { count: number | null; error: unknown };
	annotation?: { data: { trans_id: number; journal_id: number | null } | null; error: unknown };
	upsertError?: { code?: string; message: string } | null;
	captured?: { calls: unknown[] };
}) {
	const trans = opts.trans ?? { data: null, error: null };
	const splitCount = opts.splitCount ?? { count: 0, error: null };
	const annotation = opts.annotation ?? { data: null, error: null };
	const upsertError = opts.upsertError ?? null;

	return {
		schema: (_s: string) => ({
			from: (table: string) => {
				if (table === 'account_trans')
					return { select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve(trans) }) }) };
				if (table === 'account_trans_split')
					return { select: () => ({ eq: () => Promise.resolve(splitCount) }) };
				if (table === 'account_trans_annotation')
					return {
						select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve(annotation) }) }),
						upsert: (row: unknown, upsertOpts: unknown) => {
							opts.captured?.calls.push({ row, opts: upsertOpts });
							return Promise.resolve({ error: upsertError });
						}
					};
				throw new Error(`unexpected table: ${table}`);
			}
		})
	};
}

const CLASSIFIABLE: Row = { trans_id: 1, transaction_type: 'standard', security_id: null, is_reverse: false };

function makeEvent(
	transIdParam: string,
	body: unknown,
	user: { id: string } | null,
	supabaseOpts: Parameters<typeof makeSupabase>[0] = {}
) {
	const request = new Request(`http://localhost/api/transactions/${transIdParam}/classify`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: makeSupabase(supabaseOpts)
	};
	return { request, locals, params: { trans_id: transIdParam } } as unknown as Parameters<typeof POST>[0];
}

describe('POST /api/transactions/:trans_id/classify — orchestration', () => {
	it('unauthenticated → 401, no DB read attempted', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent('1', { sub_cat_id: 7 }, null, { captured }));
		expect(res.status).toBe(401);
		expect(captured.calls).toHaveLength(0);
	});

	it('non-numeric route param → 400 invalid_request', async () => {
		const res = await POST(makeEvent('not-a-number', { sub_cat_id: 7 }, { id: SESSION_UID }));
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: 'invalid_request' });
	});

	it('malformed JSON body → 400', async () => {
		const request = new Request('http://localhost/api/transactions/1/classify', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{not json'
		});
		const locals = { safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }), supabase: makeSupabase({}) };
		const res = await POST({ request, locals, params: { trans_id: '1' } } as unknown as Parameters<typeof POST>[0]);
		expect(res.status).toBe(400);
	});

	it('AC2 — .strict() rejects an unschemed field (mass-assignment fence; e.g. a client-supplied users_id)', async () => {
		const res = await POST(makeEvent('1', { sub_cat_id: 7, users_id: 'attacker-uid' }, { id: SESSION_UID }));
		expect(res.status).toBe(400);
		expect((await res.json()).error).toBe('invalid_request');
	});

	it('AC2 — sub_cat_id must be a positive int (bigint-as-string coerces)', async () => {
		const res = await POST(makeEvent('1', { sub_cat_id: '7' }, { id: SESSION_UID }, { trans: { data: CLASSIFIABLE, error: null } }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, trans_id: 1, sub_cat_id: 7 });
	});

	it('sub_cat_id = 0 or negative → 400 (not a silent no-op)', async () => {
		const res = await POST(makeEvent('1', { sub_cat_id: 0 }, { id: SESSION_UID }));
		expect(res.status).toBe(400);
	});

	it('AC4 — a split-parent refusal surfaces as 409 with code split_parent', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, {
				trans: { data: CLASSIFIABLE, error: null },
				splitCount: { count: 3, error: null }
			})
		);
		expect(res.status).toBe(409);
		expect(await res.json()).toEqual(
			expect.objectContaining({ code: 'split_parent', error: expect.stringContaining('split') })
		);
	});

	it('AC4 — a reversal-row refusal surfaces as 409 with code is_reversal', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, {
				trans: { data: { ...CLASSIFIABLE, is_reverse: true }, error: null }
			})
		);
		expect(res.status).toBe(409);
		expect((await res.json()).code).toBe('is_reversal');
	});

	it('AC4 — a journaled-annotation refusal surfaces as 409 with code journaled', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, {
				trans: { data: CLASSIFIABLE, error: null },
				annotation: { data: { trans_id: 1, journal_id: 55 }, error: null }
			})
		);
		expect(res.status).toBe(409);
		expect((await res.json()).code).toBe('journaled');
	});

	it('not found (RLS-invisible or absent trans_id) → 404, no code (no existence leak)', async () => {
		const res = await POST(makeEvent('999', { sub_cat_id: 7 }, { id: SESSION_UID }));
		expect(res.status).toBe(404);
		expect(await res.json()).toEqual({ error: 'Transaction not found.' });
	});

	it('AC1 — classifiable + no prior annotation → 200, upsert is INSERT-shaped (trans_id + sub_cat_id only)', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, { trans: { data: CLASSIFIABLE, error: null }, captured })
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, trans_id: 1, sub_cat_id: 7 });
		expect(captured.calls).toEqual([{ row: { trans_id: 1, sub_cat_id: 7 }, opts: { onConflict: 'trans_id' } }]);
	});

	it('AC6 — cross-tenant/cross-vocab Sub-Cat DB rejection → 400 invalid_sub_cat_id', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 999 }, { id: SESSION_UID }, {
				trans: { data: CLASSIFIABLE, error: null },
				upsertError: { code: 'P0001', message: 'Sub-Cat reference rejected: sub_cat_id 999 is not a taxonomy row...' }
			})
		);
		expect(res.status).toBe(400);
		expect((await res.json()).code).toBe('invalid_sub_cat_id');
	});

	it('D-8 condition 6 — the DB journaled-cat-fence raise (verbatim 092 prefix) maps to a code DISTINCT from the app-level journaled refusal', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, {
				trans: { data: CLASSIFIABLE, error: null },
				upsertError: {
					code: 'P0001',
					message:
						'journaled-leg classification rejected: trans_id 1 is attached to journal 55 and so cannot carry a Revenue classification (sub_cat_id 7) — a journaled leg must post to Journal Clearing, and this class would post it as income or spending instead. Reclassify the leg (Transfer or Trade), or detach it from the journal first (SELF-248 AC10 / ADR-058 084 P3)'
				}
			})
		);
		expect(res.status).toBe(409);
		const body = await res.json();
		expect(body.code).toBe('journaled_cat_conflict');
		expect(body.code).not.toBe('journaled');
	});

	it('COLLISION GUARD — the #12 journal-ATTACH fence (033) raise is NOT miscoded as journaled_cat_conflict (a loose /journal/i test would have collided)', async () => {
		const res = await POST(
			makeEvent('1', { sub_cat_id: 7 }, { id: SESSION_UID }, {
				trans: { data: CLASSIFIABLE, error: null },
				upsertError: {
					code: 'P0001',
					message:
						'journal attach rejected: journal_id 3 is not a journal owned by and visible to the tenant of trans_id 1 — not found, not visible under current AAL, or cross-tenant (ADR-011 Decision 3 canonical instance #12 / matched-tenant leg fence, hybrid-resolved; M2 / SELF-295)'
				}
			})
		);
		const body = await res.json();
		expect(body.code).not.toBe('journaled_cat_conflict');
		expect(body.code).toBe('invalid_sub_cat_id');
		expect(res.status).toBe(400);
	});
});
