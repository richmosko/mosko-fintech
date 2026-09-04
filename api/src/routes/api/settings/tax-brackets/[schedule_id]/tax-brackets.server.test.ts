// tax-brackets.server.test.ts — SELF-259 AC6 orchestration + Lock 14 adversarial coverage for
// POST /api/settings/tax-brackets/:schedule_id. Mirrors planning-target.server.test.ts /
// cashflow-target.server.test.ts's mocked-session / mocked-supabase-chain shape.
//
// Reconciled against migration 101 (supabase/migrations/101_tax_bracket_tables.sql @ 5f69249):
// there is no replace-all RPC, so the write path is THREE sequential `.from()` calls — UPDATE
// pfin.tax_bracket_schedule, DELETE pfin.tax_bracket_row, INSERT pfin.tax_bracket_row (see the
// route file's header for why this order). Every test captures which of {read, update, delete,
// insert} actually ran, so a rejection that should stop the sequence early (auth, shape,
// mass-assignment, identity mismatch, ordering precheck, a failure on an earlier step) can
// assert the LATER steps never ran — not just that the response code looks right.

import { describe, it, expect } from 'vitest';
import { POST } from './+server';

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

type ReadResult = {
	data: { id: number; tax_year: number; schedule_type: string } | null;
	error: { code: string; message: string } | null;
};
type WriteResult = { error: { code: string; message: string } | null; count?: number | null };

type Captured = {
	readCalls: Array<{ col: string; val: unknown }>;
	updateCalls: Array<{ payload: unknown; col: string; val: unknown }>;
	deleteCalls: Array<{ col: string; val: unknown }>;
	insertCalls: Array<unknown[]>;
};

function emptyCaptured(): Captured {
	return { readCalls: [], updateCalls: [], deleteCalls: [], insertCalls: [] };
}

function supabaseMock(
	readResult: ReadResult,
	updateResult: WriteResult,
	deleteResult: WriteResult,
	insertResult: WriteResult,
	captured: Captured
) {
	return {
		schema: (schemaName: string) => {
			if (schemaName !== 'pfin') throw new Error(`unexpected schema ${schemaName}`);
			return {
				from: (table: string) => {
					if (table === 'tax_bracket_schedule') {
						return {
							select: (_cols: string) => ({
								eq: (col: string, val: unknown) => {
									captured.readCalls.push({ col, val });
									return { maybeSingle: () => Promise.resolve(readResult) };
								}
							}),
							update: (payload: unknown, _opts: unknown) => ({
								eq: (col: string, val: unknown) => {
									captured.updateCalls.push({ payload, col, val });
									return Promise.resolve(updateResult);
								}
							})
						};
					}
					if (table === 'tax_bracket_row') {
						return {
							delete: () => ({
								eq: (col: string, val: unknown) => {
									captured.deleteCalls.push({ col, val });
									return Promise.resolve(deleteResult);
								}
							}),
							insert: (rows: unknown[]) => {
								captured.insertCalls.push(rows);
								return Promise.resolve(insertResult);
							}
						};
					}
					throw new Error(`unexpected table ${table}`);
				}
			};
		}
	};
}

const OK_WRITE: WriteResult = { error: null, count: 1 };

function makeEvent(
	body: unknown,
	user: { id: string } | null,
	scheduleIdParam: string,
	overrides: {
		readResult?: ReadResult;
		updateResult?: WriteResult;
		deleteResult?: WriteResult;
		insertResult?: WriteResult;
	} = {}
) {
	const captured = emptyCaptured();
	const readResult: ReadResult = overrides.readResult ?? {
		data: { id: Number(scheduleIdParam), tax_year: 2026, schedule_type: 'federal_ordinary' },
		error: null
	};
	const request = new Request(`http://localhost/api/settings/tax-brackets/${scheduleIdParam}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: supabaseMock(
			readResult,
			overrides.updateResult ?? OK_WRITE,
			overrides.deleteResult ?? OK_WRITE,
			overrides.insertResult ?? OK_WRITE,
			captured
		)
	};
	const params = { schedule_id: scheduleIdParam };
	return { event: { request, locals, params } as unknown as Parameters<typeof POST>[0], captured };
}

/** A minimal, otherwise-valid body: two rows, zero-floor + strictly-increasing floor and rate,
 *  matching the default read-result's identity (tax_year 2026 / federal_ordinary). Individual
 *  tests mutate one field at a time off this base. */
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
		const captured = emptyCaptured();
		const locals = {
			safeGetSession: async () => ({ session: {}, user: { id: SESSION_UID } }),
			supabase: supabaseMock(
				{ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
				OK_WRITE,
				OK_WRITE,
				OK_WRITE,
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

	it('cross-tenant / absent schedule_id: ownership read resolves no row → 404, no write calls', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', { readResult: { data: null, error: null } });
		const res = await POST(event);
		expect(res.status).toBe(404);
		expect(await res.json()).toEqual({ error: 'not_found' });
		expect(captured.readCalls).toEqual([{ col: 'id', val: 1 }]);
		expect(captured.updateCalls).toHaveLength(0);
		expect(captured.deleteCalls).toHaveLength(0);
		expect(captured.insertCalls).toHaveLength(0);
	});

	it('ownership read failure (unexpected DB error) → 500, no write calls', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
			readResult: { data: null, error: { code: 'XXYYY', message: 'boom' } }
		});
		const res = await POST(event);
		expect(res.status).toBe(500);
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('schedule identity mismatch: body tax_year disagrees with the resolved row → 409, no write calls', async () => {
		const { event, captured } = makeEvent(validBody({ tax_year: 2025 }), { id: SESSION_UID }, '1', {
			readResult: { data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = await POST(event);
		expect(res.status).toBe(409);
		expect(await res.json()).toEqual({ error: 'schedule_identity_mismatch' });
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('schedule identity mismatch: body schedule_type disagrees with the resolved row → 409, no write calls', async () => {
		const { event, captured } = makeEvent(validBody({ schedule_type: 'federal_lt_cg' }), { id: SESSION_UID }, '1', {
			readResult: { data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null }
		});
		const res = await POST(event);
		expect(res.status).toBe(409);
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('zero-floor courtesy precheck: lowest bracket_floor non-zero → 400, no write calls', async () => {
		const body = validBody({ rows: [{ bracket_floor: 500, bracket_rate: '0.10' }] });
		const { event, captured } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(400);
		expect((await res.json()).error).toBe('invalid_row_order');
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('floor-ordering courtesy precheck: a non-increasing multi-row batch (duplicate floor) → 400, no write calls', async () => {
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
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('rate-monotonicity courtesy precheck: a decreasing rate at a higher floor → 400, no write calls', async () => {
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
		expect(captured.updateCalls).toHaveLength(0);
	});

	it('equal adjacent rates (non-decreasing, not strictly increasing) are ACCEPTED by the courtesy precheck', async () => {
		const body = validBody({
			rows: [
				{ bracket_floor: 0, bracket_rate: '0.10' },
				{ bracket_floor: 11600, bracket_rate: '0.10' } // same rate — legal, per 101's own "non-decreasing" wording
			]
		});
		const { event } = makeEvent(body, { id: SESSION_UID }, '1');
		const res = await POST(event);
		expect(res.status).toBe(200);
	});

	it('happy path: valid replace-all → 200, UPDATE then DELETE then INSERT, in that order, users_id never written', async () => {
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
			standard_deduction: 14600,
			tax_balance_prior_year: null,
			row_count: 2
		});

		expect(captured.updateCalls).toHaveLength(1);
		expect(captured.updateCalls[0].col).toBe('id');
		expect(captured.updateCalls[0].val).toBe(42);
		expect(captured.updateCalls[0].payload).toEqual({ standard_deduction: 14600, tax_balance_prior_year: null });
		expect(captured.updateCalls[0].payload).not.toHaveProperty('users_id');
		expect(captured.updateCalls[0].payload).not.toHaveProperty('tax_year');
		expect(captured.updateCalls[0].payload).not.toHaveProperty('schedule_type');

		expect(captured.deleteCalls).toEqual([{ col: 'schedule_id', val: 42 }]);

		expect(captured.insertCalls).toHaveLength(1);
		expect(captured.insertCalls[0]).toEqual([
			{ schedule_id: 42, bracket_floor: 0, bracket_rate: 0.1 },
			{ schedule_id: 42, bracket_floor: 11600, bracket_rate: 0.12 }
		]);
		for (const row of captured.insertCalls[0] as Record<string, unknown>[]) {
			expect(row).not.toHaveProperty('users_id');
		}
	});

	it('a 0-row UPDATE (race: schedule vanished between the ownership read and the write) → 404, DELETE/INSERT never called', async () => {
		const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', { updateResult: { error: null, count: 0 } });
		const res = await POST(event);
		expect(res.status).toBe(404);
		expect(captured.deleteCalls).toHaveLength(0);
		expect(captured.insertCalls).toHaveLength(0);
	});

	describe('write-error mapping — UPDATE step (schedule scalars)', () => {
		it("'42501' (aal2 step-up) on UPDATE → 403, DELETE/INSERT never called", async () => {
			const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				updateResult: { error: { code: '42501', message: 'permission denied' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(403);
			expect(await res.json()).toEqual({ error: 'step_up_required' });
			expect(captured.deleteCalls).toHaveLength(0);
			expect(captured.insertCalls).toHaveLength(0);
		});

		it("'23514' (numeric CHECK) on UPDATE → 400 invalid_value, DELETE/INSERT never called", async () => {
			const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				updateResult: { error: { code: '23514', message: 'check violation' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_value' });
			expect(captured.deleteCalls).toHaveLength(0);
		});
	});

	describe('write-error mapping — DELETE step (old rows)', () => {
		it("'42501' on DELETE → 403, INSERT never called (scalars already committed — the accepted residual)", async () => {
			const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				deleteResult: { error: { code: '42501', message: 'permission denied' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(403);
			expect(captured.updateCalls).toHaveLength(1);
			expect(captured.insertCalls).toHaveLength(0);
		});
	});

	describe('write-error mapping — INSERT step (new rows) — where the deferred CONSTRAINT TRIGGER commits', () => {
		it("'P0001' (matched-tenant fence OR the deferred zero-floor/rate-monotonicity trigger, commit-time) → 400 invalid_schedule — the DB rejection surfaced correctly, never silently 200", async () => {
			const { event, captured } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				insertResult: { error: { code: 'P0001', message: 'raised by trigger at commit' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_schedule' });
			// The prior two steps DID run (scalars updated, old rows deleted) — this is the
			// accepted "new scalars, empty rows" residual the route file's header names.
			expect(captured.updateCalls).toHaveLength(1);
			expect(captured.deleteCalls).toHaveLength(1);
		});

		it("'23505' (duplicate bracket_floor, defensive fallback) → 400 duplicate_bracket_floor", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				insertResult: { error: { code: '23505', message: 'unique violation' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'duplicate_bracket_floor' });
		});

		it("'23514' on INSERT → 400 invalid_value", async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				insertResult: { error: { code: '23514', message: 'check violation' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(400);
			expect(await res.json()).toEqual({ error: 'invalid_value' });
		});

		it('unexpected error code on INSERT → 500 internal_error, never a fake 4xx', async () => {
			const { event } = makeEvent(validBody(), { id: SESSION_UID }, '1', {
				insertResult: { error: { code: '55000', message: 'unexpected' } }
			});
			const res = await POST(event);
			expect(res.status).toBe(500);
			expect(await res.json()).toEqual({ error: 'internal_error' });
		});
	});
});
