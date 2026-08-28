// CashflowAsOfToggle.dom.test.ts — SELF-254 AC4 coverage for the as-of toolbar widget: native
// min/max wiring, the client Zod mirror blocking an out-of-range navigation, and that a valid
// change preserves every OTHER existing query param (AC5's `from` marker included).
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach, type Mock } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import CashflowAsOfToggle from './CashflowAsOfToggle.svelte';
// TYPE vs RUNTIME SPLIT (NavHistoryChart.dom.test.ts's own documented idiom): svelte-check types
// `goto`/`page.url` against SvelteKit's real ambient declarations, which know nothing of the
// vitest alias (vitest.config.ts) that resolves both to the plain test stubs at runtime. Cast
// once, here.
import { goto as gotoImport } from '$app/navigation';
import { page } from '$app/state';
const goto = gotoImport as unknown as Mock;
function setPageUrl(url: string): void {
	(page as unknown as { url: URL }).url = new URL(url);
}

const FLOOR = '2015-12-01';
const MAX = '2026-08-27';

beforeEach(() => {
	goto.mockClear();
	setPageUrl('http://localhost/cash-flow/42');
});

describe('CashflowAsOfToggle — native bounds', () => {
	it('renders the date input with min/max set to floor/max', () => {
		const { getByLabelText } = render(CashflowAsOfToggle, {
			props: { value: MAX, floor: FLOOR, max: MAX }
		});
		const input = getByLabelText('As of') as HTMLInputElement;
		expect(input.min).toBe(FLOOR);
		expect(input.max).toBe(MAX);
	});
});

describe('CashflowAsOfToggle — AC4: client mirror blocks an out-of-range value before navigating', () => {
	it('a future-dated value shows an inline error and calls goto ZERO times', async () => {
		const { getByLabelText, getByRole } = render(CashflowAsOfToggle, {
			props: { value: MAX, floor: FLOOR, max: MAX }
		});
		const input = getByLabelText('As of') as HTMLInputElement;
		await fireEvent.change(input, { target: { value: '2026-09-01' } });
		expect(getByRole('alert')).toBeTruthy();
		expect(goto).not.toHaveBeenCalled();
	});

	it('a below-floor value shows an inline error and calls goto ZERO times', async () => {
		const { getByLabelText, getByRole } = render(CashflowAsOfToggle, {
			props: { value: MAX, floor: FLOOR, max: MAX }
		});
		const input = getByLabelText('As of') as HTMLInputElement;
		await fireEvent.change(input, { target: { value: '2015-11-30' } });
		expect(getByRole('alert')).toBeTruthy();
		expect(goto).not.toHaveBeenCalled();
	});
});

describe('CashflowAsOfToggle — a valid change navigates once, preserving other params (AC5 from marker)', () => {
	it('sets ?as_of= on the current URL and preserves an existing ?from= param', async () => {
		setPageUrl('http://localhost/cash-flow/42?from=cross-account-rollup');
		const { getByLabelText } = render(CashflowAsOfToggle, {
			props: { value: MAX, floor: FLOOR, max: MAX }
		});
		const input = getByLabelText('As of') as HTMLInputElement;
		await fireEvent.change(input, { target: { value: '2026-06-01' } });
		expect(goto).toHaveBeenCalledTimes(1);
		const [calledUrl] = goto.mock.calls[0];
		const url = new URL(String(calledUrl));
		expect(url.searchParams.get('as_of')).toBe('2026-06-01');
		expect(url.searchParams.get('from')).toBe('cross-account-rollup');
	});
});

describe('CashflowAsOfToggle — serverError renders when present and no local edit has occurred', () => {
	it('shows the server-supplied message inline', () => {
		const { getByRole } = render(CashflowAsOfToggle, {
			props: { value: MAX, floor: FLOOR, max: MAX, serverError: 'Date cannot be in the future.' }
		});
		expect(getByRole('alert').textContent).toContain('Date cannot be in the future.');
	});
});
