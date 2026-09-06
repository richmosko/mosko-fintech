// loadMonthlyReport.ts — the ONE shared monthly-report read path, extracted from
// reports/monthly/[target_month]/+page.server.ts (P2/P8) at the SELF-358 (P6, PDF export)
// rebase-integration. Both the in-app page loader AND the PDF export route
// (reports/monthly/[target_month]/pdf/+server.ts) call this — team-lead's explicit
// instruction was "extract it into a $lib/server/monthly-report/ module... rather than
// duplicating it" (P6's SELF-358 dispatch), because the two surfaces must render IDENTICAL
// content except the live staleness layer (R2 (C) — "the in-app view and the PDF cannot
// drift; one template" is STRUCTURAL under this ruling, not a discipline two independently
// maintained loaders could quietly violate).
//
// SCOPE: this module owns the READ path only (report row resolution, payload composition,
// tax_character catalog, staleness/banner assembly). It does NOT own auth (each caller's own
// `locals.safeGetSession()` gate stays at the call site — a route-level concern, not a data
// concern) and does NOT own `target_month` parsing (callers use `$lib/monthly-report.ts`'s
// shared `parseTargetMonth`, since a malformed param is a route-level 400 before this module
// is ever called). It also does NOT decide whether a `draft` status is acceptable for the
// caller's purpose — the in-app page renders either `final` or `draft`; the PDF route (P6 AC
// 2) refuses a `draft` — that decision reads `header.generation_status` AFTER this module
// returns and is each caller's own business rule, not a data-loading one.
//
// Everything below is extracted VERBATIM from the P2/P8 loader (git history:
// reports/monthly/[target_month]/+page.server.ts as of the P8/SELF-360 branch) — no logic
// changed, only relocated and re-exported as a single async function.

import { error } from '@sveltejs/kit';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS, type StalenessData } from '$lib/staleness/stale-constituent';
import { resolveStaleAccountIds } from '$lib/server/queries/navComposition';
import {
	loadCashflowContributors,
	computeCashflowRowStaleness,
	EMPTY_CASHFLOW_ROW_STALENESS,
	type CashflowRowStalenessMap
} from '$lib/server/queries/cashflowContributors';
import { userSuppliedAsOf } from '$lib/server/time/asOf';
import type { MonthlyReportHeader, MonthlyReportPayload } from '$lib/monthly-report';

type MonthlyReportRow = MonthlyReportHeader & { rendered_payload: MonthlyReportPayload | null };
type AccountSnapshotRow = { account_id: number };
type AccountNameRow = { account_id: number; name: string };
export interface TaxCharacterRow {
	code: string;
	label: string;
	display_order: number | null;
}

export interface LoadedMonthlyReport {
	header: MonthlyReportHeader;
	payload: MonthlyReportPayload;
	taxCharacters: TaxCharacterRow[];
	staleness: StalenessData;
	cashflowRowStaleness: CashflowRowStalenessMap;
	staleAccountNames: string[];
}

/**
 * Load everything MonthlyReportView.svelte needs for `targetMonth` (already-validated
 * `YYYY-MM-01`), under the CALLER's OWN `supabase` client (RLS-scoped, never service_role —
 * RT-13). Throws SvelteKit `error()` (400/404/500 — the caller's `params`/`url` context is
 * not needed here, since `targetMonth` arrives pre-validated) on the same conditions the
 * original P2/P8 loader did; both a `+page.server.ts` `load` and a `+server.ts` handler
 * treat a thrown `error()` identically, so this module does not need two call shapes.
 */
export async function loadMonthlyReportForRender(
	supabase: SupabaseClient,
	targetMonth: string
): Promise<LoadedMonthlyReport> {
	const { data: rows, error: reportErr } = await supabase
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
	// `final` wins over `draft` if somehow both are resolved — see the original loader's
	// header. Not expected to need it in ordinary Lock 11 workflow, but never an arbitrary
	// row-age tiebreak either.
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
			// 108's own CHECK forbids this state; a real DB-contract violation, not a
			// candidate for fail-soft degrade.
			throw error(500, 'This report is missing its stored content.');
		}
		payload = row.rendered_payload;
	} else {
		const { data: composed, error: renderErr } = await supabase
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

	const { data: taxCharacters, error: taxCharacterErr } = await supabase
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

	// P8 (SELF-360 AC2/AC4/AC7, RT-13) — see the original loader's own header for the full
	// design (unchanged, only relocated here). Fail-soft on the root read: a transient
	// failure degrades every downstream marker to UNKNOWN, never a fabricated "confirmed
	// healthy" — the report still renders.
	let staleness: StalenessData = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(supabase);
	} catch (err) {
		console.error('[loadMonthlyReportForRender] staleness load threw; degrading to unknown staleness:', err);
	}
	const staleLinkedSourceIds =
		staleness.is_stale === null
			? null
			: new Set(staleness.stale_items.map((item) => String(item.linked_source_id)));

	// ONE join, reused twice below (Account Holdings' per-leaf refresh + the Cash Flow row
	// map). `null` when the root read was itself unknown — skip entirely, mirroring
	// loadNavComposition's own root-unknown-skip convention.
	const staleAccountIds =
		staleLinkedSourceIds === null ? null : await resolveStaleAccountIds(supabase, staleLinkedSourceIds);

	// (1) Account Holdings — refresh the payload's own leaves with the CURRENT join. A
	// brand-new object tree, never a mutation of `payload` in place — this OVERWRITES
	// whatever `is_stale` arrived with the payload (frozen at generation for `final`, or
	// already-stale-by-the-time-you-clicked for `draft`).
	payload = {
		...payload,
		sections: {
			...payload.sections,
			account_holdings: {
				...payload.sections.account_holdings,
				groups: payload.sections.account_holdings.groups.map((group) => ({
					...group,
					accounts: group.accounts.map((account) => ({
						...account,
						is_stale: staleAccountIds === null ? null : staleAccountIds.has(String(account.account_id))
					}))
				}))
			}
		}
	};

	// (2) Cash Flow per-row map (AC4's shipped V1.3 shape, reused verbatim) — at the
	// report's OWN `data_as_of` (Lock 15), never today's date.
	let cashflowRowStaleness: CashflowRowStalenessMap = EMPTY_CASHFLOW_ROW_STALENESS;
	if (staleAccountIds !== null) {
		try {
			const contributors = await loadCashflowContributors(supabase, userSuppliedAsOf(row.data_as_of));
			if (contributors !== null) {
				cashflowRowStaleness = computeCashflowRowStaleness(contributors, staleAccountIds);
			}
		} catch (err) {
			console.error(
				'[loadMonthlyReportForRender] cashflow contributor read threw; degrading to empty row-staleness map:',
				err
			);
		}
	}

	// (3) Report-level banner (AC3/AC7) — MEMBERSHIP from migration 109's frozen snapshot
	// (`final` only — a `draft` has no snapshot rows), NAMES resolved LIVE. Never conflate
	// the two questions: 109 answers "did this account contribute to THIS report"; the live
	// `account` read answers "what is it called RIGHT NOW."
	let staleAccountNames: string[] = [];
	if (staleAccountIds !== null && staleAccountIds.size > 0) {
		let memberAccountIds: ReadonlySet<string>;
		if (row.generation_status === 'final') {
			const { data: snapshotRows, error: snapshotErr } = await supabase
				.schema('pfin')
				.from('monthly_report_account_snapshot')
				.select('account_id')
				.eq('monthly_report_id', row.report_id);

			if (snapshotErr) {
				console.error(
					'[loadMonthlyReportForRender] account-snapshot read failed; banner degrades to no names:',
					snapshotErr.message
				);
				memberAccountIds = new Set();
			} else {
				memberAccountIds = new Set(
					((snapshotRows ?? []) as AccountSnapshotRow[]).map((s) => String(s.account_id))
				);
			}
		} else {
			// `draft`: no frozen membership set exists yet (109 is written only at
			// finalization) — the report's own render is already fully live, so every
			// currently-stale account is, by construction, "as of today" content this
			// draft would show.
			memberAccountIds = staleAccountIds;
		}

		const bannerAccountIds = [...staleAccountIds].filter((id) => memberAccountIds.has(id));
		if (bannerAccountIds.length > 0) {
			const { data: accountRows, error: accountErr } = await supabase
				.schema('pfin')
				.from('account')
				.select('account_id, name')
				.in('account_id', bannerAccountIds);

			if (accountErr) {
				console.error(
					'[loadMonthlyReportForRender] live account-name read failed; banner degrades to no names:',
					accountErr.message
				);
			} else {
				staleAccountNames = ((accountRows ?? []) as AccountNameRow[]).map((a) => a.name).sort();
			}
		}
	}

	return { header, payload, taxCharacters: taxCharacters ?? [], staleness, cashflowRowStaleness, staleAccountNames };
}
