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

	§2.4.4 INFORMATIONAL-TIER MARKERS (the "carried" badge/basis-line vocabulary NavDeltaPanel
	and NavHistoryChart use) ARE DELIBERATELY ABSENT — SELF-229, per team-lead's explicit
	routing. Do not add a basis line, a carried-CPI badge, or a checkpoint-provenance disclosure
	here; the columns that will feed that surface are threaded through the type but have no UI
	yet.

	VALUE-COLOR FENCE (design-system-spec §5 fence 1) — THE OPPOSITE SCOPING FROM NavDeltaPanel:
	`nav` / `nav_prior_yr_dollars` are NAV LEVELS (positions), not deltas, so NEITHER --c-pos NOR
	--c-neg apply here — same neutral-ink treatment as the §2.1.1 headline and
	NavCompositionTable's current-value column.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import {
		REFERENCE_LABEL,
		isCpiUnresolvable,
		isInsufficientHistory,
		orderReferenceRows,
		formatUsd,
		type NavReferenceDateRow
	} from '$lib/nav-reference-dates';

	let { rows }: { rows: NavReferenceDateRow[] | null } = $props();

	const readFailed = $derived(rows === null);
	const orderedRows = $derived(rows ? orderReferenceRows(rows) : []);
</script>

<section class="nav-reference-panel" aria-labelledby="nav-reference-panel-label">
	<h2 id="nav-reference-panel-label" class="section-label">Reference NAV</h2>

	{#if readFailed}
		<p class="panel-notice">Reference NAV is temporarily unavailable. Please try again shortly.</p>
	{:else}
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
</style>
