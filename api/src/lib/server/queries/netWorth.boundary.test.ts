// netWorth.boundary.test.ts — QA-owned. The ADR-042 `::date` as-of BOUNDARY at the app layer.
//
// SEPARATE FILE ON PURPOSE, two reasons:
//   1. `netWorth.test.ts` is Backend's and was under concurrent edit when this was written.
//   2. It asserts the FILTER STRING. This file asserts the BEHAVIOUR that string must produce,
//      and the two instruments should be legible as different things rather than interleaved.
//
// ┌─ WHY A STRING ASSERTION IS NOT SUFFICIENT HERE (Sec condition, 2026-08-04) ────────┐
// │ The defect Sec found: `fn_compute_nav` filters `closed_at::date > p_as_of` while    │
// │ this query filtered `closed_at.gt.<asOf>`. PostgREST promotes the bare form to      │
// │ MIDNIGHT, so for up to 24h after every app-initiated close the COUNT and the NAV    │
// │ described DIFFERENT POPULATIONS — a user closing their last account at 14:00 saw a  │
// │ real $0 net worth instead of the empty state until midnight.                        │
// │                                                                                      │
// │ It survived 16/16 CI checks because the test pinned the STRING. A string assertion   │
// │ is only as correct as the string someone typed into it: it goes green on whatever    │
// │ the code emits the moment both are edited together, which is exactly what happens    │
// │ when someone "updates the test to match". **It cannot distinguish a correct          │
// │ predicate from a consistent pair of wrong ones.**                                    │
// │                                                                                      │
// │ This is Backend's own §7.9 AC-4 finding — a mock asserting the CALL rather than the  │
// │ BEHAVIOUR — firing in the file where they fixed it. That is not irony; it is the     │
// │ rule earning its keep, and it is why the instrument here evaluates the predicate     │
// │ instead of reading it.                                                               │
// └──────────────────────────────────────────────────────────────────────────────────────┘
//
// WHAT THIS FILE DOES: captures the `.or()` filter the production code actually emits, EVALUATES
// it against an in-memory account fixture, and asserts the resulting population matches the
// ruled SQL semantics (`closed_at::date > p_as_of` ⇒ same-day closure EXCLUDED).
//
// ⚠ THE EVALUATOR IS A FIXTURE, AND A FIXTURE IS THE THING A TEST CANNOT TEST. It implements a
//   deliberately TINY subset of PostgREST and is NOT proof that PostgREST behaves this way — it
//   is proof that THE PREDICATE THIS CODE EMITS selects the intended rows under those semantics.
//   Two consequences, both deliberate:
//     · every clause must be RECOGNISED or the test FAILS (see assertParsed). An unknown
//       operator must go RED, never silently match nothing and report a passing population —
//       that is the `assert anchor in s` precondition rule, applied to a parser.
//     · the DB-layer proof of the same ruling is `supabase/tests/rls/049_..._rls.sql` (1i)/(1j)/
//       (1k), against the real predicate with a real non-midnight fixture. Neither substitutes
//       for the other: that one proves the SQL, this one proves the app asks the SQL the same
//       question. The bug lived in the gap between them.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNetWorthView } from './netWorth';

const AS_OF = '2026-07-20';

/** One account row, reduced to the only column this predicate reads. */
type Row = { id: string; closed_at: string | null };

// The fixture. `afternoon` is the whole point: a closure at 14:00 ON the as-of date is the
// ONLY shape that separates `gt.<asOf>` from the ruled semantics — at midnight the two agree.
// It is also the UNIVERSAL production case: fn_close_account defaults p_closed_at to now(),
// so every app-closed account carries a time-of-day. Midnight is the fixture artefact.
const ROWS: Row[] = [
	{ id: 'open', closed_at: null },
	{ id: 'afternoon-on-as-of', closed_at: '2026-07-20T14:00:00+00:00' },
	{ id: 'midnight-on-as-of', closed_at: '2026-07-20T00:00:00+00:00' },
	{ id: 'closed-later', closed_at: '2026-07-25T09:30:00+00:00' }
];

type Clause = { matched: boolean; test: (r: Row) => boolean };

/**
 * Evaluate ONE PostgREST clause. Returns matched:false for anything unrecognised so the caller
 * can fail loudly — a parser that silently returns "no match" turns an unknown operator into a
 * passing test with an empty population.
 */
function clause(src: string): Clause {
	const isNull = /^closed_at\.is\.null$/.exec(src);
	if (isNull) return { matched: true, test: (r) => r.closed_at === null };

	const cmp = /^closed_at\.(gt|gte)\.(.+)$/.exec(src);
	if (cmp) {
		const [, op, operand] = cmp;
		// PostgREST compares a timestamptz column against the operand as Postgres would: a bare
		// date promotes to midnight. Date.parse reproduces that promotion, which is the exact
		// behaviour under test.
		const bound = Date.parse(operand.length === 10 ? `${operand}T00:00:00+00:00` : operand);
		return {
			matched: true,
			test: (r) => {
				if (r.closed_at === null) return false;
				const t = Date.parse(r.closed_at);
				return op === 'gt' ? t > bound : t >= bound;
			}
		};
	}
	return { matched: false, test: () => false };
}

/** Apply a full `.or(...)` filter, asserting every clause was understood. */
function applyOr(filter: string, rows: Row[]): Row[] {
	const clauses = filter.split(',').map(clause);
	const unparsed = filter.split(',').filter((_, i) => !clauses[i].matched);
	// PRECONDITION, asserted separately from the result (DESIGN.md rule 3): if the predicate
	// grows an operator this evaluator does not model, the run must FAIL rather than report a
	// population computed from the clauses it happened to understand.
	expect(unparsed, `unrecognised PostgREST clause(s) in "${filter}" — this evaluator models only is.null/gt/gte. A new operator means this test must be taught it, NOT that the population is empty`).toEqual([]);
	return rows.filter((r) => clauses.some((c) => c.test(r)));
}

/** Supabase stub that RECORDS the filter and answers with the population it actually selects. */
function makeSupabase(rows: Row[], navData: unknown = 0) {
	let captured: string | null = null;
	const rpc = vi.fn(async (_fn: string, _args: Record<string, unknown>) => ({
		data: navData,
		error: null
	}));
	const or = vi.fn(async (filter: string) => {
		captured = filter;
		return { count: applyOr(filter, rows).length, error: null };
	});
	const select = vi.fn(() => ({ or }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ rpc, from }));
	return {
		client: { schema } as unknown as SupabaseClient,
		filter: () => captured
	};
}

describe('loadNetWorthView — the ADR-042 as-of boundary (behavioural, not string-matched)', () => {
	it('EXCLUDES an account closed at 14:00 ON the as-of date — same-day is closed-day', async () => {
		const { client, filter } = makeSupabase(ROWS);
		await loadNetWorthView(client, AS_OF);

		const selected = applyOr(filter()!, ROWS).map((r) => r.id);

		// THE RULING: `closed_at::date > p_as_of`. A closure at ANY time on p_as_of is excluded,
		// which is what `is_active` did before 059 — so the ruled form PRESERVES current-state
		// behaviour and the bare `gt.<asOf>` form CHANGES it.
		expect(selected).not.toContain('afternoon-on-as-of');
		expect(selected).not.toContain('midnight-on-as-of');
		// …and the exclusion is DATED, not blanket: still-open and later-closed rows survive.
		expect(selected).toEqual(['open', 'closed-later']);
	});

	it('the count and the NAV describe ONE population — the empty-state disambiguator', async () => {
		// The user-visible defect, reduced: a tenant whose ONLY account was closed this
		// afternoon. The NAV excludes it (SQL `::date`), so net worth is 0 — and if the count
		// includes it, `hasAccounts` is true and the UI renders a real $0 instead of the empty
		// state. Asserting the two AGREE is the invariant; asserting either alone is not.
		const only = [ROWS[1]];
		const { client } = makeSupabase(only, 0);
		const view = await loadNetWorthView(client, AS_OF);

		expect(view).toEqual({ netWorth: 0, hasAccounts: false });
	});

	it('is NON-VACUOUS: the same fixture one day earlier DOES count the account', async () => {
		// Without this, both assertions above would also pass against a predicate that excluded
		// the account at every as-of — the current-state regression, which is a different defect
		// with the same symptom here. The boundary is a boundary only if one side of it differs.
		const only = [ROWS[1]];
		const { client } = makeSupabase(only, 5555);
		const view = await loadNetWorthView(client, '2026-07-19');

		expect(view).toEqual({ netWorth: 5555, hasAccounts: true });
	});
});
