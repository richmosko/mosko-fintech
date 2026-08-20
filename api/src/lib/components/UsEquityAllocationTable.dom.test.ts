// UsEquityAllocationTable.dom.test.ts — SELF-241 verification battery for the §2.2.3 US Equity
// sub-allocation table's ACs (2026-08-20).
//
// ENV: jsdom (per-file pragma) + @testing-library/svelte. Query via the testing-library helpers,
// never `container.querySelector` for element lookup — see this repo's own
// testing-library-container-queryselector-rune-error gotcha; `container` is used ONLY where a
// class-presence assertion has no accessible-role equivalent, matching
// NonReAllocationTable.dom.test.ts's own precedent.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, within } from '@testing-library/svelte';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import UsEquityAllocationTable from './UsEquityAllocationTable.svelte';
import { US_EQUITY_SUB_CATS } from '$lib/allocation-taxonomy';
import type { UsEquityAllocation, UsEquityRow } from '$lib/us-equity-allocation';

function row(over: Partial<UsEquityRow> & { sub_cat: string }): UsEquityRow {
	return {
		sub_cat_id: null,
		cat: 'Marketable Securities',
		pct_target: 0,
		pct_alloc: 0,
		dollar_target: 0,
		dollar_alloc: 0,
		dollar_realloc: 0,
		...over
	};
}

// A populated, non-degenerate fixture — all twelve canonical rows, one zero-alloc/zero-target row
// (US-02), the rest holding something.
const ROWS: UsEquityRow[] = US_EQUITY_SUB_CATS.map((sub_cat, i) =>
	row({
		sub_cat_id: i + 1,
		sub_cat,
		pct_target: sub_cat === 'US-02-Telecom' ? 0 : 5,
		pct_alloc: sub_cat === 'US-02-Telecom' ? 0 : 8.33,
		dollar_target: sub_cat === 'US-02-Telecom' ? 0 : 500,
		dollar_alloc: sub_cat === 'US-02-Telecom' ? 0 : 833,
		dollar_realloc: sub_cat === 'US-02-Telecom' ? 0 : -333
	})
);

const FIXTURE: UsEquityAllocation = {
	rows: ROWS,
	total: {
		dollar_alloc: ROWS.reduce((s, r) => s + r.dollar_alloc, 0),
		pct_alloc: 100,
		pct_target: 100,
		dollar_target: ROWS.reduce((s, r) => s + (r.dollar_target ?? 0), 0),
		dollar_realloc: 0
	}
};

describe('UsEquityAllocationTable — AC1: exactly twelve rows, canonical order', () => {
	it('renders all twelve Sub-Cat labels in US_EQUITY_SUB_CATS order', () => {
		const { getAllByRole } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		// Data rows have 6 `cell`-role tds (label + 5 value columns); the header row has 0 (all
		// `columnheader`) and the foot row has 5 (its label is a `rowheader` th, not a `cell`) —
		// filtering on exactly 6 isolates the twelve data rows from both.
		const rows = getAllByRole('row').filter((r) => within(r).queryAllByRole('cell').length === 6);
		expect(rows).toHaveLength(12);
		// The label cell also carries the dormant per-row staleness marker text (AC7 — no
		// per-row producer yet, so every row defaults to "Staleness unknown"); strip it to isolate
		// the Sub-Cat label itself.
		const labels = rows.map((r) =>
			within(r).getAllByRole('cell')[0].textContent?.replace('Staleness unknown', '').trim()
		);
		expect(labels).toEqual(US_EQUITY_SUB_CATS);
	});
});

describe('UsEquityAllocationTable — AC2: five columns in PRD order', () => {
	it('the header row is Sub-Cat | % Target | % Alloc | $ Target | $ Alloc | $ ReAlloc', () => {
		const { getAllByRole } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const headers = getAllByRole('columnheader').map((h) => h.textContent?.trim());
		expect(headers).toEqual(['Sub-Cat', '% Target', '% Alloc', '$ Target', '$ Alloc', '$ ReAlloc']);
	});
});

describe('UsEquityAllocationTable — AC3: Total US Equity foot row = drill-down-identity anchor', () => {
	it('the foot $Alloc cell renders allocation.total.dollar_alloc directly, with a parent-row cross-reference', () => {
		const { getByRole } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const footRow = getByRole('row', { name: /Total US Equity/ });
		const cells = within(footRow).getAllByRole('cell');
		expect(cells[3].textContent).toBe(`$${FIXTURE.total.dollar_alloc.toLocaleString('en-US')}`);
		const rowHeader = within(footRow).getByRole('rowheader');
		expect(rowHeader.getAttribute('title')).toMatch(/US - Sector Diversified/);
		expect(rowHeader.textContent).toMatch(/= §2.2.2 parent row/);
	});
});

describe('UsEquityAllocationTable — AC4: zero-allocation Sub-Cats render de-emphasized but present', () => {
	it('the zero-held, zero-target US-02-Telecom row still renders, tagged .zero-alloc', () => {
		const { getByText } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const cell = getByText('US-02-Telecom');
		const tr = cell.closest('tr')!;
		expect(tr.classList.contains('zero-alloc')).toBe(true);
	});

	it('a non-zero-alloc row does NOT carry .zero-alloc', () => {
		const { getByText } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const cell = getByText('US-01-Basic_Materials');
		const tr = cell.closest('tr')!;
		expect(tr.classList.contains('zero-alloc')).toBe(false);
	});
});

describe('UsEquityAllocationTable — AC5: no inline edit affordance anywhere', () => {
	it('the table contains no input/textarea/select/button/[contenteditable]', () => {
		const { getByRole } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const table = getByRole('table');
		expect(table.querySelectorAll('input, textarea, select, button, [contenteditable="true"]').length).toBe(0);
	});

	it('"Edit US Equity targets" is a plain navigation link to the SELF-242 editor, scoped via anchor', () => {
		const { getByRole } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const link = getByRole('link', { name: 'Edit US Equity targets' });
		expect(link.tagName).toBe('A');
		expect(link.getAttribute('href')).toBe('/settings/allocation#us-equity-heading');
	});

	it('no cell in the table ever carries a .pos or .neg performance-color class (matches shipped §2.2.2 neutral treatment)', () => {
		const { container } = render(UsEquityAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(container.querySelectorAll('.pos').length).toBe(0);
		expect(container.querySelectorAll('.neg').length).toBe(0);
	});
});

describe('UsEquityAllocationTable — AC7: section badge + per-row tri-state staleness', () => {
	it('section-level StaleConstituentBadge renders off the whole-tenant staleness prop', () => {
		const { container } = render(UsEquityAllocationTable, {
			props: {
				allocation: FIXTURE,
				staleness: {
					is_stale: true,
					stale_items: [
						{ linked_source_id: '1', institution_name: 'Bank 1', provider: 'plaid', connection_status: 'login_required', status_class: null }
					]
				}
			}
		});
		expect(container.querySelector('.stale-connection-marker')).not.toBeNull();
	});

	it('a row with is_stale === true renders the tag AND the row-tint class', () => {
		const staleFixture: UsEquityAllocation = {
			...FIXTURE,
			rows: FIXTURE.rows.map((r) => (r.sub_cat === 'US-01-Basic_Materials' ? { ...r, is_stale: true } : r))
		};
		const { getByText } = render(UsEquityAllocationTable, { props: { allocation: staleFixture, staleness: EMPTY_STALENESS } });
		const tr = getByText('US-01-Basic_Materials').closest('tr')!;
		expect(within(tr).getByText('May be stale')).toBeTruthy();
		expect(tr.classList.contains('stale-row')).toBe(true);
	});

	it('is_stale undefined (no per-row producer yet) is NORMALIZED to "Staleness unknown", never silently fresh', () => {
		const { getByText } = render(UsEquityAllocationTable, { props: { allocation: FIXTURE, staleness: EMPTY_STALENESS } });
		const tr = getByText('US-01-Basic_Materials').closest('tr')!;
		expect(within(tr).getByText('Staleness unknown')).toBeTruthy();
		expect(within(tr).queryByText('May be stale')).toBeNull();
		expect(tr.classList.contains('stale-row')).toBe(false);
	});

	it('an EXPLICIT is_stale === false renders no marker at all', () => {
		const freshFixture: UsEquityAllocation = {
			...FIXTURE,
			rows: FIXTURE.rows.map((r) => (r.sub_cat === 'US-01-Basic_Materials' ? { ...r, is_stale: false } : r))
		};
		const { getByText } = render(UsEquityAllocationTable, { props: { allocation: freshFixture, staleness: EMPTY_STALENESS } });
		const tr = getByText('US-01-Basic_Materials').closest('tr')!;
		expect(within(tr).queryByText('May be stale')).toBeNull();
		expect(within(tr).queryByText('Staleness unknown')).toBeNull();
		expect(tr.classList.contains('stale-row')).toBe(false);
	});
});

describe('UsEquityAllocationTable — degenerate zero-holding state', () => {
	it('total.dollar_alloc <= 0 renders the explanatory note; $Alloc still renders real figures', () => {
		const ZERO: UsEquityAllocation = {
			rows: US_EQUITY_SUB_CATS.map((sub_cat) => row({ sub_cat, pct_target: null, pct_alloc: null, dollar_target: null, dollar_realloc: null })),
			total: { dollar_alloc: 0, pct_alloc: null, pct_target: null, dollar_target: null, dollar_realloc: null }
		};
		const { getByRole, getByText } = render(UsEquityAllocationTable, { props: { allocation: ZERO, staleness: EMPTY_STALENESS } });
		expect(getByRole('status')).toBeTruthy();
		const tr = getByText('US-01-Basic_Materials').closest('tr')!;
		const cells = within(tr).getAllByRole('cell');
		expect(cells[1].textContent).toBe('—');
		expect(cells[4].textContent).toBe('$0');
	});
});
