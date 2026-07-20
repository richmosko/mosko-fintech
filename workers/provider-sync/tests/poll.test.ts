// poll.test.ts — sync scheduler (slice 3b): provider dispatch, per-source failure isolation,
// audit tenant-scoping + errlist surfacing, credential-resolve query shaping. Fixture/mock-
// based — NO live network/DB (the live-DB G2 integration test is QA's).

import { describe, it, expect, vi } from 'vitest';
import {
	buildAdapter,
	createPollHandlers,
	enumerateSources,
	resolveCredential,
	runPoll,
	runPollLoop,
	trailingRange,
	todayIso,
	type AuditDetail,
	type FetchAdapter,
	type PollClient,
	type PollHandlers,
	type PollWiring,
	type SourceRow,
	type SourceSyncOutcome
} from '../src/cli/poll.js';
import { PlaidAdapter } from '../src/adapters/PlaidAdapter.js';
import { SimpleFINAdapter } from '../src/adapters/SimpleFINAdapter.js';
import type { Tx } from '../src/db/TenantBoundClient.js';
import type { WorkerConfig } from '../src/config/env.js';
import type { SyncResult } from '../src/ingest/mapper.js';

const CONFIG: WorkerConfig = {
	db: { host: 'h', port: 5432, database: 'd', user: 'u', password: 'p' },
	plaid: { clientId: 'cid', secret: 'sek', env: 'sandbox' },
	simplefinToken: undefined,
	discordWebhookUrl: undefined,
	probe: { publicUrls: [], confirmRoute: false, timeoutMs: 5000 }
};

const UID_A = '11111111-1111-1111-1111-111111111111';
const UID_B = '22222222-2222-2222-2222-222222222222';
const UID_C = '33333333-3333-3333-3333-333333333333';

const row = (over: Partial<SourceRow> = {}): SourceRow => ({
	sourceId: '1',
	provider: 'simplefin',
	usersId: UID_A,
	externalConnectionId: 'conn-1',
	providerMetadata: null,
	...over
});

const emptyResult: SyncResult = {
	holdingsLanded: 0,
	balancesLanded: 0,
	pricesUpserted: 0,
	transactionsInserted: 0,
	transactionsSkipped: 0,
	droppedTransactions: [],
	unresolvedAccounts: []
};

// ── A fake postgres.js tagged-template tx that records query text + bound values, scripts
//    result rows, and supports tx.json + tx(array). ─────────────────────────────────────
interface FakeTx {
	tx: Tx;
	queries: string[];
	values: unknown[][];
}
function fakeTx(results: unknown[][]): FakeTx {
	const queries: string[] = [];
	const values: unknown[][] = [];
	let call = 0;
	const tagged = (strings: TemplateStringsArray, ...vals: unknown[]) => {
		// postgres.js fragment-helper form `tx(array)` (e.g. `in ${tx(providers)}`) passes a
		// plain array WITHOUT `.raw` — it composes into an outer query, does NOT execute. Return
		// a passthrough fragment; do NOT record it as a query or consume a result slot.
		if (!(strings as { raw?: unknown }).raw) return strings as unknown as Promise<unknown[]>;
		queries.push(strings.join('?').replace(/\s+/g, ' ').trim());
		values.push(vals);
		const r = results[call] ?? [];
		call += 1;
		return Promise.resolve(r);
	};
	(tagged as unknown as { json: (v: unknown) => unknown }).json = (v: unknown) => ({ __json: v });
	return { tx: tagged as unknown as Tx, queries, values };
}

/** A fake PollClient whose withServiceRole runs fn against a scripted fakeTx. */
function fakeClient(ft: FakeTx): PollClient & { ended: boolean } {
	const c = {
		ended: false,
		async withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
			return fn(ft.tx);
		},
		async end() {
			c.ended = true;
		}
	};
	return c;
}

// ─────────────────────────────────────────────────────────────────────────────────
describe('buildAdapter — provider dispatch', () => {
	it('routes plaid → PlaidAdapter', () => {
		expect(buildAdapter('plaid', CONFIG)).toBeInstanceOf(PlaidAdapter);
	});
	it('routes simplefin → SimpleFINAdapter', () => {
		expect(buildAdapter('simplefin', CONFIG)).toBeInstanceOf(SimpleFINAdapter);
	});
	it('throws (fail-loud) on an unsupported provider', () => {
		expect(() => buildAdapter('teller' as never, CONFIG)).toThrow(/unsupported poll provider/);
	});
});

describe('trailingRange / todayIso', () => {
	it('todayIso → YYYY-MM-DD', () => {
		expect(todayIso(new Date('2026-07-18T09:30:00Z'))).toBe('2026-07-18');
	});
	it('trailingRange spans ~89 days ending at syncDate', () => {
		expect(trailingRange('2026-07-18')).toEqual({ start: '2026-04-20', end: '2026-07-18' });
	});
});

// ── The Sec build target: per-source failure isolation ─────────────────────────────
describe('runPollLoop — per-source failure isolation (design §8 Sec risk #1)', () => {
	it('one source throwing NEVER aborts the fleet; each source audited under its OWN tenant', async () => {
		const sources = [
			row({ sourceId: '1', usersId: UID_A, provider: 'simplefin' }),
			row({ sourceId: '2', usersId: UID_B, provider: 'plaid' }), // this one throws
			row({ sourceId: '3', usersId: UID_C, provider: 'simplefin' })
		];
		const audited: { row: SourceRow; detail: AuditDetail }[] = [];
		const processed: string[] = [];

		const handlers: PollHandlers = {
			async processSource(r) {
				processed.push(r.sourceId);
				if (r.sourceId === '2') throw new Error('SimpleFIN accounts failed (HTTP 403)');
				const outcome: SourceSyncOutcome = {
					result: emptyResult,
					errlist: r.sourceId === '3' ? [{ inst: 'Synchrony', msg: 'gappy' }] : [],
					corrections: undefined
				};
				return outcome;
			},
			async writeAudit(r, detail) {
				audited.push({ row: r, detail });
			},
			log: vi.fn()
		};

		const summary = await runPollLoop(sources, handlers, '2026-07-18');

		// Fleet completed — source #3 processed AFTER #2 threw.
		expect(processed).toEqual(['1', '2', '3']);
		expect(summary).toMatchObject({ total: 3, succeeded: 2, failed: 1 });
		expect(summary.failures).toEqual([{ sourceId: '2', provider: 'plaid', error: 'SimpleFIN accounts failed (HTTP 403)' }]);

		// EVERY source got exactly one audit row, scoped to its own tenant.
		expect(audited).toHaveLength(3);
		expect(audited.map((a) => a.row.usersId)).toEqual([UID_A, UID_B, UID_C]);

		// The error is recorded on #2's row ONLY — no leak into #1 / #3.
		const a1 = audited.find((a) => a.row.sourceId === '1')!;
		const a2 = audited.find((a) => a.row.sourceId === '2')!;
		const a3 = audited.find((a) => a.row.sourceId === '3')!;
		expect(a1.detail).toMatchObject({ ok: true });
		expect(a1.detail.error).toBeUndefined();
		expect(a2.detail).toMatchObject({ ok: false, error: 'SimpleFIN accounts failed (HTTP 403)' });
		expect(a2.detail.result).toBeUndefined();
		expect(a3.detail.error).toBeUndefined();

		// errlist surfaced (never swallowed) for the gappy source.
		expect(a3.detail.errlist).toEqual([{ inst: 'Synchrony', msg: 'gappy' }]);
		expect(a1.detail.errlist).toEqual([]);
	});

	it('a writeAudit failure is logged and also non-fatal (fleet continues)', async () => {
		const sources = [row({ sourceId: '1' }), row({ sourceId: '2' })];
		const log = vi.fn();
		const handlers: PollHandlers = {
			async processSource() {
				return { result: emptyResult, errlist: [], corrections: undefined };
			},
			async writeAudit(r) {
				if (r.sourceId === '1') throw new Error('audit insert failed');
			},
			log
		};
		const summary = await runPollLoop(sources, handlers, '2026-07-18');
		expect(summary.succeeded).toBe(2); // sync still succeeded; audit failure doesn't flip it
		expect(log).toHaveBeenCalledWith(expect.stringContaining('sync_audit write FAILED source_id=1'));
	});
});

// ── Handler wiring: dispatch + credential + audit shaping ───────────────────────────
describe('createPollHandlers.processSource', () => {
	it('resolves credential, dispatches, fetches, lands, surfaces errlist + corrections', async () => {
		const client = fakeClient(fakeTx([]));
		const fetchOrder: string[] = [];
		const adapter: FetchAdapter = {
			async fetchBalances() {
				fetchOrder.push('balances');
				return [];
			},
			async fetchHoldings() {
				fetchOrder.push('holdings');
				return [];
			},
			async fetchTransactions() {
				fetchOrder.push('transactions');
				return [];
			},
			getLastErrlist: () => [{ inst: 'X' }]
		};
		const sync = vi.fn().mockResolvedValue(emptyResult);
		const wiring: PollWiring = {
			clientFor: () => client,
			buildAdapter: () => adapter,
			resolveCredential: async () => 'ACCESS-URL-SECRET',
			sync,
			syncDate: '2026-07-18'
		};
		const handlers = createPollHandlers(wiring, vi.fn());
		const outcome = await handlers.processSource(row({ sourceId: '5', provider: 'simplefin' }));

		expect(fetchOrder).toEqual(['balances', 'holdings', 'transactions']);
		expect(outcome.result).toBe(emptyResult);
		expect(outcome.errlist).toEqual([{ inst: 'X' }]);
		// sync got the resolved credential via the SourceRef + the bigint id.
		expect(sync).toHaveBeenCalledWith(client, 5n, 'simplefin', { balances: [], holdings: [], transactions: [] });
		expect(client.ended).toBe(true); // client closed in finally
	});

	it('throws (fail-loud) when no credential resolves — never emits the credential', async () => {
		const client = fakeClient(fakeTx([]));
		const log = vi.fn();
		const wiring: PollWiring = {
			clientFor: () => client,
			buildAdapter: () => {
				throw new Error('should not build an adapter without a credential');
			},
			resolveCredential: async () => null,
			sync: vi.fn(),
			syncDate: '2026-07-18'
		};
		const handlers = createPollHandlers(wiring, log);
		await expect(handlers.processSource(row({ sourceId: '9' }))).rejects.toThrow(/no credential resolved for source_id=9/);
		expect(client.ended).toBe(true);
	});
});

describe('createPollHandlers.writeAudit — tenant-scoped scheduled_poll row', () => {
	it('inserts one append-only row: provider, scheduled_poll, users_id, provider_event_id NULL, detail jsonb', async () => {
		const ft = fakeTx([[]]);
		const client = fakeClient(ft);
		const wiring: PollWiring = {
			clientFor: () => client,
			buildAdapter: () => ({}) as FetchAdapter,
			resolveCredential: async () => 'x',
			sync: vi.fn(),
			syncDate: '2026-07-18'
		};
		const handlers = createPollHandlers(wiring, vi.fn());
		const detail: AuditDetail = { ok: true, syncedAt: '2026-07-18', result: emptyResult, errlist: [] };
		await handlers.writeAudit(row({ sourceId: '7', usersId: UID_B, provider: 'plaid', externalConnectionId: 'ec-7' }), detail);

		expect(ft.queries[0]).toContain('insert into pfin.linked_source_sync_audit');
		expect(ft.queries[0]).toContain("'scheduled_poll'");
		// bound values: provider, users_id, external_connection_id, provider_event_id(null), detail(json)
		const vals = ft.values[0]!;
		expect(vals[0]).toBe('plaid');
		expect(vals[1]).toBe(UID_B); // users_id scopes the audit to THIS source's tenant
		expect(vals[2]).toBe('ec-7');
		expect(vals[3]).toBeNull(); // provider_event_id NULL for poll
		expect(vals[4]).toEqual({ __json: detail }); // detail via tx.json
		expect(client.ended).toBe(true);
	});
});

describe('enumerateSources / resolveCredential — query shaping (service_role)', () => {
	it('enumerateSources filters is_active + not-revoked + poll providers; camelCases rows', async () => {
		const ft = fakeTx([
			[{ source_id: '3', provider: 'simplefin', users_id: UID_A, external_connection_id: 'c3', provider_metadata: { a: 1 } }]
		]);
		const rows = await enumerateSources(fakeClient(ft));
		expect(ft.queries[0]).toContain('from pfin.linked_source');
		expect(ft.queries[0]).toContain('is_active = true');
		expect(ft.queries[0]).toContain("connection_status <> 'revoked'");
		expect(rows).toEqual([
			{ sourceId: '3', provider: 'simplefin', usersId: UID_A, externalConnectionId: 'c3', providerMetadata: { a: 1 } }
		]);
	});

	it('resolveCredential binds source_id + users_id; returns null on no row', async () => {
		const hit = fakeTx([[{ decrypted_credential: 'THE-SECRET' }]]);
		expect(await resolveCredential(fakeClient(hit), row({ sourceId: '4', usersId: UID_A }))).toBe('THE-SECRET');
		expect(hit.queries[0]).toContain('from pfin.decrypted_source_credential');
		expect(hit.values[0]).toEqual([4, UID_A]); // source_id (Number) + users_id in-code binding

		const miss = fakeTx([[]]);
		expect(await resolveCredential(fakeClient(miss), row({ sourceId: '4' }))).toBeNull();
	});
});

// ── #7 [MERGE-GATE C3] CA-2 probe seam NEVER flips the poll exit-code contract ───────
// runPoll THROWS only on a fleet-fatal (enumeration / DB unreachable) ⇒ main() exit 1. The
// SELF-279 probe pre-loop step must add NO new non-zero-exit path: a probe that throws (or one
// that detects-positive) must leave runPoll RESOLVING with a normal summary (⇒ exit 0). We
// inject the `probe` seam (RunPollDeps.probe) + an `enumerate` stub so the whole run is
// network-/DB-free, and assert runPoll never rejects.
describe('runPoll — CA-2 probe seam never flips the exit-code contract (design §9 #7 / C3)', () => {
	const okAdapter: FetchAdapter = {
		async fetchBalances() {
			return [];
		},
		async fetchHoldings() {
			return [];
		},
		async fetchTransactions() {
			return [];
		},
		getLastErrlist: () => []
	};

	it('a probe seam that THROWS is caught + logged non-fatally; runPoll completes a normal (exit-0) run', async () => {
		const log = vi.fn();
		const summary = await runPoll(CONFIG, {
			probe: async () => {
				throw new Error('probe blew up');
			},
			enumerate: async () => [], // no DB; the fleet-fatal enumeration path is untouched
			log,
			syncDate: '2026-07-18'
		});
		// runPoll RESOLVED (did not reject) ⇒ main() would exit 0.
		expect(summary).toMatchObject({ total: 0, succeeded: 0, failed: 0, failures: [] });
		expect(log).toHaveBeenCalledWith(expect.stringContaining('CA-2 probe step errored (non-fatal)'));
	});

	it('a probe seam that DETECTS-POSITIVE (resolves) still exits 0 — a finding alerts/logs, never pages', async () => {
		const log = vi.fn();
		let probeRan = false;
		const summary = await runPoll(CONFIG, {
			probe: async (_config, l) => {
				probeRan = true;
				// mirror the real positive-detection log line; crucially it RESOLVES (no throw).
				l('CA-2 probe: POSITIVE DETECTION — admission endpoint PUBLICLY REACHABLE: https://x/healthz');
			},
			enumerate: async () => [row({ sourceId: '1', provider: 'simplefin' })],
			wiring: {
				clientFor: () => fakeClient(fakeTx([[]])),
				buildAdapter: () => okAdapter,
				resolveCredential: async () => 'ACCESS-URL-SECRET',
				sync: vi.fn().mockResolvedValue(emptyResult)
			},
			log,
			syncDate: '2026-07-18'
		});
		expect(probeRan).toBe(true);
		// enumeration + the per-source loop still ran to completion ⇒ exit 0 with the source synced.
		expect(summary).toMatchObject({ total: 1, succeeded: 1, failed: 0 });
	});
});
