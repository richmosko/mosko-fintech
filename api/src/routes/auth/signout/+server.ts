// auth/signout/+server.ts — sign-out action (SELF-285 AC #4).
// Backend-owned server source (ARCH §4.1 allowlist).
//
// POST-ONLY by design: sign-out is state-changing, so it must not be reachable via a
// GET (a prefetch, an <img>, or a cross-site link could otherwise log the user out).
// No GET handler is exported, so a GET here 405s. signOut clears the session; the
// rotated/cleared cookies are written by @supabase/ssr's setAll (hooks.server.ts —
// the sole session chokepoint, ADR-015). NO service_role (RT-26).

import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ locals }) => {
	await locals.supabase.auth.signOut();
	throw redirect(303, '/login');
};
