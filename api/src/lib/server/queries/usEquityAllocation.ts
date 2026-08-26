// usEquityAllocation.ts — the §2.2.3 US Equity sub-allocation backend (SELF-240; PRD §2.2.3.a).
// Backend-owned server surface (ARCH §4.1 allowlist). Drill-down into the §2.2.2 Non-RE
// allocation table's (SELF-238) computed "US - Sector Diversified" row.
//
// Reuses SELF-238's substrate UNCHANGED, per team-lead's explicit instruction (no fork):
//   - `subcatMarketValue.ts`'s `loadSubcatMarketValueAndTargets` — the SAME 076 RPC +
//     planning_target read, same p_include_real_estate=false hardcoding.
//   - `usEquitySubCats.ts`'s `US_EQUITY_SUB_CATS` — the SAME twelve DDL-copied labels 238 uses
//     to EXCLUDE+collapse; here they are the entire row set (AC1).
//   - `schemas/asOf.ts`'s `asOfSchema` / `resolveAllocationAsOf` — the SAME as_of Lock-14 fence
//     (AC6: "Identical clauses to SELF-238 AC8"). Moved from `schemas/allocation.ts` at
//     SELF-247/D-6 (surface-neutral rename; same fence, same behavior for this caller).
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
// `undefined`. `computeUsEquityAllocation`'s two trailing params (`subCatAccountIds`,
// `staleAccountIds`) keep their optional defaults — mirroring `computeNonReAllocation`'s own
// pure-core signature exactly, including WHY: a pure compute function's whole job is to answer
// for whatever it's handed, and every pre-SELF-243 call site in this suite (there is no analogous
// "forgot to thread staleness" hazard at a pure-function call site the way there is at an I/O
// boundary) degrades to `is_stale: null` on every row, never a silent `false`.
//
// ROUTE WIRED (`allocation/us-equity/+page.server.ts`, SELF-243): the route threads a real
// `staleLinkedSourceIds` value into `loadUsEquityAllocation`, mirroring the parent `/allocation`
// loader's SELF-330 pattern exactly (staleness loaded first, derived to a Set-or-null, passed
// through).
//
// ⚠ SEC-FLAGGED (7084aca, non-blocking, ratified by team-lead): `loadUsEquityAllocation`'s
// `staleLinkedSourceIds` param is now REQUIRED — no default — matching `loadNonReAllocation`'s own
// SELF-330 shape exactly (nonReAllocation.ts:538-542). It ORIGINALLY carried a `= null` default so
// this route's pre-existing two-arg call site would keep compiling before the route was wired;
// once the route WAS wired (removing the only caller that needed the default), the default became
// exactly the gap the 330 precedent was written to close: Sec's finding — "the sibling catches an
// omitted thread at typecheck... a future ramp site is exactly where that gets forgotten" — a
// default degrades safely (never silently-fresh, `null` still resolves every row to UNKNOWN) but
// trades a compile-time catch for a runtime one at the NEXT surface that reuses this loader and
// forgets to thread staleness. The compiler is the watcher now, same as every other required
// staleness param in this codebase.

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
	/** null when `!targetsPositive` (ADR-061 Decision 2: totalUsEquity <= 0 OR Σ(twelve
	 *  target_percents) <= 0) — never NaN. A real 0 is a real target; null means "no target basis
	 *  to renormalize against at all". */
	pct_target: number | null;
	/** null when `!valuePositive` (ADR-061 Decision 2: Total US Equity <= 0, i.e. zero OR
	 *  negative) — never NaN. */
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

/** ADR-061 Decision 2: `pct_alloc`'s own gate. Mirrors nonReAllocation.ts's `ratioPercentOrNull`,
 *  except the row-set here needs the already-computed `valuePositive` boolean threaded in rather
 *  than re-deriving `totalUsEquity > 0` per row — the same `totalPositive` discipline that module
 *  already establishes, so every call site in one `computeUsEquityAllocation` invocation reads the
 *  identical boolean. `> 0` (not `!== 0`) is deliberate: a negative totalUsEquity must also null,
 *  because a share of a negative basis is not a share (ADR-061 Decision 4). */
function pctAllocOrNull(
	marketValue: number,
	totalUsEquity: number,
	valuePositive: boolean
): number | null {
	return valuePositive ? (marketValue / totalUsEquity) * 100 : null;
}

/** ADR-061 Decision 2: the three target-derived columns share ONE gate, `targetsPositive`, so a
 *  caller cannot null one and not the others — mirrors nonReAllocation.ts's `targetDerivedColumns`.
 *  `targetsPositive` is passed in (the ADR-061 Decision 2 conjunction: `totalUsEquity > 0 &&
 *  sumTargets > 0`), not re-derived, so every call site reads the same boolean. The single-
 *  `targetRatio` derivation is preserved verbatim (ADR-061 Decision 2): one ratio feeds both
 *  `pct_target` and `dollar_target` to avoid compounding float rounding. */
function targetDerivedColumns(
	targetPercent: number,
	marketValue: number,
	totalUsEquity: number,
	sumTargets: number,
	targetsPositive: boolean
): { pct_target: number | null; dollar_target: number | null; dollar_realloc: number | null } {
	if (!targetsPositive) return { pct_target: null, dollar_target: null, dollar_realloc: null };
	const targetRatio = targetPercent / sumTargets;
	const dollar_target = targetRatio * totalUsEquity;
	return { pct_target: targetRatio * 100, dollar_target, dollar_realloc: dollar_target - marketValue };
}

/**
 * Pure compute core — no I/O, deterministic (AC7), unit-testable without a DB. Mirrors
 * nonReAllocation.ts's `computeNonReAllocation` shape (pendingSymbols.ts's `computePendingIds`
 * precedent, applied a third time in this directory).
 *
 * ADR-061: the degenerate-state contract is §2.2.2's GATE STRUCTURE, transplanted rather than
 * symmetrised. Two gate booleans (`valuePositive`, `targetsPositive`) are computed exactly ONCE
 * per invocation, below, and threaded to every row and to the totals row — no site re-derives
 * them (§2.2.2's own `totalPositive` discipline). See ADR-061 Decision 2/3 for the full contract
 * and the reachable-states table.
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

	// ADR-061 Decision 2: the two gate booleans, computed ONCE and threaded to every row and the
	// totals row below — never re-derived per site. `> 0` on both (not `!== 0`): a negative
	// totalUsEquity must null (a share of a negative basis is not a share, Decision 4); sumTargets
	// cannot currently go negative (074's `[0, 100]` CHECK) but is specified as `> 0` regardless so
	// this module asserts its own domain requirement rather than inheriting a different artifact's
	// CHECK (Decision 4).
	const valuePositive = totalUsEquity > 0;
	const targetsPositive = totalUsEquity > 0 && sumTargets > 0;

	const rows: UsEquityRow[] = raw.map((r) => ({
		sub_cat_id: r.id,
		cat: 'Marketable Securities',
		sub_cat: r.label,
		pct_alloc: pctAllocOrNull(r.market_value, totalUsEquity, valuePositive),
		dollar_alloc: r.market_value, // NEVER null, never gated — not ratio-derived (ADR-061 Decision 2).
		is_stale: rowIsStale(r.id),
		...targetDerivedColumns(r.target_percent, r.market_value, totalUsEquity, sumTargets, targetsPositive)
	}));

	// ADR-061 Decision 2: totals row, gated by the SAME two booleans as the per-row columns.
	const total: UsEquityTotalRow = {
		dollar_alloc: totalUsEquity, // NEVER null, never gated.
		pct_alloc: valuePositive ? 100 : null,
		pct_target: targetsPositive ? 100 : null,
		dollar_target: targetsPositive ? totalUsEquity : null,
		dollar_realloc: targetsPositive ? 0 : null
	};

	return { rows, total };
}

/**
 * Load the caller's §2.2.3 US Equity sub-allocation table, RLS-scoped via the per-request
 * client. `asOf` must already be a validated `ZoneResolvedAsOf` — see `schemas/asOf.ts`'s
 * `resolveAllocationAsOf` (the SAME schema SELF-238 uses; AC6). Fail-soft, mirrors
 * nonReAllocation.ts / subcatMarketValue.ts: any read error degrades to `{ data: null, ok: false
 * }`, logged, never thrown.
 *
 * `staleLinkedSourceIds` (SELF-243 — mirrors `loadNonReAllocation`'s own parameter of the same
 * name VERBATIM, including its tri-state contract AND its REQUIRED-ness — no default, matching
 * `loadNonReAllocation` exactly (nonReAllocation.ts:538-542; Sec-flagged 7084aca, ratified by
 * team-lead: a default here would mask a caller genuinely forgetting to thread staleness — the
 * compiler is the watcher, the same discipline the 330 sibling already established). The route
 * (`allocation/us-equity/+page.server.ts`) threads a real value through, mirroring the parent
 * `/allocation` loader's SELF-330 call exactly — passing `null` explicitly is still the correct
 * choice for a caller whose OWN root `046` read was unknown; only the ABSENCE of an argument is
 * now disallowed. This function runs the SAME contributor-bridge + account-bridge sequence
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
	staleLinkedSourceIds: ReadonlySet<string> | null
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
