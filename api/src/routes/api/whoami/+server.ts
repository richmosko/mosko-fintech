// GET /api/whoami — session-health probe / SELF-181 smoke route.
//
// Returns the caller's OWN user id (from the validated safeGetSession path) or
// null when unauthenticated. Deliberately returns ONLY the bare uid — never the
// session, access_token, or refresh_token — so no JWT leaks into a response body
// or logs (Sec joint-review, surface:auth).
//
// The unauthenticated -> null path is testable with no live Supabase instance.
// The logged-in -> real-uid assertion needs a running Supabase Auth (gotrue)
// test env and is a ratified deferred follow-up.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ locals }) => {
	const { user } = await locals.safeGetSession();
	return json({ uid: user?.id ?? null });
};
