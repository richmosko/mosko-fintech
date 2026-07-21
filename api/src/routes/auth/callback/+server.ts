// auth/callback/+server.ts — email-confirm + code exchange handler (SELF-285 AC #3).
// Backend-owned server source (ARCH §4.1 allowlist).
//
// The confirmation link (and any PKCE OAuth flow) lands here with a `?code=`. We
// exchange it for a session via the anon+RLS client; @supabase/ssr's setAll (wired
// in hooks.server.ts — the sole session chokepoint, ADR-015) writes the session
// cookies as a side effect of the exchange. NO service_role (RT-26).
//
//  - valid code → session established → redirect to the (same-site-guarded) `next`.
//  - missing/invalid code → redirect to /login?error=confirmation (the login page
//    surfaces a "link expired / invalid" message; we never 500 on a bad link).

import { redirect } from '@sveltejs/kit';
import { safeRedirectPath } from '$lib/server/schemas/auth';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, locals }) => {
	const code = url.searchParams.get('code');
	const next = safeRedirectPath(url.searchParams.get('next'));

	if (code) {
		const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
		if (!error) throw redirect(303, next);
	}

	// No code, or the exchange failed (expired/replayed link) → back to login.
	throw redirect(303, '/login?error=confirmation');
};
