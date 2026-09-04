// TaxBracketSchedulesList.dom.test.ts — SELF-265 verification battery, reconciled against
// team-lead ruling E35 (under F/CTO delegation): prior-year schedules stay fully editable
// (collapsed under "Prior years on file", not delete-only), and delete renders only when a
// jurisdiction holds more than one schedule (never on the sole schedule of a type). Covers:
//   - AC1 three-jurisdiction rendering when every type has a current-year schedule, and no
//     delete control anywhere (each type holds exactly one schedule).
//   - the AC7a/E22 informational note + "Add {currentTaxYear} schedule" toggle, in both
//     sub-cases (a prior-year basis exists vs. no schedule at all for that type), with the
//     exact wording E35 specifies.
//   - the create panel prefilling from the basis schedule as a starting template.
//   - "Prior years on file" rendering a collapsed, fully-editable disclosure per superseded
//     schedule, with delete now available on BOTH the basis and prior editors once a
//     jurisdiction holds more than one schedule.
//   - the auto-open create-panel default RE-DERIVES from a live `jurisdictions` prop change
//     (team-lead correction, post-E35): `+page.svelte` instantiates this component with no
//     `{#key ...}` wrapper, so a real `invalidateAll()`-driven reload updates `jurisdictions` on
//     the SAME instance rather than remounting it (verified against that file directly — grep
//     turned up no `{#key` anywhere in the route). A one-time-captured default would go stale
//     the moment ANY jurisdiction's create/save/delete completed elsewhere on the page; this
//     uses `rerender()` (the same same-instance-prop-update tool NonReAllocationTable.dom.test.ts
//     already uses for its own stale→fresh leg) to prove the default re-derives without a
//     remount.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent, within } from '@testing-library/svelte';
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

function threeCurrentJurisdictions(): Jurisdiction[] {
	return [
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
}

describe('TaxBracketSchedulesList — AC1 three-jurisdiction grouping (all current, one schedule each)', () => {
	it('renders all three jurisdiction editors, no missing-schedule note, and no delete control anywhere (E35(b): sole schedule per type)', () => {
		const { getByRole, queryByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: threeCurrentJurisdictions(), currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByRole('heading', { name: 'Federal — Ordinary Income' })).toBeTruthy();
		expect(getByRole('heading', { name: 'Federal — Long-Term Capital Gains' })).toBeTruthy();
		expect(getByRole('heading', { name: 'California (FTB) — Ordinary Income' })).toBeTruthy();
		expect(queryByRole('status')).toBeNull(); // no missing-schedule note
		expect(queryByRole('button', { name: /Add 2026 schedule/ })).toBeNull();
		expect(queryByRole('button', { name: /^Delete /i })).toBeNull();
	});
});

describe('TaxBracketSchedulesList — AC7a/E22 prior-year-basis fallback note (E35 wording)', () => {
	it('shows "No {type} schedule entered for {year} — using {basis}." and an Add-schedule toggle, while still rendering the basis-year editor', async () => {
		const jurisdictions: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 2),
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
			getByText('No California (FTB) — Ordinary Income schedule entered for 2026 — using 2025.')
		).toBeTruthy();
		// the 2025 basis schedule's own editor still renders (tax year visible)
		expect(getByText('Tax year 2025')).toBeTruthy();
		// create panel is closed by default when a basis exists — opens on click
		expect(queryByRole('button', { name: 'Create schedule' })).toBeNull();
		await fireEvent.click(getByRole('button', { name: 'Add 2026 schedule' }));
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();
	});
});

describe('TaxBracketSchedulesList — no schedule at all for a jurisdiction', () => {
	it('shows "No {type} schedule entered." and an auto-open, blank create panel (no basis editor)', () => {
		const jurisdictions: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 2),
			{ schedule_type: 'california_ordinary', schedules: [], current_year_present: false, basis_year: null }
		];
		const { getByText, getByRole, queryByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByText('No California (FTB) — Ordinary Income schedule entered.')).toBeTruthy();
		// no basis editor to show — but the create panel auto-opens since there's nothing else
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();
		expect(queryByRole('button', { name: /Add 2026 schedule/ })).toBeNull(); // already open, no toggle shown
	});
});

describe('TaxBracketSchedulesList — "Prior years on file" (E35(a): fully editable, not delete-only)', () => {
	function jurisdictionsWithPriorYear(): Jurisdiction[] {
		return [
			{
				schedule_type: 'federal_ordinary',
				schedules: [
					makeSchedule({ id: 1, schedule_type: 'federal_ordinary', tax_year: 2026 }),
					makeSchedule({ id: 9, schedule_type: 'federal_ordinary', tax_year: 2024, schedule_label: 'Old 2024' })
				],
				current_year_present: true,
				basis_year: 2026
			},
			...threeCurrentJurisdictions().slice(1)
		];
	}

	it('lists the superseded schedule collapsed under a disclosure, as its own full editor', () => {
		const { getByText } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: jurisdictionsWithPriorYear(), currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(getByText('Prior years on file')).toBeTruthy();
		expect(getByText('2024 — Old 2024')).toBeTruthy();
		// the prior schedule's OWN editor renders (its own "Tax year 2024" tag), not just a label
		expect(getByText('Tax year 2024')).toBeTruthy();
	});

	it('E35(b): delete is now available on BOTH the basis and the prior-year editor, since the jurisdiction holds two schedules', () => {
		const { getAllByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: jurisdictionsWithPriorYear(), currentTaxYear: CURRENT_TAX_YEAR }
		});
		const deleteButtons = getAllByRole('button', { name: /^Delete Federal — Ordinary Income/i });
		expect(deleteButtons).toHaveLength(2); // one for the 2026 basis, one for the 2024 prior
	});

	it('renders no "Prior years on file" section when only the basis schedule exists', () => {
		const { queryByText } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: threeCurrentJurisdictions(), currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(queryByText('Prior years on file')).toBeNull();
	});
});

describe('TaxBracketSchedulesList — auto-open default RE-DERIVES from a live jurisdictions prop (no remount)', () => {
	it('a create panel that auto-opened because a type had no schedule closes on its own once a fresh load reports a schedule for it — WITHOUT remounting the component', async () => {
		const noScheduleYet: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 2),
			{ schedule_type: 'california_ordinary', schedules: [], current_year_present: false, basis_year: null }
		];
		const { getByRole, queryByRole, rerender } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: noScheduleYet, currentTaxYear: CURRENT_TAX_YEAR }
		});
		// auto-opened: nothing else to show for this type
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();

		// Simulate the SAME reload a successful ?/createSchedule submit's `update()` triggers —
		// `jurisdictions` changes reference on the SAME component instance (rerender, not
		// render()-again), matching +page.svelte's un-keyed instantiation.
		const nowHasSchedule: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 2),
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary' })],
				current_year_present: true,
				basis_year: 2026
			}
		];
		await rerender({ jurisdictions: nowHasSchedule, currentTaxYear: CURRENT_TAX_YEAR });

		expect(queryByRole('button', { name: 'Create schedule' })).toBeNull();
		expect(queryByRole('status')).toBeNull(); // no missing-schedule note either — current now
	});

	it('a manual "Add {year} schedule" click opens the panel for a type that already had a basis (not auto-open), and it survives a re-render carrying an IDENTICAL jurisdictions value', async () => {
		const withBasisButNotCurrent: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 2),
			{
				schedule_type: 'california_ordinary',
				schedules: [makeSchedule({ id: 3, schedule_type: 'california_ordinary', tax_year: 2025 })],
				current_year_present: false,
				basis_year: 2025
			}
		];
		const { getByRole, queryByRole, rerender } = render(TaxBracketSchedulesList, {
			props: { jurisdictions: withBasisButNotCurrent, currentTaxYear: CURRENT_TAX_YEAR }
		});
		expect(queryByRole('button', { name: 'Create schedule' })).toBeNull(); // closed until clicked
		await fireEvent.click(getByRole('button', { name: 'Add 2026 schedule' }));
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();

		// A rerender with a NEW array reference but the SAME underlying facts (as a re-run
		// load() of unchanged data would produce) resets the override in this implementation —
		// documented trade-off (file header): the whole page's manual toggles reset together on
		// any reload, matching how `update()` already refreshes every form on the page at once.
		await rerender({ jurisdictions: [...withBasisButNotCurrent], currentTaxYear: CURRENT_TAX_YEAR });
		expect(queryByRole('button', { name: 'Create schedule' })).toBeNull();
	});
});

describe('TaxBracketSchedulesList — federal_lt_cg create-from-template prefill forces 0 (Sec review, feature/self-262)', () => {
	it('prefills the create panel’s standard deduction at 0 even when the basis schedule stores a non-zero value (a legacy/anomalous row)', async () => {
		const jurisdictions: Jurisdiction[] = [
			...threeCurrentJurisdictions().slice(0, 1),
			{
				schedule_type: 'federal_lt_cg',
				schedules: [
					makeSchedule({
						id: 2,
						schedule_type: 'federal_lt_cg',
						tax_year: 2025,
						standard_deduction: 5000 // anomalous — should never reach the create prefill
					})
				],
				current_year_present: false,
				basis_year: 2025
			},
			...threeCurrentJurisdictions().slice(2)
		];
		const { getByRole } = render(TaxBracketSchedulesList, {
			props: { jurisdictions, currentTaxYear: CURRENT_TAX_YEAR }
		});
		await fireEvent.click(getByRole('button', { name: 'Add 2026 schedule' }));

		// Scope to the federal_lt_cg <section> (an implicit ARIA "region", since it carries an
		// accessible name via aria-labelledby) — the OTHER two jurisdictions' own "Standard
		// deduction" fields are ordinary editable ones and must not be swept into this assertion.
		const ltCgSection = getByRole('region', { name: 'Federal — Long-Term Capital Gains' });
		// Two "Standard deduction" fields now render inside it: the 2025 basis editor's own
		// (locked at 0 per its own stored value being ignored downstream) and the new create
		// panel's (must ALSO be 0, proving the override, not just a coincidence of the basis
		// already being 0).
		const deductionFields = within(ltCgSection).getAllByLabelText('Standard deduction') as HTMLInputElement[];
		expect(deductionFields).toHaveLength(2);
		for (const field of deductionFields) {
			expect(field.value).toBe('0');
			expect(field.disabled).toBe(true);
		}
	});
});
