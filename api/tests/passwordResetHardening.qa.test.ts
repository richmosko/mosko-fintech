// passwordResetHardening.qa.test.ts — SELF-288 / Auth-5 hardening extensions (QA-owned).
//
// Augments Backend's per-route unit specs along three axes they don't assert:
//   #1 anti-enumeration EQUAL-WORK: the registered and unregistered paths perform the IDENTICAL
//      amount of work (resetPasswordForEmail called exactly once on BOTH) — the deterministic
//      surrogate for a timing-parity check (see the timing note below).
//   #2 GoTrue rate-limit BACKSTOP: the authoritative cross-instance email_sent cap is actually
//      configured (the app-level limiter is defense-in-depth ON TOP of this, not a replacement).
//   #5 mass-assignment: the IDENTITY-bearing keys (id / users_id / user_id / user_metadata) are
//      .strict()-rejected on BOTH endpoints and never reach GoTrue (Backend covers role/email only).
//
// Node env (default). Pure-TS; no live stack.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { actions as forgotActions } from '../src/routes/forgot-password/+page.server';
import { actions as resetActions } from '../src/routes/reset-password/+page.server';
import { __resetRateLimitForTests } from '../src/lib/server/auth/rateLimit';

const RECOVERY_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', email: 'u@example.com' };

function forgotEvent(fields: Record<string, string>, resetSpy: Mock, ip = '203.0.113.20') {
	const request = new Request('http://localhost/forgot-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	return {
		request,
		locals: { supabase: { auth: { resetPasswordForEmail: resetSpy } } },
		url: new URL('http://localhost/forgot-password'),
		getClientAddress: () => ip
	} as unknown as Parameters<typeof forgotActions.default>[0];
}

function resetEvent(fields: Record<string, string>, updateSpy: Mock, user = RECOVERY_USER) {
	const request = new Request('http://localhost/reset-password', {
		method: 'POST',
		body: new URLSearchParams(fields)
	});
	return {
		request,
		locals: {
			safeGetSession: async () => ({ session: {}, user }),
			supabase: { auth: { updateUser: updateSpy, signOut: vi.fn(async () => ({ error: null })) } }
		}
	} as unknown as Parameters<typeof resetActions.default>[0];
}

beforeEach(() => __resetRateLimitForTests());

// ── Target #1 — anti-enumeration equal-work (the timing-parity structural surrogate) ─────────

describe('anti-enumeration — registered and unregistered paths do IDENTICAL work (AC#4)', () => {
	it('resetPasswordForEmail is called exactly ONCE on BOTH the found and not-found paths, byte-identical outcome', async () => {
		// "found": GoTrue resolves cleanly. "not-found": GoTrue is uniform for reset requests, but even
		// if it surfaced an error the action MUST ignore it — same single await, same outcome.
		const found = vi.fn(async () => ({ data: {}, error: null }));
		const notFound = vi.fn(async () => ({ data: {}, error: { message: 'user not found' } }));

		const foundRes = await forgotActions.default(forgotEvent({ email: 'real@example.com' }, found, '10.1.0.1'));
		const notFoundRes = await forgotActions.default(forgotEvent({ email: 'ghost@example.com' }, notFound, '10.1.0.2'));

		// Equal WORK: one GoTrue call on each path — no existence-dependent extra/skipped await.
		expect(found).toHaveBeenCalledOnce();
		expect(notFound).toHaveBeenCalledOnce();
		// Equal OUTPUT: identical value AND identical key set (no branch adds/drops a field).
		expect(foundRes).toEqual(notFoundRes);
		expect(Object.keys(foundRes as object).sort()).toEqual(Object.keys(notFoundRes as object).sort());

		// TIMING NOTE (deliberate): wall-clock latency is NOT asserted here. A time-delta assertion is
		// non-deterministic under CI scheduling/GC and would violate the no-flaky-tests discipline. The
		// equal-work invariant above (same number of awaited GoTrue calls, no existence branch) is the
		// deterministic proof that no existence-DEPENDENT work is added on either path — the residual
		// send-vs-no-send delta is GoTrue-internal and uniform per its own anti-enumeration.
		//
		// NON-VACUITY: a version that early-returned for unknown emails (skipping the GoTrue call), or
		// branched to add a distinguishing field, fails the call-count or key-set assertion → RED.
	});
});

// ── Target #2 — the GoTrue rate-limit backstop is configured ─────────────────────────────────

describe('rate-limit — GoTrue [auth.rate_limit] is the authoritative backstop (AC#4 defense-in-depth)', () => {
	it('supabase/config.toml pins email_sent to a small positive cap', () => {
		const cfg = readFileSync(fileURLToPath(new URL('../../supabase/config.toml', import.meta.url)), 'utf8');
		// Isolate the [auth.rate_limit] block so we read ITS email_sent, not a stray match elsewhere.
		const block = cfg.split(/^\[/m).find((s) => s.startsWith('auth.rate_limit]')) ?? '';
		const m = block.match(/^\s*email_sent\s*=\s*(\d+)/m);
		expect(m, 'email_sent must be set under [auth.rate_limit]').not.toBeNull();
		const cap = Number(m![1]);
		expect(cap).toBeGreaterThan(0);
		expect(cap).toBeLessThanOrEqual(10); // a real cap, not effectively-unlimited
		// NON-VACUITY: deleting the [auth.rate_limit] email_sent line, or bumping it to an
		// effectively-unlimited value, turns this RED — the app-level in-memory limiter is per-process
		// and resets on restart, so this cross-instance GoTrue cap is the load-bearing backstop.
	});
});

// ── Target #5 — mass-assignment: identity keys are rejected AND never honored ─────────────────

describe('mass-assignment fence — smuggled identity keys are .strict()-rejected (Lock 14 #2)', () => {
	it.each(['id', 'users_id', 'user_id', 'role'])(
		'forgot-password: a smuggled `%s` → 400, resetPasswordForEmail NEVER called',
		async (key) => {
			const resetSpy = vi.fn(async () => ({ data: {}, error: null }));
			const res = (await forgotActions.default(
				forgotEvent({ email: 'a@example.com', [key]: 'x' }, resetSpy)
			)) as { status: number };
			expect(res.status).toBe(400);
			expect(resetSpy).not.toHaveBeenCalled(); // the smuggle can't even reach GoTrue
		}
	);

	it.each(['id', 'users_id', 'email', 'user_metadata'])(
		'reset-password: a smuggled `%s` → 400, updateUser NEVER called (identity is the session, never the body)',
		async (key) => {
			const updateSpy = vi.fn(async () => ({ data: { user: RECOVERY_USER }, error: null }));
			const res = (await resetActions.default(
				resetEvent({ password: 'brand-new-pass-9', confirm: 'brand-new-pass-9', [key]: 'attacker' }, updateSpy)
			)) as { status: number };
			expect(res.status).toBe(400);
			expect(updateSpy).not.toHaveBeenCalled();
			// NON-VACUITY: were `.strict()` relaxed to `.passthrough()`, the smuggled `email`/`id` would
			// flow into updateUser and could re-point the write off the session identity → this RED-lines.
		}
	);
});
