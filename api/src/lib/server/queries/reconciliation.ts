// reconciliation.ts — server-side reads for SELF-204 manual↔provider dedup DETECTION +
// per-account/linked-source sync history (migration 040 / ADR-034). Backend-owned server source.
//
// Both surfaces are READ-ONLY and RLS/owner-scoped at the DB — this module composes them
// through the per-request anon client (NEVER service_role; RT-26 / Lock 11):
//   - manual_provider_dup_candidate  : security_invoker=true view → runs under the caller's
//     account_trans RLS (rd_access-JOIN, 006). DETECTION-ONLY: it surfaces candidate pairs;
//     it writes/links/skips nothing (SELF-205 interprets — clean boundary per ADR-034 D2).
//   - linked_source_sync_history     : owner-semantics security_barrier view — self-scopes
//     WHERE users_id = auth.uid() and exposes ONLY the Sec-verified scalar allowlist (provider,
//     source, created_at, transactions_inserted, transactions_skipped). The base table
//     (linked_source_sync_audit, 015) is service_role-only; this view is the SOLE authenticated
//     read path (the raw `detail` blob is never reachable).
// Both fail soft (logged, [] on error) — a detection/history read never throws the page.

import type { SupabaseClient } from '@supabase/supabase-js';

/** One manual↔provider candidate-duplicate pair for the account (DETECTION-ONLY). The user
 *  reconciles explicitly (SELF-205); this row only says "this manual entry looks like a synced
 *  provider row" (shared account_id + import_hash, both live). */
export type DupCandidate = {
	account_id: number;
	manual_trans_id: number;
	manual_date: string;
	manual_amount: number;
	manual_vendor: string | null;
	manual_description: string | null;
	provider_trans_id: number;
	provider: string;
	provider_txn_id: string;
	provider_date: string;
	provider_amount: number;
	import_hash: string;
};

/** One per-sync history row (owner-scoped). Curated scalar projection over the service_role-only
 *  audit — provider/source/timestamp + the two named count keys (ADR-034 D3 allowlist). */
export type SyncHistoryRow = {
	provider: string;
	source: string;
	created_at: string;
	transactions_inserted: number | null;
	transactions_skipped: number | null;
};

const DUP_CANDIDATE_COLUMNS =
	'account_id, manual_trans_id, manual_date, manual_amount, manual_vendor, manual_description, provider_trans_id, provider, provider_txn_id, provider_date, provider_amount, import_hash';

/**
 * Candidate duplicates for ONE account — the manual↔provider pairs the detection view surfaces
 * for this account. RLS-scoped via the per-request anon client (the view is security_invoker, so
 * it composes under the caller's account_trans RLS; a cross-tenant account_id sees nothing).
 * Fail-soft ([] on error). Ordered newest-manual-first for a stable render.
 */
export async function loadDupCandidates(
	supabase: SupabaseClient,
	accountId: number
): Promise<DupCandidate[]> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('manual_provider_dup_candidate')
		.select(DUP_CANDIDATE_COLUMNS)
		.eq('account_id', accountId)
		.order('manual_date', { ascending: false })
		.order('manual_trans_id', { ascending: false });

	if (error) {
		console.error('[reconciliation] loadDupCandidates failed:', error.message);
		return [];
	}
	return (data ?? []) as DupCandidate[];
}

/**
 * The sync history for ONE account's linked connection — provider/source + timestamp + the two
 * named count keys, newest first. Per-account per F/CTO ratify: the view (Sec-GREEN) projects a
 * `linked_source_id` discriminator (the caller's own connection FK), and we filter to the account's
 * connection. A manual / non-linked account (linked_source_id NULL) has no connection → returns []
 * WITHOUT a query. The view still self-scopes to auth.uid() (owner-semantics) and never exposes the
 * raw `detail` blob (base table ungranted to authenticated). Fail-soft ([] on error).
 */
export async function loadSyncHistory(
	supabase: SupabaseClient,
	linkedSourceId: number | null
): Promise<SyncHistoryRow[]> {
	if (linkedSourceId == null) return []; // manual / non-linked account → no sync history

	const { data, error } = await supabase
		.schema('pfin')
		.from('linked_source_sync_history')
		.select('provider, source, created_at, transactions_inserted, transactions_skipped')
		.eq('linked_source_id', linkedSourceId)
		.order('created_at', { ascending: false });

	if (error) {
		console.error('[reconciliation] loadSyncHistory failed:', error.message);
		return [];
	}
	return (data ?? []) as SyncHistoryRow[];
}
