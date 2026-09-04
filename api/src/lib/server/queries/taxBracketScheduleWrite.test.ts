// taxBracketScheduleWrite.test.ts — unit coverage for the shared replace-all write helper
// (SELF-265, backing the /settings/tax-brackets form actions). Mirrors the sibling endpoint's own
// battery (tax-brackets.server.test.ts) for the ownership-read / identity-guard / courtesy-
// precheck / RPC-error-mapping legs, since this module is a separate implementation of the same
// design (see the module's own header for why).

import { describe, it, expect } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { replaceTaxBracketSchedule, precheckRowOrdering } from './taxBracketScheduleWrite';
import type { TaxBracketScheduleReplace } from '$lib/server/schemas/tax-bracket-schedule';

type ReadResult = {
	data: { id: number; tax_year: number; schedule_type: string } | null;
	error: { code: string; message: string } | null;
};
type RpcResult = { data: unknown; error: { code: string; message: string } | null };
type Captured = {
	readCalls: Array<{ col: string; val: unknown }>;
	rpcCalls: Array<{ fn: string; params: Record<string, unknown> }>;
};

function supabaseMock(readResult: ReadResult, rpcResult: RpcResult, captured: Captured): SupabaseClient {
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
	} as unknown as SupabaseClient;
}

function validInput(overrides: Partial<TaxBracketScheduleReplace> = {}): TaxBracketScheduleReplace {
	return {
		tax_year: 2026,
		schedule_type: 'federal_ordinary',
		schedule_label: '2026 federal ordinary — married filing jointly',
		standard_deduction: 14600,
		tax_balance_prior_year: null,
		rows: [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11600, bracket_rate: 0.12 }
		],
		...overrides
	};
}

describe('precheckRowOrdering', () => {
	it('rejects a non-zero lowest floor', () => {
		expect(precheckRowOrdering([{ bracket_floor: 500, bracket_rate: 0.1 }])).toEqual({
			ok: false,
			reason: 'The lowest bracket must start at 0.'
		});
	});

	it('rejects a non-increasing floor (duplicate)', () => {
		const rows = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 0, bracket_rate: 0.12 }
		];
		expect(precheckRowOrdering(rows).ok).toBe(false);
	});

	it('rejects a decreasing rate at a higher floor', () => {
		const rows = [
			{ bracket_floor: 0, bracket_rate: 0.2 },
			{ bracket_floor: 11600, bracket_rate: 0.1 }
		];
		expect(precheckRowOrdering(rows).ok).toBe(false);
	});

	it('accepts equal adjacent rates (non-decreasing, not strictly increasing)', () => {
		const rows = [
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11600, bracket_rate: 0.1 }
		];
		expect(precheckRowOrdering(rows)).toEqual({ ok: true });
	});
});

describe('replaceTaxBracketSchedule', () => {
	it('cross-tenant / absent schedule id: ownership read resolves no row → 404, RPC never called', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock({ data: null, error: null }, { data: null, error: null }, captured);
		const result = await replaceTaxBracketSchedule(client, 1, validInput());
		expect(result).toEqual({ ok: false, status: 404, errors: { _form: ['This schedule could not be found.'] } });
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('ownership read failure (unexpected DB error) → 500, RPC never called', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock(
			{ data: null, error: { code: 'XXYYY', message: 'boom' } },
			{ data: null, error: null },
			captured
		);
		const result = await replaceTaxBracketSchedule(client, 1, validInput());
		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.status).toBe(500);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('schedule identity mismatch (resolved tax_year disagrees) → 409, RPC never called', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock(
			{ data: { id: 1, tax_year: 2025, schedule_type: 'federal_ordinary' }, error: null },
			{ data: null, error: null },
			captured
		);
		const result = await replaceTaxBracketSchedule(client, 1, validInput({ tax_year: 2026 }));
		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.status).toBe(409);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('schedule identity mismatch (resolved schedule_type disagrees) → 409, RPC never called', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock(
			{ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			{ data: null, error: null },
			captured
		);
		const result = await replaceTaxBracketSchedule(client, 1, validInput({ schedule_type: 'federal_lt_cg' }));
		expect(result.ok).toBe(false);
		if (!result.ok) expect(result.status).toBe(409);
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('courtesy precheck failure (bad row order) → 400 with a `rows` field error, RPC never called', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock(
			{ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			{ data: null, error: null },
			captured
		);
		const result = await replaceTaxBracketSchedule(
			client,
			1,
			validInput({ rows: [{ bracket_floor: 500, bracket_rate: 0.1 }] })
		);
		expect(result.ok).toBe(false);
		if (!result.ok) {
			expect(result.status).toBe(400);
			expect(result.errors).toHaveProperty('rows');
		}
		expect(captured.rpcCalls).toHaveLength(0);
	});

	it('happy path → RPC called once with the exact 7-arg contract, no users_id, matching input', async () => {
		const captured: Captured = { readCalls: [], rpcCalls: [] };
		const client = supabaseMock(
			{ data: { id: 42, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
			{ data: null, error: null },
			captured
		);
		const input = validInput();
		const result = await replaceTaxBracketSchedule(client, 42, input);
		expect(result).toEqual({ ok: true });
		expect(captured.readCalls).toEqual([{ col: 'id', val: 42 }]);
		expect(captured.rpcCalls).toHaveLength(1);
		const call = captured.rpcCalls[0];
		expect(call.fn).toBe('fn_tax_bracket_schedule_replace_all');
		expect(call.params).not.toHaveProperty('p_users_id');
		expect(call.params).not.toHaveProperty('users_id');
		expect(call.params).toEqual({
			p_schedule_id: 42,
			p_tax_year: input.tax_year,
			p_schedule_type: input.schedule_type,
			p_schedule_label: input.schedule_label,
			p_standard_deduction: input.standard_deduction,
			p_tax_balance_prior_year: input.tax_balance_prior_year,
			p_rows: input.rows
		});
	});

	describe('RPC error mapping', () => {
		const cases: Array<[string, number]> = [
			['42501', 403],
			['P0001', 400],
			['23514', 400],
			['23505', 409],
			['40001', 409],
			['55000', 500]
		];

		for (const [code, status] of cases) {
			it(`'${code}' → ${status}`, async () => {
				const captured: Captured = { readCalls: [], rpcCalls: [] };
				const client = supabaseMock(
					{ data: { id: 1, tax_year: 2026, schedule_type: 'federal_ordinary' }, error: null },
					{ data: null, error: { code, message: 'x' } },
					captured
				);
				const result = await replaceTaxBracketSchedule(client, 1, validInput());
				expect(result.ok).toBe(false);
				if (!result.ok) expect(result.status).toBe(status);
			});
		}
	});
});
