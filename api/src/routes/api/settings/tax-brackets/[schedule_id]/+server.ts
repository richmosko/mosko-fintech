// +server.ts — POST /api/settings/tax-brackets/:schedule_id (SELF-259 AC6 / Lock 14 / ADR-011
// Decision 18 Sec mod / R4 (docs/records/v14-preflight/sitting-log.md § R4)).
//
// Replace-all write path for ONE pfin.tax_bracket_schedule row plus its FULL
// pfin.tax_bracket_row set, reconciled against migration 101
// (supabase/migrations/101_tax_bracket_tables.sql, landed at 5f69249 on feature/self-259) —
// read that file live before trusting anything below; this header cites its `comment on` text,
// never restates it as if this file were the source.
//
// ============================================================================================
// WHY THREE SEQUENTIAL .from() CALLS, NOT ONE RPC — migration 101 grants FULL CRUD
// (select/insert/update/delete) on both tables directly to `authenticated` and authors NO
// replace-all stored procedure; the only two functions it ships
// (fn_tax_bracket_row_matched_schedule, fn_tax_bracket_row_schedule_invariants) are TRIGGER
// fences with EXECUTE revoked from public — neither is a callable RPC. So "replace-all under
// SERIALIZABLE... deletes and re-inserts inside one transaction" (101's own table comments) is
// achieved the ONLY way the granted surface allows: sequential direct-table calls, where the
// row DELETE-then-INSERT pair is what "one transaction" refers to at the STATEMENT level (each
// is one PostgREST request = one implicit Postgres transaction; supabase-js/PostgREST cannot
// hold a client-side multi-statement BEGIN across separate `.from()` calls — established
// precedent, see the Plaid webhook handler's own header and migration 045's comment on the
// identical constraint). This is NOT the same guarantee as one transaction spanning
// UPDATE+DELETE+INSERT together, and that gap is real — see WRITE ORDERING below and the
// residual risk named in this PR's hand-off, not silently assumed away.
//
// WHY THE ROW DELETE+INSERT SPECIFICALLY IS SAFE AS TWO TRANSACTIONS: 101's deferred
// CONSTRAINT TRIGGER (fn_tax_bracket_row_schedule_invariants) explicitly treats an EMPTY row
// set as the legal "cleared but not yet repopulated" state ("An EMPTY schedule PASSES,
// deliberately... the absence of brackets, not a malformed set — the same absence-is-unset
// semantics the parent's standard_deduction rests on"). So the DELETE's own commit (leaving
// zero rows) always passes Leg A/B trivially, and the INSERT's own commit is where both legs
// are actually evaluated against the full new set — see mapReplaceError's '42501'/'P0001'
// cases below, and the DDL ASSUMPTIONS block's WRITE ORDERING note for what happens if THAT
// commit is the one that fails.
//
// WRITE ORDERING, AND THE RESIDUAL THIS CHOICE ACCEPTS: UPDATE (schedule scalars) → DELETE
// (old rows) → INSERT (new rows). Scalars first because that write is simple (NOT NULL / CHECK
// only, already pre-validated by the Zod schema) and low-risk; if it fails, NOTHING else is
// touched. Rows last because that is where the deferred trigger's commit-time rejection can
// fire (see the file-header block above) — putting it last means a rejection there leaves the
// schedule in "new scalars, EMPTY rows" rather than "new scalars, STALE-BUT-VALID-LOOKING old
// rows": an empty row set is an honest, self-evidently-incomplete signal that matches 101's own
// absence-is-unset philosophy, where a full set of unrelated old rows sitting next to freshly
// changed scalars is a silently-plausible-looking inconsistency. ⚠ THIS DOES NOT MAKE THE WRITE
// ATOMIC — a crash or an UPDATE-succeeds-but-DELETE/INSERT-fails outcome still leaves a
// genuinely partial state (new scalars, old-or-empty rows) that no mechanism here reverts. This
// is a judgment call under the constraint that no RPC exists to make the three operations one
// real transaction, not a claim that the residual has been eliminated — flagged explicitly in
// this PR's hand-off for Architect/Sec to weigh whether a follow-up RPC is warranted.
//
// {schedule_id} IS A CLIENT-SUPPLIED OBJECT REFERENCE (R4 rider 4 / rederived-acs.md AC6): read
// under RLS with the caller's own session client BEFORE any write — never trusted alone. If it
// does not resolve (wrong tenant, or absent) this endpoint refuses with 404. The resolved row's
// OWN `tax_year` / `schedule_type` are then required to match the body's — a body that disagrees
// is refused (409), never silently treated as a request to repoint the schedule to a different
// (tax_year, schedule_type) identity. This is a deliberate, endpoint-local restriction: 101's
// `unique (users_id, tax_year, schedule_type)` is documented as "the ON CONFLICT target for the
// UPSERT write path" in general, but THIS endpoint — scoped to an ALREADY-RESOLVED
// `{schedule_id}` — only ever needs an UPDATE-by-id, never an insert-or-update decision, and
// never needs to touch the unique constraint at all. Creating a schedule for a brand-new
// (tax_year, schedule_type) with no existing `schedule_id` is OUT OF SCOPE for this endpoint —
// SELF-260's seed is the only current writer of first-time rows.
//
// INVOKER + anon-key + RLS only: every call goes through `locals.supabase`, the session-bound
// client wired at the hooks.server.ts chokepoint. service_role is FORBIDDEN here — this route
// holds no service_role key and adds no entry to the RT-26 allowlist (webhook / exchange /
// remove; untouched by this endpoint). ⚠ Team-lead's brief for this endpoint named
// `TenantBoundClient` (TBC-node) as the mechanism to use — checked live against
// `.github/workflows/security-scan.yml`'s `fence-tbc-node` job and its production-mode scope is
// `workers/provider-sync/src/` ONLY, not `api/src/`; every existing `/api/settings/*` endpoint
// uses `locals.supabase` directly with no TBC wrapper anywhere in `api/`. This file follows that
// existing, CI-fence-consistent precedent rather than the brief's TBC mention — flagged in the
// hand-off, not silently reconciled.
//
// AUDIT-LOG: not applicable — ADR-011 Decision 18 classifies the whole Lock-14 settings family
// (tax_bracket_schedule / tax_bracket_row included) as NOT audit-class (api/CLAUDE.md; same
// ruling planning-target.ts / cashflow-target.ts record). No audit-log row is emitted here.
//
// Lock 14 fences, three different owners (mirrors planning-target.ts / cashflow-target.ts):
//   1. `.strict()` at every level (schemas/tax-bracket-schedule.ts) — mass-assignment fence.
//      `users_id` and `schedule_id` are never body fields.
//   2. The shared numeric-sanitization battery (currency + the fraction-rate export) on every
//      numeric field — NaN / Infinity / currency-string / scientific-notation /
//      locale-formatted / overflow all rejected before the DB is ever touched.
//   3. The DB's matched-tenant fence (D3 canonical #18, grain (C)) + the deferred set-property
//      trigger + `025` aal2 backstop are the actual guarantees; this endpoint's job for all of
//      them is to map a rejection to a clean 4xx (mapWriteError below), never to re-derive the
//      semantics itself. BOTH trigger functions raise via plain plpgsql `raise exception` with
//      no explicit ERRCODE, so BOTH surface as SQLSTATE P0001 (Postgres's default for an
//      un-coded RAISE) — collapsed to one generic `invalid_schedule` 4xx deliberately, mirroring
//      transactions/[trans_id]/classify's precedent: the legs' exact diagnostics are a
//      DB-internal distinction, not information owed to an adversarial caller.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { PostgrestError } from '@supabase/supabase-js';
import { taxBracketScheduleReplaceSchema } from '$lib/server/schemas/tax-bracket-schedule';
import { fieldErrors } from '$lib/server/schemas/account';

/** Shape-only guard on the route param — RLS (via the ownership read below) is the actual
 *  tenant/visibility boundary, mirroring accounts/[account_id]'s parseAccountId and
 *  transactions/[trans_id]'s parseTransId. `Number.isSafeInteger` rather than a smaller bound:
 *  the PK is `bigint generated always as identity` (migration 101), and a JS
 *  `Number.isSafeInteger` id fits every value the table's own identity sequence will ever
 *  produce (same reasoning account.ts's linkedSourceIdField / classification.ts's
 *  classifySchema already rely on for bigint FK shape-checks). */
function parseScheduleId(param: string | undefined): number | null {
	const n = Number(param);
	return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/**
 * App-layer COURTESY pre-check for a friendlier error — NEVER the guarantee (101's own comment:
 * "SERIALIZABLE is NOT a substitute for this and this is not a substitute for SERIALIZABLE").
 * Validates BOTH of 101's set-property legs against the array in the order the client
 * submitted it (AC2: "an ORDERED bracket-row table"), never re-sorted:
 *   - Leg A (zero floor): the first row's `bracket_floor` must be exactly 0.
 *   - Leg B (rate monotonicity): each subsequent row's `bracket_rate` must be >= the previous
 *     row's (non-decreasing, matching the DB's own NON-DECREASING — not strictly increasing —
 *     wording).
 * ⚠ STRICTER THAN THE DB, DELIBERATELY: the DB fence sorts by `bracket_floor` internally and
 * does not care what order the client SUBMITTED rows in (Leg A/B are properties of the VALUE
 * set, not the request payload's order) — this check instead requires the client to submit
 * rows PRE-SORTED ascending by floor, rejecting a batch that is valid by value but arrives out
 * of order. That is a deliberate, simpler app-layer UX contract consistent with AC2's "ordered
 * table" framing, not an attempt to reproduce the DB's exact predicate. A batch that passes
 * this check is therefore guaranteed to also pass the DB fence; the reverse is not true, and is
 * not intended to be.
 * ⚠ SUBSUMES DUPLICATE-FLOOR DETECTION: two rows sharing one `bracket_floor` value (which would
 * violate 101's `unique (schedule_id, bracket_floor)`, surfacing as a DB `23505`) can never
 * pass "each subsequent floor > previous" — the comparison below is `<=`, not `<`, specifically
 * so an exact duplicate is caught here as a friendly 400 rather than reaching the DB.
 */
function precheckRowOrdering(
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
 * Map a write failure to a clean 4xx. Every EXPECTED rejection path is a 4xx, never a 500:
 *   - '42501' — RLS WITH CHECK/USING violation; in practice the `025` aal2 step-up backstop on
 *     whichever of the three calls tripped it.
 *   - 'P0001' — either of 101's two trigger fences (matched-tenant #18, or the deferred
 *     zero-floor/rate-monotonicity set fence) — both raise via a plain, un-coded `raise
 *     exception`, which Postgres assigns SQLSTATE P0001 by default; there is no SQLSTATE-level
 *     way to tell them apart, and this endpoint does not try (see file header). Collapsed to
 *     one generic `invalid_schedule`.
 *   - '23514' — the two-sided NaN / domain CHECKs on the three numerics. Defense-in-depth only
 *     — the app-layer battery is the first line and is expected to reject this before the DB.
 *   - '23505' — the `unique (schedule_id, bracket_floor)` violation. Defensive fallback only:
 *     `precheckRowOrdering`'s strict-floor-increase requirement already rejects any duplicate
 *     floor before the DB is reached (see that function's own comment), so this leg is not
 *     expected to fire in ordinary operation — kept as a named, mapped case rather than falling
 *     through to the generic 500 branch, since "defensive fallback, not expected to fire" is a
 *     different claim from "cannot happen" (the same discipline planning-target.ts's '23503'
 *     case states for its own defensive fallback).
 * Anything else is genuinely unexpected and stays a logged 500.
 */
function mapWriteError(error: PostgrestError): { status: number; body: { error: string } } {
	switch (error.code) {
		case '42501':
			return { status: 403, body: { error: 'step_up_required' } };
		case 'P0001':
			return { status: 400, body: { error: 'invalid_schedule' } };
		case '23514':
			return { status: 400, body: { error: 'invalid_value' } };
		case '23505':
			return { status: 400, body: { error: 'duplicate_bracket_floor' } };
		default:
			console.error('[tax-brackets] unexpected write error:', error.code, error.message);
			return { status: 500, body: { error: 'internal_error' } };
	}
}

export const POST: RequestHandler = async ({ request, locals, params }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	const scheduleId = parseScheduleId(params.schedule_id);
	if (scheduleId === null) return json({ error: 'invalid_request' }, { status: 400 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	const parsed = taxBracketScheduleReplaceSchema.safeParse(raw);
	if (!parsed.success) {
		return json({ error: 'invalid_request', fieldErrors: fieldErrors(parsed.error) }, { status: 400 });
	}

	// {schedule_id} is a client-supplied object reference (R4 rider 4) — resolved under RLS
	// with the CALLER'S OWN session client before any write. RLS filters this to the caller's
	// own rows by construction (users_id = auth.uid()); a cross-tenant or absent id therefore
	// comes back as "no row," and this endpoint refuses with 404 either way — never trusting
	// the path param alone, and never distinguishing "exists for someone else" from "doesn't
	// exist" (that distinction would itself be a cross-tenant existence leak).
	const { data: ownedSchedule, error: readError } = await locals.supabase
		.schema('pfin')
		.from('tax_bracket_schedule')
		.select('id, tax_year, schedule_type')
		.eq('id', scheduleId)
		.maybeSingle();

	if (readError) {
		console.error('[tax-brackets] ownership read failed:', readError.code, readError.message);
		return json({ error: 'internal_error' }, { status: 500 });
	}
	if (!ownedSchedule) {
		return json({ error: 'not_found' }, { status: 404 });
	}

	// The resolved row's own identity is authoritative; a body that disagrees is refused rather
	// than silently repointing the schedule to a different (tax_year, schedule_type) — see file
	// header. This also means this endpoint's writes NEVER touch 101's
	// unique (users_id, tax_year, schedule_type) constraint, so no mapping is owed for it.
	if (parsed.data.tax_year !== ownedSchedule.tax_year || parsed.data.schedule_type !== ownedSchedule.schedule_type) {
		return json({ error: 'schedule_identity_mismatch' }, { status: 409 });
	}

	// Courtesy pre-check ONLY — see precheckRowOrdering's own header. A rejection here is a
	// friendlier error than the DB trigger's, never a substitute for it.
	const ordering = precheckRowOrdering(parsed.data.rows);
	if (!ordering.ok) {
		return json({ error: 'invalid_row_order', reason: ordering.reason }, { status: 400 });
	}

	// WRITE ORDERING: UPDATE scalars → DELETE old rows → INSERT new rows. See the file header's
	// WRITE ORDERING block for why this order, and for the residual non-atomicity it does not
	// eliminate. `users_id` is NEVER a written field on any of the three calls — always the
	// validated session (Lock 14 mod #1), relying on 101's `DEFAULT auth.uid()` for the row
	// INSERTs and on RLS's `users_id = auth.uid()` USING/WITH CHECK for the schedule UPDATE.
	const { error: updateError, count: updateCount } = await locals.supabase
		.schema('pfin')
		.from('tax_bracket_schedule')
		.update(
			{
				standard_deduction: parsed.data.standard_deduction,
				tax_balance_prior_year: parsed.data.tax_balance_prior_year
			},
			{ count: 'exact' }
		)
		.eq('id', scheduleId);

	if (updateError) {
		const { status, body } = mapWriteError(updateError);
		return json(body, { status });
	}
	if ((updateCount ?? 0) === 0) {
		// The ownership read above resolved the row moments earlier; a 0-row UPDATE here means
		// a race (deleted, or stepped below aal2) between that read and this write. Refuse
		// before touching rows at all, rather than guessing which.
		return json({ error: 'not_found' }, { status: 404 });
	}

	const { error: deleteError } = await locals.supabase
		.schema('pfin')
		.from('tax_bracket_row')
		.delete()
		.eq('schedule_id', scheduleId);

	if (deleteError) {
		const { status, body } = mapWriteError(deleteError);
		return json(body, { status });
	}

	const { error: insertError } = await locals.supabase
		.schema('pfin')
		.from('tax_bracket_row')
		.insert(parsed.data.rows.map((row) => ({ schedule_id: scheduleId, ...row })));

	if (insertError) {
		// THIS is where 101's deferred CONSTRAINT TRIGGER's commit-time rejection surfaces —
		// see the file header's SAFE-AS-TWO-TRANSACTIONS block. The schedule is left with its
		// NEW scalars and EMPTY rows (the just-run DELETE already removed the old set); that is
		// the accepted residual, not a bug in this branch.
		const { status, body } = mapWriteError(insertError);
		return json(body, { status });
	}

	return json({
		ok: true,
		schedule_id: scheduleId,
		tax_year: parsed.data.tax_year,
		schedule_type: parsed.data.schedule_type,
		standard_deduction: parsed.data.standard_deduction,
		tax_balance_prior_year: parsed.data.tax_balance_prior_year,
		row_count: parsed.data.rows.length
	});
};
