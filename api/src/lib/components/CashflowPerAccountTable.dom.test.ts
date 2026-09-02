// CashflowPerAccountTable.dom.test.ts — SELF-254 verification battery for the §2.3.3 per-account
// cash-flow drill-down table's ratified ACs (2026-08-28).
//
// ENV: jsdom + @testing-library/svelte — mirrors CashflowRollupTable.dom.test.ts's own
// convention (this table's SELF-251 sibling). Query via the testing-library helpers, never
// `container.querySelector` for element lookup, except where a class-presence assertion has no
// accessible-role equivalent.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, within } from '@testing-library/svelte';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import CashflowPerAccountTable from './CashflowPerAccountTable.svelte';
import type { CashflowPerAccount, CashflowPerAccountSection } from '$lib/cashflow-per-account';

const NOTE =
	'Classifying a transfer does not by itself make it cancel out. A transfer with no matching journal entry resolves to Suspense, not a clean offset.';

function section(
	over: Partial<CashflowPerAccountSection> & {
		sectionKey: 'income' | 'other_cash_flows' | 'expenses';
	}
): CashflowPerAccountSection {
	const LABELS = { income: 'Income', other_cash_flows: 'Other Cash Flows', expenses: 'Expenses' };
	return {
		cats: [],
		rows: [],
		total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 },
		label: LABELS[over.sectionKey],
		...over
	};
}

const FIXTURE: CashflowPerAccount = {
	as_of: '2026-08-27',
	account_id: 42,
	sections: [
		section({
			sectionKey: 'income',
			cats: ['Revenue'],
			rows: [{ cat: 'Revenue', sub_cat: 'Salary', month: 5000, q1: 15000, q2: 15000, q3: null, q4: null, ytd: 30000 }],
			total: { month: 5000, q1: 15000, q2: 15000, q3: null, q4: null, ytd: 30000 }
		}),
		section({
			sectionKey: 'other_cash_flows',
			cats: ['Transfer', 'Equity'],
			rows: [
				{ cat: 'Transfer', sub_cat: 'Wire In', month: 500, q1: 500, q2: null, q3: null, q4: null, ytd: 500 },
				{ cat: 'Equity', sub_cat: 'Contribution', month: -200, q1: -200, q2: null, q3: null, q4: null, ytd: -200 }
			],
			total: { month: 300, q1: 300, q2: null, q3: null, q4: null, ytd: 300 }
		}),
		section({
			sectionKey: 'expenses',
			cats: ['Expense'],
			rows: [{ cat: 'Expense', sub_cat: 'Rent', month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }],
			total: { month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }
		})
	],
	unclassified: { count_ytd: 0 }
};

const BASE_PROPS = { staleness: EMPTY_STALENESS, classifyHref: '/accounts/42', otherCashFlowsNote: NOTE };

describe('CashflowPerAccountTable — AC1: three sections rendered Income, Other Cash Flows, Expenses in order', () => {
	it('renders all three captions in the ruled order', () => {
		const { getAllByRole } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const tables = getAllByRole('table');
		expect(tables).toHaveLength(3);
		expect(within(tables[0]).getByText('Income')).toBeTruthy();
		expect(within(tables[1]).getByText('Other Cash Flows')).toBeTruthy();
		expect(within(tables[2]).getByText('Expenses')).toBeTruthy();
	});

	it('no target caption is ever rendered (AC7 of cashflowPerAccount.ts — no targets key on this payload)', () => {
		const { queryByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		expect(queryByText(/Target/)).toBeNull();
	});
});

describe('CashflowPerAccountTable — AC2: flat Sub-Cat rows, no Cat-group headers, 6-column structure', () => {
	it('renders Month, Q1, Q2, Q3, Q4, YTD column headers in order on every section', () => {
		const { getAllByRole } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const tables = getAllByRole('table');
		for (const table of tables) {
			const headers = within(table).getAllByRole('columnheader').map((h) => h.textContent?.trim());
			expect(headers).toEqual(['Sub-Cat', 'Month', 'Q1', 'Q2', 'Q3', 'Q4', 'YTD']);
		}
	});

	it('the middle section renders Sub-Cat rows from BOTH classes flat, with no Cat column/label', () => {
		const { getByText, queryByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		expect(getByText('Wire In')).toBeTruthy();
		expect(getByText('Contribution')).toBeTruthy();
		expect(queryByText('Transfer')).toBeNull();
		expect(queryByText('Equity')).toBeNull();
	});

	it('the Month header and Month data cells carry the `.month` emphasis class', () => {
		const { getAllByRole, getByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const monthHeader = getAllByRole('columnheader', { name: 'Month' })[0];
		expect(monthHeader.classList.contains('month')).toBe(true);
		const salaryRow = getByText('Salary').closest('tr')!;
		const monthCell = within(salaryRow).getAllByRole('cell')[1];
		expect(monthCell.classList.contains('month')).toBe(true);
	});
});

describe('CashflowPerAccountTable — Total row sums DOWN each column only (rendered as-is, never re-summed)', () => {
	// QA INVERSION WATCHER (mirrors CashflowRollupTable.dom.test.ts's own documented battery):
	// a total that happens to equal the arithmetic sum of its rows cannot distinguish "renders
	// section.total as-is" from "silently re-sums section.rows". This fixture's total is
	// DELIBERATELY MISMATCHED from its row sum so a client re-sum regression renders the wrong
	// figure and reds here.
	it('a section total that does NOT equal the sum of its own rows still renders VERBATIM', () => {
		const mismatched: CashflowPerAccount = {
			...FIXTURE,
			sections: [
				section({
					sectionKey: 'income',
					cats: ['Revenue'],
					rows: [{ cat: 'Revenue', sub_cat: 'Salary', month: 100, q1: 100, q2: 100, q3: null, q4: null, ytd: 100 }],
					// Deliberately NOT the sum of the single row above (100).
					total: { month: 999, q1: 999, q2: 999, q3: null, q4: null, ytd: 999 }
				}),
				FIXTURE.sections[1],
				FIXTURE.sections[2]
			]
		};
		const { getAllByRole } = render(CashflowPerAccountTable, { props: { drilldown: mismatched, ...BASE_PROPS } });
		const totalRow = getAllByRole('row', { name: /Total/ })[0];
		const cells = within(totalRow).getAllByRole('cell');
		expect(cells[0].textContent).toContain('$999');
		expect(cells[5].textContent).toContain('$999');
	});

	it('a genuinely negative section total (other_cash_flows, no normal balance) renders its real sign', () => {
		const { getAllByRole } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const otherTotalRow = getAllByRole('row', { name: /Total/ })[1];
		const cells = within(otherTotalRow).getAllByRole('cell');
		expect(cells[0].textContent).toContain('$300');
	});
});

describe('CashflowPerAccountTable — the honest-transfer note (AC8 of cashflowSections.ts)', () => {
	it('renders the note verbatim, only inside the Other Cash Flows section', () => {
		const { getAllByRole, getByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const note = getByText(NOTE);
		expect(note).toBeTruthy();
		const otherTable = getAllByRole('table')[1];
		expect(within(otherTable).getByText(NOTE)).toBeTruthy();
		const incomeTable = getAllByRole('table')[0];
		expect(within(incomeTable).queryByText(NOTE)).toBeNull();
	});
});

describe('CashflowPerAccountTable — AC7: one-source unclassified banner + per-section footnote', () => {
	it('N = 0: neither the banner nor any footnote renders', () => {
		const { queryByRole, queryByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		expect(queryByRole('status')).toBeNull();
		expect(queryByText(/unclassified/)).toBeNull();
	});

	it('N > 0: the banner renders exact copy, ALL THREE section Total rows carry the footnote with the SAME N, and the CTA routes to the account-scoped classifyHref', () => {
		const withUnclassified: CashflowPerAccount = { ...FIXTURE, unclassified: { count_ytd: 5 } };
		const { getByRole, getAllByText } = render(CashflowPerAccountTable, {
			props: { drilldown: withUnclassified, ...BASE_PROPS }
		});
		const banner = getByRole('status');
		expect(within(banner).getByText('5 items unclassified')).toBeTruthy();
		const cta = within(banner).getByRole('link', { name: 'classify' });
		expect(cta.getAttribute('href')).toBe('/accounts/42');

		const footnotes = getAllByText('partial — 5 unclassified');
		expect(footnotes).toHaveLength(3);
	});

	// QA boundary leg (mirrors the SELF-251 precedent's own AC9 rows-present+unclassified test):
	// rows present AND count_ytd > 0 renders the tables (not an empty state), carrying the banner.
	it('rows present AND count_ytd > 0: renders all three tables with rows, plus the banner', () => {
		const withUnclassified: CashflowPerAccount = { ...FIXTURE, unclassified: { count_ytd: 2 } };
		const { getAllByRole, getByText } = render(CashflowPerAccountTable, {
			props: { drilldown: withUnclassified, ...BASE_PROPS }
		});
		expect(getAllByRole('table')).toHaveLength(3);
		expect(getByText('Salary')).toBeTruthy();
		expect(getByText('2 items unclassified')).toBeTruthy();
	});
});

describe('CashflowPerAccountTable — degenerate cell rendering: negative rows keep their real sign, never abs()d', () => {
	it('a negative Sub-Cat row cell renders signed', () => {
		const { getByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const rentRow = getByText('Rent').closest('tr')!;
		const cells = within(rentRow).getAllByRole('cell');
		expect(cells[1].textContent).toContain('-$2,000');
	});

	it('a not-yet-started quarter cell renders an em-dash, never "0"/"NaN"', () => {
		const { getByText } = render(CashflowPerAccountTable, { props: { drilldown: FIXTURE, ...BASE_PROPS } });
		const wireInRow = getByText('Wire In').closest('tr')!;
		const cells = within(wireInRow).getAllByRole('cell');
		expect(cells[3].textContent).toBe('—'); // q2
	});
});

describe('CashflowPerAccountTable — an unexpected section is rendered visibly, never dropped', () => {
	it('a section outside the 3-section contract is appended and rendered', () => {
		const withExtra: CashflowPerAccount = {
			...FIXTURE,
			sections: [
				...FIXTURE.sections,
				{
					sectionKey: 'income' as never,
					label: 'Mystery',
					cats: [],
					rows: [],
					total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 }
				}
			].map((s, i) => (i === 3 ? { ...s, sectionKey: 'bogus' as never } : s))
		};
		const { getByText } = render(CashflowPerAccountTable, { props: { drilldown: withExtra, ...BASE_PROPS } });
		expect(getByText('Mystery')).toBeTruthy();
	});
});

// SELF-258 AC3: section-level StaleConstituentBadge wiring, USER-WIDE per the team-lead ruling
// (see this component's own module header). The badge's OWN behavior is StaleConstituentBadge's
// own test suite's job — this suite only proves CashflowPerAccountTable threads its `staleness`
// prop to the badge correctly, once per section (Income, Other Cash Flows, Expenses).
describe('CashflowPerAccountTable — AC3/SELF-258: section-level StaleConstituentBadge wiring', () => {
	it('staleness: EMPTY_STALENESS renders no badge in any of the three sections', () => {
		const { container, queryByText } = render(CashflowPerAccountTable, {
			props: { drilldown: FIXTURE, ...BASE_PROPS }
		});
		expect(container.querySelectorAll('.stale-connection-marker')).toHaveLength(0);
		expect(queryByText('May be stale')).toBeNull();
	});

	it('a stale whole-tenant staleness prop renders the badge in ALL THREE section headers — same value, one read, USER-WIDE (not account-scoped)', () => {
		const stale = {
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '9',
					institution_name: 'Some Other Bank',
					provider: 'plaid',
					connection_status: 'revoked',
					status_class: null
				}
			]
		};
		const { container, getAllByRole } = render(CashflowPerAccountTable, {
			props: { drilldown: FIXTURE, ...BASE_PROPS, staleness: stale }
		});
		expect(container.querySelectorAll('.stale-connection-marker')).toHaveLength(3);
		expect(getAllByRole('table')).toHaveLength(3);
	});

	it('is_stale === null (unknown) renders the quieter "Staleness unknown" note, never the confirmed-stale tag, in all three sections', () => {
		const unknown = { is_stale: null, stale_items: [] };
		const { getAllByText, queryByText } = render(CashflowPerAccountTable, {
			props: { drilldown: FIXTURE, ...BASE_PROPS, staleness: unknown }
		});
		expect(getAllByText('Staleness unknown')).toHaveLength(3);
		expect(queryByText('May be stale')).toBeNull();
	});
});
