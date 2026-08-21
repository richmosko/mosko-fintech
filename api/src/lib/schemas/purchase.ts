// purchase.ts — CLIENT-SIDE Zod mirror of the SELF-325 manual-purchase surfaces
// (the account-detail "Add a transaction" → Purchase fork). Two schemas:
//
//   assetResolveSchema  — mirrors Backend's SHIPPED src/lib/server/schemas/asset.ts
//                          (commit 7bcba2c) field-for-field. This is the "market
//                          security" two-step's FIRST step: identify a ticker/CUSIP
//                          not yet in the caller's selectable-assets list and resolve
//                          it against the global namespace via ?/resolveAsset, which
//                          forwards to the provider-sync worker's /asset/resolve route.
//
//   manualPurchaseSchema — mirrors the pfin.fn_create_manual_purchase RPC contract
//                          (migration 088, ad7f2a1) as an app-layer form-action schema.
//
// ⚠ EXPECTED CONTRACT, NOT YET CONFIRMED (api/CLAUDE.md "+page.svelte ahead of
//   Backend's loader" precedent — SELF-242/SELF-241 same pattern). Backend's own
//   server-side RPC-arg schema + `?/createPurchase` action were still being authored
//   at the time this file was written (their 7bcba2c commit message: "Form action +
//   RPC-arg schema deliberately NOT included ... gated on F/CTO's pricing call").
//   This schema is built directly off 088's own CONTRACT block + its RAISES list, with
//   field names chosen to match this codebase's un-prefixed convention (`transaction.ts`
//   posts `transaction_date` for the RPC's `p_trade_date`-shaped concerns, not
//   `p_transaction_date` — the server action, not the browser, adds the `p_` prefix at
//   the `.rpc()` call site; see e.g. `transactions.ts`'s `createStockSplit`). Frontend
//   flagged the exact field names + action name(s) to Backend for confirmation
//   (SendMessage, 2026-08-21) and will reconcile this file the moment their schema
//   lands — never ship this LOOSER than whatever they confirm.
//
// Discipline (api/CLAUDE.md Frontend conv): client check is UX fast-feedback only; the
// RPC's own raises (088) are the security boundary. Every numeric fence here mirrors a
// named 088 raise so the user sees the same rejection before the round trip, worded in
// this codebase's field-error idiom rather than a raw `RAISE EXCEPTION` string.

import { z } from 'zod';
import { ASSET_TYPES } from '$lib/schemas/asset-constants';
import { sanitizeCurrencyAmount, sanitizeQuantity } from '$lib/validation/numeric';
import { derivedPerUnitPrice } from '$lib/purchase-util';

// Single shared ZodError flattener — same code path as every other client schema.
export { fieldErrors } from '$lib/schemas/account';

// ── Shared field builders ────────────────────────────────────────────────────────────

const isoDate = () =>
	z
		.string()
		.trim()
		.regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD.')
		.refine((s) => {
			const d = new Date(`${s}T00:00:00Z`);
			return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
		}, 'Enter a real calendar date.');

/** Zod adapter over the client currency battery (numeric(20,4) shape) → validated `number`. */
const currencyAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeCurrencyAmount(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** Zod adapter over the client quantity battery (numeric(28,8) shape) → validated `number`. */
const quantityAmount = () =>
	z.any().transform((val, ctx) => {
		const r = sanitizeQuantity(val);
		if (!r.ok) {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: r.reason });
			return z.NEVER;
		}
		return r.value;
	});

/** 088 raise: "p_quantity must be a finite number greater than zero". */
const positiveQuantity = () =>
	quantityAmount().refine((n) => n > 0, 'Enter a quantity greater than zero.');

/** 088 raise: "p_cost_basis must be a finite number greater than zero". */
const positiveCostBasis = () =>
	currencyAmount().refine((n) => n > 0, 'Enter a total cost greater than zero.');

const nullableTrimmed = (max: number) =>
	z.preprocess(
		(v) => (v === '' || v === undefined ? null : v),
		z.string().trim().max(max).nullable()
	);

/** Nullable Sub-Cat id (BTO default, Backend-supplied — see PurchaseEntryForm). */
const subCatIdField = () =>
	z
		.preprocess(
			(v) => (v === '' || v === undefined || v === null ? null : v),
			z.coerce.number().int().positive().nullable()
		)
		.default(null);

// ── Step 1 — resolve a market security (mirrors Backend's shipped asset.ts VERBATIM) ──

const symbolField = () =>
	z.preprocess(
		(v) => (v === '' || v === undefined ? null : v),
		z
			.string()
			.trim()
			.max(20, 'Symbol is too long.')
			.regex(/^[A-Za-z0-9.\-]+$/, 'Symbol must be alphanumeric (with . or -).')
			.nullable()
	);

const cusipField = () =>
	z.preprocess(
		(v) => (v === '' || v === undefined ? null : v),
		z
			.string()
			.trim()
			.length(9, 'CUSIP must be exactly 9 characters.')
			.regex(/^[A-Za-z0-9]{9}$/, 'CUSIP must be alphanumeric.')
			.nullable()
	);

export const assetResolveSchema = z
	.object({
		symbol: symbolField(),
		cusip: cusipField(),
		asset_type: z.enum(ASSET_TYPES, { message: 'Choose an asset type.' }),
		name: nullableTrimmed(200)
	})
	.strict()
	.refine((v) => v.symbol !== null || v.cusip !== null, {
		message: 'Enter a ticker symbol or a CUSIP.',
		path: ['symbol']
	});

export type AssetResolveInput = z.infer<typeof assetResolveSchema>;

// ── Step 2 — the purchase itself (mirrors 088's CONTRACT block) ───────────────────────

/**
 * account_id is the route param, not a form field (mirrors every sibling manual-entry
 * schema on this page). BIND/MINT is a discriminated union of TWO INDEPENDENTLY
 * `.strict()` object schemas — not `.strict()` shapes merged via `.and()`/intersection,
 * which does NOT propagate the unknown-key rejection (a `.strict()` object intersected
 * with a non-strict one silently STRIPS the extra key rather than rejecting it — proven
 * out in purchase.test.ts). 088's own "both or neither" raise is the server-authoritative
 * version of the mode-exclusivity rule; this is the fast-feedback mirror, and it must
 * reject a stray field the same way the server's `.strict()` schema will.
 *
 * The COMMON fields (trade_date/quantity/cost_basis/sub_cat_id/description/note) are
 * defined ONCE as `commonFields` and spread into both branches by reference — the same
 * Zod validators, not two copies that could drift from each other.
 */
const commonFields = {
	trade_date: isoDate(),
	quantity: positiveQuantity(),
	cost_basis: positiveCostBasis(),
	sub_cat_id: subCatIdField(),
	description: nullableTrimmed(500),
	note: nullableTrimmed(500)
};

const bindSchema = z
	.object({
		mode: z.literal('bind'),
		security_id: z.coerce.number().int().positive({ message: 'Choose a security.' }),
		...commonFields
	})
	.strict();

/** 088 raises on asset_type='currency' and on an empty mint name — both mirrored here. */
const mintSchema = z
	.object({
		mode: z.literal('mint'),
		asset_type: z
			.enum(ASSET_TYPES, { message: 'Choose an asset type.' })
			.refine((t) => t !== 'currency', {
				message:
					"Cash is not a purchasable asset here — use the Cash form above. A purchase can't be recorded as currency."
			}),
		asset_name: z.string().trim().min(1, 'Name this asset.').max(200, 'Name is too long.'),
		symbol: nullableTrimmed(20),
		...commonFields
	})
	.strict();

export const manualPurchaseSchema = z
	.discriminatedUnion('mode', [bindSchema, mintSchema])
	.superRefine((v, ctx) => {
		// 088's UNCONDITIONAL zero-price fence: round(cost_basis / quantity, 4) <= 0 is
		// unreachable given both operands are already refined > 0 above, but "rounds to
		// 0.0000" (a per-unit price under 0.00005, i.e. quantity > 20000 x cost_basis) is
		// reachable and is 088's own worked example. Mirrored here so the user sees it
		// before the round trip; calls the SAME shared derivation the form's live preview
		// uses (purchase-util.ts `derivedPerUnitPrice`) rather than a second inline copy
		// of the rounding expression — 088's own "test the local, not a recomputation"
		// discipline, carried up so the preview and the validation cannot drift from
		// EACH OTHER either.
		const perUnit = derivedPerUnitPrice(v.quantity, v.cost_basis);
		if (perUnit === null || perUnit <= 0) {
			ctx.addIssue({
				code: z.ZodIssueCode.custom,
				path: ['quantity'],
				message:
					'This derives a per-unit price of 0.0000 and would record a worthless trade — re-express it with a smaller quantity or a larger total cost.'
			});
		}
	});

export type ManualPurchaseInput = z.infer<typeof manualPurchaseSchema>;

// ── Ticker-nudge (F/CTO ruling, 2026-08-21) ────────────────────────────────────────────
// "Validation should nudge a ticker-looking string typed into the personal-asset path
// toward resolve." A HEURISTIC, not a hard fence — 016's asset_type vocab and the
// symbol pattern above are the real shape rules; this only steers the personal-asset
// `asset_name` field, never blocks it (a company legitimately named "ABC Holdings LLC"
// must still submit). 1-5 uppercase letters, optional ".X" suffix (e.g. BRK.B) — the
// same shape `symbolField` above accepts, narrowed to the common ticker LENGTH so a
// longer all-caps acronym (a real personal-asset name) doesn't false-positive.
const TICKER_LIKE = /^[A-Z]{1,5}(\.[A-Z])?$/;

export function looksLikeTicker(name: string): boolean {
	return TICKER_LIKE.test(name.trim());
}
