// TaxBracketSchedulesList.dom.test.ts — SELF-265 verification battery (AC1 grouping + the
// missing-jurisdiction informational note, the one AC7a-adjacent case this component can
// actually observe: a schedule_type absent from the loader's array entirely).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import TaxBracketSchedulesList from './TaxBracketSchedulesList.svelte';

type Schedule = {
	id: number;
	tax_year: number;
	schedule_type: 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';
	schedule_label: string;
	standard_deduction: number;
	tax_balance_prior_year: number | null;
	rows: { bracket_floor: number; bracket_rate: number }[];
};

function makeSchedule(overrides: Partial<Schedule>): Schedule {
	return {
		id: 1,
		tax_year: 2026,
		schedule_type: 'federal_ordinary',
		schedule_label: 'Single filer',
		standard_deduction: 15000,
		tax_balance_prior_year: null,
		rows: [{ bracket_floor: 0, bracket_rate: 0.1 }],
		...overrides
	};
}

describe('TaxBracketSchedulesList — AC1 three-jurisdiction grouping', () => {
	it('renders all three jurisdiction editors when all three schedules are present', () => {
		const schedules: Schedule[] = [
			makeSchedule({ id: 1, schedule_type: 'federal_ordinary' }),
			makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 }),
			makeSchedule({ id: 3, schedule_type: 'california_ordinary', tax_year: 2025 })
		];
		const { getByRole, queryByRole } = render(TaxBracketSchedulesList, { props: { schedules } });
		expect(getByRole('heading', { name: 'Federal — Ordinary Income' })).toBeTruthy();
		expect(getByRole('heading', { name: 'Federal — Long-Term Capital Gains' })).toBeTruthy();
		expect(getByRole('heading', { name: 'California (FTB) — Ordinary Income' })).toBeTruthy();
		expect(queryByRole('status')).toBeNull(); // no missing-schedule note when all three exist
	});
});

describe('TaxBracketSchedulesList — missing-jurisdiction informational note', () => {
	it('renders an honest gap note (never a fabricated "Add schedule" affordance) for an absent type', () => {
		const schedules: Schedule[] = [
			makeSchedule({ id: 1, schedule_type: 'federal_ordinary' }),
			makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 })
			// california_ordinary intentionally absent
		];
		const { getByText, queryByRole, getByRole } = render(TaxBracketSchedulesList, { props: { schedules } });
		expect(getByText('No California (FTB) — Ordinary Income schedule on file yet.')).toBeTruthy();
		// the two present schedules still render their editors
		expect(getByRole('heading', { name: 'Federal — Ordinary Income' })).toBeTruthy();
		// no button offering to create the missing schedule — no such endpoint exists (see file
		// header's reconciliation note)
		expect(queryByRole('button', { name: /add.*california/i })).toBeNull();
	});
});
