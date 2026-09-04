// +server.ts — POST /api/settings/tax-brackets/:schedule_id (SELF-259 AC6 / Lock 14 / ADR-011
// Decision 18 Sec mod / R4 (rulings, docs/records/v14-preflight/sitting-log.md § R4)).
//
// Replace-all write path for ONE `pfin.tax_bracket_schedule` row plus its FULL
// `pfin.tax_bracket_row` set, in ONE POST. Architect is authoring migration 101 (the DDL) on
// feature/self-259 IN PARALLEL with this file — every table/column/function name and type
// below is a Backend PROPOSAL against rederived-acs.md's AC text and the R4 ruling, pending
// reconciliation against the pushed migration. See the "DDL ASSUMPTIONS" block below for the
// complete list a reviewer must confirm or correct.
//
// ============================================================================================
// DDL ASSUMPTIONS (reconcile against migration 101 when Architect pushes it):
//   - `pfin.tax_bracket_schedule(id bigint generated always as identity primary key, users_id
//     uuid not null references auth.users, tax_year smallint not null, schedule_type <enum>
//     not null, standard_deduction numeric not null, tax_balance_prior_year numeric,
//     created_at, updated_at)` — R4 riders: bigint identity PK (rider 5), tax_year smallint
//     (Decision 18 rider, unamended), `025` aal2 backstop on `authenticated` policies (rider
//     3), USING+WITH CHECK per verb at the `090` standard (rider 6).
//   - `pfin.tax_bracket_row(id bigint generated always as identity primary key, schedule_id
//     bigint not null references pfin.tax_bracket_schedule, users_id uuid not null references
//     auth.users, bracket_floor numeric not null, bracket_rate numeric not null, created_at,
//     updated_at)` — R4's RULED grain (C): the child carries its OWN `users_id` BESIDE
//     `schedule_id` (the D3 matched-tenant fence — a genuine ADR-011 Decision 3 family member
//     under this grain, one label allocated AT the SELF-259 migration per D18's amendment).
//     This is why the RPC below is passed rows WITHOUT a client-supplied `users_id` per row —
//     the function must stamp EVERY row's `users_id` from the session, uniformly, the same way
//     it stamps the parent's.
//   - `schedule_type` enum labels: this file proposes `federal_ordinary` / `federal_ltcg` /
//     `ca_ftb_ordinary` (schemas/tax-bracket-schedule.ts) against PRD §2.5.2 (λ)/(κ). Migration
//     101 is the source of truth for the actual labels.
//   - `bracket_rate` unit: FRACTION (0.22, never 22) per team-lead ruling / Sec M-7 — two-sided
//     [0,1] CHECK proposed (numeric.ts `sanitizeFractionRate`).
//   - Two-sided NaN CHECKs on all three numerics, a zero-floor constraint (lowest
//     `bracket_floor` of every schedule = 0), and the monotonicity fence are all R4 rider 1/8
//     DB-side deferred CONSTRAINT TRIGGER / statement-level AFTER obligations on migration 101
//     — NOT re-implemented as the guarantee here (R4 rider 2: SERIALIZABLE and the monotonicity
//     check are INDEPENDENT controls; neither substitutes for the other). This endpoint runs an
//     app-layer COURTESY pre-check for a friendlier error (see `precheckRowOrdering` below) and
//     separately maps the DB trigger's rejection when it fires — both paths are exercised by
//     this file's tests.
//   - RPC CONTRACT (PROPOSED — Architect-owned; flagged, not authored, per role separation):
//     `pfin.fn_tax_bracket_schedule_replace_all(p_schedule_id bigint, p_tax_year smallint,
//     p_schedule_type <enum>, p_standard_deduction numeric, p_tax_balance_prior_year numeric,
//     p_rows jsonb) returns void`, `security invoker`, `set search_path = ''`. NO `p_users_id`
//     parameter (SELF-267 D-2(i) precedent — a client-supplied tenant on an INVOKER function is
//     either an ignored lie or an ownership-forge vector; `auth.uid()` is read inside the
//     function body, exactly as R4 rider 4 requires for the path param below). The function is
//     the ONLY way this replace-all can be transactional AND SERIALIZABLE at all:
//     supabase-js/PostgREST cannot hold a client-side multi-statement `BEGIN SERIALIZABLE`
//     across separate `.from(...)` calls (established precedent — see
//     `api/src/routes/api/plaid/webhook/+server.ts`'s header and migration `045`'s comment on
//     the same constraint) — a DELETE-then-INSERT issued as two separate requests from this
//     file would be two separate transactions, non-atomic, and unable to share one isolation
//     level. `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` therefore has to be the function
//     body's own first statement; this file cannot set it from the client. Flagged to Architect
//     as a migration-101 deliverable, not authored here.
// ============================================================================================
//
// {schedule_id} IS A CLIENT-SUPPLIED OBJECT REFERENCE (R4 rider 4 / rederived-acs.md AC6): read
// under RLS with the caller's own session client BEFORE the write — never trusted alone. If it
// does not resolve (wrong tenant, or absent) this endpoint refuses with 404, consistent with the
// existing account-detail / trans-classify routes' non-owner-is-404 convention (never a 403 that
// would confirm the id exists for another tenant).
//
// INVOKER + anon-key + RLS only: both the ownership read and the RPC go through
// `locals.supabase`, the session-bound client wired at the hooks.server.ts chokepoint.
// service_role is FORBIDDEN here — this route holds no service_role key and adds no entry to
// the RT-26 allowlist (webhook / exchange / remove; untouched by this endpoint).
//
// AUDIT-LOG: not applicable — ADR-011 Decision 18 classifies the whole Lock-14 settings family
// (tax_bracket_schedule / tax_bracket_row included) as NOT audit-class (api/CLAUDE.md; same
// ruling planning-target.ts / cashflow-target.ts record). No audit-log row is emitted here.
//
// Lock 14 fences, three different owners (mirrors planning-target.ts / cashflow-target.ts):
//   1. `.strict()` at every level (schemas/tax-bracket-schedule.ts) — mass-assignment fence.
//      `users_id` and `schedule_id` are never body fields.
//   2. The shared numeric-sanitization battery (currency + the new fraction-rate export) on
//      every numeric field — NaN / Infinity / currency-string / scientific-notation /
//      locale-formatted / overflow all rejected before the DB is ever touched.
//   3. The DB's matched-tenant fence (D3, grain (C)) + deferred monotonicity/zero-floor
//      triggers + `025` aal2 backstop are the actual guarantees; this endpoint's job for all of
//      them is to map a rejection to a clean 4xx (mapReplaceError below), never to re-derive
//      the semantics itself.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { PostgrestError } from '@supabase/supabase-js';
import { taxBracketScheduleReplaceSchema } from '$lib/server/schemas/tax-bracket-schedule';
import { fieldErrors } from '$lib/server/schemas/account';

/** Shape-only guard on the route param — RLS (via the ownership read below) is the actual
 *  tenant/visibility boundary, mirroring accounts/[account_id]'s parseAccountId and
 *  transactions/[trans_id]'s parseTransId. `Number.isSafeInteger` rather than a smaller bound:
 *  the proposed PK is `bigint generated always as identity` (R4 rider 5), and a JS
 *  `Number.isSafeInteger` id fits every value the table's own identity sequence will ever
 *  produce (same reasoning account.ts's linkedSourceIdField / classification.ts's
 *  classifySchema already rely on for bigint FK shape-checks). */
function parseScheduleId(param: string | undefined): number | null {
	const n = Number(param);
	return Number.isSafeInteger(n) && n > 0 ? n : null;
}

/**
 * App-layer COURTESY pre-check for a friendlier error — NEVER the guarantee (R4 rider 2: the
 * DB's deferred CONSTRAINT TRIGGER is independent of, and not substituted by, anything here).
 * Validates the SAME set properties the DB trigger will (R4 rider 8): the array's first row's
 * `bracket_floor` is exactly 0 (zero-floor), and every subsequent row's `bracket_floor` is
 * STRICTLY greater than the previous row's (monotonicity) — checked against the array in the
 * order the client submitted it (AC2: "an ORDERED bracket-row table"), never re-sorted, because
 * re-sorting before validating would silently accept a client that submitted the wrong order.
 */
function precheckRowOrdering(rows: readonly { bracket_floor: number }[]): { ok: true } | { ok: false; reason: string } {
	if (rows[0].bracket_floor !== 0) {
		return { ok: false, reason: 'The lowest bracket must start at 0.' };
	}
	for (let i = 1; i < rows.length; i++) {
		if (rows[i].bracket_floor <= rows[i - 1].bracket_floor) {
			return { ok: false, reason: 'Bracket thresholds must strictly increase, in order.' };
		}
	}
	return { ok: true };
}

/**
 * Map a replace-all write failure to a clean 4xx. Every EXPECTED rejection path is a 4xx, never
 * a 500 — mirrors planning-target.ts's mapWriteError, collapsing multiple DB-trigger legs into
 * one generic client-facing reason rather than relaying trigger internals to an adversarial
 * caller (classify.ts's AC6 precedent: "the legs' exact diagnostics are a DB-internal
 * distinction... not information this endpoint should hand an adversarial caller").
 *   - '42501' — RLS WITH CHECK violation; in practice the `025` aal2 step-up backstop.
 *   - 'P0001' — the D3 matched-tenant fence AND/OR the deferred monotonicity/zero-floor
 *     CONSTRAINT TRIGGER (R4 rider 8) — both raise a generic app-facing `invalid_schedule`.
 *     Collapsed deliberately (see above); the app-layer precheck above is expected to catch the
 *     ordering half BEFORE the DB is reached, so this leg mostly guards the matched-tenant half
 *     and any ordering violation the precheck's own bug might let through — either way, this
 *     endpoint must surface the DB's rejection correctly when it fires, never silently 200.
 *   - '23514' — the two-sided NaN / domain CHECKs on the three numerics. Defense-in-depth only
 *     — the app-layer battery is the first line and is expected to reject this before the DB.
 *   - '23503' — FK violation. Defensive fallback only, mirrors planning-target.ts's reasoning:
 *     the matched-tenant trigger's own read resolves (or fails to resolve) `schedule_id` before
 *     Postgres would reach the FK check in the ordinary case.
 *   - '40001' — SERIALIZABLE transaction serialization failure. This is NOT a client input
 *     error — it means a concurrent transaction made this one's view stale, and Postgres's own
 *     SERIALIZABLE contract requires the CLIENT to retry. Mapped to 409, distinctly, so the
 *     frontend can distinguish "your input was rejected" from "retry the same request."
 * Anything else is genuinely unexpected and stays a logged 500.
 */
function mapReplaceError(error: PostgrestError): { status: number; body: { error: string } } {
	switch (error.code) {
		case '42501':
			return { status: 403, body: { error: 'step_up_required' } };
		case 'P0001':
		case '23503':
			return { status: 400, body: { error: 'invalid_schedule' } };
		case '23514':
			return { status: 400, body: { error: 'invalid_value' } };
		case '40001':
			return { status: 409, body: { error: 'concurrent_update_retry' } };
		default:
			console.error('[tax-brackets] unexpected replace-all error:', error.code, error.message);
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
		.select('id')
		.eq('id', scheduleId)
		.maybeSingle();

	if (readError) {
		console.error('[tax-brackets] ownership read failed:', readError.code, readError.message);
		return json({ error: 'internal_error' }, { status: 500 });
	}
	if (!ownedSchedule) {
		return json({ error: 'not_found' }, { status: 404 });
	}

	// Courtesy pre-check ONLY — see precheckRowOrdering's own header. A rejection here is a
	// friendlier error than the DB trigger's, never a substitute for it.
	const ordering = precheckRowOrdering(parsed.data.rows);
	if (!ordering.ok) {
		return json({ error: 'invalid_row_order', reason: ordering.reason }, { status: 400 });
	}

	// users_id NEVER from the request — always the validated session (Lock 14 mod #1). Not
	// passed to the RPC at all (SELF-267 D-2(i) precedent): the function is SECURITY INVOKER
	// and derives the tenant from auth.uid() internally, for the parent row AND every child
	// row uniformly (R4's grain (C) — see DDL ASSUMPTIONS above).
	const { error: writeError } = await locals.supabase.schema('pfin').rpc('fn_tax_bracket_schedule_replace_all', {
		p_schedule_id: scheduleId,
		p_tax_year: parsed.data.tax_year,
		p_schedule_type: parsed.data.schedule_type,
		p_standard_deduction: parsed.data.standard_deduction,
		p_tax_balance_prior_year: parsed.data.tax_balance_prior_year,
		p_rows: parsed.data.rows
	});

	if (writeError) {
		const { status, body } = mapReplaceError(writeError);
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
