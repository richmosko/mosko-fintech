// planning-target.ts — CLIENT-SIDE Zod mirror of the SELF-233 planning-target write-path
// (POST /api/settings/planning-target; migration 074 / ADR-056; RT-23).
//
// MIRROR of src/lib/server/schemas/planning-target.ts. The SERVER schema is the security
// boundary (.strict() mass-assignment fence, Lock 14 mod #1 — only { sub_cat_id,
// target_percent } accepted; users_id is ALWAYS session-derived, never read from the
// client); THIS is the browser-side UX mirror consumed by SELF-242's planning-target-editor
// — fast field-level feedback before the POST/DELETE round-trip.
//
// Discipline (api/CLAUDE.md): never ship a client schema LOOSER than the server's. Same
// `.strict()` posture, same `sub_cat_id` shape-only positive-int gate, same numeric
// battery on `target_percent` via the client `sanitizePercent` mirror (validation/numeric.ts)
// — NOT a re-implementation of the battery, the shared client copy of it (Lock 14 mod #2).
// Backend owns the source of truth; when the server schema changes, this mirror updates in
// lockstep.
//
// UNSET is never expressed through this schema. Per ADR-056 + Sec's merge-gate binding
// constraint: "unset must be DELETE, never POST 0.00" — a cleared field calls DELETE
// /api/settings/planning-target (sub_cat_id only, no target_percent), which this schema
// does not model. An explicit 0.00 IS a valid, storable POST body — a real user-asserted
// zero target, a different fact from row-absent.

import { z } from 'zod';
import { sanitizePercent } from '$lib/validation/numeric';

/** Zod adapter over the shared client percent-sanitization battery → a validated `number`. */
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
 * POST body for the planning-target UPSERT. `sub_cat_id` is a positive-int SHAPE check
 * only (pfin.user_taxonomy.id) — tenant matching is the DB's Decision-3 canonical
 * instance #17 (074's `fn_planning_target_matched_sub_cat` BEFORE trigger), not this
 * schema's job. `.strict()` rejects any stray field the editor might accidentally attach.
 */
export const planningTargetUpsertSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive(),
		target_percent: percentValue()
	})
	.strict();

export type PlanningTargetUpsert = z.infer<typeof planningTargetUpsertSchema>;

/**
 * DELETE body — the "unset" affordance's sole payload. Deliberately NOT
 * `planningTargetUpsertSchema.pick(...)` sugar: a distinct, explicitly-named schema makes
 * the unset path's shape a first-class, greppable fact rather than a projection a future
 * edit could quietly widen back toward the upsert shape.
 */
export const planningTargetUnsetSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive()
	})
	.strict();

export type PlanningTargetUnset = z.infer<typeof planningTargetUnsetSchema>;
