// staleness-cross-surface-consistency.server.test.ts — SELF-243 QA pass, cross-surface parity
// check between §2.2.2's per-row staleness fold (nonReAllocation.ts, SELF-330) and §2.2.3's
// (usEquityAllocation.ts, SELF-243). No I/O — pure-core, same posture as both modules' own
// *.staleness.server.test.ts files, which this one deliberately does NOT duplicate.
//
// WHAT THIS CHECKS, AND WHY IT ISN'T ALREADY COVERED. Both modules resolve per-row staleness via
// the SAME single-id lookup shape (walk a Sub-Cat's contributing accounts, TRUE if any is in the
// caller's stale set, FALSE if none/no contributors, UNKNOWN if the root/bridge read itself was
// unknown) — nonReAllocation.ts's private `subCatIsStale` and usEquityAllocation.ts's private
// `rowIsStale` are two SEPARATE implementations of that same rule (not a shared function; each
// module's own header says so explicitly), because usEquityAllocation.ts also carries the
// `sub_cat_id === null` "missing from taxonomy" guard nonReAllocation.ts's regular-row path never
// needs. Two independent implementations of one rule is exactly the shape that CAN silently
// diverge — a future edit to either one's dominance order, defaulting, or lookup key would not be
// caught by either module's own staleness test file, because each only exercises itself.
//
// THE SPECIFIC PROPERTY: §2.2.2's collapsed "US - Sector Diversified" row Kleene-ORs the SAME
// twelve Sub-Cat ids §2.2.3 renders as individual rows (nonReAllocation.ts's own AC11 header:
// "it is the Kleene-OR of the twelve real answers" — not a separate contributor lookup). So, given
// the IDENTICAL (subCatAccountIds, staleAccountIds) inputs and the IDENTICAL twelve taxonomy rows:
//
//   §2.2.2's collapsed row is_stale  MUST equal  kleeneOr(§2.2.3's twelve rows' is_stale)
//
// This is the "same bridge, same grain" parity the SELF-330 discipline established at the DB layer
// (fn_subcat_contributors / fn_subcat_market_value's sub_cat_id set equality), applied here at the
// APP layer between the two TS folds that consume that same bridge. Deliberately scoped narrower
// than a DB-level parity battery: this is vitest, proportionate to what's actually shared here (a
// dominance-order rule implemented twice), not a re-derivation of the pgTAP-level contributor-map
// parity SELF-330 already owns.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import { computeUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import type { SubcatMarketValueRow } from './subcatMarketValue';

/** Local re-implementation of the Kleene-OR dominance order BOTH modules' own headers document
 *  (true > unknown > false) — deliberately re-derived from the documented RULE, not imported from
 *  either module's private fold, so this test does not simply restate whichever implementation it
 *  is checking against. */
function kleeneOr(values: ReadonlyArray<boolean | null>): boolean | null {
	if (values.some((v) => v === true)) return true;
	if (values.some((v) => v === null)) return null;
	return false;
}

// The twelve US-equity taxonomy rows, ids 101..112 (offset from the 1..12 range each module's OWN
// staleness test file already uses, so a copy-paste id collision can't accidentally make this test
// pass by aliasing onto a different fixture's ids). Shared verbatim between both compute calls —
// not two separately-constructed "equivalent" fixtures, which could themselves silently diverge.
const SHARED_TAXONOMY: TaxonomySubCatRow[] = US_EQUITY_SUB_CATS.map((sub_cat, i) => ({
	id: 101 + i,
	cat: 'Marketable Securities',
	sub_cat,
	display_order: 100 + i * 10,
	element: 'asset'
}));

const SHARED_MARKET_VALUE_ROWS: SubcatMarketValueRow[] = SHARED_TAXONOMY.map((t) => ({
	sub_cat_id: t.id,
	cat: t.cat,
	sub_cat: t.sub_cat,
	market_value: 100 // uniform, nonzero — value itself is irrelevant to is_stale, only presence matters
}));

function collapsedRowIsStale(result: ReturnType<typeof computeNonReAllocation>): boolean | null {
	const g = result.groups.find((g) => g.cat === 'Marketable Securities')!;
	const found = g.rows.find((r) => r.kind === 'us_sector_diversified');
	if (!found) throw new Error('collapsed row not found');
	return found.is_stale;
}

describe('§2.2.2 collapsed-row fold vs §2.2.3 per-row fold — cross-surface staleness parity (SELF-243)', () => {
	it('TRUE dominance agrees: one stale contributor anywhere in the twelve makes BOTH surfaces read TRUE for that population', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[101, new Set(['acct-stale'])], // US-01-Basic_Materials — the ONE stale contributor
			[105, new Set(['acct-fresh'])] // US-05-Energy — confirmed not stale, present so the fold isn't vacuous
		]);
		const staleAccountIds = new Set(['acct-stale']);

		const nonRe = computeNonReAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, staleAccountIds);
		const usEquity = computeUsEquityAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, staleAccountIds);

		expect(collapsedRowIsStale(nonRe)).toBe(true);
		expect(kleeneOr(usEquity.rows.map((r) => r.is_stale))).toBe(true);
		expect(collapsedRowIsStale(nonRe)).toBe(kleeneOr(usEquity.rows.map((r) => r.is_stale)));
	});

	it('FALSE agrees: a known root with every contributor confirmed-not-stale (or none) makes BOTH surfaces read FALSE', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[102, new Set(['acct-fresh-1'])],
			[103, new Set(['acct-fresh-2'])]
			// the other ten ids: no contributors at all — vacuous fold, also FALSE
		]);
		const staleAccountIds = new Set<string>(); // known root, nothing stale tenant-wide

		const nonRe = computeNonReAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, staleAccountIds);
		const usEquity = computeUsEquityAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, staleAccountIds);

		expect(collapsedRowIsStale(nonRe)).toBe(false);
		expect(kleeneOr(usEquity.rows.map((r) => r.is_stale))).toBe(false);
		expect(collapsedRowIsStale(nonRe)).toBe(kleeneOr(usEquity.rows.map((r) => r.is_stale)));
	});

	it('UNKNOWN dominance agrees: staleAccountIds === null (root/bridge unknown) makes BOTH surfaces read NULL, never a silent FALSE on either side', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([[104, new Set(['acct-x'])]]);

		const nonRe = computeNonReAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, null);
		const usEquity = computeUsEquityAllocation(SHARED_TAXONOMY, SHARED_MARKET_VALUE_ROWS, new Map(), subCatAccountIds, null);

		expect(collapsedRowIsStale(nonRe)).toBeNull();
		expect(kleeneOr(usEquity.rows.map((r) => r.is_stale))).toBeNull();
		// Every individual §2.2.3 row, not just the fold, must be null uniformly — this is the
		// "UNKNOWN propagates to every row, never mixed with a resolved value" contract both
		// modules' own headers state independently; checked here as the cross-surface instance.
		for (const row of usEquity.rows) expect(row.is_stale).toBeNull();
	});

	it('the missing-from-taxonomy guard (§2.2.3-only) does not break parity: a US-equity label absent from the caller\'s taxonomy contributes FALSE to the fold on BOTH surfaces, never inherits the Unsorted-row null-key entry', () => {
		// Drop US-01-Basic_Materials (id 101) from the taxonomy read entirely — §2.2.3 renders it
		// with sub_cat_id: null (AC1's documented edge case); §2.2.2's collapsed row simply never
		// includes id 101 among "the twelve real answers" since its own taxonomy read produced no
		// row for it either. The contributor map's null key (the Unsorted-row population) carries a
		// stale contributor — proving NEITHER surface misattributes it onto the missing label.
		const partialTaxonomy = SHARED_TAXONOMY.filter((t) => t.id !== 101);
		const partialMarketValueRows = SHARED_MARKET_VALUE_ROWS.filter((r) => r.sub_cat_id !== 101);
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[null, new Set(['acct-unsorted'])], // Unsorted-row contributors — unrelated to the twelve
			[106, new Set(['acct-fresh'])]
		]);
		const staleAccountIds = new Set(['acct-unsorted']);

		const nonRe = computeNonReAllocation(partialTaxonomy, partialMarketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		const usEquity = computeUsEquityAllocation(partialTaxonomy, partialMarketValueRows, new Map(), subCatAccountIds, staleAccountIds);

		const missingRow = usEquity.rows.find((r) => r.sub_cat === 'US-01-Basic_Materials')!;
		expect(missingRow.sub_cat_id).toBeNull();
		expect(missingRow.is_stale).toBe(false); // never inherited the Unsorted null-key's TRUE
		expect(collapsedRowIsStale(nonRe)).toBe(false); // the eleven present ids are all non-stale too
		expect(collapsedRowIsStale(nonRe)).toBe(kleeneOr(usEquity.rows.map((r) => r.is_stale)));
	});
});
