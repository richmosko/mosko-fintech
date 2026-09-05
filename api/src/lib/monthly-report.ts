// monthly-report.ts — browser-safe types + presentation helpers for the §2.6.1.b in-app monthly
// report render (SELF-354 / P2). NON-server module (ships to the browser) — mirrors the SHAPE of
// migration `110`'s CONTRACT block (`pfin.fn_render_monthly_report`) and migration `108`'s header
// row columns, verified against those files on `feature/self-345` @ be7aed6 — NOT a guess. Browser
// code cannot import `$lib/server/**`, so this is a hand-kept mirror; if the payload shape moves,
// this file needs a matching edit (same drift posture as nav-composition.ts / tax-decomposition.ts
// / tax-quarterly.ts's own mirrors).
//
// FROZEN vs LIVE (R1 (A) / AC2): a `final` (or `superseded`, never rendered — R10 A-8) report's
// `payload` is `monthly_report.rendered_payload` read back verbatim; a `draft` report's `payload`
// is the return of `pfin.fn_render_monthly_report(target_month, data_as_of)`, called live. EITHER
// WAY the shape below is identical — that is the entire point of R1: one render path, one payload
// shape, regardless of where it came from. `MonthlyReportView.svelte` (this ticket's shared
// template — also A5's PDF-composition entry point, R2 (C)) takes the union of the header ROW
// fields (this file's `MonthlyReportHeader`) and the PAYLOAD (`MonthlyReportPayload`) and does not
// care which path produced the payload.
//
// SECTION-TO-COMPONENT MAP (team-lead directive: reuse existing components; where a component
// takes live-loader props, add a payload-fed entry point rather than forking it):
//   account_holdings    -> NavCompositionTable.svelte, DIRECT reuse (payload shape IS `NavComposition`
//                          verbatim per 110's own comment: "carried VERBATIM").
//   nav_performance      -> PARTIAL direct reuse, per E16 (team-lead, closing 110 Finding 1 with
//                          Part 1's new as-of readers `fn_nav_delta_panel_as_of` /
//                          `fn_nav_reference_dates_as_of`). `delta_panel` / `reference_dates` are
//                          now ARRAYS whose field names match `NavDeltaPanelRow` /
//                          `NavReferenceDateRow` EXACTLY (verified against 110's own CTEs, not
//                          just its CONTRACT comment) — DIRECT reuse of NavDeltaPanel.svelte /
//                          NavReferenceDatesPanel.svelte, each already correct for a `null`-vs-
//                          real-array distinction and carrying no wrong "temporarily unavailable"
//                          copy risk now that these are real, permanently-threadable readers, not
//                          a structural gap. `series` / `series_inflation_adjusted` remain NOT
//                          reused: their FIELD NAMES still do not match `NavSeriesPoint`
//                          (`nav_value` vs `nav_nominal`), and NavHistoryChart is built for the
//                          LIVE page's own interactive granularity/date-range controls (`params`,
//                          `paramsError`) — controls that make no sense on a frozen, single-as-of
//                          report. This file's own `MonthlyReportNavSeriesInflationPoint` type +
//                          the minimal static table markup in MonthlyReportView.svelte render that
//                          half instead — flagged at hand-off (see that component's own header) as
//                          a Visual-Designer-worthy follow-up, not a silent gap. NavDeltaPanel's
//                          own `<h2>NAV Performance</h2>` is now THE section heading (AC1) — this
//                          file's template no longer renders a second one.
//   asset_allocation     -> NO direct reuse. NonReAllocationTable.svelte expects
//                          `{groups: [{cat, rows, dollar_alloc_subtotal, pct_alloc_subtotal}],
//                          unsorted, total_non_re}` — SERVER-authoritative per-group subtotals this
//                          payload's flat `rows[]` does not carry (asset_allocation has no
//                          `total_non_re` at all, so a % subtotal cannot be honestly computed
//                          client-side). This file's `groupAllocationByCat` mirrors
//                          tax-decomposition.ts's OWN precedent (`groupByCat`) — a pure
//                          presentational fold plus a PLAIN-ADDITION $ subtotal per group (not a
//                          money-path decision, same justification TaxDecompositionTable's header
//                          states for its own client-side Cat-grouping) — and stops there: no %
//                          subtotal is computed.
//   rebalancing_targets  -> NO existing component (P3, the commentary EDITOR, has not been built;
//                          nothing today renders these four columns read-only). New minimal
//                          plain-text display in MonthlyReportView.svelte — escaped once by
//                          Svelte's default interpolation (INV-1), line breaks via CSS
//                          `white-space: pre-wrap`, never `{@html}`.
//   cash_flow            -> CashflowRollupTable.svelte (rollup = cross_account_rollup, DIRECT reuse
//                          — field names match `CashflowCrossAccountRollup` exactly, including the
//                          nested `unclassified.count_ytd` that already drives AC4's "Partial — N
//                          items unclassified" footnote with NO new copy needed) +
//                          HistoricalExpendituresChart.svelte (points = historical_expenditures,
//                          DIRECT reuse — field names match `HistoricalExpenditurePoint` exactly).
//   estimated_taxes      -> TaxDecompositionTable.svelte + TaxQuarterlyTables.svelte, DIRECT reuse
//                          — `estimated_taxes` is `fn_compute_tax_liability`'s raw return
//                          (carried VERBATIM per 110), which already satisfies both components'
//                          existing prop shapes (`TaxLiabilitySlice` / `TaxQuarterlyLiability`)
//                          structurally, no reshaping. TaxDecompositionTable gained one new
//                          OPTIONAL prop (`capitalGainsUnavailableCopy`) for AC4's report-specific
//                          past-tense sentence — see that component's own header.
//
// P8 SLOTS, NAMED AND LEFT (team-lead directive: "staleness markers are P8's, leave a clearly
// named slot"): every reused component that REQUIRES a `staleness: StalenessData` or
// `cashflowRowStaleness: CashflowRowStalenessMap` prop is fed `UNKNOWN_STALENESS` /
// `EMPTY_CASHFLOW_ROW_STALENESS_MAP` here — NOT a live `loadStaleness()` read. AC7 states
// staleness markers are read LIVE at every render, composed OVER the frozen payload, and that P8
// owns them; wiring only the ONE slot NavCompositionTable happens to need (without P8's banner,
// the two-tier informational marker, or the other components P8's own AC touches) would ship
// partial, inconsistent staleness coverage on a Sec-joint-review-mandatory surface. `UNKNOWN`
// (never `EMPTY`) is deliberate: `EMPTY_STALENESS` is a claim ("confirmed healthy") this file has
// no basis to make; `UNKNOWN_STALENESS` renders the quiet "Staleness unknown" register these
// components already ship, which is the honest state pending P8.
//
// excludedTaxLedgers (NavCompositionTable's own SIBLING prop, SELF-268 AC10a): the frozen payload's
// `account_holdings` object carries no such key (verified against 110's CONTRACT — the function
// call is `pfin.fn_nav_composition(p_data_as_of)` alone, no second read). Left `undefined`
// (component default: "prop absent -> no exclusion note renders at all — a real payload gap,
// never a fabricated claim", NavCompositionTable's own documented state), not a fabricated `[]`.
//
// noTaxAuthorityDesignated / priorYearQ4 (TaxQuarterlyTables' own props): NEITHER is part of the
// frozen `estimated_taxes` payload (the first is a LIVE `fn_tax_authority_ledgers()` read; the
// second needs a THIRD `fn_compute_tax_liability` evaluation the render function's own header
// states it does NOT make — "TWO EVALUATIONS ... AND THE SECOND IS BOUGHT BY AC 6's OWN CONTENT").
// `noTaxAuthorityDesignated` is passed `false` (suppresses the page-level banner; each
// jurisdiction's OWN `ytd_paid`/`funds_due` unavailable-reason still renders accurately — the
// page-level banner would be REDUNDANT with, never a replacement for, that per-jurisdiction
// signal, so suppressing it does not hide anything this report could otherwise tell the reader).
// `priorYearQ4` is passed `null` (the report genuinely has no prior-year-Q4 amounts to show —
// exactly `null`'s own live-page meaning: "the window is shut / nothing to render"). Both are
// named, flagged simplifications, not silent guesses.

import type { NavComposition } from './nav-composition';
import type { NavDeltaPanelRow } from './nav-delta-panel';
import type { NavReferenceDateRow } from './nav-reference-dates';
import type { CashflowCrossAccountRollup } from './cashflow-rollup';
import type { HistoricalExpenditurePoint } from './historical-expenditures';
import type { TaxDecomposition } from './tax-decomposition';
import type { TaxJurisdictionKey, TaxJurisdictionPayload, PriorYearQ4Window } from './tax-quarterly';

/** `pfin.report_generation_status_enum` (migration 108). `superseded` is a real DB value but is
 *  NEVER the target of this route in V1 (R10 A-8 presentation bridge: "a superseded version is
 *  never rendered in V1") — the loader excludes it from its own row query rather than this type
 *  refusing to name it. */
export type MonthlyReportGenerationStatus = 'draft' | 'final' | 'superseded';

/** `commentary_disposition` (migration 108) — distinguishes an EXPLICITLY-SKIPPED month (P4's
 *  affordance) from four empty authored strings (P3 item 8: both are legitimate, and must stay
 *  distinguishable). `null` means neither has happened yet (still in the draft authoring window). */
export type CommentaryDisposition = 'authored' | 'skipped' | null;

/** One row of `pfin.monthly_report` — everything this render needs OUTSIDE the frozen/composed
 *  `rendered_payload` (which is `MonthlyReportPayload` below, arriving from one of two sources
 *  depending on `generation_status` — see this file's own header). */
export interface MonthlyReportHeader {
	report_id: number;
	target_month: string; // ISO date, always the 1st of the month (108's own CHECK).
	generation_status: MonthlyReportGenerationStatus;
	data_as_of: string; // ISO date.
	generated_at: string | null; // NULL while draft; set once, at finalization, never after.
	owner_header_at_generation: string | null; // NULL = unset (106/108's shared "unset" contract).
	commentary_cash: string | null;
	commentary_bonds: string | null;
	commentary_marketable_securities: string | null;
	commentary_alternatives: string | null;
	commentary_disposition: CommentaryDisposition;
}

/** §2.6.1 (2) NAV Performance — `series` / `series_inflation_adjusted` are NOT reused via
 *  NavHistoryChart (see this file's own header). Field names copied byte-for-byte from migration
 *  110's `nav_series` / `nav_series_infl` CTEs. */
export interface MonthlyReportNavSeriesPoint {
	point_date: string;
	nav_value: number;
	checkpoint_date: string;
}

export interface MonthlyReportNavSeriesInflationPoint {
	point_date: string;
	nav_nominal: number;
	checkpoint_date: string;
	nav_inflation_adjusted: number | null;
	cpi_period: string;
	cpi_value: number | null;
	cpi_is_carried: boolean;
	cpi_carried_from: string | null;
	cpi_period_was_due: boolean;
	cpi_nonpublication_on_record: boolean;
	cpi_coverage_through: string | null;
}

/** `delta_panel` / `reference_dates` — E16 (team-lead, closing 110 Finding 1): as of Part 1's new
 *  as-of readers, these are REAL ARRAYS whose field names match `NavDeltaPanelRow` /
 *  `NavReferenceDateRow` exactly (verified against 110's own `delta_panel` / `reference_dates`
 *  CTEs) — no longer the `{status:'unavailable', reason}` envelope an earlier revision of this
 *  file typed. DIRECT reuse of NavDeltaPanel.svelte / NavReferenceDatesPanel.svelte. */
export interface MonthlyReportNavPerformance {
	series: MonthlyReportNavSeriesPoint[];
	series_inflation_adjusted: MonthlyReportNavSeriesInflationPoint[];
	delta_panel: NavDeltaPanelRow[];
	reference_dates: NavReferenceDateRow[];
}

/** §2.6.1 (3) Asset Allocation. `target_percent` NULL = no `planning_target` row (unset is
 *  row-absent, never a seeded zero — 110's own allocation CTE comment). Real estate is EXCLUDED
 *  server-side (`fn_subcat_market_value(p_data_as_of, false)`); this reader applies no filter of
 *  its own on top of that. */
export interface MonthlyReportAllocationRow {
	sub_cat_id: number;
	cat: string;
	sub_cat: string;
	market_value: number;
	target_percent: number | null;
}

export interface MonthlyReportAssetAllocation {
	rows: MonthlyReportAllocationRow[];
}

/** Client-side presentational grouping, mirroring tax-decomposition.ts's `groupByCat` precedent —
 *  see this file's own header for why NO % subtotal is computed (no `total_non_re` in this
 *  payload). `dollar_subtotal` is PLAIN ADDITION over server-supplied `market_value` figures, not
 *  a money-path decision. */
export interface MonthlyReportAllocationGroup {
	cat: string;
	rows: MonthlyReportAllocationRow[];
	dollar_subtotal: number;
}

export function groupAllocationByCat(rows: MonthlyReportAllocationRow[]): MonthlyReportAllocationGroup[] {
	const order: string[] = [];
	const byCat = new Map<string, MonthlyReportAllocationRow[]>();
	for (const row of rows) {
		if (!byCat.has(row.cat)) {
			order.push(row.cat);
			byCat.set(row.cat, []);
		}
		byCat.get(row.cat)!.push(row);
	}
	return order.map((cat) => {
		const groupRows = byCat.get(cat)!;
		return {
			cat,
			rows: groupRows,
			dollar_subtotal: groupRows.reduce((sum, r) => sum + r.market_value, 0)
		};
	});
}

/** §2.6.1 (4) Rebalancing Targets — A1's four commentary columns, echoed inside the payload
 *  (110's `rebalancing_targets` object) alongside `source_report_id` (Finding 4: a caller MUST
 *  assert this equals the row it is about to write when this payload is used to SEED a new
 *  report — A5/A10's concern, not this read-only render's; not rendered as user copy here). */
export interface MonthlyReportRebalancingTargets {
	source_report_id: number | null;
	cash: string | null;
	bonds: string | null;
	marketable_securities: string | null;
	alternatives: string | null;
	disposition: CommentaryDisposition;
}

/** One sub-section of the Rebalancing Targets display — PRD §2.6.2's four headings, verbatim,
 *  in this fixed order. Built from `MonthlyReportRebalancingTargets` by `rebalancingSubSections`
 *  below so the render template does not repeat this list by hand. */
export interface RebalancingSubSection {
	heading: 'Cash' | 'Bonds' | 'Marketable Securities' | 'Alternatives';
	text: string | null;
}

export function rebalancingSubSections(
	targets: MonthlyReportRebalancingTargets
): RebalancingSubSection[] {
	return [
		{ heading: 'Cash', text: targets.cash },
		{ heading: 'Bonds', text: targets.bonds },
		{ heading: 'Marketable Securities', text: targets.marketable_securities },
		{ heading: 'Alternatives', text: targets.alternatives }
	];
}

/** §2.6.1 (5) Cash Flow — both fields carried VERBATIM from their live readers (110). */
export interface MonthlyReportCashFlow {
	cross_account_rollup: CashflowCrossAccountRollup;
	historical_expenditures: HistoricalExpenditurePoint[];
}

/** §2.6.1 (6) Estimated Taxes — `fn_compute_tax_liability`'s full return, carried VERBATIM and
 *  unflattened (110). Structurally satisfies BOTH `TaxLiabilitySlice` (tax_year + decomposition)
 *  AND `TaxQuarterlyLiability` (as_of + tax_year + jurisdictions + prior_year_q4_window) at once —
 *  the two live components this section reuses each pick the subset they need. */
export interface MonthlyReportEstimatedTaxes {
	as_of: string;
	tax_year: number;
	decomposition: TaxDecomposition;
	jurisdictions: Record<TaxJurisdictionKey, TaxJurisdictionPayload>;
	nav_components: unknown; // Rendered via account_holdings.buildups instead (110 invariant); not read here.
	prior_year_q4_window: PriorYearQ4Window;
}

/** THE PAYLOAD — migration 110's CONTRACT block, verbatim shape. `payload_schema_version` /
 *  `target_month` / `as_of` are echoed at the top level (Lock 15 / R1 rider 4's own-clock-proof
 *  fields); the renderer MUST branch on `payload_schema_version` to keep rendering an older
 *  version (AC2's own rule) — this ticket ships version 1 only; a future bump is this file's own
 *  edit, not a silent reinterpretation. */
export interface MonthlyReportPayload {
	payload_schema_version: number;
	target_month: string;
	as_of: string;
	sections: {
		account_holdings: NavComposition;
		nav_performance: MonthlyReportNavPerformance;
		asset_allocation: MonthlyReportAssetAllocation;
		rebalancing_targets: MonthlyReportRebalancingTargets;
		cash_flow: MonthlyReportCashFlow;
		estimated_taxes: MonthlyReportEstimatedTaxes;
	};
}

/** AC4's month/year stamp, folded verbatim: "{Month YYYY} · data as of {Mon D, YYYY} · generated
 *  {Mon D, YYYY}". The AC does not state the DRAFT case (where `generated_at` is NULL by
 *  construction — 108's own CHECK), so this function OMITS the "generated" clause when absent
 *  rather than inventing a date — flagged as a judgment call, not an AC-verbatim string, at
 *  hand-off. UTC-pinned (matches every other date-formatting helper in this codebase — nav-series
 *  / historical-expenditures / tax-quarterly's own `fmtDueDate` — so a report's own stamp never
 *  shifts a day under a non-UTC browser clock). */
export function monthYearStamp(header: MonthlyReportHeader): string {
	const monthLabel = new Date(`${header.target_month}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC'
	});
	const asOfLabel = new Date(`${header.data_as_of}T00:00:00Z`).toLocaleDateString('en-US', {
		month: 'short',
		day: 'numeric',
		year: 'numeric',
		timeZone: 'UTC'
	});
	const base = `${monthLabel} · data as of ${asOfLabel}`;
	if (!header.generated_at) return base;
	const generatedLabel = new Date(header.generated_at).toLocaleDateString('en-US', {
		month: 'short',
		day: 'numeric',
		year: 'numeric',
		timeZone: 'UTC'
	});
	return `${base} · generated ${generatedLabel}`;
}
