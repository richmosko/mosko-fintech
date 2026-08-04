// accounts/connections/[source_id]/+page.server.ts — connections-redesign per-connection
// view. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): auth-gate, then read the ONE connection (043 view) + ALL its accounts by
//    linked_source_id. Non-owner / nonexistent source → 404 (RLS-scoped, no existence leak).
//    Returns { connection, accounts }.
//  - NO actions. The per-account use/ignore control (`toggleAccount`) was REMOVED per ADR-042
//    Decision 1b: a control whose two positions are "In use" and "Ignored" persists exactly the
//    selection state concept 3 says must not exist. It is deliberately NOT re-pointed onto
//    `closed_at` — *ignored* and *closed* are different facts, and merging them would re-commit
//    the conflation ADR-042 exists to undo. Import selection lives at connect time and nowhere
//    else; closing is done from the account's own control (`accounts/[account_id]`).
//
// READ-ONLY page. No RLS policy, no service_role, no SECURITY DEFINER — anon client + existing
// policies. acct_number is never selected (masked-only render posture, SD-15).

import { error, redirect } from '@sveltejs/kit';
import {
	loadConnectionState,
	loadAccountsForSource
} from '$lib/server/queries/connectionState';
import type { PageServerLoad } from './$types';

/** source_id is the bigint linked_source PK serialized as a decimal string (SELF-199). A
 *  non-digit param can never match a real source → 404 before any DB round-trip. */
function isValidSourceId(param: string): boolean {
	return /^\d+$/.test(param);
}

export const load: PageServerLoad = async ({ locals, params, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	if (!isValidSourceId(params.source_id)) throw error(404, 'Connection not found');

	// RLS-scoped single-connection read; not-owner (or nonexistent) → null → 404 (no leak).
	const connection = await loadConnectionState(locals.supabase, params.source_id);
	if (!connection) throw error(404, 'Connection not found');

	// All accounts under this connection. Fail-soft ([] on read error).
	const accounts = await loadAccountsForSource(locals.supabase, params.source_id);

	return { connection, accounts };
};
