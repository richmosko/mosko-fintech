// staleness.ts — server-side read for the SELF-208 §2.4.4.c D1 non-silent staleness marker
// (ADR-013 Decision 1). Backend-owned server source (ARCH §4.1 allowlist).
//
// Calls Architect's `046` pfin.fn_aggregation_has_stale_constituent() — a SECURITY INVOKER
// read primitive (prosecdef=f) — through the per-request anon/authenticated client so the
// caller's RLS context propagates (users_id = auth.uid()), NEVER service_role (RT-26 / Lock 11).
// The fn composes over the `043` linked_source_connection_state INVOKER view, so owner-isolation
// + the 025 aal2 gate are INHERITED at the DB: a cross-tenant source is structurally invisible.
//
// fn_aggregation_has_stale_constituent() RETURNS TABLE(is_stale boolean, stale_items jsonb) —
// exactly ONE aggregate row (supabase-js returns a set-returning RPC as an array; we take [0]).
// `stale_items` arrives already parsed (jsonb → JS array). We normalize each element to the
// StaleConstituentItem contract Frontend locked (linked_source_id coerced to string per the
// SELF-199 bigint convention, mirroring connectionState.ts).
//
// Fail-soft is load-bearing: a staleness-read failure must NEVER throw and take down the NAV
// surface (D1 governs honesty of the number the user sees; it must not gate the number's
// availability) — but "fail-soft" does NOT mean "degrade to confirmed-healthy." See the REWORK
// note below.
//
// ADR-013 D1 (SELF-229 AC5 annotation, verbatim): "surface list at PRD §2.4.4 is
// illustrative-not-exhaustive; further surfaces ramp at V1.2-V1.5 milestones (§2.2, §2.3, §2.5,
// §2.6)." This is the FRAMEWORK's own consumption site — loadStaleness() is called exactly ONCE
// per request (from `+page.server.ts`) and its result is the SAME value every V1.1 NW surface on
// that route reads (§2.1.1 headline / §2.1.2 chart / §2.1.3 delta panel / §2.1.4 reference-dates
// panel), plus §2.1.5 composition's additional per-row join in navComposition.ts. No surface here
// re-invokes this function — see +page.server.ts's own D1 annotation for why.
//
// ⚠ SELF-229 REWORK (F/CTO-ruled, mirrors the SELF-220 Sec round 2 catch): a `046` RPC failure or
// malformed response now degrades to UNKNOWN_STALENESS (`is_stale: null`), NOT EMPTY_STALENESS
// (`is_stale: false`). The ORIGINAL shape of this function returned EMPTY_STALENESS on error —
// exactly the silent-fresh-on-failure hazard Sec rejected on the chart: the caller could not tell
// "checked, nothing stale" from "couldn't check at all." Every consumer downstream (the §2.1.1
// headline badge, and — once threaded — §2.1.2/.3/.4, plus §2.1.5 composition's per-row join,
// which now ALSO propagates this root-unknown state rather than treating an unknown root as an
// empty stale-set — see navComposition.ts) inherits this fix from this one function.

import type { SupabaseClient } from '@supabase/supabase-js';
import {
	UNKNOWN_STALENESS,
	type StalenessData,
	type StaleConstituentItem
} from '$lib/staleness/stale-constituent';

/** Raw shape of one `046` stale_items[] element as it arrives from the jsonb projection. */
type RawStaleItem = {
	linked_source_id: number | string;
	institution_name: string;
	provider: string;
	connection_status: string;
	status_class: string | null;
};

/** One `046` aggregate row as supabase-js hands it back (jsonb already parsed to a JS array). */
type StaleRow = {
	is_stale: boolean;
	stale_items: RawStaleItem[] | null;
};

/** Normalize a raw jsonb element to the Frontend-locked StaleConstituentItem contract. */
function toItem(r: RawStaleItem): StaleConstituentItem {
	return {
		linked_source_id: String(r.linked_source_id), // bigint → numeric string (SELF-199 convention)
		institution_name: r.institution_name,
		provider: r.provider,
		connection_status: r.connection_status,
		status_class: r.status_class ?? null
	};
}

/**
 * Load the caller's aggregation-staleness state, RLS-scoped via the per-request anon client.
 * Fail-soft: any error (read failure, unexpected empty result set) degrades to UNKNOWN_STALENESS
 * ({ is_stale: null, stale_items: [] }) — logged server-side, never surfaced, never thrown, and
 * NEVER EMPTY_STALENESS (SELF-229 REWORK — see module header). EMPTY_STALENESS is reserved for
 * the genuine case: a SUCCESSFUL read that found nothing stale.
 */
export async function loadStaleness(supabase: SupabaseClient): Promise<StalenessData> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_aggregation_has_stale_constituent');

	if (error) {
		console.error('[staleness] fn_aggregation_has_stale_constituent failed:', error.message);
		return UNKNOWN_STALENESS;
	}

	// Set-returning RPC → array; the contract is exactly one aggregate row.
	const row = (Array.isArray(data) ? data[0] : (data as StaleRow | null)) as StaleRow | undefined;
	if (!row) {
		// No row is not an expected state (the fn always returns one) — degrade to UNKNOWN, not
		// "confirmed nothing stale." A malformed response tells us nothing about the tenant's
		// actual staleness state.
		console.error('[staleness] fn returned no aggregate row; degrading to unknown staleness');
		return UNKNOWN_STALENESS;
	}

	const items = Array.isArray(row.stale_items) ? row.stale_items.map(toItem) : [];
	return { is_stale: Boolean(row.is_stale), stale_items: items };
}
