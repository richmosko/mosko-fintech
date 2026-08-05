// accounts/connections/+page.server.ts — SELF-207 §2.4.4.b connection-state list +
// connections-redesign per-connection account nesting.
// Backend-owned server source (ARCH §4.1 allowlist).
//
// load(): auth-gate, then read the caller's connection states from Architect's `043`
// linked_source_connection_state view (owner-scoped, anon-key + RLS, NO service_role) and,
// alongside each connection, the accounts under it (account.linked_source_id === source_id).
// Manual / non-linked accounts are NOT connections and are excluded (they live on the Hub).
// Returns { connections, error } where each connection carries `accounts: ConnectionAccount[]`
// (OPEN AND CLOSED — a management view, not NAV, so the open-as-of filter of the ADR-042 closure
// contract does not apply; each account carries `closed_at`, a DATE, not a flag — 059 dropped
// is_active). `error` is the OR of the two fail-soft reads: Frontend distinguishes a read
// failure (error:true) from a true-empty (no connections yet). Both reads fail soft (never throw).

import { redirect } from '@sveltejs/kit';
import {
	loadConnectionStates,
	loadAccountsBySource,
	type ConnectionState,
	type ConnectionAccount
} from '$lib/server/queries/connectionState';
import type { PageServerLoad } from './$types';

/** A connection plus the accounts nested under it (connections-redesign list shape). */
export type ConnectionWithAccounts = ConnectionState & { accounts: ConnectionAccount[] };

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const { connections: states, error: statesErr } = await loadConnectionStates(locals.supabase);
	const { accountsBySource, error: acctErr } = await loadAccountsBySource(locals.supabase);

	const connections: ConnectionWithAccounts[] = states.map((c) => ({
		...c,
		accounts: accountsBySource.get(c.source_id) ?? []
	}));

	return { connections, error: statesErr || acctErr };
};
