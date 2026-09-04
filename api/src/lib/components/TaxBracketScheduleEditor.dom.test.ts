// TaxBracketScheduleEditor.dom.test.ts — SELF-265 verification battery, reconciled against
// Backend's LANDED form-action contract (feature/self-265-backend @ caebbec). Covers:
//   - percent<->fraction round trip: fraction 0.22 displays "22"; editing a rate to "24" is
//     reflected in the hidden `rows` field as fraction 0.24 (a raw-DOM FormData read, the same
//     "no use:enhance needed for this assertion" pattern PurchaseEntryForm.dom.test.ts uses —
//     the visible/hidden fields already carry the right `name`s and values reactively).
//   - the first row's floor rendering DISABLED and fixed at "0" (structural-picker judgment
//     call named in this component's header) — Leg A's zero-floor courtesy message is therefore
//     untestable through this component's UI and is covered instead in
//     $lib/validation/taxBracketRows.test.ts, against the shared validation module directly.
//   - the rate-monotonicity courtesy message (Leg B) — reachable through normal editing.
//   - federal_lt_cg's standard deduction being STRUCTURALLY fixed at 0 (disabled, posts via a
//     separate hidden field, PRD §2.5.3 note visible), in both edit and create mode, overriding
//     even a caller-supplied non-zero initial value.
//   - the schedule-label textarea holding the seeded 473-character California label (E29).
//   - hidden identity fields: tax_year/schedule_type always present; schedule_id present in
//     'edit' mode, ABSENT in 'create' mode (no such identity exists yet).
//   - the create-mode action path and submit-button copy.
//   - canDelete gating (E35(b)): no delete control unless the caller explicitly says more than
//     one schedule exists for this type, and never in create mode. NOT covered here: the
//     `tax_year`-keyed duplicate-schedule error (E35 team-lead note) renders only after a real
//     createSchedule 409, which is server-error-rendering-after-submit — out of this harness's
//     reach for the same documented reason below.
//   - Save disabled (and no crash on a forced submit) while a courtesy check fails — this file
//     does NOT assert on server-error rendering after a real submit: `tests/stubs/app-forms.ts`'s
//     `enhance` stub deliberately never invokes a SubmitFunction's returned async callback (no
//     network pipeline in that stub), so a submitted form's RESULT is out of this harness's
//     reach — same scope boundary PurchaseEntryForm.dom.test.ts already accepts.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import TaxBracketScheduleEditor from './TaxBracketScheduleEditor.svelte';

type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';

const editProps = {
	mode: 'edit' as const,
	scheduleType: 'federal_ordinary' as ScheduleType,
	taxYear: 2026,
	scheduleId: 1,
	initialLabel: 'Single filer, 2026 IRS Schedule X',
	initialStandardDeduction: 15000,
	initialPriorYearBalance: null,
	initialRows: [
		{ bracket_floor: 0, bracket_rate: 0.1 },
		{ bracket_floor: 11000, bracket_rate: 0.22 }
	]
};

describe('TaxBracketScheduleEditor — percent<->fraction boundary (E1)', () => {
	it('renders stored fraction rates as percent strings', () => {
		const { getByLabelText } = render(TaxBracketScheduleEditor, { props: editProps });
		expect((getByLabelText('Bracket 2 rate') as HTMLInputElement).value).toBe('22');
	});

	it('the first row’s floor renders DISABLED and fixed at "0" — structurally unreachable for the zero-floor error', () => {
		const { getByLabelText } = render(TaxBracketScheduleEditor, { props: editProps });
		const fixedFloor = getByLabelText('Bracket 1 floor') as HTMLInputElement;
		expect(fixedFloor.value).toBe('0');
		expect(fixedFloor.disabled).toBe(true);
	});

	it('the hidden `rows` field reflects an edited percent as its FRACTION value', async () => {
		const { getByLabelText, container } = render(TaxBracketScheduleEditor, { props: editProps });
		await fireEvent.input(getByLabelText('Bracket 2 rate'), { target: { value: '24' } });

		const form = container.querySelector('form') as HTMLFormElement;
		const posted = new FormData(form);
		expect(JSON.parse(posted.get('rows') as string)).toEqual([
			{ bracket_floor: 0, bracket_rate: 0.1 },
			{ bracket_floor: 11000, bracket_rate: 0.24 }
		]);
	});
});

describe('TaxBracketScheduleEditor — identity fields', () => {
	it('edit mode posts schedule_id, tax_year, and schedule_type', () => {
		const { container } = render(TaxBracketScheduleEditor, { props: editProps });
		const form = container.querySelector('form') as HTMLFormElement;
		const posted = new FormData(form);
		expect(posted.get('schedule_id')).toBe('1');
		expect(posted.get('tax_year')).toBe('2026');
		expect(posted.get('schedule_type')).toBe('federal_ordinary');
		expect(form.getAttribute('action')).toBe('?/saveSchedule');
	});

	it('create mode posts NO schedule_id, targets ?/createSchedule, and labels its submit button "Create schedule"', () => {
		const { container, getByRole } = render(TaxBracketScheduleEditor, {
			props: {
				mode: 'create' as const,
				scheduleType: 'california_ordinary' as ScheduleType,
				taxYear: 2026,
				initialLabel: '',
				initialStandardDeduction: 0,
				initialPriorYearBalance: null,
				initialRows: [{ bracket_floor: 0, bracket_rate: 0 }]
			}
		});
		const form = container.querySelector('form') as HTMLFormElement;
		expect(form.getAttribute('action')).toBe('?/createSchedule');
		expect(new FormData(form).has('schedule_id')).toBe(false);
		expect(getByRole('button', { name: 'Create schedule' })).toBeTruthy();
	});
});

describe('TaxBracketScheduleEditor — Leg B rate-monotonicity courtesy message', () => {
	it('shows the non-decreasing-rate message and disables Save when a later rate drops below an earlier one', async () => {
		const { getByLabelText, getByRole, findByRole } = render(TaxBracketScheduleEditor, { props: editProps });
		await fireEvent.input(getByLabelText('Bracket 2 rate'), { target: { value: '5' } }); // below bracket 1's 10%
		const banner = await findByRole('alert');
		expect(banner.textContent).toBe('Bracket rates must not decrease as thresholds rise.');
		expect((getByRole('button', { name: 'Save changes' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('a forced submit while Save is disabled does not throw', async () => {
		const { getByLabelText, container } = render(TaxBracketScheduleEditor, { props: editProps });
		await fireEvent.input(getByLabelText('Bracket 2 rate'), { target: { value: '5' } });
		const form = container.querySelector('form') as HTMLFormElement;
		await expect(fireEvent.submit(form)).resolves.not.toThrow();
	});
});

describe('TaxBracketScheduleEditor — federal_lt_cg standard deduction is STRUCTURALLY fixed at 0 (Sec review, feature/self-262)', () => {
	it('renders the deduction field disabled, fixed at "0", with the PRD §2.5.3 note', () => {
		const { getByLabelText, getByText } = render(TaxBracketScheduleEditor, {
			props: { ...editProps, scheduleType: 'federal_lt_cg' as ScheduleType, initialStandardDeduction: 0 }
		});
		const deduction = getByLabelText('Standard deduction') as HTMLInputElement;
		expect(deduction.value).toBe('0');
		expect(deduction.disabled).toBe(true);
		expect(getByText('No standard deduction applies to the Federal LT CG schedule (PRD §2.5.3).')).toBeTruthy();
	});

	it('overrides a caller-supplied non-zero initial value to 0 — never trusts the prop for this type', () => {
		const { getByLabelText, container } = render(TaxBracketScheduleEditor, {
			props: { ...editProps, scheduleType: 'federal_lt_cg' as ScheduleType, initialStandardDeduction: 15000 }
		});
		expect((getByLabelText('Standard deduction') as HTMLInputElement).value).toBe('0');
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('standard_deduction')).toBe('0');
	});

	it('a disabled visible input would NOT post — the hidden field is what actually carries "0"', () => {
		const { container } = render(TaxBracketScheduleEditor, {
			props: { ...editProps, scheduleType: 'federal_lt_cg' as ScheduleType }
		});
		const form = container.querySelector('form') as HTMLFormElement;
		// Exactly one `standard_deduction` control in the DOM — the hidden field — never both a
		// disabled visible input AND a hidden one sharing the name (FormData would still work
		// either way, but two controls of the same name is a latent footgun this proves absent).
		expect(form.querySelectorAll('[name="standard_deduction"]')).toHaveLength(1);
		expect(new FormData(form).get('standard_deduction')).toBe('0');
	});

	it('locks the field in CREATE mode too, and the note still renders', () => {
		const { getByLabelText, getByText } = render(TaxBracketScheduleEditor, {
			props: {
				mode: 'create' as const,
				scheduleType: 'federal_lt_cg' as ScheduleType,
				taxYear: 2026,
				initialLabel: '',
				initialStandardDeduction: 0,
				initialPriorYearBalance: null,
				initialRows: [{ bracket_floor: 0, bracket_rate: 0 }]
			}
		});
		expect((getByLabelText('Standard deduction') as HTMLInputElement).disabled).toBe(true);
		expect(getByText('No standard deduction applies to the Federal LT CG schedule (PRD §2.5.3).')).toBeTruthy();
	});

	it('does NOT lock or show the note for a different schedule type', () => {
		const { getByLabelText, queryByText } = render(TaxBracketScheduleEditor, { props: editProps });
		expect((getByLabelText('Standard deduction') as HTMLInputElement).disabled).toBe(false);
		expect(queryByText(/No standard deduction applies/)).toBeNull();
	});
});

describe('TaxBracketScheduleEditor — canDelete gating (E35(b): never on the sole schedule of a type)', () => {
	it('renders no delete control by default (canDelete not passed)', () => {
		const { queryByRole } = render(TaxBracketScheduleEditor, { props: editProps });
		expect(queryByRole('button', { name: /^Delete /i })).toBeNull();
	});

	it('renders no delete control even in edit mode when canDelete is explicitly false', () => {
		const { queryByRole } = render(TaxBracketScheduleEditor, { props: { ...editProps, canDelete: false } });
		expect(queryByRole('button', { name: /^Delete /i })).toBeNull();
	});

	it('renders the delete control when canDelete is true (the list has already confirmed more than one schedule exists)', () => {
		const { getByRole } = render(TaxBracketScheduleEditor, { props: { ...editProps, canDelete: true } });
		expect(getByRole('button', { name: 'Delete Federal — Ordinary Income (tax year 2026)' })).toBeTruthy();
	});

	it('never renders a delete control in create mode, even if canDelete were somehow true', () => {
		const { queryByRole } = render(TaxBracketScheduleEditor, {
			props: {
				mode: 'create' as const,
				scheduleType: 'california_ordinary' as ScheduleType,
				taxYear: 2026,
				initialLabel: '',
				initialStandardDeduction: 0,
				initialPriorYearBalance: null,
				initialRows: [{ bracket_floor: 0, bracket_rate: 0 }],
				canDelete: true
			}
		});
		expect(queryByRole('button', { name: /^Delete /i })).toBeNull();
	});
});

describe('TaxBracketScheduleEditor — schedule_label textarea (E29 500-char bound)', () => {
	it('holds the seeded 473-character California label without truncation', () => {
		const longLabel = 'A'.repeat(473);
		const { getByLabelText } = render(TaxBracketScheduleEditor, {
			props: { ...editProps, initialLabel: longLabel }
		});
		const textarea = getByLabelText('Schedule label', { exact: false }) as HTMLTextAreaElement;
		expect(textarea.value).toBe(longLabel);
		expect(textarea.value.length).toBe(473);
	});
});
