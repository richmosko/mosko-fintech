// planning-target.server.test.ts — SELF-233 orchestration coverage for POST
// /api/settings/planning-target. Mocked session + mocked supabase upsert chain. This is the
// happy-path + status-mapping companion to planning-target.rt23-adversarial.server.test.ts
// (the AC4/AC5 adversarial battery).

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type UpsertResult = { error: { code: string; message: string } | null };

function supabaseWithUpsertResult(result: UpsertResult, captured?: { calls: unknown[] }) {
	const upsert = (row: unknown, opts: unknown) => {
		captured?.calls.push({ row, opts });
		return Promise.resolve(result);
	};
	return { schema: () => ({ from: () => ({ upsert }) }) };
}

function makeEvent(body: unknown, user: { id: string } | null, upsertResult: UpsertResult, captured?: { calls: unknown[] }) {
	const request = new Request('http://localhost/api/settings/planning-target', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: supabaseWithUpsertResult(upsertResult, captured)
	};
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

describe('POST /api/settings/planning-target — orchestration', () => {
	it('unauthenticated → 401, upsert never called', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ sub_cat_id: 7, target_percent: 10 }, null, { error: null }, captured));
		expect(res.status).toBe(401);
		expect(captured.calls).toHaveLength(0);
	});

	it('malformed JSON body → 400', async () => {
		const request = new Request('http://localhost/api/settings/planning-target', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{not json'
		});
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: supabaseWithUpsertResult({ error: null })
		};
		const res = await POST({ request, locals } as unknown as Parameters<typeof POST>[0]);
		expect(res.status).toBe(400);
	});

	it('valid body → 200, upsert called with server-derived users_id (never client-supplied)', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(
			makeEvent({ sub_cat_id: 7, target_percent: '12.50' }, { id: SESSION_UID }, { error: null }, captured)
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 7, target_percent: 12.5 });
		expect(captured.calls).toEqual([
			{ row: { users_id: SESSION_UID, sub_cat_id: 7, target_percent: 12.5 }, opts: { onConflict: 'users_id,sub_cat_id' } }
		]);
	});

	it('42501 (RLS WITH CHECK — aal2 step-up backstop) → 403 step_up_required', async () => {
		const res = await POST(
			makeEvent(
				{ sub_cat_id: 7, target_percent: 10 },
				{ id: SESSION_UID },
				{ error: { code: '42501', message: 'new row violates row-level security policy' } }
			)
		);
		expect(res.status).toBe(403);
		expect(await res.json()).toEqual({ error: 'step_up_required' });
	});

	it('P0001 (074 matched-tenant/domain trigger rejection) → 400, generic reason (no leg detail leaked)', async () => {
		const res = await POST(
			makeEvent(
				{ sub_cat_id: 999, target_percent: 10 },
				{ id: SESSION_UID },
				{ error: { code: 'P0001', message: 'cross-tenant planning target rejected: ...' } }
			)
		);
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: 'invalid_sub_cat_or_value' });
	});

	it('23503 (FK violation, defensive fallback) → 400', async () => {
		const res = await POST(
			makeEvent(
				{ sub_cat_id: 999, target_percent: 10 },
				{ id: SESSION_UID },
				{ error: { code: '23503', message: 'foreign key violation' } }
			)
		);
		expect(res.status).toBe(400);
	});

	it('23514 (DB CHECK on target_percent, defense-in-depth) → 400', async () => {
		const res = await POST(
			makeEvent(
				{ sub_cat_id: 7, target_percent: 10 },
				{ id: SESSION_UID },
				{ error: { code: '23514', message: 'check constraint violation' } }
			)
		);
		expect(res.status).toBe(400);
	});

	it('unexpected DB error code → 500, not silently reclassified as a 4xx', async () => {
		const res = await POST(
			makeEvent(
				{ sub_cat_id: 7, target_percent: 10 },
				{ id: SESSION_UID },
				{ error: { code: '53300', message: 'too many connections' } }
			)
		);
		expect(res.status).toBe(500);
		expect(await res.json()).toEqual({ error: 'internal_error' });
	});
});
