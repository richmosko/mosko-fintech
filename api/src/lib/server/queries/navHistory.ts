// navHistory.ts — server-side read for the §2.1.2.c NAV-over-time chart
// (SELF-220: nominal + inflation-adjusted, dual series). Backend-owned server
// surface (ARCH §4.1 allowlist).
//
// Calls Architect's `067` pfin.fn_nav_series_inflation_adjusted — a SECURITY
// INVOKER read-composition helper (Lock 11; prosecdef=f) that itself composes
// `062` (pfin.fn_nav_series, the nominal series) + `066`
// (pfin.fn_cpi_u_index_for_period, the CPI-U levels) and reads no relation of
// its own — through the per-request anon/authenticated client, exactly the
// same client netWorth.ts / navComposition.ts / staleness.ts already use, so
// the caller's RLS context propagates (users_id = auth.uid()), NEVER
// service_role (RT-26 / Lock 11). Owner-isolation is INHERITED at the DB via
// RLS on `pfin.nav_daily` reached through 062 — a cross-tenant caller sees
// zero rows, fails closed (067's own TENANT FENCE section).
//
// 067 RETURNS TABLE(...) — a SET-RETURNING RPC. supabase-js hands back an
// ARRAY of rows (contrast navComposition.ts's SCALAR jsonb RPC, which takes
// the object directly, and staleness.ts's set-returning-but-exactly-one-row
// RPC, which takes [0]). Here every row is wanted — this function returns the
// array, unaggregated and unreduced.
//
// ⚠ NO AGGREGATION HAPPENS HERE, AND NONE MAY BE ADDED. 067's own header is
// explicit that `nav_inflation_adjusted` is NULLABLE BY DESIGN and that a
// consumer summing/averaging/maxing across the series must decide EXPLICITLY
// what a NULL point means — this function is not that consumer. It returns
// 067's row set exactly as emitted, in 067's own ascending-by-point_date
// order (067's CONTRACT: "callers may rely on it"), so that decision stays
// with whatever renders the chart, not buried in a query helper nobody
// reviewing the chart code would think to check.
//
// Fail-soft is load-bearing (mirrors netWorth.ts / navComposition.ts /
// staleness.ts): any error degrades to an EMPTY ARRAY (logged server-side,
// never thrown) — a chart-data failure must never take down the §2.1.1
// headline NAV or any other section of this dashboard route. Unlike
// netWorth.ts's `accountPresence` hazard, there is no ambiguous falsy value
// to guard here: an empty array IS the correct, legible "nothing to plot"
// state, not a collapsed unknown.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { NavHistoryGranularity } from '$lib/server/schemas/navHistory';
import { serverTodayAsOf } from '$lib/server/time/asOf';

/**
 * One point of the §2.1.2.c series, normalized. Mirrors 067's ELEVEN-column
 * contract field-for-field — see migration 067's CONTRACT block for full
 * per-column semantics (the `cpi_*` columns implement the §2.4.4 CPI
 * rendering rule: NULL cpi_value → UNAVAILABLE; cpi_is_carried AND
 * cpi_period_was_due → an informational carried-basis marker; otherwise the
 * plain figure — rendering that rule is the chart's job, not this file's).
 */
export type NavHistoryRow = {
	point_date: string;
	/** 062's nav_value, passed through unmodified. */
	nav_nominal: number;
	/** 062's checkpoint_date — surface NAV staleness when this differs from point_date. */
	checkpoint_date: string;
	/** NULL — never zero — when either CPI leg is absent or non-positive (067 DIVISION SAFETY). */
	nav_inflation_adjusted: number | null;
	/** point_date normalized to first-of-month (066's grain). */
	cpi_period: string;
	/** NULL when the CPI store has no usable print for cpi_period. */
	cpi_value: number | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	/** The CPI store's trailing coverage edge — identical on every row (067). */
	cpi_coverage_through: string | null;
};

/**
 * Raw shape as it arrives from the RPC. Numeric columns may arrive as
 * `number` OR `string` — PostgREST's numeric serialization is not guaranteed
 * to be a JSON number for every value, mirroring netWorth.ts's own coercion
 * idiom ("a Postgres numeric may arrive as number OR string → coerce").
 */
type RawNavHistoryRow = {
	point_date: string;
	nav_nominal: number | string;
	checkpoint_date: string;
	nav_inflation_adjusted: number | string | null;
	cpi_period: string;
	cpi_value: number | string | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	cpi_coverage_through: string | null;
};

/** NULL passes through; a non-NULL value that fails to coerce to a finite
 * number degrades to NULL rather than poisoning the chart with NaN — 067's
 * own DB-side guards mean this should never fire in practice (nav_value is
 * NOT NULL on every emitted row and the CPI legs are finiteness-fenced at
 * 053), but a transport-layer surprise degrading to the SAME "unavailable"
 * state a legitimate NULL already means is a safe failure, not a silent one:
 * it is logged, and every one of these columns is designed to be readably
 * absent on the rendered chart. */
function toNumberOrNull(v: number | string | null): number | null {
	if (v === null) return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
}

function normalize(r: RawNavHistoryRow): NavHistoryRow {
	// nav_nominal is NOT NULL on every row 062 emits (067's CONTRACT) — a
	// coercion failure here is transport corruption, not a legitimate state,
	// so it degrades to 0 rather than null (there is no "nav unavailable for
	// one point" rendering state on the nominal leg the way there is on the
	// inflation-adjusted one; a corrupted point degrading to 0 is at least
	// visibly wrong on a NAV chart rather than silently typed away).
	return {
		point_date: r.point_date,
		nav_nominal: toNumberOrNull(r.nav_nominal) ?? 0,
		checkpoint_date: r.checkpoint_date,
		nav_inflation_adjusted: toNumberOrNull(r.nav_inflation_adjusted),
		cpi_period: r.cpi_period,
		cpi_value: toNumberOrNull(r.cpi_value),
		cpi_is_carried: r.cpi_is_carried,
		cpi_carried_from: r.cpi_carried_from,
		cpi_period_was_due: r.cpi_period_was_due,
		cpi_nonpublication_on_record: r.cpi_nonpublication_on_record,
		cpi_coverage_through: r.cpi_coverage_through
	};
}

/** Trailing window width for the chart's default range when the caller
 * supplies neither `start` nor `end` — PRD §2.1.3's 5-Year horizon (ADR-053's
 * own context: "PRD §2.1.3 mandates 1-Year, 3-Year and 5-Year delta horizons
 * in V1"), expressed as whole months so it composes with any granularity. */
const DEFAULT_WINDOW_MONTHS = 60;

/** `iso` minus `months`, UTC, calendar-month arithmetic (mirrors netWorth.ts's
 * `nextDayIso()` idiom: UTC `Date` methods, not string surgery, so month/year
 * boundaries are correct by construction). A day-of-month overflow (e.g.
 * March 31 minus 1 month) ROLLS FORWARD per JS `Date` semantics rather than
 * clamping — acceptable here because this derives a WINDOW EDGE for a
 * default range, not an exact boundary a comparison depends on: a day or two
 * of slack on the default window's start is not a correctness hazard the way
 * a shifted `p_as_of` would be on a single-point valuation. */
function monthsBeforeIso(iso: string, months: number): string {
	const d = new Date(`${iso}T00:00:00Z`);
	d.setUTCMonth(d.getUTCMonth() - months);
	return d.toISOString().slice(0, 10);
}

/**
 * Resolve the chart's [start, end] window. Each half independently defaults
 * when absent: `end` defaults to TODAY (via `serverTodayAsOf()` — the SAME
 * server-clock-in-UTC derivation every other as-of on this route uses, see
 * asOf.ts; NOT re-derived here with a bare `new Date()`, which is exactly the
 * proliferation that file's header warns against) and `start` defaults to
 * `end` minus DEFAULT_WINDOW_MONTHS — relative to the RESOLVED end, so a
 * caller-supplied `end` with no `start` still gets a sensible trailing window
 * ending where they asked, not one anchored to today regardless.
 *
 * ⚠ WHY THESE ARE PLAIN STRINGS, NOT `ZoneResolvedAsOf` — A NAMED EXEMPTION,
 * per asOf.ts's own convention that every departure from the brand states
 * what it rests on. `ZoneResolvedAsOf` guards ONE specific hazard: a date
 * compared against a `timestamptz::date` cast, evaluated in the DB SESSION
 * timezone, which can disagree with a UTC-derived string for a same-day
 * boundary. `pfin.nav_daily.nav_date` (054) — what 067's p_start_date /
 * p_end_date ultimately bound, through 062 — is a bare `date` column, NOT
 * `timestamptz`: there is no session-timezone cast anywhere on this path for
 * these two parameters to disagree with. 067's own header states
 * independently that the function "consults no clock... at any depth" and
 * performs no date arithmetic at all. The brand's guarantee (the zone
 * question has been resolved) is therefore ALREADY TRUE of a bare UTC ISO
 * string on THIS specific path — there is no unresolved zone question here
 * to brand against. If a future revision adds a `timestamptz`-compared
 * parameter to this call, THAT call site — not this one — is where the
 * brand becomes load-bearing.
 *
 * If BOTH `start` and `end` are supplied, both are returned unchanged
 * (already validated by navHistoryParamsSchema) — this function only fills
 * in what is MISSING, never overrides what was given.
 */
export function resolveNavHistoryWindow(
	start: string | undefined,
	end: string | undefined
): { start: string; end: string } {
	const resolvedEnd = end ?? serverTodayAsOf();
	const resolvedStart = start ?? monthsBeforeIso(resolvedEnd, DEFAULT_WINDOW_MONTHS);
	return { start: resolvedStart, end: resolvedEnd };
}

/**
 * Load the caller's §2.1.2.c NAV-over-time series, RLS-scoped via the
 * per-request anon/authenticated client. `startDate`/`endDate` are ISO date
 * strings (YYYY-MM-DD) — already validated by navHistoryParamsSchema and/or
 * defaulted to the 60-month window by the caller; this function performs no
 * further validation and trusts its arguments (067 itself still RAISEs on an
 * inverted or malformed range — see 062's CONTRACT — so a caller bug here
 * fails loud at the RPC boundary rather than returning silently-wrong rows).
 *
 * Fail-soft on any READ error (network, RPC failure, unexpected payload
 * shape): degrades to `[]`, logged server-side. See module header.
 */
export async function loadNavHistory(
	supabase: SupabaseClient,
	granularity: NavHistoryGranularity,
	startDate: string,
	endDate: string
): Promise<NavHistoryRow[]> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_nav_series_inflation_adjusted', {
		p_granularity: granularity,
		p_start_date: startDate,
		p_end_date: endDate
	});

	if (error) {
		console.error('[navHistory] fn_nav_series_inflation_adjusted failed:', error.message);
		return [];
	}
	if (!Array.isArray(data)) {
		console.error(
			'[navHistory] fn_nav_series_inflation_adjusted returned a non-array payload; degrading to empty series'
		);
		return [];
	}

	return (data as RawNavHistoryRow[]).map(normalize);
}
