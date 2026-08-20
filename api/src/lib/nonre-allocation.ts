// nonre-allocation.ts — browser-safe types + presentation helpers for the §2.2.2 Non-RE
// allocation table (SELF-239). NON-server module (ships to the browser) — mirrors
// nav-composition.ts's / allocation-taxonomy.ts's own established pattern: NonReAllocationTable
// stays purely presentational over the types + helpers here.
//
// MIRROR of Backend's `$lib/server/queries/nonReAllocation.ts` on `feature/self239-nonre-
// allocation-table` (commits a9ebf8e + dc033a1 — the SELF-239 rework, NOT YET on main as of this
// revision) — this file hand-copies that module's row/group/table SHAPE only, never its I/O;
// browser code cannot import `$lib/server/**` (SvelteKit's build-time guard refuses it regardless
// of `import type`). Same hand-kept-copy / drift-risk posture as `allocation-taxonomy.ts`:
// flagged to Backend at hand-off, no automated cross-check exists client-side today.
//
// REVISION NOTE: an earlier revision of this file, written against `main`'s pre-SELF-239
// `nonReAllocation.ts`, carried a "deliberate divergence" section describing a fake-zero /
// unguarded-negative-total conflict with AC6. Verified (2026-08-20) against the actual
// `feature/self239-nonre-allocation-table` tree, not the report describing it: both are FIXED on
// that branch — `pct_alloc`/`pct_target`/`dollar_target`/`dollar_realloc` are all `number | null`
// there, gated on `total_non_re > 0` (covers the negative case too), and `CAT_GROUP_ORDER` is
// genuinely 4 values (Liabilities dropped, not merely unrendered). This file's own ratio-gating
// (`ratioColumnsUnset` + `fmtRatio*`) is kept as belt-and-suspenders against the fixed server
// contract, not as a workaround for a live gap — see each function's own comment.

/** AC1 (ratified 2026-08-20): the table renders EXACTLY these four Cat-groups, in this order.
 *  Real Estate is never a member (076's own exclusion). MIRROR of nonReAllocation.ts's
 *  `CAT_GROUP_ORDER` on the SELF-239 branch, which is genuinely 4 values as of that rework —
 *  Liabilities is not merely excluded from rendering, it is absent from the backend's own
 *  `groups[]` payload entirely (assets-only via the `element` predicate, ADR-058 Decision 3). */
export const NONRE_TABLE_CAT_ORDER = [
	'Cash',
	'Bonds',
	'Marketable Securities',
	'Alternatives'
] as const;

export type NonReTableCat = (typeof NONRE_TABLE_CAT_ORDER)[number];

export type AllocationRowKind = 'sub_cat' | 'us_sector_diversified' | 'unsorted';

export interface AllocationRow {
	kind: AllocationRowKind;
	sub_cat_id: number | null;
	cat: string | null;
	sub_cat: string;
	/** AC6: null when TotalNonRE <= 0 (ratio-derived — see `targetDerivedColumns` on the server).
	 *  Also structurally null for the Unsorted row regardless of TotalNonRE (no sub_cat_id, so no
	 *  planning_target row can exist for it). Otherwise a real stored target, including 0. */
	pct_target: number | null;
	/** AC6: null when TotalNonRE <= 0 — never a fake-zero, never NaN/Infinity. */
	pct_alloc: number | null;
	/** AC6: null when TotalNonRE <= 0, same rationale as pct_target. */
	dollar_target: number | null;
	/** NEVER null, NEVER gated by AC6 — a plain market-value sum, meaningful at any total. */
	dollar_alloc: number;
	/** AC6: null when TotalNonRE <= 0. Also structurally null for the Unsorted row. */
	dollar_realloc: number | null;
	/** OPTIONAL, tri-state — mirrors NavCompositionLeaf.is_stale (SELF-229's own precedent).
	 *  UNDEFINED today: Backend's nonReAllocation.ts (SELF-239 branch) does not yet join per-row
	 *  staleness the way navComposition.ts does for §2.1.5 leaves — this field is forward-declared
	 *  so the row-tint machinery in NonReAllocationTable.svelte is ready the moment that join
	 *  lands (AC11's row-tint half; flagged to Backend/team-lead at hand-off).
	 *  `undefined`/`false` render identically (nothing); `null` renders the quiet "unknown"
	 *  treatment; `true` renders the tag + row tint. */
	is_stale?: boolean | null;
}

export interface AllocationCatGroup {
	cat: string;
	rows: AllocationRow[];
	/** SELF-239 AC4: server-authoritative Σ this group's rows' dollar_alloc. ALWAYS present — a
	 *  raw sum, never gated by TotalNonRE's sign. Consumed directly (not re-derived) so the
	 *  displayed subtotal can never diverge from the server's own footing arithmetic. */
	dollar_alloc_subtotal: number;
	/** SELF-239 AC4: server-authoritative group subtotal as a % of TotalNonRE — same AC6
	 *  null-when-nonpositive gating as every other ratio-derived column. Consumed directly. */
	pct_alloc_subtotal: number | null;
}

export interface NonReAllocation {
	groups: AllocationCatGroup[];
	unsorted: AllocationRow | null;
	total_non_re: number;
}

/** AC1: filter the backend's `groups[]` down to the four rendered Cat-groups, in
 *  NONRE_TABLE_CAT_ORDER's fixed order — never the payload's own array order, so a future backend
 *  re-order can't silently reorder the table. A Cat absent from the payload (defensive —
 *  nonReAllocation.ts's contract says every group is always present) renders as an empty group
 *  rather than being dropped from the header sequence, preserving AC1's "exactly four headers"
 *  even against a malformed payload. The backend's own `groups[]` is already exactly these four
 *  entries as of the SELF-239 rework, so this is now defense-in-depth (order + malformed-payload
 *  safety), not a name-based exclusion working around a 5th entry. */
export function groupsToRender(groups: AllocationCatGroup[]): AllocationCatGroup[] {
	const byCat = new Map(groups.map((g) => [g.cat, g] as const));
	return NONRE_TABLE_CAT_ORDER.map(
		(cat) => byCat.get(cat) ?? { cat, rows: [], dollar_alloc_subtotal: 0, pct_alloc_subtotal: null }
	);
}

/** AC6: ratio columns (%Target / %Alloc / $Target / $ReAlloc) render as UNSET whenever the
 *  denominator is non-positive — $Alloc is exempt. The SELF-239 server contract already nulls
 *  these fields on this exact gate (`total_non_re > 0`, covering the negative case too), so this
 *  is now a redundant re-check on an already-correct payload, kept as belt-and-suspenders rather
 *  than trusting a single boundary — this is the same class of bug (a fake-zero at a degenerate
 *  denominator) that shipped once already (SELF-238). */
export function ratioColumnsUnset(total_non_re: number): boolean {
	return total_non_re <= 0;
}

/** AC6 render helper for the %-scale ratio columns. `value` is already on the 0–100 scale
 *  (nonReAllocation.ts's own convention — "Percent scale (×100) applied by the caller"). */
export function fmtRatioPct(value: number | null, total_non_re: number): string {
	if (value === null || ratioColumnsUnset(total_non_re)) return '—';
	return `${value.toFixed(2)}%`;
}

/** AC6 render helper for the $-scale ratio columns ($Target / $ReAlloc). Deliberately NOT
 *  `signDisplay: 'exceptZero'` (NavCompositionTable's G/L formatter) — that '+/−' framing is
 *  reserved for ACTUAL performance (§5 fence 1); a plain Intl currency format already renders a
 *  negative $ReAlloc with an ordinary minus sign, which is the neutral treatment AC5 asks for. */
export function fmtRatioUsd(
	value: number | null,
	total_non_re: number,
	usd: Intl.NumberFormat
): string {
	if (value === null || ratioColumnsUnset(total_non_re)) return '—';
	return usd.format(value);
}

export interface GroupTargetSubtotal {
	pct_target: number;
	dollar_target: number;
	dollar_realloc: number;
}

/** AC4: the THREE target-side per-Cat-group subtotal columns the server does NOT precompute
 *  (dollar_alloc_subtotal/pct_alloc_subtotal ARE server-authoritative — read them directly off
 *  `AllocationCatGroup`, never via this function). A plain sum over the group's rows. Every row
 *  inside a rendered Cat-group (never the standalone Unsorted row, which nonReAllocation.ts keeps
 *  structurally outside every group's `rows`) carries non-null pct_target/dollar_target/
 *  dollar_realloc UNLESS TotalNonRE <= 0, in which case every row's own value is already null and
 *  this sums to 0 — the caller gates display via `ratioColumnsUnset`/`fmtRatio*`, never trusting
 *  a raw 0 from this function as "the ratio is defined." */
export function groupTargetSubtotal(rows: AllocationRow[]): GroupTargetSubtotal {
	return rows.reduce(
		(acc, r) => ({
			pct_target: acc.pct_target + (r.pct_target ?? 0),
			dollar_target: acc.dollar_target + (r.dollar_target ?? 0),
			dollar_realloc: acc.dollar_realloc + (r.dollar_realloc ?? 0)
		}),
		{ pct_target: 0, dollar_target: 0, dollar_realloc: 0 }
	);
}
