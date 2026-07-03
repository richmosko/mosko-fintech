// hooks.server.ts — the single Supabase Auth session chokepoint.
//
// Per ADR-015 Decision 1 + ARCH §4 (Auth): this file owns centralized Supabase
// session forwarding + JWT refresh under the `authenticated` tier. Session
// handling is NOT duplicated anywhere else in the app.
//
// Security posture (SELF-181, Sec joint-review — surface:auth):
//  - Uses the ANON key + RLS only. The elevated service-role key is NEVER
//    referenced here (RT-26 confinement — it lives only in the 3 allowlisted
//    endpoints). Auth is the anon+RLS path by design.
//  - `safeGetSession()` validates the JWT via `getUser()` against the Auth
//    server before returning a user. `getSession()` alone reads the cookie
//    WITHOUT verifying the JWT signature (spoofable) and is never used for any
//    authorization-bearing decision. Downstream code authorizes off the
//    validated `user`, and the DB enforces isolation via RLS (`users_id = auth.uid()`).
//  - Refresh-token rotation is Supabase Auth default: getUser()/getSession()
//    refresh as needed and `setAll` writes the rotated cookies back.

import { createServerClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	// Per-request Supabase client, cookie-bound to this request/response cycle.
	event.locals.supabase = createServerClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		cookies: {
			getAll: () => event.cookies.getAll(),
			setAll: (cookiesToSet) => {
				cookiesToSet.forEach(({ name, value, options }) => {
					event.cookies.set(name, value, { ...options, path: '/' });
				});
			}
		}
	});

	// Validated session helper. Reads the session from the cookie, then verifies
	// the JWT against the Auth server via getUser(). Returns nulls on any
	// validation failure — never a spoofed identity.
	event.locals.safeGetSession = async () => {
		const {
			data: { session }
		} = await event.locals.supabase.auth.getSession();
		if (!session) {
			return { session: null, user: null };
		}

		const {
			data: { user },
			error
		} = await event.locals.supabase.auth.getUser();
		if (error) {
			// JWT failed server-side validation — treat as unauthenticated.
			return { session: null, user: null };
		}

		return { session, user };
	};

	return resolve(event, {
		// Only these Supabase response headers are safe to serialize through SSR.
		filterSerializedResponseHeaders(name) {
			return name === 'content-range' || name === 'x-supabase-api-version';
		}
	});
};
