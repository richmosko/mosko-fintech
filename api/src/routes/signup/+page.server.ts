// signup/+page.server.ts — email+password signup (SELF-285 AC #2).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): an already-authenticated visitor has no business on /signup → bounce to /.
//  - actions.default: validate with the .strict() signup schema, then signUp via the
//    anon+RLS client with `emailRedirectTo = ${origin}/auth/callback` so the
//    confirmation link lands back on our exchange handler. Session cookies (when
//    confirmations are OFF) are written by @supabase/ssr's setAll (hooks.server.ts —
//    the sole session chokepoint, ADR-015). NO service_role (RT-26).
//
// TWO SIGNUP OUTCOMES (both handled):
//   - confirmations OFF (local/Inbucket default): signUp returns a live `session` →
//     the user is already in → redirect to /.
//   - confirmations ON: no session → return { emailSent, email } so the UI shows
//     "check your email"; the account is blocked until the link is followed.
//
// ENUMERATION FENCE (Sec joint-review, surface:auth): a signUp error returns the SAME
// generic message regardless of cause — never reveal that an email is already
// registered.

import { fail, redirect } from '@sveltejs/kit';
import { signupSchema, fieldErrors } from '$lib/server/schemas/auth';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
	const { user } = await locals.safeGetSession();
	if (user) throw redirect(303, '/');
};

export const actions: Actions = {
	default: async ({ request, locals, url }) => {
		const raw = Object.fromEntries(await request.formData());
		const parsed = signupSchema.safeParse(raw);
		if (!parsed.success) {
			return fail(400, {
				errors: fieldErrors(parsed.error),
				email: typeof raw.email === 'string' ? raw.email : ''
			});
		}
		const { email, password } = parsed.data;

		const { data, error } = await locals.supabase.auth.signUp({
			email,
			password,
			options: { emailRedirectTo: `${url.origin}/auth/callback` }
		});
		if (error) {
			// GENERIC — never reveal whether the email is already registered.
			return fail(400, {
				errors: { _form: ['Could not create your account. Please try again.'] },
				email
			});
		}

		// Confirmations OFF → a session was minted → straight in.
		if (data.session) throw redirect(303, '/');

		// Confirmations ON → no session → tell the UI to prompt for the email link.
		return { emailSent: true, email };
	}
};
