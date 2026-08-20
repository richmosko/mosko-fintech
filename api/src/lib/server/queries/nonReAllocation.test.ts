// nonReAllocation.test.ts — pure-core coverage for computeNonReAllocation (no I/O; mirrors
// pendingSymbols.ts's computePendingIds precedent). Originally SELF-238; REWORKED at SELF-239
// (2026-08-20 ratified ACs) alongside the compute core itself. Exercises AC1 (four Cat-group
// headers, Liabilities never rendered), AC2 (element='asset' row set incl. zero-held rows), AC2a/
// AC5 (twelve-row collapse, carried forward unchanged), AC2b (Real Estate exclusion), AC2c/AC3
// (Unsorted row + structurally-null target cells), AC3 (the five-column formulas + the
// same-predicate denominator fix — a liability-element row with real market_value must NOT enter
// TotalNonRE), AC4 (per-group + grand footing, incl. the new subtotal fields), AC6 (ratio columns
// null — not 0/NaN — when TotalNonRE <= 0; $Alloc always present regardless), plus the SEC
// carry-forward guard (a stray liability-element planning_target row must not re-enter the row set
// or the denominator).
//
// SEC HARDENING ROUND 2 (2026-08-20, F/CTO-adopted, post-push review) — two more describe blocks
// near the bottom of this file: (a) an asset-element Sub-Cat under a Cat OUTSIDE the canonical
// four renders as an APPENDED group (never silently dropped while still counted in the
// denominator — the union fix), and (b) Real Estate carrying a REAL, nonzero market_value is
// excluded from both the row set and TotalNonRE — the existing AC2b test above only ever gave
// Real Estate a zero value, which cannot distinguish "excluded" from "excluded and also
// coincidentally zero."

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

/** A small, representative taxonomy catalog — NOT the full 041 seed. The compute core doesn't
 *  care which specific rows exist, only how it merges/groups/collapses whatever it's given, so a
 *  lean fixture exercises the same logic paths as the full seed would. Every row now carries
 *  `element` (085) — the SELF-239 rework's row-set/denominator predicate. */
const TAXONOMY: TaxonomySubCatRow[] = [
	{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
	{ id: 2, cat: 'Cash', sub_cat: 'Cash Balances', display_order: 5, element: 'asset' },
	{ id: 3, cat: 'Bonds', sub_cat: 'IGL', display_order: 50, element: 'asset' },
	{ id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', display_order: 100, element: 'asset' },
	{ id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', display_order: 110, element: 'asset' },
	{ id: 20, cat: 'Marketable Securities', sub_cat: 'UNKNOWN', display_order: 90, element: 'asset' },
	{ id: 30, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240, element: 'asset' },
	{ id: 40, cat: 'Liabilities', sub_cat: 'Credit-Balance', display_order: 290, element: 'liability' },
	{ id: 50, cat: 'Real Estate', sub_cat: 'Residential', display_order: 320, element: 'asset' }
];

describe('computeNonReAllocation — a populated portfolio', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
		{ sub_cat_id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 500 },
		{ sub_cat_id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', market_value: 300 },
		// AC3 fix under test: 076 returns BOTH elements (085's catalog comment) — a liability
		// cash-route row (081's shape) carrying REAL market_value. Pre-SELF-239 this summed
		// straight into total_non_re; it must NOT any more.
		{ sub_cat_id: 40, cat: 'Liabilities', sub_cat: 'Credit-Balance', market_value: 5000 },
		{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 200 } // Unsorted
	];
	const targets = new Map<number, number>([
		[1, 20], // FDIC target 20%
		[10, 5], // US-01 target 5%
		[11, 3], // US-02 target 3%
		// SEC carry-forward: a stray liability-element planning_target row (the write endpoint has
		// no element check — N7-A is render-only). Must never re-enter the row set or the
		// denominator.
		[40, 10]
	]);

	const result = computeNonReAllocation(TAXONOMY, marketValueRows, targets);

	it('AC3: TotalNonRE EXCLUDES the liability-element row\'s market_value, even though 076 returned it', () => {
		expect(result.total_non_re).toBe(2000); // 1000 + 500 + 300 + 200 — NOT +5000
	});

	it('AC1: exactly four Cat-group headers, PRD order, Liabilities never present', () => {
		expect(result.groups.map((g) => g.cat)).toEqual([
			'Cash',
			'Bonds',
			'Marketable Securities',
			'Alternatives'
		]);
	});

	it('AC2b: Real Estate is entirely absent — no group, no row, anywhere', () => {
		const anyRealEstate = result.groups.some(
			(g) => (g.cat as unknown) === 'Real Estate' || g.rows.some((r) => r.cat === 'Real Estate')
		);
		expect(anyRealEstate).toBe(false);
	});

	it('SEC carry-forward: the stray liability-element planning_target row (id 40) renders NOWHERE — no group, no row, no leaked target', () => {
		const anyLiability = result.groups.some(
			(g) => g.rows.some((r) => r.sub_cat_id === 40 || r.sub_cat === 'Credit-Balance')
		);
		expect(anyLiability).toBe(false);
		// And its $5000 market_value / 10% target never surfaces in any total or subtotal either.
		expect(result.total_non_re).not.toBe(7000);
		for (const g of result.groups) expect(g.dollar_alloc_subtotal).not.toBe(5000);
	});

	it('AC2: a zero-held, zero-target seeded Sub-Cat still renders with zeros (not omitted)', () => {
		const bonds = result.groups.find((g) => g.cat === 'Bonds')!;
		expect(bonds.rows).toHaveLength(1);
		expect(bonds.rows[0]).toMatchObject({
			sub_cat: 'IGL',
			pct_target: 0,
			pct_alloc: 0,
			dollar_target: 0,
			dollar_alloc: 0,
			dollar_realloc: 0
		});
	});

	it('AC3: a normal held row computes all five columns correctly (FDIC)', () => {
		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		const fdic = cash.rows.find((r) => r.sub_cat === 'FDIC')!;
		expect(fdic.pct_alloc).toBe(50); // 1000/2000*100
		expect(fdic.pct_target).toBe(20);
		expect(fdic.dollar_target).toBe(400); // 20% of 2000
		expect(fdic.dollar_alloc).toBe(1000);
		expect(fdic.dollar_realloc).toBe(-600); // 400 - 1000, overweight (negative)
	});

	it('Cash group is sorted by display_order (Cash Balances=5 before FDIC=10)', () => {
		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		expect(cash.rows.map((r) => r.sub_cat)).toEqual(['Cash Balances', 'FDIC']);
	});

	it('AC2a/AC5: the twelve US-equity rows collapse into ONE "US - Sector Diversified" row, no individual US-0x rows', () => {
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		const subCats = equity.rows.map((r) => r.sub_cat);
		expect(subCats).not.toContain('US-01-Basic_Materials');
		expect(subCats).not.toContain('US-02-Telecom');
		expect(subCats).toContain('US - Sector Diversified');
		expect(subCats).toContain('UNKNOWN'); // non-US-equity Marketable Securities Sub-Cat renders individually

		const collapsed = equity.rows.find((r) => r.sub_cat === 'US - Sector Diversified')!;
		expect(collapsed.sub_cat_id).toBeNull();
		expect(collapsed.kind).toBe('us_sector_diversified');
		expect(collapsed.dollar_alloc).toBe(800); // 500 + 300
		expect(collapsed.pct_target).toBe(8); // 5 + 3 (Σ the twelve's target_percent)
		expect(collapsed.dollar_target).toBe(160); // 8% of 2000
		expect(collapsed.pct_alloc).toBe(40); // 800/2000*100
	});

	it('the collapsed row sorts at position 100 (UNKNOWN=90 before it)', () => {
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.rows.map((r) => r.sub_cat)).toEqual(['UNKNOWN', 'US - Sector Diversified']);
	});

	it('AC2c/AC3: the Unsorted row carries %Alloc/$Alloc only — target cells structurally null, never 0', () => {
		expect(result.unsorted).not.toBeNull();
		expect(result.unsorted!.kind).toBe('unsorted');
		expect(result.unsorted!.sub_cat_id).toBeNull();
		expect(result.unsorted!.cat).toBeNull();
		expect(result.unsorted!.dollar_alloc).toBe(200);
		expect(result.unsorted!.pct_alloc).toBe(10); // 200/2000*100
		expect(result.unsorted!.pct_target).toBeNull();
		expect(result.unsorted!.dollar_target).toBeNull();
		expect(result.unsorted!.dollar_realloc).toBeNull();
	});

	it('AC4: per-group dollar_alloc_subtotal + pct_alloc_subtotal are correct', () => {
		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		expect(cash.dollar_alloc_subtotal).toBe(1000); // FDIC only, Cash Balances is 0
		expect(cash.pct_alloc_subtotal).toBe(50);

		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.dollar_alloc_subtotal).toBe(800); // collapsed row only, UNKNOWN is 0
		expect(equity.pct_alloc_subtotal).toBe(40);

		const bonds = result.groups.find((g) => g.cat === 'Bonds')!;
		expect(bonds.dollar_alloc_subtotal).toBe(0);
		expect(bonds.pct_alloc_subtotal).toBe(0);

		const alternatives = result.groups.find((g) => g.cat === 'Alternatives')!;
		expect(alternatives.dollar_alloc_subtotal).toBe(0);
		expect(alternatives.pct_alloc_subtotal).toBe(0);
	});

	it('AC4: the four Cat subtotals plus Unsorted foot to TotalNonRE exactly', () => {
		const groupSum = result.groups.reduce((s, g) => s + g.dollar_alloc_subtotal, 0);
		const footed = groupSum + (result.unsorted?.dollar_alloc ?? 0);
		expect(footed).toBe(result.total_non_re);
	});
});

describe('computeNonReAllocation — AC6: TotalNonRE <= 0 unsets every ratio-derived column, never zeros or NaN', () => {
	it('AC7 empty portfolio (076 returns zero rows): full enumeration renders, ratio columns are null, dollar_alloc is 0 (real, not unset)', () => {
		const result = computeNonReAllocation(TAXONOMY, [], new Map());
		expect(result.total_non_re).toBe(0);
		expect(result.unsorted).toBeNull();

		for (const group of result.groups) {
			expect(group.dollar_alloc_subtotal).toBe(0);
			expect(group.pct_alloc_subtotal).toBeNull();
			for (const row of group.rows) {
				expect(row.pct_alloc).toBeNull();
				expect(row.pct_target).toBeNull();
				expect(row.dollar_target).toBeNull();
				expect(row.dollar_realloc).toBeNull();
				expect(row.dollar_alloc).toBe(0);
				expect(Number.isNaN(row.dollar_alloc)).toBe(false);
			}
		}

		// The collapsed row still renders (zeroed $Alloc, null ratios), and Real Estate/Liabilities
		// are still absent.
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.rows.map((r) => r.sub_cat)).toContain('US - Sector Diversified');
		expect(result.groups.map((g) => g.cat)).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives']);
	});

	it('a negative TotalNonRE (net-negative asset-element cash) also nulls every ratio column, while dollar_alloc stays real', () => {
		const negativeRows: SubcatMarketValueRow[] = [
			{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: -50 }
		];
		const result = computeNonReAllocation(TAXONOMY, negativeRows, new Map([[1, 20]]));
		expect(result.total_non_re).toBe(-50);

		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		const fdic = cash.rows.find((r) => r.sub_cat === 'FDIC')!;
		expect(fdic.dollar_alloc).toBe(-50);
		expect(fdic.pct_alloc).toBeNull();
		expect(fdic.pct_target).toBeNull();
		expect(fdic.dollar_target).toBeNull();
		expect(fdic.dollar_realloc).toBeNull();
		expect(cash.dollar_alloc_subtotal).toBe(-50);
		expect(cash.pct_alloc_subtotal).toBeNull();
	});
});

describe('computeNonReAllocation — no held value anywhere but a real taxonomy catalog with no US-equity rows', () => {
	it('a caller with zero US-equity Sub-Cats in their taxonomy still gets a zero-valued collapsed row', () => {
		const noEquityTaxonomy = TAXONOMY.filter((t) => t.cat !== 'Marketable Securities');
		const result = computeNonReAllocation(noEquityTaxonomy, [], new Map());
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.rows).toHaveLength(1);
		expect(equity.rows[0]).toMatchObject({ sub_cat: 'US - Sector Diversified', dollar_alloc: 0, pct_target: null });
	});
});

describe('computeNonReAllocation — SEC HARDENING ROUND 2 (a): an asset-element Cat outside the canonical four is APPENDED, never silently dropped', () => {
	const taxonomyWithUnknownCat: TaxonomySubCatRow[] = [
		...TAXONOMY,
		{ id: 60, cat: 'Crypto', sub_cat: 'BTC-Direct', display_order: 400, element: 'asset' }
	];
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
		{ sub_cat_id: 60, cat: 'Crypto', sub_cat: 'BTC-Direct', market_value: 500 }
	];
	const result = computeNonReAllocation(taxonomyWithUnknownCat, marketValueRows, new Map());

	it('the unrecognized Cat is APPENDED after the canonical four — never dropped', () => {
		expect(result.groups.map((g) => g.cat)).toEqual([
			'Cash',
			'Bonds',
			'Marketable Securities',
			'Alternatives',
			'Crypto'
		]);
	});

	it('the appended group\'s row and subtotal carry the real value, and it counts in TotalNonRE — no coverage divergence in this direction either', () => {
		expect(result.total_non_re).toBe(1500); // 1000 + 500, the unrecognized Cat's value included
		const crypto = result.groups.find((g) => g.cat === 'Crypto')!;
		expect(crypto.rows).toHaveLength(1);
		expect(crypto.rows[0]).toMatchObject({ sub_cat: 'BTC-Direct', dollar_alloc: 500 });
		expect(crypto.dollar_alloc_subtotal).toBe(500);
		expect(crypto.pct_alloc_subtotal).toBeCloseTo((500 / 1500) * 100);
	});

	it('every rendered group\'s subtotal (canonical four PLUS the appended one) feeds Unsorted foots to TotalNonRE exactly', () => {
		const groupSum = result.groups.reduce((s, g) => s + g.dollar_alloc_subtotal, 0);
		const footed = groupSum + (result.unsorted?.dollar_alloc ?? 0);
		expect(footed).toBe(result.total_non_re);
	});
});

describe('computeNonReAllocation — SEC HARDENING ROUND 2 (b): Real Estate with a REAL nonzero market_value is excluded from the row set AND TotalNonRE', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
		// Real Estate (id 50) carrying a real, large, nonzero value — 076 should never emit this
		// (p_include_real_estate:false elsewhere), but this module's OWN predicate must not depend
		// on that: if it ever did leak through, it must still be excluded here.
		{ sub_cat_id: 50, cat: 'Real Estate', sub_cat: 'Residential', market_value: 250000 }
	];
	const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map());

	it('TotalNonRE excludes the Real Estate value entirely — not 251000', () => {
		expect(result.total_non_re).toBe(1000);
	});

	it('Real Estate renders in no group, at no grain — no row, no subtotal contribution, anywhere', () => {
		expect(result.groups.map((g) => g.cat)).not.toContain('Real Estate');
		const anyRealEstateRow = result.groups.some((g) => g.rows.some((r) => r.sub_cat_id === 50 || r.cat === 'Real Estate'));
		expect(anyRealEstateRow).toBe(false);
	});
});
