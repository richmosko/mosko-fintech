// reset-password.server.test.ts — SELF-288 / Auth-5 AC #1.
// Proves: load() bounces a no-session visitor to /forgot-password; the action requires the
// recovery session, validates via .strict() (min-8 + confirm-match), calls updateUser with
// the SESSION identity, then signOut()s and redirects to /login?reset=success. The signOut
// (aal2-non-bypass proof) and the identity-from-session (never body) are asserted.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';
import { load, actions } from './+page.server';
import { requireStepUp } from '$lib/server/auth/mfa';

// The action gates on requireStepUp (Option A defense-in-depth). Mock it: default 'allow'
// (non-MFA, or an MFA user already stepped up to aal2); override to 'step-up-required' for
// the aal1-MFA POST case.
vi.mock('$lib/server/auth/mfa', () => ({ requireStepUp: vi.fn(async () => 'allow') }));

beforeEach(() => {
	vi.mocked(requireStepUp).mockResolvedValue('allow');
});

const USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', email: 'u@example.com' };

function makeLoadEvent(user: { id: string } | null) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }) };
	return { locals } as unknown as Parameters<typeof load>[0];
}

function makeActionEvent(
	fields: Record<string, string>,
	user: { id: string } | null,
	// Loose `Mock` so the error-returning updateUser mock also conforms.
	updateSpy: Mock = vi.fn(async () => ({ data: { user }, error: null })),
	signOutSpy: Mock = vi.fn(async () => ({ error: null }))
) {
	const request = new Request('http://localhost/reset-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: { auth: { updateUser: updateSpy, signOut: signOutSpy } }
	};
	const event = { request, locals } as unknown as Parameters<typeof actions.default>[0];
	return { event, updateSpy, signOutSpy };
}

async function run(fn: () => unknown) {
	try {
		return { kind: 'return' as const, value: await fn() };
	} catch (e) {
		return { kind: 'throw' as const, value: e as { status?: number; location?: string } };
	}
}

describe('load /reset-password', () => {
	it('no recovery session → redirect to /forgot-password?expired=1', async () => {
		const res = await run(() => load(makeLoadEvent(null)));
		expect(res.kind).toBe('throw');
		if (res.kind !== 'throw') throw new Error('expected redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe('/forgot-password?expired=1');
	});

	it('recovery session present → renders (ready)', async () => {
		const res = await run(() => load(makeLoadEvent(USER)));
		expect(res).toEqual({ kind: 'return', value: { ready: true } });
	});
});

describe('POST /reset-password', () => {
	it('valid new password (step-up allowed) → updateUser + signOut + redirect /login?reset=success', async () => {
		const { event, updateSpy, signOutSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'newpassword123' },
			USER
		);
		const res = await run(() => actions.default(event));
		expect(updateSpy).toHaveBeenCalledWith({ password: 'newpassword123' });
		// updateUser payload carries NO user id — identity is the session's, never the body.
		expect(signOutSpy).toHaveBeenCalledOnce(); // aal2-non-bypass: recovery session invalidated
		expect(res.kind).toBe('throw');
		if (res.kind !== 'throw') throw new Error('expected redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe('/login?reset=success');
	});

	it('MFA user still aal1 at POST (step-up-required) → 303 /mfa/step-up, updateUser never called', async () => {
		// Option A defense-in-depth: mfaHandle guards the GET render, but a scripted/lapsed
		// aal1 POST by an MFA user must ALSO be funnelled to step-up (not a bare GoTrue refusal).
		vi.mocked(requireStepUp).mockResolvedValueOnce('step-up-required');
		const { event, updateSpy, signOutSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'newpassword123' },
			USER
		);
		const res = await run(() => actions.default(event));
		expect(res.kind).toBe('throw'); // redirect
		if (res.kind !== 'throw') throw new Error('expected redirect');
		expect(res.value.status).toBe(303);
		expect(res.value.location).toBe(`/mfa/step-up?redirectTo=${encodeURIComponent('/reset-password')}`);
		expect(updateSpy).not.toHaveBeenCalled(); // gated BEFORE the password change
		expect(signOutSpy).not.toHaveBeenCalled();
	});

	it('no recovery session at submit → 401, updateUser never called', async () => {
		const { event, updateSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'newpassword123' },
			null
		);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(401);
		expect(updateSpy).not.toHaveBeenCalled();
	});

	it('password too short → 400, updateUser never called', async () => {
		const { event, updateSpy } = makeActionEvent({ password: 'short', confirm: 'short' }, USER);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(updateSpy).not.toHaveBeenCalled();
	});

	it('confirm mismatch → 400, updateUser never called', async () => {
		const { event, updateSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'different12345' },
			USER
		);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(updateSpy).not.toHaveBeenCalled();
	});

	it('extra field trips .strict() → 400 (mass-assignment fence)', async () => {
		const { event, updateSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'newpassword123', email: 'attacker@evil.com' },
			USER
		);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(updateSpy).not.toHaveBeenCalled();
	});

	it('GoTrue updateUser error → 400 generic, no signOut/redirect', async () => {
		const failing = vi.fn(async () => ({ data: { user: null }, error: { message: 'weak' } }));
		const { event, signOutSpy } = makeActionEvent(
			{ password: 'newpassword123', confirm: 'newpassword123' },
			USER,
			failing
		);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(signOutSpy).not.toHaveBeenCalled();
	});
});
