// RegenerateReportControl.dom.test.ts — SELF-357 / P5 AC4/E15 item 10. Covers:
//   - the inline two-step disclosure (never window.confirm() — this codebase's own
//     DeleteScheduleControl.svelte convention): "Regenerate" reveals a confirm row; Cancel
//     hides it again without posting anything.
//   - AC4's confirm copy, verbatim, interpolating the target month's label.
//   - the confirm form's hidden target_month field carries the targetMonth prop.
//   - clicking "Yes, regenerate" enters the loading state (the SYNCHRONOUS half of the
//     use:enhance SubmitFunction runs under tests/stubs/app-forms.ts's real-submit-event stub;
//     the async post-fetch callback is out of this stub's scope, same documented boundary
//     TaxBracketScheduleEditor.dom.test.ts / PurchaseEntryForm.dom.test.ts already accept).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import RegenerateReportControl from './RegenerateReportControl.svelte';

const PROPS = { targetMonth: '2026-08-01', monthLabel: 'August 2026' };

describe('RegenerateReportControl — inline confirm, not window.confirm()', () => {
	it('shows only the "Regenerate" link-button initially; no confirm row, nothing posted', () => {
		const { getByRole, queryByText } = render(RegenerateReportControl, { props: PROPS });
		expect(getByRole('button', { name: 'Regenerate August 2026' })).toBeTruthy();
		expect(queryByText(/The current report is replaced/)).toBeNull();
	});

	it('clicking Regenerate reveals the confirm row with AC4\'s verbatim copy', async () => {
		const { getByRole, getByText } = render(RegenerateReportControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Regenerate August 2026' }));
		expect(
			getByText(
				'Regenerate August 2026? The current report is replaced; your existing commentary is loaded into the editor to edit or keep.'
			)
		).toBeTruthy();
		expect(getByRole('button', { name: 'Yes, regenerate' })).toBeTruthy();
	});

	it('Cancel hides the confirm row again without posting', async () => {
		const { getByRole, queryByText, getByText } = render(RegenerateReportControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Regenerate August 2026' }));
		await fireEvent.click(getByRole('button', { name: 'Cancel' }));
		expect(queryByText(/The current report is replaced/)).toBeNull();
		expect(getByText('Regenerate')).toBeTruthy();
	});

	it('the confirm form carries the target month as a hidden field', async () => {
		const { getByRole, container } = render(RegenerateReportControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Regenerate August 2026' }));
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('target_month')).toBe('2026-08-01');
	});

	it('clicking "Yes, regenerate" enters the loading state', async () => {
		const { getByRole } = render(RegenerateReportControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Regenerate August 2026' }));
		const yesBtn = getByRole('button', { name: 'Yes, regenerate' }) as HTMLButtonElement;
		await fireEvent.click(yesBtn);
		expect(yesBtn.getAttribute('aria-busy')).toBe('true');
	});
});
