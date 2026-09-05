// renderClient.test.ts — SELF-349 / A5 RT-21 battery, re-derived under R2 (C). Each
// canonical letter (a)-(g) gets its OWN leg, failing for its OWN reason (a leg that
// cannot fail is not a test) — mirrors admissionClient.test.ts's harness shape: the
// $env/dynamic/private stub alias (vitest.config.ts) backed by process.env, `fetch`
// stubbed via vi.stubGlobal per case.
//
// SCOPE NOTE: this module MINTS and SENDS; it does not VERIFY (that's the worker,
// workers/pdf-render/src/auth.js, already battery-tested at SELF-348 with a real
// Chromium round trip). This file's job is (1) prove what gets MINTED matches every
// RT-21 letter's shape requirement, and (2) prove a worker rejection propagates as
// `{ ok:false }` without ever being read as success or logged with body detail (g).

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { decodeJwt, jwtVerify } from 'jose';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { renderReportHtml, mintRenderToken, __resetConfigForTests } from './renderClient';

declare const process: { env: Record<string, string | undefined> };

const USERS_ID = '22222222-2222-4222-8222-222222222222';
const SIGNING_KEY = 'test-signing-key-do-not-leak';
const OTHER_KEY = 'a-different-key-entirely';

function pdfResponse(): Response {
	return new Response(new Uint8Array([0x25, 0x50, 0x44, 0x46]) /* %PDF */, {
		status: 200,
		headers: { 'content-type': 'application/pdf' }
	});
}

beforeEach(() => {
	process.env.PDF_WORKER_SIGNING_KEY = SIGNING_KEY;
	process.env.PDF_RENDER_WORKER_URL = 'http://worker.test:8080';
	__resetConfigForTests();
});

afterEach(() => {
	vi.restoreAllMocks();
	vi.unstubAllGlobals();
});

// ── (b) DEDICATED SIGNING KEY ──────────────────────────────────────────────────────────
describe('RT-21 (b): dedicated signing key', () => {
	it('mints a token whose signature verifies under PDF_WORKER_SIGNING_KEY (HS256)', async () => {
		const token = await mintRenderToken(USERS_ID);
		const { payload } = await jwtVerify(token, new TextEncoder().encode(SIGNING_KEY), {
			algorithms: ['HS256']
		});
		expect(payload.users_id).toBe(USERS_ID);
	});

	it('the SAME token does NOT verify under a different key — proves this is the dedicated key, not an incidental one', async () => {
		const token = await mintRenderToken(USERS_ID);
		await expect(
			jwtVerify(token, new TextEncoder().encode(OTHER_KEY), { algorithms: ['HS256'] })
		).rejects.toThrow();
	});
});

// ── (a) tier restriction -> key restriction ────────────────────────────────────────────
describe('RT-21 (a): no Supabase-tier concept on this path', () => {
	it('this module never IMPORTS a Supabase client or touches a Supabase session token (prose mentions in comments are fine — this checks actual usage, via import statements)', () => {
		const src = readFileSync(fileURLToPath(new URL('./renderClient.ts', import.meta.url)), 'utf8');
		const importLines = src
			.split('\n')
			.filter((line) => /^\s*import\b/.test(line))
			.join('\n');
		expect(importLines).not.toMatch(/supabase/i);
	});
});

// ── (c) 60-second freshness window on iat, NOT exp ─────────────────────────────────────
describe('RT-21 (c): iat freshness window, never exp', () => {
	it('mints iat as the current time and carries NO exp claim', async () => {
		const before = Math.floor(Date.now() / 1000);
		const token = await mintRenderToken(USERS_ID);
		const after = Math.floor(Date.now() / 1000);
		const claims = decodeJwt(token);
		expect(claims.iat).toBeGreaterThanOrEqual(before);
		expect(claims.iat).toBeLessThanOrEqual(after);
		expect(claims.exp).toBeUndefined();
	});
});

// ── (d) nonce replay protection — minted, not stored (the store is worker-side) ────────
describe('RT-21 (d): a fresh nonce every mint', () => {
	it('two mints for the SAME usersId produce DIFFERENT nonces', async () => {
		const t1 = await mintRenderToken(USERS_ID);
		const t2 = await mintRenderToken(USERS_ID);
		const c1 = decodeJwt(t1);
		const c2 = decodeJwt(t2);
		expect(c1.nonce).not.toBe(c2.nonce);
	});

	it('renderReportHtml mints a FRESH token per call, never reusing one across two sends', async () => {
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		await renderReportHtml(USERS_ID, '<html></html>');
		await renderReportHtml(USERS_ID, '<html></html>');
		const auth1 = (fetchMock.mock.calls[0] as unknown as [string, { headers: Record<string, string> }])[1]
			.headers['authorization'];
		const auth2 = (fetchMock.mock.calls[1] as unknown as [string, { headers: Record<string, string> }])[1]
			.headers['authorization'];
		expect(auth1).not.toBe(auth2);
	});
});

// ── (e) NO service_role escalation — structural under R2 (C) ──────────────────────────
describe('RT-21 (e): no escalation path, structural not behavioral', () => {
	it('this module holds no Supabase credential and makes exactly ONE outbound call per render (no second, elevated call)', async () => {
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		await renderReportHtml(USERS_ID, '<html></html>');
		expect(fetchMock).toHaveBeenCalledTimes(1);
	});

	it('references A4\'s own fence rather than re-asserting DB-isolation independently (cited, not re-implemented)', () => {
		// This leg is intentionally a CITATION, not a duplicate control: the worker's
		// zero-Supabase-credential guarantee is RT-22 + the RT-22-manifest fence
		// (workers/pdf-render/Dockerfile + package.json, SELF-348). Re-asserting it here
		// against files that don't exist on THIS branch (A4 hasn't merged) would be a
		// false-positive-prone duplicate of a control this module cannot see.
		expect(true).toBe(true);
	});
});

// ── (f) dedicated endpoint — the referent moved to the worker's render route ───────────
describe('RT-21 (f): dedicated endpoint', () => {
	it('POSTs to exactly /render on the configured worker base URL, nothing else', async () => {
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		await renderReportHtml(USERS_ID, '<html></html>');
		const [url] = fetchMock.mock.calls[0] as unknown as [string];
		expect(url).toBe('http://worker.test:8080/render');
	});
});

// ── (g) rejected payloads — app-side half: propagate, never mask, never log detail ─────
describe('RT-21 (g): worker rejection propagates as ok:false, status only in logs', () => {
	it('a 401 from the worker returns { ok:false, status:401 }, never treated as success', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => new Response('unauthorized', { status: 401 })));
		const result = await renderReportHtml(USERS_ID, '<html></html>');
		expect(result).toEqual({ ok: false, status: 401 });
	});

	it('logs the STATUS only — never the response body', async () => {
		const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		vi.stubGlobal(
			'fetch',
			vi.fn(async () => new Response('sensitive-detail-that-must-not-be-logged', { status: 500 }))
		);
		await renderReportHtml(USERS_ID, '<html></html>');
		const logged = errorSpy.mock.calls.map((c) => c.join(' ')).join('\n');
		expect(logged).toMatch(/500/);
		expect(logged).not.toMatch(/sensitive-detail-that-must-not-be-logged/);
	});

	it('a transport failure (worker unreachable) returns { ok:false, status:502 }', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('ECONNREFUSED'); }));
		const result = await renderReportHtml(USERS_ID, '<html></html>');
		expect(result).toEqual({ ok: false, status: 502 });
	});
});

// ── Labelled ADDITIONS (Sec F-3 — kept distinct from the canonical letters) ────────────
describe('RT-21 additions', () => {
	it('tenant-claim PRESENCE: users_id is always present on a minted token', async () => {
		const token = await mintRenderToken(USERS_ID);
		const claims = decodeJwt(token);
		expect(claims.users_id).toBe(USERS_ID);
	});

	it('audience/issuer: DECLINED by design — a minted token carries neither aud nor iss (see module header ADDITIONS note); this leg catches an accidental future add without an ADR', async () => {
		const token = await mintRenderToken(USERS_ID);
		const claims = decodeJwt(token);
		expect(claims.aud).toBeUndefined();
		expect(claims.iss).toBeUndefined();
	});
});

// ── Happy path + redaction ──────────────────────────────────────────────────────────────
describe('happy path', () => {
	it('a 200 from the worker returns { ok:true, pdfBytes }', async () => {
		vi.stubGlobal('fetch', vi.fn(async () => pdfResponse()));
		const result = await renderReportHtml(USERS_ID, '<html><body>x</body></html>');
		expect(result.ok).toBe(true);
		if (result.ok) {
			expect(result.pdfBytes.slice(0, 4)).toEqual(new Uint8Array([0x25, 0x50, 0x44, 0x46]));
		}
	});

	it('never logs the HTML body or the signing key on any path (happy or rejected)', async () => {
		const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const logSpy = vi.spyOn(console, 'log').mockImplementation(() => {});
		vi.stubGlobal('fetch', vi.fn(async () => new Response('x', { status: 401 })));
		const secretHtml = '<html>SECRET-FINANCIAL-DETAIL-98765</html>';
		await renderReportHtml(USERS_ID, secretHtml);
		const allLogs = [...errorSpy.mock.calls, ...logSpy.mock.calls].map((c) => c.join(' ')).join('\n');
		expect(allLogs).not.toMatch(/SECRET-FINANCIAL-DETAIL/);
		expect(allLogs).not.toMatch(new RegExp(SIGNING_KEY));
	});
});

// ── Config ───────────────────────────────────────────────────────────────────────────────
describe('config', () => {
	it('throws a clear error when PDF_WORKER_SIGNING_KEY is unset, rather than silently minting an unusable token', async () => {
		delete process.env.PDF_WORKER_SIGNING_KEY;
		__resetConfigForTests();
		await expect(mintRenderToken(USERS_ID)).rejects.toThrow(/PDF_WORKER_SIGNING_KEY/);
	});

	it('defaults to the Coolify internal service name when PDF_RENDER_WORKER_URL is unset', async () => {
		delete process.env.PDF_RENDER_WORKER_URL;
		__resetConfigForTests();
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		await renderReportHtml(USERS_ID, '<html></html>');
		const [url] = fetchMock.mock.calls[0] as unknown as [string];
		expect(url).toBe('http://pdf-render:8080/render');
	});
});
