// purchase-util.ts — browser-side helpers + view types for the SELF-325 manual-purchase
// surface (account-detail "Add a transaction" → Purchase fork). Non-server: ships to the
// browser. Mirrors transaction-util.ts's role for the cash-entry surfaces — one home for
// display formatting + derived values so the form component and its schema mirror
// (schemas/purchase.ts) can't drift on the SAME derivation.

/**
 * A caller-selectable asset (own + global), as shaped by Backend's `selectableAssets.ts`
 * `SelectableAsset` (server-side type — NOT imported here; this is the browser-safe
 * mirror load() must serialize into). Kept field-for-field identical on purpose.
 */
export type SelectableAssetOption = {
	asset_id: number;
	asset_type: string;
	symbol: string | null;
	cusip: string | null;
	name: string | null;
	currency: string;
	is_global: boolean;
};

/** "SYMBOL — Name (yours)" / "SYMBOL — Name" / whichever of symbol|name exists / a stable
 *  id fallback. Mirrors transaction-util.ts's `securityLabel`, extended with the
 *  global-vs-owned distinction the purchase picker needs to disambiguate two rows that
 *  could otherwise share a symbol (a global ticker vs. the caller's own same-named
 *  personal asset are DIFFERENT asset_ids). */
export function selectableAssetLabel(a: SelectableAssetOption): string {
	const ident = a.symbol ?? a.cusip ?? a.name ?? `Asset #${a.asset_id}`;
	const withName = a.symbol && a.name ? `${ident} — ${a.name}` : ident;
	return a.is_global ? withName : `${withName} (yours)`;
}

/**
 * The derived per-unit price 088 computes and fences: `round(cost_basis / quantity, 4)`.
 * ONE function so the schema's `.superRefine` (fast-feedback validation) and the form's
 * LIVE preview render the exact same number — 088's own discipline ("test the local, not
 * a recomputation of the same expression") carried up a layer so the UI's preview and the
 * UI's validation cannot themselves drift from each other. Returns `null` when either
 * input isn't yet a usable positive number (nothing to preview yet).
 */
export function derivedPerUnitPrice(quantity: number, costBasis: number): number | null {
	if (!(quantity > 0) || !(costBasis > 0) || !Number.isFinite(quantity) || !Number.isFinite(costBasis)) {
		return null;
	}
	return Math.round((costBasis / quantity) * 10_000) / 10_000;
}

/** Fixed 4-decimal display, matching numeric(20,4) — e.g. for the per-unit price preview. */
export function formatPrice(n: number): string {
	return n.toFixed(4);
}

/**
 * asset_type -> friendly label for the personal-asset mint picker. Covers the FULL
 * asset-constants.ts vocabulary (016's CHECK) minus none — 'currency' stays in the map
 * (labeled, never hidden) even though the purchase form's mint schema refuses selecting
 * it; the refusal needs a real label to name in its error, not a missing map entry.
 * Copy is a placeholder pending UX/PM sign-off — flagged, not blocking (V1 precedent:
 * every other *_TYPES label map in this codebase ships a first-pass label and takes
 * copy review as a follow-up, e.g. account-display.ts's CLOSURE_REASON_LABELS).
 */
const ASSET_TYPE_LABELS: Record<string, string> = {
	equity: 'Equity',
	etf: 'ETF',
	fund: 'Fund',
	money_market: 'Money market',
	bond: 'Bond',
	future: 'Future',
	option: 'Option',
	crypto: 'Crypto',
	real_estate: 'Real estate',
	vehicle: 'Vehicle',
	metal: 'Metal',
	collectible: 'Collectible',
	currency: 'Currency',
	private: 'Private'
};

export function assetTypeLabel(t: string): string {
	return ASSET_TYPE_LABELS[t] ?? t;
}
