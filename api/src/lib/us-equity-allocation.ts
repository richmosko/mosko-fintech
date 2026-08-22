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
// RENDER-GATE STATUS (SELF-332 / ADR-061, 2026-08-21) — quoted VERBATIM from ADR-061 Decision 6
// (DECISIONS.md), which supersedes the Sec F-2 divergence note this header used to carry. §2.2.2's
// and §2.2.3's SERVER compute cores no longer diverge — `computeUsEquityAllocation`
// (usEquityAllocation.ts) now carries §2.2.2's own two-gate-group contract (`valuePositive` /
// `targetsPositive`, both `> 0`), and the client gate below is reclassified accordingly:
//
// > After this alignment, `fmtPct` and `fmtUsd` in `api/src/lib/us-equity-allocation.ts` are
// > **belt-and-suspenders, not load-bearing** — the same standing `fmtRatioPct` / `fmtRatioUsd`
// > already hold in `api/src/lib/nonre-allocation.ts`. `ratioColumnsUnset(total)` is `total <= 0`;
// > the server now nulls every ratio column in exactly that state, and in one further state the
// > client gate does not detect and does not need to (`sumTargets` non-positive at a positive
// > total), because the server's `null` already satisfies the `value === null` half of the same
// > expression. The client gate is therefore a strict subset of the server contract and can never
// > again be the only layer forcing `'—'`. It is RETAINED as redundant defense against a stale or
// > mis-built server payload, not removed. Neither helper changes signature or behaviour: the only
// > client-side edit this ADR requires is the header prose.
//
// See ADR-061 for the full aligned degenerate-state contract and the reachable-states table.

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
	/** REQUIRED, tri-state — mirrors `AllocationRow.is_stale`'s own SELF-330 tightening
	 *  (nonre-allocation.ts). LIVE as of SELF-243 (2026-08-20, Backend delivery, verified against
	 *  usEquityAllocation.ts in this same worktree — MD5 675b3ad3a91f068bef3f2a6ce1ddbf64):
	 *  `computeUsEquityAllocation` now folds `subCatAccountIds` through `staleAccountIds` into an
	 *  explicit `true | false | null` on every row, reusing `nonReAllocation.ts`'s
	 *  `loadSubCatContributors` bridge (now exported) rather than forking it — never `undefined`.
	 *  Tightened from optional to required to match: the compiler is the watcher for a future call
	 *  site that forgets to supply it, same discipline as the §2.2.2 tightening.
	 *
	 *  ⚠ NOT YET WIRED end-to-end: `loadUsEquityAllocation`'s new `staleLinkedSourceIds` param
	 *  still defaults to `null` at every call site — `allocation/us-equity/+page.server.ts` does
	 *  not yet pass a real value (holding, per team-lead, on the open AC3/AC4 tooltip-account-name
	 *  ruling). Until that route wire lands, every row's `is_stale` resolves to `null` (honest
	 *  UNKNOWN), never a false "fresh" — same posture as the pre-tightening dormant state, just
	 *  from the loader boundary instead of the type. Render boundary still normalizes a stray
	 *  `undefined` to UNKNOWN via the SHARED `staleDisplayState()` helper (reused from
	 *  nonre-allocation.ts, not reimplemented) as defense-in-depth. */
	is_stale: boolean | null;
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
