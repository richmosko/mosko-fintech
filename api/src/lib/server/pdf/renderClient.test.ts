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
// >= MIN_SIGNING_KEY_LENGTH (32, Sec F-8) — a shorter value here would make every
// non-config test in this file fail at renderConfig()'s own entropy-floor check.
const SIGNING_KEY = 'test-signing-key-do-not-leak-3456789';
const OTHER_KEY = 'a-different-key-entirely-0123456789';

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

	it('DOCUMENTATION LEG, not coverage (Sec F-3(b)): the SAME token does not verify under a different key. This is a property of HMAC itself and cannot fail for any defect of THIS module — kept as a readable statement of the property this letter relies on, not counted toward RT-21 (b)\'s actual coverage (the first leg above, which DOES exercise this module\'s own key selection, is that coverage)', async () => {
		const token = await mintRenderToken(USERS_ID);
		await expect(
			jwtVerify(token, new TextEncoder().encode(OTHER_KEY), { algorithms: ['HS256'] })
		).rejects.toThrow();
	});
});

// ── (a) tier restriction -> key restriction ────────────────────────────────────────────
// Sec F-3(a): "deleting it removes the assertion that a Supabase-issued token cannot drive
// a render" is the AC's own claim for this letter, and this leg does not carry it — that
// assertion is WORKER-side and is covered at A4
// (workers/pdf-render/test/auth.test.js: "a wrong-key signature is rejected and counted
// under signature_verification_failed"). This leg's actual job is narrower and stated as
// such: this module IMPORTS no Supabase client anywhere in its own source.
describe('RT-21 (a): no Supabase-tier concept on this path (the "cannot drive a render" assertion itself lives at A4 — see auth.test.js)', () => {
	it('this module never IMPORTS a Supabase client (prose mentions in comments are fine — this checks actual usage, matched against the WHOLE source so a wrapped/multi-line import or a dynamic import() cannot slip past a line-anchored filter)', () => {
		const src = readFileSync(fileURLToPath(new URL('./renderClient.ts', import.meta.url)), 'utf8');
		// Strip comments first so a prose mention (this file's own module header discusses
		// "Supabase-tier" at length) cannot false-positive the match — then match the WHOLE
		// remaining source, not line-by-line: a wrapped import
		// (`import {\n  x\n} from '@supabase/...'`) puts the specifier on a line that does
		// not itself start with `import`, and `await import('@supabase/...')` never starts
		// a line with the `import` keyword at all. Sec F-3(a).
		const code = src
			.split('\n')
			.filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
			.join('\n');
		expect(code).not.toMatch(/from\s+['"][^'"]*supabase|import\s*\(\s*['"][^'"]*supabase/i);
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

	it('the authorization header is EXACTLY "Bearer <jwt>" — matches the worker\'s own parse (/^Bearer\\s+(\\S+)$/, workers/pdf-render/src/auth.js), which the two legs above compare VALUES against without ever asserting the prefix shape itself (Sec F-3)', async () => {
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		await renderReportHtml(USERS_ID, '<html></html>');
		const auth = (fetchMock.mock.calls[0] as unknown as [string, { headers: Record<string, string> }])[1]
			.headers['authorization'];
		const match = /^Bearer\s+(\S+)$/.exec(auth);
		expect(match).not.toBeNull();
		// The captured token is a real JWT — three dot-separated, non-empty segments —
		// never an empty string a looser prefix check could pass.
		expect(match?.[1].split('.')).toHaveLength(3);
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

	it('this module holds no Supabase credential reach: the source names no SUPABASE_* env var and no service_role (Sec F-3(e) — the worker\'s OWN zero-Supabase-credential guarantee is a separate, cited fence: RT-22 + the RT-22-manifest fence, workers/pdf-render/Dockerfile + package.json, SELF-348, merged to `main` at `bde35a7` — this leg does not re-assert that against files it cannot see; it checks THIS module\'s own source, which is a real, failable assertion, replacing a previous `expect(true).toBe(true)`)', () => {
		const src = readFileSync(fileURLToPath(new URL('./renderClient.ts', import.meta.url)), 'utf8');
		const code = src.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
		expect(code).not.toMatch(/SUPABASE_[A-Z_]+/);
		expect(code).not.toMatch(/service_role/);
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

	it('POSTs the html argument BYTE-FOR-BYTE as the request body — this module constructs no markup and interpolates nothing into it (Sec F-3; the module header\'s own negative assertion, previously unwatched)', async () => {
		const fetchMock = vi.fn(async () => pdfResponse());
		vi.stubGlobal('fetch', fetchMock);
		const html = '<html><body>MARKER-' + Math.random() + '</body></html>';
		await renderReportHtml(USERS_ID, html);
		const call = fetchMock.mock.calls[0] as unknown as [string, { body: string }];
		expect(call[1].body).toBe(html);
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

	it('Sec F-1 catch criterion (1): a 200 response whose BODY READ rejects (mid-body network failure, after headers already arrived) returns { ok:false, status:502 }, never a thrown error out of renderReportHtml', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn(
				async () =>
					new Response(
						new ReadableStream({
							start(controller) {
								controller.error(new Error('mid-body network failure'));
							}
						}),
						{ status: 200 }
					)
			)
		);
		// If the body read were outside the try/catch (the pre-fix shape), this call
		// would REJECT instead of resolving to a discriminated result — the assertion
		// itself is the catch criterion.
		await expect(renderReportHtml(USERS_ID, '<html></html>')).resolves.toEqual({
			ok: false,
			status: 502
		});
	});

	// Sec F-1's SECOND catch criterion — "a stub whose arrayBuffer() never settles must be
	// aborted by TIMEOUT_MS rather than hanging the spec" — is explicitly labelled in Sec's
	// own review file as a leg "for the paired legs (QA)", not authored here. Attempted it
	// here first regardless (`vi.useFakeTimers()` + `vi.advanceTimersByTimeAsync(30_000)`
	// around a hung `fetch` mock) and it does NOT work in this file as a quick add: this
	// module's `mintRenderToken` calls `jose`'s `SignJWT.sign()` (WebCrypto HMAC signing)
	// BEFORE the fetch/timeout logic ever runs, and that operation appears to depend on
	// real event-loop/libuv completion rather than resolving purely off vitest's fake
	// timer + microtask queue — the whole test hangs to vitest's OWN 5s test timeout
	// without ever reaching the code path it's meant to exercise, regardless of how the
	// fetch mock itself is shaped. Left for QA to solve (a per-test `vi.spyOn` on
	// `mintRenderToken` to skip real signing while fake timers are active is one plausible
	// route; a real, short-real-time test with a small custom timeout is another) rather
	// than land a leg that either hangs CI or silently passes for the wrong reason.
});

// ── Claim SET (Sec F-2) — the exhaustive shape, not just individual presence/absence ────
describe('SD-20 claim set: EXACTLY { users_id, nonce, iat }, no data_as_of, no silent additions', () => {
	it('the claim set is EXACTLY { users_id, nonce, iat } — no data_as_of claim (SD-20 verbatim; ADR-011 Decision 19 / Lock 15 mod #7b), no silent additions', async () => {
		const token = await mintRenderToken(USERS_ID);
		expect(Object.keys(decodeJwt(token)).sort()).toEqual(['iat', 'nonce', 'users_id']);
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

	it('Sec F-8: throws a clear error when PDF_WORKER_SIGNING_KEY is shorter than the entropy floor, rather than signing with an obviously-too-short secret', async () => {
		process.env.PDF_WORKER_SIGNING_KEY = 'too-short';
		__resetConfigForTests();
		await expect(mintRenderToken(USERS_ID)).rejects.toThrow(/shorter than/i);
	});

	it('Sec F-8: a signing key AT the entropy floor (32 chars) is accepted', async () => {
		process.env.PDF_WORKER_SIGNING_KEY = 'x'.repeat(32);
		__resetConfigForTests();
		await expect(mintRenderToken(USERS_ID)).resolves.toEqual(expect.any(String));
	});
});
