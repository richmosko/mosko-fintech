// nonReAllocation.negativeDenominatorWatcher.server.test.ts — SELF-239 AC7, the MANDATORY
// Sec-condition watcher. QA-owned (per the sibling *.server.test.ts files in this directory —
// nonReAllocation.tenant-isolation / nonReAllocation.catGroupOrderEquality), authored INDEPENDENTLY
// of Backend's own pure-core regression suite (nonReAllocation.test.ts), which already carries a
// single-row negative-total case as part of its own AC6 coverage. That case stands; this file is
// not a duplicate of it and does not re-test the same fixture shape. It exists as the DEDICATED,
// separately-named Sec gate for AC7 — so a future refactor of nonReAllocation.test.ts (which is
// Backend's regression suite, not a security fence) cannot silently drop the negative-denominator
// property without also breaking a file whose name says what it guards.
//
// THE VULNERABILITY THIS WATCHES, VERBATIM FROM SEC'S 2026-08-17 FINDING (SELF-239 comment 2):
// "under a negative total the module renders a complete, error-free, SIGN-INVERTED table (positive
// assets → negative %Alloc, liabilities → positive; $Target/$ReAlloc compound it). Both ratified
// invariants (Σ%=100, AC4's Σ$Alloc identity) HOLD on the inverted table — no existing test can
// catch it." The ratified fix (F/CTO, 2026-08-18, option A): when TotalNonRE <= 0, every
// ratio-derived column renders null (never a number, never NaN/Infinity), $Alloc stays real.
//
// ⚠ EXPLICITLY NOT A Σ%=100 ASSERTION, PER SEC'S OWN INSTRUCTION (AC7 ratified text): "passes on
// the inverted table too." No sum-of-percentages check appears anywhere in this file — the only
// assertions below are per-column nullness / realness, which a sign-inverted-but-internally-
// consistent table CANNOT satisfy (a sign-inverted %Alloc is a real, non-null number; the fix
// requires null).
//
// WHAT THIS FILE ADDS BEYOND nonReAllocation.test.ts's OWN negative-total case (that case is a
// single held row, -50, alone — a minimal but not fully adversarial fixture):
//   (1) a MULTI-ROW, MIXED-SIGN negative total from REAL asset holdings (not a single row, not an
//       empty portfolio) — the shape closest to Sec's actual described scenario (a tenant whose
//       liability balances exceed asset holdings; here modelled entirely in-domain, via ordinary
//       asset-element rows, since 076's liability-route contribution is already excluded from
//       TotalNonRE by SELF-239's element predicate — this file tests the DEGENERATE-DENOMINATOR
//       fence, not the element-exclusion fence, which nonReAllocation.test.ts's own SEC
//       carry-forward test already covers);
//   (2) the BOUNDARY-EXACT case: TotalNonRE = 0 reached via two REAL, CANCELLING positions (+500 /
//       -500), not the vacuous "076 returned zero rows" case nonReAllocation.test.ts already
//       covers under its own AC7-empty-portfolio test. A gate written as `totalNonRe !== 0` and one
//       written as `!holdings.length` both look identical on an empty portfolio; they diverge
//       exactly here, and only a non-vacuous zero can tell them apart;
//   (3) an explicit re-derivation of the OLD (pre-SELF-239) formula (`safeAllocFraction`'s
//       `totalNonRe === 0 ? 0 : ratio`) against the SAME negative-total fixture, to prove BY
//       CONTRAST that the vulnerability is real and the current code does not exhibit it — a
//       watcher that never shows what failure it would have caught is not fully honest about what
//       it proves.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

const TAXONOMY: TaxonomySubCatRow[] = [
	{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
	{ id: 2, cat: 'Bonds', sub_cat: 'IGL', display_order: 50, element: 'asset' },
	{ id: 3, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240, element: 'asset' }
];

describe('AC7 — MANDATORY Sec-condition watcher: TotalNonRE < 0, non-vacuous multi-row fixture', () => {
	// Cash +200, Bonds -900, Alternatives +100 → total -600. Real, populated holdings on three
	// separate Sub-Cats — not a single-row minimal case, not an empty portfolio.
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 200 },
		{ sub_cat_id: 2, cat: 'Bonds', sub_cat: 'IGL', market_value: -900 },
		{ sub_cat_id: 3, cat: 'Alternatives', sub_cat: 'REIT', market_value: 100 }
	];
	const targets = new Map<number, number>([
		[1, 30],
		[2, 40],
		[3, 10]
	]);
	const result = computeNonReAllocation(TAXONOMY, marketValueRows, targets);

	it('non-vacuous precondition: TotalNonRE is genuinely negative, from real holdings, not an artifact of an empty fixture', () => {
		expect(result.total_non_re).toBe(-600);
	});

	it('every held row renders null ratio columns — never a sign-inverted number', () => {
		for (const group of result.groups) {
			for (const row of group.rows) {
				expect(row.pct_alloc, `${row.sub_cat}.pct_alloc must be null, not a sign-inverted number`).toBeNull();
				expect(row.pct_target, `${row.sub_cat}.pct_target must be null`).toBeNull();
				expect(row.dollar_target, `${row.sub_cat}.dollar_target must be null`).toBeNull();
				expect(row.dollar_realloc, `${row.sub_cat}.dollar_realloc must be null`).toBeNull();
			}
		}
	});

	it('$Alloc (raw market value, and its subtotal) stays REAL and correctly signed on every row and group — AC6\'s always-present half', () => {
		const cash = result.groups.find((g) => g.cat === 'Cash')!;
		const bonds = result.groups.find((g) => g.cat === 'Bonds')!;
		const alternatives = result.groups.find((g) => g.cat === 'Alternatives')!;
		expect(cash.rows.find((r) => r.sub_cat === 'FDIC')!.dollar_alloc).toBe(200);
		expect(bonds.rows.find((r) => r.sub_cat === 'IGL')!.dollar_alloc).toBe(-900);
		expect(alternatives.rows.find((r) => r.sub_cat === 'REIT')!.dollar_alloc).toBe(100);
		expect(cash.dollar_alloc_subtotal).toBe(200);
		expect(bonds.dollar_alloc_subtotal).toBe(-900);
		expect(alternatives.dollar_alloc_subtotal).toBe(100);
		// Every group's pct_alloc_subtotal, meanwhile, is null — the same gate as the row level.
		expect(cash.pct_alloc_subtotal).toBeNull();
		expect(bonds.pct_alloc_subtotal).toBeNull();
		expect(alternatives.pct_alloc_subtotal).toBeNull();
	});

	it('CONTRAST: the pre-SELF-239 formula WOULD have produced real, plausible-looking (sign-inverted) percentages on this exact fixture — demonstrating what this watcher actually guards against', () => {
		const oldFormula = (marketValue: number, totalNonRe: number) =>
			totalNonRe === 0 ? 0 : (marketValue / totalNonRe) * 100;
		const oldFdicPctAlloc = oldFormula(200, -600);
		const oldBondsPctAlloc = oldFormula(-900, -600);
		expect(Number.isFinite(oldFdicPctAlloc)).toBe(true);
		expect(oldFdicPctAlloc).toBeLessThan(0); // -33.33...% — a real number, not NaN, not caught by any NaN guard
		expect(Number.isFinite(oldBondsPctAlloc)).toBe(true);
		expect(oldBondsPctAlloc).toBeGreaterThan(0); // +150% — equally plausible-looking, equally wrong
		const cash = result.groups.find((g) => g.cat === 'Cash')!.rows.find((r) => r.sub_cat === 'FDIC')!;
		const bonds = result.groups.find((g) => g.cat === 'Bonds')!.rows.find((r) => r.sub_cat === 'IGL')!;
		expect(cash.pct_alloc).toBeNull();
		expect(bonds.pct_alloc).toBeNull();
	});
});

describe('AC7 boundary — TotalNonRE = 0 reached via REAL cancelling positions (not an empty portfolio)', () => {
	const marketValueRows: SubcatMarketValueRow[] = [
		{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 500 },
		{ sub_cat_id: 2, cat: 'Bonds', sub_cat: 'IGL', market_value: -500 }
	];
	const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map([[1, 50]]));

	it('total_non_re is exactly 0, non-vacuously (real holdings cancel, not "no data")', () => {
		expect(result.total_non_re).toBe(0);
		const held = result.groups.flatMap((g) => g.rows).filter((r) => r.dollar_alloc !== 0);
		expect(held.length, 'this leg is vacuous unless at least one row is genuinely held').toBeGreaterThan(0);
	});

	it('ratio columns are null at the exact TotalNonRE=0 boundary too, not merely for the strictly-negative case above', () => {
		const cash = result.groups.find((g) => g.cat === 'Cash')!.rows.find((r) => r.sub_cat === 'FDIC')!;
		expect(cash.dollar_alloc).toBe(500);
		expect(cash.pct_alloc).toBeNull();
		expect(cash.pct_target).toBeNull();
		expect(cash.dollar_target).toBeNull();
		expect(cash.dollar_realloc).toBeNull();
	});
});
