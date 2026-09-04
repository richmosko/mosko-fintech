// tax-brackets.server.test.ts — SELF-259 AC6 orchestration + Lock 14 adversarial coverage for
// POST /api/settings/tax-brackets/:schedule_id.
//
// Reconciled to E8 (team-lead ruling, 2026-09-03): the write path is a single RPC call —
// `pfin.fn_tax_bracket_schedule_replace_all(p_schedule_id, p_tax_year, p_schedule_type,
// p_schedule_label, p_standard_deduction, p_tax_balance_prior_year, p_rows)` (7-arg form amended
// by E27/E29 for `schedule_label`, landed migration 101 @ b073641) — that Architect is landing on
// migration 101. This endpoint STILL does its own RLS-scoped ownership read before calling the
// RPC (for a reliable, message-independent 404 — see the route file's header for why), so every
// test captures both the read call and the RPC call, and asserts the RPC is never reached when
// an earlier check should have stopped the request.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type ReadResult = {
	data: { id: number; tax_year: number; schedule_type: string } | null;
	error: { code: string; message: string } | null;
};
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
	overrides: { readResult?: ReadResult; rpcResult?: RpcResult } = {}
) {
	const captured: Captured = { readCalls: [], rpcCalls: [] };
	const readResult: ReadResult = overrides.readResult ?? {
		data: { id: Number(scheduleIdParam), tax_year: 2026, schedule_type: 'federal_ordinary' },
		error: null
	};
	const rpcResult: RpcResult = overrides.rpcResult ?? { data: null, error: null };
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

/** A minimal, otherwise-valid body: two rows, zero-floor + strictly-increasing floor and rate,
 *  matching the default read-result's identity (tax_year 2026 / federal_ordinary). */
function validBody(overrides: Record<string, unknown> = {}) {
	return {
		tax_year: 2026,
		schedule_type: 'federal_ordinary',
		schedule_label: '2026 federal ordinary — married filing jointly',
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
	});

	it('non-positive schedule_id path param → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '-1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
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
			supabase: supabaseMock(
				{ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
				{ data: null, error: null },
				captured
			)
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
	});

	it('mass-assignment: a stray `schedule_id` BODY field is rejected (.strict()) — the route param is the only path for it', async () => {
		const { event, captured } = makeEvent(validBody({ schedule_id: 999 }), { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
	});

	it('mass-assignment: a stray row-level field (e.g. `id`) is rejected (.strict() on the row schema)', async () => {
		const body = validBody({ rows: [{ bracket_floor: 0, bracket_rate: '0.10', id: 7 }] });
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect(captured.readCalls).toHaveLength(0);
	});

	it('cross-tenant / absent schedule_id: ownership read resolves no row → 404, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', { readResult: { data: null, error: null } });
		const res = await POST(event);
		expect(res.status).toBe(404);
		expect(await res.json()).toEqual({ error: 'not_found' });
		expect(captured.readCalls).toEqual([{ col: 'id', val: 1 }]);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('ownership read failure (unexpected DB error) → 500, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
			readResult: { data: null, error: { code: 'XXYYY', message: 'boom' } }
		});
		const res = await POST(event);
		expect(res.status).toBe(500);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('schedule identity mismatch: body tax_year disagrees with the resolved row → 409, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody({ tax_year: 2025 }), { id: SESSION_UID }, '1', {
			readResult: { data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = await POST(event);
		expect(res.status).toBe(409);
		expect(await res.json()).toEqual({ error: 'schedule_identity_mismatch' });
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('schedule identity mismatch: body schedule_type disagrees with the resolved row → 409, RPC never called', async () => {
		const { event, captured } = makeEvent(validBody({ schedule_type: 'federal_lt_cg' }), { id: SESSION_UID }, '1', {
			readResult: { data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = await POST(event);
		expect(res.status).toBe(409);
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

	it('floor-ordering courtesy precheck: a non-increasing multi-row batch (duplicate floor) → 400, RPC never called', async () => {
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

	it('rate-monotonicity courtesy precheck: a decreasing rate at a higher floor → 400, RPC never called', async () => {
		const body = validBody({
			rows: [
				{ bracket_floor: 0, bracket_rate: '0.20' },
				{ bracket_floor: 11600, bracket_rate: '0.10' } // rate DROPS as floor rises
			]
		});
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect((await res.json()).error).toBe('invalid_row_order');
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('equal adjacent rates (non-decreasing, not strictly increasing) are ACCEPTED by the courtesy precheck', async () => {
		const body = validBody({
			rows: [
				{ bracket_floor: 0, bracket_rate: '0.10' },
				{ bracket_floor: 11600, bracket_rate: '0.10' }
			]
		});
		const { event } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(200);
	});

	it('happy path: valid replace-all → 200, RPC called ONCE with E8\'s exact param names, no users_id, p_rows exactly the validated row array', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '42', {
			readResult: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = await POST(event);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({
			ok: true,
			schedule_id: 42,
			tax_year: 2026,
			schedule_type: 'federal_ordinary',
			schedule_label: '2026 federal ordinary — married filing jointly',
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
		expect(call.params).toEqual({
			p_schedule_id: 42,
			p_tax_year: 2026,
			p_schedule_type: 'federal_ordinary',
			p_schedule_label: '2026 federal ordinary — married filing jointly',
			p_standard_deduction: 14600,
			p_tax_balance_prior_year: null,
			p_rows: [
				{ bracket_floor: 0, bracket_rate: 0.1 },
				{ bracket_floor: 11600, bracket_rate: 0.12 }
			]
		});
	});

	describe('RPC (DB-side) error mapping — the DB rejection surfaced correctly, never silently 200', () => {
		it("'42501' (aal2 step-up RLS) → 403 step_up_required", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: '42501', message: 'permission denied' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(403);
			expect(await res.json()).toEqual({ error: 'step_up_required' });
		});

		it("'P0001' (ownership lock failure, matched-tenant fence, or the deferred set fence — collapsed deliberately, see file header) → 400 invalid_schedule", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: 'P0001', message: 'raised by the function or a trigger' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_schedule' });
		});

		it("'23514' (two-sided numeric CHECK) → 400 invalid_value", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: '23514', message: 'check violation' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_value' });
		});

		it("'23505' (unique-constraint conflict) → 409 schedule_conflict, distinct from a value-shape 4xx", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: '23505', message: 'unique violation' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(409);
			expect(await res.json()).toEqual({ error: 'schedule_conflict' });
		});

		it("'40001' (SERIALIZABLE serialization failure) → 409 concurrent_update_retry, distinct from the '23505' conflict case", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: '40001', message: 'could not serialize access' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(409);
			expect(await res.json()).toEqual({ error: 'concurrent_update_retry' });
		});

		it('unexpected error code → 500 internal_error, never a fake 4xx', async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				rpcResult: { data: null, error: { code: '55000', message: 'unexpected' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(500);
			expect(await res.json()).toEqual({ error: 'internal_error' });
		});
	});
});
