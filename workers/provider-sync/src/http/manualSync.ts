// manualSync.ts — SELF-317 "Sync now" manual on-demand sync (worker side; ADR-037 amendment).
//
// A user-initiated, provider-agnostic manual sync trigger. A NEW dedicated route on the existing
// RT-27 admission surface (POST /admission/manual-sync) drives this orchestrator. It REUSES the
// single provider-agnostic ingest path (poll.ts createPollHandlers().processSource) — it does NOT
// fork ingest logic and does NOT reuse the Plaid-only 045 webhook syncLinkedSource.
//
// TENANT SAFETY (the #1 deliverable — the §1c defense-in-depth chain):
//  • Sec C1 — enumeration runs under withTenant() (RLS-ENFORCED), NEVER withServiceRole() + a
//    hand-written WHERE. `linked_source` is RLS-readable under authenticated (linked_source_select),
//    so withTenant() makes "layer 4 independently sufficient" rest on a structural RLS lock, not one
//    correctly-typed WHERE predicate. A defensive `usersId === ownerUserId` assert is a cheap second
//    lock (would only ever fire if RLS were bypassed).
//  • Sec C2 — per-source = FILTER-THEN-PROCESS: the requested source_id is intersected with the
//    tenant-scoped enumerated set; a non-member is a no-op/skip. A client-supplied source_id is
//    NEVER passed straight into resolveCredential/processSource.
//  • credential double-bind (inside processSource → resolveCredential) is the DB-side backstop.
//
// A2 async (Sec C3): the orchestrator validates + debounce-checks + stamps in-flight SYNCHRONOUSLY,
// then runs the actual sync(s) FIRE-AND-FORGET in the always-on admission process. Each background
// run is wrapped so an unhandled rejection CANNOT crash the process, and clears its in-flight flag in
// a `finally` so a thrown sync can't wedge a source. The route returns 202 fast with per-source
// dispositions; the true outcome lands in linked_source_sync_audit + connection_status (polled by the
// 040/043 views).
//
// C6a audit provenance: processSource does NOT write the audit row (the cron's runPollLoop→writeAudit
// does, hardcoded source='scheduled_poll'). So THIS orchestrator writes its OWN audit row per
// triggered source with source='manual' (the 047 CHECK admits it), on BOTH the success and failure
// paths — the distinct user-initiated provenance marker.
//
// C4 redaction: the route logs route+status only; this module logs machine coordinates
// (source_id/provider/scrubbed message) only — never a body/credential/token.

import { TenantBoundClient, type Tx } from '../db/TenantBoundClient.js';
import type { WorkerConfig } from '../config/env.js';
import {
	POLL_PROVIDERS,
	buildAdapter,
	createPollHandlers,
	resolveCredential,
	type AuditDetail,
	type PollWiring,
	type SourceRow,
	type SourceSyncOutcome
} from '../cli/poll.js';
import { syncProviderData } from '../ingest/mapper.js';
import { readSyncCursor, writeSyncCursor } from '../ingest/cursor.js';

const errMessage = (err: unknown): string => (err instanceof Error ? err.message : String(err));

// ── Wire types (imported by admissionServer.ts, mirroring the triggerSync SyncSourceInput/Result
//    convention) ────────────────────────────────────────────────────────────────────────────────
export type ManualDisposition = 'triggered' | 'debounced';

export interface ManualSyncInput {
	ownerUserId: string;
	/** Absent ⇒ "sync all my active sources". Present ⇒ per-source (already digit-validated). */
	sourceId?: string;
}

export interface ManualSyncSourceResult {
	source_id: string;
	disposition: ManualDisposition;
}

export interface ManualSyncResult {
	sources: ManualSyncSourceResult[];
}

// ── R1 rate-limit — in-memory 60s/source debounce + in-flight flag ───────────────────────────────
// Backed by a Map/Set in the always-on serve-admission process (persists for its lifetime). The
// debounce is an abuse/UX-smoothing + provider-ToS-courtesy control — NOT a security boundary. It
// also holds the in-flight flag (a source already syncing is throttled), keyed by the bigint
// source_id string. Not durable across a worker restart (acceptable per design §5; R1→R3 is a purely
// additive upgrade if durability is ever needed).
export const DEBOUNCE_WINDOW_MS = 60_000;

export interface SyncDebounceOptions {
	windowMs?: number;
	/** Injectable clock (tests). Defaults to Date.now (normal worker code — allowed here). */
	now?: () => number;
}

export class SyncDebounce {
	readonly #lastTriggered = new Map<string, number>();
	readonly #inFlight = new Set<string>();
	readonly #windowMs: number;
	readonly #now: () => number;

	constructor(opts: SyncDebounceOptions = {}) {
		this.#windowMs = opts.windowMs ?? DEBOUNCE_WINDOW_MS;
		this.#now = opts.now ?? ((): number => Date.now());
	}

	/** Throttled if the source is currently in-flight OR within the debounce window since its last
	 *  trigger. Checked synchronously before spawning a background sync (§6 concurrency). */
	isThrottled(sourceId: string): boolean {
		if (this.#inFlight.has(sourceId)) return true;
		const last = this.#lastTriggered.get(sourceId);
		if (last === undefined) return false;
		return this.#now() - last < this.#windowMs;
	}

	/** Record a trigger: stamp last-triggered + set in-flight. Call synchronously BEFORE spawn so a
	 *  concurrent second request within the window (or while in-flight) sees `debounced`. */
	markTriggered(sourceId: string): void {
		this.#lastTriggered.set(sourceId, this.#now());
		this.#inFlight.add(sourceId);
	}

	/** Clear the in-flight flag (in a `finally` after a background run — so a thrown sync can't wedge
	 *  the source). The 60s last-triggered window persists (a completed run still debounces re-clicks). */
	clearInFlight(sourceId: string): void {
		this.#inFlight.delete(sourceId);
	}
}

export function createSyncDebounce(opts?: SyncDebounceOptions): SyncDebounce {
	return new SyncDebounce(opts);
}

// ── Enumeration (Sec C1 — RLS-scoped, NOT service_role) ──────────────────────────────────────────

/** The subset of TenantBoundClient the tenant-scoped enumeration consumes (structural — a fake
 *  satisfies it in tests; TenantBoundClient satisfies it in production). */
export interface TenantScopedClient {
	withTenant<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
	end(): Promise<void>;
}

/**
 * SELECT the CALLER's poll-eligible linked_source rows — is_active + not-revoked + a poll-capable
 * provider — under withTenant() (RLS-ENFORCED). The `users_id = auth.uid()` scope is enforced by
 * the linked_source_select RLS policy, NOT a hand-written WHERE (Sec C1 — load-bearing). The
 * defensive `usersId === ownerUserId` filter is a cheap structural second lock: under RLS every row
 * already belongs to the caller, so it never drops a row in practice — it would only ever fire if RLS
 * were somehow bypassed (fail-closed).
 */
export async function enumerateSourcesForTenant(
	client: TenantScopedClient,
	ownerUserId: string
): Promise<SourceRow[]> {
	const rows = await client.withTenant(
		(tx) =>
			tx<
				{
					source_id: string;
					provider: string;
					users_id: string;
					external_connection_id: string | null;
					provider_metadata: unknown;
				}[]
			>`
			select source_id, provider, users_id, external_connection_id, provider_metadata
			from pfin.linked_source
			where is_active = true
			  and connection_status <> 'revoked'
			  and provider in ${tx(POLL_PROVIDERS as unknown as string[])}
			order by source_id`
	);
	return rows
		.map((r) => ({
			sourceId: String(r.source_id),
			provider: r.provider as SourceRow['provider'],
			usersId: r.users_id,
			externalConnectionId: r.external_connection_id,
			providerMetadata: r.provider_metadata
		}))
		.filter((row) => row.usersId === ownerUserId); // Sec C1 defense-in-depth (RLS is primary).
}

// ── Orchestrator ─────────────────────────────────────────────────────────────────────────────────

/** All the seams manualSync() needs — defaulted for production in productionManualSyncDeps(). All
 *  injectable so the orchestration unit-tests with NO live Plaid/DB. */
export interface ManualSyncDeps {
	/** Sec C1: RLS-scoped enumeration of the caller's poll-eligible sources. */
	enumerate(ownerUserId: string): Promise<SourceRow[]>;
	/** Reuse poll.ts createPollHandlers().processSource — the single provider-agnostic ingest path
	 *  (credential resolve + fetch + land). THROWS on any per-source failure. */
	processSource(row: SourceRow): Promise<SourceSyncOutcome>;
	/** C6a: write ONE audit row with source='manual', scoped to row.usersId, on success AND failure. */
	writeAudit(row: SourceRow, detail: AuditDetail): Promise<void>;
	/** SELF-207: on a definitive auth-rejection, flip connection_status to unhealthy (reuse the poll
	 *  handler). Non-fatal + idempotent + transient-safe. */
	markUnhealthy(row: SourceRow, err: unknown): Promise<void>;
	/** R1 debounce + in-flight store (persists across calls for the process lifetime). */
	debounce: SyncDebounce;
	/** The syncedAt stamp for the audit detail (one per orchestrator run). */
	syncedAt: string;
	log(message: string): void;
}

/**
 * One background sync for a triggered source: process → audit (both paths) → clear in-flight. NEVER
 * rethrows (A2/C3 — a background rejection must not crash the always-on process); ALWAYS clears the
 * in-flight flag in a `finally` (so a thrown sync can't wedge the source). C6a: exactly one
 * source='manual' audit row per triggered source, on the success AND failure paths.
 */
async function runOneManualSync(deps: ManualSyncDeps, row: SourceRow): Promise<void> {
	try {
		let detail: AuditDetail;
		try {
			const outcome = await deps.processSource(row);
			detail = {
				ok: true,
				syncedAt: deps.syncedAt,
				result: outcome.result,
				errlist: outcome.errlist,
				corrections: outcome.corrections
			};
			const gappy = outcome.errlist.length > 0 ? ` errlist=${outcome.errlist.length}` : '';
			deps.log(`manual-synced source_id=${row.sourceId} provider=${row.provider}${gappy}`);
		} catch (err) {
			// Adapter errors are already scrubbed at source; DB errors never carry the credential
			// (it is only ever an HTTP-fetch value + a bound $N param). Keep .message only (C4).
			const message = errMessage(err);
			detail = { ok: false, syncedAt: deps.syncedAt, error: message };
			deps.log(`manual-sync FAILED source_id=${row.sourceId} provider=${row.provider}: ${message}`);
			try {
				await deps.markUnhealthy(row, err);
			} catch (markErr) {
				deps.log(`unhealthy-mark FAILED source_id=${row.sourceId}: ${errMessage(markErr)}`);
			}
		}
		// C6a: the manual audit row (source='manual') — one per triggered source, on BOTH paths.
		try {
			await deps.writeAudit(row, detail);
		} catch (auditErr) {
			deps.log(`manual sync_audit write FAILED source_id=${row.sourceId}: ${errMessage(auditErr)}`);
		}
	} finally {
		// A2/§5: always clear in-flight — a thrown sync (or audit write) must not wedge the source.
		deps.debounce.clearInFlight(row.sourceId);
	}
}

/**
 * The "Sync now" orchestrator. Phase 1 (SYNCHRONOUS, before the route's 202): enumerate (RLS-scoped,
 * C1) → filter-then-process the requested source_id (C2) → debounce + in-flight gate (R1) → compute
 * per-source dispositions. Phase 2 (BACKGROUND, A2/C3): fire-and-forget the surviving syncs; the
 * route has already returned 202 by the time these run.
 */
export async function manualSync(deps: ManualSyncDeps, input: ManualSyncInput): Promise<ManualSyncResult> {
	// (1) Sec C1 — RLS-scoped enumeration is the ONLY source of truth for which sources exist.
	const enumerated = await deps.enumerate(input.ownerUserId);

	// (2) Sec C2 — filter-then-process: intersect the requested source_id with the enumerated set.
	// A requested id NOT in the caller's set → candidates=[] → no-op (NEVER passed downstream).
	const candidates =
		input.sourceId === undefined ? enumerated : enumerated.filter((r) => r.sourceId === input.sourceId);

	// (3) R1 debounce + in-flight gate — synchronous, BEFORE any background work is spawned.
	const dispositions: ManualSyncSourceResult[] = [];
	const triggered: SourceRow[] = [];
	for (const row of candidates) {
		if (deps.debounce.isThrottled(row.sourceId)) {
			dispositions.push({ source_id: row.sourceId, disposition: 'debounced' });
			continue;
		}
		deps.debounce.markTriggered(row.sourceId); // stamp + in-flight (§6 concurrency; before spawn).
		triggered.push(row);
		dispositions.push({ source_id: row.sourceId, disposition: 'triggered' });
	}

	// (4) A2 (Sec C3) — fire-and-forget the actual syncs. runOneManualSync never rethrows; the extra
	// .catch is a belt-and-suspenders guard so no unhandled rejection can EVER reach the process.
	for (const row of triggered) {
		void runOneManualSync(deps, row).catch((err) =>
			deps.log(`manual-sync background error source_id=${row.sourceId}: ${errMessage(err)}`)
		);
	}

	return { sources: dispositions };
}

// ── Production wiring ────────────────────────────────────────────────────────────────────────────

/** Write ONE linked_source_sync_audit row with source='manual' (C6a), scoped to row.usersId. Mirrors
 *  poll.ts writeAudit's shape (fresh per-source service_role client; append-only INSERT; the 044
 *  linked_source_id stable FK) but with the manual provenance value the 047 CHECK admits. */
async function writeManualAudit(config: WorkerConfig, row: SourceRow, detail: AuditDetail): Promise<void> {
	const client = TenantBoundClient.forTenant(config, row.usersId);
	try {
		await client.withServiceRole(async (tx) => {
			await tx`
				insert into pfin.linked_source_sync_audit
					(provider, source, users_id, external_connection_id, provider_event_id, detail, linked_source_id)
				values (
					${row.provider}, 'manual', ${row.usersId}, ${row.externalConnectionId},
					${null}, ${tx.json(detail as unknown as Parameters<typeof tx.json>[0])}, ${row.sourceId}::bigint
				)`;
		});
	} finally {
		await client.end();
	}
}

/** The production PollWiring for processSource/markUnhealthy (mirrors poll.ts defaultWiring +
 *  triggerSync.ts productionSyncSourceDeps: the factory, not this file, constructs the raw client so
 *  the fence-tbc-node LEG-1 anchor stays the sole construction site). */
function manualPollWiring(config: WorkerConfig, syncDate: string): PollWiring {
	return {
		clientFor: (usersId) => TenantBoundClient.forTenant(config, usersId),
		buildAdapter: (provider) => buildAdapter(provider, config),
		resolveCredential,
		sync: syncProviderData,
		syncDate,
		readCursor: (client, row) => readSyncCursor(client, row.sourceId, row.usersId),
		writeCursor: (client, row, cursor) => writeSyncCursor(client, row.sourceId, row.usersId, cursor)
	};
}

/**
 * Production deps for serve-admission.ts: RLS-scoped enumeration (C1) + the reused poll ingest path
 * (processSource/markUnhealthy via createPollHandlers) + the source='manual' audit write (C6a). The
 * `debounce` store is passed in (NOT built here) so it PERSISTS across calls for the process lifetime
 * (R1). `syncDate` is computed PER CALL by the caller (long-running server — the date must not freeze
 * at boot).
 */
export function productionManualSyncDeps(
	config: WorkerConfig,
	syncDate: string,
	debounce: SyncDebounce
): ManualSyncDeps {
	const log = (m: string): void => console.log(`[manual-sync] ${m}`);
	const handlers = createPollHandlers(manualPollWiring(config, syncDate), log);
	return {
		enumerate: async (ownerUserId) => {
			const client = TenantBoundClient.forTenant(config, ownerUserId);
			try {
				return await enumerateSourcesForTenant(client, ownerUserId);
			} finally {
				await client.end();
			}
		},
		processSource: (row) => handlers.processSource(row),
		writeAudit: (row, detail) => writeManualAudit(config, row, detail),
		markUnhealthy: (row, err) => handlers.markUnhealthy(row, err),
		debounce,
		syncedAt: syncDate,
		log
	};
}
