// nonre-allocation.ts — browser-safe types + presentation helpers for the §2.2.2 Non-RE
// allocation table (SELF-239). NON-server module (ships to the browser) — mirrors
// nav-composition.ts's / allocation-taxonomy.ts's own established pattern: NonReAllocationTable
// stays purely presentational over the types + helpers here.
//
// MIRROR of Backend's `$lib/server/queries/nonReAllocation.ts` (SELF-239 rework) — this file
// hand-copies that module's row/group/table SHAPE only, never its I/O; browser code cannot import
// `$lib/server/**` (SvelteKit's build-time guard refuses it regardless of `import type`). Same
// hand-kept-copy / drift-risk posture as `allocation-taxonomy.ts`: flagged to Backend at hand-off,
// no automated cross-check exists client-side today.
//
// ⚠ RENDER-LAYER GUARD, NOT A GAP-FILLER (corrected at commit — see below). The render layer here
// (`ratioColumnsUnset` + `fmtRatio*`) ignores whatever raw value a ratio column carries and forces
// the AC6 "unset" treatment whenever `total_non_re <= 0`, computed from `total_non_re` directly,
// never from a per-cell raw value. As of this file's original authoring, Backend's own
// `nonReAllocation.ts` (as it existed on `main`, pre-SELF-239) had NOT yet implemented AC6 for the
// same case — that gap is CLOSED on Backend's actual SELF-239 branch (`pct_alloc` is
// `number | null`, gated on `total_non_re > 0`, negative totals included), so this render-layer
// guard is now REDUNDANT with the server's own behavior rather than covering a live gap. Left in
// place anyway: two independent implementations of the same AC6 rule — one server-side, one
// render-side, neither trusting the other — is a reasonable belt-and-suspenders posture on a
// financial-correctness surface, and removing it buys nothing. The four ratio fields stay typed
// nullable here regardless, matching the server type field-for-field.

/** AC1 (ratified 2026-08-20): the table renders EXACTLY these four Cat-groups, in this order.
 *  Real Estate is never a member (076's own exclusion). Liabilities is DELIBERATELY EXCLUDED —
 *  this MATCHES nonReAllocation.ts's own `CAT_GROUP_ORDER` as of SELF-239 (also four values,
 *  Liabilities dropped entirely — corrected at commit: an earlier draft of this comment described
 *  the pre-SELF-239 five-value form). `groupsToRender` still filters BY NAME rather than assuming
 *  the payload never carries a Liabilities entry — defensive robustness against a malformed or
 *  legacy-shaped payload, not a behavior the current contract actually exercises. */
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
	/** null ONLY for the Unsorted row (structurally empty — no target can exist for a NULL
	 *  taxonomy key). Every other row carries a real number, including 0. */
	pct_target: number | null;
	/** See the file-header note: the render layer treats this as authoritative only when
	 *  total_non_re > 0, independent of what Backend's own contract already enforces. */
	pct_alloc: number | null;
	dollar_target: number | null;
	/** NEVER null, NEVER gated by AC6 — a plain market-value sum, meaningful at any total. */
	dollar_alloc: number;
	dollar_realloc: number | null;
	/** OPTIONAL, tri-state — mirrors NavCompositionLeaf.is_stale (SELF-229's own precedent).
	 *  UNDEFINED today: Backend's nonReAllocation.ts does not yet join per-row staleness the way
	 *  navComposition.ts does for §2.1.5 leaves — this field is forward-declared so the row-tint
	 *  machinery in NonReAllocationTable.svelte is ready the moment that join lands (AC11's
	 *  row-tint half; flagged to Backend/team-lead at hand-off). `undefined`/`false` render
	 *  identically (nothing); `null` renders the quiet "unknown" treatment; `true` renders the tag
	 *  + row tint. */
	is_stale?: boolean | null;
}

export interface AllocationCatGroup {
	cat: string;
	rows: AllocationRow[];
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
 *  even against a malformed payload. */
export function groupsToRender(groups: AllocationCatGroup[]): AllocationCatGroup[] {
	const byCat = new Map(groups.map((g) => [g.cat, g] as const));
	return NONRE_TABLE_CAT_ORDER.map((cat) => byCat.get(cat) ?? { cat, rows: [] });
}

/** AC6: ratio columns (%Target / %Alloc / $Target / $ReAlloc) render as UNSET whenever the
 *  denominator is non-positive — $Alloc is exempt. Computed from `total_non_re` directly, never
 *  from a per-cell raw value, so this holds regardless of what number a given field happens to
 *  carry (see the file-header note). */
export function ratioColumnsUnset(total_non_re: number): boolean {
	return total_non_re <= 0;
}

/** AC6 render helper for the four %-scale ratio columns. `value` is already on the 0–100 scale
 *  (nonReAllocation.ts's own convention — "Percent scale (×100) applied by the caller"). */
export function fmtRatioPct(value: number | null, total_non_re: number): string {
	if (value === null || ratioColumnsUnset(total_non_re)) return '—';
	return `${value.toFixed(2)}%`;
}

/** AC6 render helper for the two $-scale ratio columns ($Target / $ReAlloc). Deliberately NOT
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

export interface GroupSubtotal {
	pct_target: number;
	pct_alloc: number;
	dollar_target: number;
	dollar_alloc: number;
	dollar_realloc: number;
}

/** AC4: per-Cat-group subtotal — a plain sum over the group's rows. Every row inside a rendered
 *  Cat-group (never the standalone Unsorted row, which nonReAllocation.ts keeps structurally
 *  outside every group's `rows`) carries non-null pct_target/dollar_target/dollar_realloc — null
 *  is reserved for the Unsorted row alone — so the `?? 0` below is belt-and-suspenders, not a
 *  path this function expects to exercise on a well-formed payload. NOTE: Backend's own payload
 *  (as of SELF-239) ALSO ships precomputed `dollar_alloc_subtotal` / `pct_alloc_subtotal` per
 *  group — this function recomputes independently rather than consuming those fields. Flagged at
 *  hand-off as a simplification opportunity, not fixed here (this file's own call).
 */
export function groupSubtotal(rows: AllocationRow[]): GroupSubtotal {
	return rows.reduce(
		(acc, r) => ({
			pct_target: acc.pct_target + (r.pct_target ?? 0),
			pct_alloc: acc.pct_alloc + (r.pct_alloc ?? 0),
			dollar_target: acc.dollar_target + (r.dollar_target ?? 0),
			dollar_alloc: acc.dollar_alloc + r.dollar_alloc,
			dollar_realloc: acc.dollar_realloc + (r.dollar_realloc ?? 0)
		}),
		{ pct_target: 0, pct_alloc: 0, dollar_target: 0, dollar_alloc: 0, dollar_realloc: 0 }
	);
}
