// selectableAssets.ts — SELF-325 user-pickable pfin.asset reads (manual purchase-path). Backend-
// owned server source.
//
// "Selectable" = own assets + global (users_id IS NULL) — exactly the 016 asset_select RLS
// posture (`using (users_id is null or users_id = auth.uid())`). Reads go through the per-request
// anon client under the caller's RLS context (SECURITY INVOKER read-composition; never
// service_role — RT-26 / Lock 11 confinement, api/CLAUDE.md). A cross-tenant per-user row is
// structurally invisible; there is no hand-written WHERE doing the tenant scoping, RLS is.
//
// Feeds the purchase-path security picker: search/browse the resolvable universe BEFORE calling
// the worker's /asset/resolve leg (which resolves-or-mints against the GLOBAL namespace only —
// this module surfaces what a caller can already see, not what /asset/resolve would create), and
// confirm a resolved asset_id's identity for display after resolve.

import type { SupabaseClient } from '@supabase/supabase-js';

/** One user-pickable asset row. `is_global` is derived (users_id === null) — never exposed as the
 *  raw users_id itself (no reason for the browser to see another row's tenant anchor, and every
 *  visible row is either global or the caller's own). */
export type SelectableAsset = {
	asset_id: number;
	asset_type: string;
	pricing_source: string;
	symbol: string | null;
	cusip: string | null;
	name: string | null;
	currency: string;
	is_global: boolean;
};

const ASSET_COLUMNS = 'asset_id, users_id, asset_type, pricing_source, symbol, cusip, name, currency';

type AssetRow = {
	asset_id: number;
	users_id: string | null;
	asset_type: string;
	pricing_source: string;
	symbol: string | null;
	cusip: string | null;
	name: string | null;
	currency: string;
};

const toSelectableAsset = (r: AssetRow): SelectableAsset => ({
	asset_id: r.asset_id,
	asset_type: r.asset_type,
	pricing_source: r.pricing_source,
	symbol: r.symbol,
	cusip: r.cusip,
	name: r.name,
	currency: r.currency,
	is_global: r.users_id === null
});

export interface LoadSelectableAssetsOptions {
	/** Restrict to one 016 asset_type (e.g. narrow a picker to market-priced instruments). */
	assetType?: string;
	/** Case-insensitive substring match against symbol OR name (a ticker/company-name search
	 *  box). Empty/whitespace-only is treated as "no filter". */
	search?: string;
	/** Cap the result set (a search-as-you-type picker; not a full-registry browse). Defaults to
	 *  50 — generous for an autocomplete list, bounded so a broad/blank search can't return the
	 *  whole global registry in one round trip. */
	limit?: number;
}

/**
 * The caller's pickable assets — own + global, RLS-scoped. Returns `{ assets, error }` so the
 * page can distinguish a read FAILURE from a true empty (mirrors connectionState.ts's
 * loadConnectionStates convention). Fail-soft: never throws.
 */
export async function loadSelectableAssets(
	supabase: SupabaseClient,
	opts: LoadSelectableAssetsOptions = {}
): Promise<{ assets: SelectableAsset[]; error: boolean }> {
	let query = supabase.schema('pfin').from('asset').select(ASSET_COLUMNS);

	if (opts.assetType) query = query.eq('asset_type', opts.assetType);

	const search = opts.search?.trim();
	if (search) {
		// PostgREST or-filter syntax; escape the two chars that are structurally significant to
		// it (comma separates conditions, parens close the ilike value) so a search string
		// containing them can't be mis-parsed into an unintended filter.
		const escaped = search.replace(/[,()]/g, '');
		query = query.or(`symbol.ilike.%${escaped}%,name.ilike.%${escaped}%`);
	}

	const { data, error } = await query
		.order('symbol', { ascending: true, nullsFirst: false })
		.order('name', { ascending: true, nullsFirst: false })
		.limit(opts.limit ?? 50);

	if (error) {
		console.error('[selectableAssets] loadSelectableAssets failed:', error.message);
		return { assets: [], error: true };
	}
	return { assets: ((data ?? []) as AssetRow[]).map(toSelectableAsset), error: false };
}

/**
 * Read ONE selectable asset by id — RLS-scoped (global-or-own; a cross-tenant per-user asset_id
 * is invisible, returns null the same as not-found — no existence leak). Used to confirm the
 * /asset/resolve leg's returned asset_id before the purchase RPC call, and to render the picked
 * security's identity back to the user.
 */
export async function loadSelectableAssetById(
	supabase: SupabaseClient,
	assetId: number
): Promise<SelectableAsset | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.from('asset')
		.select(ASSET_COLUMNS)
		.eq('asset_id', assetId)
		.maybeSingle();

	if (error) {
		console.error('[selectableAssets] loadSelectableAssetById failed:', error.message);
		return null;
	}
	if (!data) return null;
	return toSelectableAsset(data as AssetRow);
}
