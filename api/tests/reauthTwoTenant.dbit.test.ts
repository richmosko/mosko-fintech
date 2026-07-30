// reauthTwoTenant.dbit.test.ts — SELF-207 §2.4.4.b reauth APP-PATH two-tenant integration
// (QA-owned). The relay-route complement to Backend's start/complete.server.test (which MOCK
// resolveConnectionProvider) and the worker-side reauth.test (mocked DB): this drives the REAL
// /api/reauth/{start,complete} handlers against the REAL local Supabase, so the ownership fence
// runs through actual RLS — a caller supplying ANOTHER tenant's linked_source_id resolves to
// null via linked_source_select and 404s BEFORE the worker is touched. End-to-end, no provider mock.
//
// WHAT THIS PROVES BEYOND THE UNIT TESTS:
//  • cross-tenant fail-closed: session A → B's source → resolveConnectionProvider (real RLS) →
//    null → 404, worker NEVER called (the real isolation, not a mocked null).
//  • session-derived ownerUserId (SC3-C1): the relayed worker body carries ownerUserId = A's
//    SESSION id — never a client-supplied value (a body `ownerUserId`/`provider` is .strict()-rejected).
//  • provider resolved SERVER-SIDE: the worker body's `provider` is the caller's OWN source's
//    provider (plaid vs simplefin), read from the DB — not from the request.
//
// A recording worker (node:http) stands in for provider-sync (we assert the relayed body + that a
// non-owned/400 request never reaches it). The credential rotation + healthy state_history WRITE
// are the WORKER's job — proven end-to-end by the poll-loop E2E (separate deliverable), not here.
//
// SELF-GATING + boundary posture identical to attributesPersistTwoTenant.dbit (service_role in the
// runner for privileged linked_source seeding; skips without API_URL/ANON_KEY/SERVICE_ROLE_KEY).

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { POST as startPOST } from '../src/routes/api/reauth/start/+server';
import { POST as completePOST } from '../src/routes/api/reauth/complete/+server';
import { __resetConfigForTests } from '../src/lib/server/reauth/admissionClient';

declare const process: { env: Record<string, string | undefined> };

const URL_ = process.env.SUPABASE_URL ?? process.env.API_URL;
const ANON = process.env.SUPABASE_ANON_KEY ?? process.env.ANON_KEY;
const SR = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SERVICE_ROLE_KEY;
const RUN = Boolean(URL_ && ANON && SR);
const SHARED_SECRET = 'dbit-reauth-secret';

type WorkerCall = { path: string; secret: string | undefined; body: Record<string, unknown> };

/** A recording provider-sync stand-in: records each relayed call + answers by (path, provider). */
function startRecordingWorker(): Promise<{ server: http.Server; url: string; calls: WorkerCall[] }> {
	const calls: WorkerCall[] = [];
	const server = http.createServer((req, res) => {
		let body = '';
		req.on('data', (c) => (body += c));
		req.on('end', () => {
			const parsed = (body ? JSON.parse(body) : {}) as Record<string, unknown>;
			calls.push({ path: req.url ?? '', secret: req.headers['x-worker-admission-secret'] as string | undefined, body: parsed });
			const out =
				req.url === '/admission/reauth/start'
					? parsed.provider === 'plaid'
						? { kind: 'link_update', linkToken: 'lt-1' }
						: { kind: 'recollect_credential' }
					: { connectionStatus: 'healthy', rotated: parsed.provider === 'simplefin' };
			res.writeHead(200, { 'content-type': 'application/json' });
			res.end(JSON.stringify(out));
		});
	});
	return new Promise((resolve) =>
		server.listen(0, '127.0.0.1', () => {
			const port = (server.address() as AddressInfo).port;
			resolve({ server, url: `http://127.0.0.1:${port}`, calls });
		})
	);
}

function makeEvent(body: unknown, supabase: SupabaseClient, user: { id: string } | null, path: string) {
	const request = new Request(`http://localhost${path}`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	// Intersection cast so the built event is accepted by BOTH handlers (their RequestEvent types
	// differ only in the phantom route-id literal; an A&B value is assignable to each).
	return { request, locals } as unknown as Parameters<typeof startPOST>[0] & Parameters<typeof completePOST>[0];
}

describe.skipIf(!RUN)('APP-PATH reauth relay — two-tenant ownership fence (real DB)', () => {
	const RID = Date.now();
	let admin: SupabaseClient;
	let worker: { server: http.Server; url: string; calls: WorkerCall[] };
	const createdUserIds: string[] = [];
	let cA: SupabaseClient;
	let aId: string;
	let aPlaid: number, aSfin: number, bSrc: number;

	async function makeUser(tag: string): Promise<{ id: string; client: SupabaseClient }> {
		const email = `qa-self207-${tag}-${RID}@synthetic.test`;
		const password = `Pw-${RID}-${tag}-xyz`;
		const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
		if (error || !data.user) throw new Error(`createUser(${tag}) failed: ${error?.message}`);
		createdUserIds.push(data.user.id);
		const client = createClient(URL_ as string, ANON as string, { auth: { persistSession: true, autoRefreshToken: false } });
		const si = await client.auth.signInWithPassword({ email, password });
		if (si.error) throw new Error(`signIn(${tag}) failed: ${si.error.message}`);
		return { id: data.user.id, client };
	}

	async function makeSource(users_id: string, provider: string, tag: string): Promise<number> {
		const { data, error } = await admin
			.schema('pfin')
			.from('linked_source')
			.insert({ users_id, provider, external_connection_id: `conn-${tag}-${RID}`, institution_name: `Synthetic ${tag}` })
			.select('source_id')
			.single();
		if (error || !data) throw new Error(`insert linked_source(${tag}) failed: ${error?.message}`);
		return data.source_id as number;
	}

	beforeAll(async () => {
		admin = createClient(URL_ as string, SR as string, { auth: { persistSession: false, autoRefreshToken: false } });
		const A = await makeUser('a'); aId = A.id; cA = A.client;
		const B = await makeUser('b');
		aPlaid = await makeSource(aId, 'plaid', 'a-plaid');
		aSfin = await makeSource(aId, 'simplefin', 'a-sfin');
		bSrc = await makeSource(B.id, 'plaid', 'b');

		worker = await startRecordingWorker();
		process.env.WORKER_ADMISSION_SHARED_SECRET = SHARED_SECRET;
		process.env.WORKER_ADMISSION_URL = worker.url;
		__resetConfigForTests();
	}, 60_000);

	afterAll(async () => {
		if (worker) await new Promise<void>((r) => worker.server.close(() => r()));
		if (admin) for (const id of createdUserIds) await admin.auth.admin.deleteUser(id);
	}, 30_000);

	it('(1) cross-tenant START: session A supplying tenant B’s linked_source_id → 404, worker never called (real RLS ownership fence)', async () => {
		worker.calls.length = 0;
		const res = await startPOST(makeEvent({ linked_source_id: String(bSrc) }, cA, { id: aId }, '/api/reauth/start'));
		expect(res.status).toBe(404); // resolveConnectionProvider → null (B's source RLS-invisible to A)
		expect(worker.calls).toHaveLength(0); // never reaches the worker
	});

	it('(2) owner START (plaid): provider resolved server-side + session ownerUserId relayed → link_update', async () => {
		worker.calls.length = 0;
		const res = await startPOST(makeEvent({ linked_source_id: String(aPlaid) }, cA, { id: aId }, '/api/reauth/start'));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ kind: 'link_update', link_token: 'lt-1' });
		expect(worker.calls).toHaveLength(1);
		expect(worker.calls[0].path).toBe('/admission/reauth/start');
		expect(worker.calls[0].secret).toBe(SHARED_SECRET);
		// ownerUserId = A's SESSION id (not client-supplied); provider resolved server-side from A's own source.
		expect(worker.calls[0].body).toEqual({ provider: 'plaid', linked_source_id: String(aPlaid), ownerUserId: aId });
	});

	it('(3) owner START (simplefin): provider resolved simplefin → recollect_credential', async () => {
		worker.calls.length = 0;
		const res = await startPOST(makeEvent({ linked_source_id: String(aSfin) }, cA, { id: aId }, '/api/reauth/start'));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ kind: 'recollect_credential' });
		expect(worker.calls[0].body.provider).toBe('simplefin'); // resolved from A's own source, not the request
	});

	it('(4) mass-assignment: a client-supplied `provider` in the body is .strict()-rejected → 400, worker never called', async () => {
		worker.calls.length = 0;
		const res = await startPOST(
			makeEvent({ linked_source_id: String(aPlaid), provider: 'simplefin' }, cA, { id: aId }, '/api/reauth/start')
		);
		expect(res.status).toBe(400); // provider can NEVER be client-supplied (server resolves it)
		expect(worker.calls).toHaveLength(0);
	});

	it('(5) cross-tenant COMPLETE: session A supplying B’s linked_source_id → 404, worker never called', async () => {
		worker.calls.length = 0;
		const res = await completePOST(
			makeEvent({ linked_source_id: String(bSrc), setup_token: 'st-x' }, cA, { id: aId }, '/api/reauth/complete')
		);
		expect(res.status).toBe(404);
		expect(worker.calls).toHaveLength(0);
	});

	it('(6) owner COMPLETE (simplefin): session ownerUserId + setup_token input relayed → healthy/rotated', async () => {
		worker.calls.length = 0;
		const res = await completePOST(
			makeEvent({ linked_source_id: String(aSfin), setup_token: 'fresh-setup-token' }, cA, { id: aId }, '/api/reauth/complete')
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ connection_status: 'healthy', rotated: true });
		expect(worker.calls[0].path).toBe('/admission/reauth/complete');
		expect(worker.calls[0].body).toEqual({
			provider: 'simplefin',
			linked_source_id: String(aSfin),
			ownerUserId: aId, // session-derived
			input: { kind: 'setup_token', setup_token: 'fresh-setup-token' }
		});
	});

	it('(7) COMPLETE (simplefin) missing setup_token → 400 (client error), worker never called', async () => {
		worker.calls.length = 0;
		const res = await completePOST(makeEvent({ linked_source_id: String(aSfin) }, cA, { id: aId }, '/api/reauth/complete'));
		expect(res.status).toBe(400);
		expect(worker.calls).toHaveLength(0);
	});
});
