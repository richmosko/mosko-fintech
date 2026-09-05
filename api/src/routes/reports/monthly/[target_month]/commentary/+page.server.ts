// reports/monthly/[target_month]/commentary/+page.server.ts — loader + save action for the
// §2.6.2.b commentary editor (SELF-355 / P3), on top of migration 108 (pfin.monthly_report) and
// migration 112 (pfin.fn_save_monthly_commentary), landed on feature/self-355-db @ 5789c2d
// (stacked on the A1+A2+A3 unit).
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-354/359/361's own): this file lives under Backend's ARCH
// §4.1 allowlist surface and was authored by Frontend under this ticket's explicit dispatch.
// Flagged for a Backend/Sec re-read at the RT-11 joint review this surface carries.
//
// ⚠ CROSS-BRANCH NOTE, flagged rather than silently duplicated: this branch is stacked on the DB
// unit (5789c2d), NOT on top of SELF-354/P2's own frontend branch, so P2's
// `reports/monthly/[target_month]/+page.server.ts` and `$lib/monthly-report.ts` do NOT exist here.
// `parseTargetMonth` below is therefore a SECOND, independent copy of the exact same `YYYY-MM`
// regex + normalization P2's loader already has — not a shared import. Whoever integrates the two
// branches should extract one shared helper; this file does not invent a dependency on a module
// that does not exist on its own branch.
//
// READ PATH: this route only ever WRITES to a `draft` (112's own precondition), but it must still
// RENDER for a `final` month (a user can reach this URL directly, or via a stale bookmark) — in
// that case the editor renders READ-ONLY (disabled controls, no Save/Finalize), showing the
// row's own current commentary values (frozen, since the row is immutable). `superseded` rows are
// never the target of this route (R10 A-8, mirrors P2).
//
// PRIOR-MONTH REFERENCE (AC2): commentary columns live directly ON THE ROW (migration 108) for
// EVERY `generation_status` — there is no frozen-vs-live distinction to make for this read, unlike
// P2's `rendered_payload`. A missing prior-month row degrades to "nothing to copy" (never a 404 —
// this is a reference read, not the page's own subject).
//
// $ REALLOC REFERENCE PANEL (AC3): the SAME live read `/allocation` uses — `loadStaleness` +
// `loadNonReAllocation(supabase, asOf, staleLinkedSourceIds)` at `serverTodayAsOf()` — reused
// VERBATIM, not a placeholder. This is NOT a P8 slot (unlike P2's own staleness placeholders):
// SELF-330's per-row staleness tint on this exact table already shipped and is live-wired
// elsewhere on this tree; skipping it here would be a regression against what already exists,
// not a deferral to not-yet-built work.

import { error, redirect, fail } from '@sveltejs/kit';
import { loadStaleness } from '$lib/server/queries/staleness';
import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
import { loadNonReAllocation } from '$lib/server/queries/nonReAllocation';
import type { NonReAllocation } from '$lib/nonre-allocation';
import { serverTodayAsOf } from '$lib/server/time/asOf';
import { monthlyCommentaryUpsertSchema } from '$lib/server/schemas/monthly-commentary';
import { fieldErrors } from '$lib/server/schemas/account';
import type { PostgrestError } from '@supabase/supabase-js';
import type { PageServerLoad, Actions } from './$types';

const TARGET_MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

function parseTargetMonth(raw: string): string | null {
	if (!TARGET_MONTH_RE.test(raw)) return null;
	return `${raw}-01`;
}

/** One calendar month before `targetMonth` (`YYYY-MM-01`), computed in UTC so this never shifts
 *  under a non-UTC server clock — mirrors every other date-formatting helper on this tree. */
function priorMonthOf(targetMonth: string): string {
	const d = new Date(`${targetMonth}T00:00:00Z`);
	d.setUTCMonth(d.getUTCMonth() - 1);
	return d.toISOString().slice(0, 10);
}

function monthLabel(isoMonth: string): string {
	return new Date(`${isoMonth}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC'
	});
}

type CommentaryRow = {
	report_id: number;
	target_month: string;
	generation_status: 'draft' | 'final' | 'superseded';
	commentary_cash: string | null;
	commentary_bonds: string | null;
	commentary_marketable_securities: string | null;
	commentary_alternatives: string | null;
};

export type CommentaryValues = {
	cash: string;
	bonds: string;
	marketable_securities: string;
	alternatives: string;
};

function toCommentaryValues(row: Pick<CommentaryRow, 'commentary_cash' | 'commentary_bonds' | 'commentary_marketable_securities' | 'commentary_alternatives'> | null): CommentaryValues {
	return {
		cash: row?.commentary_cash ?? '',
		bonds: row?.commentary_bonds ?? '',
		marketable_securities: row?.commentary_marketable_securities ?? '',
		alternatives: row?.commentary_alternatives ?? ''
	};
}

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
			'report_id, target_month, generation_status, commentary_cash, commentary_bonds, commentary_marketable_securities, commentary_alternatives'
		)
		.eq('target_month', targetMonth)
		.in('generation_status', ['final', 'draft']);

	if (reportErr) {
		throw error(500, 'Could not load this report. Please try again.');
	}

	const allRows = (rows ?? []) as CommentaryRow[];
	const row =
		allRows.find((r) => r.generation_status === 'final') ??
		allRows.find((r) => r.generation_status === 'draft') ??
		null;

	if (!row) {
		throw error(404, 'No report found for this month.');
	}

	const priorMonth = priorMonthOf(targetMonth);
	const { data: priorRow } = await locals.supabase
		.schema('pfin')
		.from('monthly_report')
		.select('commentary_cash, commentary_bonds, commentary_marketable_securities, commentary_alternatives')
		.eq('target_month', priorMonth)
		.order('report_id', { ascending: false })
		.limit(1)
		.maybeSingle();

	// $ ReAlloc reference panel — the SAME live read /allocation uses (see file header). Fail-soft
	// on both reads (mirrors that route's own posture): a transient failure degrades to an absent
	// panel / unknown staleness, never a 500 on THIS page (the editor is still usable without it).
	const asOf = serverTodayAsOf();
	let staleness = UNKNOWN_STALENESS;
	try {
		staleness = await loadStaleness(locals.supabase);
	} catch (err) {
		console.error('[reports/monthly/commentary] staleness load threw; degrading to unknown staleness:', err);
	}
	const staleLinkedSourceIds =
		staleness.is_stale === null ? null : new Set(staleness.stale_items.map((item) => String(item.linked_source_id)));

	let allocation: NonReAllocation | null = null;
	try {
		const result = await loadNonReAllocation(locals.supabase, asOf, staleLinkedSourceIds);
		allocation = result.ok ? result.data : null;
	} catch (err) {
		console.error('[reports/monthly/commentary] allocation load threw; degrading to null:', err);
	}

	return {
		targetMonth,
		targetMonthLabel: monthLabel(targetMonth),
		isDraft: row.generation_status === 'draft',
		commentary: toCommentaryValues(row),
		priorMonthLabel: monthLabel(priorMonth),
		priorCommentary: toCommentaryValues(priorRow as CommentaryRow | null),
		allocation,
		staleness
	};
};

/** Maps a pfin.fn_save_monthly_commentary failure to a clean 4xx. Every message this function
 *  raises names its own function name and/or the exact draft-state reasoning (see 112's own
 *  header) — NEVER forwarded verbatim to the client (AC/RT-11: "no constraint/function name
 *  leaked"). One generic sentence covers both of 112's raised-exception cases (no report / not a
 *  draft) — from the caller's perspective both mean "you can't save commentary here right now",
 *  and collapsing them costs nothing: a cross-tenant caller and an owner whose report is missing
 *  see the identical message either way (non-disclosure by construction, not by effort). */
function mapSaveError(error: PostgrestError): { status: number; message: string } {
	switch (error.code) {
		case '42501':
			return {
				status: 403,
				message: 'This action requires a freshly verified session. Please step up and try again.'
			};
		case '23514':
			return {
				status: 400,
				message: 'Could not save — one section is over the character limit. Please shorten it and try again.'
			};
		case 'P0001':
			return {
				status: 400,
				message:
					'Could not save commentary for this month — the report may already be finalized, or no longer exists. Refresh and try again.'
			};
		default:
			console.error('[reports/monthly/commentary] unexpected write error:', error.code, error.message);
			return { status: 500, message: 'Something went wrong. Please try again.' };
	}
}

export const actions: Actions = {
	save: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const targetMonth = parseTargetMonth(params.target_month);
		if (targetMonth === null) {
			return fail(400, { errors: { _form: ['Invalid target month.'] } });
		}

		const form = await request.formData();
		const parsed = monthlyCommentaryUpsertSchema.safeParse({
			cash: String(form.get('cash') ?? ''),
			bonds: String(form.get('bonds') ?? ''),
			marketable_securities: String(form.get('marketable_securities') ?? ''),
			alternatives: String(form.get('alternatives') ?? '')
		});
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		const { error: rpcError } = await locals.supabase.schema('pfin').rpc('fn_save_monthly_commentary', {
			p_target_month: targetMonth,
			p_cash: parsed.data.cash,
			p_bonds: parsed.data.bonds,
			p_marketable_securities: parsed.data.marketable_securities,
			p_alternatives: parsed.data.alternatives
		});

		if (rpcError) {
			const { status, message } = mapSaveError(rpcError);
			return fail(status, { errors: { _form: [message] } });
		}

		return { ok: true as const, commentary: parsed.data };
	}
};
