// nonReAllocation.displayOrderNull.server.test.ts — SELF-239 regression-edge coverage: display_order
// NULL-handling. QA-owned (per the sibling *.server.test.ts files in this directory), covering a
// gap neither nonReAllocation.test.ts (Backend's regression suite) nor the SELF-239 rework touched
// — `display_order` is `number | null` (009) and computeNonReAllocation's sort key has always been
// `t.display_order ?? 0`, unchanged by SELF-239, but no existing fixture in this directory ever
// supplies a null display_order: every TAXONOMY fixture row carries a real number. A stated rule
// with no fixture exercising its null branch is unverified, not merely untested — this file
// exercises it.
//
// THE RULE UNDER TEST, stated once so a future reader doesn't have to infer it from a `??`:
// display_order NULL sorts as if it were EXACTLY 0 — not "sorts first", not "sorts last", not
// "excluded from sorting". Proven by sandwiching a null row between a real negative display_order
// and a real positive one: only the "=0" reading places it in the middle: a "null sorts first"
// implementation would put it ahead of the negative row; a "null sorts last" implementation would
// put it after the positive row; both are distinguishable from "=0" only with a real negative value
// present, which is why this fixture includes one even though 009's live seed data is unlikely to
// ever carry a negative display_order — the assertion is about the IMPLEMENTATION's rule, not about
// what the seed currently contains.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

describe('display_order NULL-handling — sorts as exactly 0, not first, not last, not excluded', () => {
	const taxonomy: TaxonomySubCatRow[] = [
		{ id: 1, cat: 'Cash', sub_cat: 'Positive-Order', display_order: 10, element: 'asset' },
		{ id: 2, cat: 'Cash', sub_cat: 'Null-Order', display_order: null, element: 'asset' },
		{ id: 3, cat: 'Cash', sub_cat: 'Negative-Order', display_order: -5, element: 'asset' }
	];
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'Positive-Order', market_value: 100 },
		{ sub_cat_id: 2, cat: 'Cash', sub_cat: 'Null-Order', market_value: 100 },
		{ sub_cat_id: 3, cat: 'Cash', sub_cat: 'Negative-Order', market_value: 100 }
	];

	it('a null display_order sorts BETWEEN a real negative and a real positive value — i.e. as exactly 0, per the `?? 0` rule', () => {
		const result = computeNonReAllocation(taxonomy, marketValueRows, new Map());
		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		expect(cash.rows.map((r) => r.sub_cat)).toEqual(['Negative-Order', 'Null-Order', 'Positive-Order']);
	});

	it('the null-display_order row still renders fully (not a partial/degraded row) — the null affects sort position only, no other field', () => {
		const result = computeNonReAllocation(taxonomy, marketValueRows, new Map([[2, 25]]));
		const nullOrderRow = result.groups.find((g) => g.cat === 'Cash')!.rows.find((r) => r.sub_cat === 'Null-Order')!;
		expect(nullOrderRow.dollar_alloc).toBe(100);
		expect(nullOrderRow.pct_target).toBe(25);
		expect(nullOrderRow.sub_cat_id).toBe(2);
	});
});
