// +server.ts — POST /api/settings/cashflow-target (SELF-252 / Lock 14 / RT-23-shaped).
//
// Hardened write path for pfin.cashflow_target (per-user cash-flow planning targets, PRD
// §2.3.2; migration 090 / ADR-011 Decision 18). UPSERT on `unique (users_id)` — Decision 18
// settings-store shape, same discipline as SELF-233's planning-target.ts. Unset is column
// SET NULL, WRITTEN BY UPSERT — NEVER a row DELETE (090's own UNSET SEMANTICS): this table
// carries TWO independent scalars (income_target_annual, expense_target_monthly) in ONE row,
// so a row DELETE would unset BOTH, silently discarding whichever target the caller did not
// intend to touch. The SELF-242 / planning-target.ts DELETE precedent's *verb* does not
// transplant here — that table is keyed per Sub-Cat (one row, one fact); this one is keyed per
// user (one row, two facts). See SELF-246 AC7 / migration 090 header.
//
// NULL-VS-OMITTED (AC3/AC6, sitting items 19/19a) is the crux of this endpoint, not an
// incidental detail: the write object below is built ONLY from keys whose parsed value is not
// `undefined` (schemas/cashflow-target.ts's `.optional()` keeps "absent" and "explicit null"
// distinguishable through parsing). An omitted key is never included in the upsert payload at
// all, so PostgREST's generated `ON CONFLICT DO UPDATE SET ...` clause never references that
// column — the existing value survives untouched. An explicit `null` IS included, with value
// `null`, so the column is explicitly SET NULL. This is the entire mechanism; there is no
// separate "leave alone" branch to get wrong.
//
// Defense-in-depth, three fences, three different owners (mirrors planning-target.ts):
//   1. `.strict()` Zod schema (Lock 14 mod #1, cashflowTargetUpsertSchema) rejects any
//      unschemed body property with 400 BEFORE the DB is ever touched. `users_id` is not a
//      schema field — it is always the validated session's own auth.uid(), never read from
//      the request body.
//   2. The shared numeric-sanitization battery (Lock 14 mod #2, sanitizeCurrencyAmount) plus
//      an explicit non-negative refine (the shared battery has no sign stance for this shape;
//      a negative cash-flow target has no product meaning and 090's own DB CHECK agrees)
//      rejects a malformed or negative amount before the DB is touched. This app-layer half is
//      OWED HERE and is not inherited — Sec's own note on `074`/RT-23: "RT-23 IS NOT SATISFIED
//      BY `074`", and this is a different table with its own write surface.
//   3. 090's DB CHECK (col is null or (col >= 0 and col <> 'NaN')) and its aal2-gated RLS WITH
//      CHECK are the backstop, mapped to a clean 4xx below rather than a raw DB error.
//
// INVOKER + anon-key + RLS only: writes go through `locals.supabase`, the session-bound client
// wired at the hooks.server.ts chokepoint. service_role is FORBIDDEN here — this route holds NO
// service_role key and adds no entry to the RT-26 allowlist registry
// (`scripts/ci/rt26-allowlist.txt`), which is therefore untouched (AC9). Read that registry live
// for its contents and carry no description of its shape here: ADR-016 Decision 4 pruned it to the
// single `supabase-admin.ts` factory precisely because a stale entry is a standing
// pre-authorization, and any future service_role need reuses that factory rather than adding an
// entry.
// ⚠ Do NOT spell the service-role env-var name in this file, not even to deny holding it. The
// RT-26 fence (`scripts/ci/fence-rt26-service-role-allowlist.sh`) is a filename-level grep for
// that literal across `api/src/` with no comment awareness, so any occurrence at a
// non-allowlisted path is a violation and fails a REQUIRED check. The fence is correct and must
// not be taught to skip comments; the prose bends around it. Same reason exchange/+server.ts
// says "NO service_role key".
//
// AUDIT-LOG: not applicable, per the SAME ADR-011 Decision 18 settings-not-audit-class ruling
// planning-target.ts's header records and flags to Sec at joint review rather than resolving
// unilaterally. No audit-log row is emitted here either.
//
// RESPONSE SHAPE — `200 { ok: true, income_annual?, expense_monthly? }`, echoing only the
// fields that were actually part of this write (an omitted field is omitted from the response
// too — `JSON.stringify` drops `undefined` keys, so this falls out of the response object
// construction without a separate branch).

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { PostgrestError } from '@supabase/supabase-js';
import { cashflowTargetUpsertSchema } from '$lib/server/schemas/cashflow-target';
import { fieldErrors } from '$lib/server/schemas/account';

/**
 * Map a pfin.cashflow_target write failure to a clean 4xx. Every EXPECTED rejection path is a
 * 4xx, never a 500:
 *   - '42501' — RLS WITH CHECK violation. In practice this is 090's own aal2 step-up backstop
 *     (mfa_policy is totp/passkey and the session is at aal1), copied byte-faithfully from 025
 *     — same as planning-target.ts's identical case. users_id can't mismatch here since it is
 *     always server-derived, never client-supplied.
 *   - '23514' — 090's own two-sided numeric CHECK (col >= 0 and col <> 'NaN'). Defense-in-depth
 *     only: the app-layer battery (sanitizeCurrencyAmount + the non-negative refine) is the
 *     first line and is expected to reject this before the DB is reached.
 * Anything else is genuinely unexpected and stays a logged 500 — turning every DB error into a
 * fake 4xx would hide a real outage or a schema drift this endpoint doesn't know about.
 */
function mapWriteError(error: PostgrestError): { status: number; body: { error: string } } {
	switch (error.code) {
		case '42501':
			return { status: 403, body: { error: 'step_up_required' } };
		case '23514':
			return { status: 400, body: { error: 'invalid_amount' } };
		default:
			console.error('[cashflow-target] unexpected write error:', error.code, error.message);
			return { status: 500, body: { error: 'internal_error' } };
	}
}

export const POST: RequestHandler = async ({ request, locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	const parsed = cashflowTargetUpsertSchema.safeParse(raw);
	if (!parsed.success) {
		return json({ error: 'invalid_request', fieldErrors: fieldErrors(parsed.error) }, { status: 400 });
	}

	// Build the write object ONLY from keys present in the parsed payload — see the file
	// header for why this is the entire null-vs-omitted mechanism. `users_id` NEVER from the
	// request — always the validated session (Lock 14 mod #1).
	const row: Record<string, string | number | null> = { users_id: user.id };
	if (parsed.data.income_annual !== undefined) row.income_target_annual = parsed.data.income_annual;
	if (parsed.data.expense_monthly !== undefined) row.expense_target_monthly = parsed.data.expense_monthly;

	const { error } = await locals.supabase
		.schema('pfin')
		.from('cashflow_target')
		.upsert(row, { onConflict: 'users_id' });

	if (error) {
		const { status, body } = mapWriteError(error);
		return json(body, { status });
	}

	return json({
		ok: true,
		income_annual: parsed.data.income_annual,
		expense_monthly: parsed.data.expense_monthly
	});
};
