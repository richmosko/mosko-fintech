// SkipFinalizeControl.dom.test.ts — SELF-356 / P4 AC1/AC3/AC5. Mirrors
// RegenerateReportControl.dom.test.ts's own convention (SELF-357) for the identical inline
// two-step confirm shape. Covers:
//   - the inline two-step disclosure (never window.confirm()): "Skip commentary and finalize"
//     reveals a confirm row; Cancel hides it again without posting anything.
//   - AC3's confirm copy, verbatim, interpolating the target month's label.
//   - the confirm form's hidden target_month field carries the targetMonth prop.
//   - clicking "Yes, finalize" enters the loading state (synchronous half of the use:enhance
//     SubmitFunction, under tests/stubs/app-forms.ts's real-submit-event stub).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import SkipFinalizeControl from './SkipFinalizeControl.svelte';

const PROPS = { targetMonth: '2026-08-01', monthLabel: 'August 2026' };

describe('SkipFinalizeControl — inline confirm, not window.confirm()', () => {
	it('shows only the "Skip commentary and finalize" link-button initially; no confirm row, nothing posted', () => {
		const { getByRole, queryByText } = render(SkipFinalizeControl, { props: PROPS });
		expect(getByRole('button', { name: 'Skip commentary and finalize August 2026' })).toBeTruthy();
		expect(queryByText(/will show its four headings/)).toBeNull();
	});

	it('clicking the CTA reveals the confirm row with AC3\'s verbatim copy', async () => {
		const { getByRole, getByText } = render(SkipFinalizeControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Skip commentary and finalize August 2026' }));
		expect(
			getByText(
				'Finalize August 2026 without commentary? The Rebalancing Targets section will show its four headings with empty bodies. You can regenerate this month later.'
			)
		).toBeTruthy();
		expect(getByRole('button', { name: 'Yes, finalize' })).toBeTruthy();
	});

	it('Cancel hides the confirm row again without posting', async () => {
		const { getByRole, queryByText, getByText } = render(SkipFinalizeControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Skip commentary and finalize August 2026' }));
		await fireEvent.click(getByRole('button', { name: 'Cancel' }));
		expect(queryByText(/will show its four headings/)).toBeNull();
		expect(getByText('Skip commentary and finalize')).toBeTruthy();
	});

	it('the confirm form carries the target month as a hidden field', async () => {
		const { getByRole, container } = render(SkipFinalizeControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Skip commentary and finalize August 2026' }));
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('target_month')).toBe('2026-08-01');
	});

	it('clicking "Yes, finalize" enters the loading state', async () => {
		const { getByRole } = render(SkipFinalizeControl, { props: PROPS });
		await fireEvent.click(getByRole('button', { name: 'Skip commentary and finalize August 2026' }));
		const yesBtn = getByRole('button', { name: 'Yes, finalize' }) as HTMLButtonElement;
		await fireEvent.click(yesBtn);
		expect(yesBtn.getAttribute('aria-busy')).toBe('true');
	});
});
