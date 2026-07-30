// triggerSync.ts — SELF-206 AC5 on-demand incremental sync (worker side, Option A landing path).
//
// Plaid TRANSACTIONS webhooks are NOTIFICATIONS ("new data available") — fetching the actual
// transactions needs PLAID_SECRET, which lives ONLY in the worker. ORDERING (C-X2 closure): the
// api/src handler dispatches to this route SYNC-FIRST, BEFORE it claims the idempotency gate
// (fn_plaid_webhook_commit) — on a non-2xx here the handler returns 5xx so Plaid retries, and the
// gate is committed ONLY after this confirms 2xx (gate-at-COMPLETION). The worker resolves the
// credential (service_role decrypt view, tenant-keyed), fetches from Plaid, and lands via the
// SHIPPED syncProviderData → fn_ingest_transactions (this file NEVER re-implements landing).
//
// TENANT SAFETY: `ownerUserId` is the resolved tenant api/src looked up FROM the Plaid Item id (it
// is NEVER browser-sourced — the webhook has no session). resolveCredential double-binds
// (source_id AND users_id) against the decrypt view → a mismatched/foreign source reads 0 rows →
// null → we throw (fail-loud, no cross-tenant fetch). provider is 'plaid' by construction (this is
// the Plaid-webhook trigger; SimpleFIN has no webhook — poll-only).
//
// IDEMPOTENCY: TRANSACTIONS events are NEVER id-gated (per-path idempotency, 045 — a content-hash
// id would false-collide on same-second byte-identical bodies). So a Plaid retry of a transactions
// webhook DOES re-reach this route — that is SAFE because the sync is idempotent (the
// /transactions/sync cursor advances only on real new data + syncProviderData dedups: balances DO
// NOTHING, prices upsert, txns dedup on the provider key). Only STATE-event exact-JWT replays
// short-circuit (200) in the api/src handler before any sync. The C-X2 closure rests on
// sync-first/gate-at-completion + Plaid's at-least-once retry — NOT on a scheduled-poll backstop.

import { TenantBoundClient } from '../db/TenantBoundClient.js';
import type { WorkerConfig } from '../config/env.js';
import {
	buildAdapter,
	resolveCredential,
	trailingRange,
	type FetchAdapter,
	type PollClient,
	type SourceRow
} from '../cli/poll.js';
import { syncProviderData, type SyncResult } from '../ingest/mapper.js';
import { readSyncCursor, writeSyncCursor } from '../ingest/cursor.js';
import type { SourceRef } from '../adapters/ProviderAdapter.js';

export interface SyncSourceInput {
	ownerUserId: string;
	linkedSourceId: bigint;
}

export interface SyncSourceResult {
	sourceId: string;
	inserted: number;
	skipped: number;
	unresolvedAccounts: number;
}

/** Injectable seams (mirrors poll.ts PollWiring) so the orchestration unit-tests with NO live
 *  Plaid/DB. serve-admission.ts wires these to the real TenantBoundClient + PlaidAdapter. */
export interface SyncSourceDeps {
	clientFor(usersId: string): PollClient;
	buildAdapter(provider: 'plaid'): FetchAdapter;
	resolveCredential(client: PollClient, row: SourceRow): Promise<string | null>;
	sync(client: TenantBoundClient, sourceId: bigint, provider: string, data: {
		balances: Awaited<ReturnType<FetchAdapter['fetchBalances']>>;
		holdings: Awaited<ReturnType<FetchAdapter['fetchHoldings']>>;
		transactions: Awaited<ReturnType<FetchAdapter['fetchTransactions']>>;
	}): Promise<SyncResult>;
	syncDate: string;
	/** OWD-A A3 (045): read the stored Plaid cursor before the drain (resume incremental). */
	readCursor(client: PollClient, sourceId: bigint, usersId: string): Promise<string | null>;
	/** OWD-A A3 (045): advance the stored cursor AFTER a successful land (advance-on-success-only). */
	writeCursor(client: PollClient, sourceId: bigint, usersId: string, cursor: string): Promise<void>;
}

/**
 * Run one incremental Plaid sync for the resolved tenant + source. Fail-loud on a missing
 * credential (the api/src caller has already verified the Item + tenant, so a null here is a real
 * error — audited on api/src's side, never a silent no-op). The credential is NEVER logged.
 */
export async function syncLinkedSource(
	input: SyncSourceInput,
	deps: SyncSourceDeps
): Promise<SyncSourceResult> {
	const row: SourceRow = {
		sourceId: String(input.linkedSourceId),
		provider: 'plaid',
		usersId: input.ownerUserId,
		externalConnectionId: null,
		providerMetadata: null
	};
	const client = deps.clientFor(input.ownerUserId);
	try {
		const credential = await deps.resolveCredential(client, row);
		if (credential === null) {
			// NEVER log the (absent) credential; the source id + tenant are non-secret.
			throw new Error(`no credential resolved for source_id=${row.sourceId} (plaid webhook sync)`);
		}
		const adapter = deps.buildAdapter('plaid');
		// OWD-A A3 (045): resume the Plaid /transactions/sync drain from the stored cursor.
		const priorCursor = await deps.readCursor(client, input.linkedSourceId, input.ownerUserId);
		const sourceRef: SourceRef = {
			sourceId: input.linkedSourceId,
			accessToken: credential, // consumed by the adapter fetch; never logged.
			syncDate: deps.syncDate,
			cursor: priorCursor
		};
		const range = trailingRange(deps.syncDate);
		const balances = await adapter.fetchBalances(sourceRef);
		const holdings = await adapter.fetchHoldings(sourceRef);
		const transactions = await adapter.fetchTransactions(sourceRef, range);
		const result = await deps.sync(client as unknown as TenantBoundClient, input.linkedSourceId, 'plaid', {
			balances,
			holdings,
			transactions
		});
		// A3 advance-on-success-ONLY: the land succeeded (a throw would skip this) → persist the
		// drained-to cursor so the next webhook/poll sync is incremental. Only when it changed.
		const nextCursor = adapter.getLastCursor?.() ?? null;
		if (nextCursor !== null && nextCursor !== priorCursor) {
			await deps.writeCursor(client, input.linkedSourceId, input.ownerUserId, nextCursor);
		}
		return {
			sourceId: row.sourceId,
			inserted: result.transactionsInserted,
			skipped: result.transactionsSkipped,
			unresolvedAccounts: result.unresolvedAccounts.length
		};
	} finally {
		await client.end();
	}
}

/** Production deps for serve-admission.ts: real TenantBoundClient + adapters + shipped sync. The
 *  factory (not the caller) constructs the raw client → the fence-tbc-node LEG-1 anchor stays the
 *  sole construction site. */
export function productionSyncSourceDeps(config: WorkerConfig, syncDate: string): SyncSourceDeps {
	return {
		clientFor: (usersId: string) => TenantBoundClient.forTenant(config, usersId),
		buildAdapter: (provider: 'plaid') => buildAdapter(provider, config),
		resolveCredential,
		sync: syncProviderData,
		syncDate,
		readCursor: (client, sourceId, usersId) => readSyncCursor(client, sourceId, usersId),
		writeCursor: (client, sourceId, usersId, cursor) => writeSyncCursor(client, sourceId, usersId, cursor)
	};
}
