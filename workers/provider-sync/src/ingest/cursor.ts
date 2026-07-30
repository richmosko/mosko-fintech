// cursor.ts — OWD-A A3 typed incremental-sync cursor persistence (SELF-206 migration 045).
//
// The Plaid /transactions/sync cursor (and, later, a SimpleFIN watermark) is READ from
// pfin.linked_source.sync_cursor before a drain and ADVANCED (written) ONLY on a successful land.
// Service_role path (BYPASSRLS) → the `users_id` filter is the tenant fence (Decision-1 in-code
// binding + defense-in-depth: a mismatch touches 0 rows). api/src never touches the cursor — only
// the worker sync path (poll + webhook-triggered sync) does. The cursor is opaque; NEVER logged.
//
// ADVANCE-ON-SUCCESS-ONLY is load-bearing (Plaid semantics): if we advanced the cursor but the
// land failed, the next sync would skip those transactions. Callers therefore write the new cursor
// ONLY after syncProviderData succeeds; a thrown land leaves the old cursor → the next sync
// re-drains from it (self-healing).

import type { Tx } from '../db/TenantBoundClient.js';

/** The minimal service_role runner both PollClient and TenantBoundClient satisfy (avoids a
 *  circular import on the concrete client types). */
export interface ServiceRoleRunner {
	withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
}

/** Read the stored incremental cursor for a source (service_role; tenant-bound). NULL = never
 *  synced / pre-cursor (the adapter then does a full drain from the beginning). */
export async function readSyncCursor(
	client: ServiceRoleRunner,
	sourceId: string | bigint,
	usersId: string
): Promise<string | null> {
	const rows = await client.withServiceRole(
		(tx) =>
			tx<{ sync_cursor: string | null }[]>`
				select sync_cursor from pfin.linked_source
				where source_id = ${Number(sourceId)} and users_id = ${usersId}`
	);
	return rows[0]?.sync_cursor ?? null;
}

/** Advance (write) the incremental cursor for a source (service_role; tenant-bound). No-op when
 *  the cursor is null/undefined (nothing to persist). updated_at is refreshed by the
 *  linked_source_set_updated_at BEFORE-UPDATE trigger. */
export async function writeSyncCursor(
	client: ServiceRoleRunner,
	sourceId: string | bigint,
	usersId: string,
	cursor: string | null | undefined
): Promise<void> {
	if (cursor === null || cursor === undefined) return;
	await client.withServiceRole(
		(tx) =>
			tx`update pfin.linked_source set sync_cursor = ${cursor}
			   where source_id = ${Number(sourceId)} and users_id = ${usersId}`
	);
}
