// reports/monthly/[target_month]/+page.server.ts — loader for the §2.6.1.b in-app monthly report
// render (SELF-354 / P2), on top of migration 108 (pfin.monthly_report), 109
// (pfin.monthly_report_account_snapshot), and 110 (pfin.fn_render_monthly_report).
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-359's and SELF-361's own): this file lives under
// Backend's ARCH §4.1 allowlist surface and was authored by Frontend under this ticket's explicit
// dispatch, which named the read path and directed it be built here. Flagged for a Backend/Sec
// re-read at the mandatory joint review this surface carries (P2 is Sec joint-review MANDATORY —
// team-lead's own dispatch).
//
// SELF-358 (P6, PDF export) EXTRACTION: the entire read path (report row resolution, payload
// composition, tax_character catalog, staleness/banner assembly — everything this file used to
// do inline) now lives in `$lib/server/monthly-report/loadMonthlyReport.ts`, shared VERBATIM
// with `reports/monthly/[target_month]/pdf/+server.ts` — R2 (C) makes this STRUCTURAL, not a
// discipline: "the in-app view and the PDF cannot drift; one template" requires one data path
// feeding it, not two independently-maintained copies that could silently diverge. This file's
// own remaining job is: the auth gate, `target_month` parsing (both route-level concerns the
// shared module deliberately does NOT own — see that module's own header), and the one field
// (`seedDeltaMigration`) that is a static citation constant, not a read, and therefore was never
// part of the extraction.
//
// This route accepts EITHER `final` or `draft` — see the shared module's own header for the
// read-path rules (frozen-payload-vs-live-compose, the final-wins tiebreak, the P8 staleness
// design). The PDF route (P6 AC 2) is the caller that additionally REFUSES a `draft` — that
// decision is that route's own business rule, applied to this SAME data after the shared load.

import { error, redirect } from '@sveltejs/kit';
import { INVENTORY_SEED_DELTA_MIGRATION } from '$lib/server/queries/taxLiability';
import { parseTargetMonth } from '$lib/monthly-report';
import { loadMonthlyReportForRender } from '$lib/server/monthly-report/loadMonthlyReport';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals, url, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const targetMonth = parseTargetMonth(params.target_month);
	if (targetMonth === null) {
		throw error(400, 'Invalid target month.');
	}

	const { header, payload, taxCharacters, staleness, cashflowRowStaleness, staleAccountNames } =
		await loadMonthlyReportForRender(locals.supabase, targetMonth);

	return {
		header,
		payload,
		taxCharacters,
		seedDeltaMigration: INVENTORY_SEED_DELTA_MIGRATION,
		staleness,
		cashflowRowStaleness,
		staleAccountNames
	};
};
