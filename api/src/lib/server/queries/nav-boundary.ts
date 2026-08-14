// nav-boundary.ts — server-side read for the §2.1.2 cron/imported boundary
// signal (SELF-220). Backend-owned server surface (ARCH §4.1 allowlist).
//
// Calls Architect's `069` pfin.fn_first_cron_checkpoint — a SECURITY INVOKER
// read-composition helper (Lock 11; prosecdef=f) that reads pfin.nav_daily
// ONLY — through the per-request anon/authenticated client, exactly the same
// client netWorth.ts / navComposition.ts / staleness.ts / nav-series.ts
// already use, so the caller's RLS context propagates (users_id =
// auth.uid()), NEVER service_role (RT-26 / Lock 11). Owner-isolation is
// INHERITED at the DB via RLS on pfin.nav_daily — a cross-tenant caller gets
// the empty-store answer (NULL/false/false), fails closed (069's own TENANT
// FENCE section).
//
// Row type is IMPORTED from $lib/nav-boundary.ts (Frontend-owned,
// browser-safe), not redeclared — same anti-drift pattern as nav-series.ts's
// import of NavSeriesPoint.
//
// 069 RETURNS TABLE(...) but is documented as "EXACTLY ONE ROW, ALWAYS — by
// construction, since an aggregate over an empty set still returns a row."
// supabase-js still hands back an array (any set-returning RPC does); this
// function takes element [0] — mirroring staleness.ts's own "exactly one
// aggregate row" idiom — NOT the array-of-many nav-series.ts returns for its
// genuinely multi-row series.
//
// ⚠ FAIL-SOFT TO `null`, DISTINCT FROM THE REAL EMPTY-STORE ROW. 069's
// header spells out FOUR states, and state (a) — "no rows at all" — is a
// REAL, VALID row: (NULL, false, false). That row is 069's own answer to
// "there is no data yet", and it is exactly the state a failed READ must
// not be confused with — the same collapse class 069's own row-not-scalar
// design prevents at the DB layer, one level up (a bare NULL there would
// have collapsed "no cron yet" into "no data ever"; here, a bare `[]`/thrown
// result collapsing into the SAME shape as the real empty-store row would
// do the identical thing at the transport layer). This function's contract:
// `null` = the READ failed (RPC error, missing/malformed row, thrown
// exception) — logged, never thrown; the real (NULL, false, false) object =
// the read SUCCEEDED and the tenant genuinely has no rows yet. A consumer
// must render these differently — this function's entire job is to keep
// them representable as different values.
//
// NO CACHING, NO CLIENT-SIDE DERIVATION. This function is called FRESH on
// every load(), alongside the series — the boundary is a live property of
// the tenant's store (it moves the moment the first cron checkpoint lands),
// and nothing here or in Frontend's nav-boundary.ts memoizes it or
// re-derives it from anything but this call's own return value.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { NavBoundary } from '$lib/nav-boundary';

/** Raw shape as it arrives from the RPC — booleans and a nullable date
 * string, no numeric coercion needed (contrast nav-series.ts's numeric
 * number-or-string idiom; 069 returns no numeric columns at all). */
type RawNavBoundaryRow = {
	first_cron_checkpoint: string | null;
	has_cron_rows: boolean;
	has_imported_rows: boolean;
};

/**
 * Load the caller's §2.1.2 cron/imported boundary signal, RLS-scoped via the
 * per-request anon/authenticated client. Fetched fresh on every call — no
 * caching, no derivation from a prior result.
 *
 * Fail-soft on any READ error (network, RPC failure, missing/malformed row):
 * degrades to `null` — logged server-side, never thrown. `null` means "the
 * read failed"; a genuinely returned `{ first_cron_checkpoint: null,
 * has_cron_rows: false, has_imported_rows: false }` means "the read
 * succeeded and this tenant genuinely has no rows yet" — see the module
 * header for why these must never collapse into one value.
 */
export async function loadNavBoundary(supabase: SupabaseClient): Promise<NavBoundary | null> {
	const { data, error } = await supabase.schema('pfin').rpc('fn_first_cron_checkpoint');

	if (error) {
		console.error('[nav-boundary] fn_first_cron_checkpoint failed:', error.message);
		return null;
	}
	if (!Array.isArray(data) || data.length !== 1) {
		// 069's own contract is "EXACTLY ONE ROW, ALWAYS" — anything else (zero
		// rows, more than one, a non-array payload) is a transport/contract
		// surprise, not a legitimate state this function can represent. It
		// degrades to the SAME `null` a hard RPC error would, rather than
		// guessing at a row.
		console.error(
			'[nav-boundary] fn_first_cron_checkpoint returned an unexpected shape; degrading to null:',
			Array.isArray(data) ? `array length ${data.length}` : typeof data
		);
		return null;
	}

	const row = data[0] as RawNavBoundaryRow;
	return {
		first_cron_checkpoint: row.first_cron_checkpoint,
		has_cron_rows: row.has_cron_rows,
		has_imported_rows: row.has_imported_rows
	};
}
