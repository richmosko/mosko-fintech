// resolution.ts — symbol/cusip → pfin.asset.asset_id (security_id) resolution +
// GLOBAL-asset auto-register. Design §4 Step 1 + §4.3 (cusip-first fixed income).
//
// Runs on the SERVICE_ROLE transaction (withServiceRole): auto-registering a GLOBAL
// asset row (users_id = NULL) is a service_role-only write (020 grant). Under the
// authenticated tenant path, 016's asset_insert WITH CHECK (users_id = auth.uid())
// would REJECT a global insert — so resolution MUST be service_role.
//
// Resolution key = COALESCE(cusip-match, symbol-match) against GLOBAL assets
// (users_id IS NULL):
//   1. cusip present → try cusip match first (asset_global_cusip_uniq / 020).
//   2. else / miss → try symbol match (asset_global_symbol_uniq / 016).
//   3. both miss → INSERT a GLOBAL asset row ON CONFLICT DO NOTHING → re-select.
//   4. blank symbol AND blank cusip → security_id NULL (unvalued; SELF-200 §6.4).
//
// The resolved asset_id passes the 017 #7 / 019 #11 novel global-OR-matched-tenant
// fences via the "global" arm (users_id IS NULL is legal for any tenant) — Sec guard #2,
// satisfied by the shipped fences; no new mechanism here.

import type { Tx } from '../db/TenantBoundClient.js';

/** The identity inputs the resolver keys on (from a HoldingDTO / investment TransactionDTO). */
export interface ResolvableAsset {
	symbol: string | null;
	cusip: string | null;
	/** pfin.asset.asset_type (already normalized by the adapter). */
	assetType: string;
	/** Security display name (blank-symbol fallback identity). */
	name: string | null;
	currency: string;
}

const blank = (s: string | null | undefined): boolean => s === null || s === undefined || s.trim() === '';

/** A stable dedup key for a resolvable asset, cusip-first (matches the resolution order).
 *  Used to memoize resolution within one sync run (avoid N identical round-trips). */
export function assetKey(a: Pick<ResolvableAsset, 'symbol' | 'cusip'>): string | null {
	if (!blank(a.cusip)) return `cusip:${a.cusip!.trim().toUpperCase()}`;
	if (!blank(a.symbol)) return `symbol:${a.symbol!.trim().toUpperCase()}`;
	return null; // blank/blank → unvalued
}

/** Map an asset_type → the pfin.asset.pricing_source vocab (016 R-9/R-16). Auto-registered
 *  provider securities are market instruments → 'market_feed'. */
export function pricingSourceForAssetType(assetType: string): string {
	switch (assetType) {
		case 'metal':
			return 'spot_feed';
		case 'currency':
			return 'fx_feed';
		case 'real_estate':
		case 'vehicle':
		case 'collectible':
		case 'private':
			return 'manual_valuation';
		default:
			// equity/etf/fund/money_market/bond/option/future/crypto
			return 'market_feed';
	}
}

/**
 * Resolve one asset's security_id against GLOBAL rows; auto-register on miss.
 * Runs inside a withServiceRole() transaction (`tx`). Returns the asset_id, or null for
 * a blank/blank sweep (unvalued).
 */
export async function resolveSecurityId(tx: Tx, a: ResolvableAsset): Promise<number | null> {
	const cusip = blank(a.cusip) ? null : a.cusip!.trim();
	const symbol = blank(a.symbol) ? null : a.symbol!.trim();
	if (cusip === null && symbol === null) return null; // §6.4 unvalued

	// (1) cusip-first resolve.
	if (cusip !== null) {
		const hit = await tx<{ asset_id: number }[]>`
			select asset_id from pfin.asset
			where users_id is null and cusip = ${cusip}
			limit 1`;
		if (hit.length > 0) return hit[0]!.asset_id;
	}
	// (2) symbol resolve.
	if (symbol !== null) {
		const hit = await tx<{ asset_id: number }[]>`
			select asset_id from pfin.asset
			where users_id is null and symbol = ${symbol}
			limit 1`;
		if (hit.length > 0) return hit[0]!.asset_id;
	}

	// (3) miss → auto-register a GLOBAL row. Pick the ON CONFLICT arbiter by the key we
	// have: symbol present → the symbol partial-unique (016); symbol absent but cusip
	// present → the cusip partial-unique (020). A single INSERT can name only ONE arbiter.
	const pricingSource = pricingSourceForAssetType(a.assetType);
	const name = blank(a.name) ? null : a.name!.trim();

	let inserted: { asset_id: number }[];
	if (symbol !== null) {
		inserted = await tx<{ asset_id: number }[]>`
			insert into pfin.asset (users_id, asset_type, pricing_source, symbol, cusip, name, currency)
			values (null, ${a.assetType}, ${pricingSource}, ${symbol}, ${cusip}, ${name}, ${a.currency})
			on conflict (symbol) where users_id is null do nothing
			returning asset_id`;
	} else {
		inserted = await tx<{ asset_id: number }[]>`
			insert into pfin.asset (users_id, asset_type, pricing_source, symbol, cusip, name, currency)
			values (null, ${a.assetType}, ${pricingSource}, ${null}, ${cusip}, ${name}, ${a.currency})
			on conflict (cusip) where users_id is null and cusip is not null do nothing
			returning asset_id`;
	}
	if (inserted.length > 0) return inserted[0]!.asset_id;

	// (4) ON CONFLICT DO NOTHING → a concurrent/pre-existing row won; re-select it.
	if (cusip !== null) {
		const hit = await tx<{ asset_id: number }[]>`
			select asset_id from pfin.asset where users_id is null and cusip = ${cusip} limit 1`;
		if (hit.length > 0) return hit[0]!.asset_id;
	}
	if (symbol !== null) {
		const hit = await tx<{ asset_id: number }[]>`
			select asset_id from pfin.asset where users_id is null and symbol = ${symbol} limit 1`;
		if (hit.length > 0) return hit[0]!.asset_id;
	}
	// Should be unreachable (we either inserted or a row exists). Fail loud rather than
	// silently return null (which would drop the position from valuation).
	throw new Error(
		`resolveSecurityId: could not resolve or register asset (symbol=${symbol}, cusip=${cusip})`
	);
}

/**
 * Batch-resolve a list of resolvable assets into a Map keyed by assetKey(). De-dups
 * identical keys so each distinct security is resolved/registered once per sync run.
 * Runs inside a withServiceRole() transaction.
 */
export async function resolveSecurityIds(
	tx: Tx,
	assets: readonly ResolvableAsset[]
): Promise<Map<string, number>> {
	const out = new Map<string, number>();
	for (const a of assets) {
		const key = assetKey(a);
		if (key === null || out.has(key)) continue;
		const id = await resolveSecurityId(tx, a);
		if (id !== null) out.set(key, id);
	}
	return out;
}
