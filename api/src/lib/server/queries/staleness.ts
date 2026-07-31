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
// Fail-soft is load-bearing: a staleness-read failure degrades to EMPTY_STALENESS (the badge
// just doesn't render) — it must NEVER throw and take down the NAV surface (D1 governs honesty
// of the number the user sees; it must not gate the number's availability).

import type { SupabaseClient } from '@supabase/supabase-js';
import {
	EMPTY_STALENESS,
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
 * Fail-soft: any error (read failure, unexpected empty result set) degrades to EMPTY_STALENESS
 * ({ is_stale: false, stale_items: [] }) — logged server-side, never surfaced, never thrown.
 */
export async function loadStaleness(supabase: SupabaseClient): Promise<StalenessData> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_aggregation_has_stale_constituent');

	if (error) {
		console.error('[staleness] fn_aggregation_has_stale_constituent failed:', error.message);
		return EMPTY_STALENESS;
	}

	// Set-returning RPC → array; the contract is exactly one aggregate row.
	const row = (Array.isArray(data) ? data[0] : (data as StaleRow | null)) as StaleRow | undefined;
	if (!row) {
		// No row is not an expected state (the fn always returns one) — degrade, don't assert stale.
		console.error('[staleness] fn returned no aggregate row; degrading to empty staleness');
		return EMPTY_STALENESS;
	}

	const items = Array.isArray(row.stale_items) ? row.stale_items.map(toItem) : [];
	return { is_stale: Boolean(row.is_stale), stale_items: items };
}
