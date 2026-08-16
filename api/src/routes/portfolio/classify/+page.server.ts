// portfolio/classify/+page.server.ts — SELF-200 (§2.4.1.e) pending-symbol classification surface,
// generalized at SELF-235 (§2.2.1.b) to the FULL holding-to-bucket assignment list.
// Backend-owned server source (ARCH §4.1 allowlist).
//
// ROUTE PATH is a UX naming choice — flagged to UX to confirm; `/portfolio/classify` is a
// placeholder that compiles the badge target. Not a security or data decision.
//
//  - load(): the FULL ever-transacted symbols list, each carrying its current classification or
//    `null` = pending (loadSymbols; SELF-235 AC1/AC5 — generalizes the prior pending-only
//    loadPendingSymbols) + the asset-domain Sub-Cat picker options (loadAssetSubCats). Both
//    RLS-scoped. Non-signed-in → /login bounce (SELF-285 redirectTo convention).
//  - actions.classify: UPSERT one pfin.user_asset_category row for (auth.uid(), asset_id,
//    sub_cat_id) — first-time classify AND reassign-of-an-already-classified asset are the SAME
//    idempotent upsert (SELF-235 AC3), via ON CONFLICT (users_id, asset_id) DO UPDATE.
//    `users_id` ALWAYS from the session (mass-assignment fence) — never the client. sub_cat_id is
//    app-layer pre-validated (ADR-013 H1: exists + caller-owned + domain='asset', defense-in-depth
//    — isAssignableAssetSubCat) BEFORE the write; ownership + tenant fences are then DB-enforced
//    regardless: user_asset_category INSERT/UPDATE RLS (WITH CHECK users_id = auth.uid()) + the
//    022 matched-tenant sub_cat_id (#8) and global-OR-owned asset_id (#9) triggers (BOTH fire on
//    INSERT and UPDATE → the upsert path stays fenced, fail-closed). A fence rejection maps to a
//    clean, field-scoped error.
//
// AC5: zero third-party security-master calls anywhere in this path.

import { fail, redirect } from '@sveltejs/kit';
import { classifySchema } from '$lib/server/schemas/classification';
import { fieldErrors } from '$lib/server/schemas/account';
import { loadSymbols } from '$lib/server/queries/pendingSymbols';
import { loadAssetSubCats, isAssignableAssetSubCat } from '$lib/server/queries/taxonomy';
import type { PageServerLoad, Actions } from './$types';

// The two matchers below anchor on the DISJOINT raise-message PREFIXES of the 022 Decision-3
// fences (verified against the migration): fn_user_asset_category_matched_sub_cat raises
// "cross-tenant Sub-Cat rejected: …" (#8); fn_user_asset_category_asset raises
// "cross-tenant asset rejected: …" (#9). Prefix-anchoring is required because BOTH messages also
// contain "Decision 3" and "matched-tenant" (the #9 message says "global-OR-matched-tenant fence")
// — a loose substring match would mislabel a #9 asset rejection as a Sub-Cat error.
//
// COUPLING NOTE: this maps app error labels to Architect's migration raise STRINGS. If those
// strings change, the mapping degrades to the generic `_form` 422 below — which is SAFE (fails
// closed, no data leak, DB fence still rejects the write), just a less field-specific message.

/** 022 fn_user_asset_category_matched_sub_cat (#8) raise-prefix → map to the sub_cat_id field. */
function isCrossTenantSubCat(message: string): boolean {
	return /^cross-tenant Sub-Cat rejected/i.test(message);
}

/** 022 fn_user_asset_category_asset (#9) raise-prefix → map to the asset_id field. */
function isUnavailableAsset(message: string): boolean {
	return /^cross-tenant asset rejected/i.test(message);
}

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	// Gap 1 (SELF-200, generalized SELF-235): loadSymbols returns { symbols, ok }. ok:false = a
	// read ERROR (not an empty result) → surface loadError so the page shows a retriable error
	// instead of a FALSE "all caught up" / "nothing held" empty state. subCats is independently
	// fail-soft ([] on error) — a picker with no options degrades the affordance but is not the
	// silent-all-clear hazard Gap 1 targets.
	const { symbols, ok } = await loadSymbols(locals.supabase);
	const subCats = await loadAssetSubCats(locals.supabase);

	return { symbols, subCats, loadError: !ok };
};

export const actions: Actions = {
	classify: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const parsed = classifySchema.safeParse(Object.fromEntries(await request.formData()));
		if (!parsed.success) return fail(400, { errors: fieldErrors(parsed.error) });
		const { asset_id, sub_cat_id } = parsed.data;

		// SELF-235 AC6 / ADR-013 H1: app-layer pre-validation IN FRONT OF the 022 DB fences (never
		// instead of them) — reject a forged/cross-tenant sub_cat_id with a clean 403 before it
		// reaches the write. RLS makes "belongs to another tenant" and "doesn't exist" the SAME
		// zero-row result, so both collapse to the same 403 here (fail-closed, no data leak).
		if (!(await isAssignableAssetSubCat(locals.supabase, sub_cat_id))) {
			return fail(403, { errors: { sub_cat_id: ["That sub-category isn't available."] } });
		}

		// UPSERT for idempotency / re-classify. users_id is set from the SESSION (user.id), never
		// the client — the .strict() schema already rejects a posted users_id, and this is the
		// authoritative source. onConflict targets the unique(users_id, asset_id) index (022).
		const { data: row, error: upErr } = await locals.supabase
			.schema('pfin')
			.from('user_asset_category')
			.upsert(
				{ users_id: user.id, asset_id, sub_cat_id },
				{ onConflict: 'users_id,asset_id' }
			)
			.select('asset_id')
			.maybeSingle();

		if (upErr) {
			console.error('[portfolio/classify] classify upsert failed:', upErr.message);
			// User-facing copy: plain + de-jargoned (UX pass). Field mapping is preserved via the
			// prefix-anchored matchers (sub_cat_id vs asset_id).
			if (isCrossTenantSubCat(upErr.message))
				return fail(422, { errors: { sub_cat_id: ["That sub-category isn't available."] } });
			if (isUnavailableAsset(upErr.message))
				return fail(422, { errors: { asset_id: ["That security isn't available."] } });
			return fail(422, { errors: { _form: ["Couldn't save — please try again."] } });
		}

		// RLS-filtered non-owner write → 0 rows → null. (users_id is session-derived, so this is a
		// defensive backstop, not the primary tenant fence.)
		if (!row) return fail(404, { errors: { _form: ["Couldn't save — please try again."] } });

		return { success: true, asset_id };
	}
};
