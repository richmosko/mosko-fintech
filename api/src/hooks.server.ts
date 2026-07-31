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

import { redirect } from '@sveltejs/kit';
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
import { requireStepUp } from '$lib/server/auth/mfa';
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

// mfaHandle — the fail-CLOSED app-layer step-up guard (SELF-291 / Auth-3b Slice 1, N3).
// Sequenced AFTER authHandle so identity is getUser()-validated and locals.supabase is
// wired. Defense-in-depth OVER the 025 DB aal2 backstop (the real enforcer on the direct
// PostgREST data API) — it stops an aal1 session that HAS a verified factor from
// server-rendering a protected page.
//
// SCOPE — GET page-navigations to NON-exempt routes only:
//   · GET-only: action / API POSTs are covered by the DB backstop (reads+writes clause)
//     AND each action's own safeGetSession guard; redirecting a fetch/POST would be
//     incoherent (a fetch would silently follow a 303 to an HTML page).
//   · Exempt prefixes: the auth flow + the step-up flow itself must stay reachable at
//     aal1, else the guard would loop. '/mfa' covers /mfa/step-up (and the Slice-2
//     /mfa/recover, which must be aal1-reachable). '/auth' covers callback + signout so
//     a stuck user can always sign out. '/forgot-password' is the SELF-288 (Auth-5) reset
//     REQUEST form: reached UNauthenticated (no recovery session yet), so it needs no
//     step-up; exempt so an already-authenticated aal1 user isn't pointlessly bounced from
//     a public form.
//
//     '/reset-password' is DELIBERATELY NOT exempt (F/CTO Option A, SELF-288 QA re-scope):
//     the recovery link lands the user on an aal1 recovery SESSION. For a NON-MFA user
//     requireStepUp → 'allow' and the page renders directly. For an MFA user requireStepUp
//     → 'step-up-required', so THIS guard routes them aal1 → /mfa/step-up?redirectTo=
//     /reset-password → they verify their authenticator → aal2 → return here → the form
//     renders → GoTrue's MFA-sensitive-op gate now PERMITS updateUser at aal2. So password
//     reset for an MFA user requires BOTH email control AND the 2nd factor — no bypass. The
//     earlier exemption (which let an aal1 MFA user reach the form) produced GoTrue's silent
//     aal1-refusal dead-end; removing it is the fix. (A lost-authenticator user is routed to
//     /mfa/step-up, which carries the /mfa/recover recovery-code escape.)
//
// N2/N3 reconciliation: requireStepUp keys off GoTrue AAL (the reconciled source of
// truth for "a verified factor exists"), NOT the stored mfa_policy — so a
// self-enrolled-via-API factor with a stale mfa_policy='none' still steps up (N2a), and
// any indeterminate/error AAL state fails CLOSED to step-up (N3). See $lib/server/auth/mfa.
//
// Exported for hooks.server.test.ts.
const STEP_UP_EXEMPT_PREFIXES = ['/login', '/signup', '/auth', '/mfa', '/forgot-password'];
function isStepUpExempt(pathname: string): boolean {
	return STEP_UP_EXEMPT_PREFIXES.some((p) => pathname === p || pathname.startsWith(p + '/'));
}

export const mfaHandle: Handle = async ({ event, resolve }) => {
	if (event.request.method !== 'GET' || isStepUpExempt(event.url.pathname)) {
		return resolve(event);
	}
	const { user } = await event.locals.safeGetSession();
	// Unauthenticated → let the page's own load() redirect to /login. The guard only
	// governs step-up for an already-authenticated identity.
	if (!user) return resolve(event);

	if ((await requireStepUp(event.locals.supabase)) === 'step-up-required') {
		const target = event.url.pathname + event.url.search;
		throw redirect(303, `/mfa/step-up?redirectTo=${encodeURIComponent(target)}`);
	}
	return resolve(event);
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
// session forwarding first, then the fail-closed step-up guard (which may redirect
// before a protected page renders), then the route-scoped CSP widening on whatever
// response resolves.
export const handle = sequence(authHandle, mfaHandle, cspHandle);
