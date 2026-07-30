// cursor.test.ts — OWD-A A3 (045) incremental-cursor persistence helpers.

import { describe, it, expect } from 'vitest';
import { readSyncCursor, writeSyncCursor, type ServiceRoleRunner } from '../src/ingest/cursor.js';
import type { Tx } from '../src/db/TenantBoundClient.js';

function fakeClient(result: unknown[]): { client: ServiceRoleRunner; queries: { sql: string; vals: unknown[] }[] } {
	const queries: { sql: string; vals: unknown[] }[] = [];
	const tx = ((strings: TemplateStringsArray, ...vals: unknown[]) => {
		queries.push({ sql: strings.join('?').replace(/\s+/g, ' ').trim(), vals });
		return Promise.resolve(result);
	}) as unknown as Tx;
	return { client: { withServiceRole: (fn) => fn(tx) }, queries };
}

describe('readSyncCursor', () => {
	it('returns the stored cursor, bound to source_id + users_id', async () => {
		const { client, queries } = fakeClient([{ sync_cursor: 'cur_42' }]);
		expect(await readSyncCursor(client, 42n, 'uid-A')).toBe('cur_42');
		expect(queries[0].sql).toContain('select sync_cursor');
		expect(queries[0].vals).toEqual([42, 'uid-A']); // bigint → Number; tenant fence
	});

	it('returns null for no row or a null cursor', async () => {
		expect(await readSyncCursor(fakeClient([]).client, 1n, 'x')).toBeNull();
		expect(await readSyncCursor(fakeClient([{ sync_cursor: null }]).client, 1n, 'x')).toBeNull();
	});
});

describe('writeSyncCursor', () => {
	it('advances the cursor, bound to source_id + users_id', async () => {
		const { client, queries } = fakeClient([]);
		await writeSyncCursor(client, 42n, 'uid-A', 'cur_next');
		expect(queries[0].sql).toContain('update pfin.linked_source set sync_cursor');
		expect(queries[0].vals).toEqual(['cur_next', 42, 'uid-A']);
	});

	it('is a no-op (no query) on null/undefined cursor', async () => {
		const { client, queries } = fakeClient([]);
		await writeSyncCursor(client, 1n, 'x', null);
		await writeSyncCursor(client, 1n, 'x', undefined);
		expect(queries).toHaveLength(0);
	});
});
