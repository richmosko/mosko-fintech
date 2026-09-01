// historicalExpendituresPanel.test.ts — unit coverage for the §2.3.4 panel read (SELF-256, loader
// leg). Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain for BOTH
// RPCs this loader touches:
//   .schema('pfin').rpc('fn_historical_expenditures', { p_as_of })
//   .schema('pfin').rpc('fn_expenditures_unclassified_count', { p_as_of })
// routed by function name, mirroring cashflowCrossAccountRollup.test.ts's single-RPC stub shape
// generalized to two.
//
// Proves: `asOf` is threaded identically (same value, by name) to both RPCs from the ONE call
// site; each leg fails soft to null INDEPENDENTLY of the other (the crux property the module
// header states); the unclassified_count NULL-vs-0 distinction survives untouched — 0 is not
// coalesced away and NULL is not turned into a reassuring 0; numeric transport coercion (bigint
// arriving as a JSON string) is applied.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadHistoricalExpendituresPanel } from './historicalExpendituresPanel';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const AS_OF = unsafeAsOfForTest('2026-07-20');

const RAW_POINT = {
	month_end: '2026-06-30',
	expense_monthly_nominal: '1234.56',
	expense_monthly_inflation_adjusted: '1300.00',
	rolling_12mo_avg_inflation_adjusted: null,
	cpi_period: '2026-05-01',
	cpi_value: '312.5',
	cpi_is_carried: false,
	cpi_carried_from: null,
	cpi_period_was_due: true,
	cpi_nonpublication_on_record: false,
	cpi_coverage_through: '2026-05-01'
};

/** Minimal supabase-js stub covering both `.schema('pfin').rpc(fnName, { p_as_of })` chains this
 *  loader touches, routed by function name so each test can independently control either leg's
 *  response — the whole point being that the two legs must be independently controllable AND
 *  independently observed to fail soft. */
function makeSupabase(opts: {
	pointsData?: unknown;
	pointsError?: { message: string } | null;
	countData?: unknown;
	countError?: { message: string } | null;
}) {
	const rpc = vi.fn(async (fnName: string) => {
		if (fnName === 'fn_historical_expenditures') {
			return { data: opts.pointsData ?? [], error: opts.pointsError ?? null };
		}
		if (fnName === 'fn_expenditures_unclassified_count') {
			return {
				data: opts.countData ?? [{ unclassified_count: '0', ms_floor: '2021-08-01', ms_last: '2026-07-01' }],
				error: opts.countError ?? null
			};
		}
		throw new Error(`unexpected rpc call: ${fnName}`);
	});
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

describe('loadHistoricalExpendituresPanel — one call site, one asOf', () => {
	it('threads the SAME asOf value, by name, to both RPCs', async () => {
		const { client, rpc, schema } = makeSupabase({ pointsData: [RAW_POINT] });
		await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_historical_expenditures', { p_as_of: AS_OF });
		expect(rpc).toHaveBeenCalledWith('fn_expenditures_unclassified_count', { p_as_of: AS_OF });
	});
});

describe('loadHistoricalExpendituresPanel — points leg', () => {
	it('normalizes a well-formed row, coercing numeric-transport strings', async () => {
		const { client } = makeSupabase({ pointsData: [RAW_POINT] });
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.points).toEqual([
			{
				month_end: '2026-06-30',
				expense_monthly_nominal: 1234.56,
				expense_monthly_inflation_adjusted: 1300,
				rolling_12mo_avg_inflation_adjusted: null,
				cpi_period: '2026-05-01',
				cpi_value: 312.5,
				cpi_is_carried: false,
				cpi_carried_from: null,
				cpi_period_was_due: true,
				cpi_nonpublication_on_record: false,
				cpi_coverage_through: '2026-05-01'
			}
		]);
	});

	it('a zero-row read succeeds as [] — a real, distinguishable state, not an error', async () => {
		const { client } = makeSupabase({ pointsData: [] });
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.points).toEqual([]);
	});

	it('an RPC error degrades points to null, independently of the count leg', async () => {
		const { client } = makeSupabase({
			pointsError: { message: 'boom' },
			countData: [{ unclassified_count: '7', ms_floor: '2021-08-01', ms_last: '2026-07-01' }]
		});
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.points).toBeNull();
		expect(result.unclassifiedCount).toBe(7);
	});
});

describe('loadHistoricalExpendituresPanel — unclassified-count leg, NULL vs 0', () => {
	it('a real 0 passes through as 0, NOT coalesced to null (inversion check)', async () => {
		const { client } = makeSupabase({
			pointsData: [],
			countData: [{ unclassified_count: '0', ms_floor: '2021-08-01', ms_last: '2026-07-01' }]
		});
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.unclassifiedCount).toBe(0);
		expect(result.unclassifiedCount).not.toBeNull();
	});

	it('a NULL count (098: NULL p_as_of) passes through as null, NEVER coalesced to 0 (inversion check)', async () => {
		const { client } = makeSupabase({
			pointsData: [],
			countData: [{ unclassified_count: null, ms_floor: null, ms_last: null }]
		});
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.unclassifiedCount).toBeNull();
	});

	it('a real non-zero count coerces the bigint-as-string transport to a number', async () => {
		const { client } = makeSupabase({
			pointsData: [],
			countData: [{ unclassified_count: '42', ms_floor: '2021-08-01', ms_last: '2026-07-01' }]
		});
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.unclassifiedCount).toBe(42);
	});

	it('an RPC error degrades unclassifiedCount to null, independently of the points leg', async () => {
		const { client } = makeSupabase({
			pointsData: [RAW_POINT],
			countError: { message: 'boom' }
		});
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.unclassifiedCount).toBeNull();
		expect(result.points).toEqual([
			{
				month_end: '2026-06-30',
				expense_monthly_nominal: 1234.56,
				expense_monthly_inflation_adjusted: 1300,
				rolling_12mo_avg_inflation_adjusted: null,
				cpi_period: '2026-05-01',
				cpi_value: 312.5,
				cpi_is_carried: false,
				cpi_carried_from: null,
				cpi_period_was_due: true,
				cpi_nonpublication_on_record: false,
				cpi_coverage_through: '2026-05-01'
			}
		]);
	});

	it('an unexpected row count (not exactly one) degrades to null rather than guessing', async () => {
		const { client } = makeSupabase({ pointsData: [], countData: [] });
		const result = await loadHistoricalExpendituresPanel(client, AS_OF);

		expect(result.unclassifiedCount).toBeNull();
	});
});
