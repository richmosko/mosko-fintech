// connectionState.test.ts — SELF-207 connection-state reader + banner-count summarizer.
// Mocks the supabase chain (schema→from→select→order) like the sibling query-module tests.

import { describe, it, expect, vi } from 'vitest';
import {
	loadConnectionStates,
	summarizeHealth,
	loadConnectionHealth,
	type ConnectionState
} from './connectionState';
import type { SupabaseClient } from '@supabase/supabase-js';

/** Mock a supabase client whose `.schema().from().select().order()` resolves to `result`. */
function makeSupabase(result: { data?: unknown; error?: unknown }) {
	const order = vi.fn(async () => result);
	const select = vi.fn(() => ({ order }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	return { supabase: { schema } as unknown as SupabaseClient, order, select, from, schema };
}

const VIEW_ROW = {
	linked_source_id: 42,
	provider: 'plaid',
	institution_name: 'Chase',
	is_active: true,
	connection_status: 'login_required',
	status_class: 'login_required',
	last_successful_sync_at: '2026-07-20T10:00:00Z'
};

function conn(over: Partial<ConnectionState> = {}): ConnectionState {
	return {
		source_id: '1',
		provider: 'plaid',
		institution_name: 'Bank',
		is_active: true,
		connection_status: 'healthy',
		status_class: 'healthy',
		last_successful_sync_at: null,
		...over
	};
}

describe('loadConnectionStates', () => {
	it('reads the 043 view and maps linked_source_id → source_id (numeric string)', async () => {
		const { supabase, schema, from } = makeSupabase({ data: [VIEW_ROW], error: null });
		const { connections, error } = await loadConnectionStates(supabase);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('linked_source_connection_state');
		expect(error).toBe(false);
		expect(connections).toEqual([
			{
				source_id: '42', // bigint 42 → "42"
				provider: 'plaid',
				institution_name: 'Chase',
				is_active: true,
				connection_status: 'login_required',
				status_class: 'login_required',
				last_successful_sync_at: '2026-07-20T10:00:00Z'
			}
		]);
	});

	it('fail-soft: read error → { connections: [], error: true }', async () => {
		const { supabase } = makeSupabase({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const res = await loadConnectionStates(supabase);
		expect(res).toEqual({ connections: [], error: true });
		spy.mockRestore();
	});

	it('empty result → { connections: [], error: false } (true-empty, not a failure)', async () => {
		const { supabase } = makeSupabase({ data: [], error: null });
		expect(await loadConnectionStates(supabase)).toEqual({ connections: [], error: false });
	});
});

describe('summarizeHealth', () => {
	it('counts active reauth-needed + institution-down separately; institution_down is NOT reauth', () => {
		const health = summarizeHealth([
			conn({ connection_status: 'login_required' }),
			conn({ connection_status: 'revoked' }),
			conn({ connection_status: 'disconnected' }),
			conn({ connection_status: 'institution_down' }),
			conn({ connection_status: 'healthy' })
		]);
		expect(health).toEqual({ reauthCount: 3, institutionDownCount: 1 });
	});

	it('excludes INACTIVE connections from both counts (retired source = sync-paused, no nag)', () => {
		const health = summarizeHealth([
			conn({ connection_status: 'login_required', is_active: false }),
			conn({ connection_status: 'institution_down', is_active: false }),
			conn({ connection_status: 'revoked', is_active: true })
		]);
		expect(health).toEqual({ reauthCount: 1, institutionDownCount: 0 });
	});

	it('all-healthy → zero footprint', () => {
		expect(summarizeHealth([conn(), conn()])).toEqual({ reauthCount: 0, institutionDownCount: 0 });
	});
});

describe('loadConnectionHealth', () => {
	it('reads + summarizes for the layout', async () => {
		const { supabase } = makeSupabase({
			data: [VIEW_ROW, { ...VIEW_ROW, linked_source_id: 43, connection_status: 'institution_down' }],
			error: null
		});
		expect(await loadConnectionHealth(supabase)).toEqual({ reauthCount: 1, institutionDownCount: 1 });
	});

	it('fail-soft-to-zero on a read error', async () => {
		const { supabase } = makeSupabase({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		expect(await loadConnectionHealth(supabase)).toEqual({ reauthCount: 0, institutionDownCount: 0 });
		spy.mockRestore();
	});
});
