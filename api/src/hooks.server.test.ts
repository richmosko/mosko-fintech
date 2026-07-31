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

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { authHandle, cspHandle, mfaHandle } from './hooks.server';
import { createServerClient } from '@supabase/ssr';
import {
	PLAID_CONNECT_ROUTE_ID,
	PLAID_CONNECT_SRC_PROD,
	PLAID_CONNECT_SRC_SANDBOX
} from '$lib/plaid/csp';

// authHandle constructs its per-request Supabase client via createServerClient — mock it
// so safeGetSession runs against a fake auth surface with controllable getSession/getUser.
vi.mock('@supabase/ssr', () => ({ createServerClient: vi.fn() }));

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

// ── safeGetSession — SELF-280 #16 unvalidated-session hardening ──────────────────────
//
// safeGetSession validates the JWT via getUser() and returns nulls on failure. THIS
// covers the hardening: on the success path the returned `session.user` must be the
// getUser()-VALIDATED user, NOT the (spoofable) getSession() cookie user — plus the
// preserved null-on-no-session and null-on-getUser-error behavior.

const VALIDATED_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const SPOOFED_UID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

type AuthDoubles = {
	getSession: () => Promise<{ data: { session: unknown } }>;
	getUser: () => Promise<{ data: { user: unknown }; error: unknown }>;
};

// Wire a fake Supabase client into authHandle, run it to install safeGetSession on
// event.locals, and hand the installed helper back. Mirrors the exchange.server.test.ts
// locals-double style; authHandle mutates event.locals before it calls resolve.
async function installSafeGetSession(auth: AuthDoubles) {
	(createServerClient as unknown as ReturnType<typeof vi.fn>).mockReturnValue({ auth });
	const event = {
		route: { id: '/x' },
		cookies: { getAll: () => [], set: () => {} },
		locals: {} as Record<string, unknown>
	} as unknown as Parameters<typeof authHandle>[0]['event'];
	const resolve = (async () => new Response('ok')) as unknown as Parameters<
		typeof authHandle
	>[0]['resolve'];
	await authHandle({ event, resolve } as Parameters<typeof authHandle>[0]);
	return event.locals.safeGetSession as App.Locals['safeGetSession'];
}

describe('safeGetSession — validated-identity normalization (SELF-280)', () => {
	beforeEach(() => {
		process.env.PUBLIC_SUPABASE_URL = 'http://supabase.test';
		process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon-test-key';
	});

	it('spoofed cookie user ≠ getUser() user → returns the VALIDATED user in BOTH user AND session.user', async () => {
		const safeGetSession = await installSafeGetSession({
			// getSession() cookie carries a DIFFERENT (spoofed) user than the Auth server validates.
			getSession: async () => ({
				data: { session: { access_token: 'tok', user: { id: SPOOFED_UID } } }
			}),
			getUser: async () => ({ data: { user: { id: VALIDATED_UID } }, error: null })
		});

		const { session, user } = await safeGetSession();

		// The authorization-bearing identity is the getUser()-validated one.
		expect(user).toEqual({ id: VALIDATED_UID });
		// The hardening: session.user is normalized to the validated user, never the cookie's.
		expect(session?.user).toEqual({ id: VALIDATED_UID });
		expect(session?.user.id).not.toBe(SPOOFED_UID);
		// Non-identity session fields are preserved.
		expect((session as unknown as { access_token: string }).access_token).toBe('tok');
	});

	it('no session → { session: null, user: null }', async () => {
		const safeGetSession = await installSafeGetSession({
			getSession: async () => ({ data: { session: null } }),
			// Must not be consulted, but returning a user proves nulls come from the no-session guard.
			getUser: async () => ({ data: { user: { id: VALIDATED_UID } }, error: null })
		});

		expect(await safeGetSession()).toEqual({ session: null, user: null });
	});

	it('getUser() error → { session: null, user: null } (JWT failed validation)', async () => {
		const safeGetSession = await installSafeGetSession({
			getSession: async () => ({
				data: { session: { access_token: 'tok', user: { id: SPOOFED_UID } } }
			}),
			getUser: async () => ({ data: { user: null }, error: { message: 'invalid JWT' } })
		});

		expect(await safeGetSession()).toEqual({ session: null, user: null });
	});
});

// ── mfaHandle — the fail-CLOSED step-up guard (SELF-291 / Auth-3b Slice 1, N3) ──────
//
// mfaHandle reads event.request.method + event.url + event.locals.{safeGetSession,supabase}
// and delegates the decision to requireStepUp (getAuthenticatorAssuranceLevel). No
// Supabase client is CONSTRUCTED here, so no @supabase/ssr mock is needed — we drive it
// with fully-stubbed locals.
describe('mfaHandle — step-up guard', () => {
	const RESOLVED = new Response('page');

	function makeEvent(opts: {
		method?: string;
		pathname: string;
		search?: string;
		user?: { id: string } | null;
		aal?: { currentLevel: string | null; nextLevel: string | null } | null;
		aalError?: boolean;
	}) {
		const resolve = vi.fn(async () => RESOLVED);
		const getAuthenticatorAssuranceLevel = vi.fn(async () =>
			opts.aalError ? { data: null, error: { message: 'boom' } } : { data: opts.aal, error: null }
		);
		const event = {
			request: { method: opts.method ?? 'GET' },
			url: { pathname: opts.pathname, search: opts.search ?? '' },
			locals: {
				safeGetSession: async () => ({ session: null, user: opts.user ?? null }),
				supabase: { auth: { mfa: { getAuthenticatorAssuranceLevel } } }
			}
		} as unknown as Parameters<typeof mfaHandle>[0]['event'];
		return { event, resolve, getAuthenticatorAssuranceLevel };
	}

	/** Invoke mfaHandle; return {redirected, location} — a thrown 303 redirect is captured. */
	async function run(event: Parameters<typeof mfaHandle>[0]['event'], resolve: () => Promise<Response>) {
		try {
			const res = await mfaHandle({ event, resolve } as Parameters<typeof mfaHandle>[0]);
			return { redirected: false, res, location: null as string | null };
		} catch (e) {
			const r = e as { status?: number; location?: string };
			return { redirected: r.status === 303, res: null, location: r.location ?? null };
		}
	}

	it('passes NON-GET requests through untouched (POST actions/APIs use the DB backstop)', async () => {
		const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
			method: 'POST',
			pathname: '/settings/security',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal2' } // would block if consulted
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
		expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();
	});

	it.each(['/login', '/signup', '/auth/callback', '/mfa/step-up', '/mfa/recover'])(
		'exempts %s (must stay reachable at aal1 — no loop)',
		async (pathname) => {
			const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
				pathname,
				user: { id: 'u1' },
				aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
			});
			const out = await run(event, resolve);
			expect(out.redirected).toBe(false);
			expect(resolve).toHaveBeenCalledOnce();
			expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();
		}
	);

	// ── SELF-288 (Auth-5) password-reset exemption boundary — Sec Mod #1 coverage lock ──
	// F/CTO Option A: /forgot-password stays EXEMPT (public request form, reached
	// unauthenticated); /reset-password is DELIBERATELY NOT exempt so mfaHandle routes an
	// aal1 MFA user through /mfa/step-up (→ aal2) BEFORE the set-password form — the reset
	// then requires email control + 2nd factor (no MFA bypass). These lock BOTH halves of
	// the boundary + the over-match protection, guarding a refactor that either drops the
	// /reset-password step-up (an aal2 bypass) or over-widens /forgot-password's exemption.

	// (a) /forgot-password: EXEMPT — an aal1 MFA user reaches the request form, NO step-up.
	it('(a) exempts /forgot-password for an aal1 MFA user — request form reachable, NO bounce', async () => {
		const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
			pathname: '/forgot-password',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal2' } // verified factor, aal1 → would bounce if NOT exempt
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
		// Exempt short-circuits BEFORE the AAL read — proves the prefix matched, not luck.
		expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();
	});

	// (b) /reset-password: NOT exempt — an aal1 MFA user is BOUNCED to /mfa/step-up (Option A).
	// This is the aal2-non-bypass lock: the set-password page is unreachable at aal1 for an
	// MFA user; they must verify the 2nd factor first.
	it.each(['/reset-password', '/reset-password/foo'])(
		'(b) does NOT exempt %s → an aal1 MFA user bounces to /mfa/step-up (Option A step-up)',
		async (pathname) => {
			const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
				pathname,
				user: { id: 'u1' },
				aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
			});
			const out = await run(event, resolve);
			expect(out.redirected).toBe(true);
			expect(out.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent(pathname)}`);
			expect(getAuthenticatorAssuranceLevel).toHaveBeenCalledOnce(); // AAL read RAN — treated as protected
			expect(resolve).not.toHaveBeenCalled();
		}
	);

	// (b') /reset-password NON-MFA user: aal1/aal1 → requireStepUp 'allow' → renders directly
	// (no regression — non-MFA reset is unchanged by Option A).
	it("(b') /reset-password for a NON-MFA aal1 user renders directly (no step-up)", async () => {
		const { event, resolve } = makeEvent({
			pathname: '/reset-password',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal1' } // no verified factor
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
	});

	// (c) over-match guard: a route that merely SHARES /forgot-password as a substring is NOT
	// exempt — proves the `pathname===p || startsWith(p+'/')` boundary holds (no exemption
	// leaks to a shadowed protected route).
	it.each(['/forgot-password-evil', '/forgot-passwordx'])(
		'(c) over-match guard: %s is NOT exempt → an aal1 MFA user bounces to /mfa/step-up',
		async (pathname) => {
			const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
				pathname,
				user: { id: 'u1' },
				aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
			});
			const out = await run(event, resolve);
			expect(out.redirected).toBe(true);
			expect(out.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent(pathname)}`);
			expect(getAuthenticatorAssuranceLevel).toHaveBeenCalledOnce();
			expect(resolve).not.toHaveBeenCalled();
		}
	);

	it('boundary: an exact-prefix SUBPATH (/forgot-password/foo) stays exempt', async () => {
		const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
			pathname: '/forgot-password/foo',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
		expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();
	});

	it('passes an UNAUTHENTICATED request through (page load handles /login)', async () => {
		const { event, resolve, getAuthenticatorAssuranceLevel } = makeEvent({
			pathname: '/',
			user: null
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
		expect(getAuthenticatorAssuranceLevel).not.toHaveBeenCalled();
	});

	it('ALLOWS a no-factor user through to a protected page (aal1/aal1)', async () => {
		const { event, resolve } = makeEvent({
			pathname: '/',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal1' }
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(false);
		expect(resolve).toHaveBeenCalledOnce();
	});

	it('REDIRECTS a verified-factor aal1 user to /mfa/step-up with the encoded target', async () => {
		const { event, resolve } = makeEvent({
			pathname: '/accounts/abc',
			search: '?x=1',
			user: { id: 'u1' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(true);
		expect(out.location).toBe(
			`/mfa/step-up?redirectTo=${encodeURIComponent('/accounts/abc?x=1')}`
		);
		expect(resolve).not.toHaveBeenCalled();
	});

	it('FAILS CLOSED on an indeterminate AAL read (redirects to step-up)', async () => {
		const { event, resolve } = makeEvent({
			pathname: '/',
			user: { id: 'u1' },
			aalError: true
		});
		const out = await run(event, resolve);
		expect(out.redirected).toBe(true);
		expect(out.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent('/')}`);
		expect(resolve).not.toHaveBeenCalled();
	});
});
