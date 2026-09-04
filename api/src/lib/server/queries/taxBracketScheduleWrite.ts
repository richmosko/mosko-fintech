// taxBracketScheduleWrite.ts — the ONE replace-all write path for a pfin.tax_bracket_schedule
// row (SELF-259 AC6 / SELF-265, E33). Backend-owned server surface (ARCH §4.1 allowlist).
//
// TWO CALLERS, ONE FENCE (team-lead ruling E33, 2026-09-04): POST
// /api/settings/tax-brackets/[schedule_id]/+server.ts (the original SELF-259 endpoint, Sec-
// reviewed at docs/records/v14-execution/self259-sec-review.md @ b53f766) and
// /settings/tax-brackets/+page.server.ts's saveSchedule/createSchedule actions (SELF-265) both
// delegate here rather than each re-implementing the ownership-read-before-RPC design. This
// module owns the MECHANISM: (1) the RLS-scoped ownership read — a client-supplied schedule id
// is an object reference (R4 rider 4), resolved under the caller's OWN RLS before the RPC is
// ever called, never trusted alone, and the PRIMARY, SQLSTATE-independent 404 path; (2) the
// schedule-identity guard — a body tax_year/schedule_type disagreeing with the resolved row is
// refused, never silently repointed; (3) the app-layer courtesy pre-check of 101's two
// set-property legs (zero-floor + rate monotonicity — NEVER the guarantee; the DB's deferred
// constraint trigger is); (4) the `pfin.fn_tax_bracket_schedule_replace_all` RPC call itself; and
// (5) the RPC's own SQLSTATE → error-code mapping (P0001 AMBIGUITY, NAMED RATHER THAN SILENTLY
// RESOLVED — see the original endpoint file's header, carried here unchanged: the function's own
// lock-failure raise, the matched-tenant trigger, and the deferred set-property trigger can all
// surface as P0001, with no SQLSTATE-level way to tell them apart, which is why the PRIMARY
// not-found path is the ownership read above rather than P0001 message-parsing).
//
// ⚠ THE ERROR-CODE VOCABULARY IS THE ENDPOINT'S, NOT A NEW ONE (E33: "if a test must move
// because the helper's error map differs, make the helper match the endpoint, not the reverse —
// the endpoint is the Sec-reviewed one"). `ReplaceErrorCode` is exactly the sibling endpoint's
// pre-refactor `mapWriteError` vocabulary (not_found / schedule_identity_mismatch /
// invalid_row_order / invalid_schedule / invalid_value / schedule_conflict /
// concurrent_update_retry / step_up_required / internal_error), verbatim, so the endpoint's own
// `json()` body stays byte-identical after delegating here. CALLERS OWN PRESENTATION: this module
// returns a canonical `{status, error, reason?}` outcome and does NOT itself produce a `json()`
// Response or a form-action `fail()` — the endpoint serializes the code directly (it always has),
// and the page actions translate the code into their own field-error / message shape (see
// +page.server.ts's own `errorCodeToFieldErrors`), because the two surfaces have different
// response CONTRACTS even though they share the same underlying mechanism.

import type { SupabaseClient, PostgrestError } from '@supabase/supabase-js';
import type { TaxBracketScheduleReplace } from '$lib/server/schemas/tax-bracket-schedule';

export type ReplaceErrorCode =
	| 'not_found'
	| 'schedule_identity_mismatch'
	| 'invalid_row_order'
	| 'invalid_schedule'
	| 'invalid_value'
	| 'schedule_conflict'
	| 'concurrent_update_retry'
	| 'step_up_required'
	| 'internal_error';

export type ReplaceOutcome =
	| { ok: true }
	| { ok: false; status: number; error: ReplaceErrorCode; reason?: string };

/**
 * App-layer COURTESY pre-check for a friendlier error — NEVER the guarantee (101's own comment:
 * "SERIALIZABLE is NOT a substitute for this and this is not a substitute for SERIALIZABLE").
 * Validates BOTH of 101's set-property legs against the array in the order the client submitted
 * it, never re-sorted:
 *   - Leg A (zero floor): the first row's `bracket_floor` must be exactly 0.
 *   - Leg B (rate monotonicity): each subsequent row's `bracket_rate` must be >= the previous
 *     row's (non-decreasing, matching the DB's own NON-DECREASING — not strictly increasing —
 *     wording).
 * ⚠ STRICTER THAN THE DB, DELIBERATELY: the DB fence sorts by `bracket_floor` internally and
 * does not care what order the client SUBMITTED rows in — this check instead requires the
 * client to submit rows PRE-SORTED ascending by floor. A batch that passes this check is
 * therefore guaranteed to also pass the DB fence; the reverse is not true, and is not intended
 * to be. ⚠ SUBSUMES DUPLICATE-FLOOR DETECTION: two rows sharing one `bracket_floor` (which
 * would violate 101's `unique (schedule_id, bracket_floor)`) can never pass "each subsequent
 * floor > previous" — the comparison below is `<=`, not `<`.
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

/**
 * Map an RPC write failure to a clean 4xx — the sibling endpoint's pre-refactor `mapWriteError`,
 * unchanged (see its own comment, carried into this file's header, for the full P0001 ambiguity
 * discussion):
 *   - '42501' — RLS WITH CHECK/USING violation; in practice the `025` aal2 step-up backstop.
 *   - 'P0001' — collapsed to one generic `invalid_schedule`, DELIBERATELY not sub-classified by
 *     message text (three distinct DB-side conditions can raise it; see the file header).
 *   - '23514' — the two-sided NaN / domain CHECKs on the three numerics. Defense-in-depth only.
 *   - '23505' — either the row-floor unique constraint (defensive fallback — the courtesy
 *     precheck already rejects any duplicate floor before the DB is reached) or the schedule
 *     identity unique constraint. Mapped to 409, a conflict, not a shape/value defect.
 *   - '40001' — SERIALIZABLE serialization failure. Mapped to 409, distinctly from '23505', so a
 *     caller can tell "retry the same request" apart from "this specific input conflicts."
 * Anything else is genuinely unexpected and stays a logged 500.
 */
function mapRpcError(error: PostgrestError): { status: number; error: ReplaceErrorCode } {
	switch (error.code) {
		case '42501':
			return { status: 403, error: 'step_up_required' };
		case 'P0001':
			return { status: 400, error: 'invalid_schedule' };
		case '23514':
			return { status: 400, error: 'invalid_value' };
		case '23505':
			return { status: 409, error: 'schedule_conflict' };
		case '40001':
			return { status: 409, error: 'concurrent_update_retry' };
		default:
			console.error('[taxBracketScheduleWrite] unexpected write error:', error.code, error.message);
			return { status: 500, error: 'internal_error' };
	}
}

/**
 * Replace-all write for ONE schedule the caller already owns (or has just created — see
 * `createSchedule` in +page.server.ts, which INSERTs the parent row first and then calls this
 * with the freshly-minted id; the ownership read below simply re-finds that same row).
 *
 * Order, load-bearing: (1) RLS-scoped ownership read — the PRIMARY 404 mechanism, reliable and
 * SQLSTATE-independent; (2) schedule-identity guard — a body tax_year/schedule_type disagreeing
 * with the resolved row is refused, never silently repointed; (3) the courtesy row-ordering
 * pre-check; (4) the RPC call itself.
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
		return { ok: false, status: 500, error: 'internal_error' };
	}
	if (!owned) {
		return { ok: false, status: 404, error: 'not_found' };
	}

	if (input.tax_year !== owned.tax_year || input.schedule_type !== owned.schedule_type) {
		return { ok: false, status: 409, error: 'schedule_identity_mismatch' };
	}

	const ordering = precheckRowOrdering(input.rows);
	if (!ordering.ok) {
		return { ok: false, status: 400, error: 'invalid_row_order', reason: ordering.reason };
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
