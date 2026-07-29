// plaidLinkFlow.test.ts — unit tests for the SELF-198 relay-flow core against a MOCKED
// SELF-197 relay contract (no network, no DOM, no Plaid SDK).
//
// ⚠️ HARNESS NOTE: this `api/` project has no test runner wired yet (no vitest in
// devDependencies, no CI lane). This file is authored to the intended Vitest API so it's
// ready the moment QA/DevOps stand the harness up — it does NOT run today. Adding the
// runner is a QA test-posture + DevOps CI decision (F/CTO-gated npm install), not a
// unilateral Frontend change. Flagged in the SELF-198 deliverable.

import { describe, it, expect, vi } from 'vitest';
import {
	fetchLinkToken,
	exchangePublicToken,
	PlaidRelayError,
	type FetchLike
} from './plaidLinkFlow';

/** Build a fetch stub returning a given JSON body + status. */
function jsonFetch(body: unknown, status = 200): FetchLike {
	return vi.fn(async () =>
		new Response(JSON.stringify(body), {
			status,
			headers: { 'content-type': 'application/json' }
		})
	) as unknown as FetchLike;
}

describe('fetchLinkToken (leg 1)', () => {
	it('returns the validated link_token + expiration on 200', async () => {
		const fetchFn = jsonFetch({ link_token: 'link-sandbox-abc', expiration: '2026-07-19T12:00:00Z' });
		const out = await fetchLinkToken(fetchFn);
		expect(out.link_token).toBe('link-sandbox-abc');
		expect(out.expiration).toBe('2026-07-19T12:00:00Z');
	});

	it('throws a typed http error on non-2xx', async () => {
		const fetchFn = jsonFetch({ error: 'nope' }, 500);
		await expect(fetchLinkToken(fetchFn)).rejects.toMatchObject({
			name: 'PlaidRelayError',
			leg: 'link-token',
			kind: 'http',
			status: 500
		});
	});

	it('throws malformed when the body is missing link_token', async () => {
		const fetchFn = jsonFetch({ expiration: '2026-07-19T12:00:00Z' });
		await expect(fetchLinkToken(fetchFn)).rejects.toMatchObject({ leg: 'link-token', kind: 'malformed' });
	});

	it('throws network when fetch itself rejects', async () => {
		const fetchFn = (vi.fn(async () => {
			throw new TypeError('offline');
		}) as unknown) as FetchLike;
		await expect(fetchLinkToken(fetchFn)).rejects.toMatchObject({ leg: 'link-token', kind: 'network' });
	});
});

describe('exchangePublicToken (leg 2)', () => {
	it('sends ONLY { public_token, metadata } — no tenant id, no access_token (AC #5)', async () => {
		// Type the mock with the real `fetch` signature so `mock.calls[0]` is typed as
		// `[input, init?]` — lets us destructure the 2nd arg without an unsafe cast.
		const spy: FetchLike = vi.fn<FetchLike>(async () =>
			new Response(
				JSON.stringify({ success: true, linked_source_id: '1', accounts: [{ account_id: 'a1' }] }),
				{
					status: 200,
					headers: { 'content-type': 'application/json' }
				}
			)
		);
		await exchangePublicToken('public-sandbox-xyz', { institution: { name: 'Test Bank' } }, spy);

		const init = (spy as ReturnType<typeof vi.fn<FetchLike>>).mock.calls[0]?.[1];
		const sentBody = JSON.parse(String(init?.body ?? ''));
		expect(Object.keys(sentBody).sort()).toEqual(['metadata', 'public_token']);
		expect(sentBody.public_token).toBe('public-sandbox-xyz');
		// Hard guards: none of these may ever appear in the outgoing body.
		expect(sentBody).not.toHaveProperty('access_token');
		expect(sentBody).not.toHaveProperty('ownerUserId');
		expect(sentBody).not.toHaveProperty('users_id');
	});

	it('returns { success, linked_source_id, accounts } on 200', async () => {
		const fetchFn = jsonFetch({
			success: true,
			linked_source_id: '42',
			accounts: [{ account_id: 'a1', name: 'Checking' }]
		});
		const out = await exchangePublicToken('public-sandbox-xyz', undefined, fetchFn);
		expect(out.success).toBe(true);
		expect(out.linked_source_id).toBe('42');
		expect(out.accounts).toHaveLength(1);
		expect(out.accounts[0].account_id).toBe('a1');
	});

	it('rejects a success body missing linked_source_id (required numeric string)', async () => {
		const fetchFn = jsonFetch({ success: true, accounts: [{ account_id: 'a1' }] });
		await expect(
			exchangePublicToken('public-sandbox-xyz', undefined, fetchFn)
		).rejects.toMatchObject({ leg: 'exchange', kind: 'malformed' });
	});

	it('throws a typed http error on relay failure (drives retry)', async () => {
		const fetchFn = jsonFetch({ error: 'exchange failed' }, 502);
		await expect(exchangePublicToken('public-sandbox-xyz', undefined, fetchFn)).rejects.toBeInstanceOf(
			PlaidRelayError
		);
		await expect(exchangePublicToken('public-sandbox-xyz', undefined, fetchFn)).rejects.toMatchObject({
			leg: 'exchange',
			kind: 'http',
			status: 502
		});
	});

	it('throws malformed when success flag is absent', async () => {
		const fetchFn = jsonFetch({ accounts: [] });
		await expect(exchangePublicToken('public-sandbox-xyz', undefined, fetchFn)).rejects.toMatchObject({
			leg: 'exchange',
			kind: 'malformed'
		});
	});
});
