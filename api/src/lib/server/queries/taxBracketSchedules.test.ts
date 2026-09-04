// taxBracketSchedules.test.ts — unit coverage for the /settings/tax-brackets editor's read helper
// (SELF-265 AC1/AC2/AC8/AC8b). Pure-TS server test (node env per vitest.config). Mocks the
// supabase-js chain:
//   .schema('pfin').from('tax_bracket_schedule').select(...).order(...).order(...)
//   .schema('pfin').from('tax_bracket_row').select(...).order(...).order(...)
//   → { data, error } each.
//
// Proves: the fixed three-jurisdiction grouping (even when empty); row-to-schedule attachment by
// schedule_id; the current_year_present flag; the E22 prior-year basis_year fallback (and its
// absence when no current-or-prior schedule exists); numeric transport coercion; and fail-soft
// degradation on a schedule-read error (whole page → empty), a row-read error (schedules render,
// rows empty), and a thrown chain.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadTaxBracketSchedules, TAX_SCHEDULE_TYPES } from './taxBracketSchedules';

type Result<T> = { data: T | null; error: { message: string } | null };

function makeSupabase(
	scheduleResult: Result<unknown[]>,
	rowResult: Result<unknown[]>
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
	const schema = vi.fn(() => ({ from }));
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
});
