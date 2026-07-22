// userSettings.test.ts — unit coverage for the pfin.user_settings helpers (SELF-286).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').from('user_settings').upsert(payload, opts)   → { error }
//   .schema('pfin').from('user_settings').select('mfa_policy').maybeSingle() → { data, error }
//
// Proves: ensureUserSettings issues the idempotent RLS-scoped upsert with the right
// args + is FAIL-SOFT (never throws) on a returned error AND on a thrown chain;
// getMfaPolicy returns the stored policy and falls back to 'none' on missing/error.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { ensureUserSettings, getMfaPolicy, setMfaPolicy } from './userSettings';

const USER_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/** update-path stub: .schema().from().update().eq() → { error }. */
function makeUpdateSupabase(error: { message: string } | null = null) {
	const eq = vi.fn(async () => ({ error }));
	const update = vi.fn(() => ({ eq }));
	const from = vi.fn(() => ({ update }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, eq, update, from, schema };
}

/** upsert-path stub: .schema().from().upsert() → { error }. */
function makeUpsertSupabase(error: { message: string } | null = null) {
	const upsert = vi.fn(async () => ({ error }));
	const from = vi.fn(() => ({ upsert }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, upsert, from, schema };
}

/** read-path stub: .schema().from().select().maybeSingle() → { data, error }. */
function makeReadSupabase(data: unknown, error: { message: string } | null = null) {
	const maybeSingle = vi.fn(async () => ({ data, error }));
	const select = vi.fn(() => ({ maybeSingle }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, maybeSingle, select, from, schema };
}

describe('ensureUserSettings', () => {
	it('issues the idempotent RLS-scoped upsert with the right args', async () => {
		const { client, upsert, schema, from } = makeUpsertSupabase();
		await ensureUserSettings(client, USER_ID);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('user_settings');
		expect(upsert).toHaveBeenCalledWith(
			{ users_id: USER_ID },
			{ onConflict: 'users_id', ignoreDuplicates: true }
		);
	});

	it('is fail-soft on a returned error (logs, does not throw)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeUpsertSupabase({ message: 'rls denied' });
		await expect(ensureUserSettings(client, USER_ID)).resolves.toBeUndefined();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('is fail-soft when the chain itself throws (never blocks login)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(ensureUserSettings(client, USER_ID)).resolves.toBeUndefined();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});

describe('getMfaPolicy', () => {
	it('returns the stored policy', async () => {
		const { client, schema, from } = makeReadSupabase({ mfa_policy: 'totp' });
		await expect(getMfaPolicy(client)).resolves.toBe('totp');
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('user_settings');
	});

	it('returns passkey when stored', async () => {
		const { client } = makeReadSupabase({ mfa_policy: 'passkey' });
		await expect(getMfaPolicy(client)).resolves.toBe('passkey');
	});

	it('missing row (never provisioned) → none', async () => {
		const { client } = makeReadSupabase(null);
		await expect(getMfaPolicy(client)).resolves.toBe('none');
	});

	it('read error → none (fail-soft, logs)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeReadSupabase(null, { message: 'boom' });
		await expect(getMfaPolicy(client)).resolves.toBe('none');
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('thrown chain → none (fail-soft)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(getMfaPolicy(client)).resolves.toBe('none');
		errSpy.mockRestore();
	});
});

describe('setMfaPolicy (N1 separate-write)', () => {
	it("UPDATEs only mfa_policy, RLS-scoped to the caller's own row", async () => {
		const { client, schema, from, update, eq } = makeUpdateSupabase();
		await expect(setMfaPolicy(client, USER_ID, 'totp')).resolves.toBe(true);
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('user_settings');
		expect(update).toHaveBeenCalledWith({ mfa_policy: 'totp' });
		expect(eq).toHaveBeenCalledWith('users_id', USER_ID);
	});

	it('returns false (logs) on a returned error — e.g. the MB-1 aal1 downgrade 42501', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client } = makeUpdateSupabase({ message: 'insufficient_privilege' });
		await expect(setMfaPolicy(client, USER_ID, 'none')).resolves.toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('returns false when the chain throws', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(setMfaPolicy(client, USER_ID, 'none')).resolves.toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});
