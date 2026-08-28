// cashflowPerAccount.test.ts — unit coverage for the §2.3.3 per-account drill-down read + its
// request-boundary validation (SELF-253). Pure-TS server test (node env per vitest.config).
//
// Two halves:
//   1. loadCashflowPerAccount — mocks the supabase-js chain the same way
//      cashflowCrossAccountRollup.test.ts does for 093 (`.schema('pfin').rpc('fn_cashflow_per_account', ...)`).
//   2. validateCashflowPerAccountParams / loadCashflowPerAccountForRequest — the DATE battery
//      this surface's boundary owes (D19 Edit-2, extended here per F/CTO ruling): future / pre-floor /
//      garbage / absent-as_of / valid-historical legs, plus the account_id positive-integer-bigint
//      fence. Single-surface coverage ONLY — no global route-coverage framework (deferred at
//      SELF-247 item 12 -> BACKLOG §7.25 item 3).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
	loadCashflowPerAccount,
	loadCashflowPerAccountForRequest,
	validateCashflowPerAccountParams,
	type ValidatedCashflowPerAccountParams
} from './cashflowPerAccount';
import { AS_OF_FLOOR } from '$lib/server/schemas/asOf';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');
const MAX_AS_OF = unsafeAsOfForTest('2026-08-25');

/** Minimal supabase-js stub covering the one chain this loader touches:
 *  .schema('pfin').rpc('fn_cashflow_per_account', { p_account_id, p_as_of }). */
function makeSupabase(opts: { data?: unknown; error?: { message: string } | null }) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

/** A well-formed 094 payload — three sections in the ruled order, one Sub-Cat row each. */
const RAW_PER_ACCOUNT = {
	as_of: '2026-07-20',
	account_id: 4283,
	sections: [
		{
			section_key: 'income',
			cats: ['Revenue'],
			rows: [{ cat: 'Revenue', sub_cat: 'Salary', month: 5000, q1: 15000, q2: 15000, q3: 5000, q4: null, ytd: 35000 }],
			total: { month: 5000, q1: 15000, q2: 15000, q3: 5000, q4: null, ytd: 35000 }
		},
		{
			section_key: 'other_cash_flows',
			cats: ['Transfer', 'Equity'],
			rows: [{ cat: 'Transfer', sub_cat: 'Bank Transfer', month: -200, q1: -600, q2: -600, q3: 0, q4: null, ytd: -1400 }],
			total: { month: -200, q1: -600, q2: -600, q3: 0, q4: null, ytd: -1400 }
		},
		{
			section_key: 'expenses',
			cats: ['Expense'],
			rows: [{ cat: 'Expense', sub_cat: 'Groceries', month: 400, q1: 1200, q2: 1200, q3: 0, q4: null, ytd: 2800 }],
			total: { month: 400, q1: 1200, q2: 1200, q3: 0, q4: null, ytd: 2800 }
		}
	],
	unclassified: { count_ytd: 2 }
};

const VALID_PARAMS_RESULT = validateCashflowPerAccountParams({
	accountIdRaw: '4283',
	asOfRaw: AS_OF,
	maxAsOf: MAX_AS_OF
});
if (!VALID_PARAMS_RESULT.ok) {
	throw new Error('fixture setup failed: expected a valid params result');
}
const VALID_PARAMS: ValidatedCashflowPerAccountParams = VALID_PARAMS_RESULT.params;

describe('loadCashflowPerAccount — happy path', () => {
	it('threads account_id and as_of explicitly and by name', async () => {
		const { client, rpc, schema } = makeSupabase({ data: RAW_PER_ACCOUNT });
		await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_cashflow_per_account', {
			p_account_id: VALID_PARAMS.accountId,
			p_as_of: VALID_PARAMS.asOf
		});
	});

	it('AC2: three sections in the ruled order, section_key + label + cats attached from the shared module', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.sections.map((s) => s.sectionKey)).toEqual(['income', 'other_cash_flows', 'expenses']);
		expect(result?.sections.map((s) => s.label)).toEqual(['Income', 'Other Cash Flows', 'Expenses']);
		expect(result?.sections[1].cats).toEqual(['Transfer', 'Equity']);
	});

	it('rows carry BOTH cat and sub_cat — the middle section needs cat to disambiguate its union', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.sections[1].rows[0]).toMatchObject({ cat: 'Transfer', sub_cat: 'Bank Transfer' });
	});

	it('AC7: no targets key exists anywhere on the returned shape', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result && 'targets' in result).toBe(false);
	});

	it('negative section totals (other_cash_flows, the +1 raw-signed section) pass through with their real sign, never abs()', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.sections[1].total.ytd).toBe(-1400);
	});

	it('the em-dash rule is two-sided: a not-yet-started quarter stays null, a started-empty quarter stays a real 0', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.sections[0].total.q4).toBeNull();
		const q3 = result?.sections[2].rows[0].q3;
		expect(q3).toBe(0);
		expect(q3).not.toBeNull();
	});

	it('AC label fallback: an unmapped section_key degrades to its raw value, never throws', async () => {
		const withUnmappedKey = {
			...RAW_PER_ACCOUNT,
			sections: [{ section_key: 'some_future_section', cats: [], rows: [], total: { month: 0, q1: 0, q2: 0, q3: 0, q4: 0, ytd: 0 } }]
		};
		const { client } = makeSupabase({ data: withUnmappedKey });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.sections[0]).toMatchObject({ sectionKey: 'some_future_section', label: 'some_future_section' });
	});

	it('unclassified.count_ytd passes through from the same query', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.unclassified).toEqual({ count_ytd: 2 });
	});

	it('unclassified key entirely absent degrades to a well-formed zero-count object, never undefined', async () => {
		const { unclassified, ...withoutUnclassified } = RAW_PER_ACCOUNT;
		const { client } = makeSupabase({ data: withoutUnclassified });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result?.unclassified).toEqual({ count_ytd: 0 });
	});
});

describe('loadCashflowPerAccount — fail-soft posture', () => {
	it('an RPC error degrades to null (logged, never thrown)', async () => {
		const { client } = makeSupabase({ error: { message: 'boom' } });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result).toBeNull();
	});

	it('a null payload degrades to null', async () => {
		const { client } = makeSupabase({ data: null });
		const result = await loadCashflowPerAccount(client, VALID_PARAMS);

		expect(result).toBeNull();
	});
});

describe('validateCashflowPerAccountParams — account_id: positive-integer bigint, garbage never reaches SQL', () => {
	const rejected: Array<[string, string]> = [
		['negative', '-1'],
		['zero', '0'],
		['non-numeric', 'abc'],
		['decimal', '1.5'],
		['scientific notation', '1e3'],
		['SQL-injection-shaped', "4283; DROP TABLE pfin.account_trans; --"],
		['empty string', ''],
		['embedded whitespace (trim only strips the ends, not an internal gap)', '42 83']
	];

	for (const [label, raw] of rejected) {
		it(`rejects ${label} account_id with a field-level error, before any RPC call`, () => {
			const result = validateCashflowPerAccountParams({
				accountIdRaw: raw,
				asOfRaw: undefined,
				maxAsOf: MAX_AS_OF
			});
			expect(result.ok).toBe(false);
			if (result.ok) return;
			expect(result.fieldErrors.account_id).toBeDefined();
		});
	}

	it('accepts a well-formed positive-integer digit string', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: undefined,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
		if (result.ok) expect(result.params.accountId).toBe(4283);
	});
});

describe('validateCashflowPerAccountParams — the DATE battery at this surface (D19 Edit-2, extended per F/CTO ruling)', () => {
	it('future date -> rejected with a field-level error on as_of', () => {
		const oneDayPastMax = '2026-08-26';
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: oneDayPastMax,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.fieldErrors.as_of).toBeDefined();
	});

	it('pre-floor date (< 2015-12-01) -> rejected with a field-level error on as_of', () => {
		const oneDayBeforeFloor = '2015-11-30';
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: oneDayBeforeFloor,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.fieldErrors.as_of).toBeDefined();
	});

	it('garbage / non-date -> rejected with a field-level error on as_of', () => {
		for (const garbage of ['not-a-date', '2026-02-31', '08/25/2026', 'NaN', 'Infinity']) {
			const result = validateCashflowPerAccountParams({
				accountIdRaw: '4283',
				asOfRaw: garbage,
				maxAsOf: MAX_AS_OF
			});
			expect(result.ok).toBe(false);
			if (result.ok) continue;
			expect(result.fieldErrors.as_of).toBeDefined();
		}
	});

	it('absent as_of -> the SETTLED default branch: resolves to maxAsOf, asserted explicitly (the two-clock settlement)', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: undefined,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
		if (result.ok) expect(result.params.asOf).toBe(MAX_AS_OF);
	});

	it('null as_of (a route with no query param present at all) resolves the SAME as undefined', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: null,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
		if (result.ok) expect(result.params.asOf).toBe(MAX_AS_OF);
	});

	it('a valid historical date passes through to the resolved params exactly as supplied', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: '2020-06-15',
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
		if (result.ok) expect(result.params.asOf).toBe('2020-06-15');
	});

	it('the inclusive floor boundary is accepted', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: AS_OF_FLOOR,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
	});

	it('the inclusive ceiling boundary (exactly maxAsOf) is accepted', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: '4283',
			asOfRaw: MAX_AS_OF,
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(true);
	});

	it('both account_id AND as_of failures surface together in one round trip (never short-circuited)', () => {
		const result = validateCashflowPerAccountParams({
			accountIdRaw: 'not-an-id',
			asOfRaw: '2099-01-01',
			maxAsOf: MAX_AS_OF
		});
		expect(result.ok).toBe(false);
		if (result.ok) return;
		expect(result.fieldErrors.account_id).toBeDefined();
		expect(result.fieldErrors.as_of).toBeDefined();
	});
});

describe('loadCashflowPerAccountForRequest — the end-to-end SELF-254 entry point', () => {
	it('a validation failure returns 400 with field errors and never calls the RPC', async () => {
		const { client, rpc } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccountForRequest(client, {
			accountIdRaw: 'garbage',
			asOfRaw: undefined,
			maxAsOf: MAX_AS_OF
		});

		expect(result.status).toBe(400);
		expect(rpc).not.toHaveBeenCalled();
	});

	it('a valid request returns 200 with the loaded, normalized data', async () => {
		const { client } = makeSupabase({ data: RAW_PER_ACCOUNT });
		const result = await loadCashflowPerAccountForRequest(client, {
			accountIdRaw: '4283',
			asOfRaw: AS_OF,
			maxAsOf: MAX_AS_OF
		});

		expect(result.status).toBe(200);
		if (result.status === 200) {
			expect(result.data?.account_id).toBe(4283);
			expect(result.data?.sections).toHaveLength(3);
		}
	});
});
