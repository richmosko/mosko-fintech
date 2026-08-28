// cashflow-target.null-vs-omitted.server.test.ts — SELF-252 AC3/AC6 battery: an OMITTED key
// leaves that column alone, an explicit `null` SETS that column to NULL, and the write is
// NEVER a row DELETE (090's own UNSET SEMANTICS — this table carries two independent scalars
// in one row, and a DELETE would silently unset both). Ruled at the V1.3 pre-flight sitting,
// items 19 + 19a; see SELF-246 AC7 / migration 090 header.
//
// Full per-field matrix (omitted / value / null), plus the "both" legs that prove the two
// fields never clobber each other, plus the standing DELETE-never-called guard.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, captured: { calls: unknown[] }) {
	const request = new Request('http://localhost/api/settings/cashflow-target', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const upsert = (row: unknown, opts: unknown) => {
		captured.calls.push({ op: 'upsert', row, opts });
		return Promise.resolve({ error: null });
	};
	const locals = {
		safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
		supabase: {
			schema: () => ({
				from: () => ({
					upsert,
					delete: () => {
						throw new Error(
							'cashflow-target POST must never call delete() — this table carries two independent ' +
								'scalars in one row; a DELETE would silently unset both (090 UNSET SEMANTICS).'
						);
					}
				})
			})
		}
	};
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

describe('AC3/AC6 null-vs-omitted — income_annual alone', () => {
	it('omitted → column absent from the write object (left alone), expense_monthly still written', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ expense_monthly: 4000 }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, expense_monthly: 4000 });
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, expense_target_monthly: 4000 }, opts: { onConflict: 'users_id' } }
		]);
	});

	it('a value → column included with that value', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: 120000 }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, income_annual: 120000 });
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, income_target_annual: 120000 }, opts: { onConflict: 'users_id' } }
		]);
	});

	it('explicit null → column included with value null (SET NULL), never omitted and never a DELETE', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: null }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, income_annual: null });
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, income_target_annual: null }, opts: { onConflict: 'users_id' } }
		]);
	});
});

describe('AC3/AC6 null-vs-omitted — expense_monthly alone', () => {
	it('omitted → column absent, income_annual still written', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: 120000 }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, income_target_annual: 120000 }, opts: { onConflict: 'users_id' } }
		]);
	});

	it('a value → column included with that value', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ expense_monthly: 4000 }, captured));
		expect(res.status).toBe(200);
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, expense_target_monthly: 4000 }, opts: { onConflict: 'users_id' } }
		]);
	});

	it('explicit null → column included with value null (SET NULL), never a DELETE', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ expense_monthly: null }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, expense_monthly: null });
		expect(captured.calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, expense_target_monthly: null }, opts: { onConflict: 'users_id' } }
		]);
	});
});

describe('AC3/AC6 — both fields together (cross-field non-clobber)', () => {
	it('both omitted → write object carries only users_id (no-op update on an existing row; all-NULL-by-construction first insert)', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({}, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true });
		expect(captured.calls).toEqual([{ op: 'upsert', row: { users_id: SESSION_UID }, opts: { onConflict: 'users_id' } }]);
	});

	it('both explicit values → both columns written independently in one upsert', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: 120000, expense_monthly: 4000 }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, income_annual: 120000, expense_monthly: 4000 });
		expect(captured.calls).toEqual([
			{
				op: 'upsert',
				row: { users_id: SESSION_UID, income_target_annual: 120000, expense_target_monthly: 4000 },
				opts: { onConflict: 'users_id' }
			}
		]);
	});

	it('one null, one value → each column carries its OWN independent outcome in the same write; clearing income never touches expense', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: null, expense_monthly: 4000 }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, income_annual: null, expense_monthly: 4000 });
		expect(captured.calls).toEqual([
			{
				op: 'upsert',
				row: { users_id: SESSION_UID, income_target_annual: null, expense_target_monthly: 4000 },
				opts: { onConflict: 'users_id' }
			}
		]);
	});

	it('both explicit null → both columns SET NULL in one upsert, still never a DELETE', async () => {
		const captured = { calls: [] as unknown[] };
		const res = await POST(makeEvent({ income_annual: null, expense_monthly: null }, captured));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, income_annual: null, expense_monthly: null });
		expect(captured.calls).toEqual([
			{
				op: 'upsert',
				row: { users_id: SESSION_UID, income_target_annual: null, expense_target_monthly: null },
				opts: { onConflict: 'users_id' }
			}
		]);
	});
});
