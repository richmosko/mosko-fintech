// passwordResetFlow.qa.test.ts — SELF-288 / Auth-5 password-reset COMPOSITION battery (QA-owned).
//
// Backend's per-route unit specs (forgot-password.server.test / reset-password.server.test) drive
// each handler in isolation with a mocked GoTrue. THIS file is the QA complement: it composes the
// REAL handlers end-to-end — forgot action → /auth/callback GET exchange → reset load+action → the
// mfaHandle step-up guard — mocking ONLY the GoTrue boundary. It proves the WIRING between the four
// surfaces holds (the seam no single-route unit test can see), and it proves the aal2 non-bypass at
// the guard layer (target #4), not just "signOut was called".
//
// Node env (default). No live stack — the true browser+Mailpit E2E is passwordResetRecovery.dbit.
//
// NON-VACUITY is called out per test: each key assertion names the real regression that turns it RED.

import { describe, it, expect, vi } from 'vitest';
import type { Mock } from 'vitest';
import { actions as forgotActions } from '../src/routes/forgot-password/+page.server';
import { GET as callbackGET } from '../src/routes/auth/callback/+server';
import { load as resetLoad, actions as resetActions } from '../src/routes/reset-password/+page.server';
import { mfaHandle } from '../src/hooks.server';
import { __resetRateLimitForTests } from '../src/lib/server/auth/rateLimit';

const RECOVERY_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', email: 'recover@example.com' };

/**
 * An AAL read stub for the reset action's requireStepUp gate (F/CTO Option A: the action reads
 * getAuthenticatorAssuranceLevel and funnels an un-stepped-up MFA user to /mfa/step-up). aal1/aal1 =
 * non-MFA → 'allow'; aal2/aal2 = MFA already stepped up → 'allow'; aal1/aal2 = MFA owed → 'step-up-required'.
 */
function aalStub(currentLevel: string, nextLevel: string) {
	return {
		getAuthenticatorAssuranceLevel: async () => ({ data: { currentLevel, nextLevel }, error: null })
	};
}

/** Capture a thrown SvelteKit redirect (or return value) uniformly. */
async function capture(fn: () => unknown) {
	try {
		return { kind: 'return' as const, value: await fn() };
	} catch (e) {
		return { kind: 'throw' as const, value: e as { status?: number; location?: string } };
	}
}

// ── event builders (mirror the existing route-test doubles) ──────────────────────────────────

function forgotEvent(fields: Record<string, string>, resetSpy: Mock, ip = '203.0.113.9') {
	const request = new Request('http://localhost/forgot-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const event = {
		request,
		locals: { supabase: { auth: { resetPasswordForEmail: resetSpy } } },
		url: new URL('http://localhost/forgot-password'),
		getClientAddress: () => ip
	} as unknown as Parameters<typeof forgotActions.default>[0];
	return event;
}

function callbackEvent(rawUrl: string, exchangeSpy: Mock) {
	return {
		url: new URL(rawUrl),
		locals: { supabase: { auth: { exchangeCodeForSession: exchangeSpy } } }
	} as unknown as Parameters<typeof callbackGET>[0];
}

function resetActionEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	auth: Record<string, unknown>
) {
	const request = new Request('http://localhost/reset-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const event = {
		request,
		locals: { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase: { auth } }
	} as unknown as Parameters<typeof resetActions.default>[0];
	return event;
}

/** Drive the REAL mfaHandle with a fully-stubbed session; return {redirected, location}. */
async function runMfaGuard(opts: {
	pathname: string;
	method?: string;
	user: { id: string } | null;
	aal: { currentLevel: string | null; nextLevel: string | null } | null;
}) {
	const resolve = vi.fn(async () => new Response('page'));
	const event = {
		request: { method: opts.method ?? 'GET' },
		url: { pathname: opts.pathname, search: '' },
		locals: {
			safeGetSession: async () => ({ session: null, user: opts.user }),
			supabase: {
				auth: { mfa: { getAuthenticatorAssuranceLevel: vi.fn(async () => ({ data: opts.aal, error: null })) } }
			}
		}
	} as unknown as Parameters<typeof mfaHandle>[0]['event'];
	const out = await capture(() => mfaHandle({ event, resolve } as Parameters<typeof mfaHandle>[0]));
	return {
		redirected: out.kind === 'throw' && out.value.status === 303,
		location: out.kind === 'throw' ? out.value.location ?? null : null,
		resolveCalled: resolve.mock.calls.length > 0
	};
}

// ── Target #3 (integration-level): the four surfaces compose into one flow ───────────────────

describe('password-reset full-flow composition (real handlers; browser+Mailpit E2E is the .dbit leg)', () => {
	it('forgot → callback code-exchange → reset load+action lands on /login?reset=success', async () => {
		__resetRateLimitForTests();

		// 1) forgot action issues the reset and hands GoTrue a redirectTo pointing at /auth/callback.
		const resetSpy: Mock = vi.fn(async () => ({ data: {}, error: null }));
		const forgotRes = await forgotActions.default(forgotEvent({ email: 'recover@example.com' }, resetSpy));
		expect(forgotRes).toEqual({ done: true });
		const redirectTo: string = resetSpy.mock.calls[0][1].redirectTo;
		// The `next` the forgot action asked the callback to honor — the wiring contract under test.
		const nextParam = new URL(redirectTo).searchParams.get('next');
		expect(nextParam).toBe('/reset-password');

		// 2) the recovery link lands on /auth/callback with a good code → exchange → 303 to `next`.
		const exchangeSpy = vi.fn(async () => ({ error: null }));
		const cbUrl = `${new URL(redirectTo).origin}${new URL(redirectTo).pathname}?code=good-recovery-code&next=${encodeURIComponent(nextParam!)}`;
		const cb = await capture(() => callbackGET(callbackEvent(cbUrl, exchangeSpy)));
		expect(exchangeSpy).toHaveBeenCalledWith('good-recovery-code');
		expect(cb.kind).toBe('throw');
		if (cb.kind !== 'throw') throw new Error('callback must redirect');
		expect(cb.value.status).toBe(303);
		// Continuity: the callback bounces to exactly the reset route the forgot action targeted.
		expect(cb.value.location).toBe('/reset-password');

		// 3) reset load sees the minted recovery session → renders.
		const loadRes = await resetLoad({
			locals: { safeGetSession: async () => ({ session: {}, user: RECOVERY_USER }) }
		} as unknown as Parameters<typeof resetLoad>[0]);
		expect(loadRes).toEqual({ ready: true });

		// 4) reset action gates on AAL (Option A) then sets the password on the SESSION identity →
		//    signOut → /login?reset=success. A NON-MFA recovery session reads aal1/aal1 → 'allow'.
		const updateSpy = vi.fn(async () => ({ data: { user: RECOVERY_USER }, error: null }));
		const signOutSpy = vi.fn(async () => ({ error: null }));
		const action = await capture(() =>
			resetActions.default(
				resetActionEvent(
					{ password: 'brand-new-pass-9', confirm: 'brand-new-pass-9' },
					RECOVERY_USER,
					{ updateUser: updateSpy, signOut: signOutSpy, mfa: aalStub('aal1', 'aal1') }
				)
			)
		);
		expect(updateSpy).toHaveBeenCalledWith({ password: 'brand-new-pass-9' });
		expect(signOutSpy).toHaveBeenCalledOnce();
		expect(action.kind).toBe('throw');
		if (action.kind !== 'throw') throw new Error('reset must redirect');
		expect(action.value.status).toBe(303);
		expect(action.value.location).toBe('/login?reset=success');

		// 4b) MFA HAPPY PATH (Option A completeness): an MFA user who has STEPPED UP reads aal2/aal2 →
		//     'allow' → the reset COMPLETES identically. (The un-stepped-up aal1 case is the non-bypass,
		//     asserted in the aal2 describe below.)
		const updateSpy2 = vi.fn(async () => ({ data: { user: RECOVERY_USER }, error: null }));
		const signOutSpy2 = vi.fn(async () => ({ error: null }));
		const mfaAction = await capture(() =>
			resetActions.default(
				resetActionEvent(
					{ password: 'brand-new-pass-9', confirm: 'brand-new-pass-9' },
					RECOVERY_USER,
					{ updateUser: updateSpy2, signOut: signOutSpy2, mfa: aalStub('aal2', 'aal2') }
				)
			)
		);
		expect(updateSpy2).toHaveBeenCalledWith({ password: 'brand-new-pass-9' });
		expect(mfaAction.kind).toBe('throw');
		if (mfaAction.kind !== 'throw') throw new Error('MFA stepped-up reset must redirect');
		expect((mfaAction.value as { location?: string }).location).toBe('/login?reset=success');
		// NON-VACUITY: if the forgot action stopped routing `next` to /reset-password, or the callback's
		// safeRedirectPath rejected it, step 2's location assertion breaks. If the AAL gate mis-fired for
		// a stepped-up (aal2) user, updateSpy2 goes uncalled and 4b lands /mfa/step-up instead → RED.
	});

	it('inversion — a bad/expired recovery code never reaches the reset page (→ /login?error=confirmation)', async () => {
		const exchangeSpy = vi.fn(async () => ({ error: { message: 'invalid or expired' } }));
		const cbUrl = 'http://localhost/auth/callback?code=stale&next=%2Freset-password';
		const cb = await capture(() => callbackGET(callbackEvent(cbUrl, exchangeSpy)));
		expect(cb.kind).toBe('throw');
		if (cb.kind !== 'throw') throw new Error('callback must redirect');
		expect(cb.value.status).toBe(303);
		expect(cb.value.location).toBe('/login?error=confirmation');
		// NON-VACUITY: proves the reset page is reachable ONLY via a valid recovery exchange. A callback
		// that fell through to `next` on a failed exchange would hand an UNAUTHENTICATED visitor the
		// set-password page — this asserts it does not.
	});
});

// ── Target #4 (critical): the reset can never substitute for the 2nd factor ──────────────────

describe('aal2 non-bypass — reset touches no factor; post-reset nav still steps up', () => {
	it('the reset action READS AAL to gate but MUTATES no factor (mints no aal2 — Option A)', async () => {
		const updateSpy = vi.fn(async () => ({ data: { user: RECOVERY_USER }, error: null }));
		const signOutSpy = vi.fn(async () => ({ error: null }));
		// The factor-MUTATION surface (the aal2-CONFERRING calls) — reset must touch NONE of these.
		const mutations = {
			enroll: vi.fn(),
			challenge: vi.fn(),
			verify: vi.fn(),
			unenroll: vi.fn(),
			challengeAndVerify: vi.fn()
		};
		// getAuthenticatorAssuranceLevel is a READ Option A intentionally makes to GATE; a read confers
		// nothing. Stub it to a non-MFA level ('allow') so updateUser proceeds.
		const getAAL = vi.fn(async () => ({ data: { currentLevel: 'aal1', nextLevel: 'aal1' }, error: null }));
		await capture(() =>
			resetActions.default(
				resetActionEvent(
					{ password: 'brand-new-pass-9', confirm: 'brand-new-pass-9' },
					RECOVERY_USER,
					{ updateUser: updateSpy, signOut: signOutSpy, mfa: { ...mutations, getAuthenticatorAssuranceLevel: getAAL } }
				)
			)
		);
		expect(updateSpy).toHaveBeenCalledWith({ password: 'brand-new-pass-9' });
		expect(signOutSpy).toHaveBeenCalledOnce();
		expect(getAAL).toHaveBeenCalled(); // Option A DOES read AAL to gate (defense-in-depth)
		for (const [name, spy] of Object.entries(mutations)) {
			expect(spy, `reset must not call mfa.${name} (no factor mutation, no aal2 conferral)`).not.toHaveBeenCalled();
		}
		// NON-VACUITY: if a future change added an mfa.enroll/challenge/verify to the reset path (trying to
		// mint or move a factor during recovery), one of these RED-lines. The reset stays a password-only
		// op that READS AAL but never CONFERS it — so it can never substitute for the 2nd factor.
	});

	it('an MFA user who has NOT stepped up (aal1) is funnelled to /mfa/step-up — updateUser never called', async () => {
		// The Option-A action-level non-bypass: the POST re-runs requireStepUp (mfaHandle only guards GET).
		const updateSpy = vi.fn(async () => ({ data: { user: RECOVERY_USER }, error: null }));
		const signOutSpy = vi.fn(async () => ({ error: null }));
		const action = await capture(() =>
			resetActions.default(
				resetActionEvent(
					{ password: 'brand-new-pass-9', confirm: 'brand-new-pass-9' },
					RECOVERY_USER,
					// aal1 WITH a verified factor available (nextLevel aal2) → requireStepUp 'step-up-required'.
					{ updateUser: updateSpy, signOut: signOutSpy, mfa: aalStub('aal1', 'aal2') }
				)
			)
		);
		expect(action.kind).toBe('throw');
		if (action.kind !== 'throw') throw new Error('un-stepped-up MFA reset must redirect to step-up');
		expect(action.value.status).toBe(303);
		expect(action.value.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent('/reset-password')}`);
		expect(updateSpy).not.toHaveBeenCalled(); // no password change without the 2nd factor
		expect(signOutSpy).not.toHaveBeenCalled();
		// NON-VACUITY: if the gate were removed (or 'allow'ed an aal1 MFA user), updateUser would be
		// reached → RED. The recovery link alone (aal1) can never change an MFA user's password; the 2nd
		// factor via /mfa/step-up is required. This is the aal2-non-bypass at the reset-action layer.
	});

	it("after reset+signOut, an MFA-enrolled user's next protected GET still redirects to /mfa/step-up", async () => {
		// The recovery session minted no aal2 and touched no factor (proven above). So the post-reset
		// fresh login is aal1 WITH a verified factor available (currentLevel aal1 / nextLevel aal2).
		const out = await runMfaGuard({
			pathname: '/',
			user: { id: 'mfa-user' },
			aal: { currentLevel: 'aal1', nextLevel: 'aal2' }
		});
		expect(out.redirected).toBe(true);
		expect(out.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent('/')}`);
		expect(out.resolveCalled).toBe(false);
	});

	it('inversion — the guard hinges on the AAL the reset provably did not change (an aal2 session is let through)', async () => {
		// Had the reset somehow elevated the session to aal2, mfaHandle would ALLOW the protected nav.
		// This makes the prior assertion non-vacuous: the redirect there is caused by the session still
		// being aal1 — exactly the state a password-only reset leaves behind.
		const out = await runMfaGuard({
			pathname: '/',
			user: { id: 'mfa-user' },
			aal: { currentLevel: 'aal2', nextLevel: 'aal2' }
		});
		expect(out.redirected).toBe(false);
		expect(out.resolveCalled).toBe(true);
	});
});
