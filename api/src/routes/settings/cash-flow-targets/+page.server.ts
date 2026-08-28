// settings/cash-flow-targets/+page.server.ts — loader for the §2.3.2 cash-flow targets
// editor (SELF-252 AC1/AC2). Frontend-owned browser surface. CashflowTargetEditor.svelte
// (via +page.svelte) is the sole consumer of this loader's `data` shape. This file has NO
// actions — writes go through POST /api/settings/cashflow-target (SELF-252), not through a
// form action here, same as settings/allocation/+page.server.ts's own no-actions posture.
//
// SHAPE: `targets` is Backend's `loadCashflowTarget(supabase)` return VERBATIM
// (cashflowTarget.ts) — { income_target_annual, expense_target_monthly }, both nullable.
// Row-absent (never provisioned) and a row that exists with both columns NULL read as the
// SAME state ("no targets set") — that module's own contract, not re-derived here. A NULL
// column MUST render blank in the editor, never a seeded 0 (AC2) — CashflowTargetEditor
// owns that rendering; this loader only threads the raw values through unchanged.

import { redirect } from '@sveltejs/kit';
import { loadCashflowTarget } from '$lib/server/queries/cashflowTarget';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const targets = await loadCashflowTarget(locals.supabase);

	return { targets };
};
