// TaxDecompositionTable.dom.test.ts — SELF-264 verification battery for the §2.5.1 tax-relevant
// income decomposition table's ACs.
//
// ENV: jsdom (per-file pragma, matches NonReAllocationTable.dom.test.ts / CashflowRollupTable's
// own convention) + @testing-library/svelte. Query via the testing-library helpers, never
// `container.querySelector` for element lookup. Assertions use this repo's own established
// idiom — `.toBeTruthy()` / `.toBeNull()` / `.toHaveLength()` / direct `.textContent` /
// `.getAttribute()` comparisons — NOT `@testing-library/jest-dom` matchers
// (`toBeInTheDocument`/`toHaveAttribute`), which this project does not wire into `expect` (no
// jest-dom setupFile in vitest.config.ts — verified against NonReAllocationTable.dom.test.ts's
// own assertion style, not assumed).
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, screen, within } from '@testing-library/svelte';
import TaxDecompositionTable from './TaxDecompositionTable.svelte';
import type {
	TaxLiabilitySlice,
	TaxCharacterCatalog,
	DecompositionRow
} from '$lib/tax-decomposition';

const SEED_DELTA = '100_tax_value_inventory_seed_delta.sql';

// Mirrors the real 5-row seed (migration `011`) — used as the default catalog so tests exercise
// real codes/labels, not synthetic ones.
const CATALOG: TaxCharacterCatalog = [
	{ code: 'ordinary', label: 'Ordinary income', display_order: 10 },
	{ code: 'qualified_dividend', label: 'Qualified dividend', display_order: 20 },
	{ code: 'tax_exempt_interest', label: 'Tax-exempt interest', display_order: 30 },
	{ code: 'long_term_capital_gain_eligible', label: 'Long-term capital gain eligible', display_order: 40 },
	{ code: 'short_term_only', label: 'Short-term only', display_order: 50 }
];

let nextSubCatId = 1;
function row(over: Partial<DecompositionRow> & { sub_cat: string; cat?: string }): DecompositionRow {
	return {
		sub_cat_id: nextSubCatId++,
		cat: 'Revenue',
		tax_character: 'ordinary',
		amount: 0,
		...over
	};
}

function liability(
	over: Partial<TaxLiabilitySlice['decomposition']> = {},
	rows: DecompositionRow[] = []
): TaxLiabilitySlice {
	const total = rows.reduce((s, r) => s + r.amount, 0);
	return {
		tax_year: 2026,
		decomposition: {
			ordinary_income: { rows, total },
			capital_gains: { status: 'unavailable', reason: 'no_sale_recording_capability' },
			unclassified: { count_ytd: 0 },
			...over
		}
	};
}

describe('TaxDecompositionTable', () => {
	it('renders the UNAVAILABLE-with-a-reason capital gains banner (AC 3a / R1)', () => {
		render(TaxDecompositionTable, {
			liability: liability(),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByText(/doesn't yet support recording a security sale/i)).toBeTruthy();
		// Never zeros, never a milestone name.
		expect(screen.queryByText(/\$0\.00|\$0(?!\d)/)).toBeNull();
		expect(screen.queryByText(/SELF-30[23]/)).toBeNull();
	});

	it('renders the empty state for the Income section when there are zero rows (AC9(i))', () => {
		render(TaxDecompositionTable, {
			liability: liability(),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByText('No tax-relevant activity this tax year yet.')).toBeTruthy();
	});

	it('renders PM\'s unclassified copy exactly, and only when count_ytd > 0 (AC 3b)', () => {
		const { rerender } = render(TaxDecompositionTable, {
			liability: liability({ unclassified: { count_ytd: 0 } }),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});
		expect(screen.queryByText(/unclassified/i)).toBeNull();

		rerender({
			liability: liability({ unclassified: { count_ytd: 3 } }),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});
		// The full sentence spans a text node + a nested <a> ("classify" the link), so it is
		// asserted via the containing element's normalized textContent — a bare getByText(full
		// string) does not match text split across a child element (this codebase's own
		// `.textContent` convention, see e.g. NonReAllocationTable.dom.test.ts's cell checks).
		const classifyLink = screen.getByRole('link', { name: 'classify' });
		expect(classifyLink.getAttribute('href')).toBe('/accounts');
		const banner = classifyLink.closest('.unclassified-text');
		expect(banner).not.toBeNull();
		expect((banner as HTMLElement).textContent?.replace(/\s+/g, ' ').trim()).toBe(
			'3 items unclassified — any may be income — classify'
		);
	});

	it('resolves tax_character labels against the taxCharacters catalog prop, not a hardcoded map (AC5)', () => {
		// A deliberately RELABELED catalog (not the real migration `011` strings) — if this
		// component rendered a hardcoded code→label switch instead of resolving through the
		// catalog prop, this test would see the REAL "Qualified dividend" string instead.
		const relabeledCatalog: TaxCharacterCatalog = [
			{ code: 'qualified_dividend', label: 'TEST-ONLY RELABEL', display_order: 20 }
		];
		render(TaxDecompositionTable, {
			liability: liability(
				{},
				[row({ sub_cat: 'Dividend - Qualified', tax_character: 'qualified_dividend', amount: 500 })]
			),
			taxCharacters: relabeledCatalog,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByText('TEST-ONLY RELABEL')).toBeTruthy();
		expect(screen.queryByText('Qualified dividend')).toBeNull();
	});

	it('falls back to the raw code when it is missing from the catalog, never a guessed label', () => {
		render(TaxDecompositionTable, {
			liability: liability({}, [
				row({ sub_cat: 'Mystery Row', tax_character: 'not_in_catalog', amount: 1 })
			]),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByText('not_in_catalog')).toBeTruthy();
	});

	it('renders no chip at all for a NULL tax_character', () => {
		render(TaxDecompositionTable, {
			liability: liability({}, [row({ sub_cat: 'No Character', tax_character: null, amount: 1 })]),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		const rowEl = screen.getByText('No Character').closest('tr');
		expect(rowEl).not.toBeNull();
		// The char-cell has no chip span — nothing character-shaped renders in that cell.
		expect(within(rowEl as HTMLElement).queryByTitle(/./)).toBeNull();
	});

	it('groups by Cat with a header row, per-group subtotal, and a footing total read from the server-authoritative total (AC4)', () => {
		render(TaxDecompositionTable, {
			liability: liability({}, [
				row({ sub_cat: 'Salary', cat: 'Revenue', amount: 1000 }),
				row({ sub_cat: 'Dividend', cat: 'Revenue', amount: 200 })
			]),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByRole('columnheader', { name: /cat \/ sub-cat/i })).toBeTruthy();
		expect(screen.getByText('Revenue')).toBeTruthy();
		expect(screen.getByText('Revenue subtotal')).toBeTruthy();
		// Subtotal + Total both foot to $1,200.
		const table = screen.getByRole('table');
		const cells = within(table).getAllByText('$1,200');
		expect(cells.length).toBe(2);
	});

	it('renders every ST CG / LT CG cell as "—", never derived from tax_character (contract gap note)', () => {
		render(TaxDecompositionTable, {
			liability: liability({}, [
				row({
					sub_cat: 'LT Gain Eligible Dividend',
					tax_character: 'long_term_capital_gain_eligible',
					amount: 500
				})
			]),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		const rowEl = screen.getByText('LT Gain Eligible Dividend').closest('tr');
		expect(rowEl).not.toBeNull();
		const dashes = within(rowEl as HTMLElement).getAllByText('—');
		expect(dashes.length).toBe(2); // ST CG + LT CG cells, even for an LT-CG-eligible character.
		// The $500 renders under Ordinary, not silently dropped.
		expect(within(rowEl as HTMLElement).getByText('$500')).toBeTruthy();
	});

	it('names the seed-delta migration in the basis note (AC11)', () => {
		render(TaxDecompositionTable, {
			liability: liability(),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		expect(screen.getByText(new RegExp(SEED_DELTA))).toBeTruthy();
	});

	it('renders no interactive elements in any data cell (AC10 — no inline edit)', () => {
		render(TaxDecompositionTable, {
			liability: liability({}, [row({ sub_cat: 'Salary', amount: 1000 })]),
			taxCharacters: CATALOG,
			seedDeltaMigration: SEED_DELTA
		});

		const table = screen.getByRole('table');
		expect(within(table).queryAllByRole('button')).toHaveLength(0);
		expect(within(table).queryAllByRole('textbox')).toHaveLength(0);
		expect(within(table).queryAllByRole('link')).toHaveLength(0);
	});
});
