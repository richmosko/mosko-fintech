// connectionState.test.ts — SELF-207 connection-state reader + banner-count summarizer.
// Mocks the supabase chain (schema→from→select→order) like the sibling query-module tests.

import { describe, it, expect, vi } from 'vitest';
import {
	loadConnectionStates,
	summarizeHealth,
	loadConnectionHealth,
	loadConnectionState,
	loadAccountsBySource,
	loadAccountsForSource,
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

/** Mock a `.schema().from().select().eq().maybeSingle()` chain (targeted single-row read). */
function makeSingleSupabase(result: { data?: unknown; error?: unknown }) {
	const maybeSingle = vi.fn(async () => result);
	const eq = vi.fn(() => ({ maybeSingle }));
	const select = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	return { supabase: { schema } as unknown as SupabaseClient, eq, from };
}

describe('loadConnectionState', () => {
	it('reads ONE connection by source_id and maps linked_source_id → source_id', async () => {
		const { supabase, eq } = makeSingleSupabase({ data: VIEW_ROW, error: null });
		const state = await loadConnectionState(supabase, '42');
		expect(eq).toHaveBeenCalledWith('linked_source_id', '42');
		expect(state).toEqual({
			source_id: '42',
			provider: 'plaid',
			institution_name: 'Chase',
			is_active: true,
			connection_status: 'login_required',
			status_class: 'login_required',
			last_successful_sync_at: '2026-07-20T10:00:00Z'
		});
	});

	it('non-owner / nonexistent source → null (no row, RLS-filtered → 404 upstream)', async () => {
		const { supabase } = makeSingleSupabase({ data: null, error: null });
		expect(await loadConnectionState(supabase, '999')).toBeNull();
	});

	it('fail-soft: read error → null', async () => {
		const { supabase } = makeSingleSupabase({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		expect(await loadConnectionState(supabase, '42')).toBeNull();
		spy.mockRestore();
	});
});

// ⚠ ACCT models a pfin.ACCOUNT row → `closed_at` (ADR-042 / 059). The `conn()` factory above
// models a linked_source row and KEEPS its `is_active` — a different, preserved column. Both
// live in this one file, which is why the fixtures name their table.
const ACCT = (over: Record<string, unknown> = {}) => ({
	account_id: 1,
	name: 'Checking',
	account_type: 'depository',
	closed_at: null,
	linked_source_id: 42,
	...over
});
const CLOSED_AT = '2026-06-03T10:00:00Z';

describe('loadAccountsBySource', () => {
	/** Mock a `.schema().from().select().not().order()` chain. */
	function makeMulti(result: { data?: unknown; error?: unknown }) {
		const order = vi.fn(async () => result);
		const not = vi.fn(() => ({ order }));
		const select = vi.fn(() => ({ not }));
		const from = vi.fn(() => ({ select }));
		const schema = vi.fn(() => ({ from }));
		return { supabase: { schema } as unknown as SupabaseClient, not };
	}

	it('groups linked accounts by source_id (numeric-string key); excludes NULL defensively', async () => {
		const { supabase, not } = makeMulti({
			data: [
				ACCT({ account_id: 1, linked_source_id: 42 }),
				ACCT({ account_id: 2, closed_at: CLOSED_AT, linked_source_id: 42 }),
				ACCT({ account_id: 3, linked_source_id: 7 }),
				ACCT({ account_id: 4, linked_source_id: null }) // defensive guard
			],
			error: null
		});
		const { accountsBySource, error } = await loadAccountsBySource(supabase);
		expect(not).toHaveBeenCalledWith('linked_source_id', 'is', null);
		expect(error).toBe(false);
		expect(accountsBySource.get('42')).toEqual([
			{ account_id: 1, name: 'Checking', account_type: 'depository', closed_at: null },
			{ account_id: 2, name: 'Checking', account_type: 'depository', closed_at: CLOSED_AT }
		]);
		expect(accountsBySource.get('7')).toHaveLength(1);
		expect(accountsBySource.has('null')).toBe(false);
	});

	it('fail-soft: read error → { empty map, error:true }', async () => {
		const { supabase } = makeMulti({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { accountsBySource, error } = await loadAccountsBySource(supabase);
		expect(accountsBySource.size).toBe(0);
		expect(error).toBe(true);
		spy.mockRestore();
	});
});

describe('loadAccountsForSource', () => {
	/** Mock a `.schema().from().select().eq().order()` chain. */
	function makeForSource(result: { data?: unknown; error?: unknown }) {
		const order = vi.fn(async () => result);
		const eq = vi.fn(() => ({ order }));
		const select = vi.fn(() => ({ eq }));
		const from = vi.fn(() => ({ select }));
		const schema = vi.fn(() => ({ from }));
		return { supabase: { schema } as unknown as SupabaseClient, eq };
	}

	it('returns this connection\'s accounts (OPEN AND CLOSED — management view)', async () => {
		const { supabase, eq } = makeForSource({
			data: [ACCT({ account_id: 1 }), ACCT({ account_id: 2, closed_at: CLOSED_AT })],
			error: null
		});
		const accounts = await loadAccountsForSource(supabase, '42');
		expect(eq).toHaveBeenCalledWith('linked_source_id', '42');
		// No closure filter is applied: a connections surface is a MANAGEMENT view, so a closed
		// account must still appear (as closed). The DATE is carried through rather than
		// collapsed to a boolean — that is the shape change, not a rename.
		expect(accounts).toEqual([
			{ account_id: 1, name: 'Checking', account_type: 'depository', closed_at: null },
			{ account_id: 2, name: 'Checking', account_type: 'depository', closed_at: CLOSED_AT }
		]);
	});

	it('fail-soft: read error → []', async () => {
		const { supabase } = makeForSource({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		expect(await loadAccountsForSource(supabase, '42')).toEqual([]);
		spy.mockRestore();
	});
});
