// NonReAllocationTable.dom.test.ts — SELF-239 verification battery for the §2.2.2 Non-RE
// allocation table's ratified ACs (2026-08-20).
//
// ENV: jsdom (per-file pragma, mirrors NavCompositionTable.dom.test.ts / PlanningTargetEditor's
// own convention) + @testing-library/svelte. Query via the testing-library helpers, never
// `container.querySelector` for element lookup — see this repo's own
// testing-library-container-queryselector-rune-error gotcha; `container` is used ONLY where a
// class-presence assertion has no accessible-role equivalent (e.g. proving a value-color class is
// ABSENT table-wide), matching NavCompositionTable.dom.test.ts's own precedent.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, within } from '@testing-library/svelte';
import { EMPTY_STALENESS } from '$lib/staleness/stale-constituent';
import NonReAllocationTable from './NonReAllocationTable.svelte';
import type { NonReAllocation, AllocationRow, AllocationCatGroup } from '$lib/nonre-allocation';

const FIXTURE_TOTAL = 10000;

function row(over: Partial<AllocationRow> & { sub_cat: string }): AllocationRow {
	return {
		kind: 'sub_cat',
		sub_cat_id: null,
		cat: null,
		pct_target: 0,
		pct_alloc: 0,
		dollar_target: 0,
		dollar_alloc: 0,
		dollar_realloc: 0,
		...over
	};
}

// Builds a group with server-authoritative dollar_alloc_subtotal/pct_alloc_subtotal computed the
// SAME way nonReAllocation.ts's SELF-239 branch does (Σ dollar_alloc, ÷ total when total > 0,
// else null) — verified against `feature/self239-nonre-allocation-table` (commits a9ebf8e +
// dc033a1), not assumed from a report.
function group(cat: string, rows: AllocationRow[], total = FIXTURE_TOTAL): AllocationCatGroup {
	const dollar_alloc_subtotal = rows.reduce((s, r) => s + r.dollar_alloc, 0);
	return {
		cat,
		rows,
		dollar_alloc_subtotal,
		pct_alloc_subtotal: total > 0 ? (dollar_alloc_subtotal / total) * 100 : null
	};
}

// Mirrors the SHAPE nonReAllocation.ts's `computeNonReAllocation` actually returns on the SELF-239
// branch: `groups[]` carries exactly the FOUR rendered Cat-groups (Liabilities is absent from the
// payload itself, not merely unrendered — the assets-only rework via the `element` predicate).
// Includes one zero-held row (AC2), the collapsed US-equity row, and Unsorted.
const FIXTURE: NonReAllocation = {
	groups: [
		group('Cash', [
			row({ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', pct_target: 10, pct_alloc: 8, dollar_target: 1000, dollar_alloc: 800, dollar_realloc: 200 }),
			// zero-held, zero-target seeded row — AC2 says this still renders.
			row({ sub_cat_id: 2, cat: 'Cash', sub_cat: 'Cash Balances', pct_target: 0, pct_alloc: 0, dollar_target: 0, dollar_alloc: 0, dollar_realloc: 0 })
		]),
		group('Bonds', [row({ sub_cat_id: 3, cat: 'Bonds', sub_cat: 'Treasury', pct_target: 5, pct_alloc: 5, dollar_target: 500, dollar_alloc: 500, dollar_realloc: 0 })]),
		group('Marketable Securities', [
			row({ sub_cat_id: 4, cat: 'Marketable Securities', sub_cat: 'UNKNOWN', pct_target: 5, pct_alloc: 5, dollar_target: 500, dollar_alloc: 500, dollar_realloc: 0 }),
			row({
				kind: 'us_sector_diversified',
				sub_cat_id: null,
				cat: 'Marketable Securities',
				sub_cat: 'US - Sector Diversified',
				pct_target: 60,
				pct_alloc: 62,
				dollar_target: 6000,
				dollar_alloc: 6200,
				dollar_realloc: -200
			})
		]),
		group('Alternatives', [row({ sub_cat_id: 5, cat: 'Alternatives', sub_cat: 'REIT', pct_target: 5, pct_alloc: 5, dollar_target: 500, dollar_alloc: 500, dollar_realloc: 0 })])
	],
	unsorted: row({ kind: 'unsorted', sub_cat_id: null, cat: null, sub_cat: 'Unsorted', pct_target: null, pct_alloc: 5, dollar_target: null, dollar_alloc: 500, dollar_realloc: null }),
	total_non_re: FIXTURE_TOTAL
};

describe('NonReAllocationTable — AC1: exactly four Cat-group headers, fixed order, Liabilities/Real Estate never rendered', () => {
	it('renders Cash, Bonds, Marketable Securities, Alternatives in that order and nothing else as a group header', () => {
		const { getAllByRole } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const groupHeaders = getAllByRole('columnheader', { name: /Cash|Bonds|Marketable Securities|Alternatives|Liabilities|Real Estate/ });
		const labels = groupHeaders.map((el) => el.textContent?.trim());
		expect(labels).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives']);
	});

	it('a malformed payload with an extra Liabilities entry still never renders it as a Cat-group header (defense-in-depth)', () => {
		const withLiabilities: NonReAllocation = {
			...FIXTURE,
			groups: [...FIXTURE.groups, group('Liabilities', [])]
		};
		const { queryByRole } = render(NonReAllocationTable, {
			props: { allocation: withLiabilities, staleness: EMPTY_STALENESS }
		});
		expect(queryByRole('columnheader', { name: 'Liabilities' })).toBeNull();
	});

	it('a malformed payload MISSING a Cat entirely still renders its header (defensive fallback, empty)', () => {
		const missingBonds: NonReAllocation = {
			...FIXTURE,
			groups: FIXTURE.groups.filter((g) => g.cat !== 'Bonds')
		};
		const { getByRole } = render(NonReAllocationTable, {
			props: { allocation: missingBonds, staleness: EMPTY_STALENESS }
		});
		expect(getByRole('columnheader', { name: 'Bonds' })).toBeTruthy();
	});
});

describe('NonReAllocationTable — AC2: full enumeration + collapsed row + Unsorted never dropped', () => {
	it('a zero-held, zero-target seeded Sub-Cat still renders its row', () => {
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(getByText('Cash Balances')).toBeTruthy();
	});

	it('the collapsed "US - Sector Diversified" row renders inside Marketable Securities', () => {
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(getByText('US - Sector Diversified')).toBeTruthy();
	});

	it('the derived Unsorted row renders as its own section when present', () => {
		const { getByRole, getAllByText } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(getByRole('columnheader', { name: 'Unsorted' })).toBeTruthy();
		// Two occurrences: the group header + the single row's own label cell.
		expect(getAllByText('Unsorted')).toHaveLength(2);
	});

	it('Unsorted section is absent entirely when the payload has none', () => {
		const { queryByRole } = render(NonReAllocationTable, {
			props: { allocation: { ...FIXTURE, unsorted: null }, staleness: EMPTY_STALENESS }
		});
		expect(queryByRole('columnheader', { name: 'Unsorted' })).toBeNull();
	});
});

describe('NonReAllocationTable — AC4: subtotal + Total-foot reconciliation', () => {
	it('the Cash subtotal row reconciles to its two constituent rows (10+0=10 target%, 8+0=8 alloc%)', () => {
		const { getByRole } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const subtotalRow = getByRole('row', { name: /Cash subtotal/ });
		const cells = within(subtotalRow).getAllByRole('cell');
		// [%Target, %Alloc, $Target, $Alloc, $ReAlloc]
		expect(cells[0].textContent).toBe('10.00%');
		expect(cells[1].textContent).toBe('8.00%');
		expect(cells[3].textContent).toContain('800');
	});

	it('the Total Non-RE foot row displays total_non_re for $Alloc, the authoritative anchor', () => {
		const { getByRole } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const footRow = getByRole('row', { name: /Total Non-RE/ });
		const cells = within(footRow).getAllByRole('cell');
		expect(cells[3].textContent).toBe('$10,000');
	});
});

describe('NonReAllocationTable — AC5 fence 1: no performance color anywhere; .val-target only on %Target/$Target/$ReAlloc', () => {
	it('no cell in the table ever carries a .pos or .neg class', () => {
		const { container } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		expect(container.querySelectorAll('.pos').length).toBe(0);
		expect(container.querySelectorAll('.neg').length).toBe(0);
	});

	it('a Sub-Cat data row carries .val-target on exactly the %Target/$Target/$ReAlloc cells (3), not %Alloc/$Alloc', () => {
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const cell = getByText('FDIC').closest('tr')!;
		const numCells = within(cell).getAllByRole('cell');
		// A data row's label is a plain <td> (also role "cell"), so the array is
		// [label, %Target, %Alloc, $Target, $Alloc, $ReAlloc].
		expect(numCells[1].classList.contains('val-target')).toBe(true);
		expect(numCells[2].classList.contains('val-target')).toBe(false);
		expect(numCells[3].classList.contains('val-target')).toBe(true);
		expect(numCells[4].classList.contains('val-target')).toBe(false);
		expect(numCells[5].classList.contains('val-target')).toBe(true);
	});
});

describe('NonReAllocationTable — AC6: TotalNonRE <= 0 renders ratio columns as unset, never fake-zero; $Alloc always renders', () => {
	const ZERO_TOTAL: NonReAllocation = {
		groups: FIXTURE.groups.map((g) =>
			group(g.cat, g.rows.map((r) => ({ ...r, dollar_alloc: 0 })), 0)
		),
		unsorted: null,
		total_non_re: 0
	};

	it('%Target/%Alloc/$Target/$ReAlloc all render "—", never "0.00%"/"$0"/"NaN"/"Infinity"', () => {
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: ZERO_TOTAL, staleness: EMPTY_STALENESS }
		});
		const row = getByText('FDIC').closest('tr')!;
		const cells = within(row).getAllByRole('cell');
		// [label, %Target, %Alloc, $Target, $Alloc, $ReAlloc]
		expect(cells[1].textContent).toBe('—');
		expect(cells[2].textContent).toBe('—');
		expect(cells[3].textContent).toBe('—');
		expect(cells[5].textContent).toBe('—');
		for (const c of cells) {
			expect(c.textContent).not.toMatch(/NaN|Infinity/);
		}
	});

	it('$Alloc still renders a real dollar figure (never unset) even at TotalNonRE=0', () => {
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: ZERO_TOTAL, staleness: EMPTY_STALENESS }
		});
		const row = getByText('FDIC').closest('tr')!;
		const cells = within(row).getAllByRole('cell');
		expect(cells[4].textContent).toBe('$0');
	});

	it('a negative total_non_re also triggers the unset treatment (the negative-denominator case)', () => {
		const NEGATIVE_TOTAL: NonReAllocation = { ...ZERO_TOTAL, total_non_re: -500 };
		const { getByText } = render(NonReAllocationTable, {
			props: { allocation: NEGATIVE_TOTAL, staleness: EMPTY_STALENESS }
		});
		const row = getByText('FDIC').closest('tr')!;
		expect(within(row).getAllByRole('cell')[1].textContent).toBe('—');
	});

	it('the explanatory note renders exactly when ratios are unset, and never when they are not', () => {
		const unset = render(NonReAllocationTable, { props: { allocation: ZERO_TOTAL, staleness: EMPTY_STALENESS } });
		expect(unset.getByRole('status')).toBeTruthy();
		unset.unmount();

		const set = render(NonReAllocationTable, { props: { allocation: FIXTURE, staleness: EMPTY_STALENESS } });
		expect(set.queryByRole('status')).toBeNull();
	});
});

describe('NonReAllocationTable — AC8: no inline edit affordance anywhere', () => {
	it('the table contains no input/textarea/select/button/[contenteditable]', () => {
		const { getByRole } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const table = getByRole('table');
		expect(table.querySelectorAll('input, textarea, select, button, [contenteditable="true"]').length).toBe(0);
	});

	it('"Edit allocation targets" is a plain navigation link to /settings/allocation, not a form/button', () => {
		const { getByRole } = render(NonReAllocationTable, {
			props: { allocation: FIXTURE, staleness: EMPTY_STALENESS }
		});
		const link = getByRole('link', { name: 'Edit allocation targets' });
		expect(link.tagName).toBe('A');
		expect(link.getAttribute('href')).toBe('/settings/allocation');
	});
});

describe('NonReAllocationTable — AC11: section badge + per-row tri-state staleness', () => {
	it('section-level StaleConstituentBadge renders off the whole-tenant staleness prop', () => {
		const { container } = render(NonReAllocationTable, {
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
		const staleFixture: NonReAllocation = {
			...FIXTURE,
			groups: FIXTURE.groups.map((g) =>
				g.cat === 'Cash'
					? { ...g, rows: g.rows.map((r) => (r.sub_cat === 'FDIC' ? { ...r, is_stale: true } : r)) }
					: g
			)
		};
		const { getByText } = render(NonReAllocationTable, { props: { allocation: staleFixture, staleness: EMPTY_STALENESS } });
		const row = getByText('FDIC').closest('tr')!;
		expect(within(row).getByText('May be stale')).toBeTruthy();
		expect(row.classList.contains('stale-row')).toBe(true);
	});

	it('a row with is_stale === null renders "Staleness unknown", no row tint, distinct from true', () => {
		const unknownFixture: NonReAllocation = {
			...FIXTURE,
			groups: FIXTURE.groups.map((g) =>
				g.cat === 'Cash'
					? { ...g, rows: g.rows.map((r) => (r.sub_cat === 'FDIC' ? { ...r, is_stale: null } : r)) }
					: g
			)
		};
		const { getByText } = render(NonReAllocationTable, { props: { allocation: unknownFixture, staleness: EMPTY_STALENESS } });
		const row = getByText('FDIC').closest('tr')!;
		expect(within(row).getByText('Staleness unknown')).toBeTruthy();
		expect(within(row).queryByText('May be stale')).toBeNull();
		expect(row.classList.contains('stale-row')).toBe(false);
	});

	it('a row with is_stale undefined (today\'s default — no per-row join yet) renders neither marker nor tint', () => {
		const { getByText } = render(NonReAllocationTable, { props: { allocation: FIXTURE, staleness: EMPTY_STALENESS } });
		const row = getByText('FDIC').closest('tr')!;
		expect(within(row).queryByText('May be stale')).toBeNull();
		expect(within(row).queryByText('Staleness unknown')).toBeNull();
		expect(row.classList.contains('stale-row')).toBe(false);
	});
});
