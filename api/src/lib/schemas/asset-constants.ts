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
// vocabulary — narrowing to a "market-priced" subset for the purchase-path picker's presented
// options is a Frontend UX call over this same contract, not a server-validation one (the
// worker's /asset/resolve route Zod schema mirrors this same full set for the identical reason).

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
