// auth.test.ts — SELF-285 auth schema + helper + action-fence coverage (node env).
//
// Two layers:
//  1. Pure schema/helper units — loginSchema, signupSchema, safeRedirectPath.
//  2. Action-fence integration — the Sec-critical properties: generic error on bad
//     credentials (enumeration fence), generic error on signup failure, the
//     open-redirect guard on the login success path, and the two signup outcomes.

import { describe, it, expect, vi } from 'vitest';
import { loginSchema, signupSchema, safeRedirectPath, fieldErrors } from './auth';
import { actions as loginActions } from '../../../routes/login/+page.server';
import { actions as signupActions } from '../../../routes/signup/+page.server';

// ── loginSchema ─────────────────────────────────────────────────────────────
describe('loginSchema', () => {
	it('accepts a valid credential pair and normalizes the email (trim + lowercase)', () => {
		const r = loginSchema.safeParse({ email: '  Foo@Bar.COM ', password: 'x' });
		expect(r.success).toBe(true);
		if (r.success) expect(r.data.email).toBe('foo@bar.com');
	});

	it('rejects an invalid email', () => {
		const r = loginSchema.safeParse({ email: 'not-an-email', password: 'x' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('email');
	});

	it('rejects an empty password (non-empty is the only login floor)', () => {
		const r = loginSchema.safeParse({ email: 'a@b.com', password: '' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('password');
	});

	it('does NOT impose the signup min-8 floor on login (existing accounts)', () => {
		expect(loginSchema.safeParse({ email: 'a@b.com', password: 'short' }).success).toBe(true);
	});

	it('.strict() rejects an extra field (mass-assignment fence)', () => {
		const r = loginSchema.safeParse({ email: 'a@b.com', password: 'x', role: 'admin' });
		expect(r.success).toBe(false);
	});
});

// ── signupSchema ────────────────────────────────────────────────────────────
describe('signupSchema', () => {
	const ok = { email: 'a@b.com', password: 'password1', confirm: 'password1' };

	it('accepts a valid signup', () => {
		expect(signupSchema.safeParse(ok).success).toBe(true);
	});

	it('rejects a password shorter than 8', () => {
		const r = signupSchema.safeParse({ ...ok, password: 'short', confirm: 'short' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('password');
	});

	it('rejects a password longer than 72 (bcrypt cap)', () => {
		const long = 'a'.repeat(73);
		const r = signupSchema.safeParse({ ...ok, password: long, confirm: long });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('password');
	});

	it('rejects a password / confirm mismatch, keyed to the confirm field', () => {
		const r = signupSchema.safeParse({ ...ok, confirm: 'different1' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('confirm');
	});

	it('.strict() rejects an extra field (mass-assignment fence)', () => {
		const r = signupSchema.safeParse({ ...ok, is_admin: true });
		expect(r.success).toBe(false);
	});
});

// ── safeRedirectPath (open-redirect fence) ────────────────────────────────────
describe('safeRedirectPath', () => {
	it('allows a same-site absolute path', () => {
		expect(safeRedirectPath('/accounts/new')).toBe('/accounts/new');
	});

	it('round-trips a same-site path with a query unchanged', () => {
		expect(safeRedirectPath('/dashboard')).toBe('/dashboard');
		expect(safeRedirectPath('/accounts/new?x=1')).toBe('/accounts/new?x=1');
	});

	it('falls back on a protocol-relative //host', () => {
		expect(safeRedirectPath('//evil.com')).toBe('/');
	});

	it('falls back on a backslash-smuggled /\\host', () => {
		expect(safeRedirectPath('/\\evil.com')).toBe('/');
	});

	it('falls back on a control-char smuggle (Sec finding #1)', () => {
		// `/%09/evil.com` decodes to a literal tab; the browser would strip it from
		// the Location header → //evil.com. The URL-origin check closes the class.
		expect(safeRedirectPath('/\t/evil.com')).toBe('/');
		expect(safeRedirectPath('/\n/evil.com')).toBe('/');
		expect(safeRedirectPath('/\r/evil.com')).toBe('/');
	});

	it('falls back on an absolute off-origin URL', () => {
		expect(safeRedirectPath('https://evil.com')).toBe('/');
	});

	it('falls back on a non-string', () => {
		expect(safeRedirectPath(null)).toBe('/');
		expect(safeRedirectPath(undefined)).toBe('/');
		expect(safeRedirectPath(42)).toBe('/');
	});

	it('falls back on an empty string', () => {
		expect(safeRedirectPath('')).toBe('/');
	});

	it('honors a custom fallback', () => {
		expect(safeRedirectPath('//evil.com', '/login')).toBe('/login');
	});
});

// ── action fences ─────────────────────────────────────────────────────────────
// Minimal RequestEvent stub — the actions only touch request + locals.supabase (+ url
// for signup). Cast through unknown, mirroring the connect.server.test makeEvent shape.
function makeActionEvent(
	form: Record<string, string>,
	supabaseAuth: Record<string, unknown>,
	origin = 'http://localhost'
) {
	const request = new Request(`${origin}/`, {
		method: 'POST',
		headers: { 'content-type': 'application/x-www-form-urlencoded' },
		body: new URLSearchParams(form).toString()
	});
	const locals = { supabase: { auth: supabaseAuth } };
	const url = new URL(origin);
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	return { request, locals, url } as any;
}

/** Run an action, capturing either its returned value or a thrown redirect. */
async function runAction(
	action: (event: unknown) => Promise<unknown>,
	event: unknown
): Promise<{ result?: any; redirect?: { status: number; location: string } }> {
	try {
		return { result: await action(event) };
	} catch (e) {
		const r = e as { status?: number; location?: string };
		if (typeof r?.status === 'number' && typeof r?.location === 'string') {
			return { redirect: { status: r.status, location: r.location } };
		}
		throw e;
	}
}

describe('login action', () => {
	it('bad credentials → generic error, no enumeration leak', async () => {
		const signInWithPassword = vi.fn(async () => ({ error: { message: 'Invalid login credentials' } }));
		const { result } = await runAction(
			loginActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'wrongpass' }, { signInWithPassword })
		);
		expect(result.status).toBe(400);
		expect(result.data.errors._form).toEqual(['Invalid email or password.']);
	});

	it('success → 303 redirect to the guarded target', async () => {
		const signInWithPassword = vi.fn(async () => ({ error: null }));
		const { redirect } = await runAction(
			loginActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'x', redirectTo: '/accounts/new' }, { signInWithPassword })
		);
		expect(redirect).toEqual({ status: 303, location: '/accounts/new' });
	});

	it('open-redirect guard: an off-origin redirectTo collapses to /', async () => {
		const signInWithPassword = vi.fn(async () => ({ error: null }));
		const { redirect } = await runAction(
			loginActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'x', redirectTo: '//evil.com' }, { signInWithPassword })
		);
		expect(redirect).toEqual({ status: 303, location: '/' });
	});

	it('redirectTo in the body does NOT trip the .strict() fence', async () => {
		const signInWithPassword = vi.fn(async () => ({ error: null }));
		const { redirect } = await runAction(
			loginActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'x', redirectTo: '/' }, { signInWithPassword })
		);
		// A redirect (not a 400 fail) proves redirectTo was stripped before parse.
		expect(redirect?.status).toBe(303);
		expect(signInWithPassword).toHaveBeenCalledOnce();
	});
});

describe('signup action', () => {
	it('signUp error → generic message (does not reveal email already registered)', async () => {
		const signUp = vi.fn(async () => ({ data: {}, error: { message: 'User already registered' } }));
		const { result } = await runAction(
			signupActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'password1', confirm: 'password1' }, { signUp })
		);
		expect(result.status).toBe(400);
		expect(result.data.errors._form).toEqual(['Could not create your account. Please try again.']);
	});

	it('confirmations OFF (session returned) → 303 redirect to /', async () => {
		const signUp = vi.fn(async () => ({ data: { session: { access_token: 't' } }, error: null }));
		const { redirect } = await runAction(
			signupActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'password1', confirm: 'password1' }, { signUp })
		);
		expect(redirect).toEqual({ status: 303, location: '/' });
	});

	it('confirmations ON (no session) → { emailSent, email }', async () => {
		const signUp = vi.fn(async () => ({ data: { session: null }, error: null }));
		const { result } = await runAction(
			signupActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'password1', confirm: 'password1' }, { signUp })
		);
		expect(result).toEqual({ emailSent: true, email: 'a@b.com' });
	});

	it('passes emailRedirectTo = ${origin}/auth/callback to signUp', async () => {
		const signUp = vi.fn(async () => ({ data: { session: null }, error: null }));
		await runAction(
			signupActions.default as never,
			makeActionEvent({ email: 'a@b.com', password: 'password1', confirm: 'password1' }, { signUp })
		);
		expect(signUp).toHaveBeenCalledWith(
			expect.objectContaining({ options: { emailRedirectTo: 'http://localhost/auth/callback' } })
		);
	});
});
