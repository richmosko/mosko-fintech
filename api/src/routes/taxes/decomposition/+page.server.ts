// taxes/decomposition/+page.server.ts — loader for the §2.5.1 tax-relevant income
// decomposition table (SELF-264). Backend-owned server source (ARCH §4.1 allowlist).
// Frontend's +page.svelte is the sole consumer of this loader's `data` shape. NO actions —
// this surface has no inline edit (V2+, ADR-013 P5) and this file writes nothing.
//
// SHAPE:
//   liability                    : loadTaxLiability(supabase)'s TaxLiabilityPayload,
//                                   VERBATIM — no reshaping. The page reads
//                                   `liability.decomposition` for the table itself; the other
//                                   top-level keys ride along unused here so there is still
//                                   only ONE call to fn_compute_tax_liability per page (ADR-067
//                                   Decision 1 — one composed source, not a per-surface reader).
//   taxCharacters                 : pfin.tax_character's FIVE seeded rows (code, label,
//                                   display_order), RLS-shared-read (011 — `using (true)`),
//                                   ordered for display. AC 5: the tax_character vocabulary is
//                                   FK-enforced DATA, read from the table — never a client-side
//                                   list, and never re-derived from the payload's rows (a Sub-Cat
//                                   with zero YTD activity in ANY character still needs that
//                                   character available for the legend/grouping UI).
//   inventorySeedDeltaMigration   : the literal migration filename this page's tax_relevant /
//                                   tax_character reading was built against (AC 11's hard gate —
//                                   100_tax_value_inventory_seed_delta.sql, SELF-263's inventory,
//                                   on main as of this branch's origin/main @ 346d204). A static
//                                   citation, not a DB read — 100's own column comments are the
//                                   canonical statement of what it examined; this loader only
//                                   names the artifact so the page can render "built against
//                                   migration 100" per ADR-013's non-silent-staleness principle.
//                                   ⚠ tax_relevant = false on any row is NEVER read here as an
//                                   examined determination for rows outside that inventory (100's
//                                   own column-comment fence, fn_compute_tax_liability's M-5
//                                   reader half) — this loader does not re-derive that fence, it
//                                   only carries the citation the copy needs to state it.
//
// Fail loud, no coercion — matches loadTaxLiability's posture (taxLiability.ts module header).
// A tax_character read failure means the page cannot legend its own rows correctly, so it is not
// a candidate for fail-soft degrade; this loader lets it throw rather than rendering a table with
// an incomplete or silently-empty vocabulary.

import { redirect } from '@sveltejs/kit';
import { loadTaxLiability, INVENTORY_SEED_DELTA_MIGRATION } from '$lib/server/queries/taxLiability';
import type { PageServerLoad } from './$types';

export type TaxCharacterRow = {
	code: string;
	label: string;
	display_order: number | null;
};

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const liability = await loadTaxLiability(locals.supabase);

	const { data: taxCharacters, error: taxCharacterErr } = await locals.supabase
		.schema('pfin')
		.from('tax_character')
		.select('code, label, display_order')
		.order('display_order', { ascending: true });

	if (taxCharacterErr) {
		throw new Error(
			`[taxes/decomposition] pfin.tax_character read failed: ${taxCharacterErr.message}`
		);
	}

	return {
		liability,
		taxCharacters: (taxCharacters ?? []) as TaxCharacterRow[],
		inventorySeedDeltaMigration: INVENTORY_SEED_DELTA_MIGRATION
	};
};
