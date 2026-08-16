// pendingSymbols.ts — the SELF-200 (§2.4.1.e) "pending-symbol classification" DERIVED VIEW,
// generalized at SELF-235 (§2.2.1.b) to the FULL ever-transacted symbols list carrying its
// current classification. Backend-owned server surface (ARCH §4.1 allowlist).
//
// "Pending classification" is COMPUTED AT READ TIME, never stored — no new table, no
// migration (F/CTO-ratified derived-view approach). A security is PENDING for the caller iff:
//   (a) the caller has EVER transacted it — any pfin.account_trans row they own with
//       security_id IS NOT NULL. "Ever-transacted", NOT net-position-filtered: a sold-to-zero
//       position still surfaces (no quantity filter), because it still needs a category.
//   (b) there is NO pfin.user_asset_category row for (auth.uid(), asset_id).
// Classifying/reassigning = UPSERT of that junction row; a formerly-pending asset falls out of
// the PENDING subset (but stays IN the full symbols list, now carrying its classification) on
// the next read. Nothing here writes.
//
// SELF-235 loadSymbols() is the SAME ever-transacted derivation (a) generalized to ALL ids, not
// just the (a) MINUS (b) pending subset — one derivation, two read shapes, so the pending badge
// and the full list can never drift on "what counts as pending". See readTransactedSecurityIds.
//
// RLS posture: every read is caller-RLS on the per-request anon client (INVOKER semantics,
// auth.uid()). account_trans is tenant-scoped via its account_users JOIN policy (it has no own
// users_id); user_asset_category is direct-owner; user_taxonomy is direct-owner; asset is
// global-OR-owned (022/017/016). No service_role, no SECURITY DEFINER, no cross-tenant FK. AC5:
// zero third-party security-master calls — this path reads only already-stored provider/manual
// asset metadata.
//
// DERIVATION NOTE (why app-layer set-difference/merge, not a DB anti-join or LEFT JOIN):
// expressing "transacted MINUS classified" (or a LEFT JOIN of transacted to its classification)
// as one query would need a view or a SECURITY INVOKER helper — i.e. a migration (Architect's),
// which the derived-view approach explicitly rules out. So the merge is done in TS over cheap
// RLS-scoped selects. DISTINCT is likewise done in TS (supabase-js has no DISTINCT):
// account_trans has many rows per security, so we dedupe the security_ids into a Set. All
// selects are bounded by the caller's OWN data.

import type { SupabaseClient } from '@supabase/supabase-js';
import { subCatLabel } from './taxonomy';

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

/** SELF-235 AC1: the caller's CURRENT (Cat, Sub-Cat) for an asset, read via user_asset_category
 *  → user_taxonomy — `null` = unclassified (the pending state; AC5 badge trigger). `sub_cat_id`
 *  is the value the reassignment picker preselects and posts back on Save. */
export type SymbolClassification = { sub_cat_id: number; cat: string; sub_cat: string } | null;

/** One ever-transacted asset for the SELF-235 full symbols list — PendingSymbol's hint fields
 *  plus its current classification (or `null` = pending). Deliberately NOT a PendingSymbol
 *  subtype/union: the two lists serve different surfaces (bulk pending queue vs. full
 *  holding-to-bucket list) that happen to share hint-field shape by convention, not contract. */
export type SymbolListItem = {
	asset_id: number;
	symbol: string | null;
	name: string | null;
	asset_type: string;
	metadata: unknown;
	classification: SymbolClassification;
};

/** Result of loadSymbols. `ok:false` = a READ ERROR (Gap-1 shape, same as PendingSymbolsResult) —
 *  distinct from a genuinely empty `symbols:[]` (the caller has never transacted anything). */
export type SymbolsResult = { symbols: SymbolListItem[]; ok: boolean };

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
 * Ever-transacted security_ids for the caller — RLS (account_users JOIN) auto-scopes to the
 * caller's own accounts; no explicit users_id filter needed (account_trans has none). No
 * quantity filter (ever-transacted, not net-position). DISTINCT applied here (supabase-js has
 * no DISTINCT). Shared by pendingAssetIds (SELF-200) and loadSymbols (SELF-235) so the two
 * "which securities does this caller hold" derivations can never drift apart.
 */
async function readTransactedSecurityIds(
	supabase: SupabaseClient
): Promise<{ ids: number[]; ok: boolean }> {
	const { data: txnRows, error: tErr } = await supabase
		.schema('pfin')
		.from('account_trans')
		.select('security_id')
		.not('security_id', 'is', null);
	if (tErr) {
		console.error('[pendingSymbols] transacted-securities read failed:', tErr.message);
		return { ids: [], ok: false };
	}
	return {
		ids: [
			...new Set(
				((txnRows ?? []) as Array<{ security_id: number | null }>)
					.map((r) => r.security_id)
					.filter((id): id is number => id !== null)
			)
		],
		ok: true
	};
}

/**
 * The pending asset_ids for the caller — the derived-set core shared by the full list and the
 * lean badge count so the two can never drift on "what counts as pending". Two RLS-scoped selects:
 *   (1) security_ids the caller has ever transacted (readTransactedSecurityIds).
 *   (2) asset_ids the caller has already classified (own user_asset_category rows).
 * Returns { ids: (1) minus (2), ok }. `ok:false` on a read error (logged) — callers decide whether
 * to fail-soft (badge → 0) or surface a retriable error (page). Never throws.
 */
async function pendingAssetIds(supabase: SupabaseClient): Promise<{ ids: number[]; ok: boolean }> {
	// (1) Ever-transacted securities.
	const { ids: transactedIds, ok: tOk } = await readTransactedSecurityIds(supabase);
	if (!tOk) return { ids: [], ok: false };

	// (2) Already-classified assets for this caller (direct-owner RLS). One row per (user, asset).
	const { data: classifiedRows, error: cErr } = await supabase
		.schema('pfin')
		.from('user_asset_category')
		.select('asset_id');
	if (cErr) {
		console.error('[pendingSymbols] classified-assets read failed:', cErr.message);
		return { ids: [], ok: false };
	}

	// computePendingIds re-dedupes (idempotent — transactedIds is already a Set) but stays the
	// ONE tested anti-join implementation (pendingSymbols.test.ts) rather than a second inline diff.
	return {
		ids: computePendingIds(
			transactedIds.map((security_id) => ({ security_id })),
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

/**
 * SELF-235 (§2.2.1.b) AC1: the FULL ever-transacted symbols list for the caller, each row
 * carrying its current classification (`null` = pending, the AC5 badge state). Generalizes
 * loadPendingSymbols from the (a) MINUS (b) pending subset to ALL of (a) — same
 * readTransactedSecurityIds derivation, so the two can never disagree on "what the caller holds".
 *
 * Four RLS-scoped reads: (1) transacted security_ids (shared helper), (2) the caller's
 * user_asset_category rows with an embedded user_taxonomy(cat, sub_cat) join — supabase-js has
 * no server-side LEFT JOIN across two independently-RLS'd tables, so "unclassified" is expressed
 * as "absent from this read" and merged in TS (the map lookup below), not as a SQL LEFT JOIN
 * producing NULL columns, (3) asset labels for every transacted id (not just the pending subset).
 * sub_cat_id is NOT NULL on user_asset_category (022), so a returned junction row's embedded
 * user_taxonomy is never itself null — subCatLabel's 'Unsorted' fallback is defensive, not a
 * reachable case here.
 *
 * Returns { symbols, ok }: `ok:false` on a read error at ANY step (Gap-1 shape) — the page must
 * distinguish this from a genuinely empty `{ symbols: [], ok: true }`. Never throws.
 */
export async function loadSymbols(supabase: SupabaseClient): Promise<SymbolsResult> {
	const { ids: transactedIds, ok: tOk } = await readTransactedSecurityIds(supabase);
	if (!tOk) return { symbols: [], ok: false };
	if (transactedIds.length === 0) return { symbols: [], ok: true };

	// (2) The caller's classification junction rows, Cat/Sub-Cat label embedded via the
	// user_taxonomy FK (direct-owner RLS on both sides — no cross-tenant leak possible: a junction
	// row the caller can read only ever embeds ITS OWN sub_cat_id's taxonomy row).
	const { data: classifiedRows, error: cErr } = await supabase
		.schema('pfin')
		.from('user_asset_category')
		.select('asset_id, sub_cat_id, user_taxonomy ( cat, sub_cat )');
	if (cErr) {
		console.error('[pendingSymbols] loadSymbols classified read failed:', cErr.message);
		return { symbols: [], ok: false };
	}
	const classificationByAsset = new Map<number, NonNullable<SymbolClassification>>();
	for (const row of (classifiedRows ?? []) as Array<{
		asset_id: number;
		sub_cat_id: number;
		user_taxonomy: unknown;
	}>) {
		const label = subCatLabel(row.user_taxonomy);
		classificationByAsset.set(row.asset_id, {
			sub_cat_id: row.sub_cat_id,
			cat: label.cat ?? '',
			sub_cat: label.sub_cat
		});
	}

	// (3) Asset labels for EVERY transacted id (superset of loadPendingSymbols' pending-only set).
	const { data: assets, error: aErr } = await supabase
		.schema('pfin')
		.from('asset')
		.select('asset_id, symbol, name, asset_type, metadata')
		.in('asset_id', transactedIds)
		.order('symbol', { ascending: true, nullsFirst: false })
		.order('name', { ascending: true });
	if (aErr) {
		console.error('[pendingSymbols] loadSymbols asset-detail read failed:', aErr.message);
		return { symbols: [], ok: false };
	}

	return {
		symbols: ((assets ?? []) as Array<Record<string, unknown>>).map((a) => {
			const asset_id = a.asset_id as number;
			return {
				asset_id,
				symbol: (a.symbol as string | null) ?? null,
				name: (a.name as string | null) ?? null,
				asset_type: a.asset_type as string,
				metadata: a.metadata ?? null,
				classification: classificationByAsset.get(asset_id) ?? null
			};
		}),
		ok: true
	};
}
