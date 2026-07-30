// triggerSync.test.ts — SELF-206 AC5 on-demand incremental sync orchestration (worker side).
// All seams injected (no live Plaid/DB). Asserts: happy path maps counts + binds the tenant;
// a missing credential fails LOUD (never a silent no-op); the client is ALWAYS ended.

import { describe, it, expect, vi } from 'vitest';
import { syncLinkedSource, type SyncSourceDeps } from '../src/http/triggerSync.js';
import type { PollClient, SourceRow } from '../src/cli/poll.js';
import type { SyncResult } from '../src/ingest/mapper.js';

const OWNER = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const SYNC_RESULT: SyncResult = {
	holdingsLanded: 2,
	balancesLanded: 1,
	pricesUpserted: 2,
	transactionsInserted: 5,
	transactionsSkipped: 3,
	droppedTransactions: [],
	unresolvedAccounts: ['acct_unmapped']
};

function makeDeps(
	over: Partial<SyncSourceDeps> = {},
	adapterOver: Record<string, unknown> = {}
): { deps: SyncSourceDeps; end: ReturnType<typeof vi.fn>; writeCursor: ReturnType<typeof vi.fn> } {
	const end = vi.fn(async () => {});
	const client = { withServiceRole: vi.fn(), end } as unknown as PollClient;
	const writeCursor = vi.fn(async () => {});
	const deps: SyncSourceDeps = {
		clientFor: vi.fn(() => client),
		buildAdapter: vi.fn(() => ({
			fetchBalances: vi.fn(async () => []),
			fetchHoldings: vi.fn(async () => []),
			fetchTransactions: vi.fn(async () => []),
			getLastCursor: () => 'cursor-NEXT',
			...adapterOver
		})),
		resolveCredential: vi.fn(async () => 'access-SECRET-never-logged'),
		sync: vi.fn(async () => SYNC_RESULT),
		syncDate: '2026-07-29',
		readCursor: vi.fn(async () => 'cursor-PRIOR'),
		writeCursor,
		...over
	};
	return { deps, end, writeCursor };
}

describe('syncLinkedSource', () => {
	it('happy path: binds tenant, runs the shipped sync, maps non-sensitive counts; ends client', async () => {
		const { deps, end } = makeDeps();
		const result = await syncLinkedSource({ ownerUserId: OWNER, linkedSourceId: 42n }, deps);

		expect(result).toEqual({ sourceId: '42', inserted: 5, skipped: 3, unresolvedAccounts: 1 });
		expect(deps.clientFor).toHaveBeenCalledWith(OWNER);
		// resolveCredential double-binds source + tenant (the SourceRow it receives).
		const row = (deps.resolveCredential as unknown as { mock: { calls: unknown[][] } }).mock.calls[0][1] as SourceRow;
		expect(row.sourceId).toBe('42');
		expect(row.usersId).toBe(OWNER);
		expect(row.provider).toBe('plaid');
		expect(end).toHaveBeenCalledTimes(1);
	});

	it('missing credential → throws (fail-loud, never a silent no-op); client still ended', async () => {
		const { deps, end } = makeDeps({ resolveCredential: vi.fn(async () => null) });
		await expect(syncLinkedSource({ ownerUserId: OWNER, linkedSourceId: 7n }, deps)).rejects.toThrow(
			/no credential resolved/
		);
		expect(deps.sync).not.toHaveBeenCalled();
		expect(end).toHaveBeenCalledTimes(1);
	});

	it('A3: resumes from the stored cursor and advances it after a successful land', async () => {
		const { deps, writeCursor } = makeDeps();
		const fetchTransactions = vi.fn(async () => []);
		(deps.buildAdapter as unknown as { mockReturnValue: (v: unknown) => void }).mockReturnValue({
			fetchBalances: vi.fn(async () => []),
			fetchHoldings: vi.fn(async () => []),
			fetchTransactions,
			getLastCursor: () => 'cursor-NEXT'
		});
		await syncLinkedSource({ ownerUserId: OWNER, linkedSourceId: 42n }, deps);
		// read the stored cursor, pass it into the drain, persist the drained-to cursor.
		expect(deps.readCursor).toHaveBeenCalledWith(expect.anything(), 42n, OWNER);
		const sourceRef = fetchTransactions.mock.calls[0][0] as { cursor?: string | null };
		expect(sourceRef.cursor).toBe('cursor-PRIOR');
		expect(writeCursor).toHaveBeenCalledWith(expect.anything(), 42n, OWNER, 'cursor-NEXT');
	});

	it('A3: does NOT advance the cursor when the sync throws (land failed → no skip)', async () => {
		const { deps, writeCursor } = makeDeps({
			sync: vi.fn(async () => {
				throw new Error('landing failed');
			})
		});
		await expect(syncLinkedSource({ ownerUserId: OWNER, linkedSourceId: 9n }, deps)).rejects.toThrow();
		expect(writeCursor).not.toHaveBeenCalled();
	});

	it('ends the client even when the sync throws', async () => {
		const { deps, end } = makeDeps({
			sync: vi.fn(async () => {
				throw new Error('landing failed');
			})
		});
		await expect(syncLinkedSource({ ownerUserId: OWNER, linkedSourceId: 9n }, deps)).rejects.toThrow();
		expect(end).toHaveBeenCalledTimes(1);
	});
});
