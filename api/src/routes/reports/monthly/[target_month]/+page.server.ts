// reports/monthly/[target_month]/+page.server.ts — loader for the §2.6.1.b in-app monthly report
// render (SELF-354 / P2), on top of migration 108 (pfin.monthly_report), 109
// (pfin.monthly_report_account_snapshot — read here at P8/SELF-360 for the stale-banner's
// MEMBERSHIP scope only, never for display names — see that block's own comment), and 110
// (pfin.fn_render_monthly_report), landed on feature/self-345 @ be7aed6.
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-359's and SELF-361's own): this file lives under
// Backend's ARCH §4.1 allowlist surface and was authored by Frontend under this ticket's explicit
// dispatch, which named the read path and directed it be built here. Flagged for a Backend/Sec
// re-read at the mandatory joint review this surface carries (P2 is Sec joint-review MANDATORY —
// team-lead's own dispatch). P8's own staleness additions are NOT independently Sec-joint-review-
// mandatory (R13 gates name P8/P9 as the two exceptions) but carry the RT-13 label and are
// walk-gated before any Sec touch.
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
//
// P8 STALENESS (SELF-360 AC2/AC4/AC7, RT-13): markers are computed LIVE at every render — NEVER
// frozen, even for a `final` row's own `rendered_payload` (AC2's frozen-OUT carve-out survives
// R1 (A) intact: the payload freezes VALUES, staleness is not a value). This loader is therefore
// the ONE place staleness enters the render, regardless of which path produced `payload`.
//
// ONE `loadStaleness()` read (whole-tenant, the SAME read every other V1.1+ surface already
// consumes, under `locals.supabase` — RLS-scoped by construction, never service_role) feeds every
// section-level `<StaleConstituentBadge>`. ONE `resolveStaleAccountIds` join (navComposition.ts's
// own exported SELF-330 bridge — "do not fork this logic") is computed ONCE and reused twice:
// (1) overwriting Account Holdings' own per-leaf `is_stale` with the CURRENT join — discarding
// whatever value arrived on the payload's own leaves, frozen or otherwise, per AC2; (2) feeding
// `computeCashflowRowStaleness` (AC4's shipped V1.3 shape) at the report's OWN `data_as_of` (Lock
// 15 — never today's date), for the Cash Flow section's per-row map.
//
// THE BANNER (AC3/AC7) is scoped differently from the account-name question — a MEMBERSHIP
// question, not a naming one: which of the tenant's CURRENTLY stale accounts actually belong to
// THIS report. For a `final` row, membership is migration 109's own frozen snapshot
// (`monthly_report_account_snapshot`, written only at finalization) intersected against the live
// join — an account that never contributed to this specific report has no business in ITS
// banner even if it happens to be stale today. For a `draft` row, 109 carries NO rows at all
// (written only at finalization — a genuine draft has none, per 109's own header) — a draft's
// entire render is already live-composed moments ago, so there is no frozen membership set to
// intersect against; membership degrades to the full live-stale-account set. ⚠ NAMES, in BOTH
// cases, are resolved LIVE (`pfin.account.name`, the SAME small query shape
// `loadExcludedTaxLedgers` already uses in navComposition.ts) — team-lead's explicit ruling on
// this ticket's own incident: "a live sentence must not carry frozen names beside live tables."
// 109's `acct_name_at_generation` is read here ONLY to resolve which account_ids belong to this
// report, never to label them.

import { error, redirect } from '@sveltejs/kit';
import { INVENTORY_SEED_DELTA_MIGRATION } from '$lib/server/queries/taxLiability';
import { parseTargetMonth } from '$lib/monthly-report';
import type { MonthlyReportHeader, MonthlyReportPayload } from '$lib/monthly-report';
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
import type { PageServerLoad } from './$types';

type MonthlyReportRow = MonthlyReportHeader & { rendered_payload: MonthlyReportPayload | null };

type AccountSnapshotRow = { account_id: number };
type AccountNameRow = { account_id: number; name: string };

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

	// P8 (SELF-360 AC2/AC4/AC7, RT-13) — see file header for the full design. Fail-soft on the
	// root read, mirroring every other V1.1+ surface: a transient failure degrades every
	// downstream marker to UNKNOWN, never a fabricated "confirmed healthy" — the report still
	// renders. `loadStaleness` already fails soft internally; the try/catch here is defense-in-
	// depth against a throw before that function's own promise resolves (same posture P3's
	// commentary loader already takes around this identical call).
	let staleness: StalenessData = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[reports/monthly] staleness load threw; degrading to unknown staleness:', err);
	}
	const staleLinkedSourceIds =
		staleness.is_stale === null
			? null
			: new Set(staleness.stale_items.map((item) => String(item.linked_source_id)));

	// ONE join, reused twice below (Account Holdings' per-leaf refresh + the Cash Flow row map).
	// `null` when the root read was itself unknown — skip entirely, mirroring
	// loadNavComposition's own root-unknown-skip convention.
	const staleAccountIds =
		staleLinkedSourceIds === null ? null : await resolveStaleAccountIds(locals.supabase, staleLinkedSourceIds);

	// (1) Account Holdings — refresh the payload's own leaves with the CURRENT join. A brand-new
	// object tree, never a mutation of `payload` in place (mirrors loadNavComposition's own
	// documented discipline) — this OVERWRITES whatever `is_stale` arrived with the payload
	// (frozen at generation for `final`, or already-stale-by-the-time-you-clicked for `draft`).
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

	// (2) Cash Flow per-row map (AC4's shipped V1.3 shape, reused verbatim) — at the report's OWN
	// `data_as_of` (Lock 15), never today's date. `userSuppliedAsOf` re-brands an already-
	// validated stored date (`row.data_as_of` is real by construction — 108's own column type),
	// the same factory every other "already have a real DB date" call site in this tree uses.
	let cashflowRowStaleness: CashflowRowStalenessMap = EMPTY_CASHFLOW_ROW_STALENESS;
	if (staleAccountIds !== null) {
		try {
			const contributors = await loadCashflowContributors(locals.supabase, userSuppliedAsOf(row.data_as_of));
			if (contributors !== null) {
				cashflowRowStaleness = computeCashflowRowStaleness(contributors, staleAccountIds);
			}
		} catch (err) {
			console.error(
				'[reports/monthly] cashflow contributor read threw; degrading to empty row-staleness map:',
				err
			);
		}
	}

	// (3) Report-level banner (AC3/AC7) — MEMBERSHIP from migration 109's frozen snapshot
	// (`final` only — a `draft` has no snapshot rows, see file header), NAMES resolved LIVE.
	// Never conflate the two questions: 109 answers "did this account contribute to THIS
	// report"; the live `account` read answers "what is it called RIGHT NOW."
	let staleAccountNames: string[] = [];
	if (staleAccountIds !== null && staleAccountIds.size > 0) {
		let memberAccountIds: ReadonlySet<string>;
		if (row.generation_status === 'final') {
			const { data: snapshotRows, error: snapshotErr } = await locals.supabase
				.schema('pfin')
				.from('monthly_report_account_snapshot')
				.select('account_id')
				.eq('monthly_report_id', row.report_id);

			if (snapshotErr) {
				console.error(
					'[reports/monthly] account-snapshot read failed; banner degrades to no names:',
					snapshotErr.message
				);
				memberAccountIds = new Set();
			} else {
				memberAccountIds = new Set(
					((snapshotRows ?? []) as AccountSnapshotRow[]).map((s) => String(s.account_id))
				);
			}
		} else {
			// `draft`: no frozen membership set exists yet (109 is written only at finalization) —
			// the report's own render is already fully live, so every currently-stale account is,
			// by construction, "as of today" content this draft would show.
			memberAccountIds = staleAccountIds;
		}

		const bannerAccountIds = [...staleAccountIds].filter((id) => memberAccountIds.has(id));
		if (bannerAccountIds.length > 0) {
			const { data: accountRows, error: accountErr } = await locals.supabase
				.schema('pfin')
				.from('account')
				.select('account_id, name')
				.in('account_id', bannerAccountIds);

			if (accountErr) {
				console.error(
					'[reports/monthly] live account-name read failed; banner degrades to no names:',
					accountErr.message
				);
			} else {
				staleAccountNames = ((accountRows ?? []) as AccountNameRow[]).map((a) => a.name).sort();
			}
		}
	}

	return {
		header,
		payload,
		taxCharacters: taxCharacters ?? [],
		seedDeltaMigration: INVENTORY_SEED_DELTA_MIGRATION,
		staleness,
		cashflowRowStaleness,
		staleAccountNames
	};
};
