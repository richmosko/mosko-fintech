// csp.test.ts — unit tests for the ADR-028 per-route CSP logic (RT-28).
//
// These prove the CSP-1..CSP-4 conditions at the PURE-FUNCTION level: no running server,
// no route fixtures. `applyPlaidConnectCsp` is exactly what the hooks.server.ts handle
// calls, so testing it here IS testing the real per-route behavior. CSP-1 (the Sec veto
// condition — non-Plaid routes carry NO Plaid entry) is a real assertion, not a stub.

import { describe, it, expect } from 'vitest';
import {
	applyPlaidConnectCsp,
	widenCspForPlaid,
	parseCsp,
	PLAID_CONNECT_ROUTE_ID,
	PLAID_SCRIPT_SRC,
	PLAID_FRAME_SRC,
	PLAID_CONNECT_SRC_PROD,
	PLAID_CONNECT_SRC_SANDBOX
} from './csp';

// The Plaid API env is now a pure parameter (F/CTO ruling: env-matched connect-src host).

// A representative strict base header as SvelteKit's kit.csp emits it in SSR (nonce mode).
const NONCE = 'r4Nd0mNoNcE';
const BASE_CSP =
	`default-src 'self'; script-src 'self' 'nonce-${NONCE}'; style-src 'self' 'nonce-${NONCE}'; ` +
	`style-src-elem 'self' 'nonce-${NONCE}'; style-src-attr 'none'; img-src 'self' data:; ` +
	`font-src 'self'; connect-src 'self'; frame-src 'self'; object-src 'none'; base-uri 'self'; ` +
	`form-action 'self'; frame-ancestors 'none'`;

const PLAID_TOKENS = ['plaid.com', 'cdn.plaid.com', 'production.plaid.com', 'sandbox.plaid.com'];

describe('CSP-1 — per-route scoping (Sec veto condition)', () => {
	it('returns the base CSP UNCHANGED for a non-Plaid route (identity)', () => {
		const out = applyPlaidConnectCsp('/dashboard', BASE_CSP, { plaidEnv: 'sandbox' });
		expect(out).toBe(BASE_CSP);
	});

	it('a non-Plaid route emits NO Plaid entry of any kind (in either env)', () => {
		for (const plaidEnv of ['sandbox', 'production'] as const) {
			for (const routeId of ['/', '/dashboard', '/accounts', '/accounts/new', '/accounts/[account_id]', null]) {
				const out = applyPlaidConnectCsp(routeId, BASE_CSP, { plaidEnv });
				for (const t of PLAID_TOKENS) expect(out).not.toContain(t);
			}
		}
	});

	it('only the exact Link route ids trigger widening (connect + reauth); children stay strict', () => {
		// Widened: the two exact routes where Plaid Link opens.
		expect(applyPlaidConnectCsp(PLAID_CONNECT_ROUTE_ID, BASE_CSP, { plaidEnv: 'production' })).not.toBe(BASE_CSP);
		expect(applyPlaidConnectCsp('/accounts/connections', BASE_CSP, { plaidEnv: 'production' })).not.toBe(BASE_CSP);
		// NOT widened: the attributes child (no Link SDK) + a look-alike prefix must stay BASE_CSP
		// (exact-match, not startsWith — `/accounts/connect/attributes` must never widen).
		expect(applyPlaidConnectCsp('/accounts/connect/attributes', BASE_CSP, { plaidEnv: 'production' })).toBe(BASE_CSP);
		expect(applyPlaidConnectCsp('/accounts/connections/foo', BASE_CSP, { plaidEnv: 'production' })).toBe(BASE_CSP);
	});
});

describe('CSP-2 — nonce, never unsafe-inline on script-src', () => {
	it('preserves the base nonce and adds NO unsafe-inline to script-src on the connect route', () => {
		const out = applyPlaidConnectCsp(PLAID_CONNECT_ROUTE_ID, BASE_CSP, { plaidEnv: 'production' });
		const scriptSrc = parseCsp(out).get('script-src')!;
		expect(scriptSrc).toContain(`'nonce-${NONCE}'`);
		expect(scriptSrc).not.toContain("'unsafe-inline'");
	});
});

describe('CSP-3 — explicit hosts, no wildcard, env-matched connect-src', () => {
	it('script-src + frame-src admit ONLY the exact cdn.plaid.com path/origin (no wildcard, env-independent)', () => {
		const map = parseCsp(widenCspForPlaid(BASE_CSP, { plaidEnv: 'production' }));
		expect(map.get('script-src')).toContain(PLAID_SCRIPT_SRC);
		expect(map.get('frame-src')).toEqual([PLAID_FRAME_SRC]);
		const all = [...map.values()].flat();
		expect(all).not.toContain('https://*.plaid.com');
		expect(all.some((s) => s.includes('*'))).toBe(false);
	});

	it('production env → connect-src carries production.plaid.com ONLY (never sandbox)', () => {
		const prod = parseCsp(widenCspForPlaid(BASE_CSP, { plaidEnv: 'production' })).get('connect-src')!;
		expect(prod).toEqual(["'self'", PLAID_CONNECT_SRC_PROD]);
		expect(prod).not.toContain(PLAID_CONNECT_SRC_SANDBOX);
	});

	it('sandbox env → connect-src carries sandbox.plaid.com ONLY (never production)', () => {
		// Plaid-official: in Sandbox, Link XHRs target sandbox.plaid.com (env-matched, not both).
		const sb = parseCsp(widenCspForPlaid(BASE_CSP, { plaidEnv: 'sandbox' })).get('connect-src')!;
		expect(sb).toEqual(["'self'", PLAID_CONNECT_SRC_SANDBOX]);
		expect(sb).not.toContain(PLAID_CONNECT_SRC_PROD);
	});
});

describe('CSP-4 — style-src-attr unsafe-inline is the ONLY residual', () => {
	it('sets style-src-attr to unsafe-inline while style-src / style-src-elem stay nonce-gated', () => {
		const map = parseCsp(widenCspForPlaid(BASE_CSP, { plaidEnv: 'production' }));
		expect(map.get('style-src-attr')).toEqual(["'unsafe-inline'"]);
		expect(map.get('style-src')).not.toContain("'unsafe-inline'");
		expect(map.get('style-src-elem')).not.toContain("'unsafe-inline'");
		// The residual does NOT leak to script-src.
		expect(map.get('script-src')).not.toContain("'unsafe-inline'");
	});
});

describe('base directives preserved on the connect route', () => {
	it('keeps default-src / object-src / base-uri / form-action / frame-ancestors from the base', () => {
		const map = parseCsp(widenCspForPlaid(BASE_CSP, { plaidEnv: 'production' }));
		expect(map.get('default-src')).toEqual(["'self'"]);
		expect(map.get('object-src')).toEqual(["'none'"]);
		expect(map.get('base-uri')).toEqual(["'self'"]);
		expect(map.get('form-action')).toEqual(["'self'"]);
		expect(map.get('frame-ancestors')).toEqual(["'none'"]);
	});
});
