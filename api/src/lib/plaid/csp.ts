// csp.ts — pure, browser-safe CSP directive logic for the ADR-028 per-route Plaid
// relaxation. NON-server lib (Frontend surface): no secrets, no I/O — just string/data
// transforms. The server hook (hooks.server.ts, Backend) imports `applyPlaidConnectCsp`
// and applies it to the response `content-security-policy` header; this module is where
// the ACTUAL per-route logic lives so it is unit-testable WITHOUT a running server
// (that's what makes the CSP-1 per-route-scoping test — RT-28's veto condition — a real
// assertion instead of a stub).
//
// MECHANISM (why a hook, not SvelteKit `kit.csp` alone):
//   • `kit.csp` (vite.config.ts) is APP-GLOBAL — it emits one strict base policy for
//     every route + manages the per-response nonce (CSP-2). It has NO per-route knob.
//   • In SSR (our case) SvelteKit emits the CSP as a RESPONSE HEADER (not a <meta> tag —
//     meta is prerender-only). So a `handle` hook can read that header post-`resolve`
//     and, ONLY on the Plaid connect route, widen it to the ADR-028 blessed set —
//     reusing the nonce SvelteKit already generated. Header (not meta) ⇒ no intersection
//     trap; the per-route widening is authoritative. This is what satisfies CSP-1.
//
// ADR-028 blessed set (Sec-ratified) — the connect route's target policy. CSP-3 host is
// gated on the Plaid API ENV (F/CTO ruling 2026-07-19, option 2: env-matched, NOT build
// mode — ADR-028 amendment routing to Architect):
//   script-src   'self' 'nonce-<per-response>' https://cdn.plaid.com/link/v2/stable/link-initialize.js
//   style-src    'self' 'nonce-<per-response>'
//   style-src-elem 'self' 'nonce-<per-response>'
//   style-src-attr 'unsafe-inline'                 # CSP-4 vendor-forced residual
//   frame-src    https://cdn.plaid.com             # Link ASSET host — env-independent
//   connect-src  'self' https://<env>.plaid.com    # sandbox.plaid.com | production.plaid.com per PLAID_ENV (CSP-3)

/** Which Plaid API environment the deploy talks to. Mirrors the worker's `PLAID_ENV`. */
export type PlaidEnv = 'sandbox' | 'production';

/** The SvelteKit route id of the Plaid Link onboarding surface (the ONLY route relaxed). */
export const PLAID_CONNECT_ROUTE_ID = '/accounts/connect';

// The exact allowlisted Plaid origins/paths (no wildcard — `*.plaid.com` was REJECTED).
// cdn.plaid.com is the Link ASSET host (script + frame) — the SAME regardless of API env.
export const PLAID_SCRIPT_SRC = 'https://cdn.plaid.com/link/v2/stable/link-initialize.js';
export const PLAID_FRAME_SRC = 'https://cdn.plaid.com';
// connect-src API host is env-matched (CSP-3): exactly ONE host, the one for the live tier.
export const PLAID_CONNECT_SRC_PROD = 'https://production.plaid.com';
export const PLAID_CONNECT_SRC_SANDBOX = 'https://sandbox.plaid.com';
/** The single connect-src API host for a given Plaid env. */
export const PLAID_CONNECT_SRC_BY_ENV: Record<PlaidEnv, string> = {
	sandbox: PLAID_CONNECT_SRC_SANDBOX,
	production: PLAID_CONNECT_SRC_PROD
};

/** True only for the Plaid Link onboarding route — the sole surface ADR-028 relaxes. */
export function isPlaidConnectRoute(routeId: string | null | undefined): boolean {
	return routeId === PLAID_CONNECT_ROUTE_ID;
}

/** Parse a CSP header string into an ordered directive→sources map. */
export function parseCsp(header: string): Map<string, string[]> {
	const map = new Map<string, string[]>();
	for (const part of header.split(';')) {
		const tokens = part.trim().split(/\s+/).filter(Boolean);
		if (tokens.length === 0) continue;
		const [directive, ...sources] = tokens;
		map.set(directive.toLowerCase(), sources);
	}
	return map;
}

/** Serialize a directive→sources map back to a CSP header string. */
export function serializeCsp(map: Map<string, string[]>): string {
	return [...map.entries()]
		.map(([directive, sources]) => (sources.length ? `${directive} ${sources.join(' ')}` : directive))
		.join('; ');
}

/**
 * Widen a base (global, strict) CSP header to the ADR-028 blessed set for the Plaid
 * connect route ONLY. Preserves the base's per-response nonce (reused, never dropped) and
 * every non-Plaid base directive (default-src etc.). Additive/override per directive:
 *   • script-src  ← base + the exact Link initializer path
 *   • frame-src   ← https://cdn.plaid.com (blessed exact; env-independent asset host)
 *   • connect-src ← 'self' + the env-matched API host (sandbox|production per plaidEnv)
 *   • style-src-attr ← 'unsafe-inline' (CSP-4 residual; style-src/-elem stay nonce-gated)
 */
export function widenCspForPlaid(baseCsp: string, opts: { plaidEnv: PlaidEnv }): string {
	const map = parseCsp(baseCsp);

	const scriptSrc = [...(map.get('script-src') ?? ["'self'"])];
	if (!scriptSrc.includes(PLAID_SCRIPT_SRC)) scriptSrc.push(PLAID_SCRIPT_SRC);
	map.set('script-src', scriptSrc);

	map.set('frame-src', [PLAID_FRAME_SRC]);

	// CSP-3 (F/CTO option 2): exactly ONE API host, matched to the live Plaid tier.
	map.set('connect-src', ["'self'", PLAID_CONNECT_SRC_BY_ENV[opts.plaidEnv]]);

	// CSP-4: inline style ATTRIBUTES only (Plaid Link injects them). style-src /
	// style-src-elem stay nonce-gated — the residual does not leak to them.
	map.set('style-src-attr', ["'unsafe-inline'"]);

	return serializeCsp(map);
}

/**
 * Route-scoped entry point the server hook calls. Returns the base CSP UNCHANGED for
 * every route except the Plaid connect route — the CSP-1 guarantee (no Plaid entry, no
 * Plaid nonce-relaxation, ever reaches a non-Plaid/financial surface).
 *
 * @param routeId `event.route?.id` from the SvelteKit hook.
 * @param baseCsp the `content-security-policy` header SvelteKit's kit.csp emitted.
 * @param opts.plaidEnv the live Plaid API env (server-read `PLAID_ENV`) — selects the
 *        single env-matched connect-src host (CSP-3).
 */
export function applyPlaidConnectCsp(
	routeId: string | null | undefined,
	baseCsp: string,
	opts: { plaidEnv: PlaidEnv }
): string {
	if (!isPlaidConnectRoute(routeId)) return baseCsp;
	return widenCspForPlaid(baseCsp, opts);
}
