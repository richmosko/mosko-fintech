// reports/monthly/+page.server.ts — the §2.6.3.b report listing + on-demand generation + pending
// queue (SELF-357 / P5), on top of migration 108 (pfin.monthly_report), migration 113
// (pfin.fn_open_monthly_report_draft) and migration 114 (pfin.fn_regenerate_monthly_report), all
// landed on feature/self-355-db (stacked, indirectly, via feature/self-355's own P3 branch).
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-354/355/359/361's own): this file lives under Backend's
// ARCH §4.1 allowlist surface and was authored by Frontend under this ticket's explicit dispatch.
// Flagged for a Backend/Sec re-read — this surface calls a JOINT-REVIEW-MANDATORY DB function
// (114, the only user-reachable final -> superseded path) from a form action.
//
// SCOPE (E15 items 8-10, rederived-acs.md AC 1-7): P5 CALLS A10's write path; it does not
// implement it (AC5). This file's own job is: list `final` rows (one per target_month —
// superseded rows are history, never listed, AC7); list the pending queue (`draft` rows,
// AC2 — "pending" means awaiting COMMENTARY, not a job state: no queued/in-flight/done, no
// generation-failed notice); and post to `?/generate` (113) / `?/regenerate` (114) under the
// caller's own session, never taking a `data_as_of` parameter (AC6, Lock 15, RT-25 — 113/114
// derive it server-side; this file has no argument by which to pass one even if it wanted to).
//
// TARGET-MONTH CANDIDATES (AC3): V1 offers exactly TWO selectable months for on-demand
// generation — the prior month (default) and the current month-in-progress — both derived from
// `serverTodayAsOf()` (UTC, matching every other as-of in this tree), never from a client value.
// JUDGMENT CALL, flagged: `?/generate` REFUSES any `target_month` that is not one of these two
// freshly-recomputed candidates (400), even though 113 itself is safe to call against ANY month
// (idempotent, RLS-scoped, no cross-tenant path) — AC3's "the user selects A target month" reads
// as a V1 scope commitment to exactly two options, not an open picker, and this is the
// structural-picker-over-validation-only-rejection posture applied to a PRODUCT-scope boundary
// rather than a security one. `?/regenerate` does NOT carry the same restriction — it only
// checks the month is a real month-start string — because 114's own contract already handles
// "no report" / "draft present" / "final present" safely for ANY month (its own header: "a
// month with no report at all is also answered by 113"), so restricting it further would be
// inventing a fence 114 doesn't need and the listing UI doesn't ask for (Regenerate only ever
// renders on an existing `final` row's own month in this file's own markup).
//
// CROSS-BRANCH NOTE (same class as P3's own): this branch has none of P2's frontend files
// (`$lib/monthly-report.ts`'s `monthYearStamp()`, etc.) — `monthStart`/`monthLabel` below are a
// third self-contained local copy of the same YYYY-MM-01 helpers P2 and P3 each already carry
// their own copy of. Flagged for the eventual rebase-integration extraction, same as those two.

import { error, fail, redirect } from '@sveltejs/kit';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import { noLedgerDesignated, type MonthlyReportPayload } from '$lib/monthly-report';
import { skipFinalizeSchema } from '$lib/server/schemas/monthly-report-finalize';
import { fieldErrors } from '$lib/server/schemas/account';
import type { PostgrestError } from '@supabase/supabase-js';
import type { Actions, PageServerLoad } from './$types';

const MONTH_START_RE = /^\d{4}-\d{2}-01$/;

/** `monthsAgo` months before `todayIso`'s own month, at the 1st, in UTC — mirrors
 *  reports/monthly/[target_month]/commentary/+page.server.ts's `priorMonthOf` shape,
 *  generalized to an arbitrary offset (0 = current month). */
function monthStart(todayIso: string, monthsAgo: number): string {
	const d = new Date(`${todayIso}T00:00:00Z`);
	d.setUTCDate(1);
	d.setUTCMonth(d.getUTCMonth() - monthsAgo);
	return d.toISOString().slice(0, 10);
}

function monthLabel(isoMonth: string): string {
	return new Date(`${isoMonth}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC'
	});
}

type ReportRow = {
	report_id: number;
	target_month: string;
	generation_status: 'draft' | 'final';
	generated_at: string | null;
	data_as_of: string;
};

export type ListingEntry = {
	reportId: number;
	targetMonth: string;
	monthLabel: string;
	generatedAt: string | null;
};

export type PendingEntry = {
	reportId: number;
	targetMonth: string;
	monthLabel: string;
	// P4 (SELF-356 AC4) — see this file's `load()` for how this is derived (composed draft
	// payload's own tax-authority exclusion envelope, not a second query). Fail-soft `false` on a
	// composition-read failure — a missed nudge, never a blocked/broken listing page.
	noLedgerDesignated: boolean;
};

type CandidateState = 'none' | 'draft' | 'final';
/** `label` is the full `<option>` display text (current month carries the "(in progress — as of
 *  today)" suffix, AC3 verbatim); `plainLabel` is the bare "{Month YYYY}" the CTA button text
 *  interpolates into "Continue {Month YYYY}" / the Regenerate confirm copy shares — kept as a
 *  SEPARATE field rather than stripped client-side, so the client never re-derives or parses a
 *  server-formatted string. */
export type Candidate = { targetMonth: string; label: string; plainLabel: string; state: CandidateState };

function candidatesFor(rows: ReportRow[], today: string): Candidate[] {
	const priorMonth = monthStart(today, 1);
	const currentMonth = monthStart(today, 0);
	const stateFor = (month: string): CandidateState => {
		const row = rows.find((r) => r.target_month === month);
		return row ? row.generation_status : 'none';
	};
	return [
		{
			targetMonth: priorMonth,
			label: monthLabel(priorMonth),
			plainLabel: monthLabel(priorMonth),
			state: stateFor(priorMonth)
		},
		{
			targetMonth: currentMonth,
			label: `${monthLabel(currentMonth)} (in progress — as of today)`,
			plainLabel: monthLabel(currentMonth),
			state: stateFor(currentMonth)
		}
	];
}

export const load: PageServerLoad = async ({ locals, url }) => {
	const { user } = await locals.safeGetSession();
	if (!user) throw redirect(303, `/login?redirectTo=${encodeURIComponent(url.pathname)}`);

	// AC7 / AC1: `superseded` is history, never listed — `.in(...)` excludes it structurally
	// rather than filtering it out after the fact.
	const { data: rows, error: readErr } = await locals.supabase
		.schema('pfin')
		.from('monthly_report')
		.select('report_id, target_month, generation_status, generated_at, data_as_of')
		.in('generation_status', ['final', 'draft'])
		.order('target_month', { ascending: false });

	if (readErr) {
		throw error(500, 'Could not load your monthly reports. Please try again.');
	}

	const allRows = (rows ?? []) as ReportRow[];

	// AC7: at most one `final` per target_month (108's own partial unique index) — this is
	// already the listing shape, not a fold this loader has to perform.
	const generated: ListingEntry[] = allRows
		.filter((r) => r.generation_status === 'final')
		.map((r) => ({
			reportId: r.report_id,
			targetMonth: r.target_month,
			monthLabel: monthLabel(r.target_month),
			generatedAt: r.generated_at
		}));

	// AC2: one pending item per month (at most one live draft per month, 108's sibling partial
	// unique index) — "pending" means awaiting COMMENTARY, not a job-state queue.
	//
	// P4 (SELF-356 AC4, R1 rider 6) — each pending item ALSO carries `noLedgerDesignated`, derived
	// from composing that draft's OWN payload via `fn_render_monthly_report(target_month,
	// data_as_of)` — the SAME live-compose call `[target_month]/+page.server.ts` already makes for
	// a draft's own render, not a new dedicated query. One RPC per pending row: bounded in ordinary
	// V1 use (at most the two `?/generate` candidate months plus any month a user has re-opened via
	// `?/regenerate` and not yet re-finalized), but JUDGMENT CALL flagged at hand-off — nothing
	// structurally caps how many drafts could accumulate pending over time, and this is full
	// report composition run purely to read one boolean off it. Fail-soft per row: a composition
	// failure degrades that row's own `noLedgerDesignated` to `false` (a missed nudge, never a
	// blocked listing page — "a prompt, not a block" extends to its own read failing, too).
	const draftRows = allRows.filter((r) => r.generation_status === 'draft');
	const pending: PendingEntry[] = await Promise.all(
		draftRows.map(async (r) => {
			let flagged = false;
			try {
				const { data: composed, error: renderErr } = await locals.supabase
					.schema('pfin')
					.rpc('fn_render_monthly_report', {
						p_target_month: r.target_month,
						p_data_as_of: r.data_as_of
					});
				if (!renderErr && composed) {
					flagged = noLedgerDesignated(composed as MonthlyReportPayload);
				}
			} catch (err) {
				console.error(
					'[reports/monthly] pending-item payload composition threw; degrading noLedgerDesignated to false:',
					err
				);
			}
			return {
				reportId: r.report_id,
				targetMonth: r.target_month,
				monthLabel: monthLabel(r.target_month),
				noLedgerDesignated: flagged
			};
		})
	);

	const candidates = candidatesFor(allRows, serverTodayAsOf());

	return { generated, pending, candidates };
};

/** Maps a `pfin.fn_finalize_monthly_report` failure to a clean 4xx/5xx — mirrors
 *  `[target_month]/commentary/+page.server.ts`'s own `mapSaveError` precedent for the sibling 112
 *  write path. 115 raises both of its user-reachable refusals as plain `RAISE EXCEPTION` (default
 *  SQLSTATE `P0001`, no discriminating code) — its own header states the "no live draft" refusal
 *  is DELIBERATELY non-discriminating ("absent / not-yours / already-final ... under RLS those are
 *  one condition and separating them leaks existence"), and this app's own two call sites always
 *  pass a literal `'authored'`/`'skipped'` disposition (never client-supplied), so the "invalid
 *  disposition" refusal is a defensive DB-side check against a caller this app never is, not a
 *  case this mapper needs to discriminate either — one generic sentence covers both P0001 cases,
 *  same non-disclosure-by-construction posture as `mapSaveError`. */
function mapFinalizeError(error: PostgrestError): { status: number; message: string } {
	switch (error.code) {
		case '42501':
			return {
				status: 403,
				message: 'This action requires a freshly verified session. Please step up and try again.'
			};
		case 'P0001':
			return {
				status: 400,
				message:
					'Could not finalize this report — it may already be finalized, or no longer exists. Refresh and try again.'
			};
		default:
			console.error('[reports/monthly] unexpected finalize error:', error.code, error.message);
			return { status: 500, message: 'Something went wrong. Please try again.' };
	}
}

export const actions: Actions = {
	generate: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const targetMonth = String(form.get('target_month') ?? '');
		if (!MONTH_START_RE.test(targetMonth)) {
			return fail(400, { errors: { _form: ['Invalid target month.'] } });
		}

		// Structural picker (see file header): only the two freshly-recomputed candidates are
		// legal, regardless of what a tampered form posts.
		const legalMonths = candidatesFor([], serverTodayAsOf()).map((c) => c.targetMonth);
		if (!legalMonths.includes(targetMonth)) {
			return fail(400, { errors: { _form: ['That month is not available for generation.'] } });
		}

		const { data: reportId, error: rpcError } = await locals.supabase
			.schema('pfin')
			.rpc('fn_open_monthly_report_draft', { p_target_month: targetMonth });

		if (rpcError || typeof reportId !== 'number') {
			return fail(500, { errors: { _form: ['Something went wrong. Please try again.'] } });
		}

		// AC5 / PRD §2.6.3 author-before-generate: the flow opens P3's commentary editor first —
		// this action's whole job ends at the RPC call plus this redirect.
		throw redirect(303, `/reports/monthly/${targetMonth.slice(0, 7)}/commentary`);
	},

	regenerate: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		const targetMonth = String(form.get('target_month') ?? '');
		if (!MONTH_START_RE.test(targetMonth)) {
			return fail(400, { errors: { _form: ['Invalid target month.'] } });
		}

		const { data: reportId, error: rpcError } = await locals.supabase
			.schema('pfin')
			.rpc('fn_regenerate_monthly_report', { p_target_month: targetMonth });

		if (rpcError || typeof reportId !== 'number') {
			return fail(500, { errors: { _form: ['Something went wrong. Please try again.'] } });
		}

		throw redirect(303, `/reports/monthly/${targetMonth.slice(0, 7)}/commentary`);
	},

	// P4 (SELF-356 AC1/AC5) — "Skip commentary and finalize", the pending list's own secondary CTA
	// (inline two-step confirm in the component, never window.confirm — see
	// PendingMonthlyReportItem.svelte / SkipFinalizeControl.svelte). Calls 115 with the `'skipped'`
	// disposition, the DURABLE authored-vs-skipped fact (R12(A): a skipped month does not count
	// toward SELF-365's N=2 gate) — skip is a first-class V1 affordance, not a workaround (AC1).
	// `p_commentary_disposition` is this action's OWN literal, never a posted field (see
	// monthly-report-finalize.ts's own header).
	skip: async ({ request, locals }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const form = await request.formData();
		// Whole-form parse (not a hand-picked single field) so `.strict()` actually fences a stray
		// posted field — a manual `form.get('target_month')` extraction would silently ignore
		// anything else in the body, making the mass-assignment mirror decorative rather than real.
		const parsed = skipFinalizeSchema.safeParse(Object.fromEntries(form));
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		const { data: reportId, error: rpcError } = await locals.supabase
			.schema('pfin')
			.rpc('fn_finalize_monthly_report', {
				p_target_month: parsed.data.target_month,
				p_commentary_disposition: 'skipped'
			});

		if (rpcError || typeof reportId !== 'number') {
			const { status, message } = rpcError
				? mapFinalizeError(rpcError)
				: { status: 500, message: 'Something went wrong. Please try again.' };
			return fail(status, { errors: { _form: [message] } });
		}

		// AC6 / P2's final view — the promotion is 115's own UPDATE; nothing inserts final
		// directly, so the row this route now navigates to is the SAME report_id, freshly `final`.
		throw redirect(303, `/reports/monthly/${parsed.data.target_month.slice(0, 7)}`);
	}
};
