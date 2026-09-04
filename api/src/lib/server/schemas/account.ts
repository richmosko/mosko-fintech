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
import {
	ACCOUNT_TYPES,
	TAX_TREATMENTS,
	TAX_JURISDICTIONS,
	CLOSURE_REASONS
} from '$lib/schemas/account-constants';
export { ACCOUNT_TYPES, TAX_TREATMENTS, TAX_JURISDICTIONS };

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
 * tax_jurisdiction (SELF-267 AC 2) — the §2.4.2 form's tax-authority control. Both variants
 * below accept '' (explicit clear) or one of TAX_JURISDICTIONS; an unrecognised non-empty
 * string (a typo'd value, a stale client) is REJECTED by the `.union`, never silently
 * coerced to a clear. They differ ONLY on what an ABSENT key means, because the two forms
 * that post through them have opposite defaults:
 *
 *   - CREATE (`taxJurisdictionCreateField`): absent → null. A brand-new account has no
 *     prior designation to preserve, so "the control wasn't touched" and "the control was
 *     touched and cleared" are the same outcome — null either way.
 *   - EDIT (`taxJurisdictionEditField`): absent → `undefined`, meaning "do not touch the
 *     column" — NOT "clear it". Frontend's account-edit control is HIDDEN (key absent from
 *     the post) for a provider-linked account, and hiding a control must not silently wipe
 *     whatever the column already holds (it's always null for a linked account today, but
 *     the contract is "no change", not "assume null"). Only an EXPLICIT `''` clears an
 *     existing designation on edit — the control must be rendered, pre-filled from the
 *     loaded row, for a user to reach that state deliberately.
 *
 * `updateAttributes` reads `undefined` vs `null` vs a value to decide whether to include
 * `tax_jurisdiction` in the UPDATE payload at all — see that action's own comment.
 */
const taxJurisdictionUnion = () =>
	z.union([z.enum(TAX_JURISDICTIONS), z.literal('')], {
		message: 'Choose a tax authority, or leave it unset.'
	});

const taxJurisdictionCreateField = () =>
	taxJurisdictionUnion()
		.optional()
		.transform((v) => (v ? v : null));

const taxJurisdictionEditField = () =>
	taxJurisdictionUnion()
		.optional()
		.transform((v) => (v === undefined ? undefined : v === '' ? null : v));

/**
 * Manual-account create (AC #1/#2). Six user attributes, plus SELF-267 AC 2's optional
 * tax-authority designation — the §2.4.2 form MAY present the field at creation, but it
 * is NOT a parameter of `fn_create_manual_account` (087's signature is unchanged; the
 * check that the RPC's INSERT column list still succeeds unchanged with this column
 * NULLABLE-and-unset was run and recorded at 102's header). The create action realizes a
 * non-null value as a follow-up UPDATE under `account_update` — see that action's own
 * comment for the create-then-update sequencing and the 23505-after-create branch. The
 * account-level asset Sub-Cat field is removed — accounts aren't classified per-account
 * (allocation classifies per-asset / per-transaction). The column + its param were
 * physically dropped at migration 048 (Decision-3 #5 DROPPED); the create action calls the
 * 6-arg fn_create_manual_account. `.strict()` rejects any stray posted `sub_cat_id`.
 */
export const manualAccountCreateSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS),
		initial_value: currencyAmount(),
		as_of_date: isoDate(),
		tax_jurisdiction: taxJurisdictionCreateField()
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

/**
 * CLOSE / REOPEN — two schemas, because they are two operations (ADR-042; 059).
 *
 * These replace the single `toggleActiveSchema`, and the split is the point rather than a
 * side-effect of the `is_active` drop. That schema carried a boolean whose two values needed
 * DIFFERENT payloads, so requiredness had to be expressed as a `.refine()` over the flag —
 * `reason_code` optional in the shape, then conditionally mandatory. That is a state machine
 * wearing a boolean, and it is the same mistake at the app layer that ADR-042 removed at the
 * schema layer: a boolean cannot carry a transition. Two schemas make `reason_code` plainly
 * REQUIRED where it is required and ABSENT where it is meaningless, so `.strict()` alone is the
 * fence and there is no cross-field rule to keep in step with 058.
 *
 * They mirror the two INVOKER RPCs 1:1 (`fn_close_account` / `fn_reopen_account`), which is the
 * property worth preserving: one posted shape per DB entry point, so a mismatch is a type error
 * rather than a runtime refusal.
 */

/** CLOSE. `reason_code` is REQUIRED — 058's audit writer refuses a close without one and
 *  deliberately will not invent it, so the app must not either. No date field: `p_closed_at`
 *  defaults to server now(), and a client clock would trip the gate's own future-date bound. */
export const closeAccountSchema = z
	.object({
		reason_code: z.enum(CLOSURE_REASONS, {
			message: 'Choose a reason for closing this account.'
		})
	})
	.strict();

export type CloseAccount = z.infer<typeof closeAccountSchema>;

/** REOPEN. Deliberately EMPTY: a reopen has no reason vocabulary (057 scopes requiredness to
 *  `event_type = 'closed'`) and takes no date from the client. `.strict()` on an empty object is
 *  load-bearing — it rejects a stray `reason_code` or `closed_at` rather than ignoring it. */
export const reopenAccountSchema = z.object({}).strict();

export type ReopenAccount = z.infer<typeof reopenAccountSchema>;

/**
 * Account-detail attribute edit (`accounts/[account_id]` updateAttributes action). The four
 * user-editable account attributes — name / account_type / scope / tax_treatment — plus
 * SELF-267 AC 2's `tax_jurisdiction` designation. Mirrors the manual-create field rules
 * VERBATIM (name/scope free-text 1..200; enums from the shared account-constants,
 * anti-drift with the DB CHECK). Deliberately does NOT include the aggregator / connection
 * binding (deferred) nor `closed_at` (that's the close/reopen path, and 058 fences it at
 * the DB regardless) — `.strict()` rejects any of those if posted (Lock 14 mass-assignment
 * fence). ⚠ `tax_jurisdiction` is OPTIONAL IN SHAPE and ABSENCE MEANS "DO NOT TOUCH THE
 * COLUMN" — NOT a clear. See `taxJurisdictionEditField`'s header: Frontend's control is
 * HIDDEN (key absent) for a provider-linked account, and hiding it must never wipe
 * whatever the column already holds. Only an explicit `''` clears an existing designation.
 * `parsed.data.tax_jurisdiction` is therefore `'irs' | 'ftb' | null | undefined`, and the
 * action includes the key in its UPDATE payload only when it is NOT `undefined`.
 */
export const updateAttributesSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS),
		tax_jurisdiction: taxJurisdictionEditField()
	})
	.strict();

export type UpdateAttributes = z.infer<typeof updateAttributesSchema>;

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
