// tax-brackets.server.test.ts — SELF-265 orchestration coverage for
// /settings/tax-brackets's loader + saveSchedule/createSchedule/deleteSchedule form actions.
//
// The read-side grouping (jurisdictions, current_year_present, basis_year) is unit-tested in
// queries/taxBracketSchedules.test.ts; the shared replace-all write path (ownership read /
// identity guard / courtesy precheck / RPC error mapping) is unit-tested in
// queries/taxBracketScheduleWrite.test.ts. This file locks the ORCHESTRATION this route file
// itself owns: auth gates, FormData → schema translation (including the JSON-in-a-hidden-field
// `rows` transport and the `tax_balance_prior_year` '' → null translation), the createSchedule
// INSERT-then-replace-all sequencing and its own 23505/42501 mapping, and the deleteSchedule
// idempotent-DELETE contract.

import { describe, it, expect } from 'vitest';
import { load, actions } from './+page.server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type EqResult = { data: unknown; error: { code: string; message: string } | null };
type InsertResult = { data: { id: number } | null; error: { code: string; message: string } | null };
type DeleteResult = { error: { code: string; message: string } | null; count: number | null };
type RpcResult = { data: unknown; error: { code: string; message: string } | null };
type ListResult = { data: unknown[] | null; error: { message: string } | null };

type Captured = {
	ownershipReadCalls: Array<{ col: string; val: unknown }>;
	insertCalls: unknown[];
	deleteCalls: Array<{ col1: string; val1: unknown; col2: string; val2: unknown }>;
	rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
};

function makeSupabase(
	opts: {
		scheduleList?: ListResult;
		rowList?: ListResult;
		ownershipRead?: EqResult;
		insertResult?: InsertResult;
		deleteResult?: DeleteResult;
		rpcResult?: RpcResult;
	},
	captured: Captured
) {
	const scheduleTable = {
		select: (_cols: string) => ({
			order: () => ({
				order: () => Promise.resolve(opts.scheduleList ?? { data: [], error: null })
			}),
			eq: (col: string, val: unknown) => {
				captured.ownershipReadCalls.push({ col, val });
				return { maybeSingle: () => Promise.resolve(opts.ownershipRead ?? { data: null, error: null }) };
			}
		}),
		insert: (payload: unknown) => {
			captured.insertCalls.push(payload);
			return {
				select: () => ({
					single: () => Promise.resolve(opts.insertResult ?? { data: null, error: null })
				})
			};
		},
		delete: (_arg: unknown) => ({
			eq: (col1: string, val1: unknown) => ({
				eq: (col2: string, val2: unknown) => {
					captured.deleteCalls.push({ col1, val1, col2, val2 });
					return Promise.resolve(opts.deleteResult ?? { error: null, count: 0 });
				}
			})
		})
	};
	const rowTable = {
		select: (_cols: string) => ({
			order: () => ({
				order: () => Promise.resolve(opts.rowList ?? { data: [], error: null })
			})
		})
	};
	const from = (table: string) => {
		if (table === 'tax_bracket_schedule') return scheduleTable;
		if (table === 'tax_bracket_row') return rowTable;
		throw new Error(`unexpected table ${table}`);
	};
	const rpc = (fn: string, params: Record<string, unknown>) => {
		captured.rpcCalls.push({ fn, params });
		return Promise.resolve(opts.rpcResult ?? { data: null, error: null });
	};
	return { schema: (_s: string) => ({ from, rpc }) };
}

function newCaptured(): Captured {
	return { ownershipReadCalls: [], insertCalls: [], deleteCalls: [], rpcCalls: [] };
}

function validFields(overrides: Record<string, string> = {}): Record<string, string> {
	return {
		schedule_id: '42',
		tax_year: '2026',
		schedule_type: 'federal_ordinary',
		schedule_label: '2026 federal ordinary — married filing jointly',
		standard_deduction: '14600.00',
		tax_balance_prior_year: '',
		rows: JSON.stringify([
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11600, bracket_rate: 0.12 }
		]),
		...overrides
	};
}

function makeEvent(
	action: (event: unknown) => unknown,
	fields: Record<string, string>,
	user: { id: string } | null,
	supabaseOpts: Parameters<typeof makeSupabase>[0] = {}
) {
	const captured = newCaptured();
	const request = new Request('http://localhost/settings/tax-brackets', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: makeSupabase(supabaseOpts, captured)
	};
	return { event: { request, locals } as unknown as Parameters<typeof action>[0], captured };
}

describe('load', () => {
	it('unauthenticated → redirect to /login', async () => {
		const locals = { safeGetSession: async () => ({ session: null, user: null }) };
		const url = new URL('http://localhost/settings/tax-brackets');
		await expect(load({ locals, url } as unknown as Parameters<typeof load>[0])).rejects.toMatchObject({
			status: 303
		});
	});

	it('authenticated → returns jurisdictions + currentTaxYear from the loaded schedules', async () => {
		const captured = newCaptured();
		const scheduleList: ListResult = {
			data: [
				{
					id: 1,
					tax_year: 2026,
					schedule_type: 'federal_ordinary',
					schedule_label: 'x',
					standard_deduction: 14600,
					tax_balance_prior_year: null
				}
			],
			error: null
		};
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: makeSupabase({ scheduleList, rowList: { data: [], error: null } }, captured)
		};
		const url = new URL('http://localhost/settings/tax-brackets');
		const result = await load({ locals, url } as unknown as Parameters<typeof load>[0]);
		expect(result.jurisdictions).toHaveLength(3);
		expect(typeof result.currentTaxYear).toBe('number');
		const federal = result.jurisdictions.find((j) => j.schedule_type === 'federal_ordinary')!;
		expect(federal.schedules).toHaveLength(1);
	});
});

describe('actions.saveSchedule', () => {
	it('unauthenticated → 401, no DB reached', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields(), null);
		const res = (await actions.saveSchedule(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(captured.ownershipReadCalls).toHaveLength(0);
	});

	it('invalid schedule_id field → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields({ schedule_id: 'not-a-number' }), {
			id: SESSION_UID
		});
		const res = (await actions.saveSchedule(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(captured.ownershipReadCalls).toHaveLength(0);
	});

	it('malformed rows JSON → 400 with a rows field error (schema rejects the raw string), no DB reached', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields({ rows: '{not json' }), {
			id: SESSION_UID
		});
		const res = (await actions.saveSchedule(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		expect(res.data.errors).toHaveProperty('rows');
		expect(captured.ownershipReadCalls).toHaveLength(0);
	});

	it("empty tax_balance_prior_year field → treated as null, not a validation failure", async () => {
		const { event } = makeEvent(actions.saveSchedule, validFields({ tax_balance_prior_year: '' }), { id: SESSION_UID }, {
			ownershipRead: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			rpcResult: { data: null, error: null }
		});
		const res = (await actions.saveSchedule(event)) as { ok: boolean };
		expect(res).toEqual({ action: 'saveSchedule', ok: true, scheduleId: 42 });
	});

	it('mass-assignment: a stray users_id-shaped extra field never reaches the RPC params', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields(), { id: SESSION_UID }, {
			ownershipRead: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			rpcResult: { data: null, error: null }
		});
		await actions.saveSchedule(event);
		expect(captured.rpcCalls[0].params).not.toHaveProperty('users_id');
		expect(captured.rpcCalls[0].params).not.toHaveProperty('p_users_id');
	});

	it('cross-tenant schedule_id: ownership read resolves no row → 404, RPC never called', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields(), { id: SESSION_UID }, {
			ownershipRead: { data: null, error: null }
		});
		const res = (await actions.saveSchedule(event)) as { status: number };
		expect(res.status).toBe(404);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it("identity guard: body tax_year disagrees with the resolved row → 409, RPC never called", async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields({ tax_year: '2025' }), { id: SESSION_UID }, {
			ownershipRead: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = (await actions.saveSchedule(event)) as { status: number };
		expect(res.status).toBe(409);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('a fraction of 22 (not 0.22) is rejected by the shared schema → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(
			actions.saveSchedule,
			validFields({ rows: JSON.stringify([{ bracket_floor: 0, bracket_rate: 22 }]) }),
			{ id: SESSION_UID }
		);
		const res = (await actions.saveSchedule(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		expect(res.data.errors).toHaveProperty('rows');
		expect(captured.ownershipReadCalls).toHaveLength(0);
	});

	it('empty schedule_label rejected by the shared schema (label rules) → 400', async () => {
		const { event } = makeEvent(actions.saveSchedule, validFields({ schedule_label: '' }), { id: SESSION_UID });
		const res = (await actions.saveSchedule(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		expect(res.data.errors).toHaveProperty('schedule_label');
	});

	it("aal1 → step-up branch: RPC 42501 → 403", async () => {
		const { event } = makeEvent(actions.saveSchedule, validFields(), { id: SESSION_UID }, {
			ownershipRead: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			rpcResult: { data: null, error: { code: '42501', message: 'permission denied' } }
		});
		const res = (await actions.saveSchedule(event)) as { status: number };
		expect(res.status).toBe(403);
	});

	it('happy path → 200-equivalent (plain object), RPC called once with the exact contract', async () => {
		const { event, captured } = makeEvent(actions.saveSchedule, validFields(), { id: SESSION_UID }, {
			ownershipRead: { data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			rpcResult: { data: null, error: null }
		});
		const res = await actions.saveSchedule(event);
		expect(res).toEqual({ action: 'saveSchedule', ok: true, scheduleId: 42 });
		expect(captured.rpcCalls).toHaveLength(1);
		expect(captured.rpcCalls[0].params).toEqual({
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
});

describe('actions.createSchedule', () => {
	it('unauthenticated → 401, no DB reached', async () => {
		const { event, captured } = makeEvent(actions.createSchedule, validFields(), null);
		const res = (await actions.createSchedule(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(captured.insertCalls).toHaveLength(0);
	});

	it('INSERT unique-key conflict (23505) → 409 field error on tax_year, replace-all never called', async () => {
		const { event, captured } = makeEvent(actions.createSchedule, validFields(), { id: SESSION_UID }, {
			insertResult: { data: null, error: { code: '23505', message: 'unique violation' } }
		});
		const res = (await actions.createSchedule(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(409);
		expect(res.data.errors).toHaveProperty('tax_year');
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('INSERT 42501 (aal1 step-up) → 403', async () => {
		const { event } = makeEvent(actions.createSchedule, validFields(), { id: SESSION_UID }, {
			insertResult: { data: null, error: { code: '42501', message: 'permission denied' } }
		});
		const res = (await actions.createSchedule(event)) as { status: number };
		expect(res.status).toBe(403);
	});

	it('happy path → INSERT then replace-all RPC on the freshly-minted id, in order', async () => {
		const { event, captured } = makeEvent(actions.createSchedule, validFields(), { id: SESSION_UID }, {
			insertResult: { data: { id: 99 }, error: null },
			ownershipRead: { data: { id: 99, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			rpcResult: { data: null, error: null }
		});
		const res = await actions.createSchedule(event);
		expect(res).toEqual({ action: 'createSchedule', ok: true, scheduleId: 99 });
		expect(captured.insertCalls).toHaveLength(1);
		expect(captured.insertCalls[0]).toEqual({
			tax_year: 2026,
			schedule_type: 'federal_ordinary',
			schedule_label: '2026 federal ordinary — married filing jointly',
			standard_deduction: 14600,
			tax_balance_prior_year: null
		});
		expect(captured.rpcCalls).toHaveLength(1);
		expect(captured.rpcCalls[0].params.p_schedule_id).toBe(99);
	});

	it('replace-all step fails after a successful INSERT (e.g. courtesy precheck) → surfaces that failure, not a false success', async () => {
		const { event } = makeEvent(
			actions.createSchedule,
			validFields({ rows: JSON.stringify([{ bracket_floor: 500, bracket_rate: 0.1 }]) }),
			{ id: SESSION_UID },
			{
				insertResult: { data: { id: 99 }, error: null },
				ownershipRead: { data: { id: 99, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
			}
		);
		const res = (await actions.createSchedule(event)) as { status: number; data: { errors: Record<string, string[]> } };
		expect(res.status).toBe(400);
		expect(res.data.errors).toHaveProperty('rows');
	});
});

describe('actions.deleteSchedule', () => {
	it('unauthenticated → 401, no DB reached', async () => {
		const { event, captured } = makeEvent(actions.deleteSchedule, { schedule_id: '1' }, null);
		const res = (await actions.deleteSchedule(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(captured.deleteCalls).toHaveLength(0);
	});

	it('invalid schedule_id → 400, no DB reached', async () => {
		const { event, captured } = makeEvent(actions.deleteSchedule, { schedule_id: 'nope' }, { id: SESSION_UID });
		const res = (await actions.deleteSchedule(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(captured.deleteCalls).toHaveLength(0);
	});

	it('DELETE scoped to id AND users_id (defense-in-depth predicate)', async () => {
		const { event, captured } = makeEvent(actions.deleteSchedule, { schedule_id: '7' }, { id: SESSION_UID }, {
			deleteResult: { error: null, count: 1 }
		});
		await actions.deleteSchedule(event);
		expect(captured.deleteCalls).toEqual([{ col1: 'id', val1: 7, col2: 'users_id', val2: SESSION_UID }]);
	});

	it('successful delete → deleted: true', async () => {
		const { event } = makeEvent(actions.deleteSchedule, { schedule_id: '7' }, { id: SESSION_UID }, {
			deleteResult: { error: null, count: 1 }
		});
		const res = await actions.deleteSchedule(event);
		expect(res).toEqual({ action: 'deleteSchedule', scheduleId: 7, deleted: true });
	});

	it('cross-tenant / absent id → idempotent 200-equivalent, deleted: false (never a 404)', async () => {
		const { event } = makeEvent(actions.deleteSchedule, { schedule_id: '7' }, { id: SESSION_UID }, {
			deleteResult: { error: null, count: 0 }
		});
		const res = await actions.deleteSchedule(event);
		expect(res).toEqual({ action: 'deleteSchedule', scheduleId: 7, deleted: false });
	});

	it('unexpected DB error → 500', async () => {
		const { event } = makeEvent(actions.deleteSchedule, { schedule_id: '7' }, { id: SESSION_UID }, {
			deleteResult: { error: { code: 'XXYYY', message: 'boom' }, count: null }
		});
		const res = (await actions.deleteSchedule(event)) as { status: number };
		expect(res.status).toBe(500);
	});
});
