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
		// SELF-243: is_stale is now REQUIRED on UsEquityRow (mirrors AllocationRow's own SELF-330
		// tightening) — default UNKNOWN (null), matching every fixture row that doesn't explicitly
		// exercise the stale/fresh branches.
		is_stale: null,
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

	// SELF-243 (frontend-2's own recommendation, QA-covered — mirrors the identical leg added to
	// NonReAllocationTable.dom.test.ts, same reasoning): every test above mounts a FRESH component
	// instance per fixture, proving each STATE renders correctly but nothing about the TRANSITION —
	// a real session re-fetches after re-auth and the SAME mounted instance updates its props, a
	// different Svelte code path from an initial mount. This renders once stale, asserts the tint,
	// `rerender()`s the SAME instance to fresh, and asserts the tint is actually gone.
	it('a row that WAS stale clears its tag and row-tint class on the next render once is_stale flips to false (the update path, not just the initial mount)', () => {
		const staleFixture: UsEquityAllocation = {
			...FIXTURE,
			rows: FIXTURE.rows.map((r) => (r.sub_cat === 'US-01-Basic_Materials' ? { ...r, is_stale: true } : r))
		};
		const freshFixture: UsEquityAllocation = {
			...FIXTURE,
			rows: FIXTURE.rows.map((r) => (r.sub_cat === 'US-01-Basic_Materials' ? { ...r, is_stale: false } : r))
		};
		const { getByText, rerender } = render(UsEquityAllocationTable, {
			props: { allocation: staleFixture, staleness: EMPTY_STALENESS }
		});
		const staleRow = getByText('US-01-Basic_Materials').closest('tr')!;
		expect(within(staleRow).getByText('May be stale')).toBeTruthy();
		expect(staleRow.classList.contains('stale-row')).toBe(true);

		rerender({ allocation: freshFixture, staleness: EMPTY_STALENESS });

		const clearedRow = getByText('US-01-Basic_Materials').closest('tr')!;
		expect(within(clearedRow).queryByText('May be stale')).toBeNull();
		expect(clearedRow.classList.contains('stale-row')).toBe(false);
	});
});

describe('UsEquityAllocationTable — degenerate zero-holding state', () => {
	it('total.dollar_alloc <= 0 (all-null payload) renders the explanatory note; $Alloc still renders real figures', () => {
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

describe('UsEquityAllocationTable — Sec F-1 (PR #520 AMBER, resolved): render-boundary gate on the US Equity denominator', () => {
	// HISTORICAL — the payload shapes below are what the SHIPPED SELF-240 server core used to emit:
	// it guarded pct_alloc on `totalUsEquity === 0` alone and guarded
	// pct_target/dollar_target/dollar_realloc on a SEPARATE `sumTargets === 0`, so they did not null
	// together and neither was `<= 0`. As of SELF-332 / ADR-061 the server no longer emits these
	// shapes at all — Decision 3 nulls every ratio column whenever `totalUsEquity <= 0`.
	// ⚠ THAT IS EXACTLY WHY THESE LEGS MUST NOT BE DELETED AS "UNREACHABLE". They are now the ONLY
	// exercise of this render gate, which ADR-061 Decision 6 reclassifies as belt-and-suspenders
	// RETAINED "as redundant defense against a stale or mis-built server payload". A correct payload
	// can never reach this branch; these hand-built fixtures ARE the stale/mis-built payload, and the
	// render layer must still force '—' on all four ratio columns (never $Alloc) regardless of what
	// the payload says underneath.

	it('(a) a stale/mis-built payload — totalUsEquity === 0 with a non-null pct_target (the pre-ADR-061 server shape) — render layer still forces "—" on all four ratio columns', () => {
		const ZERO_WITH_TARGETS: UsEquityAllocation = {
			rows: US_EQUITY_SUB_CATS.map((sub_cat, i) =>
				row({
					sub_cat,
					pct_target: i === 0 ? 33.33 : 0, // non-null — server's sumTargets > 0 branch
					pct_alloc: null, // server's totalUsEquity === 0 branch
					dollar_target: i === 0 ? 0 : 0,
					dollar_realloc: i === 0 ? 0 : 0
				})
			),
			// total.pct_target non-null (100) while total.dollar_alloc is exactly 0 — the split-guard
			// state Sec's finding names explicitly.
			total: { dollar_alloc: 0, pct_alloc: null, pct_target: 100, dollar_target: 0, dollar_realloc: 0 }
		};
		const { getByRole, getByText } = render(UsEquityAllocationTable, {
			props: { allocation: ZERO_WITH_TARGETS, staleness: EMPTY_STALENESS }
		});
		expect(getByRole('status').textContent).toMatch(/currently total zero or less/);
		const rowCells = within(getByText('US-01-Basic_Materials').closest('tr')!).getAllByRole('cell');
		// [label, %Target, %Alloc, $Target, $Alloc, $ReAlloc]
		expect(rowCells[1].textContent).toBe('—'); // NOT "33.33%" despite the non-null server value
		expect(rowCells[3].textContent).toBe('—');
		expect(rowCells[5].textContent).toBe('—');
		expect(rowCells[4].textContent).toBe('$0'); // $Alloc stays exempt, still real

		const footCells = within(getByRole('row', { name: /Total US Equity/ })).getAllByRole('cell');
		expect(footCells[0].textContent).toBe('—'); // NOT "100.00%" despite total.pct_target = 100
		expect(footCells[2].textContent).toBe('—');
		expect(footCells[4].textContent).toBe('—');
	});

	it('(b) a stale/mis-built payload — NEGATIVE totalUsEquity with real (non-null) ratio values throughout (the pre-ADR-061 server shape); render layer forces "—" throughout, and the banner never claims "no holdings"', () => {
		const NEGATIVE_TOTAL: UsEquityAllocation = {
			rows: US_EQUITY_SUB_CATS.map((sub_cat, i) =>
				row({
					sub_cat,
					pct_target: 8.33,
					pct_alloc: i === 0 ? 200 : 0, // real, computable ratios against a negative denominator
					dollar_target: -50,
					dollar_realloc: -50
				})
			),
			total: { dollar_alloc: -600, pct_alloc: 100, pct_target: 100, dollar_target: -600, dollar_realloc: 0 }
		};
		const { getByRole, getByText } = render(UsEquityAllocationTable, {
			props: { allocation: NEGATIVE_TOTAL, staleness: EMPTY_STALENESS }
		});
		const banner = getByRole('status');
		expect(banner.textContent).toMatch(/currently total zero or less/);
		expect(banner.textContent).not.toMatch(/No US Equity holdings/i);

		const rowCells = within(getByText('US-01-Basic_Materials').closest('tr')!).getAllByRole('cell');
		expect(rowCells[1].textContent).toBe('—');
		expect(rowCells[2].textContent).toBe('—'); // %Alloc — NOT "200.00%"
		expect(rowCells[3].textContent).toBe('—');
		expect(rowCells[5].textContent).toBe('—');

		const footCells = within(getByRole('row', { name: /Total US Equity/ })).getAllByRole('cell');
		expect(footCells[0].textContent).toBe('—');
		expect(footCells[1].textContent).toBe('—'); // %Alloc — NOT "100.00%"
		expect(footCells[2].textContent).toBe('—');
		expect(footCells[4].textContent).toBe('—');
		// $Alloc stays exempt — the real negative figure still renders.
		expect(footCells[3].textContent).toBe('-$600');
	});
});
