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
// ADR-028 blessed set (Sec-ratified, verbatim) — the connect route's target policy:
//   script-src   'self' 'nonce-<per-response>' https://cdn.plaid.com/link/v2/stable/link-initialize.js
//   style-src    'self' 'nonce-<per-response>'
//   style-src-elem 'self' 'nonce-<per-response>'
//   style-src-attr 'unsafe-inline'                 # CSP-4 vendor-forced residual
//   frame-src    https://cdn.plaid.com
//   connect-src  'self' https://production.plaid.com   # + sandbox host in NON-prod only (CSP-3)

/** The SvelteKit route id of the Plaid Link onboarding surface (the ONLY route relaxed). */
export const PLAID_CONNECT_ROUTE_ID = '/accounts/connect';

// The exact allowlisted Plaid origins/paths (no wildcard — `*.plaid.com` was REJECTED).
export const PLAID_SCRIPT_SRC = 'https://cdn.plaid.com/link/v2/stable/link-initialize.js';
export const PLAID_FRAME_SRC = 'https://cdn.plaid.com';
export const PLAID_CONNECT_SRC_PROD = 'https://production.plaid.com';
export const PLAID_CONNECT_SRC_SANDBOX = 'https://sandbox.plaid.com';

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
 *   • frame-src   ← https://cdn.plaid.com (blessed exact)
 *   • connect-src ← 'self' + production.plaid.com (+ sandbox host when includeSandbox)
 *   • style-src-attr ← 'unsafe-inline' (CSP-4 residual; style-src/-elem stay nonce-gated)
 */
export function widenCspForPlaid(baseCsp: string, opts: { includeSandbox: boolean }): string {
	const map = parseCsp(baseCsp);

	const scriptSrc = [...(map.get('script-src') ?? ["'self'"])];
	if (!scriptSrc.includes(PLAID_SCRIPT_SRC)) scriptSrc.push(PLAID_SCRIPT_SRC);
	map.set('script-src', scriptSrc);

	map.set('frame-src', [PLAID_FRAME_SRC]);

	const connectSrc = ["'self'", PLAID_CONNECT_SRC_PROD];
	if (opts.includeSandbox) connectSrc.push(PLAID_CONNECT_SRC_SANDBOX);
	map.set('connect-src', connectSrc);

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
 * @param opts.includeSandbox add sandbox.plaid.com to connect-src (NON-prod builds only).
 */
export function applyPlaidConnectCsp(
	routeId: string | null | undefined,
	baseCsp: string,
	opts: { includeSandbox: boolean }
): string {
	if (!isPlaidConnectRoute(routeId)) return baseCsp;
	return widenCspForPlaid(baseCsp, opts);
}
