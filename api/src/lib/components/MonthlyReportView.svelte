<!--
	MonthlyReportView.svelte — the §2.6.1.b monthly report render (SELF-354 / P2). Frontend-owned
	browser surface. THE SHARED TEMPLATE (R2 (C)): the in-app page below mounts this component
	directly; A5's PDF-composition path renders the SAME component server-side and pushes the
	resulting HTML to the PDF worker. It is therefore a PURE component over its payload props — no
	page-only chrome (nav, sidebar, `<svelte:head>`) lives in this file; that belongs to the route's
	own `+page.svelte`.

	CONTRACT (props) — see `$lib/monthly-report.ts` for the full type definitions and the section-
	to-component reuse map this file implements:
	  header          : MonthlyReportHeader — the `pfin.monthly_report` row (status, dates, owner
	                    header, the four commentary columns, disposition). NEVER the payload.
	  payload         : MonthlyReportPayload — migration 110's CONTRACT shape, from EITHER
	                    `rendered_payload` (final/superseded — frozen, R1 (A)) or a live
	                    `fn_render_monthly_report` call (draft) — the caller (`+page.server.ts` /
	                    A5) resolves which; this component does not care which path produced it.
	  taxCharacters   : the `pfin.tax_character` catalog TaxDecompositionTable needs (AC5) — read
	                    LIVE by the caller (a 5-row, near-immutable global reference table; not part
	                    of the frozen payload, same posture the live /taxes/decomposition page
	                    already takes for this exact read).
	  seedDeltaMigration : AC11's static citation string TaxDecompositionTable renders — reuse
	                    Backend's own `INVENTORY_SEED_DELTA_MIGRATION` constant, never retyped.
	  ownerHeaderHref / commentaryHref / regenerateHref / pdfHref : optional CTA targets, each
	                    defaulting to the route this ticket's sibling issues (P3 commentary editor,
	                    P5 listing/regenerate, P6 PDF export) will build — EXPECTED to 404 until
	                    those branches land, the SAME "route now, build later" convention
	                    TaxQuarterlyTables' own `decompositionHref` / CashflowRollupTable's
	                    `editTargetsHref` already use for their own not-yet-built siblings.
	  renderContext     : SELF-358 / P6 (backend flag, Frontend TO REVIEW) — SIZING ONLY, passed
	                    straight through to `HistoricalExpendituresChart` (see that file's own
	                    header for the full rationale). `'browser'` (default) is byte-identical to
	                    this component's pre-P6 behavior. Must never gate rendered CONTENT here or
	                    anywhere downstream — AC3's one-template guarantee depends on that.

	SIX SECTIONS, VERBATIM ORDER (AC1, §2.6 as amended at the R10 PR): Account Holdings, NAV
	Performance, Asset Allocation, Rebalancing Targets, Cash Flow, Estimated Taxes.

	P8 STALENESS (SELF-360, AC2/AC3/AC4/AC6/AC7): staleness is read LIVE by the caller at every
	render/export, NEVER from the frozen payload — `staleness` / `cashflowRowStaleness` /
	`staleAccountNames` are REQUIRED props (no default; a caller that forgets to thread real data
	fails at TYPECHECK). `staleness` (whole-tenant) feeds every section-level
	`<StaleConstituentBadge>` — Account Holdings, NAV Performance (x2), the NEW Asset Allocation
	header badge, Cash Flow (x2), Estimated Taxes (x2). Account Holdings' own per-leaf `is_stale`
	arrives ALREADY REFRESHED by the loader (never trust whatever the payload's own leaves carry).
	`cashflowRowStaleness` feeds the Cash Flow per-row map (AC4's shipped V1.3 shape).
	`staleAccountNames` feeds the report-level banner (AC3/AC7) at the top of this article.
	EXCLUDED (AC6, not account-derived): Rebalancing Targets and the owner header carry no marker
	anywhere in this file.

	ENVELOPE RENDERING (AC5) is mandatory, never defensive: every remaining `{status, ...}` object
	in this payload (NavCompositionTable's buildups; TaxDecompositionTable/TaxQuarterlyTables'
	jurisdiction envelopes) is handled by the reused component that already enforces this — never
	`?? 0`, never currency-formatted, never silently dropped. `delta_panel` / `reference_dates` are
	NO LONGER envelopes (E16 closed 110 Finding 1 with real as-of-threaded arrays) — see
	monthly-report.ts's header for the shape change and the direct-reuse this enabled.

	NO INLINE EDIT (AC8, §2.6.2's V2+ ground, not ADR-013 P5): every commentary/owner-header value
	renders as plain escaped text (Svelte's default `{...}` interpolation, INV-1) — no
	`<input>`/`[contenteditable]`/`{@html}` anywhere in this file. "Edit commentary" / "Regenerate"
	is a plain navigation link, branching on `header.generation_status` (AC3/AC8): `draft` routes to
	P3's editor; `final` (the only OTHER status this route ever renders — R10 A-8, `superseded` is
	never rendered) routes to P5's listing, where the Regenerate affordance lives.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import NavCompositionTable from './NavCompositionTable.svelte';
	import NavDeltaPanel from './NavDeltaPanel.svelte';
	import NavReferenceDatesPanel from './NavReferenceDatesPanel.svelte';
	import TaxDecompositionTable from './TaxDecompositionTable.svelte';
	import TaxQuarterlyTables from './TaxQuarterlyTables.svelte';
	import CashflowRollupTable from './CashflowRollupTable.svelte';
	import HistoricalExpendituresChart from './HistoricalExpendituresChart.svelte';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';
	import MonthlyReportStaleBanner from './MonthlyReportStaleBanner.svelte';
	import {
		groupAllocationByCat,
		rebalancingSubSections,
		monthYearStamp,
		type MonthlyReportHeader,
		type MonthlyReportPayload
	} from '$lib/monthly-report';
	import type { TaxCharacterCatalog } from '$lib/tax-decomposition';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import type { CashflowRowStalenessMap } from '$lib/cashflow-row-staleness';

	let {
		header,
		payload,
		taxCharacters,
		seedDeltaMigration,
		staleness,
		cashflowRowStaleness,
		staleAccountNames,
		ownerHeaderHref = '/settings/owner-id',
		commentaryHref = `/reports/monthly/${header.target_month.slice(0, 7)}/commentary`,
		regenerateHref = '/reports/monthly',
		pdfHref = `/reports/monthly/${header.target_month.slice(0, 7)}/pdf`,
		renderContext = 'browser'
	}: {
		header: MonthlyReportHeader;
		payload: MonthlyReportPayload;
		taxCharacters: TaxCharacterCatalog;
		seedDeltaMigration: string;
		/** P8 (SELF-360 AC2): the SAME whole-tenant, LIVE `loadStaleness()` read every other
		 *  section-level badge on this tree already consumes — REQUIRED, no default (Sec F3(B)-
		 *  style discipline: a caller that forgets to thread real data fails at TYPECHECK, never
		 *  as a silent "confirmed healthy" `EMPTY_STALENESS` fallback). */
		staleness: StalenessData;
		/** P8 (SELF-360 AC4): the Cash Flow section's per-(cat, sub_cat) row map — the shipped
		 *  V1.3 shape (`cashflowContributors.ts` / `cashflow-row-staleness.ts`), computed by the
		 *  loader at THIS report's own `data_as_of`. */
		cashflowRowStaleness: CashflowRowStalenessMap;
		/** P8 (SELF-360 AC3/AC7): already-resolved, already-sorted LIVE account names for the
		 *  report-level banner — see MonthlyReportStaleBanner.svelte's own header for why this
		 *  component does no further lookup/filtering/sorting. */
		staleAccountNames: string[];
		ownerHeaderHref?: string;
		commentaryHref?: string;
		regenerateHref?: string;
		pdfHref?: string;
		/** SELF-358 / P6 — see this file's own header + `HistoricalExpendituresChart.svelte`'s.
		 *  SIZING ONLY. */
		renderContext?: 'browser' | 'print';
	} = $props();

	const stamp = $derived(monthYearStamp(header));
	const isPending = $derived(header.generation_status === 'draft');

	// AC7's banner copy needs the BARE "{Month YYYY}" — `monthYearStamp()` above is the fuller
	// "{Month YYYY} · data as of {date} · generated {date}" stamp rendered in the report head,
	// not this shape. A small, separate derivation rather than parsing `stamp` back apart.
	const bareMonthLabel = $derived(
		new Date(`${header.target_month}T00:00:00Z`).toLocaleDateString('en-US', {
			month: 'long',
			year: 'numeric',
			timeZone: 'UTC'
		})
	);

	const allocationGroups = $derived(groupAllocationByCat(payload.sections.asset_allocation.rows));
	const rebalancing = $derived(rebalancingSubSections(payload.sections.rebalancing_targets));

	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
	const pct = new Intl.NumberFormat('en-US', { style: 'percent', minimumFractionDigits: 1, maximumFractionDigits: 1 });

	function fmtDate(iso: string): string {
		return new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
			month: 'short',
			day: 'numeric',
			year: 'numeric',
			timeZone: 'UTC'
		});
	}
</script>

<article class="monthly-report">
	<!-- P8 (SELF-360 AC3/AC7) — the report-level banner. Renders nothing when
	     `staleAccountNames` is empty; see MonthlyReportStaleBanner.svelte's own header. -->
	<MonthlyReportStaleBanner accountNames={staleAccountNames} monthLabel={bareMonthLabel} />

	<header class="report-head">
		<p class="report-stamp">{stamp}</p>

		<!-- AC4 — the owner header line; unset -> the in-app prompt (PDF unset -> no header line at
		     all, PM A-13 — that branch is A5/P6's rendering context, not this one's; this element
		     always renders something FOR THE IN-APP VIEW, which always has a place to put a
		     "Set it" prompt). P8 (SELF-360 AC6): EXCLUDED from marking, deliberately — no
		     `<StaleConstituentBadge>` anywhere near this element; the owner header is settings-
		     store config, not account-derived. -->
		{#if header.owner_header_at_generation}
			<p class="owner-header">{header.owner_header_at_generation}</p>
		{:else}
			<p class="owner-header-unset">
				<a href={ownerHeaderHref}>Set the report header in Settings</a>
			</p>
		{/if}

		{#if header.commentary_disposition === 'skipped'}
			<p class="disposition-note" role="status">Commentary was skipped for this month.</p>
		{/if}

		<div class="report-actions">
			{#if isPending}
				<a class="btn-like" href={commentaryHref}>Edit commentary</a>
			{:else}
				<a class="btn-like" href={regenerateHref}>Regenerate</a>
			{/if}

			{#if isPending}
				<span class="btn-like is-disabled" aria-disabled="true" title="Finalize this report to export it.">
					Download PDF
				</span>
			{:else}
				<a class="btn-like" href={pdfHref}>Download PDF</a>
			{/if}
		</div>
	</header>

	<!-- (1) Account Holdings — DIRECT reuse; payload IS a NavComposition verbatim. Per-leaf
	     `is_stale` arrives ALREADY REFRESHED by the loader (P8 AC2) — this component never sees
	     whatever value the frozen payload's own leaves carried. -->
	<section aria-label="Account Holdings">
		<NavCompositionTable composition={payload.sections.account_holdings} {staleness} />
	</section>

	<!-- (2) NAV Performance — E16 (team-lead): delta_panel/reference_dates are now real, always-
	     threadable arrays (110 Finding 1 closed via Part 1's as-of readers) and are reused DIRECTLY
	     via NavDeltaPanel/NavReferenceDatesPanel below. NavDeltaPanel's OWN `<h2>NAV Performance</h2>`
	     is THE section heading (AC1) — no second one rendered here. `series` /
	     `series_inflation_adjusted` are still NOT NavHistoryChart (see monthly-report.ts's header). -->
	<section class="nav-performance">
		<NavDeltaPanel rows={payload.sections.nav_performance.delta_panel} {staleness} />

		<p class="basis-line">
			This trend shows the checkpointed gross Net Worth — before the two tax lines and the
			designated tax-authority ledgers; the Account Holdings foot is the tax-adjusted figure.
		</p>

		{#if payload.sections.nav_performance.series_inflation_adjusted.length > 0}
			<div class="table-scroll">
				<table class="nav-series-table">
					<caption class="sr-only">Monthly NAV checkpoints, nominal and inflation-adjusted.</caption>
					<thead>
						<tr>
							<th scope="col">Checkpoint</th>
							<th scope="col">NAV (nominal)</th>
							<th scope="col">NAV (inflation-adjusted)</th>
						</tr>
					</thead>
					<tbody>
						{#each payload.sections.nav_performance.series_inflation_adjusted as point (point.point_date)}
							<tr>
								<td>{fmtDate(point.checkpoint_date)}</td>
								<td>{usd.format(point.nav_nominal)}</td>
								<td>
									{#if point.nav_inflation_adjusted === null}
										<span class="cell-unavailable">—</span>
									{:else}
										{usd.format(point.nav_inflation_adjusted)}
									{/if}
								</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{:else}
			<p class="empty-note" role="status">No NAV checkpoint history available for this window.</p>
		{/if}

		<NavReferenceDatesPanel
			rows={payload.sections.nav_performance.reference_dates}
			{staleness}
		/>
	</section>

	<!-- (3) Asset Allocation — new minimal grouped table; see monthly-report.ts's header for why
	     NonReAllocationTable is not reused (shape mismatch: no total_non_re in this payload).
	     P8 (SELF-360 AC4, pre-ruling (i)): a SECTION-HEADER badge only — `MonthlyReportAllocationRow`
	     carries no `account_id`, so no per-row attribution is possible from this payload (unlike
	     Account Holdings' own leaves). AC4 requires per-section marking, not per-row, so a
	     header-level badge off the SAME whole-tenant `staleness` fully discharges this section's
	     obligation without a payload change. -->
	<section class="asset-allocation" aria-labelledby="asset-allocation-label">
		<header class="head">
			<h2 id="asset-allocation-label" class="section-label">Asset Allocation</h2>
			<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />
		</header>
		{#if allocationGroups.length === 0}
			<p class="empty-note" role="status">No allocation data for this month.</p>
		{:else}
			<div class="table-scroll">
				<table class="allocation-table">
					<caption class="sr-only">Asset allocation by category and sub-category, at generation.</caption>
					<thead>
						<tr>
							<th scope="col">Cat / Sub-Cat</th>
							<th scope="col">Market Value</th>
							<th scope="col">%Target</th>
						</tr>
					</thead>
					<tbody>
						{#each allocationGroups as group (group.cat)}
							<tr class="group-row">
								<th scope="rowgroup" colspan="3">{group.cat}</th>
							</tr>
							{#each group.rows as row (row.sub_cat_id)}
								<tr>
									<td class="sub-cat-cell">{row.sub_cat}</td>
									<td>{usd.format(row.market_value)}</td>
									<td>
										{#if row.target_percent === null}
											<span class="cell-unavailable">—</span>
										{:else}
											{pct.format(row.target_percent / 100)}
										{/if}
									</td>
								</tr>
							{/each}
							<tr class="subtotal-row">
								<td>{group.cat} subtotal</td>
								<td>{usd.format(group.dollar_subtotal)}</td>
								<td></td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>

	<!-- (4) Rebalancing Targets — new minimal read-only display; no editor exists yet (P3).
	     P8 (SELF-360 AC6): EXCLUDED from marking — user-authored free-text commentary is not
	     account-derived. No `<StaleConstituentBadge>` anywhere in this section, deliberately. -->
	<section class="rebalancing-targets" aria-labelledby="rebalancing-targets-label">
		<h2 id="rebalancing-targets-label" class="section-label">Rebalancing Targets</h2>
		{#each rebalancing as sub (sub.heading)}
			<div class="commentary-sub">
				<h3 class="commentary-heading">{sub.heading}</h3>
				<!-- Empty sub-sections render label + empty body — NEVER hidden (PRD §2.6.2 verbatim). -->
				<p class="commentary-body">{sub.text ?? ''}</p>
			</div>
		{/each}
	</section>

	<!-- (5) Cash Flow — DIRECT reuse; field names match verbatim. `cashflowRowStaleness` is P8's
	     AC4 shipped-V1.3-shape per-row map, computed by the loader at this report's OWN
	     `data_as_of`. -->
	<section aria-label="Cash Flow">
		<CashflowRollupTable
			rollup={payload.sections.cash_flow.cross_account_rollup}
			{staleness}
			{cashflowRowStaleness}
		/>
		<HistoricalExpendituresChart
			points={payload.sections.cash_flow.historical_expenditures}
			{staleness}
			unclassifiedCount={payload.sections.cash_flow.cross_account_rollup.unclassified.count_ytd}
			{renderContext}
		/>
	</section>

	<!-- (6) Estimated Taxes — DIRECT reuse; `estimated_taxes` structurally satisfies both.
	     `staleness` on both components below is P8's own live wiring (P9/SELF-361 landed the
	     REQUIRED prop at the SELF-354→feature/self-345 rebase, 2026-09-05; this is the P8 slot
	     that prop created, now filled with the real whole-tenant read). -->
	<section aria-label="Estimated Taxes">
		<TaxDecompositionTable
			liability={payload.sections.estimated_taxes}
			{taxCharacters}
			{seedDeltaMigration}
			{staleness}
			capitalGainsUnavailableCopy="Capital gains were unavailable when this report was generated — sale recording lands at a later V1.x."
		/>
		<TaxQuarterlyTables
			liability={payload.sections.estimated_taxes}
			noTaxAuthorityDesignated={false}
			priorYearQ4={null}
			{staleness}
		/>
	</section>
</article>

<style>
	.monthly-report {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		max-width: 64rem;
	}
	.report-head {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.report-stamp {
		margin: 0;
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.owner-header {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
		/* Escaped once by Svelte's default interpolation above; line breaks (should the header ever
		   carry one, which 106's own single-line CHECK refuses at the source) never reflow into
		   markup — this is a visual wrap allowance only, not an HTML transform. */
		white-space: pre-wrap;
	}
	.owner-header-unset {
		margin: 0;
		font: var(--weight-med) var(--fs-body) / var(--lh-body) var(--font-ui);
	}
	.owner-header-unset a {
		color: var(--c-accent);
	}
	.disposition-note {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.report-actions {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.btn-like {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
	}
	.btn-like:hover {
		background: var(--c-surface-alt);
	}
	.btn-like:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.btn-like.is-disabled {
		color: var(--c-disabled-text);
		cursor: default;
	}
	.section-label {
		margin: 0 0 var(--space-3) 0;
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	/* Asset Allocation's own header row — the section-label heading plus its P8 stale badge,
	   mirrors TaxDecompositionTable.svelte's own `.head` layout for the identical pairing. */
	.asset-allocation .head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.asset-allocation .head .section-label {
		margin: 0;
	}
	.basis-line {
		margin: 0 0 var(--space-3) 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.table-scroll {
		overflow-x: auto;
	}
	.nav-series-table,
	.allocation-table {
		width: 100%;
		border-collapse: collapse;
	}
	.nav-series-table th,
	.allocation-table th {
		text-align: left;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		padding: var(--space-1) var(--space-2);
	}
	.nav-series-table td,
	.allocation-table td {
		padding: var(--space-1) var(--space-2);
		font: var(--fs-body) / 1.2 var(--font-num);
	}
	.group-row th {
		padding-top: var(--space-3);
		color: var(--c-text-primary);
		font: var(--weight-semi) var(--fs-body) / 1.2 var(--font-ui);
	}
	.sub-cat-cell {
		padding-left: var(--space-4);
	}
	.subtotal-row td {
		font-weight: var(--weight-semi);
		border-top: 1px solid var(--c-border);
	}
	.cell-unavailable {
		color: var(--c-text-muted);
	}
	.empty-note {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.commentary-sub {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		margin-bottom: var(--space-3);
	}
	.commentary-heading {
		margin: 0;
		font: var(--weight-semi) var(--fs-body) / 1.2 var(--font-ui);
		color: var(--c-text-primary);
	}
	.commentary-body {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-primary);
		/* Plain text, line breaks preserved via CSS only (INV-1) — never `{@html}`, never markdown. */
		white-space: pre-wrap;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
