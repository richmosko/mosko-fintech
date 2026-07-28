// pendingSymbols.ts — the SELF-200 (§2.4.1.e) "pending-symbol classification" DERIVED VIEW.
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// "Pending classification" is COMPUTED AT READ TIME, never stored — no new table, no
// migration (F/CTO-ratified derived-view approach). A security is PENDING for the caller iff:
//   (a) the caller has EVER transacted it — any pfin.account_trans row they own with
//       security_id IS NOT NULL. "Ever-transacted", NOT net-position-filtered: a sold-to-zero
//       position still surfaces (no quantity filter), because it still needs a category.
//   (b) there is NO pfin.user_asset_category row for (auth.uid(), asset_id).
// Classifying = INSERT/UPSERT that junction row; the asset then falls out of this derived set
// automatically on the next read. Nothing here writes.
//
// RLS posture: every read is caller-RLS on the per-request anon client (INVOKER semantics,
// auth.uid()). account_trans is tenant-scoped via its account_users JOIN policy (it has no own
// users_id); user_asset_category is direct-owner; asset is global-OR-owned (022/017/016). No
// service_role, no SECURITY DEFINER, no cross-tenant FK. AC5: zero third-party security-master
// calls — this path reads only already-stored provider/manual asset metadata.
//
// DERIVATION NOTE (why app-layer set-difference, not a DB anti-join): expressing
// "transacted MINUS classified" as a single NOT EXISTS would need a view or a SECURITY INVOKER
// helper — i.e. a migration (Architect's), which the derived-view approach explicitly rules out.
// So the anti-join is done in TS over two cheap RLS-scoped selects. DISTINCT is likewise done in
// TS (supabase-js has no DISTINCT): account_trans has many rows per security, so we dedupe the
// security_ids into a Set. Both selects are bounded by the caller's OWN data.

import type { SupabaseClient } from '@supabase/supabase-js';

/** One held-but-unclassified asset — the hint shape the classify picker + badge derive from.
 *  `asset_id` is pfin.asset.asset_id (the value posted back as the classify target). `metadata`
 *  is the asset's jsonb blob (already-stored provider/manual attributes; no external fetch). */
export type PendingSymbol = {
	asset_id: number;
	symbol: string | null;
	name: string | null;
	asset_type: string;
	metadata: unknown;
};

/**
 * Pure derived-set core: DISTINCT ever-transacted security_ids MINUS classified asset_ids.
 * Extracted from the RLS-coupled query fn so the anti-join semantics — DISTINCT dedup, NULL-
 * security_id drop, set-difference — are unit-testable without a DB. Deterministic, no I/O.
 */
export function computePendingIds(
	transacted: ReadonlyArray<{ security_id: number | null }>,
	classified: ReadonlyArray<{ asset_id: number }>
): number[] {
	const transactedIds = [
		...new Set(transacted.map((r) => r.security_id).filter((id): id is number => id !== null))
	];
	const classifiedSet = new Set(classified.map((r) => r.asset_id));
	return transactedIds.filter((id) => !classifiedSet.has(id));
}

/** Result of loadPendingSymbols. `ok:false` = a READ ERROR occurred (distinct from a genuinely
 *  empty `pending:[]` with `ok:true`) — the classify page uses this to show a retriable error
 *  instead of a FALSE "all caught up" empty state (SELF-200 Gap 1 / no-silent-staleness value). */
export type PendingSymbolsResult = { pending: PendingSymbol[]; ok: boolean };

/**
 * The pending asset_ids for the caller — the derived-set core shared by the full list and the
 * lean badge count so the two can never drift on "what counts as pending". Two RLS-scoped selects:
 *   (1) security_ids the caller has ever transacted (any account_trans, security_id NOT NULL,
 *       NO quantity filter — ever-transacted; DISTINCT applied in computePendingIds).
 *   (2) asset_ids the caller has already classified (own user_asset_category rows).
 * Returns { ids: (1) minus (2), ok }. `ok:false` on a read error (logged) — callers decide whether
 * to fail-soft (badge → 0) or surface a retriable error (page). Never throws.
 */
async function pendingAssetIds(supabase: SupabaseClient): Promise<{ ids: number[]; ok: boolean }> {
	// (1) Ever-transacted securities. RLS (account_users JOIN) auto-scopes to the caller's own
	// accounts; no explicit users_id filter needed (account_trans has none). No quantity filter.
	const { data: txnRows, error: tErr } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('security_id')
		.not('security_id', 'is', null);
	if (tErr) {
		console.error('[pendingSymbols] transacted-securities read failed:', tErr.message);
		return { ids: [], ok: false };
	}

	// (2) Already-classified assets for this caller (direct-owner RLS). One row per (user, asset).
	const { data: classifiedRows, error: cErr } = await supabase
		.schema('pfin')
		.from('user_asset_category')
		.select('asset_id');
	if (cErr) {
		console.error('[pendingSymbols] classified-assets read failed:', cErr.message);
		return { ids: [], ok: false };
	}

	return {
		ids: computePendingIds(
			(txnRows ?? []) as Array<{ security_id: number | null }>,
			(classifiedRows ?? []) as Array<{ asset_id: number }>
		),
		ok: true
	};
}

/**
 * Lean pending count for the header badge. Two narrow id-only RLS-scoped selects (`security_id`
 * for set (1), `asset_id` for set (2)) + a JS set-difference — NO asset-detail/metadata fetch
 * (that is list-view only). Safe to run in +layout.server.ts on every navigation at V1
 * (single-user/family) scale; bounded by the caller's own data.
 *
 * FAIL-SOFT-TO-0 (deliberate, SELF-200 Gap 1): on a read error the badge returns 0, NOT an error —
 * a per-navigation layout `load` that threw would break EVERY page. The badge must never be the
 * thing that MASKS a page-level read failure, so the classify PAGE path (loadPendingSymbols) does
 * its own error-vs-empty distinction and shows a retriable error there. A badge of 0 on a transient
 * read error is acceptable (understates, self-heals next navigation); a false page "all caught up"
 * is not — hence the split.
 *
 * DEFERRED UPGRADE PATH (documented, NOT needed at V1 scale): the app-layer anti-join here is a
 * deliberate consequence of the no-migration derived-view approach. If the caller's own data ever
 * grows enough that the two-select + JS-diff round-trip matters, the clean single-round-trip
 * replacement is a SECURITY INVOKER read-composition helper (Lock 11 pattern, à la fn_compute_nav)
 * that does the `NOT EXISTS` (transacted MINUS classified) DB-side under caller-RLS — Architect
 * authors the migration; this function becomes a one-line `.rpc()`. Explicitly out of scope for V1.
 */
export async function countPendingSymbols(supabase: SupabaseClient): Promise<number> {
	const { ids, ok } = await pendingAssetIds(supabase);
	return ok ? ids.length : 0;
}

/**
 * The full pending list for the classify surface: held-but-unclassified assets with the hint
 * fields (symbol/name/asset_type/metadata). Adds a third RLS-scoped read (asset labels, global-
 * OR-owned) on top of the derived id-set. Sorted by symbol then name.
 *
 * Returns { pending, ok }: `ok:false` signals a READ ERROR at ANY of the three reads — the page
 * MUST distinguish this from a genuinely-empty `{ pending: [], ok: true }` and show a retriable
 * error rather than the "all caught up" empty state (Gap 1). Never throws.
 */
export async function loadPendingSymbols(supabase: SupabaseClient): Promise<PendingSymbolsResult> {
	const { ids, ok } = await pendingAssetIds(supabase);
	if (!ok) return { pending: [], ok: false };
	if (ids.length === 0) return { pending: [], ok: true };

	// asset SELECT is RLS global-OR-owned; every transacted asset is by construction visible to
	// the caller (a global market security or their own asset), so no id drops out here.
	const { data: assets, error: aErr } = await supabase
		.schema('pfin')
		.from('asset')
		.select('asset_id, symbol, name, asset_type, metadata')
		.in('asset_id', ids)
		.order('symbol', { ascending: true, nullsFirst: false })
		.order('name', { ascending: true });
	if (aErr) {
		console.error('[pendingSymbols] asset-detail read failed:', aErr.message);
		return { pending: [], ok: false };
	}

	return {
		pending: ((assets ?? []) as Array<Record<string, unknown>>).map((a) => ({
			asset_id: a.asset_id as number,
			symbol: (a.symbol as string | null) ?? null,
			name: (a.name as string | null) ?? null,
			asset_type: a.asset_type as string,
			metadata: a.metadata ?? null
		})),
		ok: true
	};
}
