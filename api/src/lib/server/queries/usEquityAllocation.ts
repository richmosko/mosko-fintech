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
//
// PER-ROW STALENESS (SELF-243 — the §2.2.3 half of the SELF-208/229 staleness-ramp; producer
// only, scoped to AC1/AC3's own text: per-row `is_stale`, no account-name resolution yet — that
// half is a separate F/CTO-pending call, see team-lead routing). SELF-330-EQUIVALENT, not a
// fork: reuses `nonReAllocation.ts`'s exported `loadSubCatContributors` (the fn_subcat_
// contributors bridge) and `navComposition.ts`'s exported `resolveStaleAccountIds` (the
// linked_source_id -> account_id bridge) VERBATIM, per both functions' own "do not fork this
// logic" docstrings. This module's fold is SIMPLER than nonReAllocation.ts's own in one respect
// and stricter in another:
//   - SIMPLER: no collapsed/aggregate row exists here (all twelve rows are real, individually
//     rendered Sub-Cats — unlike §2.2.2's synthetic "US - Sector Diversified" row), so there is
//     no `foldIsStale`-style Kleene-OR-across-many-ids fold, only a single-id lookup per row.
//   - STRICTER: a row whose `sub_cat_id` is `null` here means something DIFFERENT from
//     nonReAllocation.ts's `null` key. There, `null` is the real Unsorted row and a LEGITIMATE
//     lookup key into the contributor map (076's NULL-taxonomy bucket). HERE, `sub_cat_id ===
//     null` means "this US-equity label is missing from the caller's own taxonomy" (AC1's
//     documented edge case) — it has NO sub_cat_id for ANY position to be classified into, and
//     must NEVER be used to look up the map's `null` key, which would misattribute the tenant's
//     Unsorted-bucket staleness onto this unrelated row. `rowIsStale` below guards on this
//     explicitly, before ever touching the map — see its own comment.
//
// Producer contract mirrors AllocationRow.is_stale exactly: `true | false | null`, NEVER
// `undefined`. `subCatAccountIds` / `staleAccountIds` both default to the same "unknown, nothing
// supplied" state nonReAllocation.ts's `computeNonReAllocation` uses — every pre-SELF-243 call
// site in this suite (and `loadUsEquityAllocation`'s own existing route call, until the route is
// wired) degrades to `is_stale: null` on every row, never a silent `false`.
//
// ⚠ ROUTE NOT YET WIRED (F/CTO-pending, see module header above): `loadUsEquityAllocation`'s new
// `staleLinkedSourceIds` param defaults to `null` so `allocation/us-equity/+page.server.ts`'s
// EXISTING two-arg call keeps compiling and keeps its current (correct, honest) behavior —
// every row's `is_stale` resolves to `null` (UNKNOWN) until the route is updated to thread a real
// value through, the same "default is a real code path, not a distinct one" posture
// computeNonReAllocation's own optional params already establish.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { loadSubcatMarketValueAndTargets, type SubcatMarketValueRow } from './subcatMarketValue';
import { loadSubCatContributors } from './nonReAllocation';
import { resolveStaleAccountIds } from './navComposition';
import { US_EQUITY_SUB_CATS, US_EQUITY_SUB_CAT_SET } from './usEquitySubCats';

/** One of the twelve rows (AC1's exact order — US_EQUITY_SUB_CATS is the single source of
 *  truth for both the row SET and the row ORDER). */
export type UsEquityRow = {
	/** null only if the caller's OWN taxonomy is somehow missing this Sub-Cat (not expected for a
	 *  provisioned user — 041 seeds all twelve atomically — but AC1's "all twelve render
	 *  regardless of held/target state" is honored literally even in that edge case: the row
	 *  still renders, with market_value/target_percent both defaulting to 0 as if zero-held). */
	sub_cat_id: number | null;
	cat: 'Marketable Securities';
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
	/** SELF-243: tri-state, mirroring AllocationRow.is_stale's own contract — NEVER `undefined`
	 *  (binding producer contract; see module header). `true` = at least one contributing account
	 *  is in the caller's `046` stale set. `false` = every contributing account resolved to
	 *  confirmed-not-stale, this Sub-Cat has no contributing accounts at all (vacuous fold), OR
	 *  `sub_cat_id` is `null` (the label is missing from the caller's own taxonomy — structurally
	 *  no position can be classified into it, so it is never "stale," never looked up against the
	 *  contributor map's Unsorted-row `null` key — see module header). `null` = UNKNOWN — the
	 *  root `046` read was itself unknown, or the contributor/account bridge read failed;
	 *  propagates uniformly to every row in that case, never mixed with a resolved value in the
	 *  same table. */
	is_stale: boolean | null;
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
	targetBySubCatId: ReadonlyMap<number, number>,
	// SELF-243: mirrors computeNonReAllocation's own two trailing params VERBATIM in shape and
	// default posture — see module header's PER-ROW STALENESS note for why this fold is simpler
	// (no collapsed-row Kleene-OR) and stricter (the `sub_cat_id === null` guard) than that one.
	// Both default to the "unknown, nothing supplied" state: every call site that omits them
	// (every pre-SELF-243 test in this suite) gets `is_stale: null` on every row, never a silent
	// `false` — the same non-distinct-default posture computeNonReAllocation already establishes.
	subCatAccountIds: ReadonlyMap<number | null, ReadonlySet<string>> = new Map(),
	staleAccountIds: ReadonlySet<string> | null = null
): UsEquityAllocation {
	// SELF-243 fold core. Single-id lookup per row — no Kleene-OR-across-many-ids fold needed
	// here (contrast nonReAllocation.ts's `foldIsStale`), because every row in this table already
	// has its own real `sub_cat_id` (or `null` for "missing from taxonomy" — see below), never a
	// synthetic collapsed row standing in for several.
	//
	// ⚠ THE `subCatId === null` GUARD IS LOAD-BEARING AND MUST RUN BEFORE THE MAP LOOKUP, NOT
	// AFTER. `subCatAccountIds`'s `null` key (as `loadSubCatContributors` — reused verbatim from
	// nonReAllocation.ts — populates it) holds the tenant's UNSORTED-row contributors (076's
	// NULL-taxonomy bucket), a completely unrelated population to "this US-equity label has no
	// sub_cat_id in the caller's own taxonomy." Looking up `subCatAccountIds.get(null)` for a
	// missing-from-taxonomy row would misattribute the tenant's Unsorted-bucket staleness onto an
	// unrelated US-equity row — a real, silent cross-row leak (same-tenant, not cross-tenant, but
	// still a correctness bug) with no test that would catch it by construction if the guard were
	// merely implicit. A `null` sub_cat_id here is treated as "vacuously not stale, once the root
	// state is known" — the same "no contributors, no staleness" answer a real Sub-Cat id with an
	// empty contributor set already gets — never as a key into the map.
	function rowIsStale(subCatId: number | null): boolean | null {
		if (staleAccountIds === null) return null;
		if (subCatId === null) return false;
		const contributors = subCatAccountIds.get(subCatId);
		if (!contributors || contributors.size === 0) return false;
		for (const accountId of contributors) {
			if (staleAccountIds.has(accountId)) return true;
		}
		return false;
	}

	const idByLabel = new Map<string, number>();
	for (const t of taxonomyRows) {
		if (US_EQUITY_SUB_CAT_SET.has(t.sub_cat)) idByLabel.set(t.sub_cat, t.id);
	}
	// LOAD-BEARING FOR TENANT ISOLATION, Sec-flagged: this map MUST key by sub_cat_id (074's
	// per-caller RLS-scoped bigint id), never by `sub_cat` label text. `sub_cat_id` is the row's
	// real tenant-scoped identity — the caller's OWN taxonomy read (`idByLabel` above) is what
	// resolves a label to THIS caller's id, and only an id THAT read produced is ever looked up
	// here. Labels ('US-06-Financials' etc.) are SHARED VOCABULARY across every tenant by design
	// (041's seed), so a map keyed by label would silently match a foreign tenant's row of the
	// same name — a leak with no test that would catch it by construction, since the two rows
	// would be indistinguishable by the (wrong) key. Keying by id is what makes a cross-tenant
	// value structurally unable to resolve: `marketValueRows` and `idByLabel` come from two
	// SEPARATE RLS-scoped reads (076's rollup and this caller's own user_taxonomy), so a foreign
	// value reaching this map would require BOTH reads to be broken simultaneously, not one.
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
			cat: 'Marketable Securities',
			sub_cat: r.label,
			pct_target: targetRatio === null ? null : targetRatio * 100,
			pct_alloc: allocRatio === null ? null : allocRatio * 100,
			dollar_target,
			dollar_alloc: r.market_value,
			is_stale: rowIsStale(r.id),
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
 *
 * `staleLinkedSourceIds` (SELF-243 — mirrors `loadNonReAllocation`'s own parameter of the same
 * name VERBATIM, including its tri-state contract). Defaults to `null` — UNLIKE
 * `loadNonReAllocation`'s own REQUIRED param, because the route
 * (`allocation/us-equity/+page.server.ts`) is NOT YET updated to pass one (F/CTO-pending AC3/AC4
 * account-name reconciliation, see module header) and this default keeps that existing two-arg
 * call site compiling with its current, honest behavior: `null` is the SAME value the root
 * `046` read being unknown produces, so every row's `is_stale` resolves to `null` (UNKNOWN)
 * either way — never a silent `false`. When a real Set (possibly empty) is threaded through by a
 * future route update, this function runs the SAME contributor-bridge + account-bridge sequence
 * `loadNonReAllocation` does, reusing both bridges verbatim (no forked RPC calls):
 *   1. `loadSubCatContributors` (nonReAllocation.ts) — the caller's full (sub_cat_id, account_id)
 *      contributor map. This module only ever looks up the twelve US-equity ids out of it.
 *   2. `resolveStaleAccountIds` (navComposition.ts) — resolves the stale `linked_source_id`s to
 *      `account_id`s.
 * Either bridge failing leaves `staleAccountIds` at `null`, which forces every row's fold to
 * `null` via `computeUsEquityAllocation`'s own short-circuit — never a partial or silently-fresh
 * table, same posture `loadNonReAllocation` already establishes.
 */
export async function loadUsEquityAllocation(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf,
	staleLinkedSourceIds: ReadonlySet<string> | null = null
): Promise<UsEquityAllocationResult> {
	const substrate = await loadSubcatMarketValueAndTargets(supabase, asOf);
	if (!substrate.ok) return { data: null, ok: false };

	// Scoped to exactly the twelve labels (AC1's row set) rather than the full asset-domain
	// catalog nonReAllocation.ts reads — this surface never needs anything outside them.
	// POST-084: no `.eq('domain', 'asset')` — `user_taxonomy` is asset-domain by construction now
	// (ADR-058 Decision 1's split), so the `.in('sub_cat', ...)` clause alone is the full scope.
	const { data: taxonomyRows, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, sub_cat')
		.in('sub_cat', US_EQUITY_SUB_CATS as string[]);
	if (error) {
		console.error('[usEquityAllocation] user_taxonomy read failed:', error.message);
		return { data: null, ok: false };
	}

	// SELF-243: a metadata-only (staleness) failure must NEVER take down this table's actual $/%
	// data — mirrors loadNonReAllocation's own "fail-soft, but never to confirmed-fresh" posture.
	// `subCatAccountIds` / `staleAccountIds` start at their UNKNOWN defaults (empty map / null)
	// and are only upgraded once BOTH the contributor RPC and the account bridge have succeeded.
	let subCatAccountIds: ReadonlyMap<number | null, ReadonlySet<string>> = new Map();
	let staleAccountIds: ReadonlySet<string> | null = null;
	if (staleLinkedSourceIds !== null) {
		const contributors = await loadSubCatContributors(supabase, asOf);
		if (contributors !== null) {
			subCatAccountIds = contributors;
			staleAccountIds = await resolveStaleAccountIds(supabase, staleLinkedSourceIds);
		}
	}

	return {
		data: computeUsEquityAllocation(
			(taxonomyRows ?? []) as Array<{ id: number; sub_cat: string }>,
			substrate.rows,
			substrate.targetBySubCatId,
			subCatAccountIds,
			staleAccountIds
		),
		ok: true
	};
}
