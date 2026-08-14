<!--
	NavDeltaPanel.svelte — the §2.1.3 multi-horizon NAV-delta panel (SELF-222 · V1.1).
	Frontend-owned browser surface. Consumes `pfin.fn_nav_delta_panel()` (migration
	supabase/migrations/072_fn_nav_delta_panel_real_percent.sql, which supersedes 071's
	return shape by adding `delta_inflation_adjusted_percent` — the AC3 amendment,
	F/CTO-ratified 2026-08-14) threaded through `+page.server.ts` as
	`data.navDeltaPanel: NavDeltaPanelRow[] | null` — fail-soft to `null` on a read
	failure, same convention as `data.composition` / `data.navBoundary`. Authors NO
	server logic.

	Inflation Adjusted cells render dollar + percent for 1Y/3Y/5Y (AC3, matching the NAV
	Delta column's format) — the percent is NEVER derived client-side; it rides
	delta_inflation_adjusted_percent exactly as returned. See $lib/nav-delta-panel.ts's
	header for why a client-side derivation would be arithmetically wrong (a mixed-basis
	defect, not merely redundant work).

	Mount point: on the root Net Worth dashboard, directly below the §2.1.1 headline NAV
	and ABOVE the §2.1.5 composition table — Phase 2 P2 lock (ADR-013 Decision 3):
	"Headline NAV + deltas lead → 60-mo trend → composition table." Visually subordinate
	to the headline: a `.section-label` heading (same treatment NavHistoryChart /
	NavCompositionTable use for their own section headings), not a second hero number.

	STRUCTURAL RENDERING ONLY — every branch below reads a field the backend already
	resolved (071's three-way NULL discriminator: insufficient-history /
	CPI-unresolvable / not-applicable). This component infers NONE of those states from
	a computed comparison; see $lib/nav-delta-panel.ts's header for why.

	CURRENT-SIDE STALENESS (SELF-221 AC5(i)): current_checkpoint_date is THIS panel's own
	signal — disclosed as a literal "as of" basis line, never compared against a
	client-side clock (ADR-044 R2 is exactly why a second, client-derived "is this stale"
	check must not exist here) and never borrowed from `data.navBoundary` (the chart's
	own boundary-date signal is a different surface's provenance).

	VALUE-COLOR FENCE (design-system-spec §5 fence 1): --c-pos/--c-neg apply here — unlike
	the §2.1.1 NAV headline (a position), every cell on this panel is a DELTA (actual
	performance), which is exactly what the fence scopes the tokens to.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).

	D1 stale-data-marker (SELF-229 ramp): `staleness` is the SAME whole-user `046`
	fn_aggregation_has_stale_constituent() payload the §2.1.1 headline already consumes
	(+page.server.ts's `data.staleness`, threaded down unchanged — the fn takes no scope
	filter, so every consuming surface reads the identical aggregate). Rendered beside this
	surface's own section heading (D1: mark adjacent to the surface, never a floating banner
	— that's the separate P4 reauth-staleness-banner, SELF-207 territory). This is DISTINCT
	from the `.carried-note` basis line below: the stale-data-marker (canary hue) flags an
	unhealthy CONNECTION; the carried-note (neutral ink, informational tier) flags a carried
	CPI-U REFERENCE SERIES — two different staleness sources per PRD §2.4.4, never merged
	into one signal. Per ADR-013 D1 (staleness-marking surface scope is illustrative, not
	exhaustive), further surfaces ramp later — Sec F4 (AMBER round): read D1 live, this line is a
	paraphrase not a quote.
-->
<script lang="ts">
	import {
		HORIZON_LABEL,
		isCpiApplicable,
		isCpiUnresolvable,
		isInsufficientHistory,
		isPercentInexpressible,
		isInflationPercentInexpressible,
		orderRows,
		signClass,
		formatSignedUsd,
		formatSignedPercent,
		monthYear,
		fullDate,
		currentCheckpointDate,
		cpiBasisPeriod,
		anyCpiCarried,
		type NavDeltaPanelRow
	} from '$lib/nav-delta-panel';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B) (F/CTO-ruled): `staleness` is REQUIRED, no default — a caller that forgets to
	// thread real staleness data now fails at TYPECHECK, not as a silent "confirmed healthy"
	// fallback. The live mount (+page.svelte) already passes the real loader value unconditionally.
	let { rows, staleness }: { rows: NavDeltaPanelRow[] | null; staleness: StalenessData } =
		$props();

	const readFailed = $derived(rows === null);
	const orderedRows = $derived(rows ? orderRows(rows) : []);
	const asOf = $derived(rows ? currentCheckpointDate(rows) : null);
	const basisPeriod = $derived(rows ? cpiBasisPeriod(rows) : null);
	const carried = $derived(rows ? anyCpiCarried(rows) : false);
</script>

<section class="nav-delta-panel" aria-labelledby="nav-delta-panel-label">
	<h2 id="nav-delta-panel-label" class="section-label">NAV Performance</h2>
	<!-- D1 stale-data-marker: marks stale contribution beside the surface, never hides it. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

	{#if readFailed}
		<p class="panel-notice">NAV performance is temporarily unavailable. Please try again shortly.</p>
	{:else}
		<div class="panel-basis-stack">
			{#if asOf}
				<p class="panel-basis-line">
					Current values as of <span class="basis-value">{fullDate(asOf)}</span>.
				</p>
			{/if}
			{#if basisPeriod}
				<p class="panel-basis-line">
					Real terms figures use a CPI-U basis through <span class="basis-value">{monthYear(basisPeriod)}</span>.
					{#if carried}
						<span class="carried-note">
							Carried forward — {monthYear(basisPeriod)}'s CPI-U print isn't published yet (CPI-U
							publishes one to two months in arrears). No action needed.
						</span>
					{/if}
				</p>
			{/if}
		</div>

		<div class="table-scroll">
			<table class="delta">
				<caption class="sr-only">
					Net worth change over five horizons — Month, YTD, 1-Year, 3-Year, and 5-Year — nominal
					and inflation-adjusted.
				</caption>
				<thead>
					<tr>
						<th scope="col">Horizon</th>
						<th scope="col" class="num">NAV Delta</th>
						<th scope="col" class="num">Inflation Adjusted</th>
					</tr>
				</thead>
				<tbody>
					{#each orderedRows as row (row.horizon)}
						<tr>
							<th scope="row">{HORIZON_LABEL[row.horizon]}</th>
							{#if isInsufficientHistory(row)}
								<td class="num" colspan="2">
									<span
										class="insufficient-badge"
										aria-label="Insufficient history — this horizon predates your earliest recorded NAV observation."
									>
										Insufficient history
									</span>
								</td>
							{:else}
								<td
									class="num"
									class:pos={signClass(row.delta_nominal) === 'pos'}
									class:neg={signClass(row.delta_nominal) === 'neg'}
								>
									{#if row.delta_nominal !== null}
										{formatSignedUsd(row.delta_nominal)}
										<span
											title={isPercentInexpressible(row)
												? 'Percent change cannot be expressed against a zero or negative starting value.'
												: undefined}
										>
											({row.delta_percent !== null ? formatSignedPercent(row.delta_percent) : '—'})
										</span>
									{:else}
										—
									{/if}
								</td>
								<td
									class="num"
									class:pos={signClass(row.delta_inflation_adjusted) === 'pos'}
									class:neg={signClass(row.delta_inflation_adjusted) === 'neg'}
								>
									{#if !isCpiApplicable(row.horizon)}
										—
									{:else if isCpiUnresolvable(row)}
										<span
											class="cpi-unavailable"
											title="Inflation-adjusted figure unavailable for this horizon — no CPI-U data on record."
										>
											CPI unavailable
										</span>
									{:else if row.delta_inflation_adjusted !== null}
										{formatSignedUsd(row.delta_inflation_adjusted)}
										<span
											title={isInflationPercentInexpressible(row)
												? 'Percent change cannot be expressed against a zero or negative deflated starting value.'
												: undefined}
										>
											({row.delta_inflation_adjusted_percent !== null
												? formatSignedPercent(row.delta_inflation_adjusted_percent)
												: '—'})
										</span>
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
	   NavHistoryChart / NavCompositionTable use for their own headings. */
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

	/* ── basis-line family — reproduces NavHistoryChart's .chart-basis-line vocabulary
	   verbatim (same tokens, same shape) so the two surfaces read as one system. ── */
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
	.panel-basis-line .basis-value {
		font-family: var(--font-num);
		color: var(--c-text-primary);
		font-weight: var(--weight-med);
	}
	.carried-note {
		display: block;
		margin-top: 2px;
		color: var(--c-text-muted);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css table.tbl with tokens only,
	   same shape as NavCompositionTable's .comp base. */
	.delta {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.delta th,
	.delta td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.delta thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.delta td.num,
	.delta th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.delta tbody th[scope='row'] {
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}

	/* VALUE-COLOR FENCE (§5 fence 1): every cell on this panel is a delta, so pos/neg
	   applies panel-wide — the inverse of the NAV headline / composition-position fence. */
	.delta td.num.pos {
		color: var(--c-pos);
	}
	.delta td.num.neg {
		color: var(--c-neg);
	}

	/* Insufficient-history — quiet neutral chip (NOT --c-attn-*: nothing actionable here,
	   unlike the re-auth stale-tag; this is a historical-depth fact, not a live condition). */
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

	/* CPI-unresolvable — the nominal figure stands (colored above); only this cell is
	   unformed. Neutral ink, italic, matches StaleConstituentBadge's "temporarily
	   unavailable" informational-text treatment (not a value, so no pos/neg). */
	.cpi-unavailable {
		font-style: italic;
		color: var(--c-text-muted);
		font-family: var(--font-ui);
	}
</style>
