// manualSyncRelayTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (SELF-317 "Sync now").
//
// SCOPE (QA, NOT a duplicate of src/routes/api/sync/sync.server.test.ts): the api/src RELAY half of
// the two-tenant spoof-proof. Backend's handler test uses ONE session + a single provider stub;
// this drives the REAL POST /api/sync handler over the REAL requestManualSync TRANSPORT (real
// fetch) against a REAL ephemeral node:http "worker" that RECORDS every inbound body — for TWO
// tenants, with an attacker body. It proves the two load-bearing app-layer properties of the §1c
// chain:
//   • Sec #1 layer 2 (the spoof gate): tenant A asking for tenant B's REAL source_id resolves the
//     provider under A's OWN RLS (locals.supabase) → null → 404 BEFORE any worker call. The worker
//     is NEVER hit (recorded calls == 0). Non-vacuous: A's OWN source resolves → 202 + one worker
//     call. Same handler, opposite outcome — the 404 is spoof-rejection, not a blanket deny.
//   • C6-3 / SC3-C1 (session-tenant-never-body): whatever the browser sends, the ownerUserId that
//     reaches the worker is ALWAYS the session's — never a browser-body value. A body attempting to
//     smuggle ownerUserId/users_id is rejected by Zod `.strict()` (400) and never reaches the wire.
//
// The recording worker stands in for the worker ONLY to capture what the relay transmits; the
// worker's own tenant trust boundary (RLS-scoped enumeration + credential double-bind) is the
// sibling test's job — workers/provider-sync/tests/manualSyncTwoTenant.qa.test.ts. Together they
// are the end-to-end two-tenant fence, each half tested at its right level.
//
// Grounding: docs/SECURITY §4.5 · temp/sync-now-design.md §1c (5-layer chain) / §7 · ADR-037.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createServer, type Server, type IncomingMessage } from 'node:http';
import type { AddressInfo } from 'node:net';
import { POST } from '../src/routes/api/sync/+server';
import { __resetConfigForTests } from '../src/lib/server/sync/syncClient';

declare const process: { env: Record<string, string | undefined> };

const SESSION_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const SESSION_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const A_SRC = '42'; // A owns this (plaid).
const B_SRC = '500'; // B owns this (simplefin) — the id an attacker who knows it would supply.

interface Recorded {
	path: string;
	authHeader: string | undefined;
	body: Record<string, unknown>;
}

// A real ephemeral worker: records each inbound body, replies with the 202 contract shape.
function startRecordingWorker(): Promise<{ server: Server; url: string; calls: Recorded[] }> {
	const calls: Recorded[] = [];
	const server = createServer((req: IncomingMessage, res) => {
		const chunks: Buffer[] = [];
		req.on('data', (c: Buffer) => chunks.push(c));
		req.on('end', () => {
			const path = (req.url ?? '/').split('?')[0];
			let body: Record<string, unknown> = {};
			try {
				body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {};
			} catch {
				body = {};
			}
			calls.push({ path, authHeader: req.headers['x-worker-admission-secret'] as string | undefined, body });
			const sourceId = typeof body.source_id === 'string' ? body.source_id : A_SRC;
			res.writeHead(202, { 'content-type': 'application/json' });
			res.end(JSON.stringify({ accepted: true, sources: [{ source_id: sourceId, disposition: 'triggered' }] }));
		});
	});
	return new Promise((resolve) => {
		server.listen(0, '127.0.0.1', () => {
			const { port } = server.address() as AddressInfo;
			resolve({ server, url: `http://127.0.0.1:${port}`, calls });
		});
	});
}

// Models RLS: resolveConnectionProvider (locals.supabase, anon + linked_source_select) resolves a
// provider ONLY for a source the SESSION tenant owns; a foreign source → null (as RLS yields).
function supabaseOwning(ownedSources: Record<string, string>) {
	return {
		schema: () => ({
			from: () => ({
				select: () => ({
					eq: (_col: string, sourceId: string) => ({
						maybeSingle: async () => ({
							data: sourceId in ownedSources ? { provider: ownedSources[sourceId] } : null,
							error: null
						})
					})
				})
			})
		})
	};
}

function makeEvent(body: unknown, sessionUid: string | null, ownedSources: Record<string, string>) {
	const request = new Request('http://localhost/api/sync', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const user = sessionUid ? { id: sessionUid } : null;
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: supabaseOwning(ownedSources)
	};
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

let worker: { server: Server; url: string; calls: Recorded[] };

beforeEach(async () => {
	worker = await startRecordingWorker();
	process.env.WORKER_ADMISSION_SHARED_SECRET = 'relay-two-tenant-secret';
	process.env.WORKER_ADMISSION_URL = worker.url;
	__resetConfigForTests();
});
afterEach(async () => {
	vi.restoreAllMocks();
	await new Promise<void>((r) => worker.server.close(() => r()));
});

describe('Sec #1 layer 2 — the app-side spoof gate (RLS resolve → 404) is two-tenant', () => {
	it('A asks for B\'s REAL source_id → provider resolves null under A\'s RLS → 404; worker NEVER called', async () => {
		// A's session; A owns only A_SRC; B_SRC belongs to B and does NOT resolve under A's RLS.
		const res = await POST(makeEvent({ source_id: B_SRC }, SESSION_A, { [A_SRC]: 'plaid' }));
		expect(res.status).toBe(404);
		expect(worker.calls).toHaveLength(0); // the spoof never reached the worker.
	});

	it('NON-VACUOUS control: A asks for A\'s OWN source → 202; worker called once with the SESSION tenant', async () => {
		const res = await POST(makeEvent({ source_id: A_SRC }, SESSION_A, { [A_SRC]: 'plaid' }));
		expect(res.status).toBe(202);
		expect(worker.calls).toHaveLength(1);
		expect(worker.calls[0].path).toBe('/admission/manual-sync');
		expect(worker.calls[0].body).toEqual({ ownerUserId: SESSION_A, source_id: A_SRC });
	});

	it('symmetry: B asks for A\'s source_id → 404 (each tenant\'s RLS only resolves its own sources)', async () => {
		// B's session; B owns only B_SRC; A_SRC does NOT resolve under B's RLS.
		const res = await POST(makeEvent({ source_id: A_SRC }, SESSION_B, { [B_SRC]: 'simplefin' }));
		expect(res.status).toBe(404);
		expect(worker.calls).toHaveLength(0);
	});
});

describe('C6-3 — the ownerUserId on the wire is ALWAYS the session\'s, never a browser-body value', () => {
	it('a body smuggling ownerUserId/users_id is rejected by .strict() (400); worker NEVER called', async () => {
		// Attacker (session A) tries to bind the worker call to B via the body — mass-assignment fence.
		const r1 = await POST(makeEvent({ source_id: A_SRC, ownerUserId: SESSION_B }, SESSION_A, { [A_SRC]: 'plaid' }));
		expect(r1.status).toBe(400);
		const r2 = await POST(makeEvent({ source_id: A_SRC, users_id: SESSION_B }, SESSION_A, { [A_SRC]: 'plaid' }));
		expect(r2.status).toBe(400);
		expect(worker.calls).toHaveLength(0);
	});

	it('sync-all as A → the wire body is EXACTLY { ownerUserId: sessionA } (no source_id, no body tenant)', async () => {
		const res = await POST(makeEvent({}, SESSION_A, { [A_SRC]: 'plaid' }));
		expect(res.status).toBe(202);
		expect(worker.calls).toHaveLength(1);
		expect(worker.calls[0].body).toEqual({ ownerUserId: SESSION_A });
		expect(worker.calls[0].authHeader).toBe('relay-two-tenant-secret'); // authed transport.
	});
});
