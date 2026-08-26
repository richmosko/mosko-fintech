// transaction.ts — CLIENT-SIDE Zod mirror of the manual cash-transaction surfaces
// (SELF-202). MIRROR of src/lib/server/schemas/transaction.ts.
//
// The SERVER schema is the security boundary (.strict() mass-assignment fence + the
// numeric type-confusion battery, Lock 14); THIS is the browser-side UX mirror — fast
// field-level feedback before the POST. Discipline (api/CLAUDE.md Frontend conv): never
// ship a client schema LOOSER than the server's — same shape, same .strict() posture,
// same numeric battery (client copy). Backend owns the source of truth; when the server
// schema changes, this mirror updates in lockstep.
//
// AMOUNT SIGN CONTRACT: `amount` is the SIGNED ledger amount. The entry/edit UI presents
// a positive magnitude + an Inflow/Outflow toggle and derives the sign client-side
// (see toSignedAmount in $lib/transaction-util) BEFORE validating against these schemas.

import { z } from 'zod';
import { sanitizeCurrencyAmount } from '$lib/validation/numeric';

// Single shared ZodError flattener — same code path as the account forms (client + server).
export { fieldErrors } from '$lib/schemas/account';

/** Zod adapter over the client numeric-sanitization battery → a validated finite `number`. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** A non-zero signed money amount (a ledger/split line must move money). */
const nonZeroAmount = () => currencyAmount().refine((n) => n !== 0, 'Amount cannot be zero.');

/** Real-calendar-date guard for the ISO date (rejects 2026-02-31 etc.). Mirrors server. */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/** Nullable cashflow Sub-Cat id. Empty ("Unsorted") / missing → null; else positive int. */
const subCatIdField = () =>
	z
		.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		)
		.default(null);

/** A positive-int transaction id supplied by the client (hidden field). Shape only — RLS +
 *  the DB matched-account fence are the security boundary. */
const transIdField = () => z.coerce.number().int().positive();

const optionalText = (max: number) =>
	z
		.preprocess((v) => (v === '' || v === undefined ? null : v), z.string().trim().max(max).nullable())
		.default(null);

// ── (1) Manual cash entry — account_id comes from the route param, NOT a form field. ────
export const manualTransCreateSchema = z
	.object({
		transaction_date: isoDate(),
		amount: nonZeroAmount(),
		vendor: optionalText(200),
		description: optionalText(500),
		sub_cat_id: subCatIdField(),
		note: optionalText(500)
	})
	.strict();
export type ManualTransCreate = z.infer<typeof manualTransCreateSchema>;

// ── (2a) Fact edit — reverse-and-replace (immutable ledger; NO UPDATE). ─────────────────
export const manualTransEditSchema = z
	.object({
		orig_trans_id: transIdField(),
		transaction_date: isoDate(),
		amount: nonZeroAmount(),
		vendor: optionalText(200),
		description: optionalText(500),
		sub_cat_id: subCatIdField(),
		note: optionalText(500)
	})
	.strict();
export type ManualTransEdit = z.infer<typeof manualTransEditSchema>;

// ── (2b) Category/note edit — a 023 annotation upsert (NOT a ledger touch). ──────────────
export const recategorizeSchema = z
	.object({
		trans_id: transIdField(),
		sub_cat_id: subCatIdField(),
		note: optionalText(500)
	})
	.strict();
export type Recategorize = z.infer<typeof recategorizeSchema>;

// ── (2c) Classify (SELF-249 / SELF-248 §2.3.1.a) — CLIENT mirror of the server
// `classifyTransSchema` in api/src/lib/server/schemas/transaction.ts. Same shape, same
// `.strict()` posture: `sub_cat_id` is REQUIRED and non-nullable here (unlike (2b)'s
// `subCatIdField()`, which is nullable to support clearing back to "Unsorted") — the classify
// endpoint (SELF-248) always assigns a concrete category; there is no "clear via classify".
// This mirror is fast client-side feedback only; the server's `.strict()` schema + RLS + the
// FK/matched-tenant/journaled-cat fences (023/084/092) are the security boundary.
export const classifyTransSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive()
	})
	.strict();
export type ClassifyTrans = z.infer<typeof classifyTransSchema>;

// ── (3) Split — a balanced child set. `amount` is the SIGNED child amount; Σ(children) MUST
// equal parent.amount (the 029 deferred trigger is the authoritative backstop — the editor
// pre-checks the running sum for UX). ───────────────────────────────────────────────────
export const splitLineSchema = z
	.object({
		amount: nonZeroAmount(),
		sub_cat_id: subCatIdField(),
		note: optionalText(500),
		display_order: z.coerce.number().int().nonnegative().nullable().default(null)
	})
	.strict();
export type SplitLine = z.infer<typeof splitLineSchema>;

export const splitSetSchema = z
	.object({
		trans_id: transIdField(),
		lines: z
			.array(splitLineSchema)
			.min(2, 'A split needs at least two lines.')
			.max(50, 'Too many split lines.')
	})
	.strict();
export type SplitSet = z.infer<typeof splitSetSchema>;

// ── (3b) Unsplit — delete the entire child set → revert to parent-only counting. ─────────
export const unsplitSchema = z.object({ trans_id: transIdField() }).strict();
export type Unsplit = z.infer<typeof unsplitSchema>;

// ── (4) Stock split — POSITION-LEVEL book-neutral corp_action (SELF-203 / ADR-033). CLIENT
// mirror of src/lib/server/schemas/transaction.ts stockSplitCreateSchema (Backend's source of
// truth); same field shape, same .strict() posture, same numeric battery. account_id is the
// route param, NOT a form field; there is NO `amount` (book-neutral — the RPC derives the
// quantity delta from the held position). ────────────────────────────────────────────────

/** A positive-int security/asset id (the held-position picker value). Shape only — RLS + the
 *  017 #7 security fence + the fn_create_stock_split guards are the security boundary. */
const securityIdField = () => z.coerce.number().int().positive();

/** A strictly-positive ratio component (num or den). Runs the shared numeric battery (the
 *  NaN/Inf/scientific/currency-string type-confusion fence), then requires > 0: a split ratio
 *  is a POSITIVE rational (forward num/den>1, reverse num/den<1). The server + DB re-validate
 *  (positive-rational + no-op) — this is fast UX feedback only. */
const positiveRatioComponent = () =>
	currencyAmount().refine((n) => n > 0, 'Enter a value greater than zero.');

export const stockSplitCreateSchema = z
	.object({
		security_id: securityIdField(),
		ratio_num: positiveRatioComponent(),
		ratio_den: positiveRatioComponent(),
		ex_date: isoDate()
	})
	.strict();
export type StockSplitCreate = z.infer<typeof stockSplitCreateSchema>;
