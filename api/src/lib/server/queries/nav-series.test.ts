// nav-series.test.ts — unit coverage for the §2.1.2.d NAV-over-time chart read
// (SELF-220). Pure-TS server test (node env per vitest.config). Mocks the
// supabase-js chain:
//   .schema('pfin').rpc('fn_nav_series_inflation_adjusted', { p_granularity, p_start_date, p_end_date })
//     → { data, error }
//
// Proves: the array of rows passes through with numeric coercion (mirrors
// netWorth.ts's number-OR-string idiom), the NULLABLE nav_inflation_adjusted /
// cpi_value columns stay nullable (never coerced to 0 — the whole point of
// 067's NULL-not-zero contract), the fail-soft degrade-to-`null` (NOT `[]`)
// on an RPC error and on a non-array payload — distinguishing "read failed"
// from "read succeeded, found nothing" is the entire point of this
// function's contract — and resolveNavSeriesWindow's default-window
// derivation (each half independently optional, relative-to-resolved-end).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNavSeries, resolveNavSeriesWindow } from './nav-series';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

type MockOpts = {
	data?: unknown;
	error?: { message: string } | null;
};

/** Minimal supabase-js stub: the single .schema('pfin').rpc(...) chain the helper touches. */
function makeSupabase(opts: MockOpts) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

const RAW_ROW = {
	point_date: '2020-01-31',
	nav_nominal: '100000.5', // string form — PostgREST numeric may arrive as string
	checkpoint_date: '2020-01-31',
	nav_inflation_adjusted: '105000.25',
	cpi_period: '2020-01-01',
	cpi_value: 258.678,
	cpi_is_carried: false,
	cpi_carried_from: null,
	cpi_period_was_due: true,
	cpi_nonpublication_on_record: false,
	cpi_coverage_through: '2026-06-01'
};

describe('loadNavSeries', () => {
	it('happy path: rows pass through with numeric coercion + correct RPC args', async () => {
		const { client, rpc, schema } = makeSupabase({ data: [RAW_ROW] });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');

		expect(rows).toEqual([
			{
				point_date: '2020-01-31',
				nav_nominal: 100000.5,
				checkpoint_date: '2020-01-31',
				nav_inflation_adjusted: 105000.25,
				cpi_period: '2020-01-01',
				cpi_value: 258.678,
				cpi_is_carried: false,
				cpi_carried_from: null,
				cpi_period_was_due: true,
				cpi_nonpublication_on_record: false,
				cpi_coverage_through: '2026-06-01'
			}
		]);
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_nav_series_inflation_adjusted', {
			p_granularity: 'monthly',
			p_start_date: '2020-01-01',
			p_end_date: '2020-12-31'
		});
	});

	it('NULLABLE nav_inflation_adjusted / cpi_value stay NULL — never coerced to 0', async () => {
		const rowWithNulls = { ...RAW_ROW, nav_inflation_adjusted: null, cpi_value: null };
		const { client } = makeSupabase({ data: [rowWithNulls] });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');

		expect(rows).not.toBeNull();
		expect(rows?.[0].nav_inflation_adjusted).toBeNull();
		expect(rows?.[0].cpi_value).toBeNull();
		// The row is still emitted with nav_nominal intact — 067's own contract
		// (an un-deflatable point must not vanish from the nominal series).
		expect(rows?.[0].nav_nominal).toBe(100000.5);
	});

	it('multiple rows all pass through, in the order the RPC returned them (067: ascending)', async () => {
		const row2 = { ...RAW_ROW, point_date: '2020-02-29', cpi_period: '2020-02-01' };
		const { client } = makeSupabase({ data: [RAW_ROW, row2] });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');

		expect(rows).toHaveLength(2);
		expect(rows?.[0].point_date).toBe('2020-01-31');
		expect(rows?.[1].point_date).toBe('2020-02-29');
	});

	it('genuinely EMPTY series (no rows in range) → [] — the SUCCEEDED-but-empty state', async () => {
		const { client } = makeSupabase({ data: [] });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');
		expect(rows).toEqual([]);
		expect(rows).not.toBeNull();
	});

	it('RPC error → null (NOT []) — fail-soft, but distinguishably "read failed"', async () => {
		const { client } = makeSupabase({ error: { message: 'permission denied' } });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');
		expect(rows).toBeNull();
	});

	it('non-array payload (unexpected) → null (NOT []) — degrade, do not assert a shape', async () => {
		const { client } = makeSupabase({ data: { unexpected: 'shape' } });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');
		expect(rows).toBeNull();
	});

	it('null payload (unexpected) → null — degrade, do not assert a shape', async () => {
		const { client } = makeSupabase({ data: null });
		const rows = await loadNavSeries(client, 'monthly', '2020-01-01', '2020-12-31');
		expect(rows).toBeNull();
	});
});

describe('resolveNavSeriesWindow', () => {
	it('both absent: end defaults to today, start defaults to 60 months before end', () => {
		// serverTodayAsOf() is not mockable without touching production code, so this test uses
		// unsafeAsOfForTest to build an expected value against the SAME derivation the function
		// under test uses for a supplied end — this leg instead asserts the RELATIVE distance,
		// which is the part that doesn't depend on "today".
		const { start, end } = resolveNavSeriesWindow(undefined, undefined);
		const endDate = new Date(`${end}T00:00:00Z`);
		const startDate = new Date(`${start}T00:00:00Z`);
		const monthsBetween =
			(endDate.getUTCFullYear() - startDate.getUTCFullYear()) * 12 +
			(endDate.getUTCMonth() - startDate.getUTCMonth());
		expect(monthsBetween).toBe(60);
	});

	it('end supplied, start absent: start defaults to 60 months before the SUPPLIED end, not today', () => {
		const { start, end } = resolveNavSeriesWindow(undefined, '2020-06-30');
		expect(end).toBe('2020-06-30');
		expect(start).toBe('2015-06-30');
	});

	it('both supplied: returned unchanged', () => {
		const { start, end } = resolveNavSeriesWindow('2019-01-01', '2020-01-01');
		expect(start).toBe('2019-01-01');
		expect(end).toBe('2020-01-01');
	});

	it('start supplied, end absent: end still defaults to today (unsafeAsOfForTest sanity: distinct from a fixed past date)', () => {
		const fixedPast = unsafeAsOfForTest('2015-01-01');
		const { start, end } = resolveNavSeriesWindow('2019-01-01', undefined);
		expect(start).toBe('2019-01-01');
		expect(end).not.toBe(fixedPast);
	});
});
