// purchase.ts — server-side Zod schemas for the SELF-325 manual purchase-path
// (`pfin.fn_create_manual_purchase`, migration 088). Backend-owned server source.
//
// SOURCE OF TRUTH: Frontend mirrors these client-side (Lock 14) and must never ship a looser
// schema. `.strict()` is the mass-assignment fence (Lock 14 mod #1). The numeric battery
// (`sanitizeCurrencyAmount` / `sanitizeQuantity`) is the type-confusion fence (Lock 14 mod #2).
//
// TWO MUTUALLY EXCLUSIVE MODES, per Architect's 088 contract (a fork the RPC itself enforces —
// "Supply either p_security_id ... or p_asset_type + p_asset_name ... — not both", and the
// reverse: neither raises too). Modeled as a `z.discriminatedUnion('mode', ...)` so the fork is
// explicit in the wire shape rather than a `.refine()` over an ambiguous flat object — the same
// reasoning schemas/account.ts's CLOSE/REOPEN split documents ("a boolean cannot carry a
// transition"; here it is a MODE, not a boolean, but the shape argument is identical):
//
//   BIND — `security_id` names an existing global-or-owned asset, resolved BEFORE this schema
//   ever runs (the worker's /asset/resolve leg for a market security, or a picker over
//   selectableAssets.ts for an already-owned one). This schema does NOT re-validate the
//   symbol/cusip identity — that boundary is assetResolveSchema's, a separate step.
//
//   MINT — `asset_type` + `asset_name` (+ optional `symbol`) mint a NEW caller-owned asset
//   inside the RPC's own transaction (house/car/private-holding path). Does NOT go through
//   /asset/resolve — a user cannot create a GLOBAL asset by any route (016 asset_insert WITH
//   CHECK rejects users_id NULL), and MINT isn't trying to.

import { z } from 'zod';
import { sanitizeCurrencyAmount, sanitizeQuantity } from '$lib/server/validation/numeric';
import { MINT_ASSET_TYPES } from '$lib/schemas/asset-constants';
export { fieldErrors } from '$lib/server/schemas/account'; // single shared ZodError flattener

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

/** Zod adapter over the shared numeric-sanitization battery (numeric(28,8) shape) → a validated
 *  `number`. Strict positivity is layered here, not in the sanitizer (see numeric.ts). */
const quantity = () =>
	z
		.any()
		.transform((val, ctx) => {
			const r = sanitizeQuantity(val);
			if (!r.ok) {
				ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
				return z.NEVER;
			}
			return r.value;
		})
		.refine((n) => n > 0, 'Enter a quantity greater than zero.');

const positiveCostBasis = () => currencyAmount().refine((n) => n > 0, 'Enter a value greater than zero.');

/** Real-calendar-date guard for the ISO trade date (rejects 2026-02-31 etc.). Mirrors
 *  transaction.ts / account.ts's isoDate(). */
const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

const optionalText = (max: number) =>
	z
		.preprocess((v) => (v === '' || v === undefined ? null : v), z.string().trim().max(max).nullable())
		.default(null);

/** Nullable cashflow Sub-Cat id. Empty-string ("Unsorted") / missing → null; else a positive
 *  int. Mirrors transaction.ts's subCatIdField() (duplicated per this repo's one-adapter-per-
 *  surface convention). Matched-tenant is DB-enforced (088's #10-chain 030 Trade fence). */
const subCatIdField = () =>
	z
		.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		)
		.default(null);

/** A positive-int pfin.asset.asset_id — either resolved via /asset/resolve (a market security)
 *  or picked from selectableAssets.ts (an already-owned asset). Shape only — the 088 Decision-3
 *  #7 BEFORE INSERT trigger is the authoritative tenant/visibility fence, not this. */
const securityIdField = () => z.coerce.number().int().positive();

const COMMON_FIELDS = {
	trade_date: isoDate(),
	quantity: quantity(),
	cost_basis: positiveCostBasis(),
	sub_cat_id: subCatIdField(),
	description: optionalText(500),
	note: optionalText(500)
};

const bindPurchaseSchema = z
	.object({
		mode: z.literal('bind'),
		security_id: securityIdField(),
		...COMMON_FIELDS
	})
	.strict();

const mintPurchaseSchema = z
	.object({
		mode: z.literal('mint'),
		asset_type: z.enum(MINT_ASSET_TYPES),
		asset_name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		// Optional per-asset symbol (e.g. a private holding's internal ticker). Mirrors
		// schemas/asset.ts's symbolField pattern (defense-in-depth even though 088 does not
		// dedup/constrain MINT symbols the way the global registry does).
		symbol: z.preprocess(
			(v) => (v === '' || v === undefined ? null : v),
			z
				.string()
				.trim()
				.max(20, 'Symbol is too long.')
				.regex(/^[A-Za-z0-9.\-]+$/, 'Symbol must be alphanumeric (with . or -).')
				.nullable()
		),
		...COMMON_FIELDS
	})
	.strict();

export const createPurchaseSchema = z.discriminatedUnion('mode', [bindPurchaseSchema, mintPurchaseSchema]);

export type CreatePurchaseInput = z.infer<typeof createPurchaseSchema>;
export type BindPurchaseInput = z.infer<typeof bindPurchaseSchema>;
export type MintPurchaseInput = z.infer<typeof mintPurchaseSchema>;
