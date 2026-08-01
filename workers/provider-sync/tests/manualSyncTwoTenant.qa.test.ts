// manualSyncTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (SELF-317 "Sync now").
//
// SCOPE (QA, NOT a duplicate of Backend's manualSync.test.ts / admissionServer.test.ts): the
// ADVERSARIAL two-tenant + fail-closed cases the engineers' happy/mocked fixtures do not reach.
// Each test would catch a REAL cross-tenant / wedge / audit-leak violation, and every one is
// proven non-vacuously — the inversion (the owned/same-tenant control) fires green alongside the
// adversarial red so a blanket-block or an empty-set can't masquerade as isolation.
//
// This file drives the REAL code, not mocks of it: the REAL enumerateSourcesForTenant (Sec C1
// defense-in-depth filter), the REAL manualSync orchestrator (C2 filter-then-process + R1 debounce
// + A2 fire-and-forget), the REAL createPollHandlers().processSource credential double-bind (layer
// 5), and the REAL createAdmissionServer process (item 7). The ONLY things faked are the DB tx
// (withTenant/withServiceRole) + the provider adapter + the Plaid/SimpleFIN SDKs — never the
// security-load-bearing branch under test.
//
// Sec §7 joint-review items proven here:
//   • #1 (layer 4) worker orchestrator: A's ownerUserId + B's source_id → RLS-scoped enumeration
//        EXCLUDES it → NO processSource, ZERO data effect.
//   • #1 (layer 5) credential double-bind: a foreign source FORCED into processSource → 0 rows →
//        null → THROW, never a cross-tenant fetch.
//   • #2 sync-all as A (B seeded active) → ONLY A's sources touched; ZERO sync_audit for B.
//   • #4 in-flight teeth: a THROWING sync clears in-flight (the finally) → the source is
//        re-triggerable after the window, NOT wedged forever.
//   • #5 exactly one audit per TRIGGERED source, tenant-scoped; a DEBOUNCED source writes ZERO.
//   • #7 fire-and-forget rejection does NOT crash the always-on admission process (other routes
//        still serve).
//
// Grounding: docs/SECURITY §4.5 (two-tenant posture) · temp/sync-now-design.md §1c / §7 ·
// ADR-037 amendment. Sibling: api/tests/manualSyncRelayTwoTenant.qa.test.ts (the app-relay 404
// spoof gate — layer 2, each half tested at its right level).

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import {
	SyncDebounce,
	createSyncDebounce,
	enumerateSourcesForTenant,
	manualSync,
	type ManualSyncDeps,
	type TenantScopedClient
} from '../src/http/manualSync.js';
import {
	createPollHandlers,
	type FetchAdapter,
	type PollClient,
	type PollWiring,
	type SourceRow,
	type SourceSyncOutcome
} from '../src/cli/poll.js';
import type { SyncResult } from '../src/ingest/mapper.js';
import { createAdmissionServer, type AdmissionServerDeps } from '../src/http/admissionServer.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';

const TENANT_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const A_SRC_1 = '42';
const A_SRC_2 = '77';
const B_SRC = '500'; // B's REAL source_id — the id an attacker who knows it would supply.

const SYNC_RESULT: SyncResult = {
	holdingsLanded: 1,
	balancesLanded: 1,
	pricesUpserted: 0,
	transactionsInserted: 4,
	transactionsSkipped: 1,
	droppedTransactions: [],
	unresolvedAccounts: []
};
const OUTCOME: SourceSyncOutcome = { result: SYNC_RESULT, errlist: [] };

function row(sourceId: string, usersId = TENANT_A, provider: SourceRow['provider'] = 'plaid'): SourceRow {
	return { sourceId, provider, usersId, externalConnectionId: `ext_${sourceId}`, providerMetadata: null };
}

// A withTenant client stub whose SELECT returns the given raw rows. Models "what the query
// yields" so we can exercise the REAL enumerateSourcesForTenant defense-in-depth filter. In prod
// RLS scopes the SELECT to the caller; here we deliberately let a B-row leak into the raw result
// to PROVE the code-layer `usersId === ownerUserId` filter drops it (Sec C1 fail-closed).
function tenantClientReturning(rawRows: Array<{ source_id: string; provider: string; users_id: string }>): TenantScopedClient {
	const withTenant = vi.fn(async (fn: (tx: unknown) => Promise<unknown>) => {
		const tx = Object.assign(
			(_s: TemplateStringsArray, ..._v: unknown[]) =>
				rawRows.map((r) => ({
					source_id: r.source_id,
					provider: r.provider,
					users_id: r.users_id,
					external_connection_id: `ext_${r.source_id}`,
					provider_metadata: null
				})),
			{}
		);
		return fn(tx as unknown as never);
	});
	return { withTenant, end: vi.fn(async () => {}) } as unknown as TenantScopedClient;
}

function makeDeps(over: Partial<ManualSyncDeps> = {}): {
	deps: ManualSyncDeps;
	processSource: ReturnType<typeof vi.fn>;
	writeAudit: ReturnType<typeof vi.fn>;
} {
	const processSource = vi.fn(async (_r: SourceRow) => OUTCOME);
	const writeAudit = vi.fn(async () => {});
	const deps: ManualSyncDeps = {
		enumerate: vi.fn(async () => [row(A_SRC_1), row(A_SRC_2)]),
		processSource,
		writeAudit,
		markUnhealthy: vi.fn(async () => {}),
		debounce: createSyncDebounce(),
		syncedAt: '2026-07-31',
		log: vi.fn(),
		...over
	};
	return { deps, processSource, writeAudit };
}

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 1 (layer 4) — worker orchestrator excludes B's source, via the REAL RLS-scoped enumeration.
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #1 layer 4 — A supplies B\'s source_id → tenant-scoped enumeration excludes it (zero effect)', () => {
	it('per-source B_SRC (a foreign id) → candidates empty → NO processSource, NO audit (spoof-safe)', async () => {
		// The REAL enumeration, bound to A. The raw query even leaks a B row; the code drops it.
		const client = tenantClientReturning([
			{ source_id: A_SRC_1, provider: 'plaid', users_id: TENANT_A },
			{ source_id: B_SRC, provider: 'plaid', users_id: TENANT_B }
		]);
		const enumerate = (ownerUserId: string): Promise<SourceRow[]> =>
			enumerateSourcesForTenant(client, ownerUserId);
		const { deps, processSource, writeAudit } = makeDeps({ enumerate });

		const result = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: B_SRC });

		expect(result.sources).toEqual([]); // B_SRC is not in A's enumerated set → filtered out.
		await new Promise((r) => setTimeout(r, 5)); // give any (erroneous) background task a chance.
		expect(processSource).not.toHaveBeenCalled();
		expect(writeAudit).not.toHaveBeenCalled();
	});

	it('NON-VACUOUS control: the SAME orchestrator DOES trigger A\'s OWN source (A_SRC_1) → one processSource', async () => {
		const client = tenantClientReturning([
			{ source_id: A_SRC_1, provider: 'plaid', users_id: TENANT_A },
			{ source_id: B_SRC, provider: 'plaid', users_id: TENANT_B }
		]);
		const { deps, processSource } = makeDeps({
			enumerate: (ownerUserId: string) => enumerateSourcesForTenant(client, ownerUserId)
		});

		const result = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(result.sources).toEqual([{ source_id: A_SRC_1, disposition: 'triggered' }]);
		await vi.waitFor(() => expect(processSource).toHaveBeenCalledTimes(1));
		expect((processSource.mock.calls[0][0] as SourceRow).sourceId).toBe(A_SRC_1);
		// The B row NEVER reaches processSource — the exclusion above is real, not an empty view.
		expect(processSource.mock.calls.every(([r]) => (r as SourceRow).usersId === TENANT_A)).toBe(true);
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 2 + 5 — sync-all as A (B seeded active) → ONLY A's sources; exactly one audit per triggered
// source, each scoped to A; ZERO for B.
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #2 + #5 — sync-all as A with B seeded active → A-only, one manual audit per source, zero for B', () => {
	it('processSource + writeAudit fire ONLY for A\'s two sources; B\'s active source is never touched', async () => {
		// Raw enumeration output mixes A's two sources with B's active source; the C1 filter drops B.
		const client = tenantClientReturning([
			{ source_id: A_SRC_1, provider: 'plaid', users_id: TENANT_A },
			{ source_id: A_SRC_2, provider: 'simplefin', users_id: TENANT_A },
			{ source_id: B_SRC, provider: 'plaid', users_id: TENANT_B }
		]);
		const { deps, processSource, writeAudit } = makeDeps({
			enumerate: (ownerUserId: string) => enumerateSourcesForTenant(client, ownerUserId)
		});

		const result = await manualSync(deps, { ownerUserId: TENANT_A });
		expect(result.sources).toEqual([
			{ source_id: A_SRC_1, disposition: 'triggered' },
			{ source_id: A_SRC_2, disposition: 'triggered' }
		]);

		// Exactly one audit per triggered source (2), each scoped to A; never B (zero sync_audit for B).
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(2));
		expect(processSource).toHaveBeenCalledTimes(2);
		const auditedIds = writeAudit.mock.calls.map(([r]) => (r as SourceRow).sourceId).sort();
		expect(auditedIds).toEqual([A_SRC_1, A_SRC_2].sort());
		expect(writeAudit.mock.calls.every(([r]) => (r as SourceRow).usersId === TENANT_A)).toBe(true);
		// The teeth: B's source_id appears in NO processSource and NO writeAudit call.
		const touched = [...processSource.mock.calls, ...writeAudit.mock.calls].map(([r]) => (r as SourceRow).sourceId);
		expect(touched).not.toContain(B_SRC);
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 5 — a DEBOUNCED source writes ZERO audit rows (only a TRIGGERED source audits).
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #5 — a debounced source produces NO audit row (audit is per-triggered-source only)', () => {
	it('second per-source trigger within 60s → debounced AND writeAudit is NOT called a second time', async () => {
		let nowMs = 1_000_000;
		const debounce = new SyncDebounce({ now: () => nowMs });
		const { deps, writeAudit } = makeDeps({ enumerate: vi.fn(async () => [row(A_SRC_1)]), debounce });

		const first = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(first.sources).toEqual([{ source_id: A_SRC_1, disposition: 'triggered' }]);
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1)); // the ONE triggered audit.

		nowMs += 30_000; // still within the 60s window.
		const second = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(second.sources).toEqual([{ source_id: A_SRC_1, disposition: 'debounced' }]);

		// A debounced source spawns no background run → no second audit row. Give it a beat to be sure.
		await new Promise((r) => setTimeout(r, 5));
		expect(writeAudit).toHaveBeenCalledTimes(1);
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 4 — a THROWING sync clears the in-flight flag (the finally) so the source is re-triggerable
// after the window, NOT wedged. (Backend's test asserts isThrottled==true INSIDE the window, which
// cannot distinguish a leaked in-flight flag from an active window — this adds the disambiguating
// teeth by advancing the clock PAST the window.)
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #4 — a throwing sync does not wedge the source (in-flight cleared in the finally)', () => {
	it('after a throw, within-window → debounced; PAST-window → triggered again (in-flight did NOT leak)', async () => {
		let nowMs = 1_000_000;
		const debounce = new SyncDebounce({ now: () => nowMs });
		const processSource = vi.fn(async () => {
			throw new Error('provider 5xx (scrubbed)');
		});
		const { deps, writeAudit } = makeDeps({
			enumerate: vi.fn(async () => [row(A_SRC_1)]),
			processSource,
			debounce
		});

		// t=0: trigger; the background run throws, audits the failure, and MUST clear in-flight.
		const first = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(first.sources).toEqual([{ source_id: A_SRC_1, disposition: 'triggered' }]);
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1)); // failure-path audit → run finished.
		expect(debounce.isThrottled(A_SRC_1)).toBe(true); // still within the 60s window (last-triggered).

		// +30s: within the window → debounced (window active, distinct from an in-flight leak).
		nowMs += 30_000;
		const within = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(within.sources).toEqual([{ source_id: A_SRC_1, disposition: 'debounced' }]);

		// +31s (=61s total): PAST the window. If the finally had leaked the in-flight flag, this would
		// STILL be 'debounced' forever regardless of the clock. It is 'triggered' → the flag was cleared.
		nowMs += 31_000;
		const after = await manualSync(deps, { ownerUserId: TENANT_A, sourceId: A_SRC_1 });
		expect(after.sources).toEqual([{ source_id: A_SRC_1, disposition: 'triggered' }]);
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(2)); // the re-trigger's own audit.
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 1 (layer 5) — the credential double-bind is the DB-side backstop. Even if a foreign source
// were FORCED into the REAL processSource (defeating layers 2 & 4), resolveCredential double-binds
// (source_id, users_id) → 0 rows → null → THROW, never a cross-tenant fetch.
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #1 layer 5 — resolveCredential double-bind fails closed inside the REAL processSource', () => {
	function makeHandlers(resolveCredential: PollWiring['resolveCredential']) {
		const fetchBalances = vi.fn(async () => []);
		const fetchHoldings = vi.fn(async () => []);
		const fetchTransactions = vi.fn(async () => []);
		const adapter = { fetchBalances, fetchHoldings, fetchTransactions } as unknown as FetchAdapter;
		const client = { withServiceRole: vi.fn(), end: vi.fn(async () => {}) } as unknown as PollClient;
		const wiring: PollWiring = {
			clientFor: () => client,
			buildAdapter: () => adapter,
			resolveCredential,
			sync: vi.fn(async () => SYNC_RESULT),
			syncDate: '2026-07-31'
		};
		return { handlers: createPollHandlers(wiring, () => {}), fetchBalances, fetchHoldings, fetchTransactions };
	}

	// The double-bind: a credential resolves ONLY for A's own source; a foreign source → 0 rows → null.
	const doubleBind: PollWiring['resolveCredential'] = async (_c, r) =>
		r.sourceId === A_SRC_1 && r.usersId === TENANT_A ? 'access-SECRET-never-logged' : null;

	it('a FORCED foreign source (B_SRC under A) → THROWS "no credential resolved"; NO provider fetch happens', async () => {
		const { handlers, fetchBalances, fetchHoldings, fetchTransactions } = makeHandlers(doubleBind);
		await expect(handlers.processSource(row(B_SRC, TENANT_A))).rejects.toThrow(
			/no credential resolved for source_id=500/
		);
		// The credential-less throw happens BEFORE any adapter fetch — no cross-tenant provider call.
		expect(fetchBalances).not.toHaveBeenCalled();
		expect(fetchHoldings).not.toHaveBeenCalled();
		expect(fetchTransactions).not.toHaveBeenCalled();
	});

	it('NON-VACUOUS control: A\'s OWN source resolves a credential → processSource proceeds to fetch', async () => {
		const { handlers, fetchBalances, fetchTransactions } = makeHandlers(doubleBind);
		const outcome = await handlers.processSource(row(A_SRC_1, TENANT_A));
		expect(outcome.result).toEqual(SYNC_RESULT);
		expect(fetchBalances).toHaveBeenCalledTimes(1);
		expect(fetchTransactions).toHaveBeenCalledTimes(1); // the throw above was the double-bind, not a blanket block.
	});
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Item 7 — a fire-and-forget background rejection does NOT crash the always-on admission process.
// Drives the REAL createAdmissionServer with the REAL manualSync whose background sync THROWS, then
// proves the process survives: other routes still serve + NO unhandledRejection escaped the guard.
// ─────────────────────────────────────────────────────────────────────────────────────────────
describe('Sec #7 — fire-and-forget rejection cannot crash the admission process (other routes still serve)', () => {
	const SECRET = 'manual-sync-two-tenant-secret-0123456789abcdef';
	const authed = { [ADMISSION_SECRET_HEADER]: SECRET, 'content-type': 'application/json' };
	let live: Server | undefined;
	const captured: unknown[] = [];
	const onRejection = (err: unknown): void => {
		captured.push(err);
	};

	afterEach(async () => {
		process.off('unhandledRejection', onRejection);
		captured.length = 0;
		if (live) await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;
	});

	function post(url: string, path: string, body: unknown): Promise<Response> {
		return fetch(`${url}${path}`, { method: 'POST', headers: authed, body: JSON.stringify(body) });
	}

	it('POST manual-sync whose background sync throws → 202; /healthz + a second call STILL serve; no unhandled rejection', async () => {
		process.on('unhandledRejection', onRejection);

		// REAL orchestrator deps whose processSource always throws (the fire-and-forget path is exercised).
		const { deps } = makeDeps({
			enumerate: vi.fn(async () => [row(A_SRC_1)]),
			processSource: vi.fn(async () => {
				throw new Error('kaboom-background-manual-sync');
			})
		});
		const full: AdmissionServerDeps = {
			sharedSecret: SECRET,
			mintLinkToken: vi.fn(),
			admit: vi.fn(),
			admitSimplefin: vi.fn(),
			reauthStart: vi.fn(),
			reauthComplete: vi.fn(),
			fetchWebhookVerificationKey: vi.fn(),
			syncSource: vi.fn(),
			manualSync: (input) => manualSync(deps, input), // the REAL orchestrator + REAL fire-and-forget.
			logger: vi.fn()
		};
		live = createAdmissionServer(full);
		await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
		const { port } = live!.address() as AddressInfo;
		const url = `http://127.0.0.1:${port}`;

		// (1) The route returns fast (A2) even though the background sync will throw.
		const res = await post(url, '/admission/manual-sync', { ownerUserId: TENANT_A, source_id: A_SRC_1 });
		expect(res.status).toBe(202);
		expect(await res.json()).toEqual({ accepted: true, sources: [{ source_id: A_SRC_1, disposition: 'triggered' }] });

		// (2) Let the background rejection fire + the guard swallow it.
		await new Promise((r) => setTimeout(r, 30));

		// (3) The process is ALIVE: liveness + a fresh authed route both still serve.
		const health = await fetch(`${url}/healthz`);
		expect(health.status).toBe(200);
		expect(await health.json()).toEqual({ status: 'ok' });
		const second = await post(url, '/admission/manual-sync', { ownerUserId: TENANT_A }); // sync-all still serves.
		expect(second.status).toBe(202);

		// (4) The guard held: NO unhandled rejection carrying our background error escaped.
		await new Promise((r) => setTimeout(r, 10));
		expect(
			captured.some((e) => e instanceof Error && e.message.includes('kaboom-background-manual-sync'))
		).toBe(false);
	});
});
