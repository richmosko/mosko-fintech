// nav-reference-dates.ts — server-side read for the §2.1.4 NAV-at-three-
// reference-dates panel (V1.1 / SELF-223 backend; SELF-223's own UI is the
// consumer). Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's pfin.fn_nav_reference_dates — migration 073, NOT YET
// MERGED as of this file's authoring. Written directly against the
// F/CTO-ratified contract (temp/pm-self223-ac-rewrite.md v3, jointly agreed
// with temp/architect-self223-reconciliation.md §5) per team-lead's
// direction not to block on 073 landing; re-verify column names/order and
// SECURITY posture against the live migration once it merges, same as any
// consumer authored ahead of its DDL. Expected posture per the ratified
// contract: SECURITY INVOKER read-composition (Lock 11; prosecdef=f) that
// reads pfin.nav_daily (054) directly by at-or-before carry-forward and
// pfin.fn_cpi_u_index_for_period (066) for every CPI observation, with
// "today" from pfin.fn_server_today (070, ADR-044 R2) — through the
// per-request anon/authenticated client, exactly the same client
// netWorth.ts / navComposition.ts / staleness.ts / nav-series.ts /
// nav-boundary.ts / nav-delta-panel.ts already use, so the caller's RLS
// context propagates (users_id = auth.uid()), NEVER service_role (RT-26 /
// Lock 11). Owner-isolation is INHERITED at the DB via RLS on pfin.nav_daily
// — a cross-tenant caller is expected to get three all-NULL rows, fails
// closed (071/072's precedent, carried into 073's own TENANT FENCE section).
//
// Row type is IMPORTED from $lib/nav-reference-dates.ts (Frontend-owned,
// browser-safe), not redeclared — same anti-drift pattern as
// nav-delta-panel.ts's import of NavDeltaPanelRow.
//
// ZERO-ARG RPC — the ratified contract's parameter list is deliberately
// empty (tenant comes from session RLS; "today" comes from 070 internally;
// no p_users_id, no p_scope — pfin.scope does not exist). Same zero-arg call
// shape as nav-boundary.ts's fn_first_cron_checkpoint and
// nav-delta-panel.ts's fn_nav_delta_panel.
//
// ⚠ FAIL-SOFT TO `null`, NOT `[]` — AND THERE IS NO LEGITIMATE EMPTY-ARRAY
// STATE HERE, mirroring nav-delta-panel.ts's own reasoning. The ratified
// contract is "EXACTLY THREE ROWS, ALWAYS" — a reference date is never
// absent, even when uncomputable (it returns its row with NULL values
// instead). Any payload that is not exactly three rows is a transport/
// contract surprise, not a legitimate state this function can represent,
// and degrades to the SAME `null` a hard RPC error would.
//
// NO REORDERING, NO FILTERING. The fixed row order ('this_month',
// 'prior_month', 'prior_year_end') is part of the contract; this function
// passes the three rows through exactly as returned, coercing only the
// numeric transport representation — never re-sorting, never dropping a
// row, never computing a date client-side.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { NavReferenceDateRow } from '$lib/nav-reference-dates';

/** Raw shape as it arrives from the RPC. Numeric columns may arrive as
 * `number` OR `string` — PostgREST's numeric serialization is not guaranteed
 * to be a JSON number for every value (nav-series.ts's / nav-delta-panel.ts's
 * own coercion idiom). */
type RawNavReferenceDateRow = {
	reference: string;
	reference_date: string;
	reference_checkpoint_date: string | null;
	nav: number | string | null;
	nav_prior_yr_dollars: number | string | null;
	cpi_period: string | null;
	cpi_basis_period: string;
	cpi_any_carried: boolean | null;
	cpi_unavailable: boolean | null;
};

/** NULL passes through; a non-NULL value that fails to coerce to a finite
 * number degrades to NULL rather than poisoning the panel with NaN —
 * duplicated from nav-delta-panel.ts's own toNumberOrNull idiom rather than
 * imported; the server query modules do not share a helper module today. */
function toNumberOrNull(v: number | string | null): number | null {
	if (v === null) return null;
	const n = Number(v);
	return Number.isFinite(n) ? n : null;
}

function normalize(r: RawNavReferenceDateRow): NavReferenceDateRow {
	return {
		reference: r.reference as NavReferenceDateRow['reference'],
		reference_date: r.reference_date,
		reference_checkpoint_date: r.reference_checkpoint_date,
		nav: toNumberOrNull(r.nav),
		nav_prior_yr_dollars: toNumberOrNull(r.nav_prior_yr_dollars),
		cpi_period: r.cpi_period,
		cpi_basis_period: r.cpi_basis_period,
		cpi_any_carried: r.cpi_any_carried,
		cpi_unavailable: r.cpi_unavailable
	};
}

/**
 * Load the caller's §2.1.4 NAV-at-three-reference-dates panel, RLS-scoped
 * via the per-request anon/authenticated client. No arguments: tenant and
 * "today" both derive server-side (session RLS and 070 respectively).
 *
 * Fail-soft on any READ error (network, RPC failure, wrong-shaped payload):
 * degrades to `null` — logged server-side, never thrown. A genuine result is
 * always exactly three rows, in the ratified fixed order, passed through
 * unchanged — see the module header for why there is no legitimate `[]`
 * state here.
 */
export async function loadNavReferenceDates(
	supabase: SupabaseClient
): Promise<NavReferenceDateRow[] | null> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_nav_reference_dates');

	if (error) {
		console.error('[nav-reference-dates] fn_nav_reference_dates failed:', error.message);
		return null;
	}
	if (!Array.isArray(data) || data.length !== 3) {
		// The ratified contract is "EXACTLY THREE ROWS, ALWAYS" — anything
		// else (zero rows, more/fewer than three, a non-array payload) is a
		// transport/contract surprise, not a legitimate state this function
		// can represent. Degrades to the SAME `null` a hard RPC error would,
		// rather than guessing at a partial panel.
		console.error(
			'[nav-reference-dates] fn_nav_reference_dates returned an unexpected shape; degrading to null:',
			Array.isArray(data) ? `array length ${data.length}` : typeof data
		);
		return null;
	}

	return (data as RawNavReferenceDateRow[]).map(normalize);
}
