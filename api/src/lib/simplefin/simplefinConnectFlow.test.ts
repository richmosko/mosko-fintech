// simplefinConnectFlow.test.ts — unit tests for the OQ-2 SimpleFIN connect relay-flow
// core against a MOCKED relay (no network, no DOM). Mirrors plaidLinkFlow.test.ts.

import { describe, it, expect, vi } from 'vitest';
import { submitSetupToken, SimplefinRelayError, type FetchLike } from './simplefinConnectFlow';

/** Build a fetch stub returning a given JSON body + status. */
function jsonFetch(body: unknown, status = 200): FetchLike {
	return vi.fn(async () =>
		new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' }
		})
	) as unknown as FetchLike;
}

describe('submitSetupToken (leg-S)', () => {
	it('sends ONLY { setup_token } — no tenant id, no institutionName when blank (mass-assignment fence)', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ success: true, accounts: [{ account_id: 'a1' }] }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await submitSetupToken('setup-token-abc', undefined, spy);

		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody)).toEqual(['setup_token']);
		expect(sentBody.setup_token).toBe('setup-token-abc');
		// Hard guards: none of these may ever appear in the outgoing body.
		expect(sentBody).not.toHaveProperty('ownerUserId');
		expect(sentBody).not.toHaveProperty('access_url');
		expect(sentBody).not.toHaveProperty('users_id');
	});

	it('includes institutionName only when provided', async () => {
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(JSON.stringify({ success: true, accounts: [] }), {
				status: 200,
				headers: { 'content-type': 'application/json' }
			})
		);
		await submitSetupToken('setup-token-abc', 'Capital One', spy);
		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody).sort()).toEqual(['institutionName', 'setup_token']);
		expect(sentBody.institutionName).toBe('Capital One');
	});

	it('returns { success, accounts } on 200', async () => {
		const fetchFn = jsonFetch({
			success: true,
			accounts: [{ account_id: 'a1', name: 'Checking', type: 'unknown' }]
		});
		const out = await submitSetupToken('setup-token-abc', undefined, fetchFn);
		expect(out.success).toBe(true);
		expect(out.accounts).toHaveLength(1);
		expect(out.accounts[0].account_id).toBe('a1');
	});

	it('classifies 400 as invalid-token (burned/invalid → re-enter)', async () => {
		const fetchFn = jsonFetch({ error: 'connect_failed' }, 400);
		await expect(submitSetupToken('setup-token-abc', undefined, fetchFn)).rejects.toMatchObject({
			name: 'SimplefinRelayError',
			failure: 'invalid-token',
			status: 400
		});
	});

	it('classifies 401 as unauthenticated (→ re-auth)', async () => {
		const fetchFn = jsonFetch({ error: 'unauthenticated' }, 401);
		await expect(submitSetupToken('setup-token-abc', undefined, fetchFn)).rejects.toMatchObject({
			failure: 'unauthenticated',
			status: 401
		});
	});

	it('classifies 500 and 502 as unavailable (→ retry later)', async () => {
		await expect(
			submitSetupToken('t', undefined, jsonFetch({ error: 'connect_failed' }, 500))
		).rejects.toMatchObject({ failure: 'unavailable', status: 500 });
		await expect(
			submitSetupToken('t', undefined, jsonFetch({ error: 'connect_failed' }, 502))
		).rejects.toMatchObject({ failure: 'unavailable', status: 502 });
	});

	it('throws unavailable when fetch itself rejects (network/offline)', async () => {
		const fetchFn = (vi.fn(async () => {
			throw new TypeError('offline');
		}) as unknown) as FetchLike;
		await expect(submitSetupToken('setup-token-abc', undefined, fetchFn)).rejects.toBeInstanceOf(
			SimplefinRelayError
		);
		await expect(submitSetupToken('setup-token-abc', undefined, fetchFn)).rejects.toMatchObject({
			failure: 'unavailable'
		});
	});

	it('throws unavailable when the 200 body is malformed (no success flag)', async () => {
		const fetchFn = jsonFetch({ accounts: [] });
		await expect(submitSetupToken('setup-token-abc', undefined, fetchFn)).rejects.toMatchObject({
			failure: 'unavailable'
		});
	});
});
