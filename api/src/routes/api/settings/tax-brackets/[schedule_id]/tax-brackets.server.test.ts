// tax-brackets.server.test.ts — SELF-259 AC6 orchestration + Lock 14 adversarial coverage for
// POST /api/settings/tax-brackets/:schedule_id. Mirrors planning-target.server.test.ts /
// cashflow-target.server.test.ts's mocked-session / mocked-supabase-chain shape.
//
// Two independent mocked surfaces per request: the ownership read
// (`.schema('pfin').from('tax_bracket_schedule').select('id').eq('id', ...).maybeSingle()`) and
// the replace-all RPC (`.schema('pfin').rpc('fn_tax_bracket_schedule_replace_all', {...})`).
// Every test captures which of the two were actually invoked, so a rejection that should never
// reach the DB (auth, shape, mass-assignment, ordering precheck) can assert BOTH were skipped —
// not just that the response code looks right.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type ReadResult = { data: { id: number } | null; error: { code: string; message: string } | null };
type RpcResult = { data: unknown; error: { code: string; message: string } | null };

type Captured = {
	readCalls: Array<{ col: string; val: unknown }>;
	rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
};

function supabaseMock(readResult: ReadResult, rpcResult: RpcResult, captured: Captured) {
	return {
		schema: (schemaName: string) => {
			if (schemaName !== 'pfin') throw new Error(`unexpected schema ${schemaName}`);
			return {
				from: (table: string) => {
					if (table !== 'tax_bracket_schedule') throw new Error(`unexpected table ${table}`);
					return {
						select: (_cols: string) => ({
							eq: (col: string, val: unknown) => {
								captured.readCalls.push({ col, val });
								return { maybeSingle: () => Promise.resolve(readResult) };
							}
						})
					};
				},
				rpc: (fn: string, params: Record<string, unknown>) => {
					captured.rpcCalls.push({ fn, params });
					return Promise.resolve(rpcResult);
				}
			};
		}
	};
}

function makeEvent(
	body: unknown,
	user: { id: string } | null,
	scheduleIdParam: string,
	readResult: ReadResult = { data: { id: 1 }, error: null },
	rpcResult: RpcResult = { data: null, error: null }
) {
	const captured: Captured = { readCalls: [], rpcCalls: [] };
	const request = new Request(`http://localhost/api/settings/tax-brackets/${scheduleIdParam}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: supabaseMock(readResult, rpcResult, captured)
	};
	const params = { schedule_id: scheduleIdParam };
	return { event: { request, locals, params } as unknown as Parameters<typeof POST>[0], captured };
}

/** A minimal, otherwise-valid body: two rows, zero-floor + strictly-increasing, both fields
 *  in-shape. Individual tests mutate one field at a time off this base. */
function validBody(overrides: Record<string, unknown> = {}) {
	return {
		tax_year: 2026,
		schedule_type: 'federal_ordinary',
		standard_deduction: '14600.00',
		tax_balance_prior_year: null,
		rows: [
			{ bracket_floor: 0, bracket_rate: '0.10' },
			{ bracket_floor: 11600, bracket_rate: '0.12' }
		],
		...overrides
	};
}

describe('POST /api/settings/tax-brackets/:schedule_id — orchestration', () => {
	it('unauthenticated → 401, no DB reached', async () => {
		const { event, captured } = makeEvent(validBody(), null, '1');
		const res = await POST(event);
		expect(res.status).toBe(401);
		expect(captured.readCalls).toHaveLength(0);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('non-numeric schedule_id path param → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, 'not-a-number');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('non-positive schedule_id path param → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '-1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('malformed JSON body → 400', async () => {
		const request = new Request('http://localhost/api/settings/tax-brackets/1', {
			method: 'POST',
			headers: { 'content-type': 'application/json' },
			body: '{not json'
		});
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: supabaseMock({ data: { id: 1 }, error: null }, { data: null, error: null }, captured)
		};
		const res = await POST({ request, locals, params: { schedule_id: '1' } } as unknown as Parameters<typeof POST>[0]);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray `users_id` field is rejected (.strict()) — 400, no DB reached', async () => {
		const { event, captured } = makeEvent(validBody({ users_id: 'forged-tenant' }), { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray `schedule_id` BODY field is rejected (.strict()) — the route param is the only path for it', async () => {
		const { event, captured } = makeEvent(validBody({ schedule_id: 999 }), { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray row-level field (e.g. `id`) is rejected (.strict() on the row schema)', async () => {
		const body = validBody({ rows: [{ bracket_floor: 0, bracket_rate: '0.10', id: 7 }] });
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
	});

	it('cross-tenant / absent schedule_id: ownership read resolves no row → 404, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', { data: null, error: null });
		const res = await POST(event);
		expect(res.status).toBe(404);
		expect(await res.json()).toEqual({ error: 'not_found' });
		expect(captured.readCalls).toEqual([{ col: 'id', val: 1 }]);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('ownership read failure (unexpected DB error) → 500, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
			data: null,
			error: { code: 'XXYYY', message: 'boom' }
		});
		const res = await POST(event);
		expect(res.status).toBe(500);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('zero-floor courtesy precheck: lowest bracket_floor non-zero → 400, RPC never called', async () => {
		const body = validBody({ rows: [{ bracket_floor: 500, bracket_rate: '0.10' }] });
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect((await res.json()).error).toBe('invalid_row_order');
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('monotonicity courtesy precheck: a non-increasing multi-row batch → 400, RPC never called', async () => {
		const body = validBody({
			rows: [
				{ bracket_floor: 0, bracket_rate: '0.10' },
				{ bracket_floor: 11600, bracket_rate: '0.12' },
				{ bracket_floor: 11600, bracket_rate: '0.22' } // equal, not strictly increasing
			]
		});
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect((await res.json()).error).toBe('invalid_row_order');
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('happy path: valid replace-all → 200, RPC called with server-derived scope only (no users_id param)', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '42');
		const res = await POST(event);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({
			ok: true,
			schedule_id: 42,
			tax_year: 2026,
			schedule_type: 'federal_ordinary',
			standard_deduction: 14600,
			tax_balance_prior_year: null,
			row_count: 2
		});
		expect(captured.readCalls).toEqual([{ col: 'id', val: 42 }]);
		expect(captured.rpcCalls).toHaveLength(1);
		const call = captured.rpcCalls[0];
		expect(call.fn).toBe('fn_tax_bracket_schedule_replace_all');
		expect(call.params).not.toHaveProperty('p_users_id');
		expect(call.params).not.toHaveProperty('users_id');
		expect(call.params.p_schedule_id).toBe(42);
		expect(call.params.p_rows).toEqual([
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11600, bracket_rate: 0.12 }
		]);
	});

	describe('RPC (DB-side) error mapping — the DB trigger/CHECK/isolation rejection surfaced correctly, never silently 200', () => {
		it("'42501' (aal2 step-up RLS WITH CHECK) → 403 step_up_required", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: '42501', message: 'permission denied' }
			});
			const res = await POST(event);
			expect(res.status).toBe(403);
			expect(await res.json()).toEqual({ error: 'step_up_required' });
		});

		it("'P0001' (matched-tenant fence / deferred monotonicity-zero-floor trigger) → 400 invalid_schedule", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: 'P0001', message: 'raised by trigger' }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_schedule' });
		});

		it("'23514' (two-sided numeric CHECK) → 400 invalid_value", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: '23514', message: 'check violation' }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_value' });
		});

		it("'23503' (FK violation, defensive fallback) → 400 invalid_schedule", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: '23503', message: 'fk violation' }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_schedule' });
		});

		it("'40001' (SERIALIZABLE serialization failure) → 409 concurrent_update_retry, distinct from a 4xx input error", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: '40001', message: 'could not serialize access' }
			});
			const res = await POST(event);
			expect(res.status).toBe(409);
			expect(await res.json()).toEqual({ error: 'concurrent_update_retry' });
		});

		it('unexpected error code → 500 internal_error, never a fake 4xx', async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', undefined, {
				data: null,
				error: { code: '55000', message: 'unexpected' }
			});
			const res = await POST(event);
			expect(res.status).toBe(500);
			expect(await res.json()).toEqual({ error: 'internal_error' });
		});
	});
});
