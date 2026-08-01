// accounts/connections/[source_id]/+page.server.ts — connections-redesign per-connection
// use/ignore edit page. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): auth-gate, then read the ONE connection (043 view) + ALL its accounts (active AND
//    inactive — management view, not NAV) by linked_source_id. Non-owner / nonexistent source →
//    404 (RLS-scoped, no existence leak). Returns { connection, accounts }.
//  - actions.toggleAccount: the per-account use/ignore control — a single-row RLS-scoped UPDATE
//    of account.is_active keyed on account_id (ownership fenced by account_update RLS, mirroring
//    the `[account_id]` toggleActive path). `.strict()` body { account_id, is_active }. Fail-soft.
//
// No new RLS policy, no service_role, no new SECURITY DEFINER — anon client + existing policies.
// acct_number is never selected (masked-only render posture, SD-15).

import { error, fail, redirect } from '@sveltejs/kit';
import {
	loadConnectionState,
	loadAccountsForSource
} from '$lib/server/queries/connectionState';
import { toggleAccountSchema, fieldErrors } from '$lib/server/schemas/account';
import type { PageServerLoad, Actions } from './$types';

/** source_id is the bigint linked_source PK serialized as a decimal string (SELF-199). A
 *  non-digit param can never match a real source → 404 before any DB round-trip. */
function isValidSourceId(param: string): boolean {
	return /^\d+$/.test(param);
}

export const load: PageServerLoad = async ({ locals, params, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	if (!isValidSourceId(params.source_id)) throw error(404, 'Connection not found');

	// RLS-scoped single-connection read; not-owner (or nonexistent) → null → 404 (no leak).
	const connection = await loadConnectionState(locals.supabase, params.source_id);
	if (!connection) throw error(404, 'Connection not found');

	// All accounts under this connection (active AND inactive). Fail-soft ([] on read error).
	const accounts = await loadAccountsForSource(locals.supabase, params.source_id);

	return { connection, accounts };
};

export const actions: Actions = {
	// Use/ignore a single account under this connection: set account.is_active. RLS-scoped
	// single-row UPDATE keyed on account_id (account_update = users_id = auth.uid()); a
	// cross-tenant / nonexistent account matches no row → the update is a no-op (no leak).
	toggleAccount: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const parsed = toggleAccountSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		const { error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({ is_active: parsed.data.is_active })
			.eq('account_id', parsed.data.account_id);

		if (updErr) {
			console.error('[accounts/connections/[source_id]] toggleAccount failed:', updErr.message);
			return fail(422, { errors: { _form: ['Could not update the account.'] } });
		}
		return { success: true, account_id: parsed.data.account_id, is_active: parsed.data.is_active };
	}
};
