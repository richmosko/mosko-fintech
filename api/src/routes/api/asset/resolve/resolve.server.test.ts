// resolve.server.test.ts — SELF-325 /api/asset/resolve relay handler.
// Mocked session + stubbed worker fetch (mirrors reauth/start's start.server.test.ts shape).

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { POST } from './+server';
import { __resetConfigForTests } from '$lib/server/asset/admissionClient';

declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function makeEvent(body: unknown, user: { id: string } | null) {
	const request = new Request('http://localhost/api/asset/resolve', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }) };
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

function stubWorker(body: unknown, status = 200) {
	const fetchMock = vi.fn(
		async () => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
	);
	vi.stubGlobal('fetch', fetchMock);
	return fetchMock;
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

const VALID_BODY = { symbol: 'AAPL', cusip: null, asset_type: 'equity', name: 'Apple Inc' };

describe('POST /api/asset/resolve', () => {
	it('unauthenticated → 401, worker never called', async () => {
		const fetchMock = stubWorker({});
		const res = await POST(makeEvent(VALID_BODY, null));
		expect(res.status).toBe(401);
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('bad body (.strict / no identity) → 400, worker never called', async () => {
		const fetchMock = stubWorker({});
		expect((await POST(makeEvent({ ...VALID_BODY, extra: 1 }, { id: SESSION_UID }))).status).toBe(400);
		expect(
			(await POST(makeEvent({ symbol: null, cusip: null, asset_type: 'equity', name: null }, { id: SESSION_UID })))
				.status
		).toBe(400);
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('a personal-asset type → 400 with the routing message, worker never called (namespace-pollution boundary)', async () => {
		const fetchMock = stubWorker({});
		const res = await POST(makeEvent({ ...VALID_BODY, asset_type: 'real_estate' }, { id: SESSION_UID }));
		expect(res.status).toBe(400);
		const body = await res.json();
		expect(body.errors.asset_type[0]).toMatch(/recorded directly on the purchase form/);
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it('forwards the session ownerUserId + validated body (currency=USD, never a body value) to the worker', async () => {
		const fetchMock = stubWorker({ assetId: 501 });
		const res = await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ assetId: 501 });

		const [, init] = fetchMock.mock.calls[0] as unknown as [string, { body: string }];
		const sent = JSON.parse(init.body);
		expect(sent.ownerUserId).toBe(SESSION_UID);
		expect(sent.symbol).toBe('AAPL');
		expect(sent.currency).toBe('USD');
	});

	it('forwards a null assetId unchanged (SELF-200 unvalued parity)', async () => {
		stubWorker({ assetId: null });
		const res = await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ assetId: null });
	});

	it('a worker failure maps to the outcome status, no detail leak', async () => {
		stubWorker({ error: 'asset_resolve_failed' }, 502);
		const res = await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
		expect(res.status).toBe(500);
		expect(await res.json()).toEqual({ error: 'resolve_failed' });
	});
});
