// plaidConnectCsp.qa.test.ts — QA test hook for RT-28 (Plaid Link CSP allowlist).
//
// STATUS: PENDING — INTENTIONALLY SKIPPED, NOT A FALSE GREEN.
// The CSP config itself (SvelteKit nonce mode + per-route Plaid directive set) is a SEPARATE
// tracked item (#12: "CSP nonce-mode config + RT-28 hook"), gated on ADR-028 ratify and NOT yet
// built. This file is authored NOW so the verification lands in the SAME PR-family the moment the
// CSP config exists — but it is `describe.skip`'d until the Plaid Link connect route actually
// emits CSP headers. When #12 lands: flip `.skip` → live, point BLESSED_CSP at the route's real
// header emission, and un-skip.
//
// It encodes the Sec-blessed minimal directive set + the CSP-1..CSP-4 conditions VERBATIM from
// temp/self212-sec-c6-review.md ("DOC CO-REVIEW — ADR-028"), so the intended assertions are
// pinned and reviewable now, ahead of the config.
//
// RT-28 (MEDIUM, normal RT — NOT a §10 catalogued instance): the Plaid Link connect route's CSP
// must stay (a) PER-ROUTE scoped (never app-global), (b) nonce-based on script-src (never
// 'unsafe-inline'-script), (c) admit ONLY cdn.plaid.com (script/frame) + production.plaid.com
// (connect) — no *.plaid.com wildcard, no sandbox host in a prod build.

import { describe, it, expect } from 'vitest';

// The Sec-blessed minimal set (per-route, Link onboarding surface ONLY). Source of record:
// temp/self212-sec-c6-review.md — "Blessed minimal set" table. Kept as data so the live test
// (post-#12) asserts the route's emitted CSP is a superset of these and NOTHING broader.
export const BLESSED_CSP = {
	'script-src': ["'self'", "'nonce-<per-response>'", 'https://cdn.plaid.com/link/v2/stable/link-initialize.js'],
	'style-src': ["'self'", "'nonce-<per-response>'"],
	'style-src-elem': ["'self'", "'nonce-<per-response>'"],
	'style-src-attr': ["'unsafe-inline'"], // vendor-forced residual (CSP-4), documented in SECURITY §4.2
	'frame-src': ['https://cdn.plaid.com'],
	'connect-src': ["'self'", 'https://production.plaid.com'] // sandbox.plaid.com in non-prod builds ONLY
	// default-src stays app base 'self'; img-src NOT required.
} as const;

// The forbidden shapes — the regressions RT-28 exists to catch.
export const CSP_FORBIDDEN = {
	scriptUnsafeInline: "'unsafe-inline'", // never on script-src (CSP-2)
	plaidWildcard: 'https://*.plaid.com', // never (CSP-3)
	sandboxHostInProd: 'https://sandbox.plaid.com' // absent from a prod CSP (CSP-3)
} as const;

describe.skip('RT-28 — Plaid Link connect-route CSP allowlist (PENDING #12 — CSP config not yet built)', () => {
	// When #12 lands, replace this with the route's real CSP header/meta emission.
	// e.g. const csp = parseCsp(await loadPlaidConnectRouteCspHeader());

	it('CSP-1: the Plaid relaxations are PER-ROUTE — the app-global CSP carries NONE of them', () => {
		// Assert: fetching a NON-Plaid route (e.g. /dashboard) emits a CSP WITHOUT any plaid.com
		// entry and WITHOUT nonce-relaxations added for Plaid. App-global relaxation = fail.
		expect(true).toBe(true);
	});

	it('CSP-2: script-src uses a per-response nonce, NEVER \'unsafe-inline\'', () => {
		// Assert: emitted script-src contains a nonce token and does NOT contain 'unsafe-inline'.
		expect(BLESSED_CSP['script-src']).not.toContain(CSP_FORBIDDEN.scriptUnsafeInline);
	});

	it('CSP-3: connect-src is explicit production.plaid.com — never *.plaid.com, never sandbox in prod', () => {
		expect(BLESSED_CSP['connect-src']).toContain('https://production.plaid.com');
		expect(BLESSED_CSP['connect-src']).not.toContain(CSP_FORBIDDEN.plaidWildcard);
		expect(BLESSED_CSP['connect-src']).not.toContain(CSP_FORBIDDEN.sandboxHostInProd);
	});

	it('CSP-3: script-src + frame-src admit ONLY cdn.plaid.com (no wildcard)', () => {
		expect(BLESSED_CSP['frame-src']).toEqual(['https://cdn.plaid.com']);
		expect(BLESSED_CSP['script-src']).toContain('https://cdn.plaid.com/link/v2/stable/link-initialize.js');
		for (const v of BLESSED_CSP['script-src']) expect(v).not.toBe(CSP_FORBIDDEN.plaidWildcard);
	});

	it('CSP-4: style-src-attr \'unsafe-inline\' is the ONLY vendor-forced residual (documented)', () => {
		expect(BLESSED_CSP['style-src-attr']).toEqual(["'unsafe-inline'"]);
		// script-src does not inherit the residual.
		expect(BLESSED_CSP['script-src']).not.toContain("'unsafe-inline'");
	});
});
