// simplefinConnectTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (OQ-2 / SC3-C6).
//
// SCOPE (QA, not a duplicate of connect.server.test.ts): the api/src RELAY half of the leg-S
// two-tenant cross-binding proof. The engineer's handler test uses a fetch MOCK and one tenant;
// this drives the REAL relay handler (POST /api/simplefin/connect) over the REAL admissionClient
// TRANSPORT (real fetch) against a REAL ephemeral node:http "worker" that RECORDS every inbound
// body — for TWO tenants, with attacker bodies. It proves the single load-bearing property C6-3
// asserts: whatever the browser sends, the ownerUserId that reaches the worker is ALWAYS the
// session's, NEVER a browser-body value.
//
// Composition (for Sec joint-review): this proves the relay only ever puts a SESSION-derived
// tenant on the wire. Its sibling — workers/provider-sync/tests/simplefinAdmissionTwoTenant.qa.test.ts
// — proves the worker, even under RLS-bypassing service_role, refuses a cross-tenant SimpleFIN
// credential write (SC3-C8). Together = the end-to-end two-tenant fence, each half at its right
// level. Mirrors the Plaid pair (admissionRelayTwoTenant + admissionTwoTenant).
//
// Grounding: docs/SECURITY §4.5 · temp/oq2-connect-seam-design.md (§7 C6 mapping) ·
// api/src/routes/api/simplefin/connect · api/src/lib/server/simplefin/admissionClient.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createServer, type Server, type IncomingMessage } from 'node:http';
import type { AddressInfo } from 'node:net';
import { POST } from '../src/routes/api/simplefin/connect/+server';
import { __resetConfigForTests } from '../src/lib/server/simplefin/admissionClient';

const SESSION_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const SESSION_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const ATTACKER = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const SHARED_SECRET = 'sfin-relay-two-tenant-secret-0123456789abcdef';
// A SimpleFIN setup token is a secret bearer credential (SD-03/RT-02) — a scrub sentinel.
const SETUP_TOKEN = btoa('https://setup-should-never-appear');

interface Recorded {
	path: string;
	authHeader: string | undefined;
	body: Record<string, unknown>;
}

// A real ephemeral worker: records each authed inbound body, replies with the leg-S contract
// shape. `respond` lets a test force a non-200 to exercise the relay's failure mapping + scrub.
function startRecordingWorker(
	respond?: (path: string) => { status: number; json: unknown }
): Promise<{ server: Server; url: string; calls: Recorded[] }> {
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
			// SimpleFIN refs carry type='unknown' (no provider type signal) + a surprise key the
			// upstream schema must STRIP before the browser sees it (proves the shipped contract).
			res.end(
				JSON.stringify({
					sourceId: '77',
					accounts: [{ account_id: 'sfin_acct_chk', name: 'Everyday Checking', type: 'unknown', subtype: null, currency: 'USD', __internal: 'strip-me' }]
				})
			);
		});
	});
	return new Promise((resolve) => {
		server.listen(0, '127.0.0.1', () => {
			const { port } = server.address() as AddressInfo;
			resolve({ server, url: `http://127.0.0.1:${port}`, calls });
		});
	});
}

function connectEvent(body: unknown, user: { id: string } | null) {
	const request = new Request('http://localhost/api/simplefin/connect', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(body)
	});
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }) };
	return { request, locals } as unknown as Parameters<typeof POST>[0];
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

// Node-global shim (api/ tsconfig omits @types/node from `types`). No runtime effect.
declare const process: { env: Record<string, string | undefined> };

describe('OQ-2 leg-S relay two-tenant cross-binding (QA — real transport → recording worker)', () => {
	it('the worker receives session A’s uid — not an attacker-body tenant (rejected upstream, no wire crossing)', async () => {
		const w = await wireWorker();
		// Attacker body smuggles session B’s id as ownerUserId while authed as A.
		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN, ownerUserId: SESSION_B }, { id: SESSION_A }));

		// `.strict()` rejects the extra key → 400, worker NEVER called (no wire crossing at all).
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: 'invalid_request' });
		expect(w.calls).toHaveLength(0);
	});

	it('a legitimate claim transmits ONLY the session tenant + the shared secret over the wire (tenant A)', async () => {
		const w = await wireWorker();
		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN, institutionName: 'Capital One' }, { id: SESSION_A }));
		expect(res.status).toBe(200);

		expect(w.calls).toHaveLength(1);
		expect(w.calls[0].path).toBe('/admission/simplefin/claim'); // no query string (C6-5)
		expect(w.calls[0].authHeader).toBe(SHARED_SECRET); // C6-2/C6-6 shared secret attached
		expect(w.calls[0].body.ownerUserId).toBe(SESSION_A); // session-derived, sole tenant control
		expect(w.calls[0].body.setup_token).toBe(SETUP_TOKEN); // token rides the JSON body (never a query)
		expect(w.calls[0].body.institutionName).toBe('Capital One');
	});

	it('two DIFFERENT sessions send two DIFFERENT tenants — no bleed, session is the sole control', async () => {
		const w = await wireWorker();
		// Both users send an IDENTICAL body (same setup_token) — only the session differs.
		await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_A }));
		await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_B }));

		expect(w.calls.map((c) => c.body.ownerUserId)).toEqual([SESSION_A, SESSION_B]);
		// The attacker id NEVER appears on the wire from either call.
		for (const c of w.calls) expect(c.body.ownerUserId).not.toBe(ATTACKER);
	});

	it('C6-3 headline: even with an attacker id in the body, session B’s id NEVER reaches the wire', async () => {
		const w = await wireWorker();
		// Session A, body smuggling B’s id. The relay rejects it (400) and — critically — B’s id is
		// never serialized onto any outbound call.
		await POST(connectEvent({ setup_token: SETUP_TOKEN, ownerUserId: SESSION_B }, { id: SESSION_A }));
		const onWire = JSON.stringify(w.calls);
		expect(onWire).not.toContain(SESSION_B);
	});

	it('account-ref passthrough (mapping reuse): browser receives the AccountRef[] shape, surprise keys stripped', async () => {
		await wireWorker();
		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_A }));
		expect(res.status).toBe(200);
		// Identical envelope shape to the Plaid exchange response → routes to the SHIPPED attributes
		// flow (no new mapping leg). SimpleFIN's un-typed ref (type='unknown') passes through, and the
		// upstream schema STRIPS the surprise `__internal` key so nothing unexpected reaches the browser.
		expect(await res.json()).toEqual({
			success: true,
			accounts: [{ account_id: 'sfin_acct_chk', name: 'Everyday Checking', type: 'unknown', subtype: null, currency: 'USD' }],
			// SELF-199 / ADR-037: relay forwards the caller's OWN linked_source_id alongside accounts (the
			// recording worker at L69 emits sourceId:'77'); the __internal surprise key is still stripped.
			linked_source_id: '77'
		});
	});

	it('unauthenticated → 401, worker never reached', async () => {
		const w = await wireWorker();
		expect((await POST(connectEvent({ setup_token: SETUP_TOKEN }, null))).status).toBe(401);
		expect(w.calls).toHaveLength(0);
	});
});

// ── Client-correctable discrimination + fail-safe, mapped through the REAL transport ───────────
describe('OQ-2 leg-S relay — status discrimination (client-correctable vs fail-safe)', () => {
	it('worker 400 setup_token_invalid (burned token) → browser 400, generic scrubbed body (re-enter token)', async () => {
		await wireWorker(() => ({ status: 400, json: { error: 'setup_token_invalid' } }));
		const res = await POST(connectEvent({ setup_token: 'burned' }, { id: SESSION_A }));
		expect(res.status).toBe(400);
		// The worker's internal code is NOT forwarded — a generic browser envelope.
		expect(await res.json()).toEqual({ error: 'connect_failed' });
	});

	it('worker 5xx (Bridge/admission failure) → browser 500 (fail-safe, NOT dressed as client-correctable)', async () => {
		await wireWorker(() => ({ status: 502, json: { error: 'admission_failed' } }));
		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_A }));
		expect(res.status).toBe(500);
		expect(await res.json()).toEqual({ error: 'connect_failed' });
	});

	it('a malformed worker 200 (missing accounts) → browser 502 (fail-closed, no partial success)', async () => {
		await wireWorker(() => ({ status: 200, json: { sourceId: '77' /* accounts absent */ } }));
		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_A }));
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'connect_failed' });
	});

	it('worker unreachable (transport failure) → browser 502', async () => {
		// Point at a closed port to force a transport failure deterministically.
		const dead = await startRecordingWorker();
		const url = dead.url;
		await new Promise<void>((r) => dead.server.close(() => r()));
		process.env.WORKER_ADMISSION_URL = url;
		__resetConfigForTests();

		const res = await POST(connectEvent({ setup_token: SETUP_TOKEN }, { id: SESSION_A }));
		expect(res.status).toBe(502);
	});
});

// ── C6-5 log-scrub — api/src RELAY tier, independent systematic sweep ──────────────────────────
// Capture ALL console output across success + a worker-4xx (burned) + a worker-5xx + a transport
// failure, plus the browser-facing response bodies, and assert no setup_token / Access-URL fragment
// / shared secret ever appears — on EVERY path.
describe('C6-5 log-scrub — api/src leg-S relay tier (independent sweep)', () => {
	const SETUP_SENTINEL = 'setup-sandbox-SENSITIVE-DO-NOT-LOG';
	const SENTINELS = [SETUP_SENTINEL, SHARED_SECRET, 'access-sandbox', 'user:pass@'];

	function captureConsole() {
		const lines: string[] = [];
		const push = (...args: unknown[]) => lines.push(args.map(String).join(' '));
		vi.spyOn(console, 'error').mockImplementation(push);
		vi.spyOn(console, 'log').mockImplementation(push);
		vi.spyOn(console, 'warn').mockImplementation(push);
		return lines;
	}

	it('success path: no setup token / secret in logs OR the browser response body', async () => {
		await wireWorker();
		const lines = captureConsole();
		const res = await POST(connectEvent({ setup_token: SETUP_SENTINEL }, { id: SESSION_A }));
		const bodyText = await res.text();
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('worker-4xx (burned) path: 400 generic envelope, no token/secret leak', async () => {
		await wireWorker(() => ({ status: 400, json: { error: 'setup_token_invalid' } }));
		const lines = captureConsole();
		const res = await POST(connectEvent({ setup_token: SETUP_SENTINEL }, { id: SESSION_A }));
		const bodyText = await res.text();
		expect(res.status).toBe(400);
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('worker-5xx failure path: generic 500 envelope, no token/secret leak', async () => {
		await wireWorker(() => ({ status: 502, json: { error: 'admission_failed' } }));
		const lines = captureConsole();
		const res = await POST(connectEvent({ setup_token: SETUP_SENTINEL }, { id: SESSION_A }));
		const bodyText = await res.text();
		expect(res.status).toBe(500);
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('transport-failure path: worker unreachable → 502, no token/secret leak', async () => {
		const dead = await startRecordingWorker();
		const url = dead.url;
		await new Promise<void>((r) => dead.server.close(() => r()));
		process.env.WORKER_ADMISSION_URL = url;
		__resetConfigForTests();

		const lines = captureConsole();
		const res = await POST(connectEvent({ setup_token: SETUP_SENTINEL }, { id: SESSION_A }));
		const bodyText = await res.text();
		expect(res.status).toBe(502);
		const haystack = lines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});
});
