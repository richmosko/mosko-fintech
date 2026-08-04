// accounts/connect/attributes/+page.server.ts — SELF-199 §2.4.1.d per-account attribute
// capture (provider-linked accounts). Backend-owned server source (ARCH §4.1 allowlist).
//
//  - load(): auth-gate only. Seam (b) = (ii) client-carries-refs (ADR-037): the adapter's
//    AccountRef[] + linked_source_id are carried CLIENT-SIDE from the connect step
//    (Frontend's carry mechanism), so there is no server-side ref fetch here.
//  - actions.default: validates the .strict() envelope + per-account attrs, maps each
//    carried ref to the fn_land_linked_accounts (042) p_accounts element, and calls the
//    ATOMIC INVOKER RPC which INSERTs one pfin.account per SELECTED account in ONE
//    transaction under the caller's RLS. NO hand-rolled N-insert loop (non-atomic; account
//    has no client DELETE grant → a partial landing can't be reversed — see 042 header).
//
// SECURITY: users_id is never sent — the RPC defaults it to auth.uid() (003, un-forgeable).
// A cross-tenant linked_source_id fails closed at the 015 matched-tenant fence (Decision-3
// #6). The .strict() envelope + element are the Lock 14 mass-assignment fence. No service_role
// (anon-key client + RLS + INVOKER). Same-transaction audit-log is DEFERRED (A2-lite, 042 —
// consistent with 013; SELF-201 Task #7).

import { fail, redirect } from '@sveltejs/kit';
import { landLinkedAccountsSchema, fieldErrors } from '$lib/server/schemas/account';
import { requireStepUp } from '$lib/server/auth/mfa';
import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	// Preserve where the user was headed so /login can bounce them back (SELF-285 pattern).
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);
	return {};
};

export const actions: Actions = {
	default: async ({ request, locals, url }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		// Step-up gate on the POST path (mfaHandle in hooks.server.ts guards GETs only, so a
		// direct POST — or an aal2 session that expired between page-load and submit — would
		// otherwise reach the DB fences at aal1). Mirrors the mfaHandle pattern: an aal1 owner
		// with a verified factor is redirected to step-up rather than hitting the 025 aal2
		// backstop / the #6 linked_source fence, whose raise is INDISTINGUISHABLE from a real
		// cross-tenant attempt (→ a misleading "could not be linked" 403). This disambiguates
		// the legit-owner-needs-MFA case at the source; a true cross-tenant attempt still fails
		// closed at the DB fence below. Fail-closed: requireStepUp returns 'step-up-required'
		// on any indeterminate/error AAL state.
		if ((await requireStepUp(locals.supabase)) === 'step-up-required') {
			throw redirect(303, `/mfa/step-up?redirectTo=${encodeURIComponent(url.pathname)}`);
		}

		// (ii) client-carries-refs form encoding (confirmed with Frontend): a variable-length
		// array of structured account objects doesn't map to flat form fields, so the form
		// posts the WHOLE envelope as ONE hidden `payload` field holding
		// JSON.stringify({ linked_source_id, accounts: [...] }) (kept live via $derived at
		// submit time). We parse the JSON, then Zod-validate the whole envelope — the visible
		// per-row fields are UX bindings; `payload` is the authoritative submit.
		const form = await request.formData();
		let raw: unknown;
		try {
			raw = JSON.parse(String(form.get('payload') ?? 'null'));
		} catch {
			return fail(400, { errors: { _form: ['Could not read the selected accounts. Please try again.'] } });
		}

		const parsed = landLinkedAccountsSchema.safeParse(raw);
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}
		const v = parsed.data;

		// Map the carried AccountRef join key (account_id) → provider_account_id for each
		// 042 p_accounts element; attach the four user attributes. currency is NOT threaded
		// (defaults 'USD' per 015 / the 042 contract). Unselected accounts are absent already.
		const p_accounts = v.accounts.map((a) => ({
			provider_account_id: a.account_id,
			name: a.name,
			scope: a.scope,
			tax_treatment: a.tax_treatment,
			account_type: a.account_type
		}));

		// ── 042 RPC BOUNDARY ──────────────────────────────────────────────────
		// fn_land_linked_accounts(p_linked_source_id bigint, p_accounts jsonb)
		//   RETURNS TABLE(account_id bigint, provider_account_id text). SECURITY INVOKER,
		//   EXECUTE granted to authenticated (anon denied). Atomic all-or-nothing under the
		//   caller's RLS: one pfin.account per element; users_id defaults to auth.uid() (NOT a
		//   param). ON CONFLICT (linked_source_id, provider_account_id) is a NO-OP SELF-ASSIGNMENT
		//   on the canonical row (021 dedup arbiter) — a re-land is idempotent (never a 2nd row),
		//   does NOT overwrite stored attributes, and since 058 does NOT reopen a closed account
		//   (ADR-042 D1b: reopening is a bookkeeping event belonging to the account's own close
		//   control, never a side effect of connecting). Fences evaluate as the caller and fail closed
		//   cross-tenant (account_insert WITH CHECK, fn_account_matched_linked_source #6,
		//   inherited 025 aal2 clause). source_id is a small bigint sequence value → Number()
		//   is exact for the bigint param.
		const { error } = await locals.supabase.schema('pfin').rpc('fn_land_linked_accounts', {
			p_linked_source_id: Number(v.linked_source_id),
			p_accounts
		});
		// ──────────────────────────────────────────────────────────────────────

		if (error) {
			console.error('[accounts/connect/attributes] land RPC failed:', error.message);
			// The #6 matched-tenant fence raises on a cross-tenant linked_source_id — surface
			// a distinct (still non-leaky) message; everything else is a generic save failure.
			const isTenant = /linked_source|Decision 3|matched-tenant/i.test(error.message);
			return fail(isTenant ? 403 : 422, {
				errors: {
					_form: [
						isTenant
							? 'Those accounts could not be linked to your connection.'
							: 'Could not save your accounts. Please try again.'
					]
				}
			});
		}

		// Atomic success — one row per selected account committed together. Land on the
		// accounts list (destination coordinable with Frontend if a success/summary view lands).
		throw redirect(303, '/accounts');
	}
};
