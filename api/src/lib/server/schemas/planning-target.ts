// planning-target.ts — server-side Zod schemas for the SELF-233 / SELF-242 planning-target
// write path (POST + DELETE /api/settings/planning-target; migration 074 / ADR-056; RT-23).
//
// SOURCE OF TRUTH: Frontend (SELF-242's editor UI) mirrors this client-side (Lock 14) and
// must never ship a looser schema. `.strict()` is the mass-assignment fence (Lock 14 mod #1)
// — `users_id` is deliberately NOT a field here: it is never read from the client, always
// derived from the session (auth.uid() via hooks.server.ts). `target_percent` runs through
// the shared numeric battery (Lock 14 mod #2), shaped to 074's own DDL (numeric(5,2), CHECK
// 0..100) — see $lib/server/validation/numeric.ts.
//
// `sub_cat_id` is validated for SHAPE ONLY (positive integer) — mirrors classification.ts's
// classifySchema. Tenant + domain matching is the DB's Decision-3 canonical instance #17
// (074's `fn_planning_target_matched_sub_cat` BEFORE trigger); this schema does not
// re-implement that semantics.
//
// `planningTargetDeleteSchema` (SELF-242) is the DELETE-side sibling: Sec-ruled on the
// SELF-233 joint review (2026-08-17, carried forward on SELF-242) that "unset a target" MUST
// be a DELETE, never a POST of an explicit 0.00 — ADR-056 makes 0.00 a stored, DIFFERENT fact
// from row-absent, and a UI emulating unset with zero would silently destroy that
// distinction. `sub_cat_id` is the only field, same shape-only positive-integer check as the
// upsert schema; `.strict()` rejects any other posted key (in particular `users_id`, for the
// same mass-assignment reason as the upsert schema).

import { z } from 'zod';
import { sanitizePercent } from '$lib/server/validation/numeric';

/** Zod adapter over the shared percent-sanitization battery → a validated `number`. */
const percentValue = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizePercent(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/**
 * POST body for the planning-target UPSERT. `sub_cat_id` is a positive bigint FK's app-layer
 * SHAPE check only (pfin.user_taxonomy.id, small sequence value — Number() is exact, same
 * reasoning as account.ts's linkedSourceIdField); tenant/domain matching is the 074 trigger's
 * job, not this schema's. `.strict()` rejects any stray posted field (e.g. `users_id`).
 */
export const planningTargetUpsertSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive(),
		target_percent: percentValue()
	})
	.strict();

export type PlanningTargetUpsert = z.infer<typeof planningTargetUpsertSchema>;

/**
 * DELETE body for "unset a target" (SELF-242). Row-absent IS the unset representation
 * (074's header, UNSET SEMANTICS) — this schema carries no `target_percent` because a
 * DELETE is not a value write. `.strict()` rejects any stray posted field.
 */
export const planningTargetDeleteSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive()
	})
	.strict();

export type PlanningTargetDelete = z.infer<typeof planningTargetDeleteSchema>;
