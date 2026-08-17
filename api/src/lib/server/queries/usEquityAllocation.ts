// usEquityAllocation.ts — the §2.2.3 US Equity sub-allocation backend (SELF-240; PRD §2.2.3.a).
// Backend-owned server surface (ARCH §4.1 allowlist). Drill-down into the §2.2.2 Non-RE
// allocation table's (SELF-238) computed "US - Sector Diversified" row.
//
// Reuses SELF-238's substrate UNCHANGED, per team-lead's explicit instruction (no fork):
//   - `subcatMarketValue.ts`'s `loadSubcatMarketValueAndTargets` — the SAME 076 RPC +
//     planning_target read, same p_include_real_estate=false hardcoding.
//   - `usEquitySubCats.ts`'s `US_EQUITY_SUB_CATS` — the SAME twelve DDL-copied labels 238 uses
//     to EXCLUDE+collapse; here they are the entire row set (AC1).
//   - `schemas/allocation.ts`'s `allocationAsOfSchema` / `resolveAllocationAsOf` — the SAME
//     as_of Lock-14 fence (AC6: "Identical clauses to SELF-238 AC8").
//
// AC4 (β, F/CTO-ruled 2026-08-17): a DISPLAY-LAYER renormalization, not a second stored
// semantics. `pfin.planning_target.target_percent` keeps its 074 share-of-Total-Non-RE meaning
// unchanged (238 reads it that way too) — this module computes a SECOND, LOCAL percentage
// (target_percent / Σ the twelve's target_percent) purely for THIS table's own %Target/$Target
// columns. Nothing is written back; nothing about 074's stored value changes.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { loadSubcatMarketValueAndTargets, type SubcatMarketValueRow } from './subcatMarketValue';
import { US_EQUITY_SUB_CATS, US_EQUITY_SUB_CAT_SET } from './usEquitySubCats';

/** One of the twelve rows (AC1's exact order — US_EQUITY_SUB_CATS is the single source of
 *  truth for both the row SET and the row ORDER). */
export type UsEquityRow = {
	/** null only if the caller's OWN taxonomy is somehow missing this Sub-Cat (not expected for a
	 *  provisioned user — 041 seeds all twelve atomically — but AC1's "all twelve render
	 *  regardless of held/target state" is honored literally even in that edge case: the row
	 *  still renders, with market_value/target_percent both defaulting to 0 as if zero-held). */
	sub_cat_id: number | null;
	cat: 'Equity';
	sub_cat: string;
	/** null when Σ(twelve target_percents) = 0 (AC5 ii) — never NaN. A real 0 is a real target;
	 *  null means "no target basis to renormalize against at all". */
	pct_target: number | null;
	/** null when Total US Equity = 0 (AC5 i) — never NaN. */
	pct_alloc: number | null;
	/** Cascades from pct_target: null iff pct_target is null (AC5 ii: "$Target ... render unset"). */
	dollar_target: number | null;
	/** NEVER null — always the row's real market_value, 0 when zero-held. */
	dollar_alloc: number;
	/** Cascades from dollar_target: null iff dollar_target is null. */
	dollar_realloc: number | null;
};

/** The table's total row (AC3's drill-down-identity anchor lives on `dollar_alloc` here — it
 *  MUST equal 238's collapsed "US - Sector Diversified" row's dollar_alloc exactly). The other
 *  four columns are NOT separately ratified by any AC; they are derived here by the same
 *  mechanical rule the twelve rows use (Σ of the whole = 100% of itself when non-degenerate) —
 *  a judgment call for rendering completeness, not a re-derivation of a requirement. Defined
 *  directly (100 / totalUsEquity) rather than summed from the twelve rows, to avoid any
 *  floating-point drift a literal sum could introduce. */
export type UsEquityTotalRow = {
	dollar_alloc: number;
	pct_alloc: number | null;
	pct_target: number | null;
	dollar_target: number | null;
	dollar_realloc: number | null;
};

export type UsEquityAllocation = {
	/** Exactly twelve, in AC1's canonical order. */
	rows: UsEquityRow[];
	total: UsEquityTotalRow;
};

export type UsEquityAllocationResult = { data: UsEquityAllocation | null; ok: boolean };

/**
 * Pure compute core — no I/O, deterministic (AC7), unit-testable without a DB. Mirrors
 * nonReAllocation.ts's `computeNonReAllocation` shape (pendingSymbols.ts's `computePendingIds`
 * precedent, applied a third time in this directory).
 */
export function computeUsEquityAllocation(
	taxonomyRows: ReadonlyArray<{ id: number; sub_cat: string }>,
	marketValueRows: ReadonlyArray<SubcatMarketValueRow>,
	targetBySubCatId: ReadonlyMap<number, number>
): UsEquityAllocation {
	const idByLabel = new Map<string, number>();
	for (const t of taxonomyRows) {
		if (US_EQUITY_SUB_CAT_SET.has(t.sub_cat)) idByLabel.set(t.sub_cat, t.id);
	}
	const marketValueBySubCatId = new Map<number, number>();
	for (const r of marketValueRows) {
		if (r.sub_cat_id !== null) marketValueBySubCatId.set(r.sub_cat_id, Number(r.market_value));
	}

	const raw = US_EQUITY_SUB_CATS.map((label) => {
		const id = idByLabel.get(label) ?? null;
		const market_value = id !== null ? (marketValueBySubCatId.get(id) ?? 0) : 0;
		const target_percent = id !== null ? Number(targetBySubCatId.get(id) ?? 0) : 0;
		return { id, label, market_value, target_percent };
	});

	// AC3: Total US Equity = Σ the twelve's market_value — the drill-down-identity anchor.
	const totalUsEquity = raw.reduce((sum, r) => sum + r.market_value, 0);
	// AC4 β's own denominator — Σ the twelve's RAW (074 share-of-Total-Non-RE) target_percent.
	const sumTargets = raw.reduce((sum, r) => sum + r.target_percent, 0);

	const rows: UsEquityRow[] = raw.map((r) => {
		// AC5(i): guard on totalUsEquity, never NaN.
		const allocRatio = totalUsEquity === 0 ? null : r.market_value / totalUsEquity;
		// AC4/AC5(ii): guard on sumTargets, never NaN. One ratio feeds BOTH pct_target and
		// dollar_target (not pct_target*totalUsEquity/100) to avoid compounding float rounding.
		const targetRatio = sumTargets === 0 ? null : r.target_percent / sumTargets;
		const dollar_target = targetRatio === null ? null : targetRatio * totalUsEquity;
		return {
			sub_cat_id: r.id,
			cat: 'Equity',
			sub_cat: r.label,
			pct_target: targetRatio === null ? null : targetRatio * 100,
			pct_alloc: allocRatio === null ? null : allocRatio * 100,
			dollar_target,
			dollar_alloc: r.market_value,
			dollar_realloc: dollar_target === null ? null : dollar_target - r.market_value
		};
	});

	const total: UsEquityTotalRow = {
		dollar_alloc: totalUsEquity,
		pct_alloc: totalUsEquity === 0 ? null : 100,
		pct_target: sumTargets === 0 ? null : 100,
		dollar_target: sumTargets === 0 ? null : totalUsEquity,
		dollar_realloc: sumTargets === 0 ? null : 0
	};

	return { rows, total };
}

/**
 * Load the caller's §2.2.3 US Equity sub-allocation table, RLS-scoped via the per-request
 * client. `asOf` must already be a validated `ZoneResolvedAsOf` — see `schemas/allocation.ts`'s
 * `resolveAllocationAsOf` (the SAME schema SELF-238 uses; AC6). Fail-soft, mirrors
 * nonReAllocation.ts / subcatMarketValue.ts: any read error degrades to `{ data: null, ok: false
 * }`, logged, never thrown.
 */
export async function loadUsEquityAllocation(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<UsEquityAllocationResult> {
	const substrate = await loadSubcatMarketValueAndTargets(supabase, asOf);
	if (!substrate.ok) return { data: null, ok: false };

	// Scoped to exactly the twelve labels (AC1's row set) rather than the full asset-domain
	// catalog nonReAllocation.ts reads — this surface never needs anything outside them.
	const { data: taxonomyRows, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, sub_cat')
		.eq('domain', 'asset')
		.in('sub_cat', US_EQUITY_SUB_CATS as string[]);
	if (error) {
		console.error('[usEquityAllocation] user_taxonomy read failed:', error.message);
		return { data: null, ok: false };
	}

	return {
		data: computeUsEquityAllocation(
			(taxonomyRows ?? []) as Array<{ id: number; sub_cat: string }>,
			substrate.rows,
			substrate.targetBySubCatId
		),
		ok: true
	};
}
