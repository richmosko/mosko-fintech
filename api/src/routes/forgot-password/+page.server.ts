// forgot-password/+page.server.ts — request a password reset (SELF-288 / Auth-5, AC #1 + #4).
// Backend-owned server source (ARCH §4.1 allowlist). NO service_role (RT-26), NO migration,
// NO DEFINER — password reset rides GoTrue's built-in flow on the anon+RLS client.
//
// FLOW: validate { email } → resetPasswordForEmail(email, { redirectTo }) where redirectTo
// lands on /auth/callback?next=/reset-password (the SAME exchange handler signup uses, so
// GoTrue's recovery `?code=` is swapped for a recovery SESSION there, then bounced to the
// reset page). Session cookies are written by @supabase/ssr's setAll (hooks.server.ts — the
// sole session chokepoint, ADR-015).
//
// ANTI-ENUMERATION (AC #4, the security crux — flagged for Sec): the action returns the
// EXACT SAME success outcome ({ done: true }) whether the email is registered, unregistered,
// or the GoTrue call errored. It NEVER branches the response on existence, and it does NOT
// surface the resetPasswordForEmail error to the client. Only two non-success shapes exist,
// and NEITHER leaks existence:
//   · 400 — the email failed SHAPE validation (malformed address), generic message.
//   · 429 — the REQUESTER tripped the app-level rate-limit (keyed on their own IP / a hash
//     of the typed email), independent of whether any account exists.
//
// TIMING (AC #4): we deliberately do NOT await-branch on the GoTrue result — both the
// found and not-found paths run the identical single `await resetPasswordForEmail` and then
// return the identical outcome. GoTrue is itself anti-enumerating (uniform 200 for reset
// requests) and rate-limits email_sent server-side, so the residual send-vs-no-send timing
// delta is small and server-internal; we add no existence-dependent work on top of it.

import { fail } from '@sveltejs/kit';
import { forgotPasswordSchema, fieldErrors } from '$lib/server/schemas/auth';
import { consumeRateLimit, emailKey } from '$lib/server/auth/rateLimit';
import type { Actions } from './$types';

// App-level guard tunables (documented for Sec; GoTrue's [auth.rate_limit] is the
// authoritative cross-instance backstop). Per-IP is the coarse abuse gate; per-email caps
// how often one identity can trigger a send (aligns with config email_sent = 2/hr).
const IP_RULE = { max: 10, windowMs: 15 * 60 * 1000 }; // 10 requests / 15 min / IP
const EMAIL_RULE = { max: 3, windowMs: 60 * 60 * 1000 }; // 3 requests / hour / email

// The uniform success outcome. Identical bytes for "sent", "no such account", and
// "GoTrue errored" — the anti-enumeration invariant.
const UNIFORM_DONE = { done: true } as const;

export const actions: Actions = {
	default: async ({ request, locals, url, getClientAddress }) => {
		const raw = Object.fromEntries(await request.formData());
		const parsed = forgotPasswordSchema.safeParse(raw);
		if (!parsed.success) {
			// Shape-only failure (malformed email). Generic, existence-agnostic.
			return fail(400, {
				errors: fieldErrors(parsed.error),
				email: typeof raw.email === 'string' ? raw.email : ''
			});
		}
		const { email } = parsed.data;

		// App-level rate-limit BEFORE the GoTrue call — per-IP (abuse) AND per-email (send
		// frequency). A 429 is keyed on the requester, never on account existence.
		const ip = getClientAddress();
		const ipHit = consumeRateLimit('forgot-ip', ip, IP_RULE);
		const emailHit = consumeRateLimit('forgot-email', emailKey(email), EMAIL_RULE);
		if (ipHit.limited || emailHit.limited) {
			return fail(429, {
				rateLimited: true,
				errors: { _form: ['Too many reset requests. Please wait a little while and try again.'] }
			});
		}

		// Single await, no existence branch. redirectTo mirrors signup's callback convention;
		// `next` routes the post-exchange recovery session to the set-new-password page.
		const redirectTo = `${url.origin}/auth/callback?next=${encodeURIComponent('/reset-password')}`;
		// Intentionally ignore the result: success, unknown-email, and error all collapse to
		// the SAME uniform outcome (anti-enumeration). We do not read `error`.
		await locals.supabase.auth.resetPasswordForEmail(email, { redirectTo });

		return UNIFORM_DONE;
	}
};
