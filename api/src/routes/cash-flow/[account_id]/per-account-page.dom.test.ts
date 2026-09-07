// per-account-page.dom.test.ts — SELF-254 AC3/AC4/AC5/AC6/AC8 coverage for
// cash-flow/[account_id]/+page.svelte. Mirrors cash-flow/cash-flow-page.dom.test.ts's own
// @testing-library/svelte render() precedent (SELF-251), applied to this route.
//
// @vitest-environment jsdom

import { describe, it, expect, beforeEach } from 'vitest';
import { render } from '@testing-library/svelte';
import CashFlowAccountPage from './+page.svelte';
import { page } from '$app/state';
import type { CashflowPerAccount } from '$lib/cashflow-per-account';
import type { PageData } from './$types';

// TYPE vs RUNTIME SPLIT (same idiom as NavHistoryChart.dom.test.ts's own `setPageUrl` /
// `goto` casts): svelte-check types `page.params`/`page.url.pathname` against SvelteKit's real
// route-manifest-derived literals, and `PageData.maxAsOf` against the unconstructable branded
// `ZoneResolvedAsOf` (asOf.ts — a server-only factory this browser-context test file must not
// import, even for a test-only cast). The runtime stub (tests/stubs/app-state.ts) and this
// fixture's plain string are both correct at RUNTIME; casting once here, rather than fighting
// svelte-check, matches that file's own documented precedent.
function setPageUrl(url: string): void {
	(page as unknown as { url: URL }).url = new URL(url);
}
function setPageParams(params: Record<string, string>): void {
	(page as unknown as { params: Record<string, string> }).params = params;
}

// Same merged-PageData discipline as cash-flow-page.dom.test.ts: the root +layout.server.ts
// contributes fields this page's own +page.server.ts doesn't itself produce.
const LAYOUT_DEFAULTS = {
	userEmail: null,
	pendingClassificationCount: 0,
	pendingMonthlyReportCount: 0,
	connectionHealth: { reauthCount: 0, institutionDownCount: 0 }
};

const NOTE = 'Classifying a transfer does not by itself make it cancel out.';

const EMPTY_DRILLDOWN: CashflowPerAccount = {
	as_of: '2026-08-27',
	account_id: 42,
	sections: [
		{ sectionKey: 'income', label: 'Income', cats: ['Revenue'], rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } },
		{ sectionKey: 'other_cash_flows', label: 'Other Cash Flows', cats: ['Transfer', 'Equity'], rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } },
		{ sectionKey: 'expenses', label: 'Expenses', cats: ['Expense'], rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } }
	],
	unclassified: { count_ytd: 0 }
};

const POPULATED_DRILLDOWN: CashflowPerAccount = {
	...EMPTY_DRILLDOWN,
	sections: [
		{
			...EMPTY_DRILLDOWN.sections[0],
			rows: [{ cat: 'Revenue', sub_cat: 'Salary', month: 100, q1: 300, q2: 300, q3: null, q4: null, ytd: 600 }]
		},
		EMPTY_DRILLDOWN.sections[1],
		EMPTY_DRILLDOWN.sections[2]
	]
};

const ACCOUNTS = [
	{ account_id: 42, name: 'Everyday Checking', closed_at: null },
	{ account_id: 7, name: 'Old 401k', closed_at: '2025-03-10T00:00:00Z' }
];

function baseData(over: Partial<Record<string, unknown>> = {}): PageData {
	return {
		...LAYOUT_DEFAULTS,
		drilldown: EMPTY_DRILLDOWN,
		asOfError: null,
		accounts: ACCOUNTS,
		maxAsOf: '2026-08-27',
		asOfFloor: '2015-12-01',
		otherCashFlowsNote: NOTE,
		...over
	} as unknown as PageData;
}

beforeEach(() => {
	setPageParams({ account_id: '42' });
	setPageUrl('http://localhost/cash-flow/42');
});

describe('cash-flow/[account_id]/+page.svelte — unavailable state', () => {
	it('renders an unavailable notice when drilldown is null and there is no asOfError', () => {
		const { getByText, queryByRole } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: null }) }
		});
		expect(getByText(/temporarily unavailable/i)).toBeTruthy();
		expect(queryByRole('table')).toBeNull();
	});
});

describe('cash-flow/[account_id]/+page.svelte — AC4 item 3: as-of validation failure renders a sane inline error, not a crash', () => {
	it('renders the field error message, not the generic unavailable notice, and no table', () => {
		const { container, queryByText, queryByRole } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: null, asOfError: 'Date cannot be in the future.' }) }
		});
		// The message renders TWICE by design — once inline on the toggle's own field (its
		// existing error-rendering convention) and once as the page-level banner (there is no
		// cashflow data to render underneath, so the toggle's inline copy alone would be easy to
		// miss) — scoped to `.page-error` (a class-presence check with no accessible-role
		// equivalent that distinguishes it from the toggle's own field-level alert).
		const banner = container.querySelector('.page-error');
		expect(banner?.textContent).toContain('Date cannot be in the future.');
		expect(queryByText(/temporarily unavailable/i)).toBeNull();
		expect(queryByRole('table')).toBeNull();
	});
});

describe('cash-flow/[account_id]/+page.svelte — AC8: the one empty-state message', () => {
	it('rows empty AND count_ytd === 0 renders "No transactions in [year] for this account."', () => {
		const { getByText, queryByRole } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: EMPTY_DRILLDOWN }) }
		});
		expect(getByText('No transactions in 2026 for this account.')).toBeTruthy();
		expect(queryByRole('table')).toBeNull();
	});

	it('rows empty BUT count_ytd > 0 renders the (empty) tables + banner instead of the AC8 message', () => {
		const withQueue: CashflowPerAccount = { ...EMPTY_DRILLDOWN, unclassified: { count_ytd: 3 } };
		const { queryByText, getAllByRole, getByText } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: withQueue }) }
		});
		expect(queryByText(/No transactions in/)).toBeNull();
		expect(getAllByRole('table')).toHaveLength(3);
		expect(getByText('3 items unclassified')).toBeTruthy();
	});

	it('a real positive drilldown always renders the tables, outranking the empty-state heuristic', () => {
		const { getAllByRole, queryByText } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: POPULATED_DRILLDOWN }) }
		});
		expect(getAllByRole('table')).toHaveLength(3);
		expect(queryByText(/No transactions in/)).toBeNull();
	});
});

describe('cash-flow/[account_id]/+page.svelte — AC3: the Closed badge', () => {
	// Scoped to `.status.closed` (a class-presence check with no accessible-role equivalent that
	// distinguishes it from the account picker's own closed-group OPTION, which also carries the
	// word "Closed" in its label text — this repo's own documented `container`-query exception).
	it('renders the header pill with the closure date, UTC-formatted, for a closed account', () => {
		setPageParams({ account_id: '7' });
		const { container, getByText } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: { ...EMPTY_DRILLDOWN, account_id: 7 } }) }
		});
		const badge = container.querySelector('.status.closed');
		expect(badge?.textContent).toBe('Closed Mar 10, 2025');
		expect(getByText('Old 401k')).toBeTruthy();
	});

	it('an open account renders no Closed badge (the picker may still list OTHER closed accounts)', () => {
		const { container } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: EMPTY_DRILLDOWN }) }
		});
		expect(container.querySelector('.status.closed')).toBeNull();
	});
});

describe('cash-flow/[account_id]/+page.svelte — AC5: drill-from back-nav', () => {
	it('renders NO back-link when `from` is absent', () => {
		const { queryByRole } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: POPULATED_DRILLDOWN }) }
		});
		expect(queryByRole('link', { name: /Back to Cash Flow/ })).toBeNull();
	});

	it('renders a back-link to /cash-flow when ?from=cross-account-rollup is present', () => {
		setPageUrl('http://localhost/cash-flow/42?from=cross-account-rollup');
		const { getByRole } = render(CashFlowAccountPage, {
			props: { data: baseData({ drilldown: POPULATED_DRILLDOWN }) }
		});
		const link = getByRole('link', { name: /Back to Cash Flow/ });
		expect(link.getAttribute('href')).toBe('/cash-flow');
	});
});
