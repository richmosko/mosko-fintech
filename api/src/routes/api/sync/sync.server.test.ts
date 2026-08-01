// sync.server.test.ts — SELF-317 manual "Sync now" relay handler (POST /api/sync).
// Mocked session + mocked supabase (provider resolution) + stubbed worker fetch.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { POST } from './+server';
import { __resetConfigForTests } from '$lib/server/sync/syncClient';

declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function supabaseWithProvider(provider: string | null) {
	const maybeSingle = async () => ({ data: provider === null ? null : { provider }, error: null });
	return { schema: () => ({ from: () => ({ select: () => ({ eq: () => ({ maybeSingle }) }) }) }) };
}

function makeEvent(body: unknown, user: { id: string } | null, provider: string | null) {
	const request = new Request('http://localhost/api/sync', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase: supabaseWithProvider(provider) };
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

function stubWorker(body: unknown, status = 202) {
	const fetchMock = vi.fn(
		async () => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
	);
	vi.stubGlobal('fetch', fetchMock);
	return fetchMock;
}

const TRIGGERED = { accepted: true, sources: [{ source_id: '42', disposition: 'triggered' }] };

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
	const fetchMock = stubWorker(TRIGGERED);
	const res = await POST(makeEvent({ source_id: '42' }, null, 'plaid'));
	expect(res.status).toBe(401);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('bad body (.strict / non-digit source_id / extra key) → 400, worker never called', async () => {
	const fetchMock = stubWorker(TRIGGERED);
	expect((await POST(makeEvent({ source_id: 'abc' }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
	expect((await POST(makeEvent({ source_id: '42', extra: 1 }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
	expect((await POST(makeEvent({ users_id: 'x' }, { id: SESSION_UID }, 'plaid'))).status).toBe(400);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('per-source spoof gate: foreign/nonexistent source_id (provider resolves null) → 404, worker never called', async () => {
	const fetchMock = stubWorker(TRIGGERED);
	const res = await POST(makeEvent({ source_id: '999' }, { id: SESSION_UID }, null));
	expect(res.status).toBe(404);
	expect(fetchMock).not.toHaveBeenCalled();
});

it('per-source: owned source → 202; forwards session ownerUserId + source_id, NOT the body', async () => {
	const fetchMock = stubWorker(TRIGGERED);
	const res = await POST(makeEvent({ source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(202);
	expect(await res.json()).toEqual({ status: 'accepted', sources: [{ source_id: '42', disposition: 'triggered' }] });
	const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
	expect(url).toBe('http://worker.test:8081/admission/manual-sync');
	const sent = JSON.parse(init.body as string);
	expect(sent).toEqual({ ownerUserId: SESSION_UID, source_id: '42' });
});

it('sync-all: source_id absent → skips provider resolve; relays ownerUserId only (no source_id)', async () => {
	const fetchMock = stubWorker({
		accepted: true,
		sources: [
			{ source_id: '42', disposition: 'triggered' },
			{ source_id: '77', disposition: 'debounced' }
		]
	});
	// provider resolver returns null, but sync-all must NOT 404 on it (it never calls the resolver).
	const res = await POST(makeEvent({}, { id: SESSION_UID }, null));
	expect(res.status).toBe(202);
	const sent = JSON.parse((fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1].body as string);
	expect(sent).toEqual({ ownerUserId: SESSION_UID });
	expect(await res.json()).toEqual({
		status: 'accepted',
		sources: [
			{ source_id: '42', disposition: 'triggered' },
			{ source_id: '77', disposition: 'debounced' }
		]
	});
});

it('worker 5xx → 502 sync_failed', async () => {
	stubWorker({ error: 'manual_sync_failed' }, 502);
	const res = await POST(makeEvent({ source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(502);
	expect(await res.json()).toEqual({ error: 'sync_failed' });
});

it('worker unreachable (transport failure) → 502 sync_failed', async () => {
	const fetchMock = vi.fn(async () => {
		throw new Error('ECONNREFUSED');
	});
	vi.stubGlobal('fetch', fetchMock);
	const res = await POST(makeEvent({ source_id: '42' }, { id: SESSION_UID }, 'plaid'));
	expect(res.status).toBe(502);
	expect(await res.json()).toEqual({ error: 'sync_failed' });
});
