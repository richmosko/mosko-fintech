// CashflowAccountPicker.dom.test.ts — SELF-254 AC3/AC5 coverage for the account selector: the
// Open/Closed grouping, the current-account selection, and — QA gap flagged after the SELF-254
// hand-off — a watcher on the param-preservation claim in the component's own header ("Every
// OTHER existing query param (`as_of`, `from`) is preserved — only the path segment changes").
// That claim was true but unwatched; mirrors CashflowAsOfToggle.dom.test.ts's own
// param-preservation battery, applied to the account-switch path instead of the as-of path.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach, type Mock } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import CashflowAccountPicker from './CashflowAccountPicker.svelte';
// TYPE vs RUNTIME SPLIT (NavHistoryChart.dom.test.ts's own documented idiom, also used by
// CashflowAsOfToggle.dom.test.ts): svelte-check types `goto`/`page.url` against SvelteKit's real
// ambient declarations, which know nothing of the vitest alias (vitest.config.ts) that resolves
// both to the plain test stubs at runtime. Cast once, here.
import { goto as gotoImport } from '$app/navigation';
import { page } from '$app/state';
const goto = gotoImport as unknown as Mock;
function setPageUrl(url: string): void {
	(page as unknown as { url: URL }).url = new URL(url);
}

const ACCOUNTS = [
	{ account_id: 42, name: 'Everyday Checking', closed_at: null },
	{ account_id: 7, name: 'Old 401k', closed_at: '2025-03-10T00:00:00Z' },
	{ account_id: 9, name: 'Side Fund', closed_at: null }
];

beforeEach(() => {
	goto.mockClear();
	setPageUrl('http://localhost/cash-flow/42');
});

describe('CashflowAccountPicker — AC3: Open/Closed grouping', () => {
	it('renders an Open optgroup and a Closed optgroup, with the closed option carrying its closure date', () => {
		const { getByRole, getAllByRole } = render(CashflowAccountPicker, {
			props: { accounts: ACCOUNTS, currentAccountId: 42 }
		});
		const select = getByRole('combobox', { name: 'Account' }) as HTMLSelectElement;
		const groups = select.querySelectorAll('optgroup');
		expect(Array.from(groups).map((g) => g.getAttribute('label'))).toEqual(['Open', 'Closed']);

		const options = getAllByRole('option').map((o) => o.textContent);
		expect(options).toContain('Everyday Checking');
		expect(options).toContain('Side Fund');
		expect(options).toContain('Old 401k — Closed Mar 10, 2025');
	});

	it('omits an empty group entirely (no bare "Closed" optgroup when nothing is closed)', () => {
		const allOpen = ACCOUNTS.filter((a) => a.closed_at === null);
		const { getByRole } = render(CashflowAccountPicker, {
			props: { accounts: allOpen, currentAccountId: 42 }
		});
		const select = getByRole('combobox', { name: 'Account' }) as HTMLSelectElement;
		const groups = select.querySelectorAll('optgroup');
		expect(Array.from(groups).map((g) => g.getAttribute('label'))).toEqual(['Open']);
	});
});

describe('CashflowAccountPicker — current account is selected', () => {
	it('the select value matches currentAccountId on mount', () => {
		const { getByRole } = render(CashflowAccountPicker, {
			props: { accounts: ACCOUNTS, currentAccountId: 7 }
		});
		const select = getByRole('combobox', { name: 'Account' }) as HTMLSelectElement;
		expect(select.value).toBe('7');
	});
});

describe('CashflowAccountPicker — AC3/AC5: switching accounts navigates once, preserving ?as_of= and ?from=', () => {
	it('changes only the path segment; every other existing query param survives verbatim', async () => {
		setPageUrl('http://localhost/cash-flow/42?as_of=2026-06-01&from=cross-account-rollup');
		const { getByRole } = render(CashflowAccountPicker, {
			props: { accounts: ACCOUNTS, currentAccountId: 42 }
		});
		const select = getByRole('combobox', { name: 'Account' }) as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '9' } });

		expect(goto).toHaveBeenCalledTimes(1);
		const [calledUrl] = goto.mock.calls[0];
		const url = new URL(String(calledUrl));
		expect(url.pathname).toBe('/cash-flow/9');
		expect(url.searchParams.get('as_of')).toBe('2026-06-01');
		expect(url.searchParams.get('from')).toBe('cross-account-rollup');
	});

	it('selecting the ALREADY-current account is a no-op — no navigation fires', async () => {
		const { getByRole } = render(CashflowAccountPicker, {
			props: { accounts: ACCOUNTS, currentAccountId: 42 }
		});
		const select = getByRole('combobox', { name: 'Account' }) as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: '42' } });
		expect(goto).not.toHaveBeenCalled();
	});
});
