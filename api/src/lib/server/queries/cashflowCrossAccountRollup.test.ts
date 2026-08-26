// cashflowCrossAccountRollup.test.ts — unit coverage for the §2.3.2 cross-account rollup read
// (SELF-250). Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_cashflow_cross_account_rollup', { p_as_of }) -> { data, error }
// mirroring navComposition.test.ts's own scalar-jsonb mock shape (093, like 051, returns a
// SCALAR jsonb, not a row set).
//
// Proves: `p_as_of` is threaded explicitly and by name (never left to the fn default — the
// ADR-044 D2 "resolve once, thread everywhere" discipline this file's own header cites); AC5
// section labels are attached from the shared cashflowSections.ts module and NOT typed inline;
// AC6 row-absent vs. one-row-of-NULLs targets normalize IDENTICALLY, with an inversion check
// that would catch a handler that anticipates only one shape; AC8's NULL-vs-0 em-dash distinction
// survives untouched; the fail-soft degrade-to-null on both an RPC error and a null payload.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadCashflowCrossAccountRollup } from './cashflowCrossAccountRollup';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

/** Minimal supabase-js stub covering the one chain this loader touches:
 *  .schema('pfin').rpc('fn_cashflow_cross_account_rollup', { p_as_of }). */
function makeSupabase(opts: { data?: unknown; error?: { message: string } | null }) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

/** A well-formed 093 payload — two sections, one Sub-Cat row each, a mid-year `q3`/`q4` not yet
 *  started (asOf = 2026-07-20, so q1/q2/q3-not-yet... wait: q3 STARTS 2026-07-01 <= 2026-07-20,
 *  so q3 HAS started; q4 (starts 2026-10-01) has NOT). Kept as one shared fixture so every test
 *  below reasons about the SAME concrete numbers. */
const RAW_ROLLUP = {
	as_of: '2026-07-20',
	sections: [
		{
			cat: 'Revenue',
			rows: [{ sub_cat: 'Salary', month: 5000, q1: 15000, q2: 15000, q3: 5000, q4: null, ytd: 35000 }],
			total: { month: 5000, q1: 15000, q2: 15000, q3: 5000, q4: null, ytd: 35000 }
		},
		{
			cat: 'Expense',
			// A Sub-Cat with a real $0 quarter (STARTED, no activity) alongside the not-yet-started q4.
			rows: [{ sub_cat: 'Groceries', month: 400, q1: 1200, q2: 1200, q3: 0, q4: null, ytd: 2800 }],
			total: { month: 400, q1: 1200, q2: 1200, q3: 0, q4: null, ytd: 2800 }
		}
	],
	targets: { income_target_annual: null, expense_target_monthly: null },
	unclassified: { count_ytd: 3 }
};

describe('loadCashflowCrossAccountRollup — happy path', () => {
	it('threads asOf explicitly and by name (never the fn default)', async () => {
		const { client, rpc, schema } = makeSupabase({ data: RAW_ROLLUP });
		await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_cashflow_cross_account_rollup', { p_as_of: AS_OF });
	});

	it('AC5: attaches product labels from the shared cashflowSections.ts module, not typed inline', async () => {
		const { client } = makeSupabase({ data: RAW_ROLLUP });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.sections[0]).toMatchObject({ cat: 'Revenue', sectionKey: 'income', label: 'Income' });
		expect(result?.sections[1]).toMatchObject({ cat: 'Expense', sectionKey: 'expenses', label: 'Expenses' });
	});

	it('AC5 fallback: a cat outside the current section table degrades to its raw value, never throws', async () => {
		const withUnmappedCat = {
			...RAW_ROLLUP,
			sections: [{ cat: 'SomeFutureClass', rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } }]
		};
		const { client } = makeSupabase({ data: withUnmappedCat });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.sections[0]).toMatchObject({
			cat: 'SomeFutureClass',
			sectionKey: undefined,
			label: 'SomeFutureClass'
		});
	});

	it('AC8: raw section rows/totals pass through with NO arithmetic applied', async () => {
		const { client } = makeSupabase({ data: RAW_ROLLUP });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.sections[0].rows).toEqual(RAW_ROLLUP.sections[0].rows);
		expect(result?.sections[0].total).toEqual(RAW_ROLLUP.sections[0].total);
		expect(result?.sections[1].rows).toEqual(RAW_ROLLUP.sections[1].rows);
	});

	it('AC8: unclassified.count_ytd (the S-2 banner N) passes through from the same query', async () => {
		const { client } = makeSupabase({ data: RAW_ROLLUP });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.unclassified).toEqual({ count_ytd: 3 });
	});
});

describe('loadCashflowCrossAccountRollup — AC8: the em-dash rule is two-sided, NEVER collapsed', () => {
	it('a not-yet-started quarter arrives as null and STAYS null (renders em-dash)', async () => {
		const { client } = makeSupabase({ data: RAW_ROLLUP });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		// q4 has not started relative to asOf=2026-07-20 — both the row and the section total.
		expect(result?.sections[0].rows[0].q4).toBeNull();
		expect(result?.sections[0].total.q4).toBeNull();
	});

	it('a started quarter with no activity arrives as a real 0, NEVER an em-dash null (inversion check)', async () => {
		const { client } = makeSupabase({ data: RAW_ROLLUP });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		// Groceries' q3 = 0 (started, genuinely no spend) — a handler that coalesces every
		// falsy-looking cell toward null, or that cannot distinguish 0 from null, flips this RED:
		// `0` must be strictly a number, not null, and must not become truthy-coerced either.
		const q3 = result?.sections[1].rows[0].q3;
		expect(q3).toBe(0);
		expect(q3).not.toBeNull();
	});
});

describe('loadCashflowCrossAccountRollup — AC6: row-absent vs. one-row-of-NULLs targets', () => {
	it('arrival shape (a) — the SQL-collapsed two-key-null object (093\'s actual contract)', async () => {
		const { client } = makeSupabase({
			data: { ...RAW_ROLLUP, targets: { income_target_annual: null, expense_target_monthly: null } }
		});
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.targets).toEqual({ income_target_annual: null, expense_target_monthly: null });
	});

	it('arrival shape (b) — targets key entirely ABSENT from the payload (defensive coalesce, inversion check)', async () => {
		// If normalize() read `raw.targets` without the `?? { ...null }` fallback, `result.targets`
		// would be `undefined` here — a shape a caller COULD branch on, exactly what AC6 forbids.
		const { targets, ...withoutTargets } = RAW_ROLLUP;
		const { client } = makeSupabase({ data: withoutTargets });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.targets).toEqual({ income_target_annual: null, expense_target_monthly: null });
	});

	it('shapes (a) and (b) produce the IDENTICAL result — no discriminant a caller could branch on', async () => {
		const shapeA = makeSupabase({
			data: { ...RAW_ROLLUP, targets: { income_target_annual: null, expense_target_monthly: null } }
		});
		const { targets, ...shapeBPayload } = RAW_ROLLUP;
		const shapeB = makeSupabase({ data: shapeBPayload });

		const resultA = await loadCashflowCrossAccountRollup(shapeA.client, AS_OF);
		const resultB = await loadCashflowCrossAccountRollup(shapeB.client, AS_OF);

		expect(resultA?.targets).toEqual(resultB?.targets);
	});

	it('a real (non-null) target value still passes through unchanged', async () => {
		const { client } = makeSupabase({
			data: { ...RAW_ROLLUP, targets: { income_target_annual: 120000, expense_target_monthly: 4000 } }
		});
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.targets).toEqual({ income_target_annual: 120000, expense_target_monthly: 4000 });
	});
});

describe('loadCashflowCrossAccountRollup — AC6-adjacent defensive coalesce: unclassified', () => {
	it('unclassified key entirely absent degrades to a well-formed zero-count object, never undefined', async () => {
		const { unclassified, ...withoutUnclassified } = RAW_ROLLUP;
		const { client } = makeSupabase({ data: withoutUnclassified });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result?.unclassified).toEqual({ count_ytd: 0 });
	});
});

describe('loadCashflowCrossAccountRollup — fail-soft posture', () => {
	it('an RPC error degrades to null (logged, never thrown)', async () => {
		const { client } = makeSupabase({ error: { message: 'boom' } });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result).toBeNull();
	});

	it('a null payload degrades to null (093 always returns a well-formed document; this is a transport surprise)', async () => {
		const { client } = makeSupabase({ data: null });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result).toBeNull();
	});

	it('an undefined payload degrades to null', async () => {
		const { client } = makeSupabase({ data: undefined });
		const result = await loadCashflowCrossAccountRollup(client, AS_OF);

		expect(result).toBeNull();
	});
});
