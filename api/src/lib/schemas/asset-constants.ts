// asset-constants.ts — browser-safe shared value-set for the SELF-325 asset-resolve surface.
//
// NON-server module (imports nothing server-only) so BOTH sides import the SAME canonical
// value-set: the server schema (src/lib/server/schemas/asset.ts, the .strict() + Lock 14
// mass-assignment boundary) AND Frontend's client-side UX mirror. Anti-drift point per the
// account-constants.ts precedent — the schemas stay per-role, but the enum can never diverge
// because there is only one definition.
//
// Value-set is copied VERBATIM from the DB CHECK constraint on pfin.asset.asset_type (016) —
// the DB CHECK is the authoritative backstop. If 016's CHECK changes, update here (Backend-
// sourced; the values track the migration, not UI preference). This is the FULL 14-value
// vocabulary — the right constant for MINT mode (any owned asset type except currency) and for
// Frontend's client mirror.
//
// ⚠ CORRECTED 2026-08-21 (Architect ruling, team-lead-confirmed): an EARLIER version of this
// comment said narrowing the /asset/resolve boundary to a market-priced subset was "a Frontend
// UX call... not a server-validation one." That was WRONG and has been retracted — see
// RESOLVABLE_ASSET_TYPES below. /asset/resolve is a correctness boundary (it MINTS a durable
// GLOBAL row), not a presentation one; a UI-only narrowing is not a control (the route is
// reachable from a stale tab / second window / anyone holding the shared secret — the same
// argument api/src/routes/accounts/[account_id]/+page.server.ts's isClosedAccountWrite comment
// already makes: "THE UI GATING IS NOT WHAT MAKES THIS SAFE").

/** asset_type — VERBATIM from 016 pfin.asset CHECK. */
export const ASSET_TYPES = [
	'equity',
	'etf',
	'fund',
	'money_market',
	'bond',
	'future',
	'option',
	'crypto',
	'real_estate',
	'vehicle',
	'metal',
	'collectible',
	'currency',
	'private'
] as const;
export type AssetType = (typeof ASSET_TYPES)[number];

/**
 * MINT-mode asset_type vocabulary for `pfin.fn_create_manual_purchase` (SELF-325 / 088) —
 * `ASSET_TYPES` minus `'currency'`, the RPC's one explicit rejection ("016's CHECK is the single
 * authority for the asset_type vocabulary; the one explicit rejection is 'currency': cash is
 * amount-carried, not instrument-carried, and its classification already routes through the
 * global currency-asset" — 088's own `comment on`). Hand-listed (not filtered at runtime) so this
 * stays a plain literal tuple for `z.enum`; asset-constants.test.ts asserts it never drifts from
 * `ASSET_TYPES`.
 */
export const MINT_ASSET_TYPES = [
	'equity',
	'etf',
	'fund',
	'money_market',
	'bond',
	'future',
	'option',
	'crypto',
	'real_estate',
	'vehicle',
	'metal',
	'collectible',
	'private'
] as const;
export type MintAssetType = (typeof MINT_ASSET_TYPES)[number];

/**
 * The GLOBALLY-RESOLVABLE asset_type subset for the worker's `/asset/resolve` boundary (SELF-325)
 * — the 9 feed-priceable types, hand-enumerated (NOT derived by filtering
 * `pricingSourceForAssetType`, deliberately: that would couple this route's admission policy to a
 * mapping owned by the provider-sync ingest path, so an edit there would silently change what this
 * route admits — Architect ruling, 2026-08-21).
 *
 * WHY THE OTHER 5 ARE EXCLUDED (the reason, not a restatement of the mechanism):
 * `pricingSourceForAssetType` (workers/provider-sync/src/ingest/resolution.ts) maps
 * `real_estate` / `vehicle` / `collectible` / `private` to `'manual_valuation'`. A GLOBAL asset
 * (`users_id IS NULL`) with that pricing_source can NEVER be priced by anyone: `019`'s
 * `eod_price_insert` admits `manual_valuation` only on an asset the caller OWNS, and a global row
 * is owned by nobody; the worker's `service_role` write path only ever writes `provider_implied`,
 * derived from a PROVIDER-LINKED account's holdings — and no provider reports houses. Minting one
 * therefore produces a PERMANENTLY UNPRICEABLE, UNREPAIRABLE row: it occupies a
 * `unique(symbol) WHERE users_id IS NULL` slot in an all-tenants-readable namespace, and `020`
 * grants the worker no `UPDATE` to ever fix it. `currency` is excluded for a different reason —
 * cash is amount-carried, not instrument-carried, and `088`'s MINT mode already rejects it; admitting
 * it here would put the two surfaces in disagreement.
 *
 * THE RIGHT HOME FOR ALL 5: `pfin.fn_create_manual_purchase`'s MINT mode (088) — caller-OWNED,
 * therefore priceable (its companion `manual_valuation` price is written in the same transaction).
 * Routing a personal asset through `/asset/resolve` instead doesn't just pollute the global
 * namespace, it loses the user their valuation entirely.
 *
 * Widening this set later is a one-line change; un-minting a global row is not — see the one-way
 * door this constant exists to close.
 */
export const RESOLVABLE_ASSET_TYPES = [
	'equity',
	'etf',
	'fund',
	'money_market',
	'bond',
	'future',
	'option',
	'crypto',
	'metal'
] as const;
export type ResolvableAssetType = (typeof RESOLVABLE_ASSET_TYPES)[number];
