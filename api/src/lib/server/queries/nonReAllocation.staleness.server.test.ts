// nonReAllocation.staleness.server.test.ts — pure-core coverage for SELF-330's per-Sub-Cat
// staleness fold inside computeNonReAllocation (no I/O — same posture as nonReAllocation.test.ts).
// Exercises the AC11 doc-comment's binding fold semantics:
//   (1) a regular row's is_stale is Kleene-OR over its own contributing accounts (true dominates;
//       false only when every contributor resolves confirmed-not-stale, or there are none);
//   (2) the "US - Sector Diversified" collapsed row OR-folds across its twelve underlying real
//       Sub-Cat ids' OWN folds, not a separate contributor lookup;
//   (3) the Unsorted row matches its contributors by a literal `null` key (sub_cat_id IS NULL),
//       never by coercing into an equality lookup against a real id;
//   (4) staleAccountIds === null (the caller's root `046` read, or the contributor/account bridge,
//       was itself unknown) collapses EVERY row's is_stale to null uniformly — never a partial or
//       silently-fresh table, and never "unknown folds to false" for the collapsed row either;
//   (5) the producer contract: is_stale is ALWAYS `true | false | null`, never `undefined` — even
//       at computeNonReAllocation's own two-argument call shape (every pre-SELF-330 call site in
//       this suite), which now defaults to the same "unknown, nothing supplied" degrade.

import { describe, it, expect } from 'vitest';
import { computeNonReAllocation, type TaxonomySubCatRow } from './nonReAllocation';
import type { SubcatMarketValueRow } from './subcatMarketValue';

const TAXONOMY: TaxonomySubCatRow[] = [
	{ id: 1, cat: 'Cash', sub_cat: 'FDIC', display_order: 10, element: 'asset' },
	{ id: 3, cat: 'Bonds', sub_cat: 'IGL', display_order: 50, element: 'asset' },
	{ id: 7, cat: 'Alternatives', sub_cat: 'REIT', display_order: 240, element: 'asset' },
	{ id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', display_order: 100, element: 'asset' },
	{ id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', display_order: 110, element: 'asset' }
];

const marketValueRows: SubcatMarketValueRow[] = [
	{ sub_cat_id: 1, cat: 'Cash', sub_cat: 'FDIC', market_value: 1000 },
	{ sub_cat_id: 3, cat: 'Bonds', sub_cat: 'IGL', market_value: 400 },
	{ sub_cat_id: 7, cat: 'Alternatives', sub_cat: 'REIT', market_value: 100 },
	{ sub_cat_id: 10, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 500 },
	{ sub_cat_id: 11, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', market_value: 300 },
	{ sub_cat_id: null, cat: null, sub_cat: null, market_value: 200 } // Unsorted
];

function rowById(result: ReturnType<typeof computeNonReAllocation>, id: number) {
	for (const g of result.groups) {
		const found = g.rows.find((r) => r.sub_cat_id === id);
		if (found) return found;
	}
	throw new Error(`row ${id} not found`);
}

function collapsedRow(result: ReturnType<typeof computeNonReAllocation>) {
	const g = result.groups.find((g) => g.cat === 'Marketable Securities')!;
	const found = g.rows.find((r) => r.kind === 'us_sector_diversified');
	if (!found) throw new Error('collapsed row not found');
	return found;
}

describe('computeNonReAllocation — SELF-330 per-Sub-Cat staleness fold', () => {
	it('a regular row is TRUE when at least one of its contributing accounts is in the stale set', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([[1, new Set(['acct-100'])]]);
		const staleAccountIds = new Set(['acct-100']);
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(rowById(result, 1).is_stale).toBe(true);
	});

	it('a regular row is FALSE when every contributing account resolves confirmed-not-stale', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([[3, new Set(['acct-200'])]]);
		const staleAccountIds = new Set(['acct-999']); // acct-200 not in the stale set
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(rowById(result, 3).is_stale).toBe(false);
	});

	it('a regular row with NO contributors is FALSE (vacuous fold) — never null, never true', () => {
		const staleAccountIds = new Set<string>(); // known root, empty
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), new Map(), staleAccountIds);
		expect(rowById(result, 7).is_stale).toBe(false);
	});

	it('the collapsed "US - Sector Diversified" row is TRUE if EITHER underlying real Sub-Cat is stale', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[10, new Set(['acct-us1'])], // stale
			[11, new Set(['acct-us2'])] // not stale
		]);
		const staleAccountIds = new Set(['acct-us1']);
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(collapsedRow(result).is_stale).toBe(true);
	});

	it('the collapsed row is FALSE when neither underlying real Sub-Cat is stale', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[10, new Set(['acct-us1'])],
			[11, new Set(['acct-us2'])]
		]);
		const staleAccountIds = new Set<string>(); // known root, nothing stale
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(collapsedRow(result).is_stale).toBe(false);
	});

	it('the Unsorted row matches contributors keyed on a literal null (sub_cat_id IS NULL), not by falling through to a real id', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[null, new Set(['acct-unsorted'])],
			[1, new Set(['acct-100'])] // a real-id contributor that must NOT leak into Unsorted's fold
		]);
		const staleAccountIds = new Set(['acct-unsorted']); // stale for Unsorted, NOT for id 1's contributor
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(result.unsorted?.is_stale).toBe(true);
		expect(rowById(result, 1).is_stale).toBe(false); // its own contributor (acct-100) is not stale
	});

	it('staleAccountIds === null (root/bridge unknown) collapses EVERY row — regular, collapsed, and Unsorted — to null uniformly, never false', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[1, new Set(['acct-100'])],
			[10, new Set(['acct-us1'])],
			[11, new Set(['acct-us2'])],
			[null, new Set(['acct-unsorted'])]
		]);
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map(), subCatAccountIds, null);
		expect(rowById(result, 1).is_stale).toBeNull();
		expect(rowById(result, 3).is_stale).toBeNull();
		expect(collapsedRow(result).is_stale).toBeNull();
		expect(result.unsorted?.is_stale).toBeNull();
	});

	it('producer contract: omitting the two new arguments (every pre-SELF-330 call shape) degrades every row to is_stale=null, never undefined', () => {
		const result = computeNonReAllocation(TAXONOMY, marketValueRows, new Map());
		for (const g of result.groups) {
			for (const r of g.rows) {
				expect(r.is_stale).toBeNull();
				expect(r.is_stale).not.toBeUndefined();
			}
		}
		expect(result.unsorted?.is_stale).toBeNull();
	});
});
