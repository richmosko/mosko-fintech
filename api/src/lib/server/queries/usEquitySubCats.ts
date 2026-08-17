// usEquitySubCats.ts — the twelve US-equity Sub-Cat labels, DDL-copied verbatim from migration
// 041 (pfin.taxonomy_default seed, cat = 'Equity'). Backend-owned server surface (ARCH §4.1
// allowlist). Single source of truth for BOTH consumers so the list can never drift between
// them:
//   - SELF-238 (§2.2.2 Non-RE allocation): EXCLUDES these twelve from its per-Sub-Cat row set
//     and folds their market_value + target_percent into the single computed "US - Sector
//     Diversified" row (076/238 AC2a — no taxonomy row exists for that row; none is created).
//   - SELF-240 (§2.2.3 US Equity sub-allocation): renders EXACTLY these twelve, in this order,
//     as its own row set (240 AC1).
//
// Verified against supabase/migrations/041_taxonomy_default_and_provisioning.sql (display_order
// 100-210) at authoring time — read live if this ever needs re-verifying, never trust a copy of
// a copy. All twelve are cat = 'Equity'.

/** Display order matches the 041 seed (100, 110, ..., 210) — the array order below IS the
 *  §2.2.3 row order (240 AC1 lists them in this exact sequence). */
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

/** Fast membership test — used by SELF-238's row-set filter (exclude) and, later, SELF-240's
 *  (include). A Set, not a re-scan of the array, since both call sites test membership per row
 *  of the caller's full taxonomy enumeration. */
export const US_EQUITY_SUB_CAT_SET: ReadonlySet<string> = new Set(US_EQUITY_SUB_CATS);

/** The synthetic collapsed-row label (076/238 AC2a) — has no `sub_cat_id`; not a member of
 *  US_EQUITY_SUB_CATS (it replaces the twelve, it is not a thirteenth). */
export const US_SECTOR_DIVERSIFIED_LABEL = 'US - Sector Diversified';
