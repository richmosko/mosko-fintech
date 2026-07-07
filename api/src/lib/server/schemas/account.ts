// account.ts — server-side Zod schemas for the manual-account surfaces (SELF-201).
//
// SOURCE OF TRUTH: Frontend mirrors these client-side (Lock 14) and must never ship
// a looser schema. `.strict()` is the mass-assignment fence (Lock 14 mod #2); the
// numeric battery is the type-confusion fence (Lock 14 mod #1). Enum value-sets are
// copied VERBATIM from the DB CHECK constraints (003 pfin.account) so the app layer
// and the DB agree — the DB CHECK is the authoritative backstop.

import { z } from 'zod';
import { sanitizeCurrencyAmount } from '$lib/server/validation/numeric';
// Shared value-sets live in a browser-safe module so Frontend's client mirror
// imports the SAME canonical enums (anti-drift). Re-exported here for server-side
// consumers that already reference them via this module.
import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';
export { ACCOUNT_TYPES, TAX_TREATMENTS };

/** Zod adapter over the shared numeric-sanitization battery → a validated `number`. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** Real-calendar-date guard for the ISO bootstrap date (rejects 2026-02-31 etc.). */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/**
 * Manual-account create (AC #1/#2). Six user attributes + nullable Sub-Cat.
 * `sub_cat_id` NULL = untagged / Unsorted-pending (012); empty-string from the
 * dropdown coerces to null. Matched-tenant is DB-enforced (fn_account_matched_sub_cat)
 * even if a tampered client posts a foreign id — this schema is UX + shape, the DB
 * trigger is the security boundary.
 */
export const manualAccountCreateSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS),
		initial_value: currencyAmount(),
		as_of_date: isoDate(),
		sub_cat_id: z.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		).default(null)
	})
	.strict();

export type ManualAccountCreate = z.infer<typeof manualAccountCreateSchema>;

/** Inactive-toggle (AC #3). Single boolean; coerces form string/checkbox values. */
export const toggleActiveSchema = z
	.object({
		is_active: z.preprocess(
			(v) => v === true || v === 'true' || v === 'on' || v === '1',
			z.boolean()
		)
	})
	.strict();

export type ToggleActive = z.infer<typeof toggleActiveSchema>;

/**
 * Flatten a ZodError into `{ field: [messages] }` keyed by the top-level field.
 * Built from `error.issues` directly (stable across Zod v3/v4; avoids the
 * soft-deprecated `.flatten()` method). Root-level issues bucket under `_form`.
 */
export function fieldErrors(error: z.ZodError): Record<string, string[]> {
	const out: Record<string, string[]> = {};
	for (const issue of error.issues) {
		const key = issue.path.length ? String(issue.path[0]) : '_form';
		(out[key] ??= []).push(issue.message);
	}
	return out;
}
