// allocation-taxonomy.ts — CLIENT-SIDE mirror of the §2.2.2 Non-RE Cat-group order + the
// twelve US-equity Sub-Cat labels (SELF-242 planning-target-editor).
//
// MIRROR of two Backend server modules, kept as one client copy rather than two so both
// facts travel together (a client that grouped by one and excluded by the other would
// drift silently):
//   - $lib/server/queries/nonReAllocation.ts's exported `CAT_GROUP_ORDER` — the fixed
//     §2.2.2 Cat-group header order (Cash / Bonds / Marketable Securities / Alternatives
//     / Liabilities; Real Estate is never a member — excluded independently below).
//   - $lib/server/queries/usEquitySubCats.ts's `US_EQUITY_SUB_CATS` / `US_EQUITY_SUB_CAT_SET`
//     — the twelve Sub-Cat labels SELF-238 folds into one collapsed row and SELF-240
//     renders as its own §2.2.3 US-Equity row set, IN THIS ORDER.
//
// WHY THE EDITOR NEEDS BOTH, DIFFERENTLY FROM SELF-238: SELF-238's read surface EXCLUDES
// the twelve from its per-Sub-Cat rows and folds them into a synthetic "US - Sector
// Diversified" readout with no sub_cat_id — there is no row to edit. SELF-242 edits
// %Target PER SUB-CAT (per pfin.planning_target's own grain, 074), so the twelve get
// their OWN input fields — just rendered under a distinct "US Equity" sub-section
// (AC2) rather than inline with Marketable Securities' other Sub-Cats (UNKNOWN,
// ExUS-Developed_Market, ExUS-Emerging_Market), which the editor's Non-RE section still
// groups under the Marketable Securities Cat header exactly like SELF-238/240 do.
//
// Both source lists are themselves verified against supabase/migrations/041 (seed) +
// 082 (the 'Equity' → 'Marketable Securities' rename — LABEL ONLY, no Sub-Cat renamed,
// no display_order changed) at authoring time. Real Estate is excluded here the same way
// nonReAllocation.ts excludes it: a separate, independent `cat !== 'Real Estate'` filter
// on the editor's own full-taxonomy read, since 076's own `p_include_real_estate=false`
// exclusion does not reach a client-side re-filter.
//
// DRIFT RISK, STATED RATHER THAN HOPED AWAY: this is a hand-kept copy, not an import —
// browser code cannot import $lib/server/**. If Backend's CAT_GROUP_ORDER or
// US_EQUITY_SUB_CATS ever changes (a Cat added/removed/renamed, a Sub-Cat added to the
// twelve), this file goes stale silently unless someone greps for it. Flagged to Backend
// at hand-off; no automated equality assertion exists on the client side today (the
// server side has one — nonReAllocation.catGroupOrderEquality.server.test.ts — but it
// cannot reach into browser-only code to compare against this file).

/** The fixed §2.2.2 Cat-group header order (PRD §2.2.2 / AC2). Real Estate is never a
 *  member — filtered out independently wherever this editor reads the caller's full
 *  taxonomy catalog. MIRROR of nonReAllocation.ts's `CAT_GROUP_ORDER` — keep verbatim. */
export const CAT_GROUP_ORDER = [
	'Cash',
	'Bonds',
	'Marketable Securities',
	'Alternatives',
	'Liabilities'
] as const;

export type NonReCat = (typeof CAT_GROUP_ORDER)[number];

/** Display order matches the 041 seed (100, 110, ..., 210) — the array order below IS the
 *  §2.2.3 row order (SELF-240 AC1 lists them in this exact sequence), and this editor's
 *  "US Equity" sub-section renders them in the same order for the same reason: one
 *  taxonomy, one row order, wherever it appears. MIRROR of usEquitySubCats.ts's
 *  `US_EQUITY_SUB_CATS` — keep verbatim. */
export const US_EQUITY_SUB_CATS: readonly string[] = [
	'US-01-Basic_Materials',
	'US-02-Telecom',
	'US-03-Consumer_Discretionary',
	'US-04-Consumer_Staples',
	'US-05-Energy',
	'US-06-Financials',
	'US-07-Health_Care',
	'US-08-Industrials',
	'US-09-Information_Technology',
	'US-10-Utilities',
	'US-Index-Non_Sector',
	'US-Growth-Non_Sector'
];

/** Fast membership test — mirrors usEquitySubCats.ts's `US_EQUITY_SUB_CAT_SET`. Used to
 *  split one Cat's Sub-Cats into "renders inline under its Cat group" (Marketable
 *  Securities' three non-US-equity Sub-Cats) vs "renders in the US Equity sub-section". */
export const US_EQUITY_SUB_CAT_SET: ReadonlySet<string> = new Set(US_EQUITY_SUB_CATS);

/** The Cat under which the US Equity sub-section nests (AC2: "under sub-section"). */
export const US_EQUITY_PARENT_CAT: NonReCat = 'Marketable Securities';
