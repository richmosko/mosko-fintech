// admissionRelayTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (SELF-212 / SC3-C6).
//
// SCOPE (QA, not a duplicate of exchange.server.test.ts): the api/src RELAY half of the
// two-tenant cross-binding proof. The engineers' handler test uses a fetch MOCK and one tenant;
// this drives the REAL relay handlers (GET /api/plaid/link-token + POST /api/plaid/exchange)
// over the REAL admissionClient TRANSPORT (real fetch) against a REAL ephemeral node:http
// "worker" that RECORDS every inbound body — for TWO tenants, with attacker bodies. It proves
// the single load-bearing property C6-3 asserts: whatever the browser sends, the ownerUserId
// that reaches the worker is ALWAYS the session's, NEVER a browser-body value.
//
// Composition (for Sec joint-review): this proves the relay only ever puts a SESSION-derived
// tenant on the wire. Its sibling — workers/provider-sync/tests/admissionTwoTenant.qa.test.ts —
// proves the worker, even under RLS-bypassing service_role, refuses a cross-tenant credential
// write (SC3-C8). Together = the end-to-end two-tenant fence, each half at its right level.
//
// The recording server stands in for the worker ONLY to capture what the relay transmits; the
// worker's own trust boundary is the sibling test's job, not this one's.
//
// Grounding: docs/SECURITY §4.5 · temp/self212-sec-c6-review.md (C6-3 / C6-5) ·
// temp/self212-worker-endpoint-contract.md · api/src/routes/api/plaid/{exchange,link-token}.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createServer, type Server, type IncomingMessage } from 'node:http';
import type { AddressInfo } from 'node:net';
import { GET } from '../src/routes/api/plaid/link-token/+server';
import { POST } from '../src/routes/api/plaid/exchange/+server';
import { __resetConfigForTests } from '../src/lib/server/plaid/admissionClient';

const SESSION_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const SESSION_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const ATTACKER = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const SHARED_SECRET = 'relay-two-tenant-secret-0123456789abcdef';

interface Recorded {
	path: string;
	authHeader: string | undefined;
	body: Record<string, unknown>;
}

// A real ephemeral worker: records each authed inbound body, replies with the contract shape.
// `respond` lets a test force a non-200 to exercise the relay's failure mapping + redaction.
function startRecordingWorker(respond?: (path: string) => { status: number; json: unknown }): Promise<{ server: Server; url: string; calls: Recorded[] }> {
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

			const forced = respond?.(path);
			if (forced) {
				res.writeHead(forced.status, { 'content-type': 'application/json' });
				res.end(JSON.stringify(forced.json));
				return;
			}
			res.writeHead(200, { 'content-type': 'application/json' });
			if (path === '/admission/link-token') {
				res.end(JSON.stringify({ link_token: 'link-sandbox-xyz', expiration: '2026-07-19T12:00:00Z' }));
			} else {
				res.end(JSON.stringify({ sourceId: '42', accounts: [{ account_id: 'acct_1', name: 'Checking' }] }));
			}
		});
	});
	return new Promise((resolve) => {
		server.listen(0, '127.0.0.1', () => {
			const { port } = server.address() as AddressInfo;
			resolve({ server, url: `http://127.0.0.1:${port}`, calls });
		});
	});
}

function exchangeEvent(body: unknown, user: { id: string } | null) {
	const request = new Request('http://localhost/api/plaid/exchange', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }) };
	return { request, locals } as unknown as Parameters<typeof POST>[0];
}

function linkTokenEvent(user: { id: string } | null) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }) };
	return { locals } as unknown as Parameters<typeof GET>[0];
}

let worker: { server: Server; url: string; calls: Recorded[] } | undefined;

beforeEach(() => {
	process.env.WORKER_ADMISSION_SHARED_SECRET = SHARED_SECRET;
	__resetConfigForTests();
});

afterEach(async () => {
	if (worker) await new Promise<void>((r) => worker!.server.close(() => r()));
	worker = undefined;
	vi.restoreAllMocks();
	delete process.env.WORKER_ADMISSION_URL;
	__resetConfigForTests();
});

async function wireWorker(respond?: (path: string) => { status: number; json: unknown }) {
	worker = await startRecordingWorker(respond);
	process.env.WORKER_ADMISSION_URL = worker.url;
	__resetConfigForTests();
	return worker;
}

describe('SELF-212 relay two-tenant cross-binding (QA — real transport → recording worker)', () => {
	it('leg-2: the worker receives session A’s uid — not an attacker-body tenant (rejected upstream)', async () => {
		const w = await wireWorker();
		// Attacker body carries session B’s id as a smuggled ownerUserId while authed as A.
		const res = await POST(exchangeEvent({ public_token: 'public-sandbox-abc', ownerUserId: SESSION_B }, { id: SESSION_A }));

		// `.strict()` rejects the extra key → 400, worker NEVER called (no wire crossing at all).
		expect(res.status).toBe(400);
		expect(w.calls).toHaveLength(0);
	});

	it('leg-2: a legitimate exchange transmits ONLY the session tenant over the wire (tenant A)', async () => {
		const w = await wireWorker();
		const res = await POST(exchangeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_A }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ success: true, accounts: [{ account_id: 'acct_1', name: 'Checking' }] });

		expect(w.calls).toHaveLength(1);
		expect(w.calls[0].path).toBe('/admission/exchange');
		expect(w.calls[0].authHeader).toBe(SHARED_SECRET); // shared secret attached (C6-2/C6-6)
		expect(w.calls[0].body.ownerUserId).toBe(SESSION_A);
	});

	it('leg-2: two DIFFERENT sessions send two DIFFERENT tenants — no bleed, session is the sole control', async () => {
		const w = await wireWorker();
		// Both users send an IDENTICAL body (same public_token, and each tries to smuggle ATTACKER).
		await POST(exchangeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_A }));
		await POST(exchangeEvent({ public_token: 'public-sandbox-abc' }, { id: SESSION_B }));

		expect(w.calls.map((c) => c.body.ownerUserId)).toEqual([SESSION_A, SESSION_B]);
		// The attacker id NEVER appears on the wire from either call.
		for (const c of w.calls) expect(c.body.ownerUserId).not.toBe(ATTACKER);
	});

	it('leg-1: link-token mint transmits the session tenant, POST + shared secret, never a query string', async () => {
		const w = await wireWorker();
		const res = await GET(linkTokenEvent({ id: SESSION_B }));
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ link_token: 'link-sandbox-xyz', expiration: '2026-07-19T12:00:00Z' });

		expect(w.calls).toHaveLength(1);
		expect(w.calls[0].path).toBe('/admission/link-token'); // no query string (C6-5)
		expect(w.calls[0].authHeader).toBe(SHARED_SECRET);
		expect(w.calls[0].body).toEqual({ ownerUserId: SESSION_B });
	});

	it('unauthenticated → 401, worker never reached (both legs)', async () => {
		const w = await wireWorker();
		expect((await POST(exchangeEvent({ public_token: 'public-sandbox-abc' }, null))).status).toBe(401);
		expect((await GET(linkTokenEvent(null))).status).toBe(401);
		expect(w.calls).toHaveLength(0);
	});
});

// ── C6-5 log-scrub — api/src RELAY tier, independent systematic sweep ──────────────────────────
// Capture ALL console output across success + a worker-5xx failure + a transport failure, plus
// the browser-facing response bodies, and assert no public_token / access_token fragment / shared
// secret ever appears — on BOTH the success and failure paths.
describe('C6-5 log-scrub — api/src relay tier (independent sweep)', () => {
	const PUBLIC_TOKEN = 'public-sandbox-SENSITIVE-DO-NOT-LOG';
	const SENTINELS = [PUBLIC_TOKEN, SHARED_SECRET, 'access-sandbox'];

	function captureConsole() {
		const lines: string[] = [];
		const push = (...args: unknown[]) => lines.push(args.map(String).join(' '));
		vi.spyOn(console, 'error').mockImplementation(push);
		vi.spyOn(console, 'log').mockImplementation(push);
		vi.spyOn(console, 'warn').mockImplementation(push);
		return lines;
	}

	it('success path: no sensitive token/secret in logs OR the browser response body', async () => {
		const w = await wireWorker();
		const lines = captureConsole();
		const res = await POST(exchangeEvent({ public_token: PUBLIC_TOKEN }, { id: SESSION_A }));
		const bodyText = await res.text();

		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
		void w;
	});

	it('worker-5xx failure path: generic envelope, no token/secret leak in logs or response', async () => {
		await wireWorker(() => ({ status: 502, json: { error: 'admission_failed' } }));
		const lines = captureConsole();
		const res = await POST(exchangeEvent({ public_token: PUBLIC_TOKEN }, { id: SESSION_A }));
		const bodyText = await res.text();

		expect(res.status).toBe(500); // worker 5xx → generic 500 (no internal detail)
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('transport-failure path: worker unreachable → 502, no token/secret leak', async () => {
		// Point at a closed port (nothing listening) to force a transport failure deterministically.
		const dead = await startRecordingWorker();
		const url = dead.url;
		await new Promise<void>((r) => dead.server.close(() => r()));
		process.env.WORKER_ADMISSION_URL = url;
		__resetConfigForTests();

		const lines = captureConsole();
		const res = await POST(exchangeEvent({ public_token: PUBLIC_TOKEN }, { id: SESSION_A }));
		const bodyText = await res.text();

		expect(res.status).toBe(502);
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});
});

// ── RECONCILIATION RESOLVED (2026-07-19 Sec ruling): invalid public_token → browser 400 ────────
// Ruling: the worker emits `400 public_token_invalid` for an invalid/burned public_token, and
// the relay's mapUpstreamStatus maps worker-400 → browser-400 (a client-correctable status so
// the browser re-runs Link for a fresh token — C6-4: the relay itself never retries). The
// browser body stays a GENERIC scrubbed envelope: no public_token, no shared secret, and not
// even the worker's internal `public_token_invalid` code is forwarded.
describe('invalid public_token → browser 400 (Sec reconciliation RESOLVED)', () => {
	const PUBLIC_TOKEN = 'public-sandbox-BURNED-DO-NOT-LOG';

	it('worker 400 public_token_invalid → browser 400, generic scrubbed body', async () => {
		await wireWorker(() => ({ status: 400, json: { error: 'public_token_invalid' } }));

		const lines: string[] = [];
		const push = (...args: unknown[]) => lines.push(args.map(String).join(' '));
		vi.spyOn(console, 'error').mockImplementation(push);
		vi.spyOn(console, 'log').mockImplementation(push);

		const res = await POST(exchangeEvent({ public_token: PUBLIC_TOKEN }, { id: SESSION_A }));
		const bodyText = await res.text();

		// Client-correctable 400 (NOT the 5xx-reconnect class).
		expect(res.status).toBe(400);
		// Generic envelope — no upstream detail leaked to the browser.
		expect(bodyText).toBe(JSON.stringify({ error: 'exchange_failed' }));

		// Scrub sweep: neither the token, the shared secret, nor the worker's internal
		// error code appears in logs or the browser body.
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of [PUBLIC_TOKEN, SHARED_SECRET, 'public_token_invalid']) {
			expect(haystack).not.toContain(s);
		}
	});
});
