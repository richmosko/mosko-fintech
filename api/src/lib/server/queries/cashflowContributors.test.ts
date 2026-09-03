// cashflowContributors.test.ts — pure-core coverage for SELF-258's §2.3.2 per-row (Sub-Cat)
// staleness fold (computeCashflowRowStaleness). No I/O — mirrors
// nonReAllocation.staleness.server.test.ts's own precedent, applied to the (cat, sub_cat)-keyed
// shape this surface uses instead of a bare sub_cat_id.
//
// Exercises the module header's binding fold semantics:
//   (1) a row's is_stale is Kleene-OR over its own contributing accounts (TRUE dominates; else
//       UNKNOWN dominates FALSE; FALSE only when every contributor resolves confirmed-not-stale);
//   (2) `account_name IS NULL` folds that ONE contributor to UNKNOWN before `staleAccountIds` is
//       ever consulted for it — the branch with no nonReAllocation.ts precedent;
//   (3) `staleAccountIds === null` (root `046` read, or this bridge, itself unknown) returns the
//       EMPTY map — never a partial or per-row-mixed result;
//   (4) the UNCLASSIFIED contributor set (sub_cat_id IS NULL) and the V1-dormant third-taxonomy
//       state (sub_cat_id NOT NULL, cat/sub_cat both NULL) are both excluded from the map — neither
//       is a row the rollup ever renders;
//   (5) staleAccountNames is populated (distinct, sorted) ONLY when is_stale === true, and is
//       always [] otherwise — including when an unresolvable contributor is what forced `null`.

import { describe, it, expect } from 'vitest';
import {
	computeCashflowRowStaleness,
	EMPTY_CASHFLOW_ROW_STALENESS,
	type CashflowContributorRow
} from './cashflowContributors';

function row(over: Partial<CashflowContributorRow>): CashflowContributorRow {
	return {
		cat: 'Revenue',
		sub_cat: 'Salary',
		sub_cat_id: 1,
		account_id: 100,
		account_name: 'Checking',
		...over
	};
}

describe('computeCashflowRowStaleness — root-unknown short-circuit', () => {
	it('staleAccountIds === null returns the EMPTY map, regardless of contributors', () => {
		const result = computeCashflowRowStaleness([row({})], null);
		expect(result).toBe(EMPTY_CASHFLOW_ROW_STALENESS);
		expect(result).toEqual({});
	});
});

describe('computeCashflowRowStaleness — Kleene-OR fold, TRUE dominates', () => {
	it('a row with one stale contributor is TRUE and names it', () => {
		const contributors = [row({ account_id: 100, account_name: 'Checking' })];
		const staleAccountIds = new Set(['100']);
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: true, staleAccountNames: ['Checking'] });
	});

	it('every contributor resolved confirmed-not-stale folds to FALSE', () => {
		const contributors = [row({ account_id: 100, account_name: 'Checking' })];
		const staleAccountIds = new Set<string>(); // known root, empty — nothing stale
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: false, staleAccountNames: [] });
	});

	it('TWO stale contributors both get named, distinct and sorted', () => {
		const contributors = [
			row({ account_id: 200, account_name: 'Savings' }),
			row({ account_id: 100, account_name: 'Checking' })
		];
		const staleAccountIds = new Set(['100', '200']);
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({
			is_stale: true,
			staleAccountNames: ['Checking', 'Savings']
		});
	});

	it('a fresh contributor alongside a stale one still yields TRUE, naming only the stale one', () => {
		const contributors = [
			row({ account_id: 100, account_name: 'Checking' }), // stale
			row({ account_id: 200, account_name: 'Savings' }) // fresh
		];
		const staleAccountIds = new Set(['100']);
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: true, staleAccountNames: ['Checking'] });
	});
});

describe('computeCashflowRowStaleness — account_name IS NULL folds to UNKNOWN, never fresh', () => {
	it('a single unresolvable contributor (account_name null) folds the row to null, not false', () => {
		const contributors = [row({ account_id: 999, account_name: null })];
		const staleAccountIds = new Set<string>(); // 999 not in the (visible) stale set
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: null, staleAccountNames: [] });
	});

	it('an unresolvable contributor does NOT get named even though it forced UNKNOWN', () => {
		const contributors = [row({ account_id: 999, account_name: null })];
		const result = computeCashflowRowStaleness(contributors, new Set());
		expect(result['Revenue']['Salary'].staleAccountNames).toEqual([]);
	});

	it('TRUE still dominates an unresolvable sibling contributor — inversion check on dominance order', () => {
		const contributors = [
			row({ account_id: 100, account_name: 'Checking' }), // confirmed stale
			row({ account_id: 999, account_name: null }) // unresolvable
		];
		const staleAccountIds = new Set(['100']);
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: true, staleAccountNames: ['Checking'] });
	});

	// Sec mid-flight condition (verbatim binding on this fold): an unresolvable account_id must
	// NEVER silently resolve to FALSE via `staleAccountIds.has()` missing it. `resolveStaleAccountIds`
	// builds its Set from an RLS-scoped read (navComposition.ts), so an account this caller cannot
	// see can NEVER be a member of that Set — copied by analogy from nonReAllocation.ts's own fold
	// (which has no account_name signal to test), a row with an otherwise-all-fresh contributor set
	// PLUS one unresolvable one would silently read as confirmed-FALSE, the exact three-into-two
	// collapse 099's own SHAPE 3 ruling exists to prevent one layer up. `foldRow`'s account_name
	// check runs PER CONTRIBUTOR, before `staleAccountIds.has()` is ever consulted for that
	// contributor (see its own doc comment) — this is the multi-contributor case proving it, on top
	// of the single-contributor case above.
	it('an otherwise ALL-FRESH row with ONE unresolvable contributor still yields UNKNOWN, never FALSE', () => {
		const contributors = [
			row({ account_id: 100, account_name: 'Checking' }), // confirmed fresh
			row({ account_id: 200, account_name: 'Savings' }), // confirmed fresh
			row({ account_id: 999, account_name: null }) // unresolvable — NOT a member of staleAccountIds,
			// but that absence is NOT evidence of freshness (see the comment above)
		];
		const staleAccountIds = new Set<string>(); // known root, empty — 100/200 confirmed not stale;
		// 999 cannot appear here regardless of its true staleness, because resolveStaleAccountIds's
		// own read could not see it either.
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary']).toEqual({ is_stale: null, staleAccountNames: [] });
	});
});

describe('computeCashflowRowStaleness — key restriction: unclassified + dormant third-taxonomy-state excluded', () => {
	it('sub_cat_id IS NULL (the unclassified contributor set) never appears in the map', () => {
		const contributors = [row({ cat: null, sub_cat: null, sub_cat_id: null })];
		const result = computeCashflowRowStaleness(contributors, new Set());
		expect(result).toEqual({});
	});

	it('sub_cat_id NOT NULL with cat/sub_cat both null (the dormant third state) never appears in the map', () => {
		const contributors = [row({ cat: null, sub_cat: null, sub_cat_id: 42 })];
		const result = computeCashflowRowStaleness(contributors, new Set());
		expect(result).toEqual({});
	});

	it('a mix of a real row and an excluded row only emits the real one', () => {
		const contributors = [
			row({ account_id: 100, account_name: 'Checking' }),
			row({ cat: null, sub_cat: null, sub_cat_id: null, account_id: 200, account_name: 'Savings' })
		];
		const result = computeCashflowRowStaleness(contributors, new Set(['100']));
		expect(Object.keys(result)).toEqual(['Revenue']);
		expect(Object.keys(result['Revenue'])).toEqual(['Salary']);
	});
});

describe('computeCashflowRowStaleness — grouping: two Sub-Cats, an account feeding both, cross-cat isolation', () => {
	it('two different (cat, sub_cat) keys each get their own independent fold', () => {
		const contributors = [
			row({ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 100, account_name: 'Checking' }),
			row({ cat: 'Expense', sub_cat: 'Rent', sub_cat_id: 2, account_id: 200, account_name: 'Savings' })
		];
		const staleAccountIds = new Set(['100']); // only the Revenue/Salary contributor is stale
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary'].is_stale).toBe(true);
		expect(result['Expense']['Rent'].is_stale).toBe(false);
	});

	it('one account contributing to two Sub-Cats taints BOTH rows when it is stale', () => {
		const contributors = [
			row({ cat: 'Revenue', sub_cat: 'Salary', sub_cat_id: 1, account_id: 100, account_name: 'Checking' }),
			row({ cat: 'Revenue', sub_cat: 'Bonus', sub_cat_id: 2, account_id: 100, account_name: 'Checking' })
		];
		const staleAccountIds = new Set(['100']);
		const result = computeCashflowRowStaleness(contributors, staleAccountIds);
		expect(result['Revenue']['Salary'].is_stale).toBe(true);
		expect(result['Revenue']['Bonus'].is_stale).toBe(true);
	});

	it('a Sub-Cat fed by two accounts under the SAME cat is keyed once, folding over both', () => {
		const contributors = [
			row({ cat: 'Expense', sub_cat: 'Utilities', sub_cat_id: 5, account_id: 100, account_name: 'Checking' }),
			row({ cat: 'Expense', sub_cat: 'Utilities', sub_cat_id: 5, account_id: 200, account_name: 'Savings' })
		];
		const result = computeCashflowRowStaleness(contributors, new Set(['200']));
		expect(Object.keys(result['Expense'])).toEqual(['Utilities']);
		expect(result['Expense']['Utilities']).toEqual({ is_stale: true, staleAccountNames: ['Savings'] });
	});
});
