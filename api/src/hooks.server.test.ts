// hooks.server.test.ts — SELF-198 #12 cspHandle wiring proof.
//
// Frontend's csp.ts unit tests own the pure directive logic + the RT-28 CSP-1
// per-route-scoping assertion. THIS test owns the server-hook wiring Backend added:
//  • the PLAID_ENV → plaidEnv fail-safe mapping (missing/unknown → sandbox, never prod);
//  • that the widening reaches the response header only on the connect route (CSP-1);
//  • that a response with no CSP header is passed through untouched (no throw).
//
// Drives cspHandle directly with a fake `resolve` — no live server / no authHandle
// Supabase client needed. `$env/dynamic/private` resolves to the process.env-backed
// stub via the vitest alias (vitest.config.ts).

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { cspHandle } from './hooks.server';
import {
	PLAID_CONNECT_ROUTE_ID,
	PLAID_CONNECT_SRC_PROD,
	PLAID_CONNECT_SRC_SANDBOX
} from '$lib/plaid/csp';

const BASE_CSP = "default-src 'self'; script-src 'self' 'nonce-abc'; connect-src 'self'";

// Minimal event/resolve doubles — cspHandle only touches event.route?.id + the resolved
// response's content-security-policy header.
function runCsp(routeId: string | null, opts?: { csp?: string | null }) {
	const cspHeader = opts && 'csp' in opts ? opts.csp : BASE_CSP;
	const event = { route: { id: routeId } } as unknown as Parameters<typeof cspHandle>[0]['event'];
	const resolve = (async () => {
		const headers = new Headers();
		if (cspHeader != null) headers.set('content-security-policy', cspHeader);
		return new Response('ok', { headers });
	}) as unknown as Parameters<typeof cspHandle>[0]['resolve'];
	return cspHandle({ event, resolve } as Parameters<typeof cspHandle>[0]);
}

beforeEach(() => {
	delete process.env.PLAID_ENV;
});

afterEach(() => {
	delete process.env.PLAID_ENV;
});

describe('cspHandle — CSP-1 route scoping', () => {
	it('leaves the CSP header UNCHANGED on a non-connect route (CSP-1)', async () => {
		process.env.PLAID_ENV = 'production'; // even in prod, a non-connect route must not widen
		const res = await runCsp('/accounts');
		expect(res.headers.get('content-security-policy')).toBe(BASE_CSP);
	});

	it('widens ONLY the connect route', async () => {
		const res = await runCsp(PLAID_CONNECT_ROUTE_ID);
		const csp = res.headers.get('content-security-policy') ?? '';
		expect(csp).toContain('cdn.plaid.com');
		expect(csp).not.toBe(BASE_CSP);
	});

	it('is a no-op when the response has no CSP header (no throw)', async () => {
		const res = await runCsp(PLAID_CONNECT_ROUTE_ID, { csp: null });
		expect(res.headers.get('content-security-policy')).toBeNull();
	});
});

describe('cspHandle — PLAID_ENV fail-safe host selection (CSP-3)', () => {
	it("PLAID_ENV='production' → the production connect-src host", async () => {
		process.env.PLAID_ENV = 'production';
		const csp = (await runCsp(PLAID_CONNECT_ROUTE_ID)).headers.get('content-security-policy') ?? '';
		expect(csp).toContain(PLAID_CONNECT_SRC_PROD);
		expect(csp).not.toContain(PLAID_CONNECT_SRC_SANDBOX);
	});

	it('missing PLAID_ENV → fails safe to the SANDBOX host (never production)', async () => {
		const csp = (await runCsp(PLAID_CONNECT_ROUTE_ID)).headers.get('content-security-policy') ?? '';
		expect(csp).toContain(PLAID_CONNECT_SRC_SANDBOX);
		expect(csp).not.toContain(PLAID_CONNECT_SRC_PROD);
	});

	it("unknown/typo PLAID_ENV ('prod') → fails safe to SANDBOX, not production", async () => {
		process.env.PLAID_ENV = 'prod';
		const csp = (await runCsp(PLAID_CONNECT_ROUTE_ID)).headers.get('content-security-policy') ?? '';
		expect(csp).toContain(PLAID_CONNECT_SRC_SANDBOX);
		expect(csp).not.toContain(PLAID_CONNECT_SRC_PROD);
	});
});
