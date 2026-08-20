// nonReAllocation.coverageDivergence.server.test.ts — SELF-239 AC3's "your battery pairs to it"
// clause. QA-owned (per the sibling *.server.test.ts files in this directory), authored
// INDEPENDENTLY of Backend's own paired-Σ test in nonReAllocation.test.ts ("AC4: the four Cat
// subtotals plus Unsorted foot to TotalNonRE exactly"). Backend's route (stated at SELF-239
// hand-off): same-predicate-same-query — one `assetSubCatIds` Set, built once, consulted by both
// the row set and the TotalNonRE reduce — makes coverage divergence structurally unreachable rather
// than merely tested-for, and Backend additionally shipped the paired-Σ assertion as belt-and-
// suspenders. This file is QA's OWN version of that same paired assertion, on a DIFFERENT,
// adversarially-chosen fixture, so the two do not rise and fall together on one shared fixture bug.
//
// THE NAMED FAILURE CLASS (SELF-239 AC3, verbatim): "COVERAGE DIVERGENCE" — the row set and the
// denominator derived from different predicates, under-summing, failing OPEN. The sharpest way to
// catch a regression back to that class is a fixture where the row set and a NAIVE unfiltered
// denominator would visibly DISAGREE if the guard broke: a real liability-element row with a large
// market_value, alongside real asset-element holdings and a real Unsorted row. If a future edit
// reintroduces the pre-SELF-239 unfiltered `marketValueRows.reduce(...)`, THIS footing assertion
// fails immediately — Σ(rendered $Alloc, Unsorted included) would then be strictly less than the
// (wrongly inflated) total_non_re, by exactly the liability row's value.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

describe('AC3 — QA\'s own paired Σ(rendered $Alloc incl. Unsorted) = TotalNonRE assertion', () => {
	const taxonomy: TaxonomySubCatRow[] = [
		{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
		{ id: 2, cat: 'Bonds', sub_cat: 'IGL', display_order: 50, element: 'asset' },
		{ id: 3, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240, element: 'asset' },
		{ id: 9, cat: 'Liabilities', sub_cat: 'Liability Balances', display_order: 300, element: 'liability' }
	];
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1200 },
		{ sub_cat_id: 2, cat: 'Bonds', sub_cat: 'IGL', market_value: 300 },
		{ sub_cat_id: 3, cat: 'Alternatives', sub_cat: 'REIT', market_value: 50 },
		{ sub_cat_id: 9, cat: 'Liabilities', sub_cat: 'Liability Balances', market_value: 40000 },
		{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 75 } // Unsorted
	];

	const result = computeNonReAllocation(taxonomy, marketValueRows, new Map());

	it('precondition: the excluded liability row is genuinely the dominant value in the fixture (a non-marginal divergence if the guard broke)', () => {
		expect(marketValueRows.find((r) => r.sub_cat_id === 9)!.market_value).toBeGreaterThan(
			marketValueRows.filter((r) => r.sub_cat_id !== 9).reduce((s, r) => s + r.market_value, 0)
		);
	});

	it('QA paired assertion: Σ every rendered row\'s $Alloc across all four groups, PLUS Unsorted, equals TotalNonRE exactly — no tolerance', () => {
		const renderedSum =
			result.groups.reduce((s, g) => s + g.rows.reduce((rs, r) => rs + r.dollar_alloc, 0), 0) +
			(result.unsorted?.dollar_alloc ?? 0);
		expect(renderedSum).toBe(result.total_non_re);
		const subtotalSum =
			result.groups.reduce((s, g) => s + g.dollar_alloc_subtotal, 0) + (result.unsorted?.dollar_alloc ?? 0);
		expect(subtotalSum).toBe(renderedSum);
	});

	it('the paired assertion is NON-VACUOUS on the divergence-catching value specifically: TotalNonRE is nowhere near what an unfiltered sum would be', () => {
		const naiveUnfilteredSum = marketValueRows.reduce((s, r) => s + r.market_value, 0);
		expect(result.total_non_re).toBe(1625); // 1200 + 300 + 50 + 75 — NOT 41625
		expect(result.total_non_re).not.toBe(naiveUnfilteredSum);
		expect(naiveUnfilteredSum - result.total_non_re).toBe(40000); // exactly the excluded row's value
	});

	it('the liability row renders in no group and carries no id anywhere in the output', () => {
		const allSubCatIds = result.groups.flatMap((g) => g.rows.map((r) => r.sub_cat_id));
		expect(allSubCatIds).not.toContain(9);
		expect(result.groups.map((g) => g.cat)).not.toContain('Liabilities');
	});
});
