// admissionClient.test.ts — OQ-2 leg-S relay transport unit tests (QA extension).
//
// QA GAP CLOSED: the Plaid transport (plaid/admissionClient.ts) ships its own unit test;
// the SimpleFIN transport seam had NONE — it was only exercised transitively via the route
// handler test. This file unit-tests the SimpleFIN transport's pure + network seams directly,
// mirroring plaid/admissionClient.test.ts:
//   • buildClaimPayload — the SC3-C1/C6-3 seam (session-derived ownerUserId, NEVER a body value).
//   • mapUpstreamStatus — the SELF-197/OQ-2 failure-mapping table (worker 4xx→400, else→500).
//   • admitSimplefin transport — header + payload on the wire, sourceId dropped, 4xx→400,
//     5xx→500, transport→502, malformed-200→502, fail-loud-on-missing-secret, C6-5 log-scrub.
//
// Uses the $env/dynamic/private stub alias (vitest.config.ts) backed by process.env.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	buildClaimPayload,
	mapUpstreamStatus,
	admitSimplefin,
	__resetConfigForTests
} from './admissionClient';

// Node-global shim (api/ tsconfig omits @types/node from `types` — harness gap, mirrors
// plaid/admissionClient.test.ts). No runtime effect.
declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = '11111111-1111-4111-8111-111111111111';
const ATTACKER_UID = '22222222-2222-4222-8222-222222222222';
const ADMISSION_HEADER = 'x-worker-admission-secret';
const SETUP_TOKEN = btoa('https://setup-should-never-appear'); // base64-ish; a secret sentinel.

function jsonResponse(status: number, body: unknown): Response {
	return new Response(body === undefined ? '' : JSON.stringify(body), {
		status,
		headers: { 'content-type': 'application/json' }
	});
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

// ── Pure SC3-C1/C6-3 seam ────────────────────────────────────────────────────────────────
describe('buildClaimPayload (SC3-C1 — session tenant, never the body)', () => {
	it('uses the session-derived ownerUserId argument, never a body value', () => {
		// Even if a rogue key reached here (it cannot — `.strict()` at the route is the first
		// fence), the ARG is the sole tenant source. Force-cast a body carrying an attacker
		// ownerUserId and prove the output still carries the session id.
		const payload = buildClaimPayload(SESSION_UID, {
			setup_token: SETUP_TOKEN,
			// @ts-expect-error — the validated body type has no ownerUserId; this models a defense-in-depth attempt.
			ownerUserId: ATTACKER_UID
		});
		expect(payload.ownerUserId).toBe(SESSION_UID);
		expect(payload.ownerUserId).not.toBe(ATTACKER_UID);
		expect(payload.setup_token).toBe(SETUP_TOKEN);
	});

	it('forwards institutionName when present, omits the key otherwise', () => {
		const withInst = buildClaimPayload(SESSION_UID, { setup_token: SETUP_TOKEN, institutionName: 'Capital One' });
		expect(withInst.institutionName).toBe('Capital One');

		const noInst = buildClaimPayload(SESSION_UID, { setup_token: SETUP_TOKEN });
		expect(noInst).not.toHaveProperty('institutionName');
	});
});

// ── Status mapping (OQ-2 failure-mapping AC) ───────────────────────────────────────────────
describe('mapUpstreamStatus', () => {
	it('worker 4xx (bad/burned request incl. 400 setup_token_invalid) → 400', () => {
		expect(mapUpstreamStatus(400)).toBe(400);
		expect(mapUpstreamStatus(413)).toBe(400);
	});
	it('worker 5xx (Bridge/admission failure incl. the 502 envelope) → 500', () => {
		expect(mapUpstreamStatus(500)).toBe(500);
		expect(mapUpstreamStatus(502)).toBe(500);
		expect(mapUpstreamStatus(503)).toBe(500);
	});
	it('worker 401 secret-mismatch / 404 / 405 routing (should-never-happen) → 500, no leak', () => {
		expect(mapUpstreamStatus(401)).toBe(500);
		expect(mapUpstreamStatus(404)).toBe(500);
		expect(mapUpstreamStatus(405)).toBe(500);
	});
});

// ── Transport: header, body, mapping, redaction ────────────────────────────────────────────
describe('admitSimplefin transport', () => {
	it('POSTs the shared-secret header + session ownerUserId to the claim path, drops sourceId', async () => {
		const fetchMock = vi.fn(async () =>
			jsonResponse(200, { sourceId: '77', accounts: [{ account_id: 'acct_1', name: 'Checking', type: 'unknown' }] })
		);
		vi.stubGlobal('fetch', fetchMock);

		const out = await admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN, institutionName: 'Capital One' });
		expect(out).toEqual({ ok: true, data: { accounts: [{ account_id: 'acct_1', name: 'Checking', type: 'unknown' }] } });
		// sourceId (internal pfin id) must NOT survive into the browser-facing data.
		if (out.ok) expect(JSON.stringify(out.data)).not.toContain('77');

		const [url, init] = fetchMock.mock.calls[0] as unknown as [
			string,
			{ method: string; headers: Record<string, string>; body: string }
		];
		expect(url).toBe('http://worker.test:8081/admission/simplefin/claim');
		expect(init.method).toBe('POST');
		expect(init.headers[ADMISSION_HEADER]).toBe('test-secret');
		const sent = JSON.parse(init.body);
		expect(sent.ownerUserId).toBe(SESSION_UID);
		expect(sent.setup_token).toBe(SETUP_TOKEN);
		expect(sent.institutionName).toBe('Capital One');
	});

	it('maps worker 400 (burned/invalid setup token) → 400 client-correctable', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(400, { error: 'setup_token_invalid' })));
		expect(await admitSimplefin(SESSION_UID, { setup_token: 'burned' })).toEqual({ ok: false, status: 400 });
	});

	it('maps worker 5xx (Bridge/admission failure) → 500', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'admission_failed' })));
		expect(await admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN })).toEqual({ ok: false, status: 500 });
	});

	it('maps a transport failure (worker unreachable) → 502', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn(async () => {
				throw new Error('ECONNREFUSED');
			})
		);
		expect(await admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN })).toEqual({ ok: false, status: 502 });
	});

	it('a malformed 200 body (missing accounts) → 502 (fail-closed, no partial success to the browser)', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(200, { sourceId: '77' /* no accounts */ })));
		expect(await admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN })).toEqual({ ok: false, status: 502 });
	});

	it('fails loud when the shared secret is absent (misconfig, not a silent bypass)', async () => {
		delete process.env.WORKER_ADMISSION_SHARED_SECRET;
		__resetConfigForTests();
		vi.stubGlobal('fetch', vi.fn());
		await expect(admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN })).rejects.toThrow(/WORKER_ADMISSION_SHARED_SECRET/);
	});

	it('C6-5: never logs the setup token or the shared secret (any failure path)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'admission_failed' })));

		await admitSimplefin(SESSION_UID, { setup_token: SETUP_TOKEN, institutionName: 'Capital One' });

		const logged = errSpy.mock.calls.flat().join(' ');
		expect(logged).not.toContain(SETUP_TOKEN);
		expect(logged).not.toContain('test-secret');
	});
});
