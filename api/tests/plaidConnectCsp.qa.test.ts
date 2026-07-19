// plaidConnectCsp.qa.test.ts — QA test hook for RT-28 (Plaid Link CSP allowlist).
//
// STATUS: LIVE as of #12 (CSP config landed). The stub `expect(true)` assertions are
// GONE — CSP-1 (the Sec veto condition) is now a REAL assertion driven by the shipped
// per-route logic (`src/lib/plaid/csp.ts::applyPlaidConnectCsp`, exactly what the
// hooks.server.ts handle calls). Because that logic is a pure function, the route-scoping
// behavior is testable here without a running server or route fixtures.
//
// OWNERSHIP (per #12 handoff): Frontend authored the pure CSP helper + its unit tests
// (src/lib/plaid/csp.test.ts). This QA file is the RT-28 acceptance layer asserting the
// blessed set + CSP-1..4 against that helper. QA to review/adopt; an OPTIONAL further
// hardening (an HTTP-level test that boots the app and reads the real
// `content-security-policy` RESPONSE HEADER off /accounts/connect vs a non-Plaid route)
// is QA/Backend-api territory — flagged, not required for RT-28's core assertion.
//
// RT-28 (MEDIUM, normal RT — NOT a §10 catalogued instance): the Plaid Link connect
// route's CSP must stay (a) PER-ROUTE scoped (never app-global), (b) nonce-based on
// script-src (never 'unsafe-inline'-script), (c) admit ONLY cdn.plaid.com (script/frame)
// + production.plaid.com (connect) — no *.plaid.com wildcard, no sandbox host in a prod
// build.

import { describe, it, expect } from 'vitest';
import {
	applyPlaidConnectCsp,
	parseCsp,
	PLAID_CONNECT_ROUTE_ID,
	PLAID_SCRIPT_SRC,
	PLAID_FRAME_SRC,
	PLAID_CONNECT_SRC_PROD,
	PLAID_CONNECT_SRC_SANDBOX
} from '../src/lib/plaid/csp';

// The Sec-blessed minimal set (per-route, Link onboarding surface ONLY). Source of record:
// temp/self212-sec-c6-review.md — "Blessed minimal set" table + DECISIONS.md ADR-028.
export const BLESSED_CSP = {
	'script-src': ["'self'", "'nonce-<per-response>'", 'https://cdn.plaid.com/link/v2/stable/link-initialize.js'],
	'style-src': ["'self'", "'nonce-<per-response>'"],
	'style-src-elem': ["'self'", "'nonce-<per-response>'"],
	'style-src-attr': ["'unsafe-inline'"], // vendor-forced residual (CSP-4), documented in SECURITY §4.2
	'frame-src': ['https://cdn.plaid.com'],
	'connect-src': ["'self'", 'https://production.plaid.com'] // env-matched: sandbox.plaid.com when PLAID_ENV=sandbox
	// default-src stays app base 'self'; img-src NOT required.
} as const;

// The forbidden shapes — the regressions RT-28 exists to catch.
export const CSP_FORBIDDEN = {
	scriptUnsafeInline: "'unsafe-inline'", // never on script-src (CSP-2)
	plaidWildcard: 'https://*.plaid.com', // never (CSP-3)
	sandboxHostInProd: 'https://sandbox.plaid.com' // absent from a prod CSP (CSP-3)
} as const;

// A representative strict base header as SvelteKit kit.csp emits it in SSR (nonce mode).
const NONCE = 'r4Nd0mNoNcE';
const BASE_CSP =
	`default-src 'self'; script-src 'self' 'nonce-${NONCE}'; style-src 'self' 'nonce-${NONCE}'; ` +
	`style-src-elem 'self' 'nonce-${NONCE}'; style-src-attr 'none'; img-src 'self' data:; ` +
	`font-src 'self'; connect-src 'self'; frame-src 'self'; object-src 'none'; base-uri 'self'; ` +
	`form-action 'self'; frame-ancestors 'none'`;

// The connect route's emitted CSP for each Plaid env (F/CTO ruling: env-matched host).
const connectProd = parseCsp(applyPlaidConnectCsp(PLAID_CONNECT_ROUTE_ID, BASE_CSP, { plaidEnv: 'production' }));
const connectSandbox = parseCsp(applyPlaidConnectCsp(PLAID_CONNECT_ROUTE_ID, BASE_CSP, { plaidEnv: 'sandbox' }));

describe('RT-28 — Plaid Link connect-route CSP allowlist (LIVE — #12 landed)', () => {
	it('CSP-1: relaxations are PER-ROUTE — a non-Plaid route carries NONE of them (either env)', () => {
		for (const plaidEnv of ['sandbox', 'production'] as const) {
			for (const routeId of ['/', '/dashboard', '/accounts', '/accounts/new', null]) {
				const out = applyPlaidConnectCsp(routeId, BASE_CSP, { plaidEnv });
				expect(out).toBe(BASE_CSP); // identity: untouched
				for (const t of ['plaid.com', 'cdn.plaid.com', 'production.plaid.com', 'sandbox.plaid.com']) {
					expect(out).not.toContain(t);
				}
			}
		}
	});

	it('CSP-2: script-src uses the per-response nonce, NEVER \'unsafe-inline\'', () => {
		const scriptSrc = connectProd.get('script-src')!;
		expect(scriptSrc.some((s) => s.startsWith("'nonce-"))).toBe(true);
		expect(scriptSrc).not.toContain(CSP_FORBIDDEN.scriptUnsafeInline);
	});

	it('CSP-3: production env → connect-src is explicit production.plaid.com; never *.plaid.com, never sandbox', () => {
		const connectSrc = connectProd.get('connect-src')!;
		expect(connectSrc).toEqual(["'self'", PLAID_CONNECT_SRC_PROD]);
		expect(connectSrc).not.toContain(CSP_FORBIDDEN.plaidWildcard);
		expect(connectSrc).not.toContain(CSP_FORBIDDEN.sandboxHostInProd);
	});

	it('CSP-3: sandbox env → connect-src is explicit sandbox.plaid.com ONLY (env-matched, not both)', () => {
		// Plaid-official CSP guidance: in Sandbox, point connect-src at sandbox.plaid.com.
		expect(connectSandbox.get('connect-src')).toEqual(["'self'", PLAID_CONNECT_SRC_SANDBOX]);
		expect(connectSandbox.get('connect-src')).not.toContain(PLAID_CONNECT_SRC_PROD);
	});

	it('CSP-3: script-src + frame-src admit ONLY cdn.plaid.com (no wildcard)', () => {
		expect(connectProd.get('frame-src')).toEqual([PLAID_FRAME_SRC]);
		expect(connectProd.get('script-src')).toContain(PLAID_SCRIPT_SRC);
		const all = [...connectProd.values()].flat();
		expect(all.some((s) => s.includes('*'))).toBe(false);
	});

	it('CSP-4: style-src-attr \'unsafe-inline\' is the ONLY vendor-forced residual (documented)', () => {
		expect(connectProd.get('style-src-attr')).toEqual(["'unsafe-inline'"]);
		expect(connectProd.get('style-src')).not.toContain("'unsafe-inline'");
		expect(connectProd.get('style-src-elem')).not.toContain("'unsafe-inline'");
		expect(connectProd.get('script-src')).not.toContain("'unsafe-inline'");
	});

	it('emitted connect-route CSP matches the BLESSED set shape (nonce-normalized)', () => {
		// Normalize the live nonce token to the blessed placeholder for a shape compare.
		const norm = (arr: string[]) => arr.map((s) => (s.startsWith("'nonce-") ? "'nonce-<per-response>'" : s));
		expect(norm(connectProd.get('script-src')!)).toEqual([...BLESSED_CSP['script-src']]);
		expect(norm(connectProd.get('style-src')!)).toEqual([...BLESSED_CSP['style-src']]);
		expect(norm(connectProd.get('style-src-elem')!)).toEqual([...BLESSED_CSP['style-src-elem']]);
		expect(connectProd.get('frame-src')).toEqual([...BLESSED_CSP['frame-src']]);
		expect(connectProd.get('connect-src')).toEqual([...BLESSED_CSP['connect-src']]);
	});
});
