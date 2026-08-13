// nav-series.server.test.ts — SELF-220 chart-scoped load()-integration coverage for the
// root +page.server.ts. Locks the THREE distinguishable navSeries states this route now
// returns, and that query-param validation is CHART-SCOPED (never a page-wide throw) per
// the F/CTO-adjacent team-lead ruling (2026-08-12): an invalid granularity/date must not
// take down the §2.1.1 headline or the composition table sharing this route.
//
//   1. navSeriesParamsError !== null, navSeries === null — invalid params, no read attempted.
//   2. navSeriesParamsError === null, navSeries === null — valid params, the READ failed.
//   3. navSeriesParamsError === null, navSeries deep-equals [] — valid params, genuinely empty.
//
// The rest of the route's RPCs (netWorth / staleness / composition) are mocked to trivial
// happy-path defaults — their own behavior is proven by netWorth.test.ts / navComposition.test.ts;
// this file exists only to lock the chart-scoping dispatch added around loadNavSeries().

import { describe, it, expect, vi } from 'vitest';
import { load } from './+page.server';
import type { NavSeriesPoint } from '$lib/nav-series';

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };

/**
 * Explicit result shape for `await runLoad(event)`. Needed only because this test bypasses
 * SvelteKit's generated `./$types` event typing (the mock `event` isn't a real
 * `ServerLoadEvent`), which otherwise leaves `svelte-check` unable to narrow `load`'s return
 * away from `void` in this file specifically — a type-inference artifact of the test setup,
 * not of `load` itself (every OTHER consumer of this route gets the real generated type).
 */
type LoadResult = {
	netWorth: number | null;
	navSeries: NavSeriesPoint[] | null;
	navSeriesParamsError: string | null;
	navSeriesParams: { granularity: string; start: string; end: string };
	navBoundary: {
		first_cron_checkpoint: string | null;
		has_cron_rows: boolean;
		has_imported_rows: boolean;
	} | null;
};

async function runLoad(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

/**
 * Builds a `locals.supabase` stub whose `.schema('pfin')` chain dispatches by RPC/table name,
 * so the SAME mock instance serves netWorth.ts / staleness.ts / navComposition.ts (trivial
 * happy defaults) AND the nav-series RPC under test (configurable per call).
 */
function makeLocals(
	navSeriesRpc: { data?: unknown; error?: { message: string } | null },
	navBoundaryRpc: { data?: unknown; error?: { message: string } | null } = {
		data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }]
	}
) {
	const rpc = vi.fn(async (fnName: string) => {
		switch (fnName) {
			case 'fn_compute_nav':
				return { data: 0, error: null };
			case 'fn_aggregation_has_stale_constituent':
				return { data: [{ is_stale: false, stale_items: [] }], error: null };
			case 'fn_nav_composition':
				return {
					data: { groups: [], buildups: { total_non_re: 0, gross_total: 0, debt: 0, realized_tax_liab: 0, unrealized_tax_liab: 0 }, nav: 0 },
					error: null
				};
			case 'fn_nav_series_inflation_adjusted':
				return { data: navSeriesRpc.data ?? null, error: navSeriesRpc.error ?? null };
			case 'fn_first_cron_checkpoint':
				return { data: navBoundaryRpc.data ?? null, error: navBoundaryRpc.error ?? null };
			default:
				throw new Error(`unexpected rpc: ${fnName}`);
		}
	});
	const from = vi.fn(() => ({
		select: vi.fn(() => ({
			or: vi.fn(async () => ({ count: 0, error: null }))
		}))
	}));
	const supabase = { schema: vi.fn(() => ({ rpc, from })) };
	const locals = {
		safeGetSession: async () => ({ session: {}, user: SESSION_USER }),
		supabase
	};
	return { locals, rpc };
}

function makeEvent(
	searchParams: string,
	navSeriesRpc: { data?: unknown; error?: { message: string } | null },
	navBoundaryRpc?: { data?: unknown; error?: { message: string } | null }
) {
	const { locals, rpc } =
		navBoundaryRpc !== undefined ? makeLocals(navSeriesRpc, navBoundaryRpc) : makeLocals(navSeriesRpc);
	const url = new URL(`http://localhost/${searchParams ? `?${searchParams}` : ''}`);
	const event = { locals, url } as unknown as Parameters<typeof load>[0];
	return { event, rpc };
}

describe('load() — §2.1.2.d chart-scoped navSeries dispatch', () => {
	it('invalid params: navSeriesParamsError set, navSeries stays null, NO RPC attempted, page still loads', async () => {
		const { event, rpc } = makeEvent('granularity=yearly', { data: [] });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navSeriesParamsError).toContain('granularity');
		expect(data.navSeries).toBeNull();
		// The page's other sections still resolved — this is the "chart-scoped, not
		// page-scoped" property under test. No throw reached this point at all.
		expect(data.netWorth).toBe(0);
		// The nav-series RPC was never called for an invalid-params request.
		expect(rpc).not.toHaveBeenCalledWith('fn_nav_series_inflation_adjusted', expect.anything());
	});

	it('an UNRECOGNIZED key is also chart-scoped (the .strict() fence, not a page throw)', async () => {
		const { event } = makeEvent('bogus=anything', { data: [] });
		const data = await runLoad(event);
		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navSeries).toBeNull();
	});

	it('valid params, RPC error: navSeriesParamsError stays null, navSeries is null (read failed)', async () => {
		const { event } = makeEvent('granularity=monthly', { error: { message: 'permission denied' } });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toBeNull();
	});

	it('valid params, genuinely empty result: navSeriesParamsError null, navSeries is [] (NOT null)', async () => {
		const { event } = makeEvent('granularity=monthly', { data: [] });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toEqual([]);
		expect(data.navSeries).not.toBeNull();
	});

	it('valid params, populated result: rows pass through under a successful, error-free state', async () => {
		const row = {
			point_date: '2020-01-31',
			nav_nominal: 1000,
			checkpoint_date: '2020-01-31',
			nav_inflation_adjusted: 1010,
			cpi_period: '2020-01-01',
			cpi_value: 258.7,
			cpi_is_carried: false,
			cpi_carried_from: null,
			cpi_period_was_due: true,
			cpi_nonpublication_on_record: false,
			cpi_coverage_through: '2026-06-01'
		};
		const { event } = makeEvent('granularity=monthly', { data: [row] });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toEqual([row]);
	});

	it('navSeriesParams reflects the resolved (defaulted) window even on the invalid-params path', async () => {
		const { event } = makeEvent('granularity=yearly', { data: [] });
		const data = await runLoad(event);
		// Coherent defaults for Frontend's controls, even though nothing was queried.
		expect(data.navSeriesParams.granularity).toBe('monthly');
		expect(typeof data.navSeriesParams.start).toBe('string');
		expect(typeof data.navSeriesParams.end).toBe('string');
	});
});

describe('load() — §2.1.2 navBoundary (069), fetched independently of chart params', () => {
	it('the REAL empty-store row (state a) passes through — NOT null', async () => {
		const { event } = makeEvent('granularity=monthly', { data: [] }, {
			data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }]
		});
		const data = await runLoad(event);
		expect(data.navBoundary).toEqual({
			first_cron_checkpoint: null,
			has_cron_rows: false,
			has_imported_rows: false
		});
		expect(data.navBoundary).not.toBeNull();
	});

	it('the mixed state (d) passes through with a real date', async () => {
		const { event } = makeEvent('granularity=monthly', { data: [] }, {
			data: [{ first_cron_checkpoint: '2026-08-01', has_cron_rows: true, has_imported_rows: true }]
		});
		const data = await runLoad(event);
		expect(data.navBoundary).toEqual({
			first_cron_checkpoint: '2026-08-01',
			has_cron_rows: true,
			has_imported_rows: true
		});
	});

	it('an RPC error → navBoundary is null (distinguishable from the real empty-store row)', async () => {
		const { event } = makeEvent('granularity=monthly', { data: [] }, {
			error: { message: 'permission denied' }
		});
		const data = await runLoad(event);
		expect(data.navBoundary).toBeNull();
	});

	it('is fetched even when navSeriesParamsError is set — independent of chart params', async () => {
		const { event, rpc } = makeEvent('granularity=yearly', { data: [] }, {
			data: [{ first_cron_checkpoint: '2026-08-01', has_cron_rows: true, has_imported_rows: false }]
		});
		const data = await runLoad(event);
		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navBoundary).toEqual({
			first_cron_checkpoint: '2026-08-01',
			has_cron_rows: true,
			has_imported_rows: false
		});
		expect(rpc).toHaveBeenCalledWith('fn_first_cron_checkpoint');
	});
});
