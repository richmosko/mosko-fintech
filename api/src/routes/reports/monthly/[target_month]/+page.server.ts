// reports/monthly/[target_month]/+page.server.ts — loader for the §2.6.1.b in-app monthly report
// render (SELF-354 / P2), on top of migration 108 (pfin.monthly_report), 109
// (pfin.monthly_report_account_snapshot, not read here — see below), and 110
// (pfin.fn_render_monthly_report), landed on feature/self-345 @ be7aed6.
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-359's and SELF-361's own): this file lives under
// Backend's ARCH §4.1 allowlist surface and was authored by Frontend under this ticket's explicit
// dispatch, which named the read path and directed it be built here. Flagged for a Backend/Sec
// re-read at the mandatory joint review this surface carries (P2 is Sec joint-review MANDATORY —
// team-lead's own dispatch).
//
// READ PATH (AC2, R1 (A), R10 A-8): `superseded` is NEVER the target of this route in V1 — "a
// superseded version is never rendered in V1" (the presentation bridge). The query below is
// therefore scoped to `generation_status in ('final', 'draft')`. A `final` row's `rendered_payload`
// is read back VERBATIM (frozen at generation — R1 rider 1); a `draft` row has no
// `rendered_payload` yet (108's own CHECK: NULL is legal ONLY while draft), so its render is
// composed LIVE via `pfin.fn_render_monthly_report(target_month, data_as_of)` — passing the ROW'S
// OWN `data_as_of` (Lock 15 / ONE CALL, ONE CLOCK — never a value this loader derives itself).
// ⚠ JUDGMENT CALL, flagged: nothing in the AC or the migrations forbids a `final` row and a
// `draft` row coexisting for the same `target_month` at once (e.g. mid-regeneration, between the
// old final being superseded and the new draft being authored — though ordinary Lock-11 workflow
// keeps them from overlapping in practice). If the query below ever resolves BOTH, `final` wins —
// matching the presentation bridge's own "generated = the current final" framing — never an
// arbitrary tiebreak on row age.
//
// TAX_CHARACTER CATALOG (AC5, via TaxDecompositionTable): read LIVE, mirroring
// taxes/decomposition/+page.server.ts's own read verbatim — a 5-row, FK-enforced, near-immutable
// GLOBAL reference table, not part of the frozen payload's own R1 rider-1 freeze list. Fail-loud on
// a read failure, same posture as that sibling loader (an incomplete vocabulary is not a
// candidate for fail-soft degrade).
//
// TARGET_MONTH PARAM: accepted as `YYYY-MM` (e.g. `2026-08`), normalized to `YYYY-MM-01` for the
// DB query (108's own CHECK requires `target_month = date_trunc('month', target_month)`). A
// malformed param is a 400, never a guess. `parseTargetMonth` is now the ONE shared parser for
// every `/reports/monthly/[target_month]` route — EXTRACTED to `$lib/monthly-report.ts` at the
// P2/P3/P5 rebase-integration (2026-09-05); this file's own local copy (the original narrow
// judgment call this note used to describe as fresh) is gone.

import { error, redirect } from '@sveltejs/kit';
import { INVENTORY_SEED_DELTA_MIGRATION } from '$lib/server/queries/taxLiability';
import { parseTargetMonth } from '$lib/monthly-report';
import type { MonthlyReportHeader, MonthlyReportPayload } from '$lib/monthly-report';
import type { PageServerLoad } from './$types';

type MonthlyReportRow = MonthlyReportHeader & { rendered_payload: MonthlyReportPayload | null };

export const load: PageServerLoad = async ({ locals, url, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	const targetMonth = parseTargetMonth(params.target_month);
	if (targetMonth === null) {
		throw error(400, 'Invalid target month.');
	}

	const { data: rows, error: reportErr } = await locals.supabase
		.schema('pfin')
		.from('monthly_report')
		.select(
			'report_id, target_month, generation_status, data_as_of, generated_at, owner_header_at_generation, commentary_cash, commentary_bonds, commentary_marketable_securities, commentary_alternatives, commentary_disposition, rendered_payload'
		)
		.eq('target_month', targetMonth)
		.in('generation_status', ['final', 'draft']);

	if (reportErr) {
		throw error(500, 'Could not load this report. Please try again.');
	}

	const allRows = (rows ?? []) as MonthlyReportRow[];
	// `final` wins over `draft` if somehow both are resolved — see file header. Not expected to
	// need it in ordinary Lock 11 workflow, but never an arbitrary row-age tiebreak either.
	const row =
		allRows.find((r) => r.generation_status === 'final') ??
		allRows.find((r) => r.generation_status === 'draft') ??
		null;

	if (!row) {
		throw error(404, 'No report found for this month.');
	}

	let payload: MonthlyReportPayload;
	if (row.generation_status === 'final') {
		if (!row.rendered_payload) {
			// 108's own CHECK forbids this state; a real DB-contract violation, not a candidate for
			// fail-soft degrade.
			throw error(500, 'This report is missing its stored content.');
		}
		payload = row.rendered_payload;
	} else {
		const { data: composed, error: renderErr } = await locals.supabase
			.schema('pfin')
			.rpc('fn_render_monthly_report', {
				p_target_month: row.target_month,
				p_data_as_of: row.data_as_of
			});
		if (renderErr || !composed) {
			throw error(500, 'Could not render this report. Please try again.');
		}
		payload = composed as MonthlyReportPayload;
	}

	const { data: taxCharacters, error: taxCharacterErr } = await locals.supabase
		.schema('pfin')
		.from('tax_character')
		.select('code, label, display_order')
		.order('display_order', { ascending: true });

	if (taxCharacterErr) {
		throw error(500, 'Could not load supporting reference data. Please try again.');
	}

	const header: MonthlyReportHeader = {
		report_id: row.report_id,
		target_month: row.target_month,
		generation_status: row.generation_status,
		data_as_of: row.data_as_of,
		generated_at: row.generated_at,
		owner_header_at_generation: row.owner_header_at_generation,
		commentary_cash: row.commentary_cash,
		commentary_bonds: row.commentary_bonds,
		commentary_marketable_securities: row.commentary_marketable_securities,
		commentary_alternatives: row.commentary_alternatives,
		commentary_disposition: row.commentary_disposition
	};

	return {
		header,
		payload,
		taxCharacters: taxCharacters ?? [],
		seedDeltaMigration: INVENTORY_SEED_DELTA_MIGRATION
	};
};
