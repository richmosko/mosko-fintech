// admissionClient.test.ts — SELF-325 asset-resolve leg transport unit tests.
//
// Mirrors simplefin/admissionClient.test.ts (the shipped precedent this module copies):
//   • buildResolvePayload — the SC3-C1/C6-3 seam (session-derived ownerUserId, NEVER a body value).
//   • mapUpstreamStatus — 4xx→400, else→500.
//   • resolveAsset transport — header + payload on the wire, assetId forwarded (incl. null),
//     4xx→400, 5xx→500, transport→502, malformed-200→502, fail-loud-on-missing-secret, C6-5 log-scrub.
//
// Uses the $env/dynamic/private stub alias (vitest.config.ts) backed by process.env.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { buildResolvePayload, mapUpstreamStatus, resolveAsset, __resetConfigForTests } from './admissionClient';

// Node-global shim (api/ tsconfig omits @types/node from `types` — harness gap, mirrors
// simplefin/admissionClient.test.ts). No runtime effect.
declare const process: { env: Record<string, string | undefined> };

const SESSION_UID = '11111111-1111-4111-8111-111111111111';
const ATTACKER_UID = '22222222-2222-4222-8222-222222222222';
const ADMISSION_HEADER = 'x-worker-admission-secret';

const VALID_BODY = {
	symbol: 'AAPL',
	cusip: null,
	assetType: 'equity',
	name: 'Apple Inc',
	currency: 'USD'
};

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
describe('buildResolvePayload (SC3-C1 — session tenant, never the body)', () => {
	it('uses the session-derived ownerUserId argument, never a body value', () => {
		const payload = buildResolvePayload(SESSION_UID, {
			...VALID_BODY,
			// @ts-expect-error — the validated body type has no ownerUserId; models a defense-in-depth attempt.
			ownerUserId: ATTACKER_UID
		});
		expect(payload.ownerUserId).toBe(SESSION_UID);
		expect(payload.ownerUserId).not.toBe(ATTACKER_UID);
		expect(payload.symbol).toBe('AAPL');
	});

	it('forwards every validated field verbatim', () => {
		const payload = buildResolvePayload(SESSION_UID, {
			symbol: null,
			cusip: '037833100',
			assetType: 'bond',
			name: null,
			currency: 'USD'
		});
		expect(payload).toEqual({
			ownerUserId: SESSION_UID,
			symbol: null,
			cusip: '037833100',
			assetType: 'bond',
			name: null,
			currency: 'USD'
		});
	});
});

// ── Status mapping ───────────────────────────────────────────────────────────────────────
describe('mapUpstreamStatus', () => {
	it('worker 4xx → 400', () => {
		expect(mapUpstreamStatus(400)).toBe(400);
		expect(mapUpstreamStatus(413)).toBe(400);
	});
	it('worker 5xx (incl. the 502 envelope) → 500', () => {
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
describe('resolveAsset transport', () => {
	it('POSTs the shared-secret header + session ownerUserId to the resolve path, forwards assetId', async () => {
		const fetchMock = vi.fn(async () => jsonResponse(200, { assetId: 501 }));
		vi.stubGlobal('fetch', fetchMock);

		const out = await resolveAsset(SESSION_UID, VALID_BODY);
		expect(out).toEqual({ ok: true, data: { assetId: 501 } });

		const [url, init] = fetchMock.mock.calls[0] as unknown as [
			string,
			{ method: string; headers: Record<string, string>; body: string }
		];
		expect(url).toBe('http://worker.test:8081/asset/resolve');
		expect(init.method).toBe('POST');
		expect(init.headers[ADMISSION_HEADER]).toBe('test-secret');
		const sent = JSON.parse(init.body);
		expect(sent.ownerUserId).toBe(SESSION_UID);
		expect(sent.symbol).toBe('AAPL');
		expect(sent.assetType).toBe('equity');
	});

	it('forwards a null assetId unchanged (SELF-200 unvalued parity)', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(200, { assetId: null })));
		expect(await resolveAsset(SESSION_UID, VALID_BODY)).toEqual({ ok: true, data: { assetId: null } });
	});

	it('maps worker 4xx (schema-drift should-never-happen) → 400', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(400, { error: 'invalid_request' })));
		expect(await resolveAsset(SESSION_UID, VALID_BODY)).toEqual({ ok: false, status: 400 });
	});

	it('maps worker 5xx (resolve/mint failure) → 500', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'asset_resolve_failed' })));
		expect(await resolveAsset(SESSION_UID, VALID_BODY)).toEqual({ ok: false, status: 500 });
	});

	it('maps a transport failure (worker unreachable) → 502', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn(async () => {
				throw new Error('ECONNREFUSED');
			})
		);
		expect(await resolveAsset(SESSION_UID, VALID_BODY)).toEqual({ ok: false, status: 502 });
	});

	it('a malformed 200 body (missing assetId) → 502 (fail-closed, no partial success to the browser)', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(200, {})));
		expect(await resolveAsset(SESSION_UID, VALID_BODY)).toEqual({ ok: false, status: 502 });
	});

	it('fails loud when the shared secret is absent (misconfig, not a silent bypass)', async () => {
		delete process.env.WORKER_ADMISSION_SHARED_SECRET;
		__resetConfigForTests();
		vi.stubGlobal('fetch', vi.fn());
		await expect(resolveAsset(SESSION_UID, VALID_BODY)).rejects.toThrow(/WORKER_ADMISSION_SHARED_SECRET/);
	});

	it('C6-5: never logs the shared secret or the identity payload (any failure path)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'asset_resolve_failed' })));

		await resolveAsset(SESSION_UID, VALID_BODY);

		const logged = errSpy.mock.calls.flat().join(' ');
		expect(logged).not.toContain('AAPL');
		expect(logged).not.toContain('test-secret');
	});
});
