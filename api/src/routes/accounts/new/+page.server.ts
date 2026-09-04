// accounts/new/+page.server.ts — manual (non-Plaid) account onboarding server surface.
// SELF-201 §2.4.2 AC #1/#2. Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): auth guard only (bounce to /login when signed-out). The account-level
//    asset Sub-Cat picker is removed — accounts are not classified per-account.
//  - actions.default: validates the six attributes with the .strict() schema +
//    numeric battery, then calls the ATOMIC write-composition RPC
//    fn_create_manual_account (6-arg, SECURITY INVOKER) which creates the account +
//    the AcctSetup account_trans row in ONE transaction (Option A, F/CTO-ratified).
//    NO hand-rolled two-insert sequence (non-atomic; account has no DELETE grant).
//    The account-level asset Sub-Cat surface is removed — accounts are not
//    classified per-account; the column + the p_sub_cat_id param were dropped at
//    v1.132 / migration 048 (Decision-3 #5 DROPPED), so the RPC is now 6-arg.
//
//    SELF-267 AC 2's `tax_jurisdiction`: the §2.4.2 form MAY present the control at
//    creation, but `fn_create_manual_account`'s signature is UNCHANGED (087) — adding a
//    seventh param would break other files' regprocedure assertions (102's header runs
//    and records this check). So a non-null designation is realized as a SECOND
//    statement, an ordinary UPDATE under account_update, in the SAME action AFTER the
//    RPC has committed. This is CREATE-THEN-UPDATE, not one atomic write: the account
//    row exists the instant the RPC returns, and the UPDATE either lands the
//    designation or fails on 102's account_tax_jurisdiction_uniq partial index — see
//    the 23505 branch below for why that does NOT roll the account back.
//
// No Plaid Link, no OAuth token, no credential prompt (PRD §2.4.2 verbatim).

import { fail, redirect } from '@sveltejs/kit';
import { manualAccountCreateSchema, fieldErrors } from '$lib/server/schemas/account';
import type { PageServerLoad, Actions } from './$types';

/** Same signature-based test as the account-detail action; see that file's own comment. */
function isTaxJurisdictionConflict(err: { code?: string; message?: string | null }): boolean {
	return err.code === '23505' && /account_tax_jurisdiction_uniq/i.test(err.message ?? '');
}

/** Same `Record<string, string[]>` shaping as the account-detail action; see that file's
 *  `taxJurisdictionError` comment for why a narrow object literal fails `npm run check`. */
function taxJurisdictionError(message: string): Record<string, string[]> {
	return { tax_jurisdiction: [message] };
}

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

		// ── RPC BOUNDARY (6-arg, CONFIRMED) ───────────────────────────────────
		// Arg names/order/types match Architect's recreated fn_create_manual_account
		// VERBATIM (migration 048): (p_name text, p_account_type text, p_scope text,
		// p_tax_treatment text, p_initial_value numeric, p_as_of_date date) RETURNS
		// bigint. The p_sub_cat_id param was DROPPED at v1.132 / 048 (account-level
		// asset Sub-Cat surface removed — Decision-3 #5 DROPPED); passing it now errors.
		// EXECUTE granted to authenticated (anon denied). users_id is NOT a param —
		// defaults to auth.uid().
		const { data: accountId, error } = await locals.supabase
			.schema('pfin')
			.rpc('fn_create_manual_account', {
				p_name: v.name,
				p_account_type: v.account_type,
				p_scope: v.scope,
				p_tax_treatment: v.tax_treatment,
				p_initial_value: v.initial_value,
				p_as_of_date: v.as_of_date
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
		// SELF-267 AC 2 create-then-update: the RPC above has ALREADY COMMITTED, so
		// nothing past this point may report the create itself as failed.
		if (v.tax_jurisdiction !== null) {
			const { error: taxErr } = await locals.supabase
				.schema('pfin')
				.from('account')
				.update({ tax_jurisdiction: v.tax_jurisdiction })
				.eq('account_id', accountId);

			if (taxErr) {
				// NOT ROLLED BACK. The account is real and belongs to the user; only the
				// designation failed, almost certainly on 102's account_tax_jurisdiction_uniq
				// partial index (a second account already carries this jurisdiction) — a
				// fake-atomic rollback here would delete a genuine account to hide a
				// conflict the user can resolve on the account they already have. Returned as
				// a field error WITH the created account's id so the caller can route the
				// user to it rather than silently losing the new account from view.
				if (isTaxJurisdictionConflict(taxErr)) {
					return fail(409, {
						errors: taxJurisdictionError(
							'Another account is already designated as your tax authority ledger.'
						),
						values: raw,
						accountId
					});
				}
				console.error(
					'[accounts/new] post-create tax_jurisdiction UPDATE failed:',
					taxErr.message
				);
				return fail(422, {
					errors: taxJurisdictionError(
						'Account created, but the tax authority could not be saved.'
					),
					values: raw,
					accountId
				});
			}
		}

		throw redirect(303, `/accounts/${accountId}`);
	}
};
