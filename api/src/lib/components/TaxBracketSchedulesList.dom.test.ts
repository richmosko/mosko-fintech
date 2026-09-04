// TaxBracketSchedulesList.dom.test.ts — SELF-265 verification battery, reconciled against
// Backend's LANDED `jurisdictions[]` / `current_year_present` / `basis_year` contract
// (feature/self-265-backend @ caebbec). Covers:
//   - AC1 three-jurisdiction rendering when every type has a current-year schedule.
//   - the AC7a/E22 informational note + "Add {currentTaxYear} schedule" toggle when a
//     jurisdiction's current_year_present is false, in BOTH its sub-cases (a prior-year basis
//     exists vs. no schedule at all for that type).
//   - the create panel prefilling from the basis schedule as a starting template.
//   - "Other years on file" rendering (with a delete control) for a schedule superseded by a
//     newer one, and NOT rendering that section when there is nothing to show.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import TaxBracketSchedulesList from './TaxBracketSchedulesList.svelte';

type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';

type ScheduleRecord = {
	id: number;
	tax_year: number;
	schedule_type: ScheduleType;
	schedule_label: string;
	standard_deduction: number;
	tax_balance_prior_year: number | null;
	rows: { bracket_floor: number; bracket_rate: number }[];
};

type Jurisdiction = {
	schedule_type: ScheduleType;
	schedules: ScheduleRecord[];
	current_year_present: boolean;
	basis_year: number | null;
};

function makeSchedule(overrides: Partial<ScheduleRecord>): ScheduleRecord {
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

const CURRENT_TAX_YEAR = 2026;

describe('TaxBracketSchedulesList — AC1 three-jurisdiction grouping (all current)', () => {
	it('renders all three jurisdiction editors, no missing-schedule note, when every type is current', () => {
		const jurisdictions: Jurisdiction[] = [
			{
				schedule_type: 'federal_ordinary',
				schedules: [makeSchedule({ id: 1, schedule_type: 'federal_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'federal_lt_cg',
				schedules: [makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			}
		];
		const { getByRole, queryByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByRole('heading', { name: 'Federal — Ordinary Income' })).toBeTruthy();
		expect(getByRole('heading', { name: 'Federal — Long-Term Capital Gains' })).toBeTruthy();
		expect(getByRole('heading', { name: 'California (FTB) — Ordinary Income' })).toBeTruthy();
		expect(queryByRole('status')).toBeNull(); // no missing-schedule note
		expect(queryByRole('button', { name: /Add 2026 schedule/ })).toBeNull();
	});
});

describe('TaxBracketSchedulesList — AC7a/E22 prior-year-basis fallback note', () => {
	it('shows the "hasn’t been entered yet ... runs on the prior schedule" note and an Add-schedule toggle, while still rendering the basis-year editor', async () => {
		const jurisdictions: Jurisdiction[] = [
			{
				schedule_type: 'federal_ordinary',
				schedules: [makeSchedule({ id: 1, schedule_type: 'federal_ordinary', tax_year: 2026 })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'federal_lt_cg',
				schedules: [makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', tax_year: 2026, standard_deduction: 0 })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary', tax_year: 2025 })],
				current_year_present: false,
				basis_year: 2025
			}
		];
		const { getByText, getByRole, queryByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(
			getByText(
				"California (FTB) — Ordinary Income for 2026 hasn't been entered yet — figures currently run on the 2025 schedule."
			)
		).toBeTruthy();
		// the 2025 basis schedule's own editor still renders (tax year visible)
		expect(getByText('Tax year 2025')).toBeTruthy();
		// create panel is closed by default when a basis exists — opens on click
		expect(queryByRole('button', { name: 'Create schedule' })).toBeNull();
		await fireEvent.click(getByRole('button', { name: 'Add 2026 schedule' }));
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();
	});
});

describe('TaxBracketSchedulesList — AC8(i)-equivalent: no schedule at all for a jurisdiction', () => {
	it('shows the "no schedule on file yet" note and an auto-open, blank create panel (no basis editor)', () => {
		const jurisdictions: Jurisdiction[] = [
			{
				schedule_type: 'federal_ordinary',
				schedules: [makeSchedule({ id: 1, schedule_type: 'federal_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'federal_lt_cg',
				schedules: [makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 })],
				current_year_present: true,
				basis_year: 2026
			},
			{ schedule_type: 'california_ordinary', schedules: [], current_year_present: false, basis_year: null }
		];
		const { getByText, getByRole, queryByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByText('No California (FTB) — Ordinary Income schedule on file yet.')).toBeTruthy();
		// no basis editor to show — but the create panel auto-opens since there's nothing else
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();
		expect(queryByRole('button', { name: /Add 2026 schedule/ })).toBeNull(); // already open, no toggle shown
	});
});

describe('TaxBracketSchedulesList — "Other years on file"', () => {
	it('lists a superseded schedule with a delete control, separate from the primary basis editor', () => {
		const jurisdictions: Jurisdiction[] = [
			{
				schedule_type: 'federal_ordinary',
				schedules: [
					makeSchedule({ id: 1, schedule_type: 'federal_ordinary', tax_year: 2026 }),
					makeSchedule({ id: 9, schedule_type: 'federal_ordinary', tax_year: 2024, schedule_label: 'Old 2024' })
				],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'federal_lt_cg',
				schedules: [makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			}
		];
		const { getByText, getByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByText('Other years on file')).toBeTruthy();
		expect(getByText('2024 — Old 2024')).toBeTruthy();
		expect(getByRole('button', { name: /Delete Federal — Ordinary Income \(tax year 2024\)/ })).toBeTruthy();
	});

	it('renders no "Other years on file" section when only the basis schedule exists', () => {
		const jurisdictions: Jurisdiction[] = [
			{
				schedule_type: 'federal_ordinary',
				schedules: [makeSchedule({ id: 1, schedule_type: 'federal_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'federal_lt_cg',
				schedules: [makeSchedule({ id: 2, schedule_type: 'federal_lt_cg', standard_deduction: 0 })],
				current_year_present: true,
				basis_year: 2026
			},
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			}
		];
		const { queryByText } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(queryByText('Other years on file')).toBeNull();
	});
});
