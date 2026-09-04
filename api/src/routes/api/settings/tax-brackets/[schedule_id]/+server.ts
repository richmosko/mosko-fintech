// +server.ts — POST /api/settings/tax-brackets/:schedule_id (SELF-259 AC6 / Lock 14 / ADR-011
// Decision 18 Sec mod / R4 (docs/records/v14-preflight/sitting-log.md § R4) / E8 (team-lead
// ruling, 2026-09-03, on Backend's flagged atomicity gap)).
//
// Replace-all write path for ONE pfin.tax_bracket_schedule row plus its FULL
// pfin.tax_bracket_row set, via the SECURITY INVOKER RPC E8 ruled and Architect landed on
// migration 101 (supabase/migrations/101_tax_bracket_tables.sql, feature/self-259). CONFIRMED
// against the landed sha: Sec's SELF-259 joint review
// (docs/records/v14-execution/self259-sec-review.md @ b53f766, F-6) verified the landed
// `pfin.fn_tax_bracket_schedule_replace_all` signature matches this endpoint's `.rpc()` call
// name-for-name and type-for-type. This repo's own standing lesson
// (DECISIONS.md, ADR-011 Decision 18 context — "a ratified name is not a built object") is
// satisfied here, not merely invoked: the ratified name WAS independently verified against the
// built object.
//
// ============================================================================================
// WHY AN RPC NOW, WHEN THE PRIOR REVISION OF THIS FILE DELIBERATELY DID NOT USE ONE — the
// version of migration 101 at 5f69249 shipped full CRUD table grants and two TRIGGER-ONLY
// fences (EXECUTE revoked from public on both), so the write path was three sequential
// `.from()` calls (UPDATE→DELETE→INSERT), with a named, accepted non-atomicity residual: a
// crash or a late-step rejection could leave "new scalars, old-or-empty rows." That gap was
// flagged in the hand-off rather than silently shipped. E8 rules the fix: Architect is adding
// `pfin.fn_tax_bracket_schedule_replace_all` to 101 — ONE SECURITY INVOKER call that performs
// the schedule lock, the scalar update, and the row replace-all inside ONE Postgres transaction,
// closing the gap this file previously accepted. RPC CONTRACT (E8, relayed 2026-09-03; amended
// by E27/E29 for `schedule_label`, landed migration 101 @ b073641):
//   pfin.fn_tax_bracket_schedule_replace_all(
//     p_schedule_id bigint, p_tax_year smallint, p_schedule_type pfin.tax_schedule_type_enum,
//     p_schedule_label text, p_standard_deduction numeric, p_tax_balance_prior_year numeric,
//     p_rows jsonb
//   ) returns void
// PostgREST's `.rpc()` matches parameters BY NAME, not position, so the payload below lists
// `p_schedule_label` alongside the other named args and their order in the call is immaterial —
// only the SIGNATURE'S positions (as landed in 101) matter, and are quoted verbatim above.
// ⚠ `create or replace function` with a CHANGED parameter list ADDS AN OVERLOAD rather than
// replacing the prior form in place: a local/dev DB that still holds the pre-E27/E29 6-arg
// signature from an earlier apply of this migration file will end up with BOTH the 6-arg and
// 7-arg forms resolvable, which breaks PostgREST's function-resolution-by-name for this RPC.
// Local/dev DBs must be rebuilt from a clean migration chain (`supabase db reset` — CAUTION,
// wipes local test data) or have the stale 6-arg signature dropped explicitly before this
// endpoint will resolve correctly.
// `p_rows` is a JSON array of `{bracket_floor, bracket_rate}` — exactly the shape
// `bracketRowSchema` already validates, so `parsed.data.rows` is passed through unmodified; no
// `schedule_id` or `users_id` per row (the function stamps both server-side, uniformly, the
// same way `users_id` is never a body field for the parent scalars). The function locks the
// owner's schedule row FOR UPDATE under RLS and RAISEs on an absent/other-tenant id; it NEVER
// creates a schedule (a first-time INSERT is a separate, out-of-scope write path — SELF-260's
// seed is the only current first-row writer). The deferred set-property trigger fires at
// COMMIT, which for a single RPC call is the end of this one PostgREST request — so a set-fence
// rejection surfaces as THIS call's `error`, not as some later step's.
//
// P0001 AMBIGUITY, NAMED RATHER THAN SILENTLY RESOLVED: the function's OWN "absent/other-tenant"
// lock failure, its per-row matched-tenant trigger fence (#18), and its deferred zero-floor /
// rate-monotonicity trigger fence are DISTINCT failures that may ALL surface as SQLSTATE
// P0001 (plpgsql's default code for an un-coded `raise exception`) — there is no SQLSTATE-level
// way to tell them apart. CONFIRMED against the landed migration (101): none of its `raise
// exception` sites carry an explicit `errcode`, so all three conditions genuinely do collapse to
// P0001 — this is a real ambiguity, not a gap in what this file could confirm. This endpoint
// therefore does NOT attempt message-string classification of the RPC's own P0001 —
// see mapWriteError's own comment for why that would be fragile, security-relevant guesswork
// rather than a mechanical distinction. Instead, the PRIMARY 404 path is a separate, RLS-scoped
// ownership read BEFORE the RPC call (see below) — reliable, SQLSTATE-independent, and
// consistent with this endpoint's existing "never trust {schedule_id} alone" discipline. The
// RPC's own internal not-found path is then a narrow, race-window backstop (the schedule
// vanishing between this endpoint's read and its RPC call) that collapses into the same generic
// 400 as the two trigger fences — a named, accepted residual, not a silent gap. Sec's SELF-259
// joint review (docs/records/v14-execution/self259-sec-review.md @ b53f766, F-6) reviewed this
// design and endorsed it as written: message-string classification of a security-relevant error
// is exactly the fragile guesswork it declines to do, and the pre-RPC ownership read already
// gives a reliable 404 for the one case that actually needs distinguishing. Sec's own suggested
// improvement — a distinct SQLSTATE (not P0001) on the function's lock-failure raise, e.g.
// `errcode = 'PT404'` — remains a sound future improvement, not a condition of any review to
// date; not implemented here.
//
// {schedule_id} IS A CLIENT-SUPPLIED OBJECT REFERENCE (R4 rider 4 / rederived-acs.md AC6): read
// under RLS with the caller's own session client BEFORE calling the RPC — never trusted alone.
// If it does not resolve (wrong tenant, or absent) this endpoint refuses with 404.
//
// SCHEDULE-IDENTITY GUARD (409), A PRESERVED JUDGMENT CALL: the resolved row's own `tax_year` /
// `schedule_type` are required to match the body's, refusing (409) a disagreement rather than
// silently repointing the schedule. ⚠ The RPC's signature technically ACCEPTS `p_tax_year` /
// `p_schedule_type` as write parameters, which means the DB layer alone does not obviously
// forbid this endpoint from renaming a schedule's identity via replace-all. This guard is kept
// as a conservative, app-layer restriction pending Architect/team-lead confirmation of whether
// repointing should actually be permitted here — easier to relax later than to retrofit after a
// same-tenant identity-confusion incident. Flagged explicitly in the hand-off, not silently
// assumed either way.
//
// INVOKER + anon-key + RLS only: every call goes through `locals.supabase`, the session-bound
// client wired at the hooks.server.ts chokepoint. service_role is FORBIDDEN here — this route
// holds no service_role key and adds no entry to the RT-26 allowlist (webhook / exchange /
// remove; untouched by this endpoint). TenantBoundClient (TBC-node) does NOT apply in `api/` —
// confirmed live against `.github/workflows/security-scan.yml`'s `fence-tbc-node` job, whose
// production-mode scope is `workers/provider-sync/src/` only (E9 (a), team-lead-confirmed).
//
// AUDIT-LOG: not applicable — ADR-011 Decision 18 classifies the whole Lock-14 settings family
// (tax_bracket_schedule / tax_bracket_row included) as NOT audit-class (api/CLAUDE.md; same
// ruling planning-target.ts / cashflow-target.ts record). No audit-log row is emitted here.
//
// Lock 14 fences, three different owners (mirrors planning-target.ts / cashflow-target.ts):
//   1. `.strict()` at every level (schemas/tax-bracket-schedule.ts) — mass-assignment fence.
//      `users_id` and `schedule_id` are never body fields.
//   2. The shared numeric-sanitization battery (currency + the fraction-rate export, both
//      confirmed against migration 101's real typmods — E9 (b)/(e)) on every numeric field —
//      NaN / Infinity / currency-string / scientific-notation / locale-formatted / overflow all
//      rejected before the DB is ever touched.
//   3. The DB's matched-tenant fence (D3 canonical #18) + the deferred set-property trigger +
//      `025` aal2 backstop are the actual guarantees; this endpoint's job is to map a rejection
//      to a clean 4xx (mapWriteError below), never to re-derive the semantics itself.
//
// ⚠ RT-24 (docs/SECURITY/index.html) STAYS FLAGGED, NOT FIXED HERE: its row text names a BEFORE
// INSERT/UPDATE trigger over a column called `lower_bound`; the landed DDL (5f69249) has a
// DEFERRED CONSTRAINT TRIGGER over `bracket_floor`. Sec's doc to correct at the SELF-259 joint
// review, per the prior revision of this file's flag — carried forward, not re-litigated here.

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
 * does not care what order the client SUBMITTED rows in — this check instead requires the
 * client to submit rows PRE-SORTED ascending by floor. A batch that passes this check is
 * therefore guaranteed to also pass the DB fence; the reverse is not true, and is not intended
 * to be. ⚠ SUBSUMES DUPLICATE-FLOOR DETECTION: two rows sharing one `bracket_floor` (which
 * would violate 101's `unique (schedule_id, bracket_floor)`) can never pass "each subsequent
 * floor > previous" — the comparison below is `<=`, not `<`.
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
 * Map an RPC write failure to a clean 4xx. Every EXPECTED rejection path is a 4xx, never a 500:
 *   - '42501' — RLS WITH CHECK/USING violation; in practice the `025` aal2 step-up backstop.
 *   - 'P0001' — collapsed to one generic `invalid_schedule`, DELIBERATELY not sub-classified by
 *     message text. Three distinct DB-side conditions can raise it (the RPC's own ownership
 *     lock failure, the matched-tenant trigger, the deferred set-property trigger) and only the
 *     FIRST is conceptually a 404 rather than a 400 — but this endpoint's own pre-call
 *     ownership read (see POST below) already handles that case in the ordinary flow, so by
 *     the time this function's error reaches here, a P0001 is either a genuine trigger
 *     rejection or a rare race-window ownership failure. Parsing the RPC's message text to
 *     split these would be fragile, security-adjacent guesswork against a contract whose actual
 *     wording isn't confirmed yet — see the file header's P0001 AMBIGUITY block for the
 *     recommendation (a distinct SQLSTATE) that would let this be done mechanically instead.
 *   - '23514' — the two-sided NaN / domain CHECKs on the three numerics. Defense-in-depth only.
 *   - '23505' — either `unique (schedule_id, bracket_floor)` (defensive fallback —
 *     `precheckRowOrdering` already rejects any duplicate floor before the DB is reached) or
 *     `unique (users_id, tax_year, schedule_type)` (reachable ONLY if the schedule-identity
 *     guard above is ever relaxed to permit renaming, and a rename collides with another
 *     existing schedule). Mapped to 409 rather than 400: both are "this write conflicts with
 *     another row that already exists," a conflict, not a shape/value defect.
 *   - '40001' — SERIALIZABLE serialization failure. Not a client input error — a concurrent
 *     transaction made this one's view stale, and the client is expected to retry. Mapped to
 *     409, distinctly from the '23505' conflict case above, so the frontend can tell "retry the
 *     same request" apart from "this specific input conflicts."
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
			return { status: 409, body: { error: 'schedule_conflict' } };
		case '40001':
			return { status: 409, body: { error: 'concurrent_update_retry' } };
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
	// with the CALLER'S OWN session client BEFORE the RPC call, for a reliable, message-
	// independent 404 (see file header's P0001 AMBIGUITY block for why this is the PRIMARY
	// mechanism rather than parsing the RPC's own error text). RLS filters this to the caller's
	// own rows by construction; a cross-tenant or absent id comes back as "no row" either way —
	// never distinguishing the two (that distinction would itself be a cross-tenant existence
	// leak).
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

	// Schedule-identity guard (409) — see file header for why this is a preserved, deliberately
	// conservative judgment call rather than a DB-mandated restriction.
	if (parsed.data.tax_year !== ownedSchedule.tax_year || parsed.data.schedule_type !== ownedSchedule.schedule_type) {
		return json({ error: 'schedule_identity_mismatch' }, { status: 409 });
	}

	// Courtesy pre-check ONLY — see precheckRowOrdering's own header. A rejection here is a
	// friendlier error than the DB trigger's, never a substitute for it.
	const ordering = precheckRowOrdering(parsed.data.rows);
	if (!ordering.ok) {
		return json({ error: 'invalid_row_order', reason: ordering.reason }, { status: 400 });
	}

	// ONE RPC call — E8's ruled contract (see file header). `p_rows` is exactly
	// `parsed.data.rows`: an array of `{bracket_floor, bracket_rate}`, no `schedule_id` / no
	// `users_id` per row — the function stamps both server-side. `users_id` is NEVER passed at
	// all (Lock 14 mod #1) — always the validated session, resolved inside the INVOKER function
	// from auth.uid(), the same SELF-267 D-2(i) precedent this endpoint's prior revision cited.
	const { error: writeError } = await locals.supabase.schema('pfin').rpc('fn_tax_bracket_schedule_replace_all', {
		p_schedule_id: scheduleId,
		p_tax_year: parsed.data.tax_year,
		p_schedule_type: parsed.data.schedule_type,
		p_schedule_label: parsed.data.schedule_label,
		p_standard_deduction: parsed.data.standard_deduction,
		p_tax_balance_prior_year: parsed.data.tax_balance_prior_year,
		p_rows: parsed.data.rows
	});

	if (writeError) {
		const { status, body } = mapWriteError(writeError);
		return json(body, { status });
	}

	return json({
		ok: true,
		schedule_id: scheduleId,
		tax_year: parsed.data.tax_year,
		schedule_type: parsed.data.schedule_type,
		schedule_label: parsed.data.schedule_label,
		standard_deduction: parsed.data.standard_deduction,
		tax_balance_prior_year: parsed.data.tax_balance_prior_year,
		row_count: parsed.data.rows.length
	});
};
