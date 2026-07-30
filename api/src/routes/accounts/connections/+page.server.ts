// accounts/connections/+page.server.ts — SELF-207 §2.4.4.b connection-state list.
// Backend-owned server source (ARCH §4.1 allowlist).
//
// load(): auth-gate, then read the caller's connection states from Architect's `043`
// linked_source_connection_state view (owner-scoped, anon-key + RLS, NO service_role).
// Returns { connections, error } — Frontend's +page.svelte renders the list + connection
// chips, distinguishes a read failure (error:true) from a true-empty (no connections yet),
// and hosts the (Phase 2) per-connection re-auth affordance. Fail-soft: the reader never throws.

import { redirect } from '@sveltejs/kit';
import { loadConnectionStates } from '$lib/server/queries/connectionState';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const { connections, error } = await loadConnectionStates(locals.supabase);
	return { connections, error };
};
