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
	const pending: PendingEntry[] = allRows
		.filter((r) => r.generation_status === 'draft')
		.map((r) => ({
			reportId: r.report_id,
			targetMonth: r.target_month,
			monthLabel: monthLabel(r.target_month)
		}));

	const candidates = candidatesFor(allRows, serverTodayAsOf());

	return { generated, pending, candidates };
};

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
	}
};
