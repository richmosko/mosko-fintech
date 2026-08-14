// nav-delta-panel.ts — server-side read for the §2.1.3.a multi-horizon
// NAV-delta panel (V1.1 / SELF-221 backend; SELF-222 is the UI consumer).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's `071` pfin.fn_nav_delta_panel — a SECURITY INVOKER
// read-composition helper (Lock 11; prosecdef=f) that reads pfin.nav_daily
// (054) directly by at-or-before carry-forward and pfin.fn_cpi_u_index_for_period
// (066) for every CPI observation, with "today" from pfin.fn_server_today
// (070, ADR-044 R2) — through the per-request anon/authenticated client,
// exactly the same client netWorth.ts / navComposition.ts / staleness.ts /
// nav-series.ts / nav-boundary.ts already use, so the caller's RLS context
// propagates (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11).
// Owner-isolation is INHERITED at the DB via RLS on pfin.nav_daily — a
// cross-tenant caller gets five all-NULL rows, fails closed (071's own
// TENANT FENCE section).
//
// Row type is IMPORTED from $lib/nav-delta-panel.ts (Frontend-owned,
// browser-safe), not redeclared — same anti-drift pattern as nav-series.ts's
// import of NavSeriesPoint and nav-boundary.ts's import of NavBoundary.
//
// ZERO-ARG RPC — 071's parameter list is deliberately empty (tenant comes
// from session RLS; "today" comes from 070 internally). Same zero-arg call
// shape as nav-boundary.ts's fn_first_cron_checkpoint.
//
// ⚠ FAIL-SOFT TO `null`, NOT `[]` — AND THERE IS NO LEGITIMATE EMPTY-ARRAY
// STATE HERE, UNLIKE nav-series.ts. 071's own contract is "EXACTLY FIVE
// ROWS, ALWAYS" — a horizon is never absent, even when uncomputable (it
// returns its row with NULL deltas instead). So there is no "read succeeded,
// found nothing" state to distinguish from failure the way nav-series.ts's
// `[]` does: any payload that is not exactly five rows is a transport/
// contract surprise, not a legitimate state this function can represent,
// and degrades to the SAME `null` a hard RPC error would (mirrors
// nav-boundary.ts's exactly-one-row shape check, one row-count up).
//
// NO REORDERING, NO FILTERING. 071's fixed row order ('month','ytd','1y',
// '3y','5y') is part of its contract; this function passes the five rows
// through exactly as returned, coercing only the numeric transport
// representation — never re-sorting, never dropping a row, never computing
// a date client-side.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { NavDeltaPanelRow } from '$lib/nav-delta-panel';

/** Raw shape as it arrives from the RPC. Numeric columns may arrive as
 * `number` OR `string` — PostgREST's numeric serialization is not guaranteed
 * to be a JSON number for every value (nav-series.ts's / netWorth.ts's own
 * coercion idiom). */
type RawNavDeltaPanelRow = {
	horizon: string;
	anchor_date: string;
	anchor_checkpoint_date: string | null;
	current_checkpoint_date: string | null;
	delta_nominal: number | string | null;
	delta_percent: number | string | null;
	delta_inflation_adjusted: number | string | null;
	cpi_basis_period: string | null;
	cpi_any_carried: boolean | null;
	cpi_unavailable: boolean | null;
};

/** NULL passes through; a non-NULL value that fails to coerce to a finite
 * number degrades to NULL rather than poisoning the panel with NaN — 071's
 * own DB-side guards (the strictly-positive CPI fence, 053) mean this should
 * never fire in practice, but a transport-layer surprise degrading to the
 * SAME "cannot be expressed" state a legitimate NULL already means is a safe
 * failure, not a silent one: it is logged (nav-series.ts's own
 * toNumberOrNull idiom, duplicated here rather than imported — the two
 * server query modules do not share a helper module today). */
function toNumberOrNull(v: number | string | null): number | null {
	if (v === null) return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
}

function normalize(r: RawNavDeltaPanelRow): NavDeltaPanelRow {
	return {
		horizon: r.horizon as NavDeltaPanelRow['horizon'],
		anchor_date: r.anchor_date,
		anchor_checkpoint_date: r.anchor_checkpoint_date,
		current_checkpoint_date: r.current_checkpoint_date,
		delta_nominal: toNumberOrNull(r.delta_nominal),
		delta_percent: toNumberOrNull(r.delta_percent),
		delta_inflation_adjusted: toNumberOrNull(r.delta_inflation_adjusted),
		cpi_basis_period: r.cpi_basis_period,
		cpi_any_carried: r.cpi_any_carried,
		cpi_unavailable: r.cpi_unavailable
	};
}

/**
 * Load the caller's §2.1.3.a NAV-delta panel — five fixed horizons, RLS-scoped
 * via the per-request anon/authenticated client. No arguments: tenant and
 * "today" both derive server-side (session RLS and 070 respectively).
 *
 * Fail-soft on any READ error (network, RPC failure, wrong-shaped payload):
 * degrades to `null` — logged server-side, never thrown. A genuine result is
 * always exactly five rows, in 071's fixed order, passed through unchanged —
 * see the module header for why there is no legitimate `[]` state here.
 */
export async function loadNavDeltaPanel(
	supabase: SupabaseClient
): Promise<NavDeltaPanelRow[] | null> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_nav_delta_panel');

	if (error) {
		console.error('[nav-delta-panel] fn_nav_delta_panel failed:', error.message);
		return null;
	}
	if (!Array.isArray(data) || data.length !== 5) {
		// 071's own contract is "EXACTLY FIVE ROWS, ALWAYS" — anything else
		// (zero rows, more/fewer than five, a non-array payload) is a
		// transport/contract surprise, not a legitimate state this function
		// can represent. Degrades to the SAME `null` a hard RPC error would,
		// rather than guessing at a partial panel.
		console.error(
			'[nav-delta-panel] fn_nav_delta_panel returned an unexpected shape; degrading to null:',
			Array.isArray(data) ? `array length ${data.length}` : typeof data
		);
		return null;
	}

	return (data as RawNavDeltaPanelRow[]).map(normalize);
}
