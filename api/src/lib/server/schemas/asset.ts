// asset.ts — server-side Zod schema for the SELF-325 asset-resolve boundary (manual
// purchase-path, Case 3 / public tickers). Backend-owned server source.
//
// SOURCE OF TRUTH: Frontend mirrors this client-side (Lock 14) and must never ship a looser
// schema. `.strict()` is the mass-assignment fence (Lock 14 mod #1). Pattern/length constraints
// on symbol/cusip + the asset_type enum are the namespace-pollution boundary the Architect
// design calls a DESIGN CONDITION, not polish (temp/architect-purchase-path-addendum.md §2.3 —
// "a user-triggered write into the all-tenants-readable global namespace"). This is the SECOND
// of the "two boundaries" the addendum names (§7): the worker's own /asset/resolve Zod schema
// (workers/provider-sync/src/http/admissionServer.ts) is the first, structurally identical,
// defense-in-depth at the internal-network hop — both independently enforce the same
// DDL-adjacent shape rather than trusting the other boundary to have already done so.
//
// ASSET_TYPE IS THE NARROW RESOLVABLE_ASSET_TYPES SET, NOT THE FULL 016 VOCAB (⚠ CORRECTED
// 2026-08-21 — Architect ruling, team-lead-confirmed; an earlier version of this schema used the
// full 14-value enum, which was WRONG: /asset/resolve MINTS a durable GLOBAL row, so admitting a
// `manual_valuation`-priced type here produces a permanently unpriceable, unrepairable row — see
// RESOLVABLE_ASSET_TYPES's own comment in asset-constants.ts for the full reasoning). Rejected
// values get a routing message pointing at the correct path (088's MINT mode for personal assets,
// the cash-entry form for currency) rather than a bare "invalid" — see the superRefine below.
//
// CURRENCY IS NOT A FORM FIELD (mirrors schemas/account.ts's manualAccountCreateSchema
// precedent — "currency is NOT threaded — it defaults to 'USD'"). The purchase-path form does
// not collect a currency; the action supplies the literal 'USD' when building the worker
// payload. An optional per-security currency field can be added additively later if a non-USD
// instrument is ever needed (out of SELF-325's ratified scope).

import { z } from 'zod';
import { ASSET_TYPES, RESOLVABLE_ASSET_TYPES } from '$lib/schemas/asset-constants';
export { fieldErrors } from '$lib/server/schemas/account'; // single shared ZodError flattener

const PERSONAL_ASSET_ROUTING_MESSAGE =
	'Personal assets (real estate, vehicles, collectibles, private holdings) are recorded directly on the purchase form, not looked up in the security registry.';
const CURRENCY_ROUTING_MESSAGE =
	'Cash is not purchasable through the security lookup — record it from the cash-entry form.';

const nullableTrimmed = (max: number) =>
	z.preprocess((v) => (v === '' || v === undefined ? null : v), z.string().trim().max(max).nullable());

/** Ticker-shaped symbol: alphanumeric plus '.' / '-' (e.g. BRK.B), 1..20 chars. Matches the
 *  worker's own /asset/resolve boundary constraint. */
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

/** Standard CUSIP: exactly 9 alphanumeric characters. */
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

/**
 * The "identify the security" step of the purchase-path two-step form action (resolve → RPC).
 * At least one of symbol/cusip is required — a blank/blank submission has no identity to bind a
 * purchase to (mirrors resolveSecurityId's own blank/blank→unvalued contract being unreachable
 * via this boundary; unlike an ingest sweep, a user-initiated purchase always names a security).
 */
export const assetResolveSchema = z
	.object({
		symbol: symbolField(),
		cusip: cusipField(),
		// z.enum(ASSET_TYPES) here (not RESOLVABLE_ASSET_TYPES) so an out-of-vocabulary value
		// (garbage input, not one of the 14 016 types at all) still gets Zod's own "invalid enum
		// value" — the superRefine below is what narrows to the resolvable 9 and supplies the
		// differentiated routing message for the other 5.
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
