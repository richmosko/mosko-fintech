// settings/allocation/+page.server.ts — loader for the §2.2.2 %Target editor (SELF-242
// AC2/AC6). Backend-owned server source (ARCH §4.1 allowlist). Frontend's +page.svelte +
// PlanningTargetEditor.svelte are the SOLE consumers of this loader's `data` shape. This
// file has NO actions — writes go through POST/DELETE /api/settings/planning-target
// (SELF-233/242), not through a form action here.
//
// SHAPE (matches PlanningTargetEditor's PageData contract exactly):
//   catalog : SubCatOption[] ({ id, cat, sub_cat, display_order, element }) — reuses
//             taxonomy.ts's `loadAssetSubCats()` VERBATIM, the SAME RLS-scoped read the
//             accounts/new and accounts/[account_id] pickers already use, so there is
//             exactly ONE server-side query for "what Sub-Cats does this user have", not a
//             second, driftable copy. is_active-filtered (retired Sub-Cats get no %Target
//             field). `element` ('asset' | 'liability', migration 085) rides along per
//             SELF-242/N7 (F/CTO ruling, option A): the editor renders asset-element
//             Sub-Cats only, filtered client-side. ⚠ DELIBERATELY MINIMAL — this slice does
//             NOT touch CAT_GROUP_ORDER or nonReAllocation.ts; amending that constant to be
//             element-driven without the matching denominator rework would create the exact
//             row-set/denominator divergence Sec's binding forbids. That pairing is
//             SELF-239's scope; the single-constant unification happens there, not here.
//             Real Estate is included here (it is asset-element, per 085's backfill) —
//             PlanningTargetEditor / allocation-taxonomy.ts exclude it independently,
//             client-side, same as SELF-238/240's own read surfaces exclude it independently
//             of their own upstream sources; that exclusion is orthogonal to the new
//             element filter and unaffected by it.
//   targets : Record<sub_cat_id, target_percent> — a RAW `pfin.planning_target` read
//             (sub_cat_id, target_percent), RLS-scoped to the caller. A Sub-Cat with NO
//             row is simply absent from this object — 074's own "unset is row-absent"
//             contract (ADR-056); never present with a coalesced 0, which would assert a
//             target the user never set. Same raw-select shape as subcatMarketValue.ts's
//             own planning_target read, kept as its own smaller query here rather than
//             reusing that helper — this editor has no use for the 076 market-value RPC
//             bundled into it.
//
// Fail-soft on the targets read only (mirrors taxonomy.ts's loadAssetSubCats degrading to
// []): a planning_target read error degrades to an empty targets object rather than
// throwing — the editor then renders every field blank, a safe (if stale-looking)
// degradation, never a broken page. The catalog read has its own fail-soft baked into
// loadAssetSubCats itself.

import { redirect } from '@sveltejs/kit';
import { loadAssetSubCats } from '$lib/server/queries/taxonomy';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const catalog = await loadAssetSubCats(locals.supabase);

	const { data: targetRows, error: targetErr } = await locals.supabase
		.schema('pfin')
		.from('planning_target')
		.select('sub_cat_id, target_percent');
	if (targetErr) {
		console.error(
			'[settings/allocation] planning_target read failed (fail-soft, empty targets):',
			targetErr.message
		);
	}

	const targets: Record<number, number> = {};
	for (const row of (targetRows ?? []) as Array<{ sub_cat_id: number; target_percent: number }>) {
		targets[row.sub_cat_id] = row.target_percent;
	}

	return { catalog, targets };
};
