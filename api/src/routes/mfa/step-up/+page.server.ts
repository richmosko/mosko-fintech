// mfa/step-up/+page.server.ts — TOTP step-up at login (AC#3). SELF-291 / Auth-3b Slice 1.
// Backend-owned server source (ARCH §4.1 allowlist).
//
// This route is EXEMPT from the hooks step-up guard (STEP_UP_EXEMPT_PREFIXES '/mfa') so
// a stepped-down aal1 user can actually reach it — otherwise the guard would loop.
//
//  - load(): resolve the validated user (else /login, preserving redirectTo). Read AAL:
//      · already aal2                       → nothing to do → redirect to the target.
//      · verified factor exists, aal1       → mode 'ready' (render the code form).
//      · no verified factor (levels known)  → nothing to step up to → redirect to target
//                                             (the guard ALLOWS a no-factor user, so this
//                                             does not loop).
//      · AAL indeterminate/error            → mode 'unavailable' (do NOT redirect onward —
//                                             that would loop the guard; give the user an
//                                             actionable dead-end instead).
//  - actions.default: verify a TOTP code against the verified factor
//      (challenge → verify) → session upgraded to aal2 → same-site-guarded redirect to
//      the intended target.
//
// Anon+RLS client only, NEVER service_role (RT-26). Session cookies (incl. the aal2
// upgrade) are written by @supabase/ssr's setAll in hooks.server.ts (ADR-015).

import { fail, redirect } from '@sveltejs/kit';
import { safeRedirectPath, fieldErrors } from '$lib/server/schemas/auth';
import { totpCodeSchema } from '$lib/server/schemas/mfa';
import { getTotpFactors } from '$lib/server/auth/mfa';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	const redirectTo = safeRedirectPath(url.searchParams.get('redirectTo'));
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(redirectTo)}`);

	const { data, error } = await locals.supabase.auth.mfa.getAuthenticatorAssuranceLevel();
	if (error || !data) {
		// Indeterminate — cannot resolve whether/how to step up. Give an actionable
		// dead-end rather than bouncing onward (which the fail-closed guard would loop).
		return { mode: 'unavailable' as const, redirectTo };
	}
	const { currentLevel, nextLevel } = data;
	if (currentLevel === 'aal2') {
		// Already stepped up — send them where they were headed.
		throw redirect(303, redirectTo);
	}
	if (nextLevel === 'aal2') {
		// A verified factor exists and the session is aal1 → show the code challenge.
		return { mode: 'ready' as const, redirectTo };
	}
	// No verified factor: there is nothing to step up to. The guard allows a no-factor
	// user through, so redirecting to the target does not loop.
	throw redirect(303, redirectTo);
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		// redirectTo is a control field, not a credential — strip it before .strict().
		const redirectTo = form.get('redirectTo');
		const raw = Object.fromEntries(form);
		delete raw.redirectTo;

		const parsed = totpCodeSchema.safeParse(raw);
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		// Resolve the verified TOTP factor to challenge (there is exactly one in V1).
		const { verifiedIds } = await getTotpFactors(locals.supabase);
		const factorId = verifiedIds[0];
		if (!factorId) {
			// No verified factor — cannot step up. Surface generically.
			return fail(400, { errors: { _form: ['Two-factor authentication is not set up.'] } });
		}

		const { data: challenge, error: challengeError } =
			await locals.supabase.auth.mfa.challenge({ factorId });
		if (challengeError || !challenge) {
			return fail(400, { errors: { _form: ['Could not start verification. Please try again.'] } });
		}

		const { error: verifyError } = await locals.supabase.auth.mfa.verify({
			factorId,
			challengeId: challenge.id,
			code: parsed.data.code
		});
		if (verifyError) {
			// GENERIC — do not distinguish "wrong code" from other failures beyond what the
			// user needs. Session stays aal1; they can retry.
			return fail(400, { errors: { _form: ['Invalid or expired code. Please try again.'] } });
		}

		// Session upgraded to aal2 (cookies rotated via setAll). Send them onward.
		throw redirect(303, safeRedirectPath(typeof redirectTo === 'string' ? redirectTo : null));
	}
};
