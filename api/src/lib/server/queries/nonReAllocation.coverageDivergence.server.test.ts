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
//
// SEC HARDENING ROUND 2 (2026-08-20, F/CTO-adopted, commit 519c922) — two more describe blocks
// below, arming the SAME Σ(rendered)=total_non_re leg for the two cases Sec measured as
// unexercised at the round-1 review: an asset-element Sub-Cat under a Cat OUTSIDE the canonical
// four (option (B) — union, never drop), and Real Estate carrying a real market_value (excluded
// explicitly at `assetSubCatIds`, no longer riding 076's `p_include_real_estate:false` argument).
// Confirmed BOTH legs fail against the pre-519c922 code (read backend's branch tip 61c2913
// read-only, ran the equivalent of these fixtures there, reset — never touched their worktree):
// the unknown-Cat leg diverged because `CAT_GROUP_ORDER.map(...)` never looked the Cat up; the
// Real Estate leg diverged because `assetSubCatIds` didn't exclude it, only the row-set's separate
// `cat !== 'Real Estate'` filter did. Both fixtures below are adversarially DIFFERENT from
// Backend's own round-2 regression tests (nonReAllocation.test.ts): Backend's unknown-Cat case
// uses a single appended Cat and never exercises ordering with more than one; Backend's Real
// Estate case never combines it with a stray planning_target row or an Unsorted row. Independence
// per this file's own standing practice (see the header above).

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

describe('AC3 / SEC ROUND 2 (a) — QA\'s own paired Σ assertion for the union (option-B) fix, multi-Cat alphabetical-order proof', () => {
	// THREE uncatalogued Cats, inserted in an order that is DELIBERATELY NOT alphabetical (Zeta,
	// then Alpha, then Mid) — Backend's own round-2 test uses exactly ONE appended Cat, which
	// cannot distinguish "appended alphabetically" from "appended in whatever order they were
	// discovered/inserted in": with only one element, every ordering is trivially "correct". This
	// fixture is the one that can actually tell the two apart.
	const taxonomy: TaxonomySubCatRow[] = [
		{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
		{ id: 70, cat: 'Zeta Holdings', sub_cat: 'Misc', display_order: 600, element: 'asset' },
		{ id: 71, cat: 'Alpha Metals', sub_cat: 'Gold', display_order: 610, element: 'asset' },
		// Zero-held: no corresponding marketValueRows entry below. Proves an appended group renders
		// even at zero value, the same AC2 zero-held guarantee the canonical four already carry —
		// Backend's own test never gives its single appended Cat a zero-held case.
		{ id: 72, cat: 'Mid Ventures', sub_cat: 'Seed', display_order: 620, element: 'asset' }
	];
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 100 },
		// Alpha Metals carries the DOMINANT value in the fixture (this file's standing practice) —
		// a regression back to silent-drop would be impossible to miss.
		{ sub_cat_id: 71, cat: 'Alpha Metals', sub_cat: 'Gold', market_value: 9000 },
		{ sub_cat_id: 70, cat: 'Zeta Holdings', sub_cat: 'Misc', market_value: 50 },
		{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 25 } // Unsorted, present too
	];
	// A real target on the appended Cat's own row — Backend's round-2 test only checks
	// dollar_alloc/dollar_alloc_subtotal on its appended group; it never proves the ratio-derived
	// columns (pct_target/dollar_target/dollar_realloc) compute correctly for a row living in an
	// APPENDED group, as opposed to a canonical one. `targetDerivedColumns`/`ratioPercentOrNull`
	// are Cat-blind by construction, but "by construction" is exactly the kind of claim this file
	// exists to verify rather than take on faith.
	const targets = new Map<number, number>([[71, 10]]);

	const result = computeNonReAllocation(taxonomy, marketValueRows, targets);

	it('precondition: the taxonomy\'s own insertion order is NOT already alphabetical (Zeta, Alpha, Mid) — the ordering assertion below is a real test, not an accident of input order', () => {
		const uncatalogued = taxonomy.filter((t) => t.id !== 1).map((t) => t.cat);
		const sorted = [...uncatalogued].sort();
		expect(uncatalogued).not.toEqual(sorted);
	});

	it('precondition: the appended Cat\'s dominant row is genuinely the largest single value in the fixture', () => {
		expect(9000).toBeGreaterThan(100 + 50 + 25);
	});

	it('groups render as the canonical four, THEN the three uncatalogued Cats in ALPHABETICAL order — never insertion order, never dropped', () => {
		expect(result.groups.map((g) => g.cat)).toEqual([
			'Cash',
			'Bonds',
			'Marketable Securities',
			'Alternatives',
			'Alpha Metals',
			'Mid Ventures',
			'Zeta Holdings'
		]);
	});

	it('the appended group with a real held value computes all five row-level columns correctly, not just dollar_alloc', () => {
		const alpha = result.groups.find((g) => g.cat === 'Alpha Metals')!;
		expect(alpha.rows).toHaveLength(1);
		const row = alpha.rows[0];
		expect(row.dollar_alloc).toBe(9000);
		expect(row.pct_target).toBe(10);
		expect(row.dollar_target).toBeCloseTo((10 / 100) * result.total_non_re);
		expect(row.dollar_realloc).toBeCloseTo(row.dollar_target! - 9000);
		expect(row.pct_alloc).toBeCloseTo((9000 / result.total_non_re) * 100);
		expect(alpha.dollar_alloc_subtotal).toBe(9000);
	});

	it('the zero-held appended group still renders (AC2\'s zero-held guarantee extends to appended groups, not just the canonical four)', () => {
		const mid = result.groups.find((g) => g.cat === 'Mid Ventures')!;
		expect(mid.rows).toHaveLength(1);
		expect(mid.rows[0]).toMatchObject({ sub_cat: 'Seed', dollar_alloc: 0, pct_target: 0, dollar_target: 0 });
		expect(mid.dollar_alloc_subtotal).toBe(0);
	});

	it('QA paired assertion: Σ(rendered $Alloc across ALL groups — canonical AND appended — incl. Unsorted) = TotalNonRE exactly', () => {
		expect(result.total_non_re).toBe(9175); // 100 + 9000 + 50 + 25
		const renderedSum =
			result.groups.reduce((s, g) => s + g.rows.reduce((rs, r) => rs + r.dollar_alloc, 0), 0) +
			(result.unsorted?.dollar_alloc ?? 0);
		expect(renderedSum).toBe(result.total_non_re);
		const subtotalSum =
			result.groups.reduce((s, g) => s + g.dollar_alloc_subtotal, 0) + (result.unsorted?.dollar_alloc ?? 0);
		expect(subtotalSum).toBe(renderedSum);
	});
});

describe('AC3 / SEC ROUND 2 (b) — QA\'s own paired Σ assertion for explicit Real Estate exclusion, combined with a stray target and Unsorted', () => {
	// Adversarially different from Backend's own round-2 Real Estate test: theirs is Real Estate +
	// Cash only. This fixture adds (1) a real planning_target row on the Real Estate Sub-Cat itself
	// — the SAME stray-row shape the SEC CARRY-FORWARD guard already covers for Liabilities (the
	// #17 fence checks matched-tenant only, not domain/element, so a %Target against an
	// asset-element-but-excluded Cat like Real Estate is exactly as DB-admissible as one against a
	// liability-element Cat — nobody has tested THIS combination before) — and (2) a real Unsorted
	// row, to prove Real Estate's exclusion doesn't interact badly with the one other row kind that
	// also has no Cat.
	const taxonomy: TaxonomySubCatRow[] = [
		{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
		{ id: 50, cat: 'Real Estate', sub_cat: 'Residential', display_order: 320, element: 'asset' }
	];
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 200 },
		// Real Estate carries the DOMINANT value — 076 should never emit this (p_include_real_estate
		// :false elsewhere), but this module's own predicate must not depend on that upstream flag.
		{ sub_cat_id: 50, cat: 'Real Estate', sub_cat: 'Residential', market_value: 75000 },
		{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 30 } // Unsorted, present too
	];
	// The stray target on Real Estate — DB-admissible, must never surface.
	const targets = new Map<number, number>([[50, 40]]);

	const result = computeNonReAllocation(taxonomy, marketValueRows, targets);

	it('precondition: Real Estate\'s value is genuinely the dominant one (a non-marginal divergence if the guard broke)', () => {
		expect(75000).toBeGreaterThan(200 + 30);
	});

	it('groups stay EXACTLY the canonical four — Real Estate is excluded, not appended as an "unknown Cat" (the two round-2 mechanisms are distinct code paths)', () => {
		expect(result.groups.map((g) => g.cat)).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives']);
	});

	it('Real Estate renders in no group, at no grain, and its stray target never surfaces anywhere', () => {
		const anyRealEstate = result.groups.some(
			(g) => g.rows.some((r) => r.sub_cat_id === 50 || r.sub_cat === 'Residential')
		);
		expect(anyRealEstate).toBe(false);
		// The 40% target would have produced a dollar_target of (0.4 * total_non_re) somewhere if it
		// had leaked through any row; no row in the output carries that shape at all since Real
		// Estate has no row to attach it to.
		const cash = result.groups.find((g) => g.cat === 'Cash')!.rows.find((r) => r.sub_cat === 'FDIC')!;
		expect(cash.pct_target).toBe(0); // Cash's own (unset) target, not Real Estate's 40%
	});

	it('QA paired assertion: TotalNonRE excludes Real Estate entirely, and Σ(rendered $Alloc incl. Unsorted) = TotalNonRE exactly', () => {
		expect(result.total_non_re).toBe(230); // 200 + 30 — NOT 75200, NOT 75230
		const renderedSum =
			result.groups.reduce((s, g) => s + g.rows.reduce((rs, r) => rs + r.dollar_alloc, 0), 0) +
			(result.unsorted?.dollar_alloc ?? 0);
		expect(renderedSum).toBe(result.total_non_re);
		const subtotalSum =
			result.groups.reduce((s, g) => s + g.dollar_alloc_subtotal, 0) + (result.unsorted?.dollar_alloc ?? 0);
		expect(subtotalSum).toBe(renderedSum);
	});
});
