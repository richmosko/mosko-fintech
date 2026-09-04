// taxBracketSchedules.test.ts — unit coverage for the /settings/tax-brackets editor's read helper
// (SELF-265 AC1/AC2/AC8/AC8b). Pure-TS server test (node env per vitest.config). Mocks the
// supabase-js chain:
//   .schema('pfin').from('tax_bracket_schedule').select(...).order(...).order(...)
//   .schema('pfin').from('tax_bracket_row').select(...).order(...).order(...)
//   → { data, error } each.
//
// Proves: the fixed three-jurisdiction grouping (even when empty); row-to-schedule attachment by
// schedule_id; the current_year_present flag; the E22 prior-year basis_year fallback (and its
// absence when no current-or-prior schedule exists); numeric transport coercion; fail-soft
// degradation on a schedule-read error (whole page → empty), a row-read error (schedules render,
// rows empty), and a thrown chain; and (SELF-265 second pass, E38) the `is_seed_template` marking
// against `pfin.fn_tax_bracket_seed_template()`, including its own fail-OPEN degradation.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadTaxBracketSchedules, TAX_SCHEDULE_TYPES } from './taxBracketSchedules';

type Result<T> = { data: T | null; error: { message: string } | null };

// The live migration 103 template, flat (one row per bracket) — used as the DEFAULT seed-
// template RPC result so every pre-existing test call site (which passes no third argument)
// keeps behaving as it did before `is_seed_template` existed. Deliberately mirrors 103's actual
// three tuples (federal_ordinary/2026, federal_lt_cg/2026, california_ordinary/2025) rather than
// an arbitrary fixture, so a real drift between the migration and this test would need a second,
// independent transcription error to go unnoticed.
const LIVE_SEED_TEMPLATE_RESULT: Result<unknown[]> = {
	data: [
		{ schedule_type: 'federal_ordinary', tax_year: 2026, standard_deduction: 16100, schedule_label: 'x', bracket_floor: 0, bracket_rate: 0.1 },
		{ schedule_type: 'federal_lt_cg', tax_year: 2026, standard_deduction: 0, schedule_label: 'x', bracket_floor: 0, bracket_rate: 0 },
		{ schedule_type: 'california_ordinary', tax_year: 2025, standard_deduction: 5706, schedule_label: 'x', bracket_floor: 0, bracket_rate: 0.01 },
		{ schedule_type: 'california_ordinary', tax_year: 2025, standard_deduction: 5706, schedule_label: 'x', bracket_floor: 11079, bracket_rate: 0.02 }
	],
	error: null
};

function makeSupabase(
	scheduleResult: Result<unknown[]>,
	rowResult: Result<unknown[]>,
	seedTemplateResult: Result<unknown[]> = LIVE_SEED_TEMPLATE_RESULT
): { client: SupabaseClient; from: ReturnType<typeof vi.fn> } {
	const scheduleOrder2 = vi.fn(() => Promise.resolve(scheduleResult));
	const scheduleOrder1 = vi.fn(() => ({ order: scheduleOrder2 }));
	const scheduleSelect = vi.fn(() => ({ order: scheduleOrder1 }));

	const rowOrder2 = vi.fn(() => Promise.resolve(rowResult));
	const rowOrder1 = vi.fn(() => ({ order: rowOrder2 }));
	const rowSelect = vi.fn(() => ({ order: rowOrder1 }));

	const from = vi.fn((table: string) => {
		if (table === 'tax_bracket_schedule') return { select: scheduleSelect };
		if (table === 'tax_bracket_row') return { select: rowSelect };
		throw new Error(`unexpected table ${table}`);
	});
	const rpc = vi.fn((fn: string) => {
		if (fn === 'fn_tax_bracket_seed_template') return Promise.resolve(seedTemplateResult);
		throw new Error(`unexpected rpc ${fn}`);
	});
	const schema = vi.fn(() => ({ from, rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, from };
}

const EMPTY_ROWS: Result<unknown[]> = { data: [], error: null };

describe('loadTaxBracketSchedules', () => {
	it('returns all three fixed jurisdictions, empty, when the caller holds no schedules', async () => {
		const { client } = makeSupabase({ data: [], error: null }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		expect(result.map((j) => j.schedule_type)).toEqual([...TAX_SCHEDULE_TYPES]);
		for (const j of result) {
			expect(j.schedules).toEqual([]);
			expect(j.current_year_present).toBe(false);
			expect(j.basis_year).toBeNull();
		}
	});

	it('attaches rows to the correct schedule by schedule_id, coercing string numerics', async () => {
		const schedules = [
			{
				id: 1,
				tax_year: 2026,
				schedule_type: 'federal_ordinary',
				schedule_label: '2026 federal ordinary',
				standard_deduction: '14600.00',
				tax_balance_prior_year: null
			}
		];
		const rows = [
			{ schedule_id: 1, bracket_floor: '0.0000', bracket_rate: '0.10000000' },
			{ schedule_id: 1, bracket_floor: '11600.0000', bracket_rate: '0.12000000' }
		];
		const { client } = makeSupabase({ data: schedules, error: null }, { data: rows, error: null });
		const result = await loadTaxBracketSchedules(client, 2026);
		const jurisdiction = result.find((j) => j.schedule_type === 'federal_ordinary')!;
		expect(jurisdiction.schedules).toHaveLength(1);
		expect(jurisdiction.schedules[0]).toEqual({
			id: 1,
			tax_year: 2026,
			schedule_type: 'federal_ordinary',
			schedule_label: '2026 federal ordinary',
			standard_deduction: 14600,
			tax_balance_prior_year: null,
			is_seed_template: true, // (2026, federal_ordinary) is one of 103's live template tuples
			rows: [
				{ bracket_floor: 0, bracket_rate: 0.1 },
				{ bracket_floor: 11600, bracket_rate: 0.12 }
			]
		});
	});

	it('current_year_present is true when a schedule of that type matches currentTaxYear', async () => {
		const schedules = [
			{
				id: 1,
				tax_year: 2026,
				schedule_type: 'california_ordinary',
				schedule_label: 'x',
				standard_deduction: 0,
				tax_balance_prior_year: null
			}
		];
		const { client } = makeSupabase({ data: schedules, error: null }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		const j = result.find((j) => j.schedule_type === 'california_ordinary')!;
		expect(j.current_year_present).toBe(true);
		expect(j.basis_year).toBe(2026);
	});

	it('E22 fallback: current year absent → basis_year is the LATEST prior year actually present', async () => {
		// Already tax_year DESC, matching the DB's own `.order('tax_year', {ascending:false})` —
		// this stub returns raw arrays verbatim rather than simulating a real ORDER BY.
		const schedules = [
			{ id: 2, tax_year: 2025, schedule_type: 'federal_lt_cg', schedule_label: 'b', standard_deduction: 0, tax_balance_prior_year: null },
			{ id: 1, tax_year: 2023, schedule_type: 'federal_lt_cg', schedule_label: 'a', standard_deduction: 0, tax_balance_prior_year: null }
		];
		const { client } = makeSupabase({ data: schedules, error: null }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		const j = result.find((j) => j.schedule_type === 'federal_lt_cg')!;
		expect(j.current_year_present).toBe(false);
		expect(j.basis_year).toBe(2025);
		expect(j.schedules.map((s) => s.tax_year)).toEqual([2025, 2023]);
	});

	it('a FUTURE-dated schedule (relative to currentTaxYear) is neither current nor a fallback basis', async () => {
		const schedules = [
			{ id: 1, tax_year: 2027, schedule_type: 'federal_ordinary', schedule_label: 'a', standard_deduction: 0, tax_balance_prior_year: null }
		];
		const { client } = makeSupabase({ data: schedules, error: null }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		const j = result.find((j) => j.schedule_type === 'federal_ordinary')!;
		expect(j.current_year_present).toBe(false);
		expect(j.basis_year).toBeNull();
	});

	it('schedule-read error → degrades the WHOLE page to the three empty jurisdictions', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeSupabase({ data: null, error: { message: 'boom' } }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		expect(result.every((j) => j.schedules.length === 0)).toBe(true);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('row-read error → schedules still render, with empty rows arrays (narrower degradation)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const schedules = [
			{ id: 1, tax_year: 2026, schedule_type: 'federal_ordinary', schedule_label: 'a', standard_deduction: 0, tax_balance_prior_year: null }
		];
		const { client } = makeSupabase({ data: schedules, error: null }, { data: null, error: { message: 'boom' } });
		const result = await loadTaxBracketSchedules(client, 2026);
		const j = result.find((j) => j.schedule_type === 'federal_ordinary')!;
		expect(j.schedules).toHaveLength(1);
		expect(j.schedules[0].rows).toEqual([]);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('a thrown chain degrades to the three empty jurisdictions (fail-soft, never throws)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		const result = await loadTaxBracketSchedules(client, 2026);
		expect(result.every((j) => j.schedules.length === 0)).toBe(true);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	// ── is_seed_template (SELF-265 second pass, E38) ────────────────────────────────────────────

	it('marks the three provisioned seed-template tuples, and NOT a user-created 2026 CA schedule', async () => {
		const schedules = [
			{ id: 1, tax_year: 2026, schedule_type: 'federal_ordinary', schedule_label: 'a', standard_deduction: 16100, tax_balance_prior_year: null },
			{ id: 2, tax_year: 2026, schedule_type: 'federal_lt_cg', schedule_label: 'b', standard_deduction: 0, tax_balance_prior_year: null },
			{ id: 3, tax_year: 2025, schedule_type: 'california_ordinary', schedule_label: 'c', standard_deduction: 5706, tax_balance_prior_year: null },
			// A user-authored schedule for a (tax_year, schedule_type) the template does NOT hold —
			// the exact case AC7a/E22's CTA exists for (California 2026, once the user adds it
			// themselves ahead of the FTB seed landing).
			{ id: 4, tax_year: 2026, schedule_type: 'california_ordinary', schedule_label: 'user-created 2026 CA', standard_deduction: 6000, tax_balance_prior_year: null }
		];
		const { client } = makeSupabase({ data: schedules, error: null }, EMPTY_ROWS);
		const result = await loadTaxBracketSchedules(client, 2026);
		const byId = (id: number) => result.flatMap((j) => j.schedules).find((s) => s.id === id)!;
		expect(byId(1).is_seed_template).toBe(true);
		expect(byId(2).is_seed_template).toBe(true);
		expect(byId(3).is_seed_template).toBe(true);
		expect(byId(4).is_seed_template).toBe(false);
	});

	it('seed-template RPC failure → is_seed_template defaults to false for every schedule (fail-OPEN, informational only)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const schedules = [
			{ id: 1, tax_year: 2026, schedule_type: 'federal_ordinary', schedule_label: 'a', standard_deduction: 16100, tax_balance_prior_year: null }
		];
		const { client } = makeSupabase(
			{ data: schedules, error: null },
			EMPTY_ROWS,
			{ data: null, error: { message: 'boom' } }
		);
		const result = await loadTaxBracketSchedules(client, 2026);
		const j = result.find((j) => j.schedule_type === 'federal_ordinary')!;
		expect(j.schedules[0].is_seed_template).toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});
