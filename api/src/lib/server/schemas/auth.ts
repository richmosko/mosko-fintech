// auth.ts — server-side Zod schemas + helpers for the base auth surfaces (SELF-285).
//
// SOURCE OF TRUTH: Frontend mirrors these client-side (Lock 14) and must never ship
// a looser schema. `.strict()` is the mass-assignment fence (Lock 14 mod #2) — it
// rejects any extra field so a tampered form body cannot smuggle keys. Email is
// normalized (trim + lowercase) so identity comparisons and Auth calls see one
// canonical form.
//
// DELIBERATELY DECOUPLED from account.ts: auth has no schema/enum overlap with the
// manual-account surfaces, so it carries its OWN `fieldErrors` copy rather than
// coupling the two boundaries. `safeRedirectPath` lives here (not a route) because
// both the load + action of /login and the /auth/callback handler consume it.
//
// Zod v4: `z.email()` is the top-level email validator; we read `error.issues`
// directly (not the soft-deprecated `.flatten()`).

import { z } from 'zod';

/**
 * Normalized email field: trim + lowercase BEFORE validating, so trailing
 * whitespace / mixed case never produce a "different" identity. Validation runs on
 * the normalized value via `.pipe(z.email())`.
 */
const emailField = () =>
	z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address.'));

/**
 * Login credentials. Password is NON-EMPTY only — we deliberately do NOT re-impose
 * the signup min-8 floor here: existing accounts may predate any policy bump, and
 * the server never wants to reveal password-shape hints on the sign-in path.
 */
export const loginSchema = z
	.object({
		email: emailField(),
		password: z.string().min(1, 'Password is required.')
	})
	.strict();

export type LoginInput = z.infer<typeof loginSchema>;

/**
 * Signup credentials. Password floor = 8 (mirrors supabase/config.toml
 * `minimum_password_length`); max = 72 (bcrypt truncates past 72 bytes, so a longer
 * value would silently ignore the tail — reject it instead). `confirm` must match;
 * the mismatch issue is attached to `confirm` so the UI flags the right field.
 */
export const signupSchema = z
	.object({
		email: emailField(),
		password: z
			.string()
			.min(8, 'Password must be at least 8 characters.')
			.max(72, 'Password must be at most 72 characters.'),
		confirm: z.string().min(1, 'Please confirm your password.')
	})
	.strict()
	.refine((v) => v.password === v.confirm, {
		message: 'Passwords do not match.',
		path: ['confirm']
	});

export type SignupInput = z.infer<typeof signupSchema>;

/**
 * Open-redirect guard. A post-login / post-confirm redirect target is honored ONLY
 * when it is a SAME-SITE absolute path: a single leading `/`, and NOT a
 * protocol-relative URL (`//host`) or a backslash-smuggled one (`/\host`, which some
 * browsers normalize to `//host`). Anything else — a non-string, an empty string, an
 * absolute `https://evil` URL — collapses to the fallback. Never let a client value
 * steer the browser to another origin.
 *
 * A prefix-only check is INSUFFICIENT (Sec finding #1): a control-char smuggle like
 * `/%09/evil.com` decodes to `"/\t/evil.com"` — 2nd char is a tab, so it slips past
 * `startsWith('//')` / `startsWith('/\\')`, then the browser strips the tab from the
 * `Location` header, yielding `//evil.com` (off-origin). So after the cheap prefix
 * pass we RESOLVE `raw` against a dummy origin and reject anything whose origin
 * changes — this subsumes `//`, `/\`, control-char smuggles, and absolute URLs — and
 * return the URL-normalized same-site path (`pathname + search + hash`).
 */
export function safeRedirectPath(raw: unknown, fallback = '/'): string {
	if (typeof raw !== 'string') return fallback;
	if (!raw.startsWith('/')) return fallback; // empty string + absolute URLs fail here
	if (raw.startsWith('//')) return fallback; // cheap first pass: protocol-relative
	if (raw.startsWith('/\\')) return fallback; // cheap first pass: backslash-smuggled
	try {
		const u = new URL(raw, 'http://x');
		if (u.origin !== 'http://x') return fallback; // smuggled //, /\, control-chars, absolute URL
		return u.pathname + u.search + u.hash; // normalized same-site path
	} catch {
		return fallback;
	}
}

/**
 * Flatten a ZodError into `{ field: [messages] }` keyed by the top-level field.
 * Built from `error.issues` directly (stable across Zod v3/v4). Root-level issues
 * (e.g. a cross-field refine with no path) bucket under `_form`. LOCAL copy — auth
 * stays decoupled from account.ts by design.
 */
export function fieldErrors(error: z.ZodError): Record<string, string[]> {
	const out: Record<string, string[]> = {};
	for (const issue of error.issues) {
		const key = issue.path.length ? String(issue.path[0]) : '_form';
		(out[key] ??= []).push(issue.message);
	}
	return out;
}
