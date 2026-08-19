// subcatMarketValue.ts — the SHARED 076-consumer join logic for the §2.2.2 Non-RE allocation
// table (SELF-238) and the §2.2.3 US Equity sub-allocation (SELF-240). Backend-owned server
// surface (ARCH §4.1 allowlist). One low-level helper, two consumers — mirrors 076's own header
// ("Shared primitive: §2.2.2 Non-RE allocation (SELF-238) and §2.2.3 US Equity sub-allocation
// (SELF-240) consume it at different filters").
//
// Two RLS-scoped reads through the SAME per-request anon/authenticated client, INVOKER
// throughout, never service_role:
//   (1) `pfin.fn_subcat_market_value(p_as_of, p_include_real_estate=false)` — Architect's `076`,
//       SECURITY INVOKER + STABLE. Always called with p_include_real_estate=false: NEITHER V1
//       consumer of this shared helper ever wants Real Estate included (§2.2.2 explicitly
//       excludes it; §2.2.3 is a pure Marketable-Securities drill-down — the twelve
//       US-equity Sub-Cats, all under the Cat ADR-058 Decision 7 renamed 'Equity' →
//       'Marketable Securities' (082), to remove the collision with the accounting
//       element Equity and with 028's cashflow class Equity). Not parameterized on that flag —
//       hardcoding it here removes a footgun (an accidental `true` call) rather than mirroring
//       076's full signature for its own sake; if a THIRD consumer ever needs RE included, that
//       is a new, explicit call, not a silently-widened default on this one.
//   (2) `pfin.planning_target` — direct-owner RLS (074), read RAW (sub_cat_id, target_percent)
//       for the caller. supabase-js has no server-side LEFT JOIN across two independently-RLS'd
//       tables (pendingSymbols.ts / navComposition.ts's own precedent), so the "LEFT-join
//       planning_target on sub_cat_id, coalesce absent → 0" the ACs describe is expressed as two
//       reads + a caller-side Map lookup, not a SQL join.
//
// Fail-soft (mirrors navComposition.ts / pendingSymbols.ts): any read error degrades the WHOLE
// result to `{ ok: false }` — logged, never thrown. A financial-calculation, multi-tenant read
// surface (076's own JOINT-REVIEW-MANDATORY note) must not throw an unhandled error into a page
// render; the caller decides how to present "allocation unavailable".

import type { SupabaseClient } from '@supabase/supabase-js';
import type { ZoneResolvedAsOf } from '$lib/server/time/asOf';

/** One row as `076` returns it. `sub_cat_id`/`cat`/`sub_cat` are ALL null together for the
 *  unclassified row (076 R2) — never null independently. */
export type SubcatMarketValueRow = {
	sub_cat_id: number | null;
	cat: string | null;
	sub_cat: string | null;
	market_value: number;
};

export type SubcatMarketValueResult =
	| {
			ok: true;
			/** Raw 076 return, verbatim — including the unclassified row if present. Every
			 *  consumer's own TotalNonRE-style total MUST sum over this array unfiltered (076's
			 *  own exact-footing contract depends on not dropping any row). */
			rows: SubcatMarketValueRow[];
			/** The caller's OWN planning_target rows, sub_cat_id -> target_percent. A missing key
			 *  means "no row" (ADR-056 unset-is-row-absent) — callers coalesce to 0 themselves at
			 *  the point they know whether 0 or `null` is the correct absent-value representation
			 *  for their own output shape (e.g. the Unsorted row structurally cannot have one). */
			targetBySubCatId: Map<number, number>;
	  }
	| { ok: false; rows: []; targetBySubCatId: Map<number, number> };

export async function loadSubcatMarketValueAndTargets(
	supabase: SupabaseClient,
	asOf: ZoneResolvedAsOf
): Promise<SubcatMarketValueResult> {
	const { data: rpcRows, error: rpcErr } = await supabase
		.schema('pfin')
		.rpc('fn_subcat_market_value', { p_as_of: asOf, p_include_real_estate: false });
	if (rpcErr) {
		console.error('[subcatMarketValue] fn_subcat_market_value failed:', rpcErr.message);
		return { ok: false, rows: [], targetBySubCatId: new Map() };
	}

	const { data: targetRows, error: targetErr } = await supabase
		.schema('pfin')
		.from('planning_target')
		.select('sub_cat_id, target_percent');
	if (targetErr) {
		console.error('[subcatMarketValue] planning_target read failed:', targetErr.message);
		return { ok: false, rows: [], targetBySubCatId: new Map() };
	}

	const targetBySubCatId = new Map<number, number>();
	for (const row of (targetRows ?? []) as Array<{ sub_cat_id: number; target_percent: number }>) {
		targetBySubCatId.set(row.sub_cat_id, row.target_percent);
	}

	return {
		ok: true,
		rows: ((rpcRows ?? []) as Array<Record<string, unknown>>).map((r) => ({
			sub_cat_id: (r.sub_cat_id as number | null) ?? null,
			cat: (r.cat as string | null) ?? null,
			sub_cat: (r.sub_cat as string | null) ?? null,
			market_value: Number(r.market_value)
		})),
		targetBySubCatId
	};
}
