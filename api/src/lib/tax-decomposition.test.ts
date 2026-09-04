// tax-decomposition.test.ts — direct unit coverage for the pure presentation helpers in
// tax-decomposition.ts (SELF-264). TaxDecompositionTable.dom.test.ts exercises these indirectly
// through rendering but only ever seeds a SINGLE Cat ('Revenue'), so groupByCat's cross-Cat
// order-preservation property has no watcher anywhere else on the tree — this file closes that
// gap and gives the remaining pure helpers (groupSubtotal, hasUnclassifiedItems's boundary,
// the unclassified copy strings, lookupTaxCharacter, fmtCell) a fast, non-DOM home, matching this
// directory's own precedent (account-display.test.ts / asset-classify.test.ts, etc. — plain
// lib/*.ts modules get a lib/*.test.ts, not only a component dom test).

import { describe, it, expect } from 'vitest';
import {
	groupByCat,
	groupSubtotal,
	hasUnclassifiedItems,
	unclassifiedCopyPrefix,
	unclassifiedCopy,
	incomeIsEmpty,
	lookupTaxCharacter,
	fmtCell,
	type DecompositionRow,
	type TaxCharacterCatalog
} from './tax-decomposition';

let nextId = 1;
function row(over: Partial<DecompositionRow> & { sub_cat: string; cat: string }): DecompositionRow {
	return {
		sub_cat_id: nextId++,
		tax_character: null,
		amount: 0,
		...over
	};
}

describe('groupByCat', () => {
	it('preserves each Cat\'s FIRST-SEEN order across MULTIPLE Cat groups — not a re-sort', () => {
		// Interleaved input: Revenue, Trade, Revenue, Trade, Cash — three distinct Cats, first-seen
		// order Revenue -> Trade -> Cash. A naive `.sort()` or a Map iterating insertion-unstably
		// would silently reorder this; the dom test's single-Cat fixture cannot catch a regression here.
		const rows = [
			row({ sub_cat: 'Salary Untagged', cat: 'Revenue', amount: 100 }),
			row({ sub_cat: 'STC', cat: 'Trade', amount: 10 }),
			row({ sub_cat: 'Dividend', cat: 'Revenue', amount: 20 }),
			row({ sub_cat: 'BTC', cat: 'Trade', amount: 5 }),
			row({ sub_cat: 'Interest', cat: 'Cash', amount: 1 })
		];

		const groups = groupByCat(rows);

		expect(groups.map((g) => g.cat)).toEqual(['Revenue', 'Trade', 'Cash']);
		expect(groups[0].rows.map((r) => r.sub_cat)).toEqual(['Salary Untagged', 'Dividend']);
		expect(groups[1].rows.map((r) => r.sub_cat)).toEqual(['STC', 'BTC']);
		expect(groups[2].rows.map((r) => r.sub_cat)).toEqual(['Interest']);
	});

	it('returns an empty array for zero rows, never a single empty-Cat group', () => {
		expect(groupByCat([])).toEqual([]);
	});
});

describe('groupSubtotal', () => {
	it('sums a group\'s rows by plain addition, independent of any server-reported total', () => {
		const rows = [
			row({ sub_cat: 'A', cat: 'Revenue', amount: 100.5 }),
			row({ sub_cat: 'B', cat: 'Revenue', amount: 49.25 })
		];
		expect(groupSubtotal(rows)).toBeCloseTo(149.75);
	});

	it('is 0 for an empty group', () => {
		expect(groupSubtotal([])).toBe(0);
	});
});

describe('hasUnclassifiedItems / incomeIsEmpty — boundary conditions', () => {
	it('hasUnclassifiedItems is false at exactly 0 and true at 1 — the AC9 boundary', () => {
		expect(hasUnclassifiedItems({ count_ytd: 0 })).toBe(false);
		expect(hasUnclassifiedItems({ count_ytd: 1 })).toBe(true);
	});

	it('incomeIsEmpty is true only at zero rows', () => {
		expect(incomeIsEmpty([])).toBe(true);
		expect(incomeIsEmpty([row({ sub_cat: 'X', cat: 'Revenue', amount: 1 })])).toBe(false);
	});
});

describe('unclassifiedCopyPrefix / unclassifiedCopy — PM\'s exact sentence, one source', () => {
	it('composes the exact PM copy at an arbitrary count, and unclassifiedCopy appends "classify" from the SAME prefix', () => {
		expect(unclassifiedCopyPrefix({ count_ytd: 5 })).toBe(
			'5 items unclassified — any may be income —'
		);
		expect(unclassifiedCopy({ count_ytd: 5 })).toBe(
			'5 items unclassified — any may be income — classify'
		);
		// The two never diverge because unclassifiedCopy is composed FROM unclassifiedCopyPrefix.
		expect(unclassifiedCopy({ count_ytd: 5 })).toBe(unclassifiedCopyPrefix({ count_ytd: 5 }) + ' classify');
	});
});

describe('lookupTaxCharacter', () => {
	const CATALOG: TaxCharacterCatalog = [
		{ code: 'ordinary', label: 'Ordinary income', display_order: 10 },
		{ code: 'qualified_dividend', label: 'Qualified dividend', display_order: 20 }
	];

	it('returns null for a null code — nothing to legend', () => {
		expect(lookupTaxCharacter(CATALOG, null)).toBeNull();
	});

	it('resolves a known code against the catalog', () => {
		expect(lookupTaxCharacter(CATALOG, 'qualified_dividend')).toEqual({
			code: 'qualified_dividend',
			label: 'Qualified dividend'
		});
	});

	it('falls back to the raw code as its own label when missing from the catalog — never a guessed string', () => {
		expect(lookupTaxCharacter(CATALOG, 'short_term_only')).toEqual({
			code: 'short_term_only',
			label: 'short_term_only'
		});
	});
});

describe('fmtCell', () => {
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});

	it('renders "—" for null, never "$0"', () => {
		expect(fmtCell(null, usd)).toBe('—');
	});

	it('renders a formatted amount for a real number, including exactly zero', () => {
		expect(fmtCell(0, usd)).toBe('$0');
		expect(fmtCell(1200, usd)).toBe('$1,200');
	});
});
