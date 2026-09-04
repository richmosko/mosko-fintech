<!--
	NavReferenceDatesPanel.svelte — the §2.1.4 NAV-at-three-reference-dates panel (SELF-223 ·
	V1.1). Frontend-owned browser surface. Consumes `pfin.fn_nav_reference_dates()` (RATIFIED
	CONTRACT: temp/pm-self223-ac-rewrite.md v3-final — the migration is being authored in
	parallel; this component is built against the ratified AC text per team-lead's routing, not
	an applied migration file) threaded through `+page.server.ts` as
	`data.navReferenceDates: NavReferenceDateRow[] | null` — fail-soft to `null` on a read
	failure, same convention as `data.navDeltaPanel` / `data.composition` / `data.navBoundary`.
	Authors NO server logic. Field name `navReferenceDates` is a naming assumption pending
	Backend's actual loader text (same flow as SELF-222: Backend authors +page.server.ts and
	sends commit-ready text).

	Mount point (AC4): on the root Net Worth dashboard, ABOVE the §2.1.3 NavDeltaPanel and below
	the §2.1.1 headline NAV — sub-surface order matches Finance_Report page 3 (the §2.1.4 table
	sits above the §2.1.3 panel in the incumbent report), both under the ADR-013 P2 lock
	("Headline NAV + deltas lead → 60-mo trend → composition table").

	STRUCTURAL RENDERING ONLY, TWO discriminated NULL causes (AC5) — see
	$lib/nav-reference-dates.ts's header for the full contract reasoning. No signal here is
	inferred client-side, and none is borrowed from NavDeltaPanel's current_checkpoint_date
	disclosure (F/CTO-ratified 2026-08-13: a surface carries its own staleness signal).

	§2.4.4 INFORMATIONAL-TIER MARKERS (SELF-229 ramp): a PER-ROW carried-CPI marker now renders
	next to the "NAV — Prior Yr $" cell (073's cpi_any_carried is per-row, NOT the panel-wide flag
	NavDeltaPanel/NavHistoryChart read — see $lib/nav-reference-dates.ts's header). Vocabulary
	("Carried forward — …No action needed") is harmonized with NavDeltaPanel's existing basis-line
	wording so the two panels read as one system despite the different per-row vs panel-wide shape.
	The JANUARY-FAMILY COPY PROBLEM (PM comment 775fb0d1) is also handled here — two independent,
	data-driven captions below the table (never a structural row/column change — SELF-229 owns
	words only): priorMonthDuplicatesPriorYearEnd (duplicate rows) and columnsCollapseUnderArrears
	(duplicate columns). Draft copy in temp/frontend-self229-copy.md pending PM review.

	D1 stale-data-marker (SELF-229 ramp, distinct signal from the carried-CPI note above):
	`staleness` is the SAME whole-user `046` fn_aggregation_has_stale_constituent() payload the
	§2.1.1 headline already consumes, threaded down unchanged. Rendered beside this surface's own
	section heading. Per ADR-013 D1 (staleness-marking surface scope is illustrative, not
	exhaustive), further surfaces ramp later — Sec F4 (AMBER round): read D1 live, this line is a
	paraphrase not a quote.

	VALUE-COLOR FENCE (design-system-spec §5 fence 1) — THE OPPOSITE SCOPING FROM NavDeltaPanel:
	`nav` / `nav_prior_yr_dollars` are NAV LEVELS (positions), not deltas, so NEITHER --c-pos NOR
	--c-neg apply here — same neutral-ink treatment as the §2.1.1 headline and
	NavCompositionTable's current-value column.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).

	SELF-268 AC 4a — POINTER, not a restatement: `nav` / `nav_prior_yr_dollars` come off the
	checkpointed GROSS NAV series, which stays pre-tax and pre-exclusion permanently (R3 rider 0).
	The composed-gap explanation lives ONCE, on NavHistoryChart.svelte (§2.1.2) — this panel points
	to it rather than repeating it (one copy of the fact).
-->
<script lang="ts">
	import {
		REFERENCE_LABEL,
		isCpiUnresolvable,
		isInsufficientHistory,
		isRowCpiCarried,
		priorMonthDuplicatesPriorYearEnd,
		columnsCollapseUnderArrears,
		orderReferenceRows,
		formatUsd,
		type NavReferenceDateRow
	} from '$lib/nav-reference-dates';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B) (F/CTO-ruled): `staleness` is REQUIRED, no default — a caller that forgets to
	// thread real staleness data now fails at TYPECHECK, not as a silent "confirmed healthy"
	// fallback. The live mount (+page.svelte) already passes the real loader value unconditionally.
	let { rows, staleness }: { rows: NavReferenceDateRow[] | null; staleness: StalenessData } =
		$props();

	const readFailed = $derived(rows === null);
	const orderedRows = $derived(rows ? orderReferenceRows(rows) : []);
	const duplicateRows = $derived(rows ? priorMonthDuplicatesPriorYearEnd(orderedRows) : false);
	const columnsCollapsed = $derived(rows ? columnsCollapseUnderArrears(orderedRows) : false);

	const monthYear = (iso: string) =>
		new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });

	function carriedTitle(row: NavReferenceDateRow): string | undefined {
		if (!row.cpi_period) return undefined;
		return `Carried forward — ${monthYear(row.cpi_period)}'s CPI-U print isn't published yet (CPI-U publishes one to two months in arrears). No action needed.`;
	}
</script>

<section class="nav-reference-panel" aria-labelledby="nav-reference-panel-label">
	<h2 id="nav-reference-panel-label" class="section-label">Reference NAV</h2>
	<!-- D1 stale-data-marker: marks stale contribution beside the surface, never hides it. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

	{#if readFailed}
		<p class="panel-notice">Reference NAV is temporarily unavailable. Please try again shortly.</p>
	{:else}
		<!-- SELF-268 AC 4a POINTER — see the module header; full explanation on the trend chart
		     below, not restated here. -->
		<div class="panel-basis-stack">
			<p class="panel-basis-line">
				Tracks the checkpointed gross Net Worth — see the trend chart below for basis.
			</p>
		</div>

		<div class="table-scroll">
			<table class="reference">
				<caption class="sr-only">
					Net worth at three reference dates — This Month, Prior Month, and Prior Year-End —
					nominal and in prior-Year-End dollars.
				</caption>
				<thead>
					<tr>
						<th scope="col">Reference</th>
						<th scope="col" class="num">NAV</th>
						<th scope="col" class="num">NAV — Prior Yr $</th>
					</tr>
				</thead>
				<tbody>
					{#each orderedRows as row (row.reference)}
						<tr>
							<th scope="row">{REFERENCE_LABEL[row.reference]}</th>
							{#if isInsufficientHistory(row)}
								<td class="num" colspan="2">
									<span
										class="insufficient-badge"
										aria-label="Insufficient history — this reference date predates your earliest recorded NAV observation."
									>
										Insufficient history
									</span>
								</td>
							{:else}
								<td class="num">
									{row.nav !== null ? formatUsd(row.nav) : '—'}
								</td>
								<td class="num">
									{#if isCpiUnresolvable(row)}
										<span
											class="cpi-unavailable"
											title="Prior-Year-End-dollar figure unavailable for this reference date — no CPI-U data on record."
										>
											CPI unavailable
										</span>
									{:else if row.nav_prior_yr_dollars !== null}
										{formatUsd(row.nav_prior_yr_dollars)}
										{#if isRowCpiCarried(row)}
											<span class="carried-flag" title={carriedTitle(row)}>Carried</span>
										{/if}
									{:else}
										—
									{/if}
								</td>
							{/if}
						</tr>
					{/each}
				</tbody>
			</table>
		</div>

		<!-- THE JANUARY-FAMILY COPY PROBLEM (SELF-229 · PM comment 775fb0d1) — two independent,
		     data-driven captions. Neither changes the table's shape (three rows always render, no
		     de-duplication); both are words-only, gated on facts the panel's own rows already carry. -->
		{#if duplicateRows || columnsCollapsed}
			<div class="panel-footnotes">
				{#if duplicateRows}
					<p class="panel-footnote">
						Prior Month and Prior Year-End show identical figures this month — both reference the
						same December date, so this is expected, not a duplicate entry.
					</p>
				{/if}
				{#if columnsCollapsed}
					<p class="panel-footnote">
						NAV and NAV — Prior Yr $ match exactly across all three rows this month — CPI-U's most
						recent print is still catching up (it publishes one to two months in arrears), so the
						conversion hasn't moved yet. This is expected, not a stalled figure.
					</p>
				{/if}
			</div>
		{/if}
	{/if}
</section>

<style>
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

	/* Visually subordinate to the §2.1.1 headline — same section-heading treatment
	   NavHistoryChart / NavCompositionTable / NavDeltaPanel use for their own headings. */
	.section-label {
		margin: 0 0 var(--space-3);
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}

	.panel-notice {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}

	/* ── basis-line family — reproduces NavHistoryChart's / NavDeltaPanel's .chart-basis-line /
	   .panel-basis-line vocabulary verbatim (same tokens, same shape) so all three surfaces read
	   as one system (SELF-268 AC 4a pointer). ── */
	.panel-basis-stack {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-bottom: var(--space-3);
	}
	.panel-basis-line {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		line-height: var(--lh-body);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css table.tbl with tokens only, same shape as
	   NavCompositionTable's .comp / NavDeltaPanel's .delta base. */
	.reference {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.reference th,
	.reference td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.reference thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.reference td.num,
	.reference th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.reference tbody th[scope='row'] {
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}

	/* NO pos/neg classes anywhere in this file — VALUE-COLOR FENCE: these are NAV LEVELS
	   (positions), not deltas. Cell values render in the same neutral --c-text-primary the
	   base table rules above already apply; no override needed. */

	/* Insufficient-history — quiet neutral chip, same treatment as NavDeltaPanel's
	   .insufficient-badge (NOT --c-attn-*: nothing actionable, a historical-depth fact). */
	.insufficient-badge {
		display: inline-flex;
		align-items: center;
		font-size: var(--fs-small);
		font-style: italic;
		color: var(--c-text-muted);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-sm);
		padding: 2px var(--space-2);
	}

	/* CPI-unresolvable — the nominal figure stands (in this table's own neutral cell ink);
	   only this cell is unformed. Same treatment as NavDeltaPanel's .cpi-unavailable. */
	.cpi-unavailable {
		font-style: italic;
		color: var(--c-text-muted);
		font-family: var(--font-ui);
	}

	/* PER-ROW carried-CPI marker (§2.4.4 informational tier) — deliberately NOT --c-attn-*
	   (that hue is reserved for the D1 actionable/stale-connection signal the StaleConstituentBadge
	   above renders); same quiet-neutral register as InformationalMarkerBadge / NavDeltaPanel's
	   .carried-note. A compact inline tag (not a whole sentence) since it repeats per row. */
	.carried-flag {
		display: inline-flex;
		align-items: center;
		margin-left: var(--space-1);
		font-family: var(--font-ui);
		font-size: var(--fs-small);
		font-style: italic;
		color: var(--c-text-muted);
	}

	/* Duplicate-row / duplicate-column January-family captions — same basis-line vocabulary
	   (neutral, secondary ink) NavDeltaPanel / NavHistoryChart use for their own disclosures. */
	.panel-footnotes {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-top: var(--space-3);
	}
	.panel-footnote {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		line-height: var(--lh-body);
	}
</style>
