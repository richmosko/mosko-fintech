// accounts/new/+page.server.ts — manual (non-Plaid) account onboarding server surface.
// SELF-201 §2.4.2 AC #1/#2. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): auth guard only (bounce to /login when signed-out). The account-level
//    asset Sub-Cat picker is removed — accounts are not classified per-account.
//  - actions.default: validates the six attributes with the .strict() schema +
//    numeric battery, then calls the ATOMIC write-composition RPC
//    fn_create_manual_account (013, SECURITY INVOKER) which creates the account +
//    the AcctSetup account_trans row in ONE transaction (Option A, F/CTO-ratified).
//    NO hand-rolled two-insert sequence (non-atomic; account has no DELETE grant).
//    p_sub_cat_id is passed NULL (the account-level asset Sub-Cat surface is removed;
//    the 013 param stays dormant — a full column drop is a separate future ADR).
//
// No Plaid Link, no OAuth token, no credential prompt (PRD §2.4.2 verbatim).

import { fail, redirect } from '@sveltejs/kit';
import { manualAccountCreateSchema, fieldErrors } from '$lib/server/schemas/account';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	return {};
};

export const actions: Actions = {
	default: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const raw = Object.fromEntries(await request.formData());
		const parsed = manualAccountCreateSchema.safeParse(raw);
		if (!parsed.success) {
			// Echo sticky values (no secrets on this form) so Frontend can repopulate.
			return fail(400, { errors: fieldErrors(parsed.error), values: raw });
		}
		const v = parsed.data;

		// ── 013 RPC BOUNDARY (CONFIRMED) ──────────────────────────────────────
		// Arg names/order/types match Architect's authored 013 fn_create_manual_account
		// VERBATIM (ADR-026): (p_name text, p_account_type text, p_scope text,
		// p_tax_treatment text, p_initial_value numeric, p_as_of_date date,
		// p_sub_cat_id bigint default null) RETURNS bigint. EXECUTE granted to
		// authenticated (anon denied). users_id is NOT a param — defaults to auth.uid().
		// p_sub_cat_id is passed NULL: the account-level asset Sub-Cat surface is removed
		// (accounts aren't classified per-account). The 013 param stays dormant; a full
		// column/param drop is a separate future Architect ADR.
		const { data: accountId, error } = await locals.supabase
			.schema('pfin')
			.rpc('fn_create_manual_account', {
				p_name: v.name,
				p_account_type: v.account_type,
				p_scope: v.scope,
				p_tax_treatment: v.tax_treatment,
				p_initial_value: v.initial_value,
				p_as_of_date: v.as_of_date,
				p_sub_cat_id: null
			});
		// ──────────────────────────────────────────────────────────────────────

		if (error) {
			console.error('[accounts/new] create RPC failed:', error.message);
			return fail(422, {
				errors: { _form: ['Could not create the account. Please try again.'] },
				values: raw
			});
		}

		// Atomic success — account + AcctSetup row committed together.
		throw redirect(303, `/accounts/${accountId}`);
	}
};
