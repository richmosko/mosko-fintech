// accounts/[account_id]/+page.server.ts — account-detail server surface.
// SELF-201 §2.4.2 (AC #3/#4) + SELF-236 §2.2.1.c (Sub-Cat reassignment).
// Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): account row (+ embedded Sub-Cat label) + transaction history +
//    asset-domain Sub-Cat picker options — all RLS-scoped. Non-owner → 404.
//  - actions.toggleActive: single-row RLS-scoped UPDATE of is_active (SELF-201 AC#3).
//  - actions.reassignSubCat: single-row RLS-scoped UPDATE of sub_cat_id (SELF-236).
//    Fenced by account_update RLS (ownership) + the 012 fn_account_matched_sub_cat
//    trigger (BEFORE INSERT OR UPDATE — a reassignment cannot pivot to another
//    tenant's Sub-Cat). Nullable clears the tag → "Unsorted". No migration needed
//    (the trigger + account_update RLS already exist).
//
// AC #3 polarity: is_active (WHERE is_active = TRUE), NOT a new `inactive` column
// (reconciled at 012). CONTRACT for NAV/current-state consumers: filter is_active.
// AC #4: inactive accounts retain account_trans history (schema-guaranteed).
// acct_number intentionally NOT selected — masked-only render posture (SD-15).

import { error, fail, redirect } from '@sveltejs/kit';
import { reassignSubCatSchema, toggleActiveSchema, fieldErrors } from '$lib/server/schemas/account';
import { loadAssetSubCats, subCatLabel } from '$lib/server/queries/taxonomy';
import type { PageServerLoad, Actions } from './$types';

// Embed the Sub-Cat label via the account.sub_cat_id → user_taxonomy FK (012).
const ACCOUNT_COLUMNS =
	'account_id, name, account_type, scope, tax_treatment, sub_cat_id, is_active, created_at, user_taxonomy ( cat, sub_cat )';

function parseAccountId(param: string): number | null {
	const n = Number(param);
	return Number.isInteger(n) && n > 0 ? n : null;
}

/** 012 fn_account_matched_sub_cat raise-message signature → map to the sub_cat field. */
function isCrossTenantSubCat(message: string): boolean {
	return /sub_cat|Decision 3|matched-tenant/i.test(message);
}

export const load: PageServerLoad = async ({ locals, params, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const accountId = parseAccountId(params.account_id);
	if (accountId === null) throw error(404, 'Account not found');

	// Embedded read is itself RLS-scoped (user_taxonomy_select = auth.uid()); the
	// matched-tenant write fence guarantees the joined row is the caller's own.
	const { data: row } = await locals.supabase
		.schema('pfin')
		.from('account')
		.select(ACCOUNT_COLUMNS)
		.eq('account_id', accountId)
		.maybeSingle();

	// RLS-filtered: not-owner (or nonexistent) → no row → 404 (no existence leak).
	if (!row) throw error(404, 'Account not found');

	const { user_taxonomy, ...rest } = row;
	const account = { ...rest, ...subCatLabel(user_taxonomy) };

	const { data: transactions } = await locals.supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, transaction_date, amount, vendor, description, transaction_type, is_reverse, created_at')
		.eq('account_id', accountId)
		.order('transaction_date', { ascending: false })
		.order('trans_id', { ascending: false });

	// Asset-domain Sub-Cat options for the reassignment picker (SELF-236) — same
	// RLS-scoped shape as the accounts/new create picker.
	const subCats = await loadAssetSubCats(locals.supabase);

	return { account, transactions: transactions ?? [], subCats };
};

export const actions: Actions = {
	toggleActive: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = toggleActiveSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		const { error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({ is_active: parsed.data.is_active })
			.eq('account_id', accountId);

		if (updErr) {
			console.error('[accounts/[account_id]] toggleActive failed:', updErr.message);
			return fail(422, { errors: { _form: ['Could not update the account.'] } });
		}
		return { success: true, is_active: parsed.data.is_active };
	},

	reassignSubCat: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const accountId = parseAccountId(params.account_id);
		if (accountId === null) return fail(400, { errors: { _form: ['Invalid account.'] } });

		const parsed = reassignSubCatSchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });

		// Single-row RLS-scoped UPDATE. Ownership fenced by account_update RLS
		// (USING/WITH CHECK users_id = auth.uid()); a cross-tenant sub_cat_id is fenced
		// by the 012 fn_account_matched_sub_cat trigger (covers UPDATE, fail-closed).
		// Minimal .select('account_id') only detects the RLS-filtered non-owner (0 rows
		// → null → 404); the fresh label is NOT returned — enhance's default update()
		// re-invalidates load(), which refreshes account.cat/sub_cat from the one place
		// the label lives (identical to toggleActive). Return { success: true } only.
		const { data: updated, error: updErr } = await locals.supabase
			.schema('pfin')
			.from('account')
			.update({ sub_cat_id: parsed.data.sub_cat_id })
			.eq('account_id', accountId)
			.select('account_id')
			.maybeSingle();

		if (updErr) {
			console.error('[accounts/[account_id]] reassignSubCat failed:', updErr.message);
			return fail(422, {
				errors: isCrossTenantSubCat(updErr.message)
					? { sub_cat_id: ['That Sub-Cat is not available.'] }
					: { _form: ['Could not update the Sub-Cat.'] }
			});
		}
		// RLS-filtered non-owner → 0 rows updated → null.
		if (!updated) return fail(404, { errors: { _form: ['Account not found.'] } });

		return { success: true };
	}
};
