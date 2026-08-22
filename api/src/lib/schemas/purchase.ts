// purchase.ts — CLIENT-SIDE Zod mirror of the SELF-325 manual-purchase surfaces
// (the account-detail "Add a transaction" → Purchase fork). Two schemas:
//
//   assetResolveSchema   — mirrors Backend's server-side src/lib/server/schemas/asset.ts
//                          (confirmed via SendMessage 2026-08-21, latest at commit
//                          a9ba25e) field-for-field. This is the "market security"
//                          two-step's FIRST step: POST JSON to `/api/asset/resolve`
//                          (a fetch endpoint, NOT a form action — see
//                          PurchaseEntryForm.svelte's resolve handler) to identify a
//                          ticker/CUSIP not yet in the caller's selectable-assets list.
//
//   createPurchaseSchema — mirrors Backend's server-side
//                          src/lib/server/schemas/purchase.ts (createPurchaseSchema,
//                          same commit) field-for-field — itself the app-layer mirror of
//                          the pfin.fn_create_manual_purchase RPC contract (migration
//                          088). Posts to the EXISTING accounts/[account_id] route's
//                          `?/createPurchase` action (not a new route).
//
// CONFIRMED CONTRACT (Backend, SendMessage 2026-08-21, superseding this file's earlier
// EXPECTED-CONTRACT draft built ahead of their schema): field names are UN-PREFIXED
// (`trade_date`/`quantity`/`cost_basis`/... — the server action adds the RPC's `p_`
// prefix at the `.rpc()` call site, this file never does). Two INDEPENDENTLY `.strict()`
// discriminated-union branches (confirmed — Backend's own server schema uses the exact
// same shape this file already chose, for the exact same reason: `.strict()` merged via
// `.and()` silently strips an unknown key instead of rejecting it).
//
// ⚠ ASSET-TYPE VOCABULARY SPLIT (F/CTO + Architect ruling, 2026-08-21, relayed by
//   team-lead — HOLD until this landed, now resolved): the RESOLVE step (this schema's
//   `assetResolveSchema`) admits only `RESOLVABLE_ASSET_TYPES` — the 9 feed-priceable
//   types. MINT mode (`createPurchaseSchema`'s mint branch) admits `MINT_ASSET_TYPES` —
//   the full 13 (14 minus currency), INCLUDING the 4 personal types (real_estate/
//   vehicle/collectible/private) that must NEVER reach resolve. Routing a personal asset
//   through resolve would mint a permanently unpriceable, unrepairable GLOBAL row (019's
//   eod_price_insert requires ownership; 020 grants no UPDATE) — see
//   RESOLVABLE_ASSET_TYPES's own comment in asset-constants.ts for the full reasoning.
//   This is a STRUCTURAL boundary, not a labeling one: the picker driving the resolve
//   step's `asset_type` field must offer ONLY `RESOLVABLE_ASSET_TYPES` — see
//   PurchaseEntryForm.svelte's `resolveAssetTypeOptions` vs `mintAssetTypeOptions`.
//
// Discipline (api/CLAUDE.md Frontend conv): client check is UX fast-feedback only; the
// server's own Zod schema + the RPC's own raises (088) are the security boundary. The
// zero-price-rounds-to-0.0000 ratio check below mirrors the RPC's own raise directly
// (088's DB-level fence) — Backend's server Zod schema does NOT re-check it client-side
// either (that check has no Zod-layer counterpart on either side; it is the DB's alone),
// so this is genuinely EXTRA fast-feedback, not a mirror of a Zod rule.

import { z } from 'zod';
import { ASSET_TYPES, RESOLVABLE_ASSET_TYPES, MINT_ASSET_TYPES } from '$lib/schemas/asset-constants';
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

/** 088 raise: "p_cost_basis must be a finite number greater than zero". Message copied
 *  VERBATIM from Backend's server schema (positiveCostBasis) — mirror discipline. */
const positiveCostBasis = () =>
	currencyAmount().refine((n) => n > 0, 'Enter a value greater than zero.');

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

// ── Step 1 — resolve a market security (mirrors Backend's server schemas/asset.ts VERBATIM,
// including its 2026-08-21 narrowing correction) ────────────────────────────────────────

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

/** Copied VERBATIM from Backend's server schema — the two differentiated routing
 *  messages for an asset_type that IS one of the full 14 016 types but is NOT one of
 *  the 9 resolvable ones (personal types + currency). A picker offering only
 *  `RESOLVABLE_ASSET_TYPES` makes these two messages structurally unreachable through
 *  normal use — kept anyway as the same defense-in-depth reasoning Backend's own
 *  schema states (the route is reachable from a stale tab / second window). */
const PERSONAL_ASSET_ROUTING_MESSAGE =
	'Personal assets (real estate, vehicles, collectibles, private holdings) are recorded directly on the purchase form, not looked up in the security registry.';
const CURRENCY_ROUTING_MESSAGE =
	'Cash is not purchasable through the security lookup — record it from the cash-entry form.';

export const assetResolveSchema = z
	.object({
		symbol: symbolField(),
		cusip: cusipField(),
		// z.enum(ASSET_TYPES) here (not RESOLVABLE_ASSET_TYPES) so a genuinely
		// out-of-vocabulary value gets Zod's own "invalid enum value" — the superRefine
		// below is what narrows to the resolvable 9 with a differentiated routing
		// message for the other 5. Mirrors Backend's server schema exactly.
		asset_type: z.enum(ASSET_TYPES),
		name: nullableTrimmed(200)
	})
	.strict()
	.refine((v) => v.symbol !== null || v.cusip !== null, {
		message: 'Enter a ticker symbol or a CUSIP.',
		path: ['symbol']
	})
	.superRefine((v, ctx) => {
		if ((RESOLVABLE_ASSET_TYPES as readonly string[]).includes(v.asset_type)) return;
		const message = v.asset_type === 'currency' ? CURRENCY_ROUTING_MESSAGE : PERSONAL_ASSET_ROUTING_MESSAGE;
		ctx.addIssue({ code: z.ZodIssueCode.custom, message, path: ['asset_type'] });
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

/** MINT's asset_type vocabulary is `MINT_ASSET_TYPES` (13 = 14 minus currency) — currency
 *  is structurally EXCLUDED from the enum itself (matches Backend's server schema
 *  exactly), not rejected by a separate `.refine()` after the fact. 088's own empty-name
 *  raise is mirrored by the `.min(1, ...)` below. */
const mintSchema = z
	.object({
		mode: z.literal('mint'),
		asset_type: z.enum(MINT_ASSET_TYPES, { message: 'Choose an asset type.' }),
		asset_name: z.string().trim().min(1, 'Name is required.').max(200, 'Name is too long.'),
		symbol: nullableTrimmed(20),
		...commonFields
	})
	.strict();

export const createPurchaseSchema = z
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

export type CreatePurchaseInput = z.infer<typeof createPurchaseSchema>;

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
