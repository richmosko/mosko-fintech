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

	SIX SECTIONS, VERBATIM ORDER (AC1, §2.6 as amended at the R10 PR): Account Holdings, NAV
	Performance, Asset Allocation, Rebalancing Targets, Cash Flow, Estimated Taxes.

	P8 STALENESS SLOT (AC7 — staleness markers are read LIVE at every render, over the frozen
	payload; P8 owns them): every reused component requiring `staleness` / `cashflowRowStaleness`
	is fed `UNKNOWN_STALENESS` / `EMPTY_CASHFLOW_ROW_STALENESS_MAP` here, NEVER a live read — see
	$lib/monthly-report.ts's own header for why partial wiring would be worse than an honest,
	clearly-named placeholder. P8 replaces these two constants with real live reads; nothing else
	in this file should need to change when it does.

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
	import {
		groupAllocationByCat,
		rebalancingSubSections,
		monthYearStamp,
		type MonthlyReportHeader,
		type MonthlyReportPayload
	} from '$lib/monthly-report';
	import type { TaxCharacterCatalog } from '$lib/tax-decomposition';
	import { UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';
	import { EMPTY_CASHFLOW_ROW_STALENESS_MAP } from '$lib/cashflow-row-staleness';

	let {
		header,
		payload,
		taxCharacters,
		seedDeltaMigration,
		ownerHeaderHref = '/settings/owner-id',
		commentaryHref = `/reports/monthly/${header.target_month.slice(0, 7)}/commentary`,
		regenerateHref = '/reports/monthly',
		pdfHref = `/reports/monthly/${header.target_month.slice(0, 7)}/pdf`
	}: {
		header: MonthlyReportHeader;
		payload: MonthlyReportPayload;
		taxCharacters: TaxCharacterCatalog;
		seedDeltaMigration: string;
		ownerHeaderHref?: string;
		commentaryHref?: string;
		regenerateHref?: string;
		pdfHref?: string;
	} = $props();

	const stamp = $derived(monthYearStamp(header));
	const isPending = $derived(header.generation_status === 'draft');

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
	<header class="report-head">
		<p class="report-stamp">{stamp}</p>

		<!-- AC4 — the owner header line; unset -> the in-app prompt (PDF unset -> no header line at
		     all, PM A-13 — that branch is A5/P6's rendering context, not this one's; this element
		     always renders something FOR THE IN-APP VIEW, which always has a place to put a
		     "Set it" prompt). -->
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

	<!-- (1) Account Holdings — DIRECT reuse; payload IS a NavComposition verbatim. -->
	<section aria-label="Account Holdings">
		<NavCompositionTable composition={payload.sections.account_holdings} staleness={UNKNOWN_STALENESS} />
	</section>

	<!-- (2) NAV Performance — E16 (team-lead): delta_panel/reference_dates are now real, always-
	     threadable arrays (110 Finding 1 closed via Part 1's as-of readers) and are reused DIRECTLY
	     via NavDeltaPanel/NavReferenceDatesPanel below. NavDeltaPanel's OWN `<h2>NAV Performance</h2>`
	     is THE section heading (AC1) — no second one rendered here. `series` /
	     `series_inflation_adjusted` are still NOT NavHistoryChart (see monthly-report.ts's header). -->
	<section class="nav-performance">
		<NavDeltaPanel rows={payload.sections.nav_performance.delta_panel} staleness={UNKNOWN_STALENESS} />

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
			staleness={UNKNOWN_STALENESS}
		/>
	</section>

	<!-- (3) Asset Allocation — new minimal grouped table; see monthly-report.ts's header for why
	     NonReAllocationTable is not reused (shape mismatch: no total_non_re in this payload). -->
	<section class="asset-allocation" aria-labelledby="asset-allocation-label">
		<h2 id="asset-allocation-label" class="section-label">Asset Allocation</h2>
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

	<!-- (4) Rebalancing Targets — new minimal read-only display; no editor exists yet (P3). -->
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

	<!-- (5) Cash Flow — DIRECT reuse; field names match verbatim. -->
	<section aria-label="Cash Flow">
		<CashflowRollupTable
			rollup={payload.sections.cash_flow.cross_account_rollup}
			staleness={UNKNOWN_STALENESS}
			cashflowRowStaleness={EMPTY_CASHFLOW_ROW_STALENESS_MAP}
		/>
		<HistoricalExpendituresChart
			points={payload.sections.cash_flow.historical_expenditures}
			staleness={UNKNOWN_STALENESS}
			unclassifiedCount={payload.sections.cash_flow.cross_account_rollup.unclassified.count_ytd}
		/>
	</section>

	<!-- (6) Estimated Taxes — DIRECT reuse; `estimated_taxes` structurally satisfies both.
	     `staleness` on both components below was added at the SELF-354→feature/self-345 rebase
	     (2026-09-05): P9/SELF-361 landed a REQUIRED `staleness` prop on both components (the
	     §2.5.x staleness ramp) after this file was first authored — P8 SLOT, same convention as
	     every other reused component here (see the file header). -->
	<section aria-label="Estimated Taxes">
		<TaxDecompositionTable
			liability={payload.sections.estimated_taxes}
			{taxCharacters}
			{seedDeltaMigration}
			staleness={UNKNOWN_STALENESS}
			capitalGainsUnavailableCopy="Capital gains were unavailable when this report was generated — sale recording lands at a later V1.x."
		/>
		<TaxQuarterlyTables
			liability={payload.sections.estimated_taxes}
			noTaxAuthorityDesignated={false}
			priorYearQ4={null}
			staleness={UNKNOWN_STALENESS}
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
