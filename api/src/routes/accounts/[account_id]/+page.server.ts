// accounts/[account_id]/+page.server.ts — account-detail server surface.
// SELF-201 §2.4.2 AC #3/#4. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): account row + its transaction history, RLS-scoped. A non-owner gets
//    zero rows (RLS-filtered) → 404 (existence is not leaked).
//  - actions.toggleActive: single-row RLS-scoped UPDATE of is_active. Inherently
//    atomic (one PostgREST call) — no RPC needed. RLS (account_update USING/WITH
//    CHECK users_id = auth.uid()) fences it to the owner; no users_id in payload.
//
// AC #3 polarity: we use is_active (WHERE is_active = TRUE), NOT a new `inactive`
// column (reconciled at 012). CONTRACT for NAV/current-state consumers (SELF-225
// et al., not built here): filter WHERE is_active = TRUE by default.
// AC #4: inactive accounts retain account_trans history — guaranteed by schema
// (ON DELETE RESTRICT + soft-delete, no cascade/skip-flag); no code here.
//
// acct_number is intentionally NOT selected — masked-only render posture (SD-15);
// manual accounts carry none anyway.

import { error, fail, redirect } from '@sveltejs/kit';
import { toggleActiveSchema, fieldErrors } from '$lib/server/schemas/account';
import type { PageServerLoad, Actions } from './$types';

function parseAccountId(param: string): number | null {
	const n = Number(param);
	return Number.isInteger(n) && n > 0 ? n : null;
}

export const load: PageServerLoad = async ({ locals, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, '/login');

	const accountId = parseAccountId(params.account_id);
	if (accountId === null) throw error(404, 'Account not found');

	// Embed the Sub-Cat label via the account.sub_cat_id → user_taxonomy FK (012), so
	// the detail view renders a human label instead of "#N". The embedded read is
	// itself RLS-scoped (user_taxonomy_select = auth.uid()) and the matched-tenant
	// write fence (fn_account_matched_sub_cat) guarantees the joined row is the
	// caller's own taxonomy. Many-to-one FK → single embedded object (or null).
	const { data: row } = await locals.supabase
		.schema('pfin')
		.from('account')
		.select(
			'account_id, name, account_type, scope, tax_treatment, sub_cat_id, is_active, created_at, user_taxonomy ( cat, sub_cat )'
		)
		.eq('account_id', accountId)
		.maybeSingle();

	// RLS-filtered: not-owner (or nonexistent) → no row → 404 (no existence leak).
	if (!row) throw error(404, 'Account not found');

	// Flatten the embedded label onto data.account. Untagged (NULL sub_cat_id) →
	// cat null, sub_cat "Unsorted" (mirrors the create dropdown's Unsorted option).
	// supabase-js types FK embeds as to-many arrays, but this many-to-one FK returns
	// a single object at runtime — normalize both shapes so it's correct either way.
	const { user_taxonomy, ...rest } = row;
	const embedded = user_taxonomy as unknown;
	const label = (Array.isArray(embedded) ? (embedded[0] ?? null) : (embedded ?? null)) as
		| { cat: string; sub_cat: string }
		| null;
	const account = {
		...rest,
		cat: label?.cat ?? null,
		sub_cat: label?.sub_cat ?? 'Unsorted'
	};

	const { data: transactions } = await locals.supabase
		.schema('pfin')
		.from('account_trans')
		.select('trans_id, transaction_date, amount, vendor, description, transaction_type, is_reverse, created_at')
		.eq('account_id', accountId)
		.order('transaction_date', { ascending: false })
		.order('trans_id', { ascending: false });

	return { account, transactions: transactions ?? [] };
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
	}
};
