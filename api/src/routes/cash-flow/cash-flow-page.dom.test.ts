// cash-flow-page.dom.test.ts — SELF-251 AC8: the two distinct empty states on
// cash-flow/+page.svelte, discriminated by `unclassified.count_ytd` off the SAME rollup payload
// AC9's banner/footnote already read. Mirrors the established
// allocation/us-equity/us-equity-page.dom.test.ts precedent (no +page.svelte DOM test convention
// existed before that file; this is the same @testing-library/svelte render() pattern applied to
// a second route component, not a new pattern).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import CashFlowPage from './+page.svelte';
import type { CashflowCrossAccountRollup } from '$lib/cashflow-rollup';

// Same merged-PageData discipline as us-equity-page.dom.test.ts: the root +layout.server.ts
// contributes fields this page's own +page.server.ts (which only adds `rollup`) doesn't itself
// produce, but svelte-check enforces the FULL merged PageData type at the component boundary.
const LAYOUT_DEFAULTS = {
	userEmail: null,
	pendingClassificationCount: 0,
	connectionHealth: { reauthCount: 0, institutionDownCount: 0 }
};

const EMPTY_ROLLUP: CashflowCrossAccountRollup = {
	as_of: '2026-08-27',
	sections: [
		{ cat: 'Revenue', sectionKey: 'income', label: 'Income', rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } },
		{ cat: 'Expense', sectionKey: 'expenses', label: 'Expenses', rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } }
	],
	targets: { income_target_annual: null, expense_target_monthly: null },
	unclassified: { count_ytd: 0 }
};

const POPULATED_ROLLUP: CashflowCrossAccountRollup = {
	...EMPTY_ROLLUP,
	sections: [
		{
			...EMPTY_ROLLUP.sections[0],
			rows: [{ sub_cat: 'Salary', month: 100, q1: 300, q2: 300, q3: null, q4: null, ytd: 600 }]
		},
		EMPTY_ROLLUP.sections[1]
	]
};

describe('cash-flow/+page.svelte — unavailable state', () => {
	it('renders an unavailable notice when rollup is null (load failure), never a fabricated empty table', () => {
		const { getByText, queryByRole } = render(CashFlowPage, {
			props: { data: { ...LAYOUT_DEFAULTS, rollup: null } }
		});
		expect(getByText(/temporarily unavailable/i)).toBeTruthy();
		expect(queryByRole('table')).toBeNull();
	});
});

describe('cash-flow/+page.svelte — AC8 zero-transaction empty state (count_ytd === 0, no rows)', () => {
	it('renders the onboarding CTA pair, not the classify CTA', () => {
		const { getByText, getByRole, queryByRole } = render(CashFlowPage, {
			props: { data: { ...LAYOUT_DEFAULTS, rollup: EMPTY_ROLLUP } }
		});
		expect(getByText('Add transactions via Onboarding to see your cash flow.')).toBeTruthy();
		expect(getByRole('link', { name: 'Connect an account' }).getAttribute('href')).toBe(
			'/accounts/connect'
		);
		expect(getByRole('link', { name: 'Add a manual account' }).getAttribute('href')).toBe(
			'/accounts/new'
		);
		expect(queryByRole('table')).toBeNull();
	});
});

describe('cash-flow/+page.svelte — AC8 zero-classified empty state (count_ytd > 0, no rows)', () => {
	it('renders the classify CTA, not the onboarding CTA pair', () => {
		const rollupWithQueue: CashflowCrossAccountRollup = {
			...EMPTY_ROLLUP,
			unclassified: { count_ytd: 3 }
		};
		const { getByText, getByRole, queryByRole } = render(CashFlowPage, {
			props: { data: { ...LAYOUT_DEFAULTS, rollup: rollupWithQueue } }
		});
		expect(getByText('Classify your transactions to see your cash flow.')).toBeTruthy();
		expect(getByRole('link', { name: 'Classify transactions' }).getAttribute('href')).toBe(
			'/accounts'
		);
		expect(queryByRole('link', { name: 'Connect an account' })).toBeNull();
		expect(queryByRole('table')).toBeNull();
	});
});

describe('cash-flow/+page.svelte — a real positive rollup always renders the table, outranking the empty-state heuristic', () => {
	it('renders the table when at least one section has rows, even with count_ytd === 0', () => {
		const { getAllByRole, queryByText } = render(CashFlowPage, {
			props: { data: { ...LAYOUT_DEFAULTS, rollup: POPULATED_ROLLUP } }
		});
		// Two <table> elements — one per section (Income + Expenses).
		expect(getAllByRole('table')).toHaveLength(2);
		expect(queryByText(/Add transactions via Onboarding/)).toBeNull();
	});
});
