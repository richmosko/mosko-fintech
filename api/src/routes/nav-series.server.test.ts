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
// ALSO locks the `chart_` NAMESPACE FIX (F/CTO-ratified 2026-08-13, Sec's param-fence
// finding, option A): a NON-namespaced param (e.g. `?utm_source=`) must be IGNORED, not
// rejected — the original defect was `Object.fromEntries(url.searchParams)` strict-parsing
// the WHOLE page's query string, so any unrelated param disabled the chart. A CHART-
// namespaced but unrecognized param (`chart_bogus`) must still be REJECTED — proving the
// fix is a namespace, not a loosened fence (see the two dedicated tests below).
//
// The rest of the route's RPCs (netWorth / staleness / composition) are mocked to trivial
// happy-path defaults — their own behavior is proven by netWorth.test.ts / navComposition.test.ts;
// this file exists only to lock the chart-scoping dispatch added around loadNavSeries().
//
// QA FINDING 1 (SELF-222 PR review) FIX: fn_nav_delta_panel had NO mock case — the switch's
// `default:` throws for an unmocked RPC name, and +page.server.ts's belt-and-suspenders
// try/catch around loadNavDeltaPanel() silently swallows that throw into `navDeltaPanel = null`.
// Every test in this file was therefore accidentally exercising ONLY the fail-soft path for
// navDeltaPanel, with nothing at load()-integration level proving the RPC's rows actually
// thread through to `data.navDeltaPanel` on success. Fixed by giving `fn_nav_delta_panel` a
// real mock case (default: the happy 5-row payload, so every EXISTING test above now takes
// the success path instead of the accidental-throw path) plus two dedicated tests below that
// assert the success-threads-through and explicit-RPC-error-fails-soft states.
//
// QA FINDING 1 (SELF-223 PR review) FIX: same gap, same fix, one surface later —
// fn_nav_reference_dates had no mock case either. Given a real-shaped default payload (the
// EMPTY-DB all-three-rows-insufficient-history shape — Backend's live smoke against the
// post-incident unseeded DB, migration 073's X1 leg) plus the same success/fail-soft/
// independent-of-chart-params test trio.

import { describe, it, expect, vi } from 'vitest';
import { load } from './+page.server';
import type { NavSeriesPoint } from '$lib/nav-series';
import type { NavDeltaPanelRow } from '$lib/nav-delta-panel';
import type { NavReferenceDateRow } from '$lib/nav-reference-dates';

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };

// Verbatim real local smoke-verify sample from Backend's SELF-222 hand-off (migration 071
// against seeded tenant b1aa21a2) — same fixture already used in
// $lib/components/NavDeltaPanel.ssr.test.ts, reused here as the default happy-path RPC payload.
// ⚠ delta_inflation_adjusted_percent values are SYNTHETIC (071's sample predates migration 072,
// which added the column; no regenerated real sample was available — the local DB lost its seed
// data in a QA incident, recovery F/CTO-gated). Deliberately round, non-derived placeholders —
// see the identical fixture + fuller note in $lib/components/NavDeltaPanel.ssr.test.ts.
const REAL_NAV_DELTA_PANEL_SAMPLE: NavDeltaPanelRow[] = [
	{
		horizon: 'month',
		anchor_date: '2026-07-31',
		anchor_checkpoint_date: '2026-07-31',
		current_checkpoint_date: '2026-08-10',
		delta_nominal: -8217654.37,
		delta_percent: -99.40310112495464,
		delta_inflation_adjusted: null,
		delta_inflation_adjusted_percent: null,
		cpi_basis_period: null,
		cpi_any_carried: null,
		cpi_unavailable: null
	},
	{
		horizon: 'ytd',
		anchor_date: '2025-12-31',
		anchor_checkpoint_date: '2025-12-31',
		current_checkpoint_date: '2026-08-10',
		delta_nominal: -7828654.37,
		delta_percent: -99.37362744351358,
		delta_inflation_adjusted: null,
		delta_inflation_adjusted_percent: null,
		cpi_basis_period: null,
		cpi_any_carried: null,
		cpi_unavailable: null
	},
	{
		horizon: '1y',
		anchor_date: '2025-07-31',
		anchor_checkpoint_date: '2025-07-31',
		current_checkpoint_date: '2026-08-10',
		delta_nominal: -7546654.37,
		delta_percent: -99.35037348604529,
		delta_inflation_adjusted: -7571771.53943,
		delta_inflation_adjusted_percent: -95.1,
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: false
	},
	{
		horizon: '3y',
		anchor_date: '2023-07-31',
		anchor_checkpoint_date: '2023-07-31',
		current_checkpoint_date: '2026-08-10',
		delta_nominal: -6955654.37,
		delta_percent: -99.2955655960029,
		delta_inflation_adjusted: -7377910.52013,
		delta_inflation_adjusted_percent: -94.8,
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: false
	},
	{
		horizon: '5y',
		anchor_date: '2021-07-31',
		anchor_checkpoint_date: '2021-07-31',
		current_checkpoint_date: '2026-08-10',
		delta_nominal: -6307654.37,
		delta_percent: -99.22375916312726,
		delta_inflation_adjusted: -7497862.86149,
		delta_inflation_adjusted_percent: -94.5,
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: false
	}
];

// EMPTY-DB all-three-rows-insufficient-history shape (Backend's SELF-223 live smoke against the
// post-incident unseeded local DB, migration 073's X1 leg — literally the state a brand-new
// user boots into: zero nav_daily rows, so no checkpoint reaches ANY of the three reference
// dates). reference_checkpoint_date / nav / nav_prior_yr_dollars are the LOAD-BEARING, verified
// part of this fixture (all NULL on all three rows). The cpi_* fields don't affect rendering
// here at all — isInsufficientHistory takes precedence over isCpiUnresolvable in the component
// — so their values below are a best-effort "no CPI coverage at all" reading (cpi_period null
// only on this_month per Backend's note; cpi_any_carried/cpi_unavailable never null per the 073
// correction), not independently verified against a real payload.
const EMPTY_DB_NAV_REFERENCE_DATES: NavReferenceDateRow[] = [
	{
		reference: 'this_month',
		reference_date: '2026-08-31',
		reference_checkpoint_date: null,
		nav: null,
		nav_prior_yr_dollars: null,
		cpi_period: null,
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: true
	},
	{
		reference: 'prior_month',
		reference_date: '2026-07-31',
		reference_checkpoint_date: null,
		nav: null,
		nav_prior_yr_dollars: null,
		cpi_period: '2026-07-01',
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: true
	},
	{
		reference: 'prior_year_end',
		reference_date: '2025-12-31',
		reference_checkpoint_date: null,
		nav: null,
		nav_prior_yr_dollars: null,
		cpi_period: '2025-12-01',
		cpi_basis_period: '2025-12-01',
		cpi_any_carried: false,
		cpi_unavailable: true
	}
];

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
	navDeltaPanel: NavDeltaPanelRow[] | null;
	navReferenceDates: NavReferenceDateRow[] | null;
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
	},
	navDeltaPanelRpc: { data?: unknown; error?: { message: string } | null } = {
		data: REAL_NAV_DELTA_PANEL_SAMPLE
	},
	navReferenceDatesRpc: { data?: unknown; error?: { message: string } | null } = {
		data: EMPTY_DB_NAV_REFERENCE_DATES
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
					data: {
						groups: [],
						// SELF-268 / E41-E42: envelopes, not plain numbers.
						buildups: {
							total_non_re: 0,
							gross_total: 0,
							debt: 0,
							realized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' },
							unrealized_tax_liab: { status: 'unavailable', reason: 'no_schedule_any_year' }
						},
						nav: 0
					},
					error: null
				};
			case 'fn_tax_authority_ledgers':
				// SELF-268 AC 10a: trivial empty default — this file's own scope is chart-scoping,
				// not the exclusion list (see nav-composition-flip.server.test.ts for that).
				return { data: [], error: null };
			case 'fn_nav_series_inflation_adjusted':
				return { data: navSeriesRpc.data ?? null, error: navSeriesRpc.error ?? null };
			case 'fn_first_cron_checkpoint':
				return { data: navBoundaryRpc.data ?? null, error: navBoundaryRpc.error ?? null };
			case 'fn_nav_delta_panel':
				return { data: navDeltaPanelRpc.data ?? null, error: navDeltaPanelRpc.error ?? null };
			case 'fn_nav_reference_dates':
				return { data: navReferenceDatesRpc.data ?? null, error: navReferenceDatesRpc.error ?? null };
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
	navBoundaryRpc?: { data?: unknown; error?: { message: string } | null },
	navDeltaPanelRpc?: { data?: unknown; error?: { message: string } | null },
	navReferenceDatesRpc?: { data?: unknown; error?: { message: string } | null }
) {
	// Nested rather than flattened: each optional RPC config is passed only when EVERY preceding
	// one was also explicitly supplied, so makeLocals' own defaults still apply to any trailing
	// gap (a caller can't skip a positional arg without supplying the ones before it).
	const { locals, rpc } =
		navBoundaryRpc !== undefined
			? navDeltaPanelRpc !== undefined
				? navReferenceDatesRpc !== undefined
					? makeLocals(navSeriesRpc, navBoundaryRpc, navDeltaPanelRpc, navReferenceDatesRpc)
					: makeLocals(navSeriesRpc, navBoundaryRpc, navDeltaPanelRpc)
				: makeLocals(navSeriesRpc, navBoundaryRpc)
			: makeLocals(navSeriesRpc);
	const url = new URL(`http://localhost/${searchParams ? `?${searchParams}` : ''}`);
	const event = { locals, url } as unknown as Parameters<typeof load>[0];
	return { event, rpc };
}

describe('load() — §2.1.2.d chart-scoped navSeries dispatch', () => {
	it('invalid params: navSeriesParamsError set, navSeries stays null, NO RPC attempted, page still loads', async () => {
		const { event, rpc } = makeEvent('chart_granularity=yearly', { data: [] });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navSeriesParamsError).toContain('chart_granularity');
		expect(data.navSeries).toBeNull();
		// The page's other sections still resolved — this is the "chart-scoped, not
		// page-scoped" property under test. No throw reached this point at all.
		expect(data.netWorth).toBe(0);
		// The nav-series RPC was never called for an invalid-params request.
		expect(rpc).not.toHaveBeenCalledWith('fn_nav_series_inflation_adjusted', expect.anything());
	});

	it("a NON-NAMESPACED key (e.g. an analytics tracker param) is IGNORED, not rejected — the chart_ namespace fix under test (F/CTO-ratified 2026-08-13, Sec's param-fence finding)", async () => {
		const { event } = makeEvent('utm_source=newsletter', { data: [] });
		const data = await runLoad(event);
		// This is the actual regression this namespace exists to close: before
		// the fix, ANY unrelated page param tripped .strict() on the WHOLE
		// query string and disabled the chart. Now it's simply not chart input.
		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toEqual([]);
	});

	it('a CHART-NAMESPACED but UNRECOGNIZED key (chart_bogus) still trips the fence — NOT pick-then-parse', async () => {
		const { event, rpc } = makeEvent('chart_bogus=anything', { data: [] });
		const data = await runLoad(event);
		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navSeries).toBeNull();
		expect(rpc).not.toHaveBeenCalledWith('fn_nav_series_inflation_adjusted', expect.anything());
	});

	it('a non-namespaced key ALONGSIDE valid chart_ params does not interfere with them', async () => {
		const { event } = makeEvent('chart_granularity=weekly&utm_source=newsletter', { data: [] });
		const data = await runLoad(event);
		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeriesParams.granularity).toBe('weekly');
	});

	it('valid params, RPC error: navSeriesParamsError stays null, navSeries is null (read failed)', async () => {
		const { event } = makeEvent('chart_granularity=monthly', { error: { message: 'permission denied' } });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toBeNull();
	});

	it('valid params, genuinely empty result: navSeriesParamsError null, navSeries is [] (NOT null)', async () => {
		const { event } = makeEvent('chart_granularity=monthly', { data: [] });
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
		const { event } = makeEvent('chart_granularity=monthly', { data: [row] });
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).toBeNull();
		expect(data.navSeries).toEqual([row]);
	});

	it('navSeriesParams reflects the resolved (defaulted) window even on the invalid-params path', async () => {
		const { event } = makeEvent('chart_granularity=yearly', { data: [] });
		const data = await runLoad(event);
		// Coherent defaults for Frontend's controls, even though nothing was queried.
		expect(data.navSeriesParams.granularity).toBe('monthly');
		expect(typeof data.navSeriesParams.start).toBe('string');
		expect(typeof data.navSeriesParams.end).toBe('string');
	});
});

describe('load() — §2.1.2 navBoundary (069), fetched independently of chart params', () => {
	it('the REAL empty-store row (state a) passes through — NOT null', async () => {
		const { event } = makeEvent('chart_granularity=monthly', { data: [] }, {
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
		const { event } = makeEvent('chart_granularity=monthly', { data: [] }, {
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
		const { event } = makeEvent('chart_granularity=monthly', { data: [] }, {
			error: { message: 'permission denied' }
		});
		const data = await runLoad(event);
		expect(data.navBoundary).toBeNull();
	});

	it('is fetched even when navSeriesParamsError is set — independent of chart params', async () => {
		const { event, rpc } = makeEvent('chart_granularity=yearly', { data: [] }, {
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

// QA Finding 1 (SELF-222 PR review): closes the load-level gap — before this, EVERY test above
// exercised navDeltaPanel only via the accidental `default:`-throw-swallowed-by-try/catch path
// (see the module header). These two tests are the CATCH CRITERION: one fails if +page.server.ts
// stops returning the RPC's rows as `data.navDeltaPanel` (success path), the other fails if an
// RPC error stops degrading to `null` (explicit fail-soft, not accidental).
describe('load() — §2.1.3.a navDeltaPanel (071), fetched independently of chart params', () => {
	it('a genuine 5-row RPC result threads through to data.navDeltaPanel UNCHANGED (success path)', async () => {
		const { event, rpc } = makeEvent(
			'chart_granularity=monthly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ data: REAL_NAV_DELTA_PANEL_SAMPLE }
		);
		const data = await runLoad(event);

		expect(data.navDeltaPanel).toEqual(REAL_NAV_DELTA_PANEL_SAMPLE);
		expect(data.navDeltaPanel).not.toBeNull();
		expect(rpc).toHaveBeenCalledWith('fn_nav_delta_panel');
	});

	it('an RPC error → navDeltaPanel is null (EXPLICIT fail-soft, not the accidental unmocked-throw path)', async () => {
		const { event } = makeEvent(
			'chart_granularity=monthly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ error: { message: 'permission denied' } }
		);
		const data = await runLoad(event);

		expect(data.navDeltaPanel).toBeNull();
	});

	it('is fetched even when navSeriesParamsError is set — independent of chart params, same as navBoundary', async () => {
		const { event, rpc } = makeEvent(
			'chart_granularity=yearly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ data: REAL_NAV_DELTA_PANEL_SAMPLE }
		);
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navDeltaPanel).toEqual(REAL_NAV_DELTA_PANEL_SAMPLE);
		expect(rpc).toHaveBeenCalledWith('fn_nav_delta_panel');
	});
});

// QA Finding 1 (SELF-223 PR review): same load-level gap, same fix, one surface later — before
// this, EVERY test above exercised navReferenceDates only via the accidental
// `default:`-throw-swallowed-by-try/catch path. These three tests are the CATCH CRITERION: one
// fails if +page.server.ts stops returning the RPC's rows as `data.navReferenceDates` (success
// path, using the real-shaped empty-DB fixture), one fails if an RPC error stops degrading to
// `null` (explicit fail-soft, not accidental), one fails if the fetch stops being independent of
// chart params — mirrors the navDeltaPanel trio directly above.
describe('load() — §2.1.4 navReferenceDates (073), fetched independently of chart params', () => {
	it('a genuine 3-row RPC result threads through to data.navReferenceDates UNCHANGED (success path)', async () => {
		const { event, rpc } = makeEvent(
			'chart_granularity=monthly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ data: REAL_NAV_DELTA_PANEL_SAMPLE },
			{ data: EMPTY_DB_NAV_REFERENCE_DATES }
		);
		const data = await runLoad(event);

		expect(data.navReferenceDates).toEqual(EMPTY_DB_NAV_REFERENCE_DATES);
		expect(data.navReferenceDates).not.toBeNull();
		expect(rpc).toHaveBeenCalledWith('fn_nav_reference_dates');
	});

	it('an RPC error → navReferenceDates is null (EXPLICIT fail-soft, not the accidental unmocked-throw path)', async () => {
		const { event } = makeEvent(
			'chart_granularity=monthly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ data: REAL_NAV_DELTA_PANEL_SAMPLE },
			{ error: { message: 'permission denied' } }
		);
		const data = await runLoad(event);

		expect(data.navReferenceDates).toBeNull();
	});

	it('is fetched even when navSeriesParamsError is set — independent of chart params, same as navDeltaPanel', async () => {
		const { event, rpc } = makeEvent(
			'chart_granularity=yearly',
			{ data: [] },
			{ data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }] },
			{ data: REAL_NAV_DELTA_PANEL_SAMPLE },
			{ data: EMPTY_DB_NAV_REFERENCE_DATES }
		);
		const data = await runLoad(event);

		expect(data.navSeriesParamsError).not.toBeNull();
		expect(data.navReferenceDates).toEqual(EMPTY_DB_NAV_REFERENCE_DATES);
		expect(rpc).toHaveBeenCalledWith('fn_nav_reference_dates');
	});
});
