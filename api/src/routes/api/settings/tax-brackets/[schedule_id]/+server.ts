// +server.ts — POST /api/settings/tax-brackets/:schedule_id (SELF-259 AC6 / Lock 14 / ADR-011
// Decision 18 Sec mod / R4 (docs/records/v14-preflight/sitting-log.md § R4) / E8 (team-lead
// ruling, 2026-09-03, on Backend's flagged atomicity gap) / E33 (team-lead ruling, 2026-09-04,
// consolidating the write path — see below)).
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
// PostgREST's `.rpc()` matches parameters BY NAME, not position, so the payload lists
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
// seed is the only current first-row writer, and SELF-265's createSchedule action is the second).
// The deferred set-property trigger fires at COMMIT, which for a single RPC call is the end of
// this one PostgREST request — so a set-fence rejection surfaces as THIS call's `error`, not as
// some later step's.
//
// P0001 AMBIGUITY, NAMED RATHER THAN SILENTLY RESOLVED: the function's OWN "absent/other-tenant"
// lock failure, its per-row matched-tenant trigger fence (#18), and its deferred zero-floor /
// rate-monotonicity trigger fence are DISTINCT failures that may ALL surface as SQLSTATE
// P0001 (plpgsql's default code for an un-coded `raise exception`) — there is no SQLSTATE-level
// way to tell them apart. CONFIRMED against the landed migration (101): none of its `raise
// exception` sites carry an explicit `errcode`, so all three conditions genuinely do collapse to
// P0001 — this is a real ambiguity, not a gap in what this file could confirm. This endpoint
// therefore does NOT attempt message-string classification of the RPC's own P0001 — see the
// shared write module's own comment for why that would be fragile, security-relevant guesswork
// rather than a mechanical distinction. Instead, the PRIMARY 404 path is a separate, RLS-scoped
// ownership read BEFORE the RPC call (now inside that shared module — see below) — reliable,
// SQLSTATE-independent, and consistent with this endpoint's existing "never trust {schedule_id}
// alone" discipline. The RPC's own internal not-found path is then a narrow, race-window backstop
// (the schedule vanishing between the ownership read and the RPC call) that collapses into the
// same generic 400 as the two trigger fences — a named, accepted residual, not a silent gap.
// Sec's SELF-259 joint review (docs/records/v14-execution/self259-sec-review.md @ b53f766, F-6)
// reviewed this design and endorsed it as written: message-string classification of a
// security-relevant error is exactly the fragile guesswork it declines to do, and the pre-RPC
// ownership read already gives a reliable 404 for the one case that actually needs
// distinguishing. Sec's own suggested improvement — a distinct SQLSTATE (not P0001) on the
// function's lock-failure raise, e.g. `errcode = 'PT404'` — remains a sound future improvement,
// not a condition of any review to date; not implemented here.
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
// ── ONE HOME FOR THE REPLACE-ALL FENCE (team-lead ruling E33, 2026-09-04) ──────────────────────
// The ownership read, the schedule-identity guard, the courtesy row-ordering precheck, the RPC
// call, and the RPC's SQLSTATE → error-code mapping described above are no longer implemented IN
// THIS FILE — they live in `$lib/server/queries/taxBracketScheduleWrite.ts`'s
// `replaceTaxBracketSchedule`, which `/settings/tax-brackets/+page.server.ts`'s
// saveSchedule/createSchedule actions (SELF-265) delegate to as well, so the two write paths
// share one implementation rather than two independently-maintained copies of the same fence.
// This file's job is now exactly the HTTP boundary: auth gate → route-param shape guard → JSON
// body parse → schema validate → delegate → serialize the shared module's `ReplaceOutcome` into
// THIS response contract, byte-identical to before the refactor — this endpoint's own two test
// files (tax-brackets.server.test.ts, tax-brackets.rt24-adversarial.server.test.ts) pass
// unchanged, which is the refactor's own acceptance test (E33: "the endpoint is the
// Sec-reviewed one" — its status/body contract governs, and the shared module was made to match
// it, not the reverse). The shared module's `ReplaceErrorCode` vocabulary IS this endpoint's own
// pre-refactor `error` strings, verbatim, so the mapping below is a direct passthrough, not a
// re-derivation.
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
//      to a clean 4xx, never to re-derive the semantics itself — literally true now, since the
//      mapping lives in the shared module and this file only serializes its outcome.
//
// ⚠ RT-24 (docs/SECURITY/index.html) STAYS FLAGGED, NOT FIXED HERE: its row text names a BEFORE
// INSERT/UPDATE trigger over a column called `lower_bound`; the landed DDL (5f69249) has a
// DEFERRED CONSTRAINT TRIGGER over `bracket_floor`. Sec's doc to correct at the SELF-259 joint
// review, per the prior revision of this file's flag — carried forward, not re-litigated here.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { taxBracketScheduleReplaceSchema } from '$lib/server/schemas/tax-bracket-schedule';
import { fieldErrors } from '$lib/server/schemas/account';
import { replaceTaxBracketSchedule } from '$lib/server/queries/taxBracketScheduleWrite';

/** Shape-only guard on the route param — RLS (via the shared helper's own ownership read) is
 *  the actual tenant/visibility boundary, mirroring accounts/[account_id]'s parseAccountId and
 *  transactions/[trans_id]'s parseTransId. `Number.isSafeInteger` rather than a smaller bound:
 *  the PK is `bigint generated always as identity` (migration 101), and a JS
 *  `Number.isSafeInteger` id fits every value the table's own identity sequence will ever
 *  produce (same reasoning account.ts's linkedSourceIdField / classification.ts's
 *  classifySchema already rely on for bigint FK shape-checks). */
function parseScheduleId(param: string | undefined): number | null {
	const n = Number(param);
	return Number.isSafeInteger(n) && n > 0 ? n : null;
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

	// ONE HOME FOR THE FENCE (E33) — ownership read → identity guard → courtesy precheck → RPC
	// call → SQLSTATE mapping, all inside the shared helper. See file header.
	const result = await replaceTaxBracketSchedule(locals.supabase, scheduleId, parsed.data);

	if (!result.ok) {
		// `result.error` IS this endpoint's own pre-refactor error-string vocabulary — a direct
		// passthrough, not a re-derivation. `invalid_row_order` is the one case that carries an
		// extra `reason` field, matching this endpoint's original body shape exactly.
		const body: Record<string, unknown> = { error: result.error };
		if (result.reason !== undefined) body.reason = result.reason;
		return json(body, { status: result.status });
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
