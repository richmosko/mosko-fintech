// cashflow-row-staleness.ts — browser-safe mirror of Backend's SELF-258 per-Sub-Cat staleness map
// ($lib/server/queries/cashflowContributors.ts). NON-server module (ships to the browser) — mirrors
// cashflow-rollup.ts's / nonre-allocation.ts's own established pattern: this file hand-copies the
// OUTPUT SHAPE of `computeCashflowRowStaleness`, never its I/O — browser code cannot import
// `$lib/server/**` (SvelteKit's build-time guard refuses it regardless of `import type`). Same
// hand-kept-copy / drift-risk posture as every other browser-safe mirror in this tree: flagged to
// Backend at hand-off, no automated cross-check exists client-side today.
//
// SCOPE: §2.3.2 (CashflowRollupTable) ONLY — the §2.3.3 per-account drill-down's per-row indicator
// is RULED OFF (099's own R3: every drill-down row is folded from items of ONE account, so a
// per-row indicator there is provably CONSTANT and carries no information; that surface keeps its
// existing section-level badge and never consumes this map). See cashflowContributors.ts's own
// module header for the full ruling — not re-litigated here.
//
// TRI-STATE NORMALIZATION IS REUSED, NOT REFORKED: `staleDisplayState()` (nonre-allocation.ts,
// SELF-330) already implements the EXACT `true → 'stale'` / `false → 'fresh'` / `null|undefined →
// 'unknown'` mapping this per-row marker needs — this module does not redeclare it.

import { staleDisplayState, type StaleDisplayState } from './nonre-allocation';

/** Mirrors `CashflowRowStaleness` (cashflowContributors.ts) verbatim: the app-side-computed
 *  tri-state verdict for one (cat, sub_cat) Sub-Cat row. `staleAccountNames` is AC5's tooltip
 *  source — the DISTINCT, sorted names of every CONFIRMED-stale contributor; always `[]` when
 *  `is_stale` is not `true` (an unresolvable contributor is one this map cannot name, even when it
 *  is what forced `is_stale` to `null`). */
export interface CashflowRowStaleness {
	is_stale: boolean | null;
	staleAccountNames: string[];
}

/** Mirrors `CashflowRowStalenessMap` (cashflowContributors.ts) verbatim: `map[cat][sub_cat]`. A
 *  MISSING key at EITHER level means the same thing an explicit `UNKNOWN_ROW_STALENESS` would —
 *  see `lookupCashflowRowStaleness` below, which is the ONLY sanctioned way to read this map (never
 *  a bare `map[cat]?.[sub_cat]` at a call site, so the missing-key-means-unknown convention cannot
 *  be forgotten at one render site and not another). */
export type CashflowRowStalenessMap = Record<string, Record<string, CashflowRowStaleness>>;

/** The UNKNOWN verdict — returned by `lookupCashflowRowStaleness` for any missing key, and the
 *  value a caller's own `data.cashflowRowStaleness ?? EMPTY_CASHFLOW_ROW_STALENESS_MAP` fallback
 *  resolves to on every lookup once the map itself is empty. Mirrors `UNKNOWN_STALENESS`'s own
 *  default-to-unknown convention at the section-badge grain — never a silent "fresh". */
export const UNKNOWN_ROW_STALENESS: CashflowRowStaleness = { is_stale: null, staleAccountNames: [] };

/** Zero-footprint default for the WHOLE map — mirrors `EMPTY_CASHFLOW_ROW_STALENESS`
 *  (cashflowContributors.ts) verbatim. Every lookup against `{}` resolves to
 *  `UNKNOWN_ROW_STALENESS` via `lookupCashflowRowStaleness`'s own missing-key handling — this is
 *  NOT a "confirmed fresh" default, matching `UNKNOWN_STALENESS` (never `EMPTY_STALENESS`) at the
 *  loader boundary. */
export const EMPTY_CASHFLOW_ROW_STALENESS_MAP: CashflowRowStalenessMap = {};

/** THE lookup helper — per the loader's own PROP CONTRACT note (cash-flow/+page.server.ts): a
 *  missing key at EITHER level (`map[cat]` absent, or `map[cat][sub_cat]` absent) means UNKNOWN,
 *  never fresh. Centralizing this in one function (rather than `map[cat]?.[sub_cat] ??
 *  UNKNOWN_ROW_STALENESS` inline at each render site) means the convention cannot be silently
 *  dropped at a future new call site. */
export function lookupCashflowRowStaleness(
	map: CashflowRowStalenessMap,
	cat: string,
	subCat: string
): CashflowRowStaleness {
	return map[cat]?.[subCat] ?? UNKNOWN_ROW_STALENESS;
}

/** The tri-state RENDER state for one row — reuses `staleDisplayState` (nonre-allocation.ts,
 *  SELF-330) verbatim rather than reforking the same `true→'stale'`/`false→'fresh'`/`null|
 *  undefined→'unknown'` mapping a second time. */
export function rowStaleDisplayState(rowStaleness: CashflowRowStaleness): StaleDisplayState {
	return staleDisplayState(rowStaleness.is_stale);
}

export type { StaleDisplayState };
