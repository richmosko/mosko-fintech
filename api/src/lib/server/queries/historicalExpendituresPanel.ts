// historicalExpendituresPanel.ts — server-side read for the §2.3.4 Historical Expenditures panel
// (SELF-256, loader leg). Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's 098 pair — pfin.fn_historical_expenditures(p_as_of) (096, CoR'd by 098; the
// series) and pfin.fn_expenditures_unclassified_count(p_as_of) (098, new; AC9's window-scoped N)
// — both SECURITY INVOKER read-composition (Lock 11; prosecdef=f) that ultimately compose on
// pfin.fn_cashflow_items (093), through the per-request anon/authenticated client, exactly the
// same client every other §2.1-§2.3 loader uses, so the caller's RLS context propagates. NEVER
// service_role (RT-26 / Lock 11).
//
// ⚠ ONE `asOf`, ONE CALL SITE — 098's CONTRACT literally spells "invoke BOTH in ONE statement with
// ONE p_as_of argument" as a raw multi-function SELECT. That literal shape cannot be issued from
// this client: `locals.supabase` is a PostgREST client (`@supabase/ssr`'s `createServerClient`),
// and grepping `/api` for a `pg`/`postgres` driver returns nothing — there is no raw-SQL
// passthrough anywhere in this tree, and 098 deliberately creates no third wrapping RPC (its own
// KNOWN COST note: that would be a return-shape change / DROP+CREATE, exactly what the CoR on 096
// exists to avoid). 098's own text names what actually matters, though: "ONE STATEMENT IS NOT WHAT
// MAKES THE TWO AGREE... they would still agree in two statements in the same transaction. What
// the single statement buys is that the caller cannot pass two different p_as_of values by
// accident." That property IS delivered here, at the JS boundary: exactly one function below,
// taking exactly one `asOf` parameter, is the ONLY place either RPC is invoked — there is no
// second call site where a different value could be threaded by mistake. Flagged at hand-off as a
// default-and-notify judgment call (the literal SQL shape vs. the property it exists to buy).
//
// FAIL-SOFT, INDEPENDENTLY PER LEG — mirrors the brief's binding constraint at the +page.server.ts
// boundary (a chart-query failure must never break the rollup, and vice versa) one level down:
// `points` and `unclassifiedCount` are two independent RPCs and degrade independently, matching
// HistoricalExpendituresChart.svelte's own null-tolerant contract for each prop separately.
//
// NULL vs 0 (098's own ruling on fn_expenditures_unclassified_count): `unclassified_count` is
// `null` on a NULL `p_as_of` and a real, distinguishable `0` when the window holds nothing
// unclassified. NEVER coalesced to 0 anywhere in this file — coalescing would hand the component a
// false "nothing outstanding" signal derived from no data (098's header states the same hazard for
// the DB function itself; this file must not re-introduce it one layer up).

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import type { HistoricalExpenditurePoint } from '$lib/historical-expenditures';

export type HistoricalExpendituresPanel = {
	/** `null` = the RPC read failed (fail-soft, logged, never thrown). `[]` = the read succeeded
	 *  and the window holds no qualifying expense (096's dense-interior contract: a real,
	 *  distinguishable state, not an error). */
	points: HistoricalExpenditurePoint[] | null;
	/** `null` = the RPC read failed, OR the underlying `p_as_of` could not be resolved (098's own
	 *  NULL-on-NULL-argument contract). `0` = a real, distinguishable answer: nothing unclassified
	 *  in the window. Never coalesced together — see the module header. */
	unclassifiedCount: number | null;
};

/** Raw shape as one row of `fn_historical_expenditures` arrives over PostgREST. Numeric columns
 *  may arrive as `number` OR `string` — PostgREST's numeric serialization is not guaranteed to be
 *  a JSON number for every value (nav-series.ts's / netWorth.ts's own coercion idiom, duplicated
 *  here rather than imported — no shared coercion module exists across these query files today). */
type RawHistoricalExpenditurePoint = {
	month_end: string;
	expense_monthly_nominal: number | string;
	expense_monthly_inflation_adjusted: number | string | null;
	rolling_12mo_avg_inflation_adjusted: number | string | null;
	cpi_period: string;
	cpi_value: number | string | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	cpi_coverage_through: string | null;
};

/** Raw shape of `fn_expenditures_unclassified_count`'s single row. `unclassified_count` is a
 *  Postgres `bigint`, so PostgREST serializes it as a JSON string, not a number — same transport
 *  hazard as every other bigint/numeric column in this tree. */
type RawUnclassifiedCountRow = {
	unclassified_count: number | string | null;
	ms_floor: string | null;
	ms_last: string | null;
};

/** NULL passes through; a non-NULL value that fails to coerce to a finite number degrades to NULL
 *  rather than poisoning the chart with NaN — nav-series.ts's / nav-delta-panel.ts's own
 *  toNumberOrNull idiom, duplicated here for the same reason those two duplicate it from each
 *  other: no shared coercion module exists across these query files today. */
function toNumberOrNull(v: number | string | null): number | null {
	if (v === null) return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
}

function normalizePoint(r: RawHistoricalExpenditurePoint): HistoricalExpenditurePoint {
	return {
		month_end: r.month_end,
		// NEVER null on 096's contract (LEFT JOIN + coalesce(...,0)) — a coercion failure here is
		// transport corruption, not a legitimate state, so it degrades to 0 rather than null,
		// mirroring nav-series.ts's identical treatment of nav_nominal for the same reason.
		expense_monthly_nominal: toNumberOrNull(r.expense_monthly_nominal) ?? 0,
		expense_monthly_inflation_adjusted: toNumberOrNull(r.expense_monthly_inflation_adjusted),
		rolling_12mo_avg_inflation_adjusted: toNumberOrNull(r.rolling_12mo_avg_inflation_adjusted),
		cpi_period: r.cpi_period,
		cpi_value: toNumberOrNull(r.cpi_value),
		cpi_is_carried: r.cpi_is_carried,
		cpi_carried_from: r.cpi_carried_from,
		cpi_period_was_due: r.cpi_period_was_due,
		cpi_nonpublication_on_record: r.cpi_nonpublication_on_record,
		cpi_coverage_through: r.cpi_coverage_through
	};
}

/**
 * Load the caller's §2.3.4 chart series and AC9's window-scoped unclassified-item count, both
 * over the SAME `asOf` — see the module header for why this is ONE function with ONE parameter
 * rather than two independently-called loaders. Each RPC fails soft to `null` independently: a
 * read failure on one leg never blocks the other (generalizes loadCashflowCrossAccountRollup's /
 * loadNavSeries's single-leg fail-soft posture to two independent legs).
 */
export async function loadHistoricalExpendituresPanel(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<HistoricalExpendituresPanel> {
	const [pointsResult, countResult] = await Promise.all([
		supabase.schema('pfin').rpc('fn_historical_expenditures', { p_as_of: asOf }),
		supabase.schema('pfin').rpc('fn_expenditures_unclassified_count', { p_as_of: asOf })
	]);

	let points: HistoricalExpenditurePoint[] | null;
	if (pointsResult.error) {
		console.error(
			'[historicalExpendituresPanel] fn_historical_expenditures failed:',
			pointsResult.error.message
		);
		points = null;
	} else if (!Array.isArray(pointsResult.data)) {
		console.error(
			'[historicalExpendituresPanel] fn_historical_expenditures returned a non-array payload; degrading to null'
		);
		points = null;
	} else {
		points = (pointsResult.data as RawHistoricalExpenditurePoint[]).map(normalizePoint);
	}

	let unclassifiedCount: number | null;
	if (countResult.error) {
		console.error(
			'[historicalExpendituresPanel] fn_expenditures_unclassified_count failed:',
			countResult.error.message
		);
		unclassifiedCount = null;
	} else if (!Array.isArray(countResult.data) || countResult.data.length !== 1) {
		// 098's own CONTRACT: "EXACTLY ONE ROW, ALWAYS." Anything else (zero rows, more than one,
		// a non-array payload) is a transport/contract surprise, not a legitimate state this
		// function can represent — degrades to the SAME null an RPC error would, rather than
		// guessing at a partial answer or coalescing toward 0.
		console.error(
			'[historicalExpendituresPanel] fn_expenditures_unclassified_count returned an unexpected shape; degrading to null'
		);
		unclassifiedCount = null;
	} else {
		const row = (countResult.data as RawUnclassifiedCountRow[])[0];
		unclassifiedCount = toNumberOrNull(row.unclassified_count);
	}

	return { points, unclassifiedCount };
}
