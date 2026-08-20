// +server.ts — POST /api/settings/planning-target (SELF-233 / Lock 14 mods #1+#2 / RT-23).
//
// Hardened write path for pfin.planning_target (per-Sub-Cat "% Target", PRD §2.2.2;
// migration 074 / ADR-056). UPSERT on (users_id, sub_cat_id) — Decision 18 settings-store
// shape: unset is ROW ABSENT (never NULL, never a seeded zero); an explicit 0.00 is a
// stored, different fact. This endpoint owns the write; SELF-242's editor UI is the sole
// browser-side consumer of it (boundary ratified in the 238/240 AC sets — 242 does not
// re-implement any of this). SELF-242 does own the DELETE handler below, added HERE
// (Sec-ruled — see the DELETE section further down this header) rather than as a separate
// route, because it is the "unset" un-do of this same POST.
//
// Defense-in-depth, not duplication — three fences, three different owners:
//   1. `.strict()` Zod schema (Lock 14 mod #1, planningTargetUpsertSchema) rejects any
//      unschemed body property with 400 BEFORE the DB is ever touched. `users_id` is not a
//      schema field at all — it is always the validated session's own auth.uid() (SC3-C1
//      pattern, mirrors reauth/start), never read from the request body.
//   2. The shared numeric-sanitization battery (Lock 14 mod #2, sanitizePercent — SELF-201's
//      sibling, same six adversarial categories) rejects a malformed target_percent before
//      the DB is touched.
//   3. `sub_cat_id` is validated for SHAPE ONLY here (positive integer, mirrors
//      classification.ts's classifySchema). Tenant + domain matching is NOT re-implemented
//      at this layer — it is the DB's Decision-3 canonical instance #17
//      (`pfin.fn_planning_target_matched_sub_cat`, a BEFORE INSERT OR UPDATE trigger, 074).
//      This endpoint's job for that fence is only to map its rejection to a clean 4xx — see
//      mapWriteError below — never to re-derive tenant/domain matching itself.
//
// INVOKER + anon-key + RLS only: writes go through `locals.supabase`, the session-bound
// client wired at the hooks.server.ts chokepoint. service_role is FORBIDDEN here — RT-26's
// 3-surface allowlist (webhook / exchange / remove) is untouched by this endpoint.
//
// AUDIT-LOG TENSION — surfaced to Sec at joint review, not resolved unilaterally here:
// api/CLAUDE.md's blanket "every state-changing write emits a same-transaction audit-log
// row" convention does NOT apply to this table. ADR-011 Decision 18 classifies settings
// (planning_target included) as NOT audit-class: UPSERT-in-place, no edit-history rows, by
// design (that is also why DELETE is a granted operation here — "unset" must be able to
// remove the row, which an audit-class table's append-only discipline would forbid). This
// endpoint therefore emits no audit-log row. Flagged for Sec to rule on the record rather
// than silently reconciled against the CLAUDE.md convention.
//
// DELETE /api/settings/planning-target — "unset a target" (SELF-242; Sec-ruled at the
// SELF-233 joint review, 2026-08-17, carried forward on SELF-242): ⚠ unset MUST be a DELETE,
// never a POST of an explicit 0.00 — ADR-056 makes 0.00 a stored, DIFFERENT fact from
// row-absent (074's header, UNSET SEMANTICS), and a UI emulating unset with zero would
// silently destroy that distinction. Lands HERE, beside the POST it is the un-do of, per
// Sec's ruling. Carries the SAME three Lock-14 fences as POST: (1) `.strict()` shape
// validation (planningTargetDeleteSchema — sub_cat_id only), (2) session-derived users_id,
// never from the request body, applied as an EXPLICIT `.eq('users_id', ...)` predicate on
// the delete query (a DELETE has no row payload the way an INSERT/UPSERT does, so the fence
// has to be a query predicate rather than a WITH-CHECK-observable field), (3) clean 4xx
// mapping — except there is little TO map: 074's matched-tenant/domain trigger is BEFORE
// INSERT OR UPDATE only, so it never fires on DELETE. The only DB-side gate on DELETE is the
// `planning_target_delete` RLS policy's USING clause (owner + 025 aal2 clause), and per 074's
// own header that clause "affects 0 rows, silently and correctly" when it does not match —
// there is no distinguishable error for row-absent vs cross-tenant-hidden vs
// below-aal2-filtered, by design (distinguishing them would leak cross-tenant existence /
// step-up state to the caller). This endpoint therefore returns the SAME 200 success shape
// in all three cases — DELETE is idempotent by REST convention, and "unset something already
// unset" is correctly a no-op success, never a 404.

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { PostgrestError } from '@supabase/supabase-js';
import { planningTargetUpsertSchema, planningTargetDeleteSchema } from '$lib/server/schemas/planning-target';
import { fieldErrors } from '$lib/server/schemas/account';

/**
 * Map a pfin.planning_target write failure to a clean 4xx. Every EXPECTED rejection path is
 * a 4xx, never a 500:
 *   - '42501' — RLS WITH CHECK violation. In practice this is the 025 aal2 step-up backstop
 *     (mfa_policy is totp/passkey and the session is at aal1); users_id can't mismatch here
 *     since it is always server-derived, never client-supplied.
 *   - 'P0001' — the 074 matched-tenant/matched-domain trigger's three legs (unresolvable /
 *     cross-tenant / wrong-domain sub_cat_id). Deliberately collapsed to one generic 4xx
 *     reason rather than relaying the trigger's own message: the three legs' exact
 *     diagnostics are a DB-internal distinction (useful in a migration/pgTAP context), not
 *     information this endpoint should hand an adversarial caller.
 *   - '23503' — FK violation. Defensive fallback only: the BEFORE trigger's leg-1 read
 *     resolves (or fails to resolve) sub_cat_id before Postgres would ever reach the FK
 *     check, so this path is not expected to fire in practice.
 *   - '23514' — the DB CHECK on target_percent (0..100). Defense-in-depth only — the
 *     app-layer battery (sanitizePercent) is the first line and rejects this before the DB
 *     is reached.
 * Anything else is genuinely unexpected and stays a logged 500 — turning every DB error into
 * a fake 4xx would hide a real outage or a schema drift this endpoint doesn't know about.
 */
function mapWriteError(error: PostgrestError): { status: number; body: { error: string } } {
	switch (error.code) {
		case '42501':
			return { status: 403, body: { error: 'step_up_required' } };
		case 'P0001':
		case '23503':
		case '23514':
			return { status: 400, body: { error: 'invalid_sub_cat_or_value' } };
		default:
			console.error('[planning-target] unexpected write error:', error.code, error.message);
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

	const parsed = planningTargetUpsertSchema.safeParse(raw);
	if (!parsed.success) {
		return json({ error: 'invalid_request', fieldErrors: fieldErrors(parsed.error) }, { status: 400 });
	}

	// users_id NEVER from the request — always the validated session (Lock 14 mod #1).
	const { error } = await locals.supabase
		.schema('pfin')
		.from('planning_target')
		.upsert(
			{
				users_id: user.id,
				sub_cat_id: parsed.data.sub_cat_id,
				target_percent: parsed.data.target_percent
			},
			{ onConflict: 'users_id,sub_cat_id' }
		);

	if (error) {
		const { status, body } = mapWriteError(error);
		return json(body, { status });
	}

	return json({ ok: true, sub_cat_id: parsed.data.sub_cat_id, target_percent: parsed.data.target_percent });
};

export const DELETE: RequestHandler = async ({ request, locals }) => {
	const { user } = await locals.safeGetSession();
	if (!user) return json({ error: 'unauthenticated' }, { status: 401 });

	let raw: unknown;
	try {
		raw = await request.json();
	} catch {
		return json({ error: 'invalid_request' }, { status: 400 });
	}

	const parsed = planningTargetDeleteSchema.safeParse(raw);
	if (!parsed.success) {
		return json({ error: 'invalid_request', fieldErrors: fieldErrors(parsed.error) }, { status: 400 });
	}

	// users_id NEVER from the request — always the validated session (Lock 14 mod #1),
	// applied here as an explicit query predicate (see file header for why a DELETE needs
	// this where the UPSERT above does not). No BEFORE trigger runs on DELETE (074's fence
	// is INSERT OR UPDATE only) — the planning_target_delete RLS policy's owner + aal2 USING
	// clause is the only other gate, and it silently excludes non-matching rows rather than
	// erroring. Genuinely unexpected DB errors (not a 074-trigger path — none exists here)
	// stay a logged 500, same discipline as mapWriteError above.
	const { error } = await locals.supabase
		.schema('pfin')
		.from('planning_target')
		.delete()
		.eq('users_id', user.id)
		.eq('sub_cat_id', parsed.data.sub_cat_id);

	if (error) {
		console.error('[planning-target] unexpected delete error:', error.code, error.message);
		return json({ error: 'internal_error' }, { status: 500 });
	}

	// Same success shape whether a row existed and was removed, was owned by another
	// tenant (RLS-hidden), or was below-aal2-gated — see file header. Never a 404.
	return json({ ok: true, sub_cat_id: parsed.data.sub_cat_id });
};
