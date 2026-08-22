// resolve.server.test.ts — SELF-325 /api/asset/resolve relay handler.
// Mocked session + stubbed worker fetch (mirrors reauth/start's start.server.test.ts shape).

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { POST } from './+server';
import { __resetConfigForTests } from '$lib/server/asset/admissionClient';
import { __resetRateLimitForTests } from '$lib/server/auth/rateLimit';

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
	__resetRateLimitForTests(); // SELF-325 Sec C2 — isolate the sliding window between cases.
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

	// ── Sec C1 (SELF-325 round 10, joint review) ─────────────────────────────────────────────
	// Catch criterion verbatim: "a server test asserting the worker payload carries name === null
	// regardless of the request body." A free-text `name` reaching the worker on a resolve MISS
	// becomes a GLOBAL row's permanent display name (no UPDATE grant exists — 020) — unrepairable
	// first-write squatting. `name` must never be threaded from the client.
	it('Sec C1 — the worker payload carries name === null regardless of what the request body sent', async () => {
		const fetchMock = stubWorker({ assetId: 501 });
		const res = await POST(makeEvent({ ...VALID_BODY, name: 'Totally Legit Company Inc' }, { id: SESSION_UID }));
		expect(res.status).toBe(200);

		const [, init] = fetchMock.mock.calls[0] as unknown as [string, { body: string }];
		const sent = JSON.parse(init.body);
		expect(sent.name).toBeNull();
	});

	it('Sec C1 — still null even when the body omits name entirely', async () => {
		const fetchMock = stubWorker({ assetId: 501 });
		const { name: _name, ...bodyWithoutName } = VALID_BODY;
		void _name;
		const res = await POST(makeEvent(bodyWithoutName, { id: SESSION_UID }));
		expect(res.status).toBe(200);

		const [, init] = fetchMock.mock.calls[0] as unknown as [string, { body: string }];
		expect(JSON.parse(init.body).name).toBeNull();
	});

	// ── Sec C2 (SELF-325 round 10, joint review) ─────────────────────────────────────────────
	// Catch criterion verbatim: "N resolves per user per window → 429, with a golden test
	// asserting the 429." RESOLVE_RULE in +server.ts is { max: 30, windowMs: 5 * 60 * 1000 }.
	describe('Sec C2 — rate limit (30 / 5min / user.id)', () => {
		it('the 31st resolve within the window 429s; the prior 30 succeed', async () => {
			stubWorker({ assetId: 501 });
			for (let i = 0; i < 30; i++) {
				const res = await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
				expect(res.status).toBe(200);
			}
			const limited = await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
			expect(limited.status).toBe(429);
			expect(await limited.json()).toEqual({ error: 'rate_limited' });
			expect(limited.headers.get('retry-after')).not.toBeNull();
		});

		it('the worker is never called on the limited (31st) request', async () => {
			const fetchMock = stubWorker({ assetId: 501 });
			for (let i = 0; i < 30; i++) await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
			fetchMock.mockClear();
			await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
			expect(fetchMock).not.toHaveBeenCalled();
		});

		it('the window is scoped per-user — a different user.id is unaffected by another user hitting the cap', async () => {
			stubWorker({ assetId: 501 });
			for (let i = 0; i < 30; i++) await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
			const otherUser = await POST(makeEvent(VALID_BODY, { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' }));
			expect(otherUser.status).toBe(200);
		});

		it('rate-limiting runs BEFORE body validation — a limited caller never reaches the Zod boundary', async () => {
			for (let i = 0; i < 30; i++) await POST(makeEvent(VALID_BODY, { id: SESSION_UID }));
			// A body that would otherwise 400 (extra field) — still 429, not 400, once limited.
			const res = await POST(makeEvent({ ...VALID_BODY, extra: 1 }, { id: SESSION_UID }));
			expect(res.status).toBe(429);
		});
	});
});
