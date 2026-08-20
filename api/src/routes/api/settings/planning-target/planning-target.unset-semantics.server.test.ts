// planning-target.unset-semantics.server.test.ts — SELF-242 ADR-056 unset-vs-explicit-zero
// distinguishing battery. Sec-ruled trap (2026-08-17, SELF-233 joint review, carried forward
// on SELF-242): "unset must be DELETE, never POST 0.00" — ADR-056 makes an explicit stored
// 0.00 a DIFFERENT fact from row-absent (074's header, UNSET SEMANTICS). The DELETE
// mass-assignment battery (planning-target.delete.server.test.ts) already proves DELETE's
// schema cannot carry a target_percent field at all — this file proves the COMPLEMENTARY
// half: that POST target_percent: 0 and DELETE are mechanically DISTINCT operations at the
// orchestration layer (different supabase methods, different persisted outcomes), not two
// spellings of the same "unset" action.

import { describe, it, expect } from 'vitest';
import { POST, DELETE } from './+server';
import { planningTargetDeleteSchema } from '$lib/server/schemas/planning-target';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

describe('ADR-056 unset-vs-explicit-zero: POST 0.00 and DELETE are mechanically distinct', () => {
	it('POST target_percent: 0 is ACCEPTED and upserts a stored 0 — zero is a valid, storable fact, never rejected as falsy/empty; the same call path must never reach delete()', async () => {
		const calls: unknown[] = [];
		const upsert = (row: unknown, opts: unknown) => {
			calls.push({ op: 'upsert', row, opts });
			return Promise.resolve({ error: null });
		};
		const request = new Request('http://localhost/api/settings/planning-target', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ sub_cat_id: 7, target_percent: 0 })
		});
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: {
				schema: () => ({
					from: () => ({
						upsert,
						delete: () => {
							throw new Error('POST must never call delete() — a POST of zero is a stored value, not an unset');
						}
					})
				})
			}
		};
		const res = await POST({ request, locals } as unknown as Parameters<typeof POST>[0]);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 7, target_percent: 0 });
		expect(calls).toEqual([
			{ op: 'upsert', row: { users_id: SESSION_UID, sub_cat_id: 7, target_percent: 0 }, opts: { onConflict: 'users_id,sub_cat_id' } }
		]);
	});

	it('DELETE the SAME sub_cat_id calls delete(), never upsert() — row-removal is a categorically different operation, not a POST of zero under the hood', async () => {
		const calls: unknown[] = [];
		function chain(): PromiseLike<{ error: null }> & { eq: (col: string, val: unknown) => ReturnType<typeof chain> } {
			return {
				eq: (col: string, val: unknown) => {
					calls.push({ op: 'delete.eq', col, val });
					return chain();
				},
				then: (onFulfilled) => Promise.resolve({ error: null }).then(onFulfilled)
			};
		}
		const request = new Request('http://localhost/api/settings/planning-target', {
			method: 'DELETE',
			headers: { 'content-type': 'application/json' },
			body: JSON.stringify({ sub_cat_id: 7 })
		});
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: {
				schema: () => ({
					from: () => ({
						delete: () => {
							calls.push({ op: 'delete' });
							return chain();
						},
						upsert: () => {
							throw new Error('DELETE must never call upsert() — never emulate unset with a stored zero');
						}
					})
				})
			}
		};
		const res = await DELETE({ request, locals } as unknown as Parameters<typeof DELETE>[0]);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sub_cat_id: 7 });
		expect(calls).toEqual([
			{ op: 'delete' },
			{ op: 'delete.eq', col: 'users_id', val: SESSION_UID },
			{ op: 'delete.eq', col: 'sub_cat_id', val: 7 }
		]);
	});

	it('planningTargetDeleteSchema has no value field at all — structurally cannot represent "unset via zero", independent of the mass-assignment leg in planning-target.delete.server.test.ts', () => {
		expect(Object.keys(planningTargetDeleteSchema.shape)).toEqual(['sub_cat_id']);
	});
});
