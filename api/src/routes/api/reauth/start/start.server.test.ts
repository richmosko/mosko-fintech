// start.server.test.ts — SELF-207 reauth Phase-1 relay handler.
// Mocked session + mocked supabase (provider resolution) + stubbed worker fetch.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { POST } from './+server';
import { __resetConfigForTests } from '$lib/server/reauth/admissionClient';

declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function supabaseWithProvider(provider: string | null) {
	const maybeSingle = async () => ({ data: provider === null ? null : { provider }, error: null });
	return { schema: () => ({ from: () => ({ select: () => ({ eq: () => ({ maybeSingle }) }) }) }) };
}

function makeEvent(body: unknown, user: { id: string } | null, provider: string | null) {
	const request = new Request('http://localhost/api/reauth/start', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase: supabaseWithProvider(provider) };
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

it('unauthenticated → 401, worker never called', async () => {
	const fetchMock = stubWorker({});
	const res = await POST(makeEvent({ linked_source_id: '42' }, null, 'plaid'));
	expect(res.status).toBe(401);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('bad body (.strict / non-digit id) → 400', async () => {
	const fetchMock = stubWorker({});
	expect((await POST(makeEvent({ linked_source_id: 'abc' }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
	expect((await POST(makeEvent({ linked_source_id: '42', extra: 1 }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('source not owned / nonexistent (provider resolves null) → 404, worker never called', async () => {
	const fetchMock = stubWorker({});
	const res = await POST(makeEvent({ linked_source_id: '999' }, { id: SESSION_UID }, null));
	expect(res.status).toBe(404);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('plaid → forwards session ownerUserId + resolved provider; returns link_update with snake link_token', async () => {
	const fetchMock = stubWorker({ kind: 'link_update', linkToken: 'lt-1' });
	const res = await POST(makeEvent({ linked_source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(200);
	expect(await res.json()).toEqual({ kind: 'link_update', link_token: 'lt-1' });
	const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
	const sent = JSON.parse(init.body as string);
	expect(sent).toEqual({ provider: 'plaid', linked_source_id: '42', ownerUserId: SESSION_UID });
});

it('simplefin → returns recollect_credential', async () => {
	stubWorker({ kind: 'recollect_credential' });
	const res = await POST(makeEvent({ linked_source_id: '77' }, { id: SESSION_UID }, 'simplefin'));
	expect(res.status).toBe(200);
	expect(await res.json()).toEqual({ kind: 'recollect_credential' });
});

it('worker 5xx → 500 reauth_failed', async () => {
	stubWorker({ error: 'reauth_failed' }, 502);
	const res = await POST(makeEvent({ linked_source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(500);
	expect(await res.json()).toEqual({ error: 'reauth_failed' });
});
