// nonReAllocation.test.ts — SELF-238 pure-core coverage for computeNonReAllocation (no I/O;
// mirrors pendingSymbols.ts's computePendingIds precedent). Exercises AC2 (full enumeration incl.
// zero-held rows), AC2a/AC5 (twelve-row collapse), AC2b (Real Estate exclusion), AC2c/AC3
// (Unsorted row + structurally-null target cells), AC3 (the five-column formulas), AC4 (footing
// — total_non_re = Σ every 076 row, unfiltered), AC7 (empty portfolio → zeros, no Unsorted, no
// error/NaN).

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

/** A small, representative taxonomy catalog — NOT the full 041 seed. The compute core doesn't
 *  care which specific rows exist, only how it merges/groups/collapses whatever it's given, so a
 *  lean fixture exercises the same logic paths as the full seed would. */
const TAXONOMY: TaxonomySubCatRow[] = [
	{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10 },
	{ id: 2, cat: 'Cash', sub_cat: 'Cash Balances', display_order: 5 },
	{ id: 3, cat: 'Bonds', sub_cat: 'IGL', display_order: 50 },
	{ id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', display_order: 100 },
	{ id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', display_order: 110 },
	{ id: 20, cat: 'Marketable Securities', sub_cat: 'UNKNOWN', display_order: 90 },
	{ id: 30, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240 },
	{ id: 40, cat: 'Liabilities', sub_cat: 'Credit-Balance', display_order: 290 },
	{ id: 50, cat: 'Real Estate', sub_cat: 'Residential', display_order: 320 }
];

describe('computeNonReAllocation — a populated portfolio', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
		{ sub_cat_id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 500 },
		{ sub_cat_id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', market_value: 300 },
		{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 200 } // Unsorted
	];
	const targets = new Map<number, number>([
		[1, 20], // FDIC target 20%
		[10, 5], // US-01 target 5%
		[11, 3], // US-02 target 3%
		[40, 10] // Liabilities/Credit-Balance target 10% — real target on a ZERO-HELD row
	]);

	const result = computeNonReAllocation(TAXONOMY, marketValueRows, targets);

	it('AC4: total_non_re foots to the UNFILTERED sum of every 076 row, Unsorted included', () => {
		expect(result.total_non_re).toBe(2000); // 1000 + 500 + 300 + 200
	});

	it('AC2b: Real Estate is entirely absent — no group, no row, anywhere', () => {
		const anyRealEstate = result.groups.some(
			(g) => g.cat === ('Real Estate' as unknown) || g.rows.some((r) => r.cat === 'Real Estate')
		);
		expect(anyRealEstate).toBe(false);
		expect(result.groups.map((g) => g.cat)).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives', 'Liabilities']);
	});

	it('AC2: a zero-held row with a REAL target still renders — target ≠ 0 is a real fact even at zero alloc', () => {
		const liabilities = result.groups.find((g) => g.cat === 'Liabilities')!;
		const creditBalance = liabilities.rows.find((r) => r.sub_cat === 'Credit-Balance')!;
		expect(creditBalance.dollar_alloc).toBe(0);
		expect(creditBalance.pct_target).toBe(10);
		expect(creditBalance.dollar_target).toBe(200); // 10% of 2000
		expect(creditBalance.dollar_realloc).toBe(200); // 200 - 0, underweight
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
});

describe('computeNonReAllocation — AC7 empty portfolio', () => {
	it('076 returns zero rows → full enumeration renders, every value is 0 (never NaN), no Unsorted row', () => {
		const result = computeNonReAllocation(TAXONOMY, [], new Map());
		expect(result.total_non_re).toBe(0);
		expect(result.unsorted).toBeNull();

		for (const group of result.groups) {
			for (const row of group.rows) {
				expect(row.pct_alloc).toBe(0);
				expect(Number.isNaN(row.pct_alloc)).toBe(false);
				expect(row.dollar_alloc).toBe(0);
				expect(row.dollar_target).toBe(0);
				expect(row.dollar_realloc).toBe(0);
			}
		}

		// The collapsed row still renders (zeros), and Real Estate is still absent.
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.rows.map((r) => r.sub_cat)).toContain('US - Sector Diversified');
		expect(result.groups.map((g) => g.cat)).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives', 'Liabilities']);
	});
});

describe('computeNonReAllocation — no held value anywhere but a real taxonomy catalog with no US-equity rows', () => {
	it('a caller with zero US-equity Sub-Cats in their taxonomy still gets a zero-valued collapsed row', () => {
		const noEquityTaxonomy = TAXONOMY.filter((t) => t.cat !== 'Marketable Securities');
		const result = computeNonReAllocation(noEquityTaxonomy, [], new Map());
		const equity = result.groups.find((g) => g.cat === 'Marketable Securities')!;
		expect(equity.rows).toHaveLength(1);
		expect(equity.rows[0]).toMatchObject({ sub_cat: 'US - Sector Diversified', dollar_alloc: 0, pct_target: 0 });
	});
});
