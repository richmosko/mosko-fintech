// login/+page.server.ts — password sign-in (SELF-285 AC #1).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): if already authenticated, bounce straight to the (guarded) redirect
//    target. Otherwise hand the sanitized `redirectTo` back to the page so the form
//    can round-trip it as a hidden field.
//  - actions.default: strip the control field `redirectTo` BEFORE the .strict()
//    parse (it is not a credential — leaving it in trips the mass-assignment fence),
//    validate, then signInWithPassword via the anon+RLS client. Session cookies are
//    written by @supabase/ssr's setAll (wired in hooks.server.ts — the sole session
//    chokepoint, ADR-015). NO service_role anywhere (RT-26).
//
// ENUMERATION FENCE (Sec joint-review, surface:auth): a failed sign-in returns the
// SAME generic "Invalid email or password." regardless of whether the email exists —
// the server never reveals account existence on this path.

import { fail, redirect } from '@sveltejs/kit';
import { loginSchema, fieldErrors, safeRedirectPath } from '$lib/server/schemas/auth';
import { ensureUserSettings } from '$lib/server/queries/userSettings';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	const redirectTo = safeRedirectPath(url.searchParams.get('redirectTo'));
	if (user) throw redirect(303, redirectTo);
	return { redirectTo };
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		const form = await request.formData();
		// Pull the redirect target out of the body BEFORE parsing — it is a control
		// field, not part of the credential schema. `.strict()` would otherwise reject
		// the whole body for the extra key.
		const redirectTo = form.get('redirectTo');
		const raw = Object.fromEntries(form);
		delete raw.redirectTo;

		const parsed = loginSchema.safeParse(raw);
		if (!parsed.success) {
			return fail(400, {
				errors: fieldErrors(parsed.error),
				email: typeof raw.email === 'string' ? raw.email : ''
			});
		}
		const { email, password } = parsed.data;

		const { data, error } = await locals.supabase.auth.signInWithPassword({ email, password });
		if (error) {
			// GENERIC — never reveal whether the email exists (enumeration fence).
			return fail(400, { errors: { _form: ['Invalid email or password.'] }, email });
		}

		// Lazily provision the caller's user_settings row (SELF-286 substrate). FAIL-SOFT:
		// ensureUserSettings never throws, so a provisioning hiccup cannot block login —
		// the row self-heals next request and a missing row reads as 'none' anyway.
		if (data.user) await ensureUserSettings(locals.supabase, data.user.id);

		// Same-site-guarded redirect (open-redirect fence). Bad targets → '/'.
		throw redirect(303, safeRedirectPath(typeof redirectTo === 'string' ? redirectTo : null));
	}
};
