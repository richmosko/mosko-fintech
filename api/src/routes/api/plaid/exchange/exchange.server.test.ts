// exchange.server.test.ts — SELF-197 leg-2 handler integration tests.
//
// The headline SC3-C1 / C6-3 proof: an attacker body carrying `ownerUserId` is
// rejected by `.strict()` (400) and NEVER reaches the worker; when a legitimate body
// is exchanged, the ownerUserId the worker receives is the SESSION's, not anything the
// client could supply. Also covers unauthenticated → 401 and the failure mapping.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { POST } from './+server';
import { __resetConfigForTests } from '$lib/server/plaid/admissionClient';

// Node-global shim (api/ tsconfig omits @types/node from `types` — harness gap,
// flagged to DevOps; also affects tests/harness.smoke.test.ts). No runtime effect.
declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const ATTACKER_UID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

function makeEvent(body: unknown, user: { id: string } | null) {
	const request = new Request('http://localhost/api/plaid/exchange', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user })
	};
	// Cast through unknown — the handler only touches request + locals.safeGetSession.
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

beforeEach(() => {
	process.env.WORKER_ADMISSION_SHARED_SECRET = 'test-secret';
	process.env.WORKER_ADMISSION_URL = 'http://worker.test:8081';
	__resetConfigForTests();
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

it('unauthenticated request → 401, worker never called', async () => {
	const fetchMock = vi.fn();
	vi.stubGlobal('fetch', fetchMock);

	const res = await POST(makeEvent({ public_token: 'public-sandbox-abc' }, null));
	expect(res.status).toBe(401);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('SC3-C1: attacker-supplied ownerUserId in the body → 400, worker never called', async () => {
	const fetchMock = vi.fn();
	vi.stubGlobal('fetch', fetchMock);

	const res = await POST(
		makeEvent(
			{ public_token: 'public-sandbox-abc', ownerUserId: ATTACKER_UID },
			{ id: SESSION_UID }
		)
	);

	// `.strict()` rejects the extra `ownerUserId` key before any relay happens.
	expect(res.status).toBe(400);
	expect(await res.json()).toEqual({ error: 'invalid_request' });
	expect(fetchMock).not.toHaveBeenCalled();
});

it('legitimate exchange → worker receives the SESSION ownerUserId, not any client value', async () => {
	const fetchMock = vi.fn(
		async () =>
			new Response(
				JSON.stringify({
					sourceId: '42',
					accounts: [{ account_id: 'acct_1', name: 'Checking' }]
				}),
				{ status: 200, headers: { 'content-type': 'application/json' } }
			)
	);
	vi.stubGlobal('fetch', fetchMock);

	const res = await POST(makeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_UID }));

	expect(res.status).toBe(200);
	expect(await res.json()).toEqual({
		success: true,
		accounts: [{ account_id: 'acct_1', name: 'Checking' }]
	});

	// The value that reached the worker is the session uid — provably.
	const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
	const sent = JSON.parse(init.body as string);
	expect(sent.ownerUserId).toBe(SESSION_UID);
	expect(sent.ownerUserId).not.toBe(ATTACKER_UID);
});

it('worker 5xx → 500 generic envelope (no leak)', async () => {
	vi.stubGlobal(
		'fetch',
		vi.fn(
			async () =>
				new Response(JSON.stringify({ error: 'admission_failed' }), {
					status: 502,
					headers: { 'content-type': 'application/json' }
				})
		)
	);

	const res = await POST(makeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_UID }));
	expect(res.status).toBe(500);
	expect(await res.json()).toEqual({ error: 'exchange_failed' });
});

it('worker unreachable (transport failure) → 502', async () => {
	vi.stubGlobal(
		'fetch',
		vi.fn(async () => {
			throw new Error('ECONNREFUSED');
		})
	);
	const res = await POST(makeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_UID }));
	expect(res.status).toBe(502);
});
