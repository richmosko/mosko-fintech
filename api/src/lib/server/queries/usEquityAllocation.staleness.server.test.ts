// usEquityAllocation.staleness.server.test.ts — pure-core coverage for SELF-243's per-row
// staleness fold inside computeUsEquityAllocation (no I/O — same posture as
// usEquityAllocation.test.ts / nonReAllocation.staleness.server.test.ts, which this file mirrors
// in shape). Exercises the module header's + UsEquityRow.is_stale's own doc-comment binding fold
// semantics:
//   (1) a row's is_stale is a single-id lookup against its own contributing accounts — TRUE if at
//       least one is in the stale set, FALSE if every contributor resolves confirmed-not-stale or
//       there are none (vacuous fold). No Kleene-OR-across-many-ids fold exists here — unlike
//       nonReAllocation.ts's collapsed row, every row in this table already has its own real
//       sub_cat_id (or null — see (2) below), never a synthetic id standing in for several;
//   (2) a row whose sub_cat_id is null (AC1's "missing from the caller's own taxonomy" edge case)
//       is ALWAYS false-when-known — it must NEVER be looked up against subCatAccountIds' `null`
//       key, which (as nonReAllocation.ts's loadSubCatContributors populates it) holds the
//       tenant's UNSORTED-row contributors, a wholly unrelated population. The sharpest test below
//       proves this by populating the map's null key with a stale contributor and asserting the
//       missing-from-taxonomy row does NOT inherit it;
//   (3) staleAccountIds === null (the caller's root `046` read, or the contributor/account bridge,
//       was itself unknown) collapses EVERY row's is_stale to null uniformly — including a
//       missing-from-taxonomy (sub_cat_id === null) row, which must resolve to null-not-false in
//       that state (the same "unknown wins over vacuous" dominance nonReAllocation.ts's
//       subCatIsStale establishes for its own null-keyed Unsorted row);
//   (4) the producer contract: is_stale is ALWAYS `true | false | null`, never `undefined` — even
//       at computeUsEquityAllocation's own three-argument call shape (every pre-SELF-243 call site
//       in usEquityAllocation.test.ts), which now defaults to the same "unknown, nothing supplied"
//       degrade computeNonReAllocation's own optional params already establish.

import { describe, it, expect } from 'vitest';
import { computeUsEquityAllocation } from './usEquityAllocation';
import { US_EQUITY_SUB_CATS } from './usEquitySubCats';
import type { SubcatMarketValueRow } from './subcatMarketValue';

/** Taxonomy rows for all twelve, ids 1..12 in canonical order (mirrors usEquityAllocation.test.ts's
 *  FULL_TAXONOMY). US-01-Basic_Materials -> id 1, US-02-Telecom -> id 2. */
const FULL_TAXONOMY = US_EQUITY_SUB_CATS.map((sub_cat, i) => ({ id: i + 1, sub_cat }));

/** A partial taxonomy dropping US-01-Basic_Materials (id 1) — exercises the "missing from the
 *  caller's own taxonomy" edge case (AC1), where the row's sub_cat_id renders null. */
const PARTIAL_TAXONOMY = FULL_TAXONOMY.slice(1);

const marketValueRows: SubcatMarketValueRow[] = [
	{ sub_cat_id: 1, cat: 'Marketable Securities', sub_cat: 'US-01-Basic_Materials', market_value: 100 },
	{ sub_cat_id: 2, cat: 'Marketable Securities', sub_cat: 'US-02-Telecom', market_value: 300 }
];

function rowFor(result: ReturnType<typeof computeUsEquityAllocation>, sub_cat: string) {
	const found = result.rows.find((r) => r.sub_cat === sub_cat);
	if (!found) throw new Error(`row ${sub_cat} not found`);
	return found;
}

describe('computeUsEquityAllocation — SELF-243 per-row staleness fold', () => {
	it('a row is TRUE when at least one of its contributing accounts is in the stale set', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([[1, new Set(['acct-100'])]]);
		const staleAccountIds = new Set(['acct-100']);
		const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(rowFor(result, 'US-01-Basic_Materials').is_stale).toBe(true);
	});

	it('a row is FALSE when every contributing account resolves confirmed-not-stale', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([[2, new Set(['acct-200'])]]);
		const staleAccountIds = new Set(['acct-999']); // acct-200 not in the stale set
		const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		expect(rowFor(result, 'US-02-Telecom').is_stale).toBe(false);
	});

	it('a row with NO contributors is FALSE (vacuous fold) — never null, never true', () => {
		const staleAccountIds = new Set<string>(); // known root, empty
		const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, new Map(), new Map(), staleAccountIds);
		expect(rowFor(result, 'US-06-Financials').is_stale).toBe(false);
	});

	it('SHARPEST CASE — a row missing from the caller\'s own taxonomy (sub_cat_id null) is FALSE and does NOT inherit the contributor map\'s null-keyed Unsorted-row entry, even when that entry IS stale', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[null, new Set(['acct-unsorted'])] // the tenant's Unsorted-row contributors — unrelated
		]);
		const staleAccountIds = new Set(['acct-unsorted']); // stale for Unsorted, NOT for anything in this table
		const result = computeUsEquityAllocation(PARTIAL_TAXONOMY, marketValueRows, new Map(), subCatAccountIds, staleAccountIds);
		const missing = rowFor(result, 'US-01-Basic_Materials');
		expect(missing.sub_cat_id).toBeNull(); // precondition: this is genuinely the missing-from-taxonomy row
		expect(missing.is_stale).toBe(false); // NOT true — must never have looked up the null key
	});

	it('staleAccountIds === null (root/bridge unknown) collapses EVERY row — including a missing-from-taxonomy row — to null uniformly, never false', () => {
		const subCatAccountIds = new Map<number | null, ReadonlySet<string>>([
			[2, new Set(['acct-200'])],
			[null, new Set(['acct-unsorted'])]
		]);
		const result = computeUsEquityAllocation(PARTIAL_TAXONOMY, marketValueRows, new Map(), subCatAccountIds, null);
		expect(rowFor(result, 'US-02-Telecom').is_stale).toBeNull();
		expect(rowFor(result, 'US-01-Basic_Materials').is_stale).toBeNull(); // missing-from-taxonomy row too — unknown dominates vacuous
	});

	it('producer contract: omitting the two new arguments (every pre-SELF-243 call shape) degrades every row to is_stale=null, never undefined', () => {
		const result = computeUsEquityAllocation(FULL_TAXONOMY, marketValueRows, new Map());
		for (const row of result.rows) {
			expect(row.is_stale).toBeNull();
			expect(row.is_stale).not.toBeUndefined();
		}
	});
});
