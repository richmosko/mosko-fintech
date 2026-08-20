// us-equity-allocation.ts — browser-safe types + presentation helpers for the §2.2.3 US Equity
// sub-allocation table (SELF-241). NON-server module (ships to the browser) — mirrors
// nonre-allocation.ts's own established pattern: UsEquityAllocationTable stays purely
// presentational over the types + helpers here.
//
// MIRROR of Backend's `$lib/server/queries/usEquityAllocation.ts` (SELF-240, verified live at
// authoring time, 2026-08-20) — this file hand-copies that module's row/total SHAPE only, never
// its I/O; browser code cannot import `$lib/server/**` (SvelteKit's build-time guard refuses it
// regardless of `import type`). Same hand-kept-copy / drift-risk posture as nonre-allocation.ts /
// allocation-taxonomy.ts: flagged to Backend at hand-off, no automated cross-check exists
// client-side today.
//
// Row ORDER/SET is NOT re-declared here — `allocation-taxonomy.ts`'s `US_EQUITY_SUB_CATS` is
// already the single client-side source of truth for the twelve labels (SELF-242 uses it too);
// this file only adds the numeric row/total SHAPE on top of that.
//
// Sec F-2 (PR #520 review, recorded per team-lead ruling — Option B for now, disposition open to
// Architect/Backend): §2.2.2's and §2.2.3's SERVER compute cores carry DIFFERENT degenerate-state
// contracts, and this file's render helpers are NOT interchangeable with nonre-allocation.ts's for
// that reason:
//   - `computeNonReAllocation` (§2.2.2, nonReAllocation.ts) guards on ONE denominator (`total_non_re
//     > 0`, a domain guard — "covering the negative case too", its own words) and nulls all four
//     ratio columns TOGETHER. Its client-side `fmtRatioPct`/`fmtRatioUsd` gate (`ratioColumnsUnset`)
//     is therefore belt-and-suspenders on an already-correct payload — redundant defense, not the
//     only layer.
//   - `computeUsEquityAllocation` (§2.2.3, usEquityAllocation.ts) guards on TWO INDEPENDENT
//     denominators, each `=== 0` (a NaN guard, not a domain guard, and NOT `<= 0`): `pct_alloc`
//     nulls on `totalUsEquity === 0` alone; `pct_target`/`dollar_target`/`dollar_realloc` null on a
//     SEPARATE `sumTargets === 0`. They do not null together, and a NEGATIVE `totalUsEquity` passes
//     both guards un-gated — the server payload can carry real (non-null) ratio values at a
//     degenerate or negative total.
// Consequence: `fmtPct`/`fmtUsd` below taking the denominator and re-applying `ratioColumnsUnset`
// is LOAD-BEARING here — the ONLY thing forcing '—' at a degenerate total, not a second check on an
// already-guarded payload. A future author who copies THIS file's shape rather than
// nonre-allocation.ts's, or vice versa, needs to know the two source contracts differ; recorded
// here so that isn't rediscovered as a live bug a second time.

import { ratioColumnsUnset } from '$lib/nonre-allocation';

export interface UsEquityRow {
	sub_cat_id: number | null;
	cat: 'Marketable Securities';
	sub_cat: string;
	pct_target: number | null;
	pct_alloc: number | null;
	dollar_target: number | null;
	dollar_alloc: number;
	dollar_realloc: number | null;
	/** OPTIONAL, tri-state — forward-declared per nonre-allocation.ts's `AllocationRow.is_stale`
	 *  precedent (ADR-013 D1 "illustrative, not exhaustive"). UNDEFINED today: Backend's
	 *  usEquityAllocation.ts (SELF-240) has no per-row staleness join yet (same gap
	 *  nonReAllocation.ts has for §2.2.2) — this field is forward-declared so the row-tint
	 *  machinery in UsEquityAllocationTable.svelte is ready the moment that join lands (flagged
	 *  to Backend/team-lead at hand-off, same as §2.2.2's own open item). Render boundary
	 *  normalizes `undefined` to UNKNOWN via the SHARED `staleDisplayState()` helper
	 *  (reused from nonre-allocation.ts, not reimplemented) — never silently "fresh." */
	is_stale?: boolean | null;
}

export interface UsEquityTotalRow {
	dollar_alloc: number;
	pct_alloc: number | null;
	pct_target: number | null;
	dollar_target: number | null;
	dollar_realloc: number | null;
}

export interface UsEquityAllocation {
	/** Exactly twelve, in `US_EQUITY_SUB_CATS` canonical order (allocation-taxonomy.ts). */
	rows: UsEquityRow[];
	total: UsEquityTotalRow;
}

/** AC4: a Sub-Cat is the "zero-allocation, still present" case exactly when it holds nothing AND
 *  carries no target share — PRD's own two-part test ("market_value = 0 AND pct_target = 0"),
 *  not dollar_alloc alone (a zero-held row WITH a nonzero target is a real gap, not a quiet row).
 *  `pct_target === 0` deliberately excludes the `null` (guard) case — a null target means "no
 *  target basis to renormalize against at all" (AC5 ii), a different state from "this Sub-Cat's
 *  own target share is genuinely zero", and de-emphasizing every row during that degenerate state
 *  would defeat AC4's "present, not hidden" intent for the one case it actually names. */
export function isZeroAllocSubCat(row: UsEquityRow): boolean {
	return row.dollar_alloc === 0 && row.pct_target === 0;
}

/** AC5-equivalent render helper for the %-scale ratio columns. Sec F-1 (PR #520 review): takes the
 *  US Equity denominator (`allocation.total.dollar_alloc`) and re-applies `ratioColumnsUnset()`
 *  (REUSED from nonre-allocation.ts, not a second predicate) on TOP OF the `null` check — see this
 *  file's own header (F-2 note) for why that second layer is load-bearing here rather than
 *  redundant: the server's two split `=== 0` guards can leave a ratio column non-null at a
 *  degenerate or negative total, and this is the ONLY place that gets closed. `value` is already
 *  on the 0–100 scale. */
export function fmtPct(value: number | null, totalUsEquity: number): string {
	if (value === null || ratioColumnsUnset(totalUsEquity)) return '—';
	return `${value.toFixed(2)}%`;
}

/** AC5-equivalent render helper for the $-scale columns ($Target / $ReAlloc) — same Sec F-1
 *  denominator gate as `fmtPct` above, otherwise a plain currency format (neutral, no
 *  sign-coloring — matches nonre-allocation.ts's own `fmtRatioUsd`, and the ACTUAL shipped §2.2.2
 *  treatment: AC5 there reversed the pre-SELF-238 spec to neutral-only, no pos/neg color anywhere;
 *  see UsEquityAllocationTable.svelte's own header for the flagged discrepancy against this
 *  ticket's brief). */
export function fmtUsd(value: number | null, totalUsEquity: number, usd: Intl.NumberFormat): string {
	if (value === null || ratioColumnsUnset(totalUsEquity)) return '—';
	return usd.format(value);
}
