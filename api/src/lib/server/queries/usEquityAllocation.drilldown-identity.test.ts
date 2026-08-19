// usEquityAllocation.drilldown-identity.test.ts — SELF-240 AC3, the ratified cross-module
// invariant: "the table's total-row $Alloc MUST equal the §2.2.2 collapsed 'US - Sector
// Diversified' row's $Alloc exactly." Runs BOTH SELF-238's computeNonReAllocation and SELF-240's
// computeUsEquityAllocation against the SAME synthetic fixture (same market-value rows, same
// targets, same taxonomy) and asserts the two independently-computed numbers agree exactly — no
// tolerance, per AC3/AC7's own "asserted exactly, no hedge" framing.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import { computeUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import type { SubcatMarketValueRow } from './subcatMarketValue';

describe('AC3 drill-down identity — 238 collapsed row vs 240 total row', () => {
	it('exact equality against a mixed portfolio (US-equity holdings + non-US-equity Non-RE holdings)', () => {
		const taxonomy: TaxonomySubCatRow[] = [
			{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10 },
			{ id: 2, cat: 'Bonds', sub_cat: 'IGL', display_order: 50 },
			...US_EQUITY_SUB_CATS.map((sub_cat, i) => ({
				id: 10 + i,
				cat: 'Marketable Securities',
				sub_cat,
				display_order: 100 + i * 10
			}))
		];
		const marketValueRows: SubcatMarketValueRow[] = [
			{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 5000 }, // non-US-equity — must NOT leak into either total
			{ sub_cat_id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 400 },
			{ sub_cat_id: 15, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: 900 },
			{ sub_cat_id: 21, cat: 'Marketable Securities', sub_cat: 'US-Growth-Non_Sector', market_value: 300 }
		];
		const targets = new Map<number, number>([
			[10, 5],
			[15, 15],
			[21, 5]
		]);

		const allocation238 = computeNonReAllocation(taxonomy, marketValueRows, targets);
		const equity238 = allocation238.groups.find((g) => g.cat === 'Marketable Securities')!;
		const collapsed238 = equity238.rows.find((r) => r.kind === 'us_sector_diversified')!;

		const usEquityTaxonomy = taxonomy
			.filter((t) => t.cat === 'Marketable Securities')
			.map((t) => ({ id: t.id, sub_cat: t.sub_cat }));
		const allocation240 = computeUsEquityAllocation(usEquityTaxonomy, marketValueRows, targets);

		expect(collapsed238.dollar_alloc).toBe(1600); // 400 + 900 + 300
		expect(allocation240.total.dollar_alloc).toBe(1600);
		expect(allocation240.total.dollar_alloc).toBe(collapsed238.dollar_alloc); // the ratified identity, exact
	});

	it('exact equality holds at the degenerate zero-holdings boundary too (both sides land on 0)', () => {
		const taxonomy: TaxonomySubCatRow[] = US_EQUITY_SUB_CATS.map((sub_cat, i) => ({
			id: i + 1,
			cat: 'Marketable Securities',
			sub_cat,
			display_order: 100 + i * 10
		}));
		const allocation238 = computeNonReAllocation(taxonomy, [], new Map());
		const equity238 = allocation238.groups.find((g) => g.cat === 'Marketable Securities')!;
		const collapsed238 = equity238.rows.find((r) => r.kind === 'us_sector_diversified')!;

		const usEquityTaxonomy = taxonomy.map((t) => ({ id: t.id, sub_cat: t.sub_cat }));
		const allocation240 = computeUsEquityAllocation(usEquityTaxonomy, [], new Map());

		expect(collapsed238.dollar_alloc).toBe(0);
		expect(allocation240.total.dollar_alloc).toBe(0);
	});
});
