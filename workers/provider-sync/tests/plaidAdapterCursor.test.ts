// plaidAdapterCursor.test.ts — OWD-A A3 (045): PlaidAdapter resumes /transactions/sync from the
// stored cursor + exposes the drained-to cursor via getLastCursor().

import { describe, it, expect } from 'vitest';
import { PlaidAdapter, type PlaidClientLike } from '../src/adapters/PlaidAdapter.js';

describe('PlaidAdapter cursor (OWD-A A3)', () => {
	it('resumes from source.cursor and exposes the drained-to next_cursor', async () => {
		const seenCursors: (string | undefined)[] = [];
		const client = {
			transactionsSync: async (req: { cursor?: string }) => {
				seenCursors.push(req.cursor);
				return { data: { added: [], modified: [], removed: [], next_cursor: 'cur_NEW', has_more: false } };
			},
			investmentsTransactionsGet: async () => ({
				data: { investment_transactions: [], securities: [], total_investment_transactions: 0 }
			})
		} as unknown as PlaidClientLike;

		const adapter = new PlaidAdapter(client);
		await adapter.fetchTransactions(
			{ sourceId: 1n, accessToken: 'access-x', syncDate: '2026-07-15', cursor: 'cur_PRIOR' },
			{ start: '2026-01-01', end: '2026-07-15' }
		);
		expect(seenCursors[0]).toBe('cur_PRIOR'); // resumed incrementally from the stored cursor
		expect(adapter.getLastCursor()).toBe('cur_NEW'); // watermark the caller persists on success
	});

	it('getLastCursor() defaults to null before any fetch', () => {
		const adapter = new PlaidAdapter({} as unknown as PlaidClientLike);
		expect(adapter.getLastCursor()).toBeNull();
	});
});
