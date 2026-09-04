// taxBracketScheduleWrite.ts — shared replace-all write path for ONE pfin.tax_bracket_schedule
// row (SELF-265, the /settings/tax-brackets form actions). Backend-owned server surface
// (ARCH §4.1 allowlist).
//
// REUSES the RPC contract POST /api/settings/tax-brackets/[schedule_id]/+server.ts already
// established (SELF-259 AC6 / E8): the same ownership-read-before-RPC design (a client-supplied
// schedule id is an object reference — R4 rider 4 — resolved under the caller's OWN RLS before
// the RPC is ever called, never trusted alone), the same schedule-identity guard (a body tax_year
// / schedule_type disagreeing with the resolved row is refused, never silently repointed), the
// same app-layer courtesy pre-check of 101's two set-property legs (zero-floor + rate
// monotonicity — NEVER the guarantee; the DB's deferred constraint trigger is), and the same
// `pfin.fn_tax_bracket_schedule_replace_all` RPC call, by name and by argument shape.
//
// ⚠ NOT a re-export of that endpoint's own internal `precheckRowOrdering` / `mapWriteError` —
// that file is outside this branch's touch scope (api/src/routes/api/settings/tax-brackets/**,
// not api/src/routes/settings/tax-brackets/**), so this module is a SEPARATE implementation of
// the same design, not a shared import. Flagged as a residual duplication in this issue's
// hand-off — both copies encode the same P0001 ambiguity / SQLSTATE mapping and should be
// consolidated into one shared module in a follow-up once both files are in one PR's touch scope.
//
// RESPONSE SHAPE is a discriminated union rather than `json()` — this module is called from
// SvelteKit FORM ACTIONS (api/CLAUDE.md: "forms go through SvelteKit form actions"), which
// return `fail(status, data)` / a plain object, never a raw Response. Callers map `ReplaceOutcome`
// onto their own `fail()` calls.

import type { SupabaseClient, PostgrestError } from '@supabase/supabase-js';
import type { TaxBracketScheduleReplace } from '$lib/server/schemas/tax-bracket-schedule';

export type ReplaceOutcome =
	| { ok: true }
	| { ok: false; status: number; errors: Record<string, string[]> };

/**
 * App-layer COURTESY pre-check for a friendlier error — NEVER the guarantee (101's own comment:
 * "SERIALIZABLE is NOT a substitute for this and this is not a substitute for SERIALIZABLE").
 * Validates BOTH of 101's set-property legs against the array in the order the client submitted
 * it, never re-sorted — identical logic to the sibling endpoint's `precheckRowOrdering`, kept
 * here as its own copy (see file header).
 */
export function precheckRowOrdering(
	rows: readonly { bracket_floor: number; bracket_rate: number }[]
): { ok: true } | { ok: false; reason: string } {
	if (rows[0].bracket_floor !== 0) {
		return { ok: false, reason: 'The lowest bracket must start at 0.' };
	}
	for (let i = 1; i < rows.length; i++) {
		if (rows[i].bracket_floor <= rows[i - 1].bracket_floor) {
			return { ok: false, reason: 'Bracket thresholds must strictly increase, in order.' };
		}
		if (rows[i].bracket_rate < rows[i - 1].bracket_rate) {
			return { ok: false, reason: 'Bracket rates must not decrease as thresholds rise.' };
		}
	}
	return { ok: true };
}

/** Map an RPC write failure to a clean 4xx + field-error envelope — same SQLSTATE reasoning as
 *  the sibling endpoint's `mapWriteError` (see that file's own comment for the full P0001
 *  ambiguity discussion; not restated here). */
function mapRpcError(error: PostgrestError): { status: number; errors: Record<string, string[]> } {
	switch (error.code) {
		case '42501':
			return {
				status: 403,
				errors: { _form: ['This action requires a freshly verified session. Please step up and try again.'] }
			};
		case 'P0001':
			return { status: 400, errors: { _form: ['This schedule could not be saved. Please refresh and try again.'] } };
		case '23514':
			return { status: 400, errors: { _form: ['One of the entered values is out of range.'] } };
		case '23505':
			return { status: 409, errors: { _form: ['This write conflicts with an existing schedule.'] } };
		case '40001':
			return { status: 409, errors: { _form: ['Another update is in progress. Please retry.'] } };
		default:
			console.error('[taxBracketScheduleWrite] unexpected write error:', error.code, error.message);
			return { status: 500, errors: { _form: ['Something went wrong. Please try again.'] } };
	}
}

/**
 * Replace-all write for ONE schedule the caller already owns (or has just created — see
 * `createSchedule` in +page.server.ts, which INSERTs the parent row first and then calls this
 * with the freshly-minted id; the ownership read below simply re-finds that same row).
 *
 * Order, load-bearing (mirrors the sibling endpoint): (1) RLS-scoped ownership read — the
 * PRIMARY 404 mechanism, reliable and SQLSTATE-independent; (2) schedule-identity guard — a body
 * tax_year/schedule_type disagreeing with the resolved row is refused, never silently repointed;
 * (3) the courtesy row-ordering pre-check; (4) the RPC call itself.
 */
export async function replaceTaxBracketSchedule(
	supabase: SupabaseClient,
	scheduleId: number,
	input: TaxBracketScheduleReplace
): Promise<ReplaceOutcome> {
	const { data: owned, error: readError } = await supabase
		.schema('pfin')
		.from('tax_bracket_schedule')
		.select('id, tax_year, schedule_type')
		.eq('id', scheduleId)
		.maybeSingle();

	if (readError) {
		console.error('[taxBracketScheduleWrite] ownership read failed:', readError.code, readError.message);
		return { ok: false, status: 500, errors: { _form: ['Something went wrong. Please try again.'] } };
	}
	if (!owned) {
		return { ok: false, status: 404, errors: { _form: ['This schedule could not be found.'] } };
	}

	if (input.tax_year !== owned.tax_year || input.schedule_type !== owned.schedule_type) {
		return {
			ok: false,
			status: 409,
			errors: { _form: ["This schedule's year or type has changed since it was loaded. Please refresh and try again."] }
		};
	}

	const ordering = precheckRowOrdering(input.rows);
	if (!ordering.ok) {
		return { ok: false, status: 400, errors: { rows: [ordering.reason] } };
	}

	const { error: writeError } = await supabase.schema('pfin').rpc('fn_tax_bracket_schedule_replace_all', {
		p_schedule_id: scheduleId,
		p_tax_year: input.tax_year,
		p_schedule_type: input.schedule_type,
		p_schedule_label: input.schedule_label,
		p_standard_deduction: input.standard_deduction,
		p_tax_balance_prior_year: input.tax_balance_prior_year,
		p_rows: input.rows
	});

	if (writeError) {
		return { ok: false, ...mapRpcError(writeError) };
	}

	return { ok: true };
}
