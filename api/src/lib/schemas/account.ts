// account.ts — CLIENT-SIDE Zod mirror of the manual-account surfaces (SELF-201).
//
// MIRROR of src/lib/server/schemas/account.ts. The SERVER schema is the security
// boundary (.strict() mass-assignment fence + numeric type-confusion fence, Lock 14);
// THIS is the browser-side UX mirror — fast field-level feedback before the POST.
// Discipline (api/CLAUDE.md): never ship a client schema LOOSER than the server's.
// Same value-sets (imported from the shared browser-safe constants — single anti-drift
// point), same .strict() posture, same numeric battery (client copy). Backend owns the
// source of truth; when the server schema changes, this mirror updates in lockstep.

import { z } from 'zod';
import { ACCOUNT_TYPES, TAX_TREATMENTS, CLOSURE_REASONS } from '$lib/schemas/account-constants';
import { sanitizeCurrencyAmount } from '$lib/validation/numeric';

/** Zod adapter over the client numeric-sanitization battery → a validated `number`. */
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
 * Manual-account create (AC #1/#2) — mirrors manualAccountCreateSchema server-side.
 * Enum messages are friendlier than the server's raw enum error — a UX nicety, NOT a
 * loosening (same value-set, same .strict()). Matched-tenant is a DB-enforced boundary,
 * not checked here.
 *
 * Note: the account-level asset Sub-category (`sub_cat_id`) was removed from the product
 * (dead field — nothing read it for allocation/NAV; allocation classifies per-asset via
 * user_asset_category, not per-account). The DB column stays dormant; Backend passes null.
 */
export const manualAccountCreateSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES, { message: 'Choose an account type.' }),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS, { message: 'Choose a tax treatment.' }),
		initial_value: currencyAmount(),
		as_of_date: isoDate()
	})
	.strict();

export type ManualAccountCreate = z.infer<typeof manualAccountCreateSchema>;

/** Inactive-toggle (AC #3) — mirrors toggleActiveSchema server-side. */
export const toggleActiveSchema = z
	.object({
		is_active: z.preprocess(
			(v) => v === true || v === 'true' || v === 'on' || v === '1',
			z.boolean()
		),
		// Required to CLOSE, absent to REOPEN — 058's audit writer refuses a close with no
		// reason and deliberately will not invent one. Optional here and enforced by the
		// refinement below, so the reopen path is not forced to post a meaningless value.
		reason_code: z.enum(CLOSURE_REASONS).optional()
	})
	.strict()
	.refine((v) => v.is_active || v.reason_code !== undefined, {
		path: ['reason_code'],
		message: 'Choose a reason for closing this account.'
	});

export type ToggleActive = z.infer<typeof toggleActiveSchema>;

/**
 * Account-detail attribute edit — CLIENT mirror of the server `updateAttributesSchema`
 * (`accounts/[account_id]` `?/updateAttributes`). The four user-editable attributes:
 * name / account_type / scope / tax_treatment. Field rules copied VERBATIM from the manual-create
 * mirror (name/scope free-text 1..200; enums from the shared account-constants, anti-drift with the
 * DB CHECK). Deliberately excludes the aggregator/connection binding (deferred) and is_active (the
 * toggle path) — `.strict()` rejects any stray posted field, matching the server mass-assignment fence.
 */
export const updateAttributesSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES, { message: 'Choose an account type.' }),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS, { message: 'Choose a tax treatment.' })
	})
	.strict();

export type UpdateAttributes = z.infer<typeof updateAttributesSchema>;

/**
 * Flatten a ZodError into `{ field: [messages] }` keyed by the top-level field.
 * Mirrors the server helper so client + server errors render through one code path.
 * Root-level issues bucket under `_form`.
 */
export function fieldErrors(error: z.ZodError): Record<string, string[]> {
	const out: Record<string, string[]> = {};
	for (const issue of error.issues) {
		const key = issue.path.length ? String(issue.path[0]) : '_form';
		(out[key] ??= []).push(issue.message);
	}
	return out;
}
