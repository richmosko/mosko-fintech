// nonReAllocation.ts — the §2.2.2 Non-RE allocation table backend. Originally SELF-238; REWORKED
// WHOLESALE at SELF-239 (2026-08-20 ratified ACs) to close the assets-only gap 085's `element`
// column exists to make enforceable. Backend-owned server surface (ARCH §4.1 allowlist).
//
// WHAT CHANGED AT SELF-239, AND WHY. `pfin.fn_subcat_market_value` (076) returns rows for BOTH
// `element` values — deliberately, per its own catalog comment (085): the liability cash route
// (081) contributes rows the seam invariant `Σ fn_subcat_market_value(as_of, true) =
// fn_compute_nav(as_of)` counts, so the producer cannot filter on element without breaking that
// footing. The assets-only exclusion is therefore a CONSUMER-side predicate, and this module is
// the consumer 076's own comment names as owning it. Pre-085 this module could only express
// "assets-only" as "exclude the Cat named Liabilities" — a NAME-based exclusion, silently wrong if
// a Sub-Cat under a different Cat ever held a liability balance. Post-085 it is expressible as
// `element = 'asset'`, a PREDICATE, and SELF-239 moves both the row set AND the denominator onto
// it — in the SAME compute call, from the SAME taxonomy read, so the two cannot diverge (AC3's
// "same-query predicate" route; see `assetSubCatIds` below). Three consumer-visible deltas fall
// out of this rework, none of them producer changes:
//   (1) CAT_GROUP_ORDER drops 'Liabilities' — it was never supposed to render here (assets-only),
//       and rendering it was reachable pre-085 because nothing prevented a Liabilities Cat's rows
//       from flowing through this module's own full-taxonomy read.
//   (2) TotalNonRE no longer includes a liability-cash-route row's value — pre-085 it summed EVERY
//       076 row unfiltered, which silently counted Liabilities/`Liability Balances` (081) in the
//       denominator.
//   (3) The five ratio-derived columns (%Alloc/%Target/$Target/$ReAlloc) render `null`, not `0`,
//       when TotalNonRE <= 0 (AC6) — the shipped SELF-238 payload rendered `pct_alloc: 0` in that
//       state, which reads as "a real zero allocation" instead of "this ratio is undefined."
//       `$Alloc` (raw market value) is unaffected — it is never ratio-derived.
//
// SEC HARDENING ROUND 2 (2026-08-20, F/CTO-adopted, post-push review). Two further changes, both
// on the SAME theme as the round-1 rework: a claim this module made about its own shape was true
// CONDITIONALLY (true of the seed as it stands today) rather than STRUCTURALLY (true by
// construction, regardless of what the taxonomy vocabulary ever grows to hold) — Sec's own framing
// for the class.
//   (a) UNKNOWN-CAT HANDLING, option (B) — UNION, never silent drop. Pre-round-2, `groups` was
//       built as `CAT_GROUP_ORDER.map(...)` — a lookup over exactly the four canonical Cats. If the
//       caller's taxonomy ever held an asset-element Sub-Cat under a Cat OUTSIDE those four (a new
//       Cat added to the vocabulary, not yet one of the recognized four), that Sub-Cat's value was
//       STILL counted in `total_non_re` (assetSubCatIds does not filter by Cat) but its ROW was
//       silently absent from every group — never rendered, anywhere, not even as Unsorted (it has a
//       real sub_cat_id; Unsorted is keyed on sub_cat_id IS NULL specifically). A footing total that
//       counts a value with no rendered row backing it is the same failure class AC3's coverage-
//       divergence guard exists to close, reached from the opposite direction. `groups` is now the
//       UNION: the canonical four, in `CAT_GROUP_ORDER`'s fixed order, then any OTHER Cat actually
//       present among the caller's asset-element Sub-Cats, appended (alphabetically — a rendering
//       judgment call, not a ratified requirement, same footing as the collapsed row's display-order
//       choice below). This is what makes NonReAllocationTable.svelte's own `groupsToRender()`
//       "unexpected group" append-and-log path (SELF-239 frontend, 2026-08-20) REACHABLE: pre-round-2
//       the server could never emit a group outside the four, so that client-side path was dead code
//       from this module's own output, however correctly written.
//   (b) REAL ESTATE, excluded EXPLICITLY at `assetSubCatIds`, not by riding 076's flag. Pre-round-2
//       Real Estate never appeared in `marketValueRows` only because `subcatMarketValue.ts` calls 076
//       with `p_include_real_estate: false` — a DIFFERENT module's parameter, not a predicate this
//       module asserts about itself. `assetSubCatIds` now excludes Real Estate explicitly (`element
//       = 'asset' AND cat != 'Real Estate'`), so this module's own row-set/denominator agreement no
//       longer depends on 076's flag continuing to be called the way it is today — if that flag's
//       default or call site ever changed, this module's own predicate still holds. The §2.1.5
//       composition's Total Non-RE anchor also excludes Real Estate (Architect-verified), so the
//       footing anchor this module targets is unaffected either way.
//
// Consumes the shared `subcatMarketValue.ts` helper (076 rollup + planning_target read) and adds
// this surface's OWN row-set logic on top: a FULL enumeration of the caller's asset-ELEMENT
// Sub-Cats (so a zero-held, zero-target seeded Sub-Cat still renders — AC2), the twelve US-equity
// Sub-Cats collapsed into one computed "US - Sector Diversified" row (AC2a/AC5 — carried forward
// from SELF-238, unchanged), the derived Unsorted row when 076 emits its unclassified row (AC2c —
// also unchanged; that row has no `element` to filter on and is always included, both in the row
// set and in TotalNonRE), and the four %/$ ratio columns per AC3/AC6 plus the always-present
// $Alloc.
//
// WHY A SEPARATE `user_taxonomy` READ, ON TOP OF THE 076 RPC: 076 returns one row per Sub-Cat the
// caller HOLDS VALUE IN — a zero-held Sub-Cat is simply absent from its return (076's own
// contract). AC2's "zero-held+zero-target seeded Sub-Cats still render with zeros" requires the
// FULL catalog, not just the held subset, so this module reads the caller's OWN
// `pfin.user_taxonomy` (direct-owner RLS) separately, NOW INCLUDING `element` (085), and
// LEFT-merges 076's market_value onto it (absent → 0) — the same "supabase-js has no cross-table
// server LEFT JOIN across independently-RLS'd tables" shape pendingSymbols.ts / navComposition.ts
// already established.
//
// SEC CARRY-FORWARD (2026-08-20, binding): a stray liability-element `planning_target` row CAN
// exist — SELF-242/N7-A is render-only enforcement on the editor; the write endpoint deliberately
// has no element check. This module's %Target join cannot let such a row re-enter the row set or
// the denominator BY CONSTRUCTION: `rowFor` is only ever invoked for ids drawn from
// `assetTaxonomyRows` (element = 'asset'), so a liability Sub-Cat's id is never looked up in
// `targetBySubCatId` here — its target simply has no row to attach to in this render. TotalNonRE
// never reads `targetBySubCatId` at all (it is market-value-only), so a stray target row cannot
// affect the denominator either, independent of the row-set guard.
//
// Fail-soft (mirrors subcatMarketValue.ts / navComposition.ts): any read error degrades to
// `{ data: null, ok: false }` — logged, never thrown.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { loadSubcatMarketValueAndTargets, type SubcatMarketValueRow } from './subcatMarketValue';
import { US_EQUITY_SUB_CAT_SET, US_SECTOR_DIVERSIFIED_LABEL } from './usEquitySubCats';

/** The fixed §2.2.2 Cat-group header order (PRD §2.2.2 / SELF-239 AC1) — the CANONICAL four,
 *  rendered first and in this order. FOUR members as of SELF-239 — 'Liabilities' DROPPED
 *  (assets-only ruling: Liabilities is not §2.2.2 domain and must not render here, in the row set
 *  OR the denominator). Real Estate is never a member — excluded explicitly at `assetSubCatIds`
 *  (SEC HARDENING ROUND 2 above), so it never reaches this module's row-set enumeration at all.
 *
 *  ⚠ NOT THE FULL SET OF POSSIBLE `groups[]` KEYS as of SEC HARDENING ROUND 2 (a): if the caller's
 *  taxonomy holds an asset-element Sub-Cat under a Cat OUTSIDE this list, `computeNonReAllocation`
 *  still renders it — appended after these four, never dropped. This constant names the EXPECTED,
 *  ratified four; it is not a filter on what can appear.
 *
 *  EXPORTED (ADR-058 Decision 7) so the paired DB-Cat-set equality assertion imports THIS array
 *  rather than a hand-maintained copy — a copy could itself drift from what this module actually
 *  uses, which would make the assertion test its own duplicate instead of the real fail-open
 *  surface. See nonReAllocation.catGroupOrderEquality.server.test.ts, which post-SELF-239 derives
 *  its DB-side comparison set element-aware (`element = 'asset'`) rather than off the raw six-Cat
 *  set. */
export const CAT_GROUP_ORDER = ['Cash', 'Bonds', 'Marketable Securities', 'Alternatives'] as const;

/** The collapsed row's sort position within the Marketable Securities group: 100 is 041's `display_order` for
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
	/** AC6: null when TotalNonRE <= 0 — a ratio-derived column, UNSET rather than a stale/
	 *  misleading number when the denominator is degenerate. Also structurally null for the
	 *  Unsorted row regardless of TotalNonRE ("structurally empty": 074's sub_cat_id bigint NOT
	 *  NULL FK means no planning_target row can exist for a NULL-taxonomy key). Otherwise a real
	 *  stored target — including 0, which IS an assertable target (074/ADR-056), distinct from
	 *  null/unset. */
	pct_target: number | null;
	/** AC6: null when TotalNonRE <= 0 — SUPERSEDES the SELF-238 AC7 convention (0 at total=0),
	 *  which the shipped payload got wrong: a rendered 0 reads as "a real zero allocation,"
	 *  indistinguishable from an actual zero-percent holding, when the true state is "this ratio
	 *  is undefined; the denominator is non-positive." Never NaN/Infinity either state. */
	pct_alloc: number | null;
	/** AC6: null when TotalNonRE <= 0, same rationale as pct_alloc/pct_target. */
	dollar_target: number | null;
	/** NEVER null and NEVER gated by TotalNonRE — the raw market value this row holds, not a
	 *  ratio. Always present, per AC6. */
	dollar_alloc: number;
	/** AC6: null when TotalNonRE <= 0. Also structurally null for the Unsorted row (see
	 *  pct_target). */
	dollar_realloc: number | null;
};

export type AllocationCatGroup = {
	/** `string`, NOT `(typeof CAT_GROUP_ORDER)[number]` — widened at SEC HARDENING ROUND 2 (a).
	 *  `groups[]` is a UNION (the canonical four plus any other Cat the caller's asset-element
	 *  taxonomy actually holds), so a group's `cat` is not guaranteed to be one of the four literal
	 *  values any more. Matches the client mirror's own type ($lib/nonre-allocation.ts), which was
	 *  already `string` — the client side never assumed the narrower union. */
	cat: string;
	rows: AllocationRow[];
	/** SELF-239 AC4: Σ this group's rows' dollar_alloc. Always present, mirroring dollar_alloc's
	 *  own always-present contract — a raw sum, not a ratio, so TotalNonRE's sign/value never
	 *  gates it. EVERY rendered group's subtotal (canonical four PLUS any appended Cat) plus
	 *  `unsorted`'s dollar_alloc (if present) foot to `total_non_re` exactly, by construction: all
	 *  are sums over the same element='asset'-minus-Real-Estate-or-Unsorted partition of the same
	 *  076 rows (see computeNonReAllocation's `assetSubCatIds`) — this is now STRUCTURALLY true
	 *  (every asset-element row lands in SOME group, canonical or appended; none can be silently
	 *  dropped), not merely true of the seed vocabulary as it stands today (SEC HARDENING ROUND 2). */
	dollar_alloc_subtotal: number;
	/** SELF-239 AC4: this group's subtotal as a % of TotalNonRE — same AC6 null-when-nonpositive
	 *  gating as every other ratio-derived column. */
	pct_alloc_subtotal: number | null;
};

export type NonReAllocation = {
	/** The canonical four (`CAT_GROUP_ORDER`) always present first, in that fixed order — never
	 *  omitted for being empty (at V1 scale a provisioned caller's full taxonomy always populates
	 *  every seeded Cat, and AC2 does not ask for empty-group omission the way 051's composition
	 *  groups do). MAY carry ADDITIONAL groups after those four, one per any OTHER Cat the caller's
	 *  asset-element taxonomy holds (SEC HARDENING ROUND 2 (a)) — not expected against the current
	 *  seed, but never silently dropped if the vocabulary grows. */
	groups: AllocationCatGroup[];
	/** Present iff 076 emitted its unclassified row (AC2c) — never a zero-valued placeholder. */
	unsorted: AllocationRow | null;
	/** SELF-239 AC3: Σ market_value over every 076 row that is EITHER the Unsorted row (no
	 *  element to filter on — always included) OR classified by the caller's OWN taxonomy as
	 *  element = 'asset' AND NOT Real Estate. NOT every 076 row unfiltered any more (that was the
	 *  SELF-238 shape; 076 returns BOTH elements by design — see this file's header — and
	 *  unfiltered summation silently counted a liability-cash-route row (081) in the denominator).
	 *  Equals the §2.1.5 composition's Total Non-RE at the same p_as_of, exactly — the AC4 footing
	 *  anchor. */
	total_non_re: number;
};

export type NonReAllocationResult = { data: NonReAllocation | null; ok: boolean };

/** One caller-owned Sub-Cat, as read from `pfin.user_taxonomy` directly (NOT through 076) — the
 *  full-enumeration source AC2's zero-render requirement needs. Carries BOTH elements (085) —
 *  this module, not the read, is what narrows to asset-only (AC2/AC3). */
export type TaxonomySubCatRow = {
	id: number;
	cat: string;
	sub_cat: string;
	display_order: number | null;
	/** NOT NULL, CHECK-constrained ('asset' | 'liability') since migration 085 (ADR-058 Decision
	 *  3). This is the predicate SELF-239's rework filters the row set AND the denominator on —
	 *  see `assetSubCatIds` in computeNonReAllocation. */
	element: 'asset' | 'liability';
};

/** AC6: a ratio-derived column is null, not 0 or NaN, whenever TotalNonRE <= 0 — the denominator
 *  is degenerate and no percentage is DEFINED, let alone computable. Percent scale (×100) applied
 *  by the caller of this helper via its own local total_non_re, matching every call site below. */
function ratioPercentOrNull(marketValue: number, totalNonRe: number): number | null {
	return totalNonRe > 0 ? (marketValue / totalNonRe) * 100 : null;
}

/** AC6: the three total-derived (non-percent) ratio columns share one gate — computed together so
 *  a caller can't accidentally null one and not the others. `totalPositive` is passed in rather
 *  than re-derived, so every call site in one compute() invocation reads the same boolean. */
function targetDerivedColumns(
	targetPercent: number,
	marketValue: number,
	totalNonRe: number,
	totalPositive: boolean
): Pick<AllocationRow, 'pct_target' | 'dollar_target' | 'dollar_realloc'> {
	if (!totalPositive) return { pct_target: null, dollar_target: null, dollar_realloc: null };
	const dollar_target = (targetPercent / 100) * totalNonRe;
	return { pct_target: targetPercent, dollar_target, dollar_realloc: dollar_target - marketValue };
}

/**
 * Pure compute core — no I/O, deterministic, unit-testable without a DB (pendingSymbols.ts's
 * `computePendingIds` precedent). Takes the caller's full taxonomy catalog (both elements), 076's
 * raw rows (both elements), and the planning_target map; returns the fully-shaped, assets-only
 * §2.2.2 table (SELF-239 AC1–AC4/AC6).
 */
export function computeNonReAllocation(
	taxonomyRows: ReadonlyArray<TaxonomySubCatRow>,
	marketValueRows: ReadonlyArray<SubcatMarketValueRow>,
	targetBySubCatId: ReadonlyMap<number, number>
): NonReAllocation {
	// AC2/AC3 — THE SINGLE PREDICATE SOURCE. Every id in this Set is a Sub-Cat the caller's OWN
	// taxonomy classifies as element='asset' AND NOT Real Estate (SEC HARDENING ROUND 2 (b) —
	// excluded HERE, explicitly, rather than relying on 076 being called with
	// p_include_real_estate:false in a different module). Both the row set (via assetTaxonomyRows
	// below) and TotalNonRE (via the reduce below) derive from THIS Set, built from this ONE
	// taxonomy read — not two independently-filtered copies. That is the "same-query predicate"
	// route AC3 offers (vs. a paired Σ assertion the caller would ship separately): coverage
	// divergence between the row set and the denominator is structurally unreachable here, not
	// merely tested for.
	const assetSubCatIds = new Set(
		taxonomyRows.filter((t) => t.element === 'asset' && t.cat !== 'Real Estate').map((t) => t.id)
	);

	// AC3: TotalNonRE sums every 076 row whose sub_cat_id is the Unsorted key (null — no element
	// to filter on, always included, per AC3's explicit instruction) OR is in assetSubCatIds. 076
	// itself returns BOTH elements (085's catalog comment on fn_subcat_market_value: the producer
	// cannot filter on element without breaking the seam invariant Σ fn_subcat_market_value(as_of,
	// true) = fn_compute_nav(as_of); that comment names THIS module as the intended consumer of
	// the predicate). GUARD: the predicate lives here, never inside the RPC. In practice 076 never
	// returns a Real Estate row anyway (called with p_include_real_estate:false elsewhere), but
	// this reduce does not rely on that — assetSubCatIds already excludes Real Estate on its own.
	const total_non_re = marketValueRows.reduce((sum, r) => {
		if (r.sub_cat_id === null) return sum + Number(r.market_value);
		return assetSubCatIds.has(r.sub_cat_id) ? sum + Number(r.market_value) : sum;
	}, 0);
	const totalPositive = total_non_re > 0;

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
		return {
			kind: 'sub_cat',
			sub_cat_id: id,
			cat,
			sub_cat,
			pct_alloc: ratioPercentOrNull(market_value, total_non_re),
			dollar_alloc: market_value,
			...targetDerivedColumns(target_percent, market_value, total_non_re, totalPositive)
		};
	}

	// AC2: the row set is the caller's element='asset'-minus-Real-Estate Sub-Cats (Real Estate is
	// already excluded at assetSubCatIds — SEC HARDENING ROUND 2 (b); no second, separate Cat-name
	// filter is applied here any more), MINUS the twelve US-equity Sub-Cats (folded into the
	// collapsed row below, not individual rows). Liabilities-element rows never reach this point
	// at all — they are outside assetSubCatIds, never inside it.
	const assetTaxonomyRows = taxonomyRows.filter((t) => assetSubCatIds.has(t.id));
	const regularTaxonomyRows = assetTaxonomyRows.filter((t) => !US_EQUITY_SUB_CAT_SET.has(t.sub_cat));

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
	// formulas, using that summed target_percent exactly like any other row's; all four ratio
	// columns null together per AC6 when TotalNonRE <= 0 (targetDerivedColumns/ratioPercentOrNull).
	const usEquityTaxonomyRows = assetTaxonomyRows.filter((t) => US_EQUITY_SUB_CAT_SET.has(t.sub_cat));
	const collapsedMarketValue = usEquityTaxonomyRows.reduce(
		(sum, t) => sum + (marketValueBySubCatId.get(t.id) ?? 0),
		0
	);
	const collapsedTargetPercent = usEquityTaxonomyRows.reduce(
		(sum, t) => sum + Number(targetBySubCatId.get(t.id) ?? 0),
		0
	);
	const collapsedRow: AllocationRow = {
		kind: 'us_sector_diversified',
		sub_cat_id: null,
		cat: 'Marketable Securities',
		sub_cat: US_SECTOR_DIVERSIFIED_LABEL,
		pct_alloc: ratioPercentOrNull(collapsedMarketValue, total_non_re),
		dollar_alloc: collapsedMarketValue,
		...targetDerivedColumns(collapsedTargetPercent, collapsedMarketValue, total_non_re, totalPositive)
	};
	(
		rowsByCat.get('Marketable Securities') ??
		rowsByCat.set('Marketable Securities', []).get('Marketable Securities')!
	).push(collapsedRow);
	displayOrderById.set(-1, US_SECTOR_DIVERSIFIED_DISPLAY_ORDER); // synthetic id for the sort below

	// AC4: per-group subtotal is a raw Σ of dollar_alloc — never gated by TotalNonRE's sign,
	// mirroring dollar_alloc's own always-present contract. pct_alloc_subtotal derives from the
	// SAME ratioPercentOrNull gate as every row-level percent column. Shared by both the canonical
	// and any appended group below, so the two paths cannot compute a subtotal differently.
	function buildGroup(cat: string): AllocationCatGroup {
		const rows = (rowsByCat.get(cat) ?? []).slice();
		rows.sort((a, b) => {
			const da = displayOrderById.get(a.sub_cat_id ?? -1) ?? 0;
			const db = displayOrderById.get(b.sub_cat_id ?? -1) ?? 0;
			return da - db;
		});
		const dollar_alloc_subtotal = rows.reduce((s, r) => s + r.dollar_alloc, 0);
		return {
			cat,
			rows,
			dollar_alloc_subtotal,
			pct_alloc_subtotal: ratioPercentOrNull(dollar_alloc_subtotal, total_non_re)
		};
	}

	// SEC HARDENING ROUND 2 (a): `groups` is the UNION of the canonical four (always present, in
	// CAT_GROUP_ORDER's fixed order, even if empty) and any OTHER Cat actually present in
	// `rowsByCat` — a Cat that reached regularTaxonomyRows (so it is genuinely asset-element,
	// non-US-equity) but is not one of the four. `rowsByCat` is fully drained here: every key it
	// holds ends up in EXACTLY ONE group, canonical or appended, so no asset-element row can be
	// counted in `total_non_re` while having no rendered row anywhere — the failure this hardening
	// closes. Appended Cats are sorted alphabetically — a rendering judgment call (their order is
	// not ratified by any AC), not a claim about which is more "important."
	const knownCats = new Set<string>(CAT_GROUP_ORDER);
	const canonicalGroups: AllocationCatGroup[] = CAT_GROUP_ORDER.map((cat) => buildGroup(cat));
	const unexpectedCats = [...rowsByCat.keys()].filter((cat) => !knownCats.has(cat)).sort();
	const unexpectedGroups: AllocationCatGroup[] = unexpectedCats.map((cat) => buildGroup(cat));
	const groups: AllocationCatGroup[] = [...canonicalGroups, ...unexpectedGroups];

	// AC2c/AC3: Unsorted carries %Alloc/$Alloc only — target cells are structurally null, never
	// 0 (0 would assert "a real zero target", which is impossible for a row with no sub_cat_id).
	// %Alloc itself now follows AC6 (null at TotalNonRE <= 0) via ratioPercentOrNull, same as every
	// other row.
	const unsorted: AllocationRow | null =
		unsortedMarketValue === null
			? null
			: {
					kind: 'unsorted',
					sub_cat_id: null,
					cat: null,
					sub_cat: 'Unsorted',
					pct_target: null,
					pct_alloc: ratioPercentOrNull(unsortedMarketValue, total_non_re),
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

	// POST-084: no `.eq('domain', 'asset')` filter — `user_taxonomy` is the storage-classification
	// table only (ADR-058 Decision 1's split moved every cashflow row out), so the unfiltered read
	// already is the full catalog AC2 needs. POST-085: `element` rides along — this module's own
	// compute core (computeNonReAllocation), not this read, is what narrows to asset-only, so the
	// read itself stays unconditional beyond the column list, same discipline as taxonomy.ts's
	// loadAssetSubCats.
	const { data: taxonomyRows, error } = await supabase
		.schema('pfin')
		.from('user_taxonomy')
		.select('id, cat, sub_cat, display_order, element');
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
