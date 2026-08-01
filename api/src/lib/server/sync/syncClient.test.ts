// syncClient.test.ts — SELF-317 manual-sync relay transport.
//
// Covers the SC3-C1 payload seam (session id, never body), the sync-all vs per-source payload
// shape, the 202 return-fast contract, and the failure-mapping (worker 5xx/transport → 502,
// worker 4xx → 400). Uses the $env/dynamic/private stub alias (vitest.config.ts) backed by
// process.env.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { requestManualSync, mapUpstreamStatus, __resetConfigForTests } from './syncClient';

// Node-global shim (api/ tsconfig omits @types/node from `types`). No runtime effect.
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

describe('mapUpstreamStatus', () => {
	it('worker 4xx → 400; worker 5xx / unexpected → 502', () => {
		expect(mapUpstreamStatus(400)).toBe(400);
		expect(mapUpstreamStatus(413)).toBe(400);
		expect(mapUpstreamStatus(500)).toBe(502);
		expect(mapUpstreamStatus(502)).toBe(502);
	});
});

describe('requestManualSync', () => {
	it('202: parses dispositions; sends session ownerUserId + secret header; per-source carries source_id', async () => {
		const fetchMock = vi.fn(async () =>
			jsonResponse(202, { accepted: true, sources: [{ source_id: '42', disposition: 'triggered' }] })
		);
		vi.stubGlobal('fetch', fetchMock);

		const out = await requestManualSync(SESSION_UID, '42');
		expect(out).toEqual({ ok: true, data: { accepted: true, sources: [{ source_id: '42', disposition: 'triggered' }] } });

		const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
		expect(url).toBe('http://worker.test:8081/admission/manual-sync');
		expect((init.headers as Record<string, string>)[ADMISSION_HEADER]).toBe('test-secret');
		expect(JSON.parse(init.body as string)).toEqual({ ownerUserId: SESSION_UID, source_id: '42' });
	});

	it('sync-all: omits source_id from the payload', async () => {
		const fetchMock = vi.fn(async () => jsonResponse(202, { accepted: true, sources: [] }));
		vi.stubGlobal('fetch', fetchMock);
		await requestManualSync(SESSION_UID);
		const init = (fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1];
		expect(JSON.parse(init.body as string)).toEqual({ ownerUserId: SESSION_UID });
	});

	it('worker 5xx → { ok:false, status:502 }', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(502, { error: 'manual_sync_failed' })));
		expect(await requestManualSync(SESSION_UID, '42')).toEqual({ ok: false, status: 502 });
	});

	it('worker 400 → { ok:false, status:400 }', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(400, { error: 'invalid_request' })));
		expect(await requestManualSync(SESSION_UID, '42')).toEqual({ ok: false, status: 400 });
	});

	it('transport failure → { ok:false, status:502 }', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn(async () => {
				throw new Error('ECONNREFUSED');
			})
		);
		expect(await requestManualSync(SESSION_UID, '42')).toEqual({ ok: false, status: 502 });
	});

	it('202 with a malformed body → { ok:false, status:502 } (fail-closed on schema mismatch)', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => jsonResponse(202, { accepted: true, sources: 'nope' })));
		expect(await requestManualSync(SESSION_UID, '42')).toEqual({ ok: false, status: 502 });
	});
});
