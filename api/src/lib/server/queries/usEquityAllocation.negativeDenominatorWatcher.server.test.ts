// usEquityAllocation.negativeDenominatorWatcher.server.test.ts — SELF-332 / ADR-061, the
// DEDICATED Sec-condition watcher for the §2.2.3 US Equity sub-allocation core, mirroring
// nonReAllocation.negativeDenominatorWatcher.server.test.ts's own shape and rationale for
// computeUsEquityAllocation. Authored INDEPENDENTLY of Backend's own pure-core regression suite
// (usEquityAllocation.test.ts), which carries the ADR-061 Decision 3 reachable-states coverage as
// part of its own suite. That coverage stands; this file is not a duplicate of it. It exists as
// the DEDICATED, separately-named watcher for the negative-total property — so a future refactor
// of usEquityAllocation.test.ts (Backend's regression suite, not a security fence) cannot silently
// drop the negative-denominator property without also breaking a file whose name says what it
// guards.
//
// THE VULNERABILITY THIS WATCHES, PER SEC F-2 (PR #520) AND ADR-061'S CONTEXT SECTION: the
// SHIPPED SELF-240 code guarded `pct_alloc` on `totalUsEquity === 0` alone and the three
// target-derived columns on a SEPARATE `sumTargets === 0` — both NaN guards, neither `<= 0`. A
// NEGATIVE `totalUsEquity` passed BOTH guards un-gated: `pct_alloc` renders a real, sign-flipped
// percentage, and — because `sumTargets` can be positive even when `totalUsEquity` is negative —
// the three target-derived columns ALSO rendered real numbers, compounding the sign inversion into
// `$Target`/`$ReAlloc`. No fixture in the shipped suite supplied a negative total; that is why the
// defect survived (ADR-061 Consequences: "A green suite before the change is not evidence the
// change is unnecessary.").
//
// THE FIX, PER ADR-061 DECISION 2/3: exactly two gate booleans, `valuePositive = totalUsEquity > 0`
// and `targetsPositive = totalUsEquity > 0 && sumTargets > 0`. Because `targetsPositive` is a
// CONJUNCTION that includes `totalUsEquity > 0`, a negative (or zero) total nulls BOTH gate groups
// together — `pct_alloc` AND all three target-derived columns — even when `sumTargets` alone is
// positive. That conjunction is the exact property this file watches; it is NOT implied by testing
// either gate in isolation (Decision 3's rows 2 and 3 are both needed to see it).
//
// ⚠ EXPLICITLY NOT A Σ%=100 ASSERTION, mirroring the nonReAllocation watcher's own instruction: no
// sum-of-percentages check appears anywhere in this file. The only assertions below are per-column
// nullness / realness, which a sign-inverted-but-internally-consistent table cannot satisfy.
//
// WHAT THIS FILE ADDS BEYOND usEquityAllocation.test.ts'S OWN COVERAGE:
//   (1) a MULTI-ROW, MIXED-SIGN negative total from REAL holdings (not a single row, not an empty
//       portfolio), WITH real positive targets set on the same rows — the fixture that isolates the
//       `targetsPositive` conjunction, since `sumTargets` alone is positive here;
//   (2) the BOUNDARY-EXACT case: totalUsEquity = 0 reached via two REAL, CANCELLING positions
//       (+500 / -500), again with real positive targets, proving the conjunction holds at the exact
//       boundary too, not merely for the strictly-negative case above;
//   (3) an explicit re-derivation of the PRE-ADR-061 (shipped SELF-240) formula against the SAME
//       negative-total fixture, to prove BY CONTRAST that the vulnerability was real and the current
//       code does not exhibit it.

import { describe, it, expect } from 'vitest';
import { computeUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import type { SubcatMarketValueRow } from './subcatMarketValue';

const FULL_TAXONOMY = US_EQUITY_SUB_CATS.map((sub_cat, i) => ({ id: i + 1, sub_cat }));

describe('ADR-061 watcher — Total US Equity < 0, non-vacuous multi-row fixture, targets positive', () => {
	// US-01 +200, US-06 -900, US-09 +100 → total -600. Real, populated holdings on three separate
	// Sub-Cats — not a single-row minimal case, not an empty portfolio. Targets are ALSO real and
	// their sum (80) is positive — isolating the `targetsPositive` conjunction from `valuePositive`.
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 200 },
		{ sub_cat_id: 6, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: -900 },
		{ sub_cat_id: 9, cat: 'Marketable Securities', sub_cat: 'US-09-Information_Technology', market_value: 100 }
	];
	const targets = new Map<number, number>([
		[1, 30],
		[6, 40],
		[9, 10]
	]);
	const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, targets);
	const totalUsEquity = result.total.dollar_alloc;

	it('non-vacuous precondition: Total US Equity is genuinely negative, from real holdings, not an artifact of an empty fixture', () => {
		expect(totalUsEquity).toBe(-600);
	});

	it('non-vacuous precondition: Σtargets is genuinely positive (80) — the conjunction, not a vacuous sumTargets=0 case, is what this fixture isolates', () => {
		expect([...targets.values()].reduce((s, v) => s + v, 0)).toBe(80);
	});

	it('every held row renders null pct_alloc — never a sign-inverted number', () => {
		for (const row of result.rows) {
			expect(row.pct_alloc, `${row.sub_cat}.pct_alloc must be null, not a sign-inverted number`).toBeNull();
		}
	});

	it('every row renders null pct_target/dollar_target/dollar_realloc too — the targetsPositive CONJUNCTION, not sumTargets alone', () => {
		for (const row of result.rows) {
			expect(row.pct_target, `${row.sub_cat}.pct_target must be null despite Σtargets > 0`).toBeNull();
			expect(row.dollar_target, `${row.sub_cat}.dollar_target must be null despite Σtargets > 0`).toBeNull();
			expect(row.dollar_realloc, `${row.sub_cat}.dollar_realloc must be null despite Σtargets > 0`).toBeNull();
		}
	});

	it('dollar_alloc (raw market value, and the totals row) stays REAL and correctly signed — never null, never gated', () => {
		const us01 = result.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		const us06 = result.rows.find((r) => r.sub_cat === 'US-06-Financials')!;
		const us09 = result.rows.find((r) => r.sub_cat === 'US-09-Information_Technology')!;
		expect(us01.dollar_alloc).toBe(200);
		expect(us06.dollar_alloc).toBe(-900);
		expect(us09.dollar_alloc).toBe(100);
		expect(totalUsEquity).toBe(-600);
	});

	it('total row: every ratio-derived column null, dollar_alloc real', () => {
		expect(result.total.pct_alloc).toBeNull();
		expect(result.total.pct_target).toBeNull();
		expect(result.total.dollar_target).toBeNull();
		expect(result.total.dollar_realloc).toBeNull();
		expect(result.total.dollar_alloc).toBe(-600);
	});

	it('CONTRAST: the pre-ADR-061 (shipped SELF-240) split-guard formula WOULD have produced real, plausible-looking numbers on this exact fixture — demonstrating what this watcher actually guards against', () => {
		const sumTargets: number = 80;
		const oldPctAlloc = (marketValue: number) =>
			totalUsEquity === 0 ? 0 : (marketValue / totalUsEquity) * 100; // shipped guard: === 0, not <= 0
		const oldTargetRatio = (targetPercent: number) => (sumTargets === 0 ? null : targetPercent / sumTargets); // shipped guard: independent of totalUsEquity's sign

		const oldUs01PctAlloc = oldPctAlloc(200);
		const oldUs06PctAlloc = oldPctAlloc(-900);
		expect(Number.isFinite(oldUs01PctAlloc)).toBe(true);
		expect(oldUs01PctAlloc).toBeLessThan(0); // -33.33...% — a real, sign-inverted number the shipped guard would not have caught
		expect(Number.isFinite(oldUs06PctAlloc)).toBe(true);
		expect(oldUs06PctAlloc).toBeGreaterThan(0); // +150% — equally plausible-looking, equally wrong

		const oldUs01TargetRatio = oldTargetRatio(30);
		expect(oldUs01TargetRatio).not.toBeNull(); // shipped guard renders a real target ratio even at a negative total
		expect(oldUs01TargetRatio).toBeCloseTo(30 / 80, 6);
		const oldUs01DollarTarget = oldUs01TargetRatio! * totalUsEquity; // negative dollar target — the compounding Sec described
		expect(oldUs01DollarTarget).toBeLessThan(0);

		// The current code nulls all four for the same row.
		const us01 = result.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		expect(us01.pct_alloc).toBeNull();
		expect(us01.pct_target).toBeNull();
		expect(us01.dollar_target).toBeNull();
	});
});

describe('ADR-061 watcher boundary — Total US Equity = 0 reached via REAL cancelling positions, targets positive', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 500 },
		{ sub_cat_id: 6, cat: 'Marketable Securities', sub_cat: 'US-06-Financials', market_value: -500 }
	];
	const targets = new Map<number, number>([[1, 25]]);
	const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, targets);

	it('Total US Equity is exactly 0, non-vacuously (real holdings cancel, not "no data"), Σtargets is genuinely positive', () => {
		expect(result.total.dollar_alloc).toBe(0);
		const held = result.rows.filter((r) => r.dollar_alloc !== 0);
		expect(held.length, 'this leg is vacuous unless at least one row is genuinely held').toBeGreaterThan(0);
		expect([...targets.values()].reduce((s, v) => s + v, 0)).toBeGreaterThan(0);
	});

	it('every ratio-derived column is null at the exact Total US Equity=0 boundary too — including the target group, despite Σtargets > 0', () => {
		const us01 = result.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		expect(us01.dollar_alloc).toBe(500);
		expect(us01.pct_alloc).toBeNull();
		expect(us01.pct_target).toBeNull();
		expect(us01.dollar_target).toBeNull();
		expect(us01.dollar_realloc).toBeNull();
		expect(result.total.pct_alloc).toBeNull();
		expect(result.total.pct_target).toBeNull();
		expect(result.total.dollar_target).toBeNull();
		expect(result.total.dollar_realloc).toBeNull();
	});
});
