// cashflowContributors.ts — server-side read + pure compute for the SELF-258 §2.3.2 per-row
// (Sub-Cat) staleness indicator. Backend-owned server source (ARCH §4.1 allowlist).
//
// Calls Architect's `099` pfin.fn_cashflow_contributors(p_as_of date) — a SECURITY INVOKER
// contributor MAP with NO staleness verdict (099's own SHAPE 3 ruling, inherited from `086`: a
// DB-side is_stale boolean collapses three states into two and fails OPEN). The verdict is
// computed HERE, app-side, by consuming the SAME ratified pipeline SELF-330 already built and
// QA-verified for §2.2.2 — never re-derived:
//   `resolveStaleAccountIds()` (navComposition.ts, EXPORTED at SELF-330) resolves the caller's
//   `046` stale linked_source_id set down to `pfin.account.account_id` — the SAME bridge
//   nonReAllocation.ts's own per-Sub-Cat fold uses, reused VERBATIM (not forked).
//   The Kleene-OR tri-state fold below mirrors nonReAllocation.ts's `subCatIsStale`/`foldIsStale`
//   exactly: TRUE dominates; else UNKNOWN dominates FALSE; a `staleAccountIds === null` root-
//   unknown short-circuits BEFORE any per-key work, never a partial per-row mix.
//
// ⚠ THE ONE ADDITION THIS MODULE MAKES ON TOP OF THAT PATTERN: 099's `account_name IS NULL`
// signal. 099's own contract: a NULL `account_name` means the caller's LEFT JOIN could not see
// that contributor's `pfin.account` row (V1-dormant — see 099's own header for the revival
// condition), so its staleness is UNRESOLVABLE regardless of what `resolveStaleAccountIds` says
// about that `account_id`. `resolveStaleAccountIds` queries the SAME RLS-fenced `pfin.account`
// relation, so it could not see that row either — a bare "not in the returned stale set" would
// silently read as FRESH, which is the exact fail-open 099's LEFT JOIN exists to prevent one hop
// upstream. This module folds an unresolvable-identity contributor to UNKNOWN on `account_name`
// ALONE, before `staleAccountIds` is ever consulted for that contributor. `fn_subcat_contributors`
// (SELF-330's own primitive) carries no `account_name` column and has no equivalent branch to
// mirror — this is new, not copied.
//
// SCOPE: §2.3.2 (the cross-account rollup) ONLY, per SELF-258's team-lead ruling recorded in 099's
// own R3 (2026-09-03, F/CTO-reversible at PR review) — the §2.3.3 per-account drill-down's per-row
// indicator is RULED OFF: every drill-down row is folded from items of ONE account (split children
// carry the split PARENT's account_id — `093` rule 2), so a per-row indicator there is provably
// CONSTANT across every row and carries no per-row information. That surface keeps its existing
// account-level badge and does not call this module. A future author finding the drill-down not
// consuming this map per-row is looking at that ruling, not at unfinished wiring.
//
// KEYING: the (cat, sub_cat) STRING pair — not `sub_cat_id`. `093`'s own rendered row
// (`CashflowSectionRow`, cashflowCrossAccountRollup.ts) carries no `sub_cat_id` at all, only
// `sub_cat: string` inside a `CashflowSection` keyed by `cat` — that is the ONLY key the rendered
// row exposes to match against. This mirrors 099's own P1 parity property exactly, which is stated
// over the same pair, restricted to `sub_cat_id IS NOT NULL AND cat IN ('Revenue','Expense')` — the
// restriction `computeCashflowRowStaleness` applies when building the map (see below): the
// UNCLASSIFIED contributor set (`sub_cat_id IS NULL`) and the V1-dormant third-taxonomy state
// (`sub_cat_id NOT NULL` with `cat`/`sub_cat` both NULL — 099's own header) are both excluded,
// because NEITHER corresponds to a Sub-Cat row the rollup ever renders.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';

/** One raw `099` tuple, as it arrives from the RPC. `sub_cat_id` / `account_id` are bigint columns
 *  (number | string per the SELF-199 convention every other §2.x contributor read already
 *  applies) — this module only ever compares `account_id` via `String(...)`, never numerically. */
export type CashflowContributorRow = {
	cat: string | null;
	sub_cat: string | null;
	sub_cat_id: number | string | null;
	account_id: number | string;
	account_name: string | null;
};

/** Per-(cat, sub_cat)-row staleness verdict, computed app-side — mirrors `AllocationRow.is_stale`'s
 *  own tri-state contract VERBATIM (NEVER `undefined`): `true` = at least one contributing account
 *  is in the caller's `046` stale set (Kleene-OR fold, TRUE dominates); `false` = every contributor
 *  resolved to confirmed-not-stale; `null` = UNKNOWN — the root `046` read (or this bridge) was
 *  itself unresolved, OR at least one contributing account's identity could not be resolved (099's
 *  `account_name IS NULL` signal) and therefore could not be cleared.
 *  `staleAccountNames` is AC5's tooltip source: the DISTINCT, sorted `account_name`s of every
 *  contributor that resolved CONFIRMED-stale. Always `[]` when `is_stale` is not `true` — an
 *  unresolvable contributor is, by definition, one this module cannot name, so it never appears
 *  here even when it is what forced `is_stale` to `null`. */
export type CashflowRowStaleness = {
	is_stale: boolean | null;
	staleAccountNames: string[];
};

/** `rowStaleness[cat][sub_cat]` — a MISSING key, at EITHER level, means the same thing an explicit
 *  `{ is_stale: null, staleAccountNames: [] }` would: this leg could not be resolved for that row
 *  (the root staleness read was unknown, or the contributor/fold read itself failed). Consumers
 *  MUST default a missing lookup to UNKNOWN, never to fresh — mirrors `data.staleness ??
 *  UNKNOWN_STALENESS`'s own default-to-unknown convention at the Svelte layer (see
 *  CashflowRollupTable.svelte, which threads this same discipline). A plain `Record`, not a `Map`
 *  — this crosses the loader/PageData boundary and every other §2.x per-row payload in this
 *  codebase (AllocationRow.is_stale, UsEquityRow.is_stale) is likewise plain JSON-serializable
 *  data, never a Map/Set handed to a component. */
export type CashflowRowStalenessMap = Record<string, Record<string, CashflowRowStaleness>>;

/** Zero-footprint default — a caller whose leg failed returns this UNCHANGED, never a partially
 *  populated map. Exported so a consumer's own fallback never has to hand-construct `{}`. */
export const EMPTY_CASHFLOW_ROW_STALENESS: CashflowRowStalenessMap = {};

/**
 * Load the caller's raw `099` contributor tuples, RLS-scoped via the per-request client. Returns
 * `null` on any read failure (never partial data) — mirrors `loadSubCatContributors`'s own
 * posture exactly. The caller degrades every row's `is_stale` to UNKNOWN in that case by never
 * calling `computeCashflowRowStaleness` at all (see cash-flow/+page.server.ts).
 */
export async function loadCashflowContributors(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<CashflowContributorRow[] | null> {
	const { data, error } = await supabase
		.schema('pfin')
		.rpc('fn_cashflow_contributors', { p_as_of: asOf });

	if (error) {
		console.error('[cashflowContributors] fn_cashflow_contributors failed:', error.message);
		return null;
	}
	return (data ?? []) as CashflowContributorRow[];
}

/** ⚠ `account_name IS NULL` folds to UNKNOWN BEFORE `staleAccountIds` is ever consulted for that
 *  contributor — see the module header's LEFT-JOIN note. This is the ONE branch with no
 *  nonReAllocation.ts precedent to mirror; every other line here is that file's `subCatIsStale`
 *  pattern applied to a (cat, sub_cat) group instead of a bare sub_cat_id. Dominance order is
 *  TRUE > UNKNOWN > FALSE, identical to nonReAllocation.ts's own fold — a row with both a
 *  confirmed-stale contributor AND an unresolvable one still reports `true` (with the confirmed
 *  name), never `null`. */
function foldRow(
	rows: ReadonlyArray<CashflowContributorRow>,
	staleAccountIds: ReadonlySet<string>
): CashflowRowStaleness {
	let anyUnknown = false;
	const staleNames = new Set<string>();
	for (const c of rows) {
		if (c.account_name === null) {
			anyUnknown = true;
			continue;
		}
		if (staleAccountIds.has(String(c.account_id))) {
			staleNames.add(c.account_name);
		}
	}
	if (staleNames.size > 0) return { is_stale: true, staleAccountNames: [...staleNames].sort() };
	if (anyUnknown) return { is_stale: null, staleAccountNames: [] };
	return { is_stale: false, staleAccountNames: [] };
}

/**
 * Pure compute core — no I/O, deterministic, unit-testable without a DB (mirrors
 * `computeNonReAllocation`'s own precedent). `staleAccountIds` is the SAME tri-state
 * `resolveStaleAccountIds` return every other §2.1/§2.2 per-row fold already consumes: a known
 * (possibly empty) Set, or `null` when the root `046` read or the bridge itself was
 * unknown/failed — in which case this function returns the EMPTY map (`{}`), never a partial
 * result. Every row then degrades to UNKNOWN via `CashflowRowStalenessMap`'s own documented
 * missing-key convention.
 */
export function computeCashflowRowStaleness(
	contributors: ReadonlyArray<CashflowContributorRow>,
	staleAccountIds: ReadonlySet<string> | null
): CashflowRowStalenessMap {
	if (staleAccountIds === null) return EMPTY_CASHFLOW_ROW_STALENESS;

	// Group by the (cat, sub_cat) STRING pair — see the module header's KEYING note for why this,
	// not sub_cat_id, is the match key, and why sub_cat_id IS NULL / the third-taxonomy state are
	// both excluded here (neither is a row the rollup ever renders).
	const groups = new Map<string, Map<string, CashflowContributorRow[]>>();
	for (const c of contributors) {
		if (c.sub_cat_id === null || c.cat === null || c.sub_cat === null) continue;
		let bySubCat = groups.get(c.cat);
		if (!bySubCat) {
			bySubCat = new Map();
			groups.set(c.cat, bySubCat);
		}
		const list = bySubCat.get(c.sub_cat);
		if (list) list.push(c);
		else bySubCat.set(c.sub_cat, [c]);
	}

	const result: CashflowRowStalenessMap = {};
	for (const [cat, bySubCat] of groups) {
		const catOut: Record<string, CashflowRowStaleness> = {};
		for (const [subCat, rows] of bySubCat) {
			catOut[subCat] = foldRow(rows, staleAccountIds);
		}
		result[cat] = catOut;
	}
	return result;
}
