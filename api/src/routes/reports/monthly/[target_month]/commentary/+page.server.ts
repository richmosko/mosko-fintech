// reports/monthly/[target_month]/commentary/+page.server.ts — loader + save action for the
// §2.6.2.b commentary editor (SELF-355 / P3), on top of migration 108 (pfin.monthly_report) and
// migration 112 (pfin.fn_save_monthly_commentary).
//
// ⚠ AUTHORSHIP NOTE (same class as SELF-354/359/361's own): this file lives under Backend's ARCH
// §4.1 allowlist surface and was authored by Frontend under this ticket's explicit dispatch.
// Flagged for a Backend/Sec re-read at the RT-11 joint review this surface carries.
//
// SHARED-MODULE NOTE (was a CROSS-BRANCH duplication, resolved at the P2/P3/P5 rebase-integration,
// 2026-09-05): this file originally carried its own local `parseTargetMonth` and its own exported
// `CommentaryValues` because it was authored on a branch stacked on the DB-only unit, not on top of
// P2's own frontend branch — P2's `$lib/monthly-report.ts` didn't exist on this branch's tree yet.
// Now that P3 is rebased ONTO P2, both are imported from `$lib/monthly-report.ts` instead — the ONE
// shared copy every `/reports/monthly` route uses. `MonthlyCommentaryEditor.svelte`'s own former
// local `CommentaryValues` interface is likewise gone, importing this same one.
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
import { authoredFinalizeSchema } from '$lib/server/schemas/monthly-report-finalize';
import { fieldErrors } from '$lib/server/schemas/account';
import {
	parseTargetMonth,
	noLedgerDesignated as computeNoLedgerDesignated,
	type CommentaryValues,
	type MonthlyReportPayload
} from '$lib/monthly-report';
import type { PostgrestError } from '@supabase/supabase-js';
import type { PageServerLoad, Actions } from './$types';

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
	data_as_of: string;
	commentary_cash: string | null;
	commentary_bonds: string | null;
	commentary_marketable_securities: string | null;
	commentary_alternatives: string | null;
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
			'report_id, target_month, generation_status, data_as_of, commentary_cash, commentary_bonds, commentary_marketable_securities, commentary_alternatives'
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

	// P4 (SELF-356 AC4, R1 rider 6) — the SAME live-compose call `[target_month]/+page.server.ts`
	// already makes for a draft's own render (`fn_render_monthly_report`), NOT a second dedicated
	// query. Only meaningful while `isDraft` (a `final` row can no longer be finalized, so the
	// prompt has nothing left to gate); fail-soft to `false` on a composition-read failure — a
	// missed nudge, never a broken editor page.
	const isDraft = row.generation_status === 'draft';
	let noLedgerDesignated = false;
	if (isDraft) {
		try {
			const { data: composed, error: renderErr } = await locals.supabase
				.schema('pfin')
				.rpc('fn_render_monthly_report', {
					p_target_month: row.target_month,
					p_data_as_of: row.data_as_of
				});
			if (!renderErr && composed) {
				noLedgerDesignated = computeNoLedgerDesignated(composed as MonthlyReportPayload);
			}
		} catch (err) {
			console.error(
				'[reports/monthly/commentary] payload composition threw; degrading noLedgerDesignated to false:',
				err
			);
		}
	}

	return {
		targetMonth,
		targetMonthLabel: monthLabel(targetMonth),
		isDraft,
		commentary: toCommentaryValues(row),
		priorMonthLabel: monthLabel(priorMonth),
		priorCommentary: toCommentaryValues(priorRow as CommentaryRow | null),
		allocation,
		staleness,
		noLedgerDesignated
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

/** Maps a `pfin.fn_finalize_monthly_report` failure to a clean 4xx/5xx — mirrors `mapSaveError`
 *  just above (112's own sibling write path) and the identically-named mapper in
 *  `reports/monthly/+page.server.ts` (P5's own `?/skip` action, the OTHER call site onto this same
 *  115 RPC). Not extracted into a shared module — the two files are each a small, self-contained
 *  Backend-surface file per this ticket's own authorship note, and the mapping is three lines;
 *  flagged as a judgment call at hand-off rather than a silent duplication. */
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
			console.error('[reports/monthly/commentary] unexpected finalize error:', error.code, error.message);
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
	},

	// P4 (SELF-356 AC5) — the editor's own "Finalize {Month YYYY}" action (P3 item 4's former
	// PERMANENTLY DISABLED stub, now wired). Calls 115 with the `'authored'` disposition — the
	// DURABLE fact that the author declared this month done, which does NOT require non-empty
	// commentary (four empty strings ARE authored, per 115's own header — R12 rider 1). Whatever
	// commentary text is currently SAVED on the row is what gets frozen; this action does not
	// itself save unsaved edits (115 takes no commentary text at all — see monthly-report-
	// finalize.ts's own header). `p_commentary_disposition` is this action's OWN literal, never a
	// posted field.
	finalize: async ({ request, locals, params }) => {
		const { user } = await locals.safeGetSession();
		if (!user) return fail(401, { errors: { _form: ['You must be signed in.'] } });

		const targetMonth = parseTargetMonth(params.target_month);
		if (targetMonth === null) {
			return fail(400, { errors: { _form: ['Invalid target month.'] } });
		}

		const form = await request.formData();
		const parsed = authoredFinalizeSchema.safeParse(Object.fromEntries(form));
		if (!parsed.success) {
			return fail(400, { errors: fieldErrors(parsed.error) });
		}

		const { data: reportId, error: rpcError } = await locals.supabase
			.schema('pfin')
			.rpc('fn_finalize_monthly_report', {
				p_target_month: targetMonth,
				p_commentary_disposition: 'authored'
			});

		if (rpcError || typeof reportId !== 'number') {
			const { status, message } = rpcError
				? mapFinalizeError(rpcError)
				: { status: 500, message: 'Something went wrong. Please try again.' };
			return fail(status, { errors: { _form: [message] } });
		}

		// AC6 / P2's final view — the promotion is 115's own UPDATE; nothing inserts final
		// directly.
		throw redirect(303, `/reports/monthly/${targetMonth.slice(0, 7)}`);
	}
};
