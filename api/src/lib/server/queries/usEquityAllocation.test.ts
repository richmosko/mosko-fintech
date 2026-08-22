// usEquityAllocation.test.ts — SELF-240 pure-core coverage for computeUsEquityAllocation (no
// I/O; mirrors nonReAllocation.test.ts / pendingSymbols.ts's computePendingIds precedent).
// Exercises AC1 (exactly twelve, canonical order, all cat='Marketable Securities', no cash/Unsorted possible by
// construction), AC3 (total.dollar_alloc = Σ the twelve — the drill-down-identity anchor), AC4/β
// (display-layer renormalization formulas), AC7 (determinism), and — per SELF-332 / ADR-061 —
// ALL THREE rows of ADR-061 Decision 3's reachable-states table (`valuePositive` /
// `targetsPositive`, the latter a CONJUNCTION on `totalUsEquity > 0 && sumTargets > 0`, not an
// independent guard). The dedicated negative-total watcher lives in the separately-named
// `usEquityAllocation.negativeDenominatorWatcher.server.test.ts`, mirroring
// `nonReAllocation.negativeDenominatorWatcher.server.test.ts`'s own split.

import { describe, it, expect } from 'vitest';
import { computeUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import type { SubcatMarketValueRow } from './subcatMarketValue';

/** Taxonomy rows for all twelve, ids 1..12 in canonical order — a realistic provisioned-user
 *  shape. Some tests use a SUBSET to exercise the "missing from taxonomy" edge case. */
const FULL_TAXONOMY = US_EQUITY_SUB_CATS.map((sub_cat, i) => ({ id: i + 1, sub_cat }));

describe('computeUsEquityAllocation — AC1 row-set shape', () => {
	it('always emits exactly twelve rows, in US_EQUITY_SUB_CATS canonical order, all cat=Marketable Securities', () => {
		const result = computeUsEquityAllocation(FULL_TAXONOMY, [], new Map());
		expect(result.rows).toHaveLength(12);
		expect(result.rows.map((r) => r.sub_cat)).toEqual(US_EQUITY_SUB_CATS);
		expect(result.rows.every((r) => r.cat === 'Marketable Securities')).toBe(true);
	});

	it('a Sub-Cat missing from the caller\'s own taxonomy still renders (AC1 "regardless"), as zero-held/zero-target', () => {
		const partial = FULL_TAXONOMY.slice(1); // drop US-01-Basic_Materials
		const result = computeUsEquityAllocation(partial, [], new Map());
		expect(result.rows).toHaveLength(12);
		const missing = result.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		expect(missing.sub_cat_id).toBeNull();
		expect(missing.dollar_alloc).toBe(0);
	});
});

describe('computeUsEquityAllocation — a populated, non-degenerate portfolio', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 100 },
		{ sub_cat_id: 6, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: 300 },
		{
			sub_cat_id: 9,
			cat: 'Marketable Securities',
			sub_cat: 'US-09-Information_Technology',
			market_value: 600
		}
		// remaining nine Sub-Cats zero-held
	];
	const targets = new Map<number, number>([
		[1, 5], // US-01 raw target 5% (of Total Non-RE, 074 semantics)
		[6, 10], // US-06 raw target 10%
		[9, 5] // US-09 raw target 5%
		// Σ = 20; remaining nine Sub-Cats zero-target
	]);

	const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, targets);

	it('AC3: total.dollar_alloc = Σ the twelve\'s market_value — the drill-down-identity anchor', () => {
		expect(result.total.dollar_alloc).toBe(1000); // 100 + 300 + 600
		const summed = result.rows.reduce((s, r) => s + r.dollar_alloc, 0);
		expect(summed).toBe(result.total.dollar_alloc);
	});

	it('AC4/β: %Alloc is against Total US Equity (1000), not Total Non-RE', () => {
		const us09 = result.rows.find((r) => r.sub_cat === 'US-09-Information_Technology')!;
		expect(us09.pct_alloc).toBe(60); // 600/1000*100
		expect(us09.dollar_alloc).toBe(600);
	});

	it('AC4/β: %Target displayed is target_percent RENORMALIZED against Σ the twelve (20), not against 100', () => {
		const us06 = result.rows.find((r) => r.sub_cat === 'US-06-Financials')!;
		expect(us06.pct_target).toBe(50); // 10/20*100 — NOT the raw 10
		expect(us06.dollar_target).toBe(500); // 50% of Total US Equity (1000)
		expect(us06.dollar_realloc).toBe(200); // 500 - 300, underweight
	});

	it('a zero-held, zero-target Sub-Cat renders zeros/nulls-where-guarded consistently', () => {
		const us02 = result.rows.find((r) => r.sub_cat === 'US-02-Telecom')!;
		expect(us02.dollar_alloc).toBe(0);
		expect(us02.pct_alloc).toBe(0); // 0/1000*100 = 0, NOT null — total is nonzero here
		expect(us02.pct_target).toBe(0); // 0/20*100 = 0, NOT null — Σtargets is nonzero here
		expect(us02.dollar_target).toBe(0);
		expect(us02.dollar_realloc).toBe(0);
	});

	it('total row: pct_alloc and pct_target are exactly 100 when non-degenerate', () => {
		expect(result.total.pct_alloc).toBe(100);
		expect(result.total.pct_target).toBe(100);
		expect(result.total.dollar_target).toBe(1000);
		expect(result.total.dollar_realloc).toBe(0);
	});

	it('AC7: determinism — identical inputs produce a byte-identical result on repeat calls', () => {
		const again = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, targets);
		expect(again).toEqual(result);
	});
});

describe('computeUsEquityAllocation — ADR-061 Decision 3 row 3: Total US Equity = 0, targets present', () => {
	// Targets ARE present (Σtargets > 0), but `targetsPositive` is a CONJUNCTION on
	// `totalUsEquity > 0 && sumTargets > 0` (ADR-061 Decision 2) — a zero Total US Equity nulls the
	// target-derived group TOO, not just pct_alloc. This replaces the pre-ADR-061 "independent
	// guards" expectation, which was the shipped SELF-240 defect Sec F-2 flagged.
	const targets = new Map<number, number>([[1, 5], [6, 10]]);
	const result = computeUsEquityAllocation(FULL_TAXONOMY, [], targets);

	it('every row: dollar_alloc=0 (never null/gated), pct_alloc=null, AND pct_target/dollar_target/dollar_realloc=null (never NaN)', () => {
		for (const row of result.rows) {
			expect(row.dollar_alloc).toBe(0);
			expect(row.pct_alloc).toBeNull();
			expect(row.pct_target).toBeNull();
			expect(row.dollar_target).toBeNull();
			expect(row.dollar_realloc).toBeNull();
		}
	});

	it('total row: dollar_alloc=0, every ratio-derived column null', () => {
		expect(result.total.dollar_alloc).toBe(0);
		expect(result.total.pct_alloc).toBeNull();
		expect(result.total.pct_target).toBeNull();
		expect(result.total.dollar_target).toBeNull();
		expect(result.total.dollar_realloc).toBeNull();
	});
});

describe('computeUsEquityAllocation — ADR-061 Decision 3 row 2: holdings present, Σtargets = 0', () => {
	// Holdings ARE present (Total US Equity > 0) and sumTargets = 0 — the ONE state where the two
	// gate groups genuinely diverge: `valuePositive` is true (pct_alloc/dollar_alloc real) while
	// `targetsPositive` is false (target group null), because the conjunction's first half is
	// satisfied and its second half is not. This is the "holdings present, no planning targets set"
	// default-new-tenant state ADR-061 Decision 3 names as the load-bearing reason for NOT nulling
	// pct_alloc whenever either denominator is degenerate.
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 500 }
	];
	const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, new Map());

	it('every row: pct_target/dollar_target/dollar_realloc are null (never NaN); pct_alloc/dollar_alloc UNAFFECTED', () => {
		for (const row of result.rows) {
			expect(row.pct_target).toBeNull();
			expect(row.dollar_target).toBeNull();
			expect(row.dollar_realloc).toBeNull();
		}
		const us01 = result.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		expect(us01.dollar_alloc).toBe(500);
		expect(us01.pct_alloc).toBe(100); // 500/500*100
	});

	it('total row: pct_target/dollar_target/dollar_realloc null; dollar_alloc/pct_alloc still real', () => {
		expect(result.total.pct_target).toBeNull();
		expect(result.total.dollar_target).toBeNull();
		expect(result.total.dollar_realloc).toBeNull();
		expect(result.total.dollar_alloc).toBe(500);
		expect(result.total.pct_alloc).toBe(100);
	});
});

describe('computeUsEquityAllocation — ADR-061 Decision 3 row 3: fully empty (both denominators zero)', () => {
	it('every numeric field is 0 or null, never NaN/Infinity, no error', () => {
		const result = computeUsEquityAllocation(FULL_TAXONOMY, [], new Map());
		for (const row of result.rows) {
			expect(row.dollar_alloc).toBe(0);
			expect(row.pct_alloc).toBeNull();
			expect(row.pct_target).toBeNull();
			expect(row.dollar_target).toBeNull();
			expect(row.dollar_realloc).toBeNull();
		}
		expect(result.total).toEqual({
			dollar_alloc: 0,
			pct_alloc: null,
			pct_target: null,
			dollar_target: null,
			dollar_realloc: null
		});
	});
});
