// accounts/new/+page.server.ts — manual (non-Plaid) account onboarding server surface.
// SELF-201 §2.4.2 AC #1/#2. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): fetches the caller's asset-domain Sub-Cat taxonomy for the dropdown,
//    RLS-scoped via the per-request anon client (users_id = auth.uid()).
//  - actions.default: validates the six attributes + Sub-Cat with the .strict()
//    schema + numeric battery, then calls the ATOMIC write-composition RPC
//    fn_create_manual_account (013, SECURITY INVOKER) which creates the account +
//    the AcctSetup account_trans row in ONE transaction (Option A, F/CTO-ratified).
//    NO hand-rolled two-insert sequence (non-atomic; account has no DELETE grant).
//
// No Plaid Link, no OAuth token, no credential prompt (PRD §2.4.2 verbatim).

import { fail, redirect } from '@sveltejs/kit';
import { manualAccountCreateSchema, fieldErrors } from '$lib/server/schemas/account';
import { loadAssetSubCats } from '$lib/server/queries/taxonomy';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	// Asset-domain Sub-Cat options for the create picker — RLS-scoped, shared with the
	// accounts/[account_id] reassignment picker (SELF-236) via loadAssetSubCats.
	const subCats = await loadAssetSubCats(locals.supabase);
	return { subCats };
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
		const { data: accountId, error } = await locals.supabase
			.schema('pfin')
			.rpc('fn_create_manual_account', {
				p_name: v.name,
				p_account_type: v.account_type,
				p_scope: v.scope,
				p_tax_treatment: v.tax_treatment,
				p_initial_value: v.initial_value,
				p_as_of_date: v.as_of_date,
				p_sub_cat_id: v.sub_cat_id
			});
		// ──────────────────────────────────────────────────────────────────────

		if (error) {
			console.error('[accounts/new] create RPC failed:', error.message);
			// The matched-tenant fence (fn_account_matched_sub_cat) raises on a
			// cross-tenant sub_cat_id — surface that against the field; else generic.
			const isSubCat = /sub_cat|Decision 3|matched-tenant/i.test(error.message);
			return fail(422, {
				errors: isSubCat
					? { sub_cat_id: ['That Sub-Cat is not available.'] }
					: { _form: ['Could not create the account. Please try again.'] },
				values: raw
			});
		}

		// Atomic success — account + AcctSetup row committed together.
		throw redirect(303, `/accounts/${accountId}`);
	}
};
