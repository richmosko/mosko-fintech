// transaction.ts — server-side Zod schemas for the manual cash-transaction surfaces
// (SELF-202 §2.4.3.a; migration 038 / ADR-032). Backend-owned server source.
//
// SOURCE OF TRUTH: Frontend mirrors these client-side (Lock 14) and must never ship a
// looser schema. `.strict()` is the mass-assignment fence (Lock 14 mod #2); the numeric
// battery is the type-confusion fence (Lock 14 mod #1). There is NO skip/exclusion field
// anywhere — a "don't count it" is categorize-as-Transfer + a report-view filter, never
// stored state (ADR-032). `transaction_type` is NEVER a form input — the RPC/edit path
// always sets it (cash = 'standard'); the Income/Expense/Transfer distinction is the
// CATEGORY class (sub_cat_id → 028 taxonomy), not transaction_type.
//
// AMOUNT SIGN CONTRACT: `amount` is the SIGNED ledger amount (+inflow / −outflow, per 017).
// The category (sub_cat_id) is independent of the sign in V1 (the GL derives class from the
// category per ADR-031 D3). Whether the entry UI presents a signed field or an
// Income/Expense toggle that flips the sign is a Frontend UX choice over this same contract.

import { z } from 'zod';
import { sanitizeCurrencyAmount } from '$lib/server/validation/numeric';
export { fieldErrors } from '$lib/server/schemas/account'; // single shared ZodError flattener

/** Zod adapter over the shared numeric battery → a validated finite `number`. */
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
const nonZeroAmount = () =>
	currencyAmount().refine((n) => n !== 0, 'Amount cannot be zero.');

/** Real-calendar-date guard for the ISO date (rejects 2026-02-31 etc.). Mirrors account.ts. */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/** Nullable cashflow Sub-Cat id. Empty-string ("Unsorted") / missing → null; else a
 *  positive int. Matched-tenant is DB-enforced (#10 annotation fence / #13 split fence). */
const subCatIdField = () =>
	z
		.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		)
		.default(null);

/** A positive-int transaction id supplied by the client (a hidden form field). RLS + the
 *  004 matched-account fence are the security boundary; this is shape validation only. */
const transIdField = () => z.coerce.number().int().positive();

/** A positive-int security/asset id (the held-position picker value for a stock split).
 *  Shape only — RLS + the 017 #7 security fence + the fn_create_stock_split guards are the
 *  security boundary. */
const securityIdField = () => z.coerce.number().int().positive();

/** A strictly-positive ratio component (num or den). Runs the shared numeric battery (the
 *  NaN/Inf/scientific/currency-string type-confusion fence — Lock 14 mod #1), then requires
 *  > 0: a split ratio is a POSITIVE rational (forward num/den>1, reverse num/den<1; both
 *  book-neutral). The DB re-validates (positive-rational + no-op) — this is fast UX feedback. */
const positiveRatioComponent = () =>
	currencyAmount().refine((n) => n > 0, 'Enter a value greater than zero.');

const optionalText = (max: number) =>
	z
		.preprocess((v) => (v === '' || v === undefined ? null : v), z.string().trim().max(max).nullable())
		.default(null);

// ── (1) Manual cash entry — fn_create_manual_trans RPC boundary ────────────────────────
// account_id is NOT a form field — it comes from the route param (accounts/[account_id]).
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

// ── (2a) Fact edit — reverse-and-replace (004 immutable ledger; NO UPDATE) ──────────────
// The corrected fact fields + which original row is being replaced. sub_cat_id/note carry
// the category/note onto the replacement row (usually copied unchanged from the original).
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

// ── (2b) Category/note edit — a 023 annotation upsert (NOT a ledger touch) ──────────────
export const recategorizeSchema = z
	.object({
		trans_id: transIdField(),
		sub_cat_id: subCatIdField(),
		note: optionalText(500)
	})
	.strict();
export type Recategorize = z.infer<typeof recategorizeSchema>;

// ── (3) Split — a balanced child set over the 029 write path ────────────────────────────
// One split line. `amount` is the SIGNED child amount; Σ(children) MUST equal parent.amount
// (029 Σ=parent deferred trigger is the authoritative backstop — we also pre-check for UX).
export const splitLineSchema = z
	.object({
		amount: nonZeroAmount(),
		sub_cat_id: subCatIdField(),
		note: optionalText(500),
		display_order: z.coerce.number().int().nonnegative().nullable().default(null)
	})
	.strict();
export type SplitLine = z.infer<typeof splitLineSchema>;

// CREATE or REPLACE a split: the parent trans_id + the full balanced set (≥2 lines — a
// 1-line split is just the parent). Frontend posts `lines` as a JSON array string; the
// action JSON-parses then validates with this schema.
export const splitSetSchema = z
	.object({
		trans_id: transIdField(),
		lines: z.array(splitLineSchema).min(2, 'A split needs at least two lines.').max(50, 'Too many split lines.')
	})
	.strict();
export type SplitSet = z.infer<typeof splitSetSchema>;

// UNSPLIT: delete the entire child set → revert to parent-only counting.
export const unsplitSchema = z.object({ trans_id: transIdField() }).strict();
export type Unsplit = z.infer<typeof unsplitSchema>;

// ── (2c) Classify — POST /api/transactions/:id/classify body (SELF-248 AC2). trans_id is the
// ROUTE param, not a body field. sub_cat_id is REQUIRED (unlike (2b) recategorizeSchema's
// nullable field, which also allows clearing to Unsorted) — classify always assigns a real
// category; `posting_prototype.id` is bigint, not UUID, and crosses the wire as a STRING —
// z.coerce.number() is the documented server-side coercion (classification.ts precedent).
export const classifyTransSchema = z
	.object({
		sub_cat_id: z.coerce.number().int().positive()
	})
	.strict();
export type ClassifyTrans = z.infer<typeof classifyTransSchema>;

// ── (4) Stock split — POSITION-LEVEL book-neutral corp_action (SELF-203; migration 039 /
// fn_create_stock_split; ADR-033). account_id is the route param, NOT a form field. There is
// NO `amount` here — a split is book-neutral; the RPC resolves the held position as-of ex_date
// (fn_holdings_as_of) and derives the quantity delta itself. transaction_type is RPC-set
// ('corp_action'), never a form input. The ratio is a positive rational (num:den).
export const stockSplitCreateSchema = z
	.object({
		security_id: securityIdField(),
		ratio_num: positiveRatioComponent(),
		ratio_den: positiveRatioComponent(),
		ex_date: isoDate()
	})
	.strict();
export type StockSplitCreate = z.infer<typeof stockSplitCreateSchema>;
