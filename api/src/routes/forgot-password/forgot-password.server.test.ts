// forgot-password.server.test.ts — SELF-288 / Auth-5 AC #1 + #4.
// The headline anti-enumeration proof: the action returns the IDENTICAL outcome whether the
// email is registered, unregistered, or resetPasswordForEmail errored — it NEVER branches
// the response on existence. Plus: rate-limit (per-IP + per-email) → 429; malformed email →
// 400; NO service_role touched; redirectTo routes to /auth/callback?next=/reset-password.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';
import { actions } from './+page.server';
import { __resetRateLimitForTests } from '$lib/server/auth/rateLimit';

function makeEvent(
	fields: Record<string, string>,
	// Loose `Mock` (like the other route tests) so both the success default and the
	// error-returning mocks conform (vitest's Mock<T> is invariant on the return type).
	resetSpy: Mock = vi.fn(async () => ({ data: {}, error: null })),
	ip = '203.0.113.7'
) {
	const request = new Request('http://localhost/forgot-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	const locals = {
		supabase: { auth: { resetPasswordForEmail: resetSpy } }
	};
	const url = new URL('http://localhost/forgot-password');
	const event = {
		request,
		locals,
		url,
		getClientAddress: () => ip
	} as unknown as Parameters<typeof actions.default>[0];
	return { event, resetSpy };
}

beforeEach(() => __resetRateLimitForTests());

describe('POST /forgot-password (anti-enumeration)', () => {
	it('registered email → uniform { done: true }, resetPasswordForEmail called', async () => {
		const { event, resetSpy } = makeEvent({ email: 'real@example.com' });
		const res = await actions.default(event);
		expect(res).toEqual({ done: true });
		expect(resetSpy).toHaveBeenCalledOnce();
		const [, opts] = resetSpy.mock.calls[0];
		expect(opts.redirectTo).toBe(
			'http://localhost/auth/callback?next=%2Freset-password'
		);
	});

	it('unregistered email (GoTrue returns an error) → IDENTICAL { done: true }', async () => {
		// GoTrue erroring must NOT change the response — the anti-enum invariant.
		const erroring = vi.fn(async () => ({ data: {}, error: { message: 'user not found' } }));
		const { event } = makeEvent({ email: 'ghost@example.com' }, erroring);
		const res = await actions.default(event);
		expect(res).toEqual({ done: true }); // byte-identical to the registered case
	});

	it('found vs not-found responses are indistinguishable', async () => {
		const ok = makeEvent({ email: 'a@example.com' }, undefined, '198.51.100.1');
		const err = makeEvent(
			{ email: 'b@example.com' },
			vi.fn(async () => ({ data: {}, error: { message: 'nope' } })),
			'198.51.100.2'
		);
		expect(await actions.default(ok.event)).toEqual(await actions.default(err.event));
	});

	it('email normalized (trim + lowercase) before the GoTrue call', async () => {
		const { event, resetSpy } = makeEvent({ email: '  MixedCase@Example.COM ' });
		await actions.default(event);
		expect(resetSpy.mock.calls[0][0]).toBe('mixedcase@example.com');
	});

	it('malformed email → 400 generic, resetPasswordForEmail never called', async () => {
		const { event, resetSpy } = makeEvent({ email: 'not-an-email' });
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(resetSpy).not.toHaveBeenCalled();
	});

	it('extra field trips .strict() → 400 (mass-assignment fence)', async () => {
		const { event, resetSpy } = makeEvent({ email: 'a@example.com', role: 'admin' });
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(400);
		expect(resetSpy).not.toHaveBeenCalled();
	});
});

describe('POST /forgot-password (rate-limit, AC #4)', () => {
	it('per-email cap (3/hr) → 4th distinct-IP request for same email is 429', async () => {
		const email = 'target@example.com';
		for (let i = 0; i < 3; i++) {
			const { event } = makeEvent({ email }, undefined, `10.0.0.${i}`);
			expect(await actions.default(event)).toEqual({ done: true });
		}
		const { event, resetSpy } = makeEvent({ email }, undefined, '10.0.0.99');
		const res = (await actions.default(event)) as { status: number; data: { rateLimited: boolean } };
		expect(res.status).toBe(429);
		expect(res.data.rateLimited).toBe(true);
		expect(resetSpy).not.toHaveBeenCalled(); // limited BEFORE the GoTrue call
	});

	it('per-IP cap (10/15min) → 11th request from same IP (distinct emails) is 429', async () => {
		const ip = '192.0.2.50';
		for (let i = 0; i < 10; i++) {
			const { event } = makeEvent({ email: `u${i}@example.com` }, undefined, ip);
			expect(await actions.default(event)).toEqual({ done: true });
		}
		const { event } = makeEvent({ email: 'u10@example.com' }, undefined, ip);
		const res = (await actions.default(event)) as { status: number };
		expect(res.status).toBe(429);
	});
});
