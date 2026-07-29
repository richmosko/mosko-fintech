// complete.server.test.ts — SELF-207 reauth Phase-2 relay handler.
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
	const request = new Request('http://localhost/api/reauth/complete', {
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
	expect((await POST(makeEvent({ linked_source_id: '42' }, null, 'plaid'))).status).toBe(401);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('source not owned → 404', async () => {
	const fetchMock = stubWorker({});
	expect((await POST(makeEvent({ linked_source_id: '999' }, { id: SESSION_UID }, null))).status).toBe(404);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('plaid → builds link_update_success input (no token), returns healthy/rotated:false', async () => {
	const fetchMock = stubWorker({ connectionStatus: 'healthy', rotated: false });
	const res = await POST(makeEvent({ linked_source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(200);
	expect(await res.json()).toEqual({ connection_status: 'healthy', rotated: false });
	const sent = JSON.parse((fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1].body as string);
	expect(sent).toEqual({
		provider: 'plaid',
		linked_source_id: '42',
		ownerUserId: SESSION_UID,
		input: { kind: 'link_update_success' }
	});
});

it('simplefin WITHOUT setup_token → 400, worker never called', async () => {
	const fetchMock = stubWorker({});
	const res = await POST(makeEvent({ linked_source_id: '77' }, { id: SESSION_UID }, 'simplefin'));
	expect(res.status).toBe(400);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('simplefin WITH setup_token → forwards setup_token input; returns rotated:true', async () => {
	const fetchMock = stubWorker({ connectionStatus: 'healthy', rotated: true });
	const res = await POST(makeEvent({ linked_source_id: '77', setup_token: 'tok-abc' }, { id: SESSION_UID }, 'simplefin'));
	expect(res.status).toBe(200);
	expect(await res.json()).toEqual({ connection_status: 'healthy', rotated: true });
	const sent = JSON.parse((fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1].body as string);
	expect(sent.input).toEqual({ kind: 'setup_token', setup_token: 'tok-abc' });
});

it('bad body (extra key) → 400', async () => {
	stubWorker({});
	expect((await POST(makeEvent({ linked_source_id: '42', nope: 1 }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
});

it('worker 5xx → 500 reauth_failed', async () => {
	stubWorker({ error: 'reauth_failed' }, 502);
	const res = await POST(makeEvent({ linked_source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(500);
	expect(await res.json()).toEqual({ error: 'reauth_failed' });
});
