// admissionClient.test.ts — SELF-197 relay transport unit tests.
//
// Covers the SC3-C1 payload seam (session id, never body), C6-5 redaction, and the
// SELF-197 failure-mapping AC (worker 5xx→500, 4xx→400, transport→502). Uses the
// $env/dynamic/private stub alias (vitest.config.ts) backed by process.env.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	buildExchangePayload,
	buildLinkTokenPayload,
	extractInstitution,
	mapUpstreamStatus,
	mintLinkToken,
	exchangePublicToken,
	__resetConfigForTests
} from './admissionClient';

// Node-global shim (api/ tsconfig omits @types/node from `types` — harness gap,
// flagged to DevOps; also affects tests/harness.smoke.test.ts). No runtime effect.
declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = '11111111-1111-4111-8111-111111111111';
const ADMISSION_HEADER = 'x-worker-admission-secret';

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

// ── Pure SC3-C1 seam ───────────────────────────────────────────────────────────────────
describe('buildExchangePayload (SC3-C1)', () => {
	it('uses the session-derived ownerUserId argument, never a body value', () => {
		// Even if a body value somehow reached here, the arg wins. (`.strict()` at the
		// route makes an extra body key impossible upstream — this is the second fence.)
		const payload = buildExchangePayload(SESSION_UID, {
			public_token: 'public-sandbox-abc'
		});
		expect(payload.ownerUserId).toBe(SESSION_UID);
		expect(payload.public_token).toBe('public-sandbox-abc');
	});

	it('forwards institution metadata when present, omits it otherwise', () => {
		const withInst = buildExchangePayload(SESSION_UID, {
			public_token: 'public-sandbox-abc',
			metadata: { institution: { institution_id: 'ins_1', name: 'Chase' } }
		});
		expect(withInst.institutionId).toBe('ins_1');
		expect(withInst.institutionName).toBe('Chase');

		const noInst = buildExchangePayload(SESSION_UID, { public_token: 'public-sandbox-abc' });
		expect(noInst).not.toHaveProperty('institutionId');
		expect(noInst).not.toHaveProperty('institutionName');
	});

	it('buildLinkTokenPayload carries only the session ownerUserId', () => {
		expect(buildLinkTokenPayload(SESSION_UID)).toEqual({ ownerUserId: SESSION_UID });
	});
});

describe('extractInstitution', () => {
	it('returns {} for junk / missing metadata', () => {
		expect(extractInstitution(undefined)).toEqual({});
		expect(extractInstitution('not-an-object')).toEqual({});
		expect(extractInstitution({ nope: true })).toEqual({});
	});
});

// ── Status mapping (SELF-197 failure-mapping AC) ───────────────────────────────────────
describe('mapUpstreamStatus', () => {
	it('worker 4xx (bad/burned request) → 400', () => {
		expect(mapUpstreamStatus(400)).toBe(400);
		expect(mapUpstreamStatus(413)).toBe(400);
	});
	it('worker 5xx (Plaid/admission failure incl. 502) → 500', () => {
		expect(mapUpstreamStatus(500)).toBe(500);
		expect(mapUpstreamStatus(502)).toBe(500);
		expect(mapUpstreamStatus(503)).toBe(500);
	});
	it('worker 401 secret-mismatch / 404 routing (should-never-happen) → 500, no leak', () => {
		expect(mapUpstreamStatus(401)).toBe(500);
		expect(mapUpstreamStatus(404)).toBe(500);
	});
});

// ── Transport: header, body, mapping, redaction ────────────────────────────────────────
describe('mintLinkToken transport', () => {
	it('POSTs the shared-secret header + session ownerUserId, returns the token', async () => {
		const fetchMock = vi.fn(async () =>
			jsonResponse(200, { link_token: 'link-sandbox-xyz', expiration: '2026-07-19T12:00:00Z' })
		);
		vi.stubGlobal('fetch', fetchMock);

		const out = await mintLinkToken(SESSION_UID);
		expect(out).toEqual({
			ok: true,
			data: { link_token: 'link-sandbox-xyz', expiration: '2026-07-19T12:00:00Z' }
		});

		const [url, init] = fetchMock.mock.calls[0] as unknown as [
			string,
			{ method: string; headers: Record<string, string>; body: string }
		];
		expect(url).toBe('http://worker.test:8081/admission/link-token');
		expect(init.method).toBe('POST');
		expect(init.headers[ADMISSION_HEADER]).toBe('test-secret');
		expect(JSON.parse(init.body)).toEqual({ ownerUserId: SESSION_UID });
	});

	it('maps a worker 5xx to 500', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'link_token_failed' })));
		expect(await mintLinkToken(SESSION_UID)).toEqual({ ok: false, status: 500 });
	});

	it('maps a transport failure (worker unreachable) to 502', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn(async () => {
				throw new Error('ECONNREFUSED');
			})
		);
		expect(await mintLinkToken(SESSION_UID)).toEqual({ ok: false, status: 502 });
	});

	it('fails loud when the shared secret is absent', async () => {
		delete process.env.WORKER_ADMISSION_SHARED_SECRET;
		__resetConfigForTests();
		vi.stubGlobal('fetch', vi.fn());
		await expect(mintLinkToken(SESSION_UID)).rejects.toThrow(/WORKER_ADMISSION_SHARED_SECRET/);
	});
});

describe('exchangePublicToken transport', () => {
	it('sends session ownerUserId + public_token, forwards sourceId in the result', async () => {
		const fetchMock = vi.fn(async () =>
			jsonResponse(200, {
				sourceId: '42',
				accounts: [{ account_id: 'acct_1', name: 'Checking', type: 'depository' }]
			})
		);
		vi.stubGlobal('fetch', fetchMock);

		const out = await exchangePublicToken(SESSION_UID, { public_token: 'public-sandbox-abc' });
		// sourceId (the caller's own linked_source id) is now FORWARDED for the SELF-199
		// attributes flow (ADR-037 (ii) client-carries-refs) — no longer dropped.
		expect(out).toEqual({
			ok: true,
			data: {
				sourceId: '42',
				accounts: [{ account_id: 'acct_1', name: 'Checking', type: 'depository' }]
			}
		});

		const [, init] = fetchMock.mock.calls[0] as unknown as [string, { body: string }];
		expect(JSON.parse(init.body).ownerUserId).toBe(SESSION_UID);
	});

	it('maps worker 400 (invalid/burned request) → 400', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(400, { error: 'invalid_request' })));
		expect(await exchangePublicToken(SESSION_UID, { public_token: 'x' })).toEqual({
			ok: false,
			status: 400
		});
	});

	it('C6-5: never logs the public_token or the shared secret', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'admission_failed' })));

		await exchangePublicToken(SESSION_UID, { public_token: 'public-sandbox-SECRETTOKEN' });

		const logged = errSpy.mock.calls.flat().join(' ');
		expect(logged).not.toContain('public-sandbox-SECRETTOKEN');
		expect(logged).not.toContain('test-secret');
	});
});
