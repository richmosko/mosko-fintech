// CashflowRollupTable.dom.test.ts — SELF-251 verification battery for the §2.3.2.b cross-account
// cash-flow rollup table's ratified ACs (2026-08-27).
//
// ENV: jsdom + @testing-library/svelte — mirrors NonReAllocationTable.dom.test.ts's own
// convention. Query via the testing-library helpers, never `container.querySelector` for element
// lookup (this repo's own testing-library-container-queryselector-rune-error gotcha); `container`
// is used ONLY where a class-presence assertion has no accessible-role equivalent.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, within } from '@testing-library/svelte';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import CashflowRollupTable from './CashflowRollupTable.svelte';
import type { CashflowCrossAccountRollup, CashflowSection } from '$lib/cashflow-rollup';

function section(over: Partial<CashflowSection> & { cat: string; sectionKey: 'income' | 'expenses' }): CashflowSection {
	return {
		rows: [],
		total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 },
		label: over.sectionKey === 'income' ? 'Income' : 'Expenses',
		...over
	};
}

const FIXTURE: CashflowCrossAccountRollup = {
	as_of: '2026-08-27',
	sections: [
		section({
			cat: 'Revenue',
			sectionKey: 'income',
			rows: [
				{ sub_cat: 'Salary', month: 5000, q1: 15000, q2: 15000, q3: null, q4: null, ytd: 30000 },
				{ sub_cat: 'Interest', month: 10, q1: 30, q2: 30, q3: null, q4: null, ytd: 60 }
			],
			total: { month: 5010, q1: 15030, q2: 15030, q3: null, q4: null, ytd: 30060 }
		}),
		section({
			cat: 'Expense',
			sectionKey: 'expenses',
			rows: [
				{ sub_cat: 'Rent', month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }
			],
			total: { month: -2000, q1: -6000, q2: -6000, q3: null, q4: null, ytd: -12000 }
		})
	],
	targets: { income_target_annual: 60000, expense_target_monthly: 2200 },
	unclassified: { count_ytd: 0 }
};

describe('CashflowRollupTable — AC1: two sections rendered Income then Expenses', () => {
	it('renders Income before Expenses as table captions, nothing else', () => {
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const tables = getAllByRole('table');
		expect(tables).toHaveLength(2);
		expect(within(tables[0]).getByText('Income')).toBeTruthy();
		expect(within(tables[1]).getByText('Expenses')).toBeTruthy();
	});
});

describe('CashflowRollupTable — AC2: section header caption + NULL-target suppression', () => {
	it('renders the target caption when a target is set', () => {
		const { getByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		expect(getByText('Target $60,000/yr')).toBeTruthy();
		expect(getByText('Target $2,200/mo')).toBeTruthy();
	});

	it('renders NO caption at all when a target is NULL (never a placeholder)', () => {
		const nullTargets: CashflowCrossAccountRollup = {
			...FIXTURE,
			targets: { income_target_annual: null, expense_target_monthly: null }
		};
		const { queryByText } = render(CashflowRollupTable, { props: { rollup: nullTargets, staleness: EMPTY_STALENESS } });
		expect(queryByText(/Target/)).toBeNull();
	});

	it('a stored $0 target still renders a caption (NULL, not zero, suppresses it)', () => {
		const zeroTarget: CashflowCrossAccountRollup = {
			...FIXTURE,
			targets: { income_target_annual: 0, expense_target_monthly: null }
		};
		const { getByText, queryByText } = render(CashflowRollupTable, { props: { rollup: zeroTarget, staleness: EMPTY_STALENESS } });
		expect(getByText('Target $0/yr')).toBeTruthy();
		expect(queryByText(/\/mo/)).toBeNull();
	});
});

describe('CashflowRollupTable — AC3: flat Sub-Cat rows, no Cat-group headers/subtotals', () => {
	it('renders exactly one header row (columnheader group) per section — no colgroup/group-header row', () => {
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		// 7 columns × 2 sections = 14 columnheaders; no extra colspanned group-header row exists.
		expect(getAllByRole('columnheader')).toHaveLength(14);
	});

	it('Sub-Cat rows render directly, no wrapping group row', () => {
		const { getByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		expect(getByText('Salary')).toBeTruthy();
		expect(getByText('Rent')).toBeTruthy();
	});
});

describe('CashflowRollupTable — AC4: six period columns, Month visually emphasized', () => {
	it('renders Month, Q1, Q2, Q3, Q4, YTD column headers in order', () => {
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const table = getAllByRole('table')[0];
		const headers = within(table).getAllByRole('columnheader').map((h) => h.textContent?.trim());
		expect(headers).toEqual(['Sub-Cat', 'Month', 'Q1', 'Q2', 'Q3', 'Q4', 'YTD']);
	});

	it('the Month header and Month data cells carry the `.month` emphasis class', () => {
		const { getAllByRole, getByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const monthHeader = getAllByRole('columnheader', { name: 'Month' })[0];
		expect(monthHeader.classList.contains('month')).toBe(true);

		const salaryRow = getByText('Salary').closest('tr')!;
		const monthCell = within(salaryRow).getAllByRole('cell')[1];
		expect(monthCell.classList.contains('month')).toBe(true);
	});
});

describe('CashflowRollupTable — AC5: Total row sums DOWN each column only (rendered as-is, never re-summed)', () => {
	it('the Total row for Income renders the server-supplied total, not a client re-sum', () => {
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const totalRow = getAllByRole('row', { name: /Total/ })[0];
		const cells = within(totalRow).getAllByRole('cell');
		// [Month, Q1, Q2, Q3, Q4, YTD]
		expect(cells[0].textContent).toContain('$5,010');
		expect(cells[5].textContent).toContain('$30,060');
	});

	// QA INVERSION WATCHER: FIXTURE's total happens to equal the arithmetic sum of its own rows
	// (5000+10=5010, 30000+60=30060), so the assertion above cannot distinguish "renders
	// section.total as-is" from "silently re-sums section.rows" — a client-resum regression
	// (`section.rows.reduce((a,r) => a + r.month, 0)` swapped in for `section.total.month`) still
	// passes it. Confirmed live: mutating the component to resum month/ytd from `rows` left the
	// test above green. This fixture's total is DELIBERATELY MISMATCHED from its row sum (rows
	// sum to 100, `total.month` is a distinct 999) so a resum regression renders the wrong figure
	// and reds here.
	it('a section total that does NOT equal the sum of its own rows still renders VERBATIM — proves no client re-sum path exists', () => {
		const mismatched: CashflowCrossAccountRollup = {
			...FIXTURE,
			sections: [
				section({
					cat: 'Revenue',
					sectionKey: 'income',
					rows: [{ sub_cat: 'Salary', month: 100, q1: 100, q2: 100, q3: null, q4: null, ytd: 100 }],
					// Deliberately NOT the sum of the single row above (100) — a real server payload
					// never disagrees with its own rows this way; the mismatch exists only to make a
					// re-sum regression observable.
					total: { month: 999, q1: 999, q2: 999, q3: null, q4: null, ytd: 999 }
				})
			]
		};
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: mismatched, staleness: EMPTY_STALENESS } });
		const totalRow = getAllByRole('row', { name: /Total/ })[0];
		const cells = within(totalRow).getAllByRole('cell');
		expect(cells[0].textContent).toContain('$999');
		expect(cells[5].textContent).toContain('$999');
	});
});

describe('CashflowRollupTable — AC6: no delta/color-coding, static rendering only', () => {
	it('no cell anywhere carries a .pos or .neg class', () => {
		const { container } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		expect(container.querySelectorAll('.pos').length).toBe(0);
		expect(container.querySelectorAll('.neg').length).toBe(0);
	});
});

describe('CashflowRollupTable — AC7: Edit cash-flow targets routes to /settings/cash-flow-targets', () => {
	it('is a plain navigation link, not a form/button', () => {
		const { getByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const link = getByRole('link', { name: 'Edit cash-flow targets' });
		expect(link.tagName).toBe('A');
		expect(link.getAttribute('href')).toBe('/settings/cash-flow-targets');
	});
});

describe('CashflowRollupTable — AC8: degenerate cell rendering', () => {
	it('a null quarter cell renders an em-dash, never "0"/"NaN"', () => {
		const { getByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const salaryRow = getByText('Salary').closest('tr')!;
		// A data row's label is a plain <td> (also role "cell"), so the array is
		// [label, Month, Q1, Q2, Q3, Q4, YTD] — mirrors NonReAllocationTable.dom.test.ts's own
		// documented shift for exactly this reason.
		const cells = within(salaryRow).getAllByRole('cell');
		expect(cells[4].textContent).toBe('—');
		expect(cells[5].textContent).toBe('—');
	});
});

describe('CashflowRollupTable — AC9: one-source unclassified banner + per-section footnote', () => {
	it('N = 0: neither the banner nor any footnote renders', () => {
		const { queryByRole, queryByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		expect(queryByRole('status')).toBeNull();
		expect(queryByText(/unclassified/)).toBeNull();
	});

	it('N > 0: the banner renders exact copy, and BOTH section Total rows carry the footnote with the SAME N', () => {
		const withUnclassified: CashflowCrossAccountRollup = {
			...FIXTURE,
			unclassified: { count_ytd: 7 }
		};
		const { getByRole, getAllByText } = render(CashflowRollupTable, {
			props: { rollup: withUnclassified, staleness: EMPTY_STALENESS }
		});
		const banner = getByRole('status');
		expect(within(banner).getByText('7 items unclassified')).toBeTruthy();
		const cta = within(banner).getByRole('link', { name: 'classify' });
		expect(cta.getAttribute('href')).toBe('/accounts');

		const footnotes = getAllByText('partial — 7 unclassified');
		expect(footnotes).toHaveLength(2);
	});

	it('classifyHref prop overrides the CTA target', () => {
		const withUnclassified: CashflowCrossAccountRollup = {
			...FIXTURE,
			unclassified: { count_ytd: 1 }
		};
		const { getByRole } = render(CashflowRollupTable, {
			props: { rollup: withUnclassified, staleness: EMPTY_STALENESS, classifyHref: '/some-queue' }
		});
		expect(getByRole('link', { name: 'classify' }).getAttribute('href')).toBe('/some-queue');
	});
});

describe('CashflowRollupTable — AC10: negative totals render with their real sign', () => {
	it('a negative section total renders with a leading minus, never abs()d or hidden', () => {
		const { getAllByRole } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const expensesTotalRow = getAllByRole('row', { name: /Total/ })[1];
		const cells = within(expensesTotalRow).getAllByRole('cell');
		expect(cells[0].textContent).toContain('-$2,000');
		expect(cells[5].textContent).toContain('-$12,000');
	});

	it('a negative Sub-Cat row cell also renders signed', () => {
		const { getByText } = render(CashflowRollupTable, { props: { rollup: FIXTURE, staleness: EMPTY_STALENESS } });
		const rentRow = getByText('Rent').closest('tr')!;
		// [label, Month, Q1, ...] — same label-is-a-<td> shift as the AC8 test above.
		const cells = within(rentRow).getAllByRole('cell');
		expect(cells[1].textContent).toContain('-$2,000');
	});
});

describe('CashflowRollupTable — AC1 defensive completeness: an unexpected section is rendered visibly, never dropped', () => {
	it('a section outside the Income/Expenses contract is appended and rendered', () => {
		const withExtra: CashflowCrossAccountRollup = {
			...FIXTURE,
			sections: [
				...FIXTURE.sections,
				{
					cat: 'Transfer',
					sectionKey: 'other_cash_flows',
					label: 'Other Cash Flows',
					rows: [],
					total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 }
				}
			]
		};
		const { getByText } = render(CashflowRollupTable, { props: { rollup: withExtra, staleness: EMPTY_STALENESS } });
		expect(getByText('Other Cash Flows')).toBeTruthy();
	});
});

// SELF-258 AC1: section-level StaleConstituentBadge wiring. The badge's OWN behavior (disclosure,
// tri-state, tooltip content, Re-authenticate link) is StaleConstituentBadge's own test suite's
// job (StaleConstituentBadge.dom.test.ts) — this suite only proves CashflowRollupTable threads its
// `staleness` prop to the badge correctly, once per section, and nowhere re-derives it.
describe('CashflowRollupTable — AC1/SELF-258: section-level StaleConstituentBadge wiring', () => {
	it('staleness: EMPTY_STALENESS renders no badge in either section', () => {
		const { container, queryByText } = render(CashflowRollupTable, {
			props: { rollup: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(container.querySelectorAll('.stale-connection-marker')).toHaveLength(0);
		expect(queryByText('May be stale')).toBeNull();
	});

	it('a stale whole-tenant staleness prop renders the badge in BOTH section headers (Income and Expenses) — same value, one read', () => {
		const stale = {
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '1',
					institution_name: 'Bank 1',
					provider: 'plaid',
					connection_status: 'login_required',
					status_class: null
				}
			]
		};
		const { container, getAllByRole } = render(CashflowRollupTable, {
			props: { rollup: FIXTURE, staleness: stale }
		});
		// One marker per section table (Income, Expenses) — both fed by the SAME `stale` value.
		expect(container.querySelectorAll('.stale-connection-marker')).toHaveLength(2);
		expect(getAllByRole('table')).toHaveLength(2);
	});

	it('is_stale === null (unknown) renders the quieter "Staleness unknown" note, never the confirmed-stale tag, in both sections', () => {
		const unknown = { is_stale: null, stale_items: [] };
		const { getAllByText, queryByText } = render(CashflowRollupTable, {
			props: { rollup: FIXTURE, staleness: unknown }
		});
		expect(getAllByText('Staleness unknown')).toHaveLength(2);
		expect(queryByText('May be stale')).toBeNull();
	});
});
