// hooks.server.ts — the single Supabase Auth session chokepoint.
//
// Per ADR-015 Decision 1 + ARCH §4 (Auth): this file owns centralized Supabase
// session forwarding + JWT refresh under the `authenticated` tier. Session
// handling is NOT duplicated anywhere else in the app.
//
// Security posture (SELF-181, Sec joint-review — surface:auth):
//  - Uses the ANON key + RLS only. The elevated service-role key is NEVER
//    referenced here (RT-26 confinement — it lives only in the 3 allowlisted
//    endpoints). Auth is the anon+RLS path by design.
//  - `safeGetSession()` validates the JWT via `getUser()` against the Auth
//    server before returning a user. `getSession()` alone reads the cookie
//    WITHOUT verifying the JWT signature (spoofable) and is never used for any
//    authorization-bearing decision. Downstream code authorizes off the
//    validated `user`, and the DB enforces isolation via RLS (`users_id = auth.uid()`).
//  - Refresh-token rotation is Supabase Auth default: getUser()/getSession()
//    refresh as needed and `setAll` writes the rotated cookies back.

import { createServerClient } from '@supabase/ssr';
// `$env/dynamic/public` (NOT static): values are read at container RUNTIME, so
// the build succeeds with no env present and Coolify injects the anon config at
// deploy time (build-once/inject-at-runtime). Still the anon key — never the
// service-role key (RT-26).
import { env } from '$env/dynamic/public';
// Server-only private env (never ships to the browser) — reads PLAID_ENV for the
// per-route Plaid CSP host selection (ADR-028 / CSP-3). Aliased to avoid colliding
// with the public `env` above.
import { env as privateEnv } from '$env/dynamic/private';
import { sequence } from '@sveltejs/kit/hooks';
import { applyPlaidConnectCsp } from '$lib/plaid/csp';
import type { Handle } from '@sveltejs/kit';

// One-time fail-loud guard, memoized: validated at FIRST request (runtime, where
// env is populated) — not at module load (build time, where it is empty). Once
// cached, subsequent requests return the config without re-reading env or
// re-checking, so the guard stays off the per-request hot path.
let cached: { url: string; anonKey: string } | null = null;
function supabaseEnv(): { url: string; anonKey: string } {
	if (cached) return cached;
	const url = env.PUBLIC_SUPABASE_URL;
	const anonKey = env.PUBLIC_SUPABASE_ANON_KEY;
	if (!url || !anonKey) {
		throw new Error(
			'Missing PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY — set them in the container runtime env (see .env.example).'
		);
	}
	cached = { url, anonKey };
	return cached;
}

// Exported for hooks.server.test.ts (safeGetSession identity-normalization proof).
export const authHandle: Handle = async ({ event, resolve }) => {
	const { url, anonKey } = supabaseEnv();
	// Per-request Supabase client, cookie-bound to this request/response cycle.
	event.locals.supabase = createServerClient(url, anonKey, {
		cookies: {
			getAll: () => event.cookies.getAll(),
			setAll: (cookiesToSet) => {
				cookiesToSet.forEach(({ name, value, options }) => {
					event.cookies.set(name, value, { ...options, path: '/' });
				});
			}
		}
	});

	// Validated session helper. Reads the session from the cookie, then verifies
	// the JWT against the Auth server via getUser(). Returns nulls on any
	// validation failure — never a spoofed identity.
	event.locals.safeGetSession = async () => {
		const {
			data: { session }
		} = await event.locals.supabase.auth.getSession();
		if (!session) {
			return { session: null, user: null };
		}

		const {
			data: { user },
			error
		} = await event.locals.supabase.auth.getUser();
		if (error || !user) {
			// JWT failed server-side validation (or no validated user) — treat as
			// unauthenticated. The `!user` arm also narrows `user` to non-null below, so
			// the normalized `session.user` is a genuine validated User, never null.
			return { session: null, user: null };
		}

		// Normalize the session's identity to the getUser()-VALIDATED user. The raw
		// `session` from getSession() carries `session.user` derived from the UNVERIFIED
		// cookie (spoofable); overriding it with the validated `user` means any caller
		// reading `session.user` gets the server-verified identity, never the cookie's.
		return { session: { ...session, user }, user };
	};

	return resolve(event, {
		// Only these Supabase response headers are safe to serialize through SSR.
		filterSerializedResponseHeaders(name) {
			return name === 'content-range' || name === 'x-supabase-api-version';
		}
	});
};

// cspHandle — per-route Plaid CSP widening (ADR-028 / CSP-1 / CSP-3). Sequenced AFTER
// authHandle so it observes the fully-resolved response + the strict CSP header that
// SvelteKit's app-global `kit.csp` already emitted (with its per-response nonce, CSP-2).
//
// For the Plaid connect route ONLY, `applyPlaidConnectCsp` widens that header to the
// ADR-028 blessed set (reusing the same nonce); for EVERY other route it returns the
// base header UNCHANGED, so this hook is a structural no-op elsewhere — that identity
// is the CSP-1 (RT-28) veto guarantee. The connect-src host is matched to the live
// Plaid API tier via the server-side private PLAID_ENV (CSP-3, F/CTO ruling option 2).
// Exported for hooks.server.test.ts (fail-safe PLAID_ENV default + route-scoping proof).
export const cspHandle: Handle = async ({ event, resolve }) => {
	const response = await resolve(event);
	const base = response.headers.get('content-security-policy');
	if (base) {
		// Fail-safe: ANY value other than the exact string 'production' → 'sandbox'. A
		// missing/typo'd/unknown PLAID_ENV admits the SANDBOX host, never production.
		// Mirrors the worker's `z.enum(['sandbox','production']).default('sandbox')`.
		const plaidEnv = privateEnv.PLAID_ENV === 'production' ? 'production' : 'sandbox';
		response.headers.set(
			'content-security-policy',
			applyPlaidConnectCsp(event.route?.id, base, { plaidEnv })
		);
	}
	return response;
};

// The exported chokepoint stays a single `handle` (ADR-015 D1) — now a sequence: auth
// session forwarding first, then the route-scoped CSP widening.
export const handle = sequence(authHandle, cspHandle);
