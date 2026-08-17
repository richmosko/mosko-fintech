// nonReAllocation.ts — the §2.2.2 Non-RE allocation table backend (SELF-238; PRD §2.2.2.b).
// Backend-owned server surface (ARCH §4.1 allowlist).
//
// Consumes the shared `subcatMarketValue.ts` helper (076 rollup + planning_target read) and
// adds this surface's OWN row-set logic on top: a FULL enumeration of the caller's asset-domain
// Sub-Cats (so a zero-held, zero-target seeded Sub-Cat still renders — AC2), the twelve
// US-equity Sub-Cats collapsed into one computed "US - Sector Diversified" row (AC2a/AC5), the
// derived Unsorted row when 076 emits its unclassified row (AC2c), and the five %/$ columns per
// AC3.
//
// WHY A SEPARATE `user_taxonomy` READ, ON TOP OF THE 076 RPC: 076 returns one row per Sub-Cat
// the caller HOLDS VALUE IN — a zero-held Sub-Cat is simply absent from its return (076's own
// contract). AC2's "zero-held+zero-target seeded Sub-Cats still render with zeros" requires the
// FULL catalog, not just the held subset, so this module reads the caller's OWN
// `pfin.user_taxonomy` (direct-owner RLS, domain='asset') separately and LEFT-merges 076's
// market_value onto it (absent → 0) — the same "supabase-js has no cross-table server LEFT
// JOIN across independently-RLS'd tables" shape pendingSymbols.ts / navComposition.ts already
// established, applied to a THIRD table pair here.
//
// Fail-soft (mirrors subcatMarketValue.ts / navComposition.ts): any read error degrades to
// `{ data: null, ok: false }` — logged, never thrown.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { loadSubcatMarketValueAndTargets, type SubcatMarketValueRow } from './subcatMarketValue';
import { US_EQUITY_SUB_CAT_SET, US_SECTOR_DIVERSIFIED_LABEL } from './usEquitySubCats';

/** The fixed §2.2.2 Cat-group header order (PRD §2.2.2 / AC2). Real Estate is never a member —
 *  076 excludes it entirely at p_include_real_estate=false, and this module's own taxonomy
 *  enumeration filters it out independently (see computeNonReAllocation) since 076's exclusion
 *  does not reach the SEPARATE full-catalog read this surface adds. */
const CAT_GROUP_ORDER = ['Cash', 'Bonds', 'Equity', 'Alternatives', 'Liabilities'] as const;

/** The collapsed row's sort position within the Equity group: 100 is 041's `display_order` for
 *  `US-01-Basic_Materials`, the first of the twelve it replaces — a defensible, deterministic
 *  choice tied to real seed data. No AC specifies collapsed-row placement; this is a rendering
 *  judgment call, not a ratified requirement. */
const US_SECTOR_DIVERSIFIED_DISPLAY_ORDER = 100;

export type AllocationRowKind = 'sub_cat' | 'us_sector_diversified' | 'unsorted';

export type AllocationRow = {
	kind: AllocationRowKind;
	/** null for the collapsed row (no taxonomy row exists, none is created — AC2a) and for the
	 *  Unsorted row (076's NULL-taxonomy row — AC2c). */
	sub_cat_id: number | null;
	cat: string | null;
	sub_cat: string;
	/** null ONLY for the Unsorted row — "structurally empty" (AC3): 074's sub_cat_id bigint NOT
	 *  NULL FK means no planning_target row can exist for a NULL-taxonomy key. Every other row,
	 *  including a zero-target one, carries a real 0 here (0 IS an assertable target, per
	 *  074/ADR-056 — distinct from null/absent). */
	pct_target: number | null;
	/** NEVER null — AC7 (empty portfolio) renders zeros, not an unset state; the division guard
	 *  below returns 0 when total_non_re is 0 rather than NaN. */
	pct_alloc: number;
	dollar_target: number | null;
	dollar_alloc: number;
	dollar_realloc: number | null;
};

export type AllocationCatGroup = {
	cat: (typeof CAT_GROUP_ORDER)[number];
	rows: AllocationRow[];
};

export type NonReAllocation = {
	/** Fixed order per CAT_GROUP_ORDER; every group present (never omitted for being empty — at
	 *  V1 scale a provisioned caller's full taxonomy always populates every seeded Cat, and AC2
	 *  does not ask for empty-group omission the way 051's composition groups do). */
	groups: AllocationCatGroup[];
	/** Present iff 076 emitted its unclassified row (AC2c) — never a zero-valued placeholder. */
	unsorted: AllocationRow | null;
	/** Σ market_value over EVERY row 076 returned, Unsorted included (AC3) — the AC4 footing
	 *  anchor: must equal the §2.1.5 composition's Total Non-RE at the same p_as_of, exactly. */
	total_non_re: number;
};

export type NonReAllocationResult = { data: NonReAllocation | null; ok: boolean };

/** One caller-owned asset-domain Sub-Cat, as read from `pfin.user_taxonomy` directly (NOT
 *  through 076) — the full-enumeration source AC2's zero-render requirement needs. */
export type TaxonomySubCatRow = {
	id: number;
	cat: string;
	sub_cat: string;
	display_order: number | null;
};

/** AC7 / general Lock-14 numeric discipline: 0/0 renders as 0 here (076's own contract makes
 *  every market_value 0 when total_non_re is 0, so this is never a hidden divide-by-nonzero
 *  case) — NEVER NaN. Percent scale (×100) applied by the caller. */
function safeAllocFraction(marketValue: number, totalNonRe: number): number {
	return totalNonRe === 0 ? 0 : (marketValue / totalNonRe) * 100;
}

/**
 * Pure compute core — no I/O, deterministic, unit-testable without a DB (pendingSymbols.ts's
 * `computePendingIds` precedent). Takes the caller's full asset-domain taxonomy catalog, 076's
 * raw rows, and the planning_target map; returns the fully-shaped §2.2.2 table.
 */
export function computeNonReAllocation(
	taxonomyRows: ReadonlyArray<TaxonomySubCatRow>,
	marketValueRows: ReadonlyArray<SubcatMarketValueRow>,
	targetBySubCatId: ReadonlyMap<number, number>
): NonReAllocation {
	// AC3: TotalNonRE is the UNFILTERED sum over every row 076 returned (Unsorted included) — the
	// exact-footing anchor. Computed from the raw RPC rows, never re-derived from the merged
	// taxonomy view below, so a merge bug can never silently change this number.
	const total_non_re = marketValueRows.reduce((sum, r) => sum + Number(r.market_value), 0);

	const marketValueBySubCatId = new Map<number, number>();
	let unsortedMarketValue: number | null = null;
	for (const r of marketValueRows) {
		if (r.sub_cat_id === null) {
			unsortedMarketValue = Number(r.market_value);
		} else {
			marketValueBySubCatId.set(r.sub_cat_id, Number(r.market_value));
		}
	}

	function rowFor(id: number, cat: string, sub_cat: string): AllocationRow {
		const market_value = marketValueBySubCatId.get(id) ?? 0;
		const target_percent = Number(targetBySubCatId.get(id) ?? 0);
		const dollar_target = (target_percent / 100) * total_non_re;
		return {
			kind: 'sub_cat',
			sub_cat_id: id,
			cat,
			sub_cat,
			pct_target: target_percent,
			pct_alloc: safeAllocFraction(market_value, total_non_re),
			dollar_target,
			dollar_alloc: market_value,
			dollar_realloc: dollar_target - market_value
		};
	}

	// Real Estate is excluded independently here (this read is NOT 076's own p_include_real_estate
	// filter — it is a separate full-catalog read of user_taxonomy). The twelve US-equity Sub-Cats
	// are excluded too — they fold into the collapsed row below, not individual rows.
	const regularTaxonomyRows = taxonomyRows.filter(
		(t) => t.cat !== 'Real Estate' && !US_EQUITY_SUB_CAT_SET.has(t.sub_cat)
	);

	const rowsByCat = new Map<string, AllocationRow[]>();
	for (const t of regularTaxonomyRows) {
		const row = rowFor(t.id, t.cat, t.sub_cat);
		(rowsByCat.get(t.cat) ?? rowsByCat.set(t.cat, []).get(t.cat)!).push(row);
	}
	// Track display_order per emitted row for the final per-group sort (Map above loses it).
	const displayOrderById = new Map<number, number>();
	for (const t of regularTaxonomyRows) displayOrderById.set(t.id, t.display_order ?? 0);

	// AC5: the collapsed row. $Alloc = Σ the twelve's market_value; %Target = Σ their
	// target_percent (074's uniform Non-RE denomination — summing shares of the SAME whole is
	// valid, unlike SELF-240's own drill-down renormalization). $Target/$ReAlloc per AC3's
	// formulas, using that summed target_percent exactly like any other row's.
	const usEquityTaxonomyRows = taxonomyRows.filter((t) => US_EQUITY_SUB_CAT_SET.has(t.sub_cat));
	const collapsedMarketValue = usEquityTaxonomyRows.reduce(
		(sum, t) => sum + (marketValueBySubCatId.get(t.id) ?? 0),
		0
	);
	const collapsedTargetPercent = usEquityTaxonomyRows.reduce(
		(sum, t) => sum + Number(targetBySubCatId.get(t.id) ?? 0),
		0
	);
	const collapsedDollarTarget = (collapsedTargetPercent / 100) * total_non_re;
	const collapsedRow: AllocationRow = {
		kind: 'us_sector_diversified',
		sub_cat_id: null,
		cat: 'Equity',
		sub_cat: US_SECTOR_DIVERSIFIED_LABEL,
		pct_target: collapsedTargetPercent,
		pct_alloc: safeAllocFraction(collapsedMarketValue, total_non_re),
		dollar_target: collapsedDollarTarget,
		dollar_alloc: collapsedMarketValue,
		dollar_realloc: collapsedDollarTarget - collapsedMarketValue
	};
	(rowsByCat.get('Equity') ?? rowsByCat.set('Equity', []).get('Equity')!).push(collapsedRow);
	displayOrderById.set(-1, US_SECTOR_DIVERSIFIED_DISPLAY_ORDER); // synthetic id for the sort below

	const groups: AllocationCatGroup[] = CAT_GROUP_ORDER.map((cat) => {
		const rows = (rowsByCat.get(cat) ?? []).slice();
		rows.sort((a, b) => {
			const da = displayOrderById.get(a.sub_cat_id ?? -1) ?? 0;
			const db = displayOrderById.get(b.sub_cat_id ?? -1) ?? 0;
			return da - db;
		});
		return { cat, rows };
	});

	// AC2c / AC3: Unsorted carries %Alloc/$Alloc only — target cells are structurally null, never
	// 0 (0 would assert "a real zero target", which is impossible for a row with no sub_cat_id).
	const unsorted: AllocationRow | null =
		unsortedMarketValue === null
			? null
			: {
					kind: 'unsorted',
					sub_cat_id: null,
					cat: null,
					sub_cat: 'Unsorted',
					pct_target: null,
					pct_alloc: safeAllocFraction(unsortedMarketValue, total_non_re),
					dollar_target: null,
					dollar_alloc: unsortedMarketValue,
					dollar_realloc: null
				};

	return { groups, unsorted, total_non_re };
}

/**
 * Load the caller's §2.2.2 Non-RE allocation table, RLS-scoped via the per-request client. `asOf`
 * must already be a validated `ZoneResolvedAsOf` (see schemas/allocation.ts's
 * `resolveAllocationAsOf` — this function does no parsing of its own, mirroring
 * navComposition.ts's `loadNavComposition` signature).
 */
export async function loadNonReAllocation(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<NonReAllocationResult> {
	const substrate = await loadSubcatMarketValueAndTargets(supabase, asOf);
	if (!substrate.ok) return { data: null, ok: false };

	const { data: taxonomyRows, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, cat, sub_cat, display_order')
		.eq('domain', 'asset');
	if (error) {
		console.error('[nonReAllocation] user_taxonomy read failed:', error.message);
		return { data: null, ok: false };
	}

	return {
		data: computeNonReAllocation(
			(taxonomyRows ?? []) as TaxonomySubCatRow[],
			substrate.rows,
			substrate.targetBySubCatId
		),
		ok: true
	};
}
