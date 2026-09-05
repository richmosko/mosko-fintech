// GenerateMonthlyReportControl.dom.test.ts — SELF-357 / P5 AC3, E15 items 9-10. Covers:
//   - both candidates render as <option>s, prior month selected by default;
//   - the CTA label reacts to the selected option's server-computed state ('none' -> "Generate
//     monthly report"; 'draft' -> "Continue {Month YYYY}"; 'final' -> disabled + hint note);
//   - the posted FormData carries the currently-selected month.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import GenerateMonthlyReportControl from './GenerateMonthlyReportControl.svelte';

type Candidate = {
	targetMonth: string;
	label: string;
	plainLabel: string;
	state: 'none' | 'draft' | 'final';
};

const PRIOR: Candidate = {
	targetMonth: '2026-08-01',
	label: 'August 2026',
	plainLabel: 'August 2026',
	state: 'none'
};
const CURRENT: Candidate = {
	targetMonth: '2026-09-01',
	label: 'September 2026 (in progress — as of today)',
	plainLabel: 'September 2026',
	state: 'none'
};

describe('GenerateMonthlyReportControl — candidates + default selection (AC3)', () => {
	it('renders both candidates as options, in order, with the current-month suffix verbatim', () => {
		const { getAllByRole } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, CURRENT] }
		});
		const options = getAllByRole('option').map((o) => o.textContent);
		expect(options).toEqual(['August 2026', 'September 2026 (in progress — as of today)']);
	});

	it('the prior month is selected by default', () => {
		const { getByRole } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, CURRENT] }
		});
		expect((getByRole('combobox') as HTMLSelectElement).value).toBe('2026-08-01');
	});
});

describe('GenerateMonthlyReportControl — CTA label per selected state (E15 items 9-10)', () => {
	it("state 'none' (default selection) -> \"Generate monthly report\"", () => {
		const { getByRole } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, CURRENT] }
		});
		expect(getByRole('button', { name: 'Generate monthly report' })).toBeTruthy();
	});

	it("state 'draft' -> \"Continue {Month YYYY}\", no confirmation copy, button enabled", async () => {
		const draftCurrent = { ...CURRENT, state: 'draft' as const };
		const { getByRole } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, draftCurrent] }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: draftCurrent.targetMonth } });
		const cta = getByRole('button', { name: 'Continue September 2026' }) as HTMLButtonElement;
		expect(cta.disabled).toBe(false);
	});

	it("state 'final' -> the CTA is disabled and a hint points at Regenerate instead", async () => {
		const finalCurrent = { ...CURRENT, state: 'final' as const };
		const { getByRole, getByText } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, finalCurrent] }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: finalCurrent.targetMonth } });
		expect((getByRole('button', { name: 'Generate monthly report' }) as HTMLButtonElement).disabled).toBe(true);
		expect(getByText(/already generated/i)).toBeTruthy();
	});
});

describe('GenerateMonthlyReportControl — posted FormData', () => {
	it('the hidden select value posted is the currently-selected candidate month', async () => {
		const { getByRole, container } = render(GenerateMonthlyReportControl, {
			props: { candidates: [PRIOR, CURRENT] }
		});
		const select = getByRole('combobox') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: CURRENT.targetMonth } });
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('target_month')).toBe('2026-09-01');
	});
});
