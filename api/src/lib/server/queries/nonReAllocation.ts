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
//       default or call site ever changed, this module's own predicate still holds. ⚠ CORRECTION
//       (Architect, 2026-08-20): an earlier draft of this note claimed "§2.1.5's Total Non-RE
//       anchor also excludes Real Estate (Architect-verified)" — that attribution was wrong; it
//       was never actually verified, and having now been measured, it does not hold as stated.
//       051's total_non_re filters on `pfin.account.account_type not in ('real_estate',
//       'liability')`; this module excludes by TAXONOMY CAT (`element` + `cat`). Two different
//       columns, which coincide only where a holding classified under Cat 'Real Estate' also sits
//       in an account typed `real_estate` — nothing constrains that pairing to always hold. This
//       change's own justification needs nothing from §2.1.5 (row set and denominator agree at
//       THIS consumer by construction, independent of any anchor), so the fix above stands
//       unchanged; the anchor-agreement question itself is unasserted and routed to BACKLOG §7.24.
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
//
// PER-ROW STALENESS (SELF-330, per §2.2.2's own per-row staleness tint AC — the PRD's own
// per-Sub-Cat sibling of navComposition.ts's per-ACCOUNT `is_stale` join). Architect's
// `pfin.fn_subcat_contributors(p_as_of, p_include_real_estate)` returns DISTINCT
// (sub_cat_id, account_id) pairs — SECURITY INVOKER, RLS-scoped through the SAME per-request
// client every other read in this module uses. `account_id -> linked_source_id -> the 046 stale
// set` is resolved by calling navComposition.ts's `resolveStaleAccountIds` VERBATIM (exported for
// this reuse at SELF-330) — the SAME bridge, not a second copy, so the two surfaces can never
// disagree about which accounts are currently stale.
//
// FOLD SEMANTICS (binding, AC11 doc comment):
//   - A Sub-Cat's is_stale is the Kleene-OR fold over its contributing accounts' is_stale: TRUE
//     dominates (any one stale account taints the whole Sub-Cat — Cash's wide contributor set
//     tinting on ONE stale institution is BY DESIGN, not a bug to "fix"); else UNKNOWN dominates
//     FALSE (an account whose own staleness could not be resolved must not be silently treated as
//     confirmed-fresh — the SELF-220/229 precedent this whole file's staleness.ts sibling exists
//     to enforce); else FALSE only when every contributor resolved to confirmed-not-stale, or the
//     Sub-Cat has NO contributors at all (vacuous OR — nothing to be stale about).
//   - The WHOLE fold collapses to UNKNOWN uniformly, for every row, whenever the caller's root
//     `046` read was itself unknown OR the contributor/account bridge read failed — mirrors
//     navComposition.ts's "skip the join entirely" posture exactly; never a per-row mix of known
//     and unknown in that case.
//   - The "US - Sector Diversified" collapsed row (AC5) OR-folds the SAME way across its twelve
//     underlying real Sub-Cat ids' individual folds — it is not a separate contributor lookup, it
//     is the Kleene-OR of the twelve real answers.
//   - The Unsorted row (076's NULL-taxonomy row) keys on `sub_cat_id IS NULL` — matched by a plain
//     JS `Map` lookup on a literal `null` key (SameValueZero equality already implements
//     IS-NULL-shaped matching; no separate sentinel or `=== undefined` fallback is used, which
//     would silently miss the row instead of matching it).
//
// PRODUCER CONTRACT (binding, Frontend-measured — nonre-allocation.ts's own hazard note): every
// row's `is_stale` is ALWAYS one of `true | false | null` — NEVER `undefined`. A Sub-Cat this
// module has not (yet) resolved a fold for still gets an explicit `null`, computed by the SAME
// fold function as every other row — there is no code path that leaves the field unset.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';
import { loadSubcatMarketValueAndTargets, type SubcatMarketValueRow } from './subcatMarketValue';
import { US_EQUITY_SUB_CAT_SET, US_SECTOR_DIVERSIFIED_LABEL } from './usEquitySubCats';
import { resolveStaleAccountIds } from './navComposition';

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
	/** SELF-330: tri-state, mirroring NavCompositionAccount.is_stale's own contract — NEVER
	 *  `undefined` (binding producer contract; see module header). `true` = at least one
	 *  contributing account is in the caller's `046` stale set (Kleene-OR fold, TRUE dominates).
	 *  `false` = every contributing account resolved to confirmed-not-stale, OR this Sub-Cat has no
	 *  contributing accounts at all (vacuous fold). `null` = UNKNOWN — the root `046` read was
	 *  itself unknown, or the contributor/account bridge read failed; propagates uniformly to every
	 *  row in that case, never mixed with a resolved value in the same table. */
	is_stale: boolean | null;
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
	 *  ⚠ AC4 names §2.1.5's Total Non-RE as this figure's footing ANCHOR, and their agreement is
	 *  INTENDED BUT UNASSERTED — do not read it as a guarantee. `051` partitions by
	 *  `pfin.account.account_type not in ('real_estate','liability')`; this figure partitions by
	 *  TAXONOMY (`element` + Cat). Two different columns, coinciding only where a Cat-'Real Estate'
	 *  holding also sits in a `real_estate`-typed account, which nothing constrains. Measured and
	 *  retracted at SEC HARDENING ROUND 2 (b) above; no watcher exists, booked at BACKLOG §7.24
	 *  item 15. Nothing in THIS module depends on the anchor holding — its row set and denominator
	 *  agree by construction, independently. */
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
	targetBySubCatId: ReadonlyMap<number, number>,
	// SELF-330: `fn_subcat_contributors`'s DISTINCT (sub_cat_id, account_id) pairs, grouped by
	// sub_cat_id — a literal `null` key holds the Unsorted row's contributors (076's NULL-taxonomy
	// row has no sub_cat_id to key on; matched by IS-NULL, i.e. a real `null` Map key, never a
	// sentinel or `=== undefined` fallback). `staleAccountIds` is the SAME tri-state
	// `resolveStaleAccountIds` return navComposition.ts already establishes: a known (possibly
	// empty) Set, or `null` when the root `046` read or the bridge join itself was unknown/failed —
	// in which case every row's fold below returns `null` uniformly, never a partial result.
	// Both default to the "unknown, nothing supplied" state — every existing call site (including
	// every pre-SELF-330 test in this suite) that does not pass these two arguments gets `is_stale:
	// null` on every row, never a silent `false`. This is a DEFAULT, not a different code path: it
	// runs through the exact same short-circuit `staleAccountIds === null` branch a real "root read
	// unknown" caller hits (see subCatIsStale below) — so a caller that forgets to thread staleness
	// degrades the same way a caller that explicitly couldn't determine it does.
	subCatAccountIds: ReadonlyMap<number | null, ReadonlySet<string>> = new Map(),
	staleAccountIds: ReadonlySet<string> | null = null
): NonReAllocation {
	// SELF-330 fold core. `subCatIsStale` answers for ONE Sub-Cat key (a real id, or `null` for
	// Unsorted); `foldIsStale` Kleene-ORs across several ids (the US-Sector-Diversified collapsed
	// row's twelve). Both obey the SAME dominance order: true > unknown > false. Vacuous (no
	// contributors, or an empty id list) resolves to `false` — nothing to be stale about — UNLESS
	// the root/bridge itself is unknown, which short-circuits every key to `null` before any
	// per-contributor lookup happens at all (mirrors navComposition.ts's "skip the join entirely").
	function subCatIsStale(subCatId: number | null): boolean | null {
		if (staleAccountIds === null) return null;
		const contributors = subCatAccountIds.get(subCatId);
		if (!contributors || contributors.size === 0) return false;
		for (const accountId of contributors) {
			if (staleAccountIds.has(accountId)) return true;
		}
		return false;
	}
	function foldIsStale(subCatIds: ReadonlyArray<number>): boolean | null {
		let anyUnknown = false;
		for (const id of subCatIds) {
			const s = subCatIsStale(id);
			if (s === true) return true; // TRUE dominates — short-circuit
			if (s === null) anyUnknown = true;
		}
		return anyUnknown ? null : false;
	}

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
			...targetDerivedColumns(target_percent, market_value, total_non_re, totalPositive),
			is_stale: subCatIsStale(id)
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
		...targetDerivedColumns(collapsedTargetPercent, collapsedMarketValue, total_non_re, totalPositive),
		// AC11: the collapsed row is NOT a second contributor lookup (it has no sub_cat_id of its
		// own to key on) — it Kleene-ORs the twelve real underlying Sub-Cat ids' OWN folds.
		is_stale: foldIsStale(usEquityTaxonomyRows.map((t) => t.id))
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
					dollar_realloc: null,
					// AC11: keyed on sub_cat_id IS NULL — subCatIsStale(null) matches contributor
					// pairs fn_subcat_contributors returned with a NULL sub_cat_id, never by coercing
					// this row's own (structurally null) id into an equality lookup against a real id.
					is_stale: subCatIsStale(null)
				};

	return { groups, unsorted, total_non_re };
}

/**
 * Load the caller's §2.2.2 Non-RE allocation table, RLS-scoped via the per-request client. `asOf`
 * must already be a validated `ZoneResolvedAsOf` (see schemas/allocation.ts's
 * `resolveAllocationAsOf` — this function does no parsing of its own, mirroring
 * navComposition.ts's `loadNavComposition` signature).
 *
 * `staleLinkedSourceIds` (SELF-330 — mirrors `loadNavComposition`'s own parameter of the same
 * name VERBATIM, including its tri-state contract): the CALLER's already-loaded `046`
 * stale_items[], as a set of `linked_source_id` strings. `null` means the caller's own root `046`
 * read was itself UNKNOWN — this function skips BOTH the contributor RPC and the account bridge
 * entirely and every row's `is_stale` comes back `null` (see computeNonReAllocation's fold). A
 * known (possibly empty) Set runs the join normally.
 */
export async function loadNonReAllocation(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf,
	staleLinkedSourceIds: ReadonlySet<string> | null
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

	// SELF-330: a metadata-only (staleness) failure must NEVER take down this table's actual
	// $/% data — mirrors loadStaleness()/loadNavComposition()'s own "fail-soft, but never to
	// confirmed-fresh" posture. `subCatAccountIds` and `staleAccountIds` start at their UNKNOWN
	// defaults (empty map / null) and are only upgraded to real values once BOTH the contributor
	// RPC and the account bridge have succeeded — a failure in either one leaves `staleAccountIds`
	// at `null`, which forces every row's fold to `null` via computeNonReAllocation's own
	// short-circuit, never a partial or silently-fresh table.
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
		data: computeNonReAllocation(
			(taxonomyRows ?? []) as TaxonomySubCatRow[],
			substrate.rows,
			substrate.targetBySubCatId,
			subCatAccountIds,
			staleAccountIds
		),
		ok: true
	};
}

/**
 * SELF-330: load the caller's OWN (sub_cat_id, account_id) contributor pairs from Architect's
 * `pfin.fn_subcat_contributors(p_as_of, p_include_real_estate)` — SECURITY INVOKER, DISTINCT
 * pairs, RLS-scoped through the SAME per-request client every other read in this module uses.
 * `p_include_real_estate: false` mirrors subcatMarketValue.ts's own `fn_subcat_market_value` call
 * convention — this module is assets-only, non-RE throughout (SEC HARDENING ROUND 2 (b) above),
 * and the contributor map must partition the SAME way the row set does, or a Sub-Cat's fold could
 * draw on accounts outside its own domain.
 *
 * Returns `null` on any read failure (never partial data) — the caller degrades every row's
 * `is_stale` to UNKNOWN in that case, the same posture staleness.ts / navComposition.ts already
 * apply to their own primitives. A `null` sub_cat_id key holds the Unsorted row's contributors
 * (076's own NULL-taxonomy row has no sub_cat_id to key on).
 */
async function loadSubCatContributors(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<ReadonlyMap<number | null, ReadonlySet<string>> | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_subcat_contributors', { p_as_of: asOf, p_include_real_estate: false });
	if (error) {
		console.error('[nonReAllocation] fn_subcat_contributors failed:', error.message);
		return null;
	}

	const bySubCat = new Map<number | null, Set<string>>();
	for (const row of (data ?? []) as Array<{
		sub_cat_id: number | null;
		account_id: number | string;
	}>) {
		const key = row.sub_cat_id ?? null;
		const accountId = String(row.account_id); // SELF-199 bigint -> string convention
		const set = bySubCat.get(key);
		if (set) set.add(accountId);
		else bySubCat.set(key, new Set([accountId]));
	}
	return bySubCat;
}
