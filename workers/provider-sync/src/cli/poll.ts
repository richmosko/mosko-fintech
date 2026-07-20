// poll.ts — provider-sync SYNC SCHEDULER (slice 3b). A Coolify-cron ENTRYPOINT (NOT an
// in-app timer; workers/CLAUDE.md "Cron via Coolify"): `node dist/cli/poll.js`, invoked
// once per Coolify cron container run, exits when done.
//
// FLOW (design temp/provider-sync-scheduler-design.md §1):
//   1. ENUMERATE (service_role, cross-tenant): poll-eligible pfin.linked_source rows
//      (is_active + connection_status <> 'revoked' + a poll-capable provider), via the
//      enumeration-only TenantBoundClient (no tenant bound; withServiceRole = BYPASSRLS).
//   2. PER SOURCE — SEQUENTIAL + FAILURE-ISOLATED (each in its own try/catch; each under
//      its OWN forTenant(row.users_id) client — the per-source isolation anchor):
//        a. resolve the credential (service_role decrypt view, tenant-keyed by join);
//        b. dispatch by provider → Plaid | SimpleFIN adapter → fetchBalances/Holdings/
//           Transactions;
//        c. land via the SHIPPED syncProviderData (this file NEVER re-implements landing);
//        d. write ONE linked_source_sync_audit row (source='scheduled_poll', provider_event_id
//           NULL) scoped to THIS source's tenant, detail = landed counts + errlist + error.
//   3. One source's error NEVER aborts the fleet, and NEVER leaks into another source's
//      audit row (design §8 Sec risk #1).
//
// EXIT-CODE SEMANTICS (DevOps Coolify→Discord contract): non-zero = FLEET-FATAL only
// (can't enumerate / DB unreachable → runPoll throws → main() catch → exit 1). A run where
// the fleet ran exits 0 EVEN WITH per-source failures — those are isolated + captured in the
// scheduled_poll audit + the structured `FAILED source_id=…` log lines (DevOps-routable),
// NOT a page. A single gappy/revoked institution must never exit non-zero. No webhook secret
// in code (Discord is Coolify-side).
//
// The SCHEDULER enumerates + invokes; the ADAPTERS + syncProviderData are shipped. The
// core loop (runPollLoop) + dispatch (buildAdapter) are pure/injectable for unit testing
// with NO live network/DB (the live-DB G2 integration test is QA's).

import { fileURLToPath } from 'node:url';
import { loadConfig, type WorkerConfig } from '../config/env.js';
import { TenantBoundClient, type Tx } from '../db/TenantBoundClient.js';
import { PlaidAdapter, type PlaidClientLike } from '../adapters/PlaidAdapter.js';
import { SimpleFINAdapter } from '../adapters/SimpleFINAdapter.js';
import { buildPlaidClient } from './admit.js';
import { syncProviderData, type ProviderData, type SyncResult } from '../ingest/mapper.js';
import { runAdmissionReachabilityProbe } from '../http/reachabilityProbe.js';
import type {
	BalanceDTO,
	CorrectionCounts,
	DateRange,
	HoldingDTO,
	SourceRef,
	TransactionDTO
} from '../adapters/ProviderAdapter.js';

// ── Poll-eligible providers ──────────────────────────────────────────────────────
// Only providers with a fetch* adapter + a stored credential are polled. manual/import
// carry no credential (the decrypt-view INNER JOIN would exclude them anyway); snaptrade/
// teller have no adapter yet. Filtered in the enumeration query too (defense in depth).
export type PollProvider = 'plaid' | 'simplefin';
export const POLL_PROVIDERS: readonly PollProvider[] = ['plaid', 'simplefin'];

/** One poll-eligible source row (camelCased from pfin.linked_source). */
export interface SourceRow {
	/** bigint identity as a string (postgres.js returns bigint as string). */
	sourceId: string;
	provider: PollProvider;
	usersId: string;
	externalConnectionId: string | null;
	providerMetadata: unknown;
}

/** The linked_source_sync_audit.detail jsonb payload for one source-run. NEVER carries the
 *  credential — only landed counts, the gappy-institution errlist, and a SCRUBBED error. */
export interface AuditDetail {
	ok: boolean;
	syncedAt: string;
	result?: SyncResult;
	/** SimpleFIN per-account gappy-institution failures (surfaced, never swallowed). */
	errlist?: unknown[];
	/** Plaid correction counts (OWD-2a: logged, not applied). */
	corrections?: CorrectionCounts;
	/** Scrubbed error message on the failure path. */
	error?: string;
}

export interface SourceSyncOutcome {
	result: SyncResult;
	errlist: unknown[];
	corrections?: CorrectionCounts;
}

export interface PollSummary {
	total: number;
	succeeded: number;
	failed: number;
	failures: { sourceId: string; provider: string; error: string }[];
}

/** The per-source handlers the loop drives. Split from the loop so failure isolation is
 *  unit-testable with pure mocks (no client/adapter/DB). */
export interface PollHandlers {
	/** Resolve credential + fetch + land for one source. THROWS on any failure (the loop
	 *  isolates it). */
	processSource(row: SourceRow): Promise<SourceSyncOutcome>;
	/** Append the scheduled_poll audit row for this source, scoped to row.usersId. */
	writeAudit(row: SourceRow, detail: AuditDetail): Promise<void>;
	log(message: string): void;
}

/** The subset of TenantBoundClient the scheduler consumes (structural — a fake satisfies it
 *  in tests; TenantBoundClient satisfies it in production). */
export interface PollClient {
	withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
	end(): Promise<void>;
}

/** The subset of a ProviderAdapter the scheduler consumes (fetch* + optional diagnostics). */
export interface FetchAdapter {
	fetchBalances(source: SourceRef): Promise<BalanceDTO[]>;
	fetchHoldings(source: SourceRef): Promise<HoldingDTO[]>;
	fetchTransactions(source: SourceRef, range: DateRange): Promise<TransactionDTO[]>;
	/** SimpleFIN gappy-institution errlist (design §8 Sec risk #3). */
	getLastErrlist?(): unknown[];
	/** Plaid correction counts. */
	getLastSyncDiagnostics?(): CorrectionCounts;
}

/** syncProviderData signature (needs a concrete TenantBoundClient). Injectable for tests. */
export type SyncFn = (
	client: TenantBoundClient,
	sourceId: bigint,
	provider: string,
	data: ProviderData
) => Promise<SyncResult>;

/** All the seams createPollHandlers() needs — defaulted for production in runPoll(). */
export interface PollWiring {
	clientFor: (usersId: string) => PollClient;
	buildAdapter: (provider: PollProvider) => FetchAdapter;
	resolveCredential: (client: PollClient, row: SourceRow) => Promise<string | null>;
	sync: SyncFn;
	syncDate: string;
}

// ── Pure helpers ───────────────────────────────────────────────────────────────

const errMessage = (err: unknown): string => (err instanceof Error ? err.message : String(err));

/** ISO date (YYYY-MM-DD) for a Date. The scheduler stamps one syncDate per run. */
export function todayIso(now: Date): string {
	return now.toISOString().slice(0, 10);
}

/** The full trailing window each run pulls (design §3): ~89 days (SimpleFIN caps ~90; Plaid
 *  uses the same). The shipped (source_provider, provider_txn_id) dedup makes re-appearing
 *  txns no-ops — idempotent + self-healing, no cursor state to corrupt. SimpleFIN ignores the
 *  range (computes its own window from syncDate); Plaid uses it for the investment-txn window. */
export function trailingRange(syncDate: string, days = 89): DateRange {
	const end = new Date(`${syncDate}T00:00:00Z`);
	const start = new Date(end.getTime() - days * 24 * 60 * 60 * 1000);
	return { start: start.toISOString().slice(0, 10), end: syncDate };
}

/** Dispatch: provider → the matching adapter (fetch-only construction; no dbFor needed —
 *  the scheduler never admits credentials). PlaidAdapter needs the SDK client; SimpleFINAdapter
 *  uses global fetch. Throws on an unsupported provider (fail-loud). */
export function buildAdapter(provider: PollProvider, config: WorkerConfig): FetchAdapter {
	switch (provider) {
		case 'plaid':
			return new PlaidAdapter(buildPlaidClient(config) as unknown as PlaidClientLike);
		case 'simplefin':
			return new SimpleFINAdapter();
		default: {
			// Exhaustiveness guard — a new PollProvider must add a case here.
			const never: never = provider;
			throw new Error(`buildAdapter: unsupported poll provider ${String(never)}`);
		}
	}
}

// ── Enumeration (service_role, cross-tenant) ─────────────────────────────────────

/** SELECT poll-eligible linked_source rows across all tenants (service_role BYPASSRLS on the
 *  enumeration-only client). is_active + not-revoked + a poll-capable provider. */
export async function enumerateSources(client: PollClient): Promise<SourceRow[]> {
	const rows = await client.withServiceRole(
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
	return rows.map((r) => ({
		sourceId: String(r.source_id),
		provider: r.provider as PollProvider,
		usersId: r.users_id,
		externalConnectionId: r.external_connection_id,
		providerMetadata: r.provider_metadata
	}));
}

/** Resolve a source's decrypted credential (service_role decrypt view). Binds BOTH source_id
 *  AND users_id in code (Decision 1 in-code tenant binding + defense-in-depth: a mismatch
 *  reads 0 rows). Returns null when no credential resolves (credential-less / missing source).
 *  The returned secret is NEVER logged. */
export async function resolveCredential(client: PollClient, row: SourceRow): Promise<string | null> {
	const rows = await client.withServiceRole(
		(tx) =>
			tx<{ decrypted_credential: string }[]>`
			select decrypted_credential
			from pfin.decrypted_source_credential
			where source_id = ${Number(row.sourceId)}
			  and users_id = ${row.usersId}`
	);
	return rows[0]?.decrypted_credential ?? null;
}

// ── Handlers (production wiring) ─────────────────────────────────────────────────

export function createPollHandlers(wiring: PollWiring, log: (message: string) => void): PollHandlers {
	return {
		async processSource(row) {
			const client = wiring.clientFor(row.usersId);
			try {
				const credential = await wiring.resolveCredential(client, row);
				if (credential === null) {
					// Fail-loud (audited on the error path) — NEVER log the (absent) credential.
					throw new Error(`no credential resolved for source_id=${row.sourceId} (${row.provider})`);
				}
				const adapter = wiring.buildAdapter(row.provider);
				const sourceRef: SourceRef = {
					sourceId: BigInt(row.sourceId),
					accessToken: credential, // consumed by the adapter's HTTP fetch; never logged.
					syncDate: wiring.syncDate
				};
				const range = trailingRange(wiring.syncDate);
				const balances = await adapter.fetchBalances(sourceRef);
				const holdings = await adapter.fetchHoldings(sourceRef);
				const transactions = await adapter.fetchTransactions(sourceRef, range);
				// The shipped orchestration (its own two-access-mode + idempotency). The cast is
				// localized: production clientFor returns a real TenantBoundClient (PollClient is
				// its structural subset); tests inject a fake + a stub sync that ignores it.
				const result = await wiring.sync(client as unknown as TenantBoundClient, sourceRef.sourceId, row.provider, {
					balances,
					holdings,
					transactions
				});
				return {
					result,
					errlist: adapter.getLastErrlist?.() ?? [],
					corrections: adapter.getLastSyncDiagnostics?.()
				};
			} finally {
				await client.end();
			}
		},

		async writeAudit(row, detail) {
			// A FRESH per-source client (fail-safe: even if processSource's client died on the
			// error path, the audit still writes). service_role — linked_source_sync_audit is
			// service_role-only + append-only (INSERT). users_id = row.usersId scopes this audit
			// row to THIS source's tenant (design §8 Sec risk #1 — no cross-source leak).
			const client = wiring.clientFor(row.usersId);
			try {
				await client.withServiceRole(async (tx) => {
					await tx`
						insert into pfin.linked_source_sync_audit
							(provider, source, users_id, external_connection_id, provider_event_id, detail)
						values (
							${row.provider}, 'scheduled_poll', ${row.usersId}, ${row.externalConnectionId},
							${null}, ${tx.json(detail as unknown as Parameters<typeof tx.json>[0])}
						)`;
				});
			} finally {
				await client.end();
			}
		},

		log
	};
}

// ── The failure-isolated loop (pure — mock-testable) ─────────────────────────────

/**
 * Drive each source through processSource → writeAudit, SEQUENTIALLY. Per-source failure
 * isolation (design §8 Sec risk #1): a processSource throw is caught, recorded in THIS
 * source's OWN audit row (scoped to its tenant by the handler), and the loop continues —
 * one gappy/revoked/erroring source never aborts the fleet. A writeAudit failure is logged
 * (Discord-routable) and also non-fatal.
 */
export async function runPollLoop(
	sources: readonly SourceRow[],
	handlers: PollHandlers,
	syncedAt: string
): Promise<PollSummary> {
	const failures: PollSummary['failures'] = [];
	let succeeded = 0;
	let failed = 0;

	for (const row of sources) {
		let detail: AuditDetail;
		try {
			const outcome = await handlers.processSource(row);
			detail = {
				ok: true,
				syncedAt,
				result: outcome.result,
				errlist: outcome.errlist,
				corrections: outcome.corrections
			};
			succeeded += 1;
			const gappy = outcome.errlist.length > 0 ? ` errlist=${outcome.errlist.length}` : '';
			handlers.log(`synced source_id=${row.sourceId} provider=${row.provider}${gappy}`);
		} catch (err) {
			// Adapter errors are already scrubbed (scrubbedPlaidError/scrubbedSimplefinError);
			// non-adapter (DB) errors never carry the credential (it is only ever an HTTP-fetch
			// value + a bound $N param, never interpolated into SQL text). Keep .message only.
			const message = errMessage(err);
			detail = { ok: false, syncedAt, error: message };
			failed += 1;
			failures.push({ sourceId: row.sourceId, provider: row.provider, error: message });
			handlers.log(`FAILED source_id=${row.sourceId} provider=${row.provider}: ${message}`);
		}

		// Audit is scoped to THIS row's tenant inside the handler → no cross-source leak.
		try {
			await handlers.writeAudit(row, detail);
		} catch (auditErr) {
			handlers.log(
				`sync_audit write FAILED source_id=${row.sourceId} provider=${row.provider}: ${errMessage(auditErr)}`
			);
		}
	}

	return { total: sources.length, succeeded, failed, failures };
}

// ── Entrypoint ───────────────────────────────────────────────────────────────────

/** Optional injection surface for tests (production defaults are built from config). */
export interface RunPollDeps {
	syncDate?: string;
	now?: Date;
	log?: (message: string) => void;
	/** Override the whole wiring (tests). */
	wiring?: Partial<PollWiring>;
	/** Override enumeration (tests). */
	enumerate?: (config: WorkerConfig) => Promise<SourceRow[]>;
	/** Override the CA-2 reachability probe pre-loop step (SELF-279). Tests stub to a no-op, or to a
	 *  thrower to assert the exit-code contract is unaffected. Defaults to runAdmissionReachabilityProbe. */
	probe?: (config: WorkerConfig, log: (message: string) => void) => Promise<void>;
}

/** Build the production wiring from config (all seams overridable via deps.wiring). */
function defaultWiring(config: WorkerConfig, syncDate: string, over: Partial<PollWiring> = {}): PollWiring {
	return {
		clientFor: over.clientFor ?? ((usersId) => TenantBoundClient.forTenant(config, usersId)),
		buildAdapter: over.buildAdapter ?? ((provider) => buildAdapter(provider, config)),
		resolveCredential: over.resolveCredential ?? resolveCredential,
		sync: over.sync ?? syncProviderData,
		syncDate: over.syncDate ?? syncDate
	};
}

/**
 * Run one poll cycle: enumerate → per-source sync+audit → summarize. Returns the summary.
 * THROWS only on a FLEET-FATAL (enumeration / DB unreachable); per-source failures are caught
 * inside the loop, audited, and returned in `summary.failures` — they do NOT throw. The CLI
 * main() therefore exits non-zero ONLY when this throws (fleet-fatal → Discord page); a
 * completed run exits 0 even with per-source failures (the ratified no-page-on-per-source
 * contract — a single gappy/revoked institution must never page). See the exit-code block at
 * the top of this file + main() below.
 */
export async function runPoll(config: WorkerConfig, deps: RunPollDeps = {}): Promise<PollSummary> {
	const log = deps.log ?? ((m: string) => console.log(`[poll] ${m}`));
	const syncDate = deps.syncDate ?? todayIso(deps.now ?? new Date());

	// (0) CA-2 recurring reachability probe — isolated + non-fatal (SELF-279). A positive detection
	//     alerts via Discord + logs a durable finding; it NEVER throws out of runPoll and NEVER
	//     changes the exit code. Runs BEFORE enumeration so it touches no DB/enumeration exit path
	//     and cannot mask a real fleet-fatal. The step is fail-safe internally; this outer try/catch
	//     is belt-and-suspenders (per design §6). A bounded per-URL timeout caps its wall-time.
	try {
		await (deps.probe ?? runAdmissionReachabilityProbe)(config, log);
	} catch (probeErr) {
		log(`CA-2 probe step errored (non-fatal): ${errMessage(probeErr)}`);
	}

	// (1) ENUMERATE — the enumeration-only client (service_role, no tenant bound). Its own
	// short-lived connection, ended before the per-source loop opens per-tenant clients.
	let sources: SourceRow[];
	if (deps.enumerate) {
		sources = await deps.enumerate(config);
	} else {
		const enumClient = TenantBoundClient.forEnumeration(config);
		try {
			sources = await enumerateSources(enumClient);
		} finally {
			await enumClient.end();
		}
	}
	log(`enumerated ${sources.length} poll-eligible source(s) for ${syncDate}`);

	// (2) PER-SOURCE failure-isolated loop.
	const wiring = defaultWiring(config, syncDate, deps.wiring);
	const handlers = createPollHandlers(wiring, log);
	const summary = await runPollLoop(sources, handlers, syncDate);

	log(`poll complete: ${summary.succeeded} ok, ${summary.failed} failed of ${summary.total}`);
	return summary;
}

async function main(): Promise<void> {
	// Fleet-fatal (enumeration / DB unreachable) throws out of runPoll → the entrypoint catch
	// sets exit 1 (Coolify → Discord page). A completed run exits 0 EVEN WITH per-source
	// failures — those are isolated + audited (scheduled_poll rows) + logged (FAILED lines),
	// NOT a page (DevOps Coolify→Discord contract; a single gappy/revoked source must not exit
	// non-zero). The summary counts are logged inside runPoll for observability.
	await runPoll(loadConfig());
}

// Entrypoint guard: run main() only when invoked directly (node dist/cli/poll.js), NOT when
// imported by a unit test (mirrors admit.ts).
const invokedPath = process.argv[1];
const isMain = invokedPath !== undefined && fileURLToPath(import.meta.url) === invokedPath;
if (isMain) {
	main().catch((err: unknown) => {
		// Adapter/enumeration errors are scrubbed at source; surface only .message.
		console.error(err instanceof Error ? err.message : String(err));
		process.exitCode = 1;
	});
}
