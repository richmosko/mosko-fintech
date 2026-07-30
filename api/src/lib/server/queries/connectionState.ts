// connectionState.ts — server-side reads for SELF-207 §2.4.4.b connection-state + P4 re-auth
// banner. Backend-owned server source. Reads Architect's `043` linked_source_connection_state
// view (security_invoker=true) through the per-request anon client — owner-scoped at the DB
// (composes over linked_source RLS + the 040 owner-semantics sync-history view), NEVER
// service_role (RT-26 / Lock 11). Both reads fail SOFT (logged) — a health/list read must
// never throw the layout or the page.
//
// The 043 view projects `linked_source_id` (= the caller's own linked_source PK, == the FK
// each account carries as account.linked_source_id). We surface it as `source_id` to match the
// contract locked with Frontend (AccountConnectionState). Same bigint, renamed at this boundary.
//
// The reauth/institution-down SEMANTIC is Backend's (Frontend renders it): we derive the banner
// counts here via the shared browser-safe predicates (single anti-drift source, VERBATIM from
// the 015 CHECK enum) so the server counts and the client chips can never diverge.

import type { SupabaseClient } from '@supabase/supabase-js';
import { needsReauth, isInstitutionDown } from '$lib/schemas/connection-status-constants';

/** One connection's current state (per linked_source), owner-scoped. Shape locked with
 *  Frontend (AccountConnectionState). `source_id` === account.linked_source_id. */
export type ConnectionState = {
	source_id: string;
	provider: string;
	institution_name: string | null;
	is_active: boolean;
	connection_status: string;
	status_class: string | null;
	last_successful_sync_at: string | null;
};

/** Layout banner summary — the two counts the P4 banner needs (present-N vs info vs zero). */
export type ConnectionHealth = { reauthCount: number; institutionDownCount: number };

// View column names (043). `linked_source_id` is renamed to `source_id` in the mapped row.
const VIEW_COLUMNS =
	'linked_source_id, provider, institution_name, is_active, connection_status, status_class, last_successful_sync_at';

type ViewRow = {
	linked_source_id: number | string;
	provider: string;
	institution_name: string | null;
	is_active: boolean;
	connection_status: string;
	status_class: string | null;
	last_successful_sync_at: string | null;
};

/**
 * All of the caller's connections, newest-institution-stable order. Owner-scoped via the anon
 * client (the 043 view is security_invoker → composes under the caller's RLS; a cross-tenant
 * source is invisible). Returns `{ connections, error }` — `error:true` lets the page
 * distinguish a read FAILURE from a true empty (Frontend renders a retriable error vs the
 * "connect an institution" empty state). Fail-soft: never throws.
 */
export async function loadConnectionStates(
	supabase: SupabaseClient
): Promise<{ connections: ConnectionState[]; error: boolean }> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('linked_source_connection_state')
		.select(VIEW_COLUMNS)
		.order('institution_name', { ascending: true, nullsFirst: false });

	if (error) {
		console.error('[connectionState] loadConnectionStates failed:', error.message);
		return { connections: [], error: true };
	}

	const connections = ((data ?? []) as ViewRow[]).map((r) => ({
		source_id: String(r.linked_source_id), // bigint → numeric string (SELF-199 convention)
		provider: r.provider,
		institution_name: r.institution_name,
		is_active: r.is_active,
		connection_status: r.connection_status,
		status_class: r.status_class,
		last_successful_sync_at: r.last_successful_sync_at
	}));
	return { connections, error: false };
}

/**
 * Banner counts over the connection list. Counts only ACTIVE connections: an inactive/retired
 * source is sync-paused and must not nag re-auth (matches the chip's inactive-first precedence).
 * `institution_down` is info-only (not a re-auth trigger, per REAUTH_STATUSES / AC #2).
 */
export function summarizeHealth(connections: ConnectionState[]): ConnectionHealth {
	let reauthCount = 0;
	let institutionDownCount = 0;
	for (const c of connections) {
		if (!c.is_active) continue;
		if (needsReauth(c.connection_status)) reauthCount++;
		else if (isInstitutionDown(c.connection_status)) institutionDownCount++;
	}
	return { reauthCount, institutionDownCount };
}

/**
 * Layout convenience: read + summarize for the always-on P4 banner. Fail-soft-to-zero on a read
 * error (mirrors the pendingClassificationCount pattern — a layout load that threw breaks every
 * page). The banner is a summary, not the source of truth; the /accounts/connections page
 * surfaces the retriable read error itself.
 */
export async function loadConnectionHealth(supabase: SupabaseClient): Promise<ConnectionHealth> {
	const { connections, error } = await loadConnectionStates(supabase);
	return error ? { reauthCount: 0, institutionDownCount: 0 } : summarizeHealth(connections);
}

/**
 * Resolve the provider for ONE of the caller's connections — the AUTHORITATIVE provider for the
 * SELF-207 reauth dispatch (never trust a client-supplied provider). Owner-scoped via the anon
 * client (linked_source_select RLS → users_id = auth.uid()); a cross-tenant / nonexistent
 * source_id returns null (the reauth route then 404s before touching the worker). `provider` is
 * in the 015 authenticated column grant. Returns null on error too (caller treats as not-found).
 */
export async function resolveConnectionProvider(
	supabase: SupabaseClient,
	sourceId: string
): Promise<string | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('linked_source')
		.select('provider')
		.eq('source_id', sourceId)
		.maybeSingle();

	if (error) {
		console.error('[connectionState] resolveConnectionProvider failed:', error.message);
		return null;
	}
	return (data?.provider as string | undefined) ?? null;
}
