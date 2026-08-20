// planning-target.delete.server.test.ts — SELF-242 orchestration + mass-assignment coverage
// for DELETE /api/settings/planning-target ("unset a target"). Sec-ruled at the SELF-233
// joint review (2026-08-17), carried forward on SELF-242: unset MUST be a DELETE, never a
// POST of an explicit 0.00 (ADR-056 — 0.00 is a stored, DIFFERENT fact from row-absent).
// Mirrors the POST orchestration test's mocked-session / mocked-supabase-chain shape.
//
// Response shape (Sec C2, this PR): `{ ok: true, sub_cat_id, deleted: boolean }`, read from
// `.delete({ count: 'exact' })`'s row count — `deleted` describes ONLY the caller's own
// outcome (their own request either matched a row or it didn't); it can never describe
// another tenant's row, because the query is `.eq('users_id', ...)`-scoped before it ever
// reaches count.

import { describe, it, expect } from 'vitest';
import { DELETE } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type DeleteResult = { error: { code: string; message: string } | null; count?: number | null };

/**
 * Mocks the `.schema('pfin').from('planning_target').delete({ count: 'exact' }).eq(...).eq(...)`
 * chain. Real supabase-js filter builders are PromiseLike at every step, so the mock stays
 * chainable through any number of `.eq()` calls and resolves to `result` (error + count) when
 * awaited — matching the two `.eq()` calls (`users_id`, `sub_cat_id`) the DELETE handler issues.
 */
function supabaseWithDeleteResult(result: DeleteResult, captured?: { calls: Array<[string, unknown]> }) {
	function chain(): PromiseLike<DeleteResult> & { eq: (col: string, val: unknown) => ReturnType<typeof chain> } {
		return {
			eq: (col: string, val: unknown) => {
				captured?.calls.push([col, val]);
				return chain();
			},
			then: (onFulfilled) => Promise.resolve(result).then(onFulfilled)
		};
	}
	return { schema: () => ({ from: () => ({ delete: () => chain() }) }) };
}

function makeEvent(body: unknown, user: { id: string } | null, deleteResult: DeleteResult, captured?: { calls: Array<[string, unknown]> }) {
	const request = new Request('http://localhost/api/settings/planning-target', {
		method: 'DELETE',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: supabaseWithDeleteResult(deleteResult, captured)
	};
	return { request, locals } as unknown as Parameters<typeof DELETE>[0];
}

describe('DELETE /api/settings/planning-target — orchestration', () => {
	it('unauthenticated → 401, delete never called', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({ sub_cat_id: 7 }, null, { error: null }, captured));
		expect(res.status).toBe(401);
		expect(captured.calls).toHaveLength(0);
	});

	it('malformed JSON body → 400', async () => {
		const request = new Request('http://localhost/api/settings/planning-target', {
			method: 'DELETE',
			headers: { 'content-type': 'application/json' },
			body: '{not json'
		});
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: supabaseWithDeleteResult({ error: null })
		};
		const res = await DELETE({ request, locals } as unknown as Parameters<typeof DELETE>[0]);
		expect(res.status).toBe(400);
	});

	it('valid body, row existed (count 1) → 200, deleted: true, delete scoped by BOTH server-derived users_id AND sub_cat_id (never client-supplied users_id)', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({ sub_cat_id: 7 }, { id: SESSION_UID }, { error: null, count: 1 }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 7, deleted: true });
		expect(captured.calls).toEqual([
			['users_id', SESSION_UID],
			['sub_cat_id', 7]
		]);
	});

	it('deleting an already-absent row (count 0) is still 200 with deleted: false — idempotent, never a 404', async () => {
		const res = await DELETE(makeEvent({ sub_cat_id: 999 }, { id: SESSION_UID }, { error: null, count: 0 }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 999, deleted: false });
	});

	it('a null/undefined count (defensive: an unexpected supabase-js response shape) is treated as deleted: false, never thrown', async () => {
		const res = await DELETE(makeEvent({ sub_cat_id: 999 }, { id: SESSION_UID }, { error: null, count: null }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 999, deleted: false });
	});

	it('unexpected DB error → 500, not silently reclassified as a 4xx', async () => {
		const res = await DELETE(
			makeEvent({ sub_cat_id: 7 }, { id: SESSION_UID }, { error: { code: '53300', message: 'too many connections' } })
		);
		expect(res.status).toBe(500);
		expect(await res.json()).toEqual({ error: 'internal_error' });
	});
});

describe('DELETE /api/settings/planning-target — mass-assignment fence (.strict())', () => {
	it('a stray users_id in the body is rejected — cross-tenant impersonation attempt via the delete predicate itself', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({ sub_cat_id: 7, users_id: 999 }, { id: SESSION_UID }, { error: null }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toHaveLength(0);
	});

	it('target_percent is not a field on this schema — a POST-shaped body (unset-via-zero attempt) is rejected', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({ sub_cat_id: 7, target_percent: 0 }, { id: SESSION_UID }, { error: null }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toHaveLength(0);
	});

	it('any unsanctioned extra field is rejected', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({ sub_cat_id: 7, is_admin: true }, { id: SESSION_UID }, { error: null }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toHaveLength(0);
	});

	it('missing required field (sub_cat_id) is rejected', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		const res = await DELETE(makeEvent({}, { id: SESSION_UID }, { error: null }, captured));
		expect(res.status).toBe(400);
		expect(captured.calls).toHaveLength(0);
	});

	it('non-positive / non-integer sub_cat_id (shape check) is rejected', async () => {
		const captured = { calls: [] as Array<[string, unknown]> };
		expect((await DELETE(makeEvent({ sub_cat_id: -1 }, { id: SESSION_UID }, { error: null }, captured))).status).toBe(400);
		expect((await DELETE(makeEvent({ sub_cat_id: 0 }, { id: SESSION_UID }, { error: null }, captured))).status).toBe(400);
		expect((await DELETE(makeEvent({ sub_cat_id: 1.5 }, { id: SESSION_UID }, { error: null }, captured))).status).toBe(400);
		expect(captured.calls).toHaveLength(0);
	});
});
