// stale-constituent.ts — browser-safe types + per-status affordance mapping for the
// D1 non-silent staleness marker (SELF-208 · §2.4.4.c · ADR-013 Decision 1).
//
// NON-server module: mirrors the shape returned by the Architect's `046`
// pfin.fn_aggregation_has_stale_constituent() read primitive, which Backend threads
// through the loader `data`. This is the single browser-side definition of the staleness
// payload shape + the affordance decision, so the badge component stays presentational.
//
// AFFORDANCE is keyed on `connection_status` using the CANONICAL predicates in
// connection-status-constants.ts (the single anti-drift value-set copied verbatim from the
// `015` DB CHECK) — NOT re-derived here. `status_class` is CONTEXT, not the affordance driver
// (per the `046` header PER-STATUS AFFORDANCE contract); `provider` is available for display /
// future per-adapter reauth dispatch.

import { needsReauth, isInstitutionDown } from '$lib/schemas/connection-status-constants';

/**
 * One stale constituent, mirroring a `046` stale_items[] element:
 *   { linked_source_id, institution_name, provider, connection_status, status_class }.
 * `status_class` may be NULL (no state_history transition yet) — hence nullable.
 */
export interface StaleConstituentItem {
	linked_source_id: number | string;
	institution_name: string;
	provider: string;
	connection_status: string;
	status_class: string | null;
}

/**
 * The aggregate payload = one `046` row: is_stale flag + the (possibly empty) list.
 * `stale_items` is never NULL server-side ('[]' coalesce) — default to [] defensively here.
 *
 * `is_stale` is TRI-STATE (`boolean | null`), NOT a plain boolean — SELF-229 REWORK (F/CTO-ruled,
 * mirrors the SELF-220 Sec round 2 catch). The ORIGINAL shape degraded a `046` RPC failure to
 * `is_stale: false` — silently indistinguishable from "confirmed healthy." `null` = UNKNOWN (the
 * read failed); see UNKNOWN_STALENESS below. NO consumer may treat `null` the same as `false`.
 */
export interface StalenessData {
	is_stale: boolean | null;
	stale_items: StaleConstituentItem[];
}

/** CONFIRMED-healthy zero-value: the `046` read SUCCEEDED and found nothing stale. */
export const EMPTY_STALENESS: StalenessData = { is_stale: false, stale_items: [] };

/**
 * SELF-229 REWORK: the `046` read FAILED — genuinely UNKNOWN, not "confirmed healthy." This is
 * `staleness.ts`'s degrade target on an RPC error / malformed response, replacing what used to be
 * EMPTY_STALENESS there. Render an explicit "staleness unknown" affordance for this value — never
 * the same treatment as EMPTY_STALENESS (silence) or a stale badge (a specific known list).
 */
export const UNKNOWN_STALENESS: StalenessData = { is_stale: null, stale_items: [] };

/**
 * Per-item affordance kind, keyed on connection_status:
 *   - 'reauth'           → login_required | revoked | disconnected (owner can fix by re-auth);
 *   - 'institution-down' → transient provider outage (re-auth CANNOT fix — informational only);
 *   - 'info'             → any other non-healthy value (forward-compat: mark, don't offer reauth).
 * Fail-safe: only the REAUTH set gets the re-auth link; everything else is informational, so a
 * future unknown status is marked-but-not-mis-actioned (D1 never-silently-fresh).
 */
export type StaleAffordance = 'reauth' | 'institution-down' | 'info';

export function staleAffordance(status: string): StaleAffordance {
	if (needsReauth(status)) return 'reauth';
	if (isInstitutionDown(status)) return 'institution-down';
	return 'info';
}

/** True when at least one stale constituent is re-auth-actionable (drives the CTA presence). */
export function hasReauthActionable(items: StaleConstituentItem[]): boolean {
	return items.some((i) => staleAffordance(i.connection_status) === 'reauth');
}
