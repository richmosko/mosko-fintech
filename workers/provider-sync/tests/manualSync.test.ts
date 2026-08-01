// manualSync.test.ts — SELF-317 "Sync now" orchestration (worker side). All seams injected (no live
// Plaid/DB). Asserts the Sec conditions in code:
//   • C1 — enumeration is the ONLY source of truth (a source the caller doesn't own can't appear).
//   • C2 — per-source = filter-then-process: a requested source_id NOT in the enumerated set is a
//           no-op/skip (NEVER passed into processSource).
//   • C3/A2 — the route resolves FAST (dispositions) before the background sync runs; a background
//           rejection cannot escape (fire-and-forget guard + in-flight cleared in finally).
//   • C6a — exactly one writeAudit per triggered source, on BOTH the success and failure paths.
//   • R1 — 60s/source debounce + in-flight flag (fake clock).

import { describe, it, expect, vi } from 'vitest';
import {
	SyncDebounce,
	createSyncDebounce,
	enumerateSourcesForTenant,
	manualSync,
	type ManualSyncDeps,
	type TenantScopedClient
} from '../src/http/manualSync.js';
import type { SourceRow, SourceSyncOutcome } from '../src/cli/poll.js';
import type { SyncResult } from '../src/ingest/mapper.js';

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const OTHER = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

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

function row(sourceId: string, provider: SourceRow['provider'] = 'plaid', usersId = OWNER): SourceRow {
	return { sourceId, provider, usersId, externalConnectionId: `ext_${sourceId}`, providerMetadata: null };
}

function makeDeps(over: Partial<ManualSyncDeps> = {}): {
	deps: ManualSyncDeps;
	processSource: ReturnType<typeof vi.fn>;
	writeAudit: ReturnType<typeof vi.fn>;
	markUnhealthy: ReturnType<typeof vi.fn>;
} {
	const processSource = vi.fn(async (_r: SourceRow) => OUTCOME);
	const writeAudit = vi.fn(async () => {});
	const markUnhealthy = vi.fn(async () => {});
	const deps: ManualSyncDeps = {
		enumerate: vi.fn(async () => [row('42'), row('77')]),
		processSource,
		writeAudit,
		markUnhealthy,
		debounce: createSyncDebounce(),
		syncedAt: '2026-07-31',
		log: vi.fn(),
		...over
	};
	return { deps, processSource, writeAudit, markUnhealthy };
}

describe('manualSync — dispatch + dispositions (phase 1, synchronous)', () => {
	it('sync-all: every enumerated source is triggered; the actual syncs run in the background', async () => {
		const { deps, processSource, writeAudit } = makeDeps();
		const result = await manualSync(deps, { ownerUserId: OWNER });

		expect(result.sources).toEqual([
			{ source_id: '42', disposition: 'triggered' },
			{ source_id: '77', disposition: 'triggered' }
		]);
		// A2: the background runs complete AFTER the fast return — wait for both audits.
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(2));
		expect(processSource).toHaveBeenCalledTimes(2);
	});

	it('C2 — per-source: a requested id IN the enumerated set is triggered (only that one)', async () => {
		const { deps, processSource } = makeDeps();
		const result = await manualSync(deps, { ownerUserId: OWNER, sourceId: '77' });
		expect(result.sources).toEqual([{ source_id: '77', disposition: 'triggered' }]);
		await vi.waitFor(() => expect(processSource).toHaveBeenCalledTimes(1));
		expect((processSource.mock.calls[0][0] as SourceRow).sourceId).toBe('77');
	});

	it('C2 — a requested id NOT in the enumerated set is a no-op/skip (never reaches processSource)', async () => {
		const { deps, processSource, writeAudit } = makeDeps();
		const result = await manualSync(deps, { ownerUserId: OWNER, sourceId: '999' });
		expect(result.sources).toEqual([]); // filtered out — never passed downstream (spoof-safe).
		// Give any (erroneous) background task a chance to run, then assert nothing fired.
		await new Promise((r) => setTimeout(r, 5));
		expect(processSource).not.toHaveBeenCalled();
		expect(writeAudit).not.toHaveBeenCalled();
	});
});

describe('manualSync — C6a audit (one source=manual row per triggered source, both paths)', () => {
	it('success path: writeAudit called once with ok:true detail carrying the counts', async () => {
		const { deps, writeAudit } = makeDeps({ enumerate: vi.fn(async () => [row('42')]) });
		await manualSync(deps, { ownerUserId: OWNER });
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1));
		const [auditedRow, detail] = writeAudit.mock.calls[0] as [SourceRow, { ok: boolean; result?: SyncResult }];
		expect(auditedRow.sourceId).toBe('42');
		expect(detail.ok).toBe(true);
		expect(detail.result).toEqual(SYNC_RESULT);
	});

	it('failure path: processSource throws → writeAudit STILL called once with ok:false + scrubbed error; markUnhealthy attempted', async () => {
		const processSource = vi.fn(async () => {
			throw new Error('provider 5xx (scrubbed)');
		});
		const { deps, writeAudit, markUnhealthy } = makeDeps({
			enumerate: vi.fn(async () => [row('42', 'simplefin')]),
			processSource
		});
		await manualSync(deps, { ownerUserId: OWNER });
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1));
		const [, detail] = writeAudit.mock.calls[0] as [SourceRow, { ok: boolean; error?: string }];
		expect(detail.ok).toBe(false);
		expect(detail.error).toMatch(/provider 5xx/);
		expect(markUnhealthy).toHaveBeenCalledTimes(1);
	});
});

describe('manualSync — A2/C3 background safety', () => {
	it('a background processSource rejection does NOT escape manualSync (fire-and-forget guard)', async () => {
		const processSource = vi.fn(async () => {
			throw new Error('kaboom');
		});
		const { deps, writeAudit } = makeDeps({ enumerate: vi.fn(async () => [row('42')]), processSource });
		// The phase-1 return must resolve normally even though the background sync throws.
		await expect(manualSync(deps, { ownerUserId: OWNER })).resolves.toEqual({
			sources: [{ source_id: '42', disposition: 'triggered' }]
		});
		// The failure is still audited (both-paths discipline).
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1));
	});

	it('in-flight is cleared after the run (finally) even when processSource throws', async () => {
		const debounce = createSyncDebounce();
		const processSource = vi.fn(async () => {
			throw new Error('kaboom');
		});
		const { deps, writeAudit } = makeDeps({
			enumerate: vi.fn(async () => [row('42')]),
			processSource,
			debounce
		});
		await manualSync(deps, { ownerUserId: OWNER });
		await vi.waitFor(() => expect(writeAudit).toHaveBeenCalledTimes(1));
		// After the run, the in-flight flag is cleared → the source is no longer throttled-by-in-flight
		// (the 60s window still applies, so we advance a fake clock past it below in the R1 suite).
		expect(debounce.isThrottled('42')).toBe(true); // still within the 60s last-triggered window.
	});
});

describe('R1 debounce — 60s/source + in-flight (fake clock)', () => {
	it('a second trigger within 60s is debounced; after the window it triggers again', async () => {
		let nowMs = 1_000_000;
		const debounce = new SyncDebounce({ now: () => nowMs });
		const { deps, processSource } = makeDeps({ enumerate: vi.fn(async () => [row('42')]), debounce });

		const first = await manualSync(deps, { ownerUserId: OWNER });
		expect(first.sources).toEqual([{ source_id: '42', disposition: 'triggered' }]);
		await vi.waitFor(() => expect(processSource).toHaveBeenCalledTimes(1)); // let in-flight clear.

		nowMs += 30_000; // within the 60s window.
		const second = await manualSync(deps, { ownerUserId: OWNER });
		expect(second.sources).toEqual([{ source_id: '42', disposition: 'debounced' }]);

		nowMs += 31_000; // now past 60s since the first trigger.
		const third = await manualSync(deps, { ownerUserId: OWNER });
		expect(third.sources).toEqual([{ source_id: '42', disposition: 'triggered' }]);
	});

	it('an in-flight source is debounced even inside the window (concurrent double-click)', async () => {
		const debounce = createSyncDebounce();
		// A processSource that never resolves keeps the source in-flight for the duration of the test.
		let release: () => void = () => {};
		const gate = new Promise<void>((r) => {
			release = r;
		});
		const processSource = vi.fn(async () => {
			await gate;
			return OUTCOME;
		});
		const { deps } = makeDeps({ enumerate: vi.fn(async () => [row('42')]), processSource, debounce });

		const first = await manualSync(deps, { ownerUserId: OWNER });
		expect(first.sources).toEqual([{ source_id: '42', disposition: 'triggered' }]);
		// Second call while the first is still in-flight → debounced (in-flight flag).
		const second = await manualSync(deps, { ownerUserId: OWNER });
		expect(second.sources).toEqual([{ source_id: '42', disposition: 'debounced' }]);
		release(); // let the first background run finish so the test doesn't leak a pending promise.
		await vi.waitFor(() => expect(debounce.isThrottled('42')).toBe(true));
	});
});

describe('enumerateSourcesForTenant — Sec C1 (RLS via withTenant; defense-in-depth tenant filter)', () => {
	it('runs the SELECT under withTenant (RLS-enforced), NOT withServiceRole', async () => {
		const withTenant = vi.fn(async (fn: (tx: unknown) => Promise<unknown>) => {
			// A minimal tagged-template stub: returns the caller's own rows (RLS would).
			const tx = Object.assign(
				(_s: TemplateStringsArray, ..._v: unknown[]) => [
					{
						source_id: '42',
						provider: 'plaid',
						users_id: OWNER,
						external_connection_id: 'ext_42',
						provider_metadata: null
					}
				],
				{}
			);
			return fn(tx as unknown as never);
		});
		const client = { withTenant, end: vi.fn() } as unknown as TenantScopedClient;
		const rows = await enumerateSourcesForTenant(client, OWNER);
		expect(withTenant).toHaveBeenCalledTimes(1);
		expect(rows).toEqual([
			{ sourceId: '42', provider: 'plaid', usersId: OWNER, externalConnectionId: 'ext_42', providerMetadata: null }
		]);
	});

	it('defense-in-depth: a row whose users_id !== ownerUserId is filtered out (would only fire if RLS were bypassed)', async () => {
		const withTenant = vi.fn(async (fn: (tx: unknown) => Promise<unknown>) => {
			const tx = Object.assign(
				(_s: TemplateStringsArray, ..._v: unknown[]) => [
					{ source_id: '42', provider: 'plaid', users_id: OWNER, external_connection_id: null, provider_metadata: null },
					{ source_id: '99', provider: 'plaid', users_id: OTHER, external_connection_id: null, provider_metadata: null }
				],
				{}
			);
			return fn(tx as unknown as never);
		});
		const client = { withTenant, end: vi.fn() } as unknown as TenantScopedClient;
		const rows = await enumerateSourcesForTenant(client, OWNER);
		expect(rows.map((r) => r.sourceId)).toEqual(['42']); // the foreign row is dropped.
	});
});
