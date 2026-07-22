// mfa.test.ts — unit coverage for the fail-CLOSED step-up decision + factor/status
// helpers (SELF-291 / Auth-3b Slice 1). Pure-TS server test (node env). Mocks the
// supabase-js auth.mfa surface.
//
// Proves the N3 fail-closed contract of requireStepUp: allow ONLY when there is no
// verified factor or the session is already aal2; block on aal2-available-but-aal1,
// on any error, on indeterminate (null) levels, and on a thrown chain.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { requireStepUp, getTotpFactors, getMfaStatus } from './mfa';

/** Build a supabase double whose auth.mfa methods return the given fixtures. */
function makeSupabase(opts: {
	aal?: { data: unknown; error: unknown };
	aalThrows?: boolean;
	factors?: { data: unknown; error: unknown };
	policy?: string | null;
}): SupabaseClient {
	const getAuthenticatorAssuranceLevel = opts.aalThrows
		? vi.fn(async () => {
				throw new Error('transport down');
			})
		: vi.fn(async () => opts.aal ?? { data: null, error: null });
	const listFactors = vi.fn(async () => opts.factors ?? { data: null, error: null });

	// getMfaPolicy reads .schema('pfin').from('user_settings').select().maybeSingle()
	const maybeSingle = vi.fn(async () => ({
		data: opts.policy === undefined ? null : { mfa_policy: opts.policy },
		error: null
	}));
	const select = vi.fn(() => ({ maybeSingle }));
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));

	return {
		auth: { mfa: { getAuthenticatorAssuranceLevel, listFactors } },
		schema
	} as unknown as SupabaseClient;
}

describe('requireStepUp (N3 fail-closed)', () => {
	it("ALLOWS a no-factor user (aal1/aal1)", async () => {
		const sb = makeSupabase({ aal: { data: { currentLevel: 'aal1', nextLevel: 'aal1' }, error: null } });
		await expect(requireStepUp(sb)).resolves.toBe('allow');
	});

	it('ALLOWS an already-stepped-up user (aal2/aal2)', async () => {
		const sb = makeSupabase({ aal: { data: { currentLevel: 'aal2', nextLevel: 'aal2' }, error: null } });
		await expect(requireStepUp(sb)).resolves.toBe('allow');
	});

	it('BLOCKS a verified-factor user who is not stepped up (aal1/next=aal2) — N2a', async () => {
		const sb = makeSupabase({ aal: { data: { currentLevel: 'aal1', nextLevel: 'aal2' }, error: null } });
		await expect(requireStepUp(sb)).resolves.toBe('step-up-required');
	});

	it('BLOCKS on a getAAL error (fail closed)', async () => {
		const sb = makeSupabase({ aal: { data: null, error: { message: 'boom' } } });
		await expect(requireStepUp(sb)).resolves.toBe('step-up-required');
	});

	it('BLOCKS on null/indeterminate levels (fail closed)', async () => {
		const sb = makeSupabase({ aal: { data: { currentLevel: null, nextLevel: null }, error: null } });
		await expect(requireStepUp(sb)).resolves.toBe('step-up-required');
	});

	it('BLOCKS when the chain throws (fail closed)', async () => {
		const sb = makeSupabase({ aalThrows: true });
		await expect(requireStepUp(sb)).resolves.toBe('step-up-required');
	});
});

describe('getTotpFactors', () => {
	it('partitions verified vs unverified totp factor ids', async () => {
		const sb = makeSupabase({
			factors: {
				data: {
					totp: [
						{ id: 'v1', status: 'verified' },
						{ id: 'u1', status: 'unverified' },
						{ id: 'v2', status: 'verified' }
					]
				},
				error: null
			}
		});
		await expect(getTotpFactors(sb)).resolves.toEqual({
			verifiedIds: ['v1', 'v2'],
			unverifiedIds: ['u1']
		});
	});

	it('returns empty arrays on a listFactors error (conservative)', async () => {
		const sb = makeSupabase({ factors: { data: null, error: { message: 'boom' } } });
		await expect(getTotpFactors(sb)).resolves.toEqual({ verifiedIds: [], unverifiedIds: [] });
	});
});

describe('getMfaStatus', () => {
	it('derives hasVerifiedTotp + levels + declared policy', async () => {
		const sb = makeSupabase({
			aal: { data: { currentLevel: 'aal2', nextLevel: 'aal2' }, error: null },
			factors: { data: { totp: [{ id: 'v1', status: 'verified' }] }, error: null },
			policy: 'totp'
		});
		await expect(getMfaStatus(sb)).resolves.toEqual({
			hasVerifiedTotp: true,
			verifiedTotpFactorIds: ['v1'],
			currentLevel: 'aal2',
			nextLevel: 'aal2',
			mfaPolicy: 'totp'
		});
	});

	it('collapses to MFA-off shape when nothing is enrolled', async () => {
		const sb = makeSupabase({
			aal: { data: { currentLevel: 'aal1', nextLevel: 'aal1' }, error: null },
			factors: { data: { totp: [] }, error: null },
			policy: null
		});
		await expect(getMfaStatus(sb)).resolves.toEqual({
			hasVerifiedTotp: false,
			verifiedTotpFactorIds: [],
			currentLevel: 'aal1',
			nextLevel: 'aal1',
			mfaPolicy: 'none'
		});
	});
});
