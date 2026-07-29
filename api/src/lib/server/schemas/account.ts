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

/**
 * Nullable Sub-Cat id field, shared by the create + reassign paths so both validate
 * identically. Empty-string (dropdown "Unsorted") / missing → null; else a positive
 * integer. Matched-tenant is DB-enforced (012 fn_account_matched_sub_cat) regardless.
 */
const subCatIdField = () =>
	z
		.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		)
		.default(null);

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
		sub_cat_id: subCatIdField()
	})
	.strict();

export type ManualAccountCreate = z.infer<typeof manualAccountCreateSchema>;

/**
 * SELF-199 (§2.4.1.d) — per-account attribute capture for PROVIDER-LINKED accounts
 * (ADR-037; distinct from the manual path above). Seam (b) = (ii) client-carries-refs:
 * the browser carries the adapter's AccountRef[] + linked_source_id from the connect step
 * and submits, per SELECTED account, the four user attributes + the provider account id
 * (the AccountRef join key). Maps 1:1 to the `fn_land_linked_accounts` (042) `p_accounts`
 * element shape — the action renames `account_id` → `provider_account_id` at the RPC
 * boundary. Unselected accounts are simply absent from the array (never persisted, per AC).
 * Both envelope + element are `.strict()` (Lock 14 mass-assignment fence). `scope` is
 * free-text (ADR-004 Dec B); enums from the shared account-constants (anti-drift, same as
 * the manual form). `currency` is NOT threaded — it defaults to 'USD' (015) per the 042
 * contract (an optional per-account currency key can be added additively later).
 */
const linkedSourceIdField = () =>
	// pfin.linked_source.source_id is a bigint, serialized by the connect relay as a decimal
	// STRING (JSON-safe). Validate the digit-string here; the action coerces to a number for
	// the bigint RPC param (source_id is a small sequence value — Number() is exact).
	z.string().trim().regex(/^\d+$/, 'Invalid connection reference.');

export const linkedAccountAttrSchema = z
	.object({
		// The adapter AccountRef join key → persisted as pfin.account.provider_account_id.
		account_id: z.string().trim().min(1, 'Missing account reference.'),
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS),
		account_type: z.enum(ACCOUNT_TYPES)
	})
	.strict();

export type LinkedAccountAttr = z.infer<typeof linkedAccountAttrSchema>;

export const landLinkedAccountsSchema = z
	.object({
		linked_source_id: linkedSourceIdField(),
		// .min(1): the client only includes SELECTED accounts; an empty submit is a
		// client-prevented no-op the action rejects. .max(100): generous per-institution
		// cap (defensive; institutions expose well under this) — bounds the atomic txn.
		accounts: z
			.array(linkedAccountAttrSchema)
			.min(1, 'Select at least one account to add.')
			.max(100, 'Too many accounts in one submission.')
	})
	.strict();

export type LandLinkedAccounts = z.infer<typeof landLinkedAccountsSchema>;

/** Sub-Cat reassignment (SELF-236 §2.2.1.c). Single nullable field; nullable clears
 *  the tag ("Unsorted"). Matched-tenant fenced by the 012 trigger on UPDATE. */
export const reassignSubCatSchema = z.object({ sub_cat_id: subCatIdField() }).strict();

export type ReassignSubCat = z.infer<typeof reassignSubCatSchema>;

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
