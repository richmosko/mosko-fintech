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
import {
	ACCOUNT_TYPES,
	TAX_TREATMENTS,
	TAX_JURISDICTIONS,
	CLOSURE_REASONS
} from '$lib/schemas/account-constants';
import { sanitizeCurrencyAmount } from '$lib/validation/numeric';

/**
 * tax_jurisdiction (SELF-267 AC 2) — PROVISIONAL, ahead of Backend's server schema (this branch's
 * `$lib/server/schemas/account.ts` does not yet accept this field; Backend's `feature/self-267-
 * backend` lands it in parallel — reconcile on relay). `''` is the client's own convention for
 * "unset", NOT a third DB enum member (TAX_JURISDICTIONS is the DB type's two values only —
 * account-constants.ts). Never LOOSER than the server: same two enum values, same nullable-as-
 * empty-string posture the contract states Backend's schema will share.
 */
const taxJurisdictionField = () =>
	z.enum(['', ...TAX_JURISDICTIONS] as const, {
		message: 'Choose IRS, FTB, or leave this account unset.'
	});

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
		// SELF-267 AC 2 — always present on this form (manual-only; every account this flow
		// creates is a valid tax-authority-designation candidate). '' = not designated.
		tax_jurisdiction: taxJurisdictionField(),
		initial_value: currencyAmount(),
		as_of_date: isoDate()
	})
	.strict();

export type ManualAccountCreate = z.infer<typeof manualAccountCreateSchema>;

/**
 * CLOSE / REOPEN — two schemas, mirroring Backend's split of the same name (ADR-042; `059`).
 *
 * These REPLACE the single `toggleActiveSchema`. The split is the point, not fallout from the
 * `is_active` drop: one schema meant a boolean whose two values needed different payloads, so
 * `reason_code` had to be optional-in-the-shape and then made mandatory by a cross-field
 * `.refine()`. That is a state machine wearing a boolean — the same mistake at the app layer
 * that ADR-042 removed at the schema layer. Two schemas make `reason_code` plainly REQUIRED
 * where it is required and ABSENT where it is meaningless, so `.strict()` alone is the fence.
 *
 * Mirror discipline (api/CLAUDE.md): never LOOSER than the server. Worth stating what that means
 * once the shapes are this small — `closeAccountSchema` below is field-for-field identical to
 * Backend's, and `reopenAccountSchema` is identical *including its emptiness*, which is the half
 * a reader is most likely to assume is a stub.
 */

/**
 * CLOSE. `reason_code` REQUIRED — `058`'s audit writer refuses a close with no reason and
 * deliberately will not invent one, so neither does the app. No date field: `p_closed_at`
 * defaults to server `now()`, and a client clock would trip the gate's own future-date bound.
 */
export const closeAccountSchema = z
	.object({
		reason_code: z.enum(CLOSURE_REASONS, {
			message: 'Choose a reason for closing this account.'
		})
	})
	.strict();

export type CloseAccount = z.infer<typeof closeAccountSchema>;

/**
 * REOPEN. Deliberately EMPTY — a reopen has no reason vocabulary (`057` scopes requiredness to
 * `event_type = 'closed'`) and takes no date from the client. `.strict()` on an empty object is
 * load-bearing server-side: it REJECTS a stray `reason_code` or `closed_at` rather than ignoring
 * it.
 *
 * ⚠ EXPORTED BUT DELIBERATELY NOT WIRED to the reopen form's `use:enhance`, and the reason is a
 * trap rather than an oversight. A client mirror's only job here would be to `cancel()` the
 * submit on a stray field — but the stray field's name is by definition one no error slot on the
 * page renders, so the user would press Reopen and see NOTHING HAPPEN. The server's 400 is the
 * better outcome: it is visible. Kept in the file so the mirror stays in lockstep with Backend's
 * schema and a future non-empty reopen payload has an obvious home — NOT because it is dead.
 */
export const reopenAccountSchema = z.object({}).strict();

export type ReopenAccount = z.infer<typeof reopenAccountSchema>;

/**
 * Account-detail attribute edit — CLIENT mirror of the server `updateAttributesSchema`
 * (`accounts/[account_id]` `?/updateAttributes`). The four user-editable attributes:
 * name / account_type / scope / tax_treatment. Field rules copied VERBATIM from the manual-create
 * mirror (name/scope free-text 1..200; enums from the shared account-constants, anti-drift with the
 * DB CHECK). Deliberately excludes the aggregator/connection binding (deferred) and `closed_at`
 * (that is the close/reopen pair above, and `058` fences it at the DB regardless) — `.strict()`
 * rejects any stray posted field, matching the server mass-assignment fence.
 */
export const updateAttributesSchema = z
	.object({
		name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		account_type: z.enum(ACCOUNT_TYPES, { message: 'Choose an account type.' }),
		scope: z.string().trim().min(1, 'Scope is required.').max(200, 'Scope is too long.'),
		tax_treatment: z.enum(TAX_TREATMENTS, { message: 'Choose a tax treatment.' }),
		// SELF-267 AC 2 — OPTIONAL here, unlike the create mirror: the edit form hides this
		// control entirely for a provider-linked account (TaxJurisdictionField `hidden`), so a
		// linked account's submit carries no `tax_jurisdiction` key at all. `.strict()` still
		// rejects any OTHER stray key; only this one may be absent.
		tax_jurisdiction: taxJurisdictionField().optional()
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
