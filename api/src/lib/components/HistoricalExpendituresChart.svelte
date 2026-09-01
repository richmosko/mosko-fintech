<!--
	HistoricalExpendituresChart.svelte — the §2.3.4 Historical Expenditures chart UI (SELF-256).
	Frontend-owned browser surface. Consumes `points` and `unclassifiedCount` — both from Backend's
	`loadHistoricalExpendituresPanel` (`$lib/server/queries/historicalExpendituresPanel.ts`),
	wired into cash-flow/+page.server.ts (475efeb) and threaded through as
	`data.historicalExpenditures` / `data.historicalExpendituresUnclassifiedCount` on
	cash-flow/+page.svelte. Authors NO server logic and performs NO re-derivation of any server-side
	rule — every number rendered here is exactly what the server computed; historical-
	expenditures.ts owns the presentation-only derivations this component reads.

	PLACEMENT: DECIDED (AC1, Visual Designer's ruling, relayed by team-lead) — a panel on the
	existing `/cash-flow` route, stacked below `CashflowRollupTable`, no dedicated route. See
	cash-flow/+page.svelte's own header for the mount-order rationale (mounted unconditionally,
	outside the rollup's own read-failed/empty/populated branching — this chart owns independent
	fail-soft gating in both directions). This component itself stays prop-driven (no
	`$app/state`/`$app/navigation` reads — this surface has no query-param-driven state, AC7), so
	it is exercised directly by HistoricalExpendituresChart.dom.test.ts with fixture props rather
	than through the route.

	LIVE LOADER CONTRACT (`historicalExpendituresPanel.ts`'s own header is canonical — read it live
	before touching this one, it is not restated in full here):
	  - `points: HistoricalExpenditurePoint[] | null` — one call to `pfin.fn_historical_expenditures`
	    (096). `null` = the RPC read failed (fail-soft, logged, never thrown); `[]` = the read
	    succeeded and the caller has no qualifying expense in the trailing 5-year window (096's own
	    dense-interior contract: ZERO rows is a real, distinguishable state, not an error).
	  - `unclassifiedCount: number | null` — AC9's window-scoped N. Sourced from migration 098's
	    `pfin.fn_expenditures_unclassified_count(p_as_of)`, a CoR'd pair with 096 (ONE `asOf`, ONE
	    JS call site — `loadHistoricalExpendituresPanel` invokes both RPCs together so the caller
	    can never thread two different `p_as_of` values by accident). `null` = the RPC read failed,
	    OR `p_as_of` could not be resolved (098's own NULL-on-NULL-argument contract); `0` = a real,
	    distinguishable answer — nothing unclassified in the window. NEVER coalesced to 0 anywhere
	    in the loader or here — this component's own N-gate (below) still treats `null` and `0` as
	    two different renders (no banner either way, but `0` is a real computed absence, not a gap).
	  - The two RPCs fail independently — one leg's failure never blocks the other (matches this
	    component's own per-prop null-tolerance).

	AC11 / SELF-258 SEAM: staleness markers are NOT wired here — SELF-258 (which consumes them)
	has not landed. The `<!-- SELF-258 seam -->` comment below marks the mount point, mirroring
	CashflowRollupTable.svelte's own seam convention for the identical reason.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { LayerCake, Svg } from 'layercake';
	import { scaleBand, scaleLinear } from 'd3-scale';
	import {
		isCpiWhollyUnavailable,
		carriedCount,
		latestCarriedPoint,
		cpiCoverageThrough,
		sharedYDomain,
		type HistoricalExpenditurePoint
	} from '$lib/historical-expenditures';
	import InformationalMarkerBadge from './InformationalMarkerBadge.svelte';
	import HistoricalExpendituresBars from './HistoricalExpendituresBars.svelte';

	let {
		points,
		unclassifiedCount = null,
		classifyHref = '/accounts'
	}: {
		points: HistoricalExpenditurePoint[] | null;
		/** AC9's window-scoped N — see the module header's LIVE LOADER CONTRACT (098's
		 * fn_expenditures_unclassified_count). `null` = the RPC failed or `p_as_of` couldn't be
		 * resolved (renders no banner/caption); `0` is a real, distinguishable computed value
		 * (also no banner/caption — N=0 has nothing to report — but it is NOT the same claim as
		 * `null`). */
		unclassifiedCount?: number | null;
		/** AC9 CTA target — CashflowRollupTable.svelte's own `classifyHref` precedent: SELF-249
		 * built classification INLINE on per-account transaction lists, not as a dedicated queue
		 * page, so `/accounts` is the best-available entry point pending a real §2.3.1 queue
		 * surface (same flagged default, not re-derived here). */
		classifyHref?: string;
	} = $props();

	// ---- state classification — mirrors NavHistoryChart's ordering rationale: a read failure
	// never reaches the "empty" state — they are different problems, not a ladder of increasingly
	// bad news about the same one. This surface has no `paramsError` state at all (AC7: no
	// user-configurable params exist to reject).
	const readFailed = $derived(points === null);
	const rows = $derived(points ?? []);
	const empty = $derived(!readFailed && rows.length === 0);
	const showChart = $derived(!readFailed && !empty);

	// ---- flows/phase-2-flows-2.3-spending.md §6 "CPI-U unavailable" fallback: every row's
	// adjusted figure is null (the CPI-U store has no usable coverage at all) → render the
	// NOMINAL series instead, with an explicit note, matching §2.1.2/NavHistoryChart's own
	// cpiUnavailable rule. A single unresolvable month is a DIFFERENT, per-row state (AC6),
	// handled inside HistoricalExpendituresBars — it must not trip this fallback.
	const wholeUnavailable = $derived(showChart && isCpiWhollyUnavailable(rows));
	const barField = $derived(
		wholeUnavailable ? 'expense_monthly_nominal' : 'expense_monthly_inflation_adjusted'
	) as 'expense_monthly_nominal' | 'expense_monthly_inflation_adjusted';

	// ---- series-level informational marker (AC6 / PRD §2.4.4 "one series-level mark, not one per
	// point" — 096's own header states the per-row cpi_* columns are the INPUTS to this
	// OR-reduction). Naturally zero under wholeUnavailable — see historical-expenditures.ts's
	// carriedCpiPoints header: a carried point requires a RESOLVED value, which cannot occur when
	// every row is unresolvable.
	const carriedCnt = $derived(carriedCount(rows));
	const latestCarried = $derived(latestCarriedPoint(rows));
	const coverageThrough = $derived(cpiCoverageThrough(rows));

	// ---- AC9: window-scoped unclassified banner + chart caption, ONE source (unclassifiedCount),
	// never re-derived. See the module header for why this is `null`-able today.
	const showUnclassifiedNotice = $derived(unclassifiedCount !== null && unclassifiedCount > 0);

	const yDomain = $derived(sharedYDomain(rows, barField));

	let activeMonthEnd: string | null = $state(null);
	const activePoint = $derived(rows.find((p) => p.month_end === activeMonthEnd) ?? null);

	const monthYearFmt = (iso: string) =>
		new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });
	const usd = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });
</script>

<section class="hist-expenditures" aria-labelledby="hist-expenditures-label">
	<header class="head">
		<h2 id="hist-expenditures-label" class="section-label">Historical Expenditures</h2>
		<!-- SELF-258 seam: a series-adjacent StaleConstituentBadge mounts here once SELF-258 lands.
		     Nothing renders at this seam today — see the module header. -->
	</header>

	<!-- AC9 — the S-2 unclassified banner (window-scoped, S-2-ruled copy: MUST NOT claim the
	     items ARE expenses). Absent entirely when unclassifiedCount is null (the RPC failed) or
	     0 (a real, distinguishable computed absence) — mirrors CashflowRollupTable.svelte's
	     identical N>0 gate + canary register. -->
	{#if showUnclassifiedNotice}
		<div class="unclassified-banner" role="status">
			<span class="unclassified-tag">
				<span class="unclassified-dot" aria-hidden="true"></span>
				<span class="unclassified-text">{unclassifiedCount} items unclassified — any of these may be expenses</span>
			</span>
			<span class="unclassified-sep" aria-hidden="true">—</span>
			<a class="unclassified-cta" href={classifyHref}>classify</a>
		</div>
	{/if}

	{#if readFailed}
		<p class="chart-notice">Historical expenditures are temporarily unavailable. Please try again shortly.</p>
	{:else if empty}
		<div class="chart-placeholder is-empty">
			<p class="empty-title">Classify your expense transactions to see your historical expenditures.</p>
			<a class="empty-cta" href={classifyHref}>Classify transactions</a>
		</div>
	{:else}
		<div class="chart-legend-row">
			<span class="chart-legend-entry">
				<span class="swatch-fill" aria-hidden="true"></span>
				{wholeUnavailable ? 'Monthly Expenses (Nominal)' : 'Monthly Expenses (Inflation-Adjusted)'}
			</span>
			{#if !wholeUnavailable}
				<span class="chart-legend-entry">
					<span class="swatch-line" aria-hidden="true"></span>
					12-Month Rolling Average
					{#if latestCarried}
						<InformationalMarkerBadge
							carriedCount={carriedCnt}
							cpiPeriod={latestCarried.cpi_period}
							carriedFrom={latestCarried.cpi_carried_from}
							nonpublicationOnRecord={latestCarried.cpi_nonpublication_on_record}
						/>
					{/if}
				</span>
			{/if}
		</div>

		<div class="chart-basis-stack">
			{#if wholeUnavailable}
				<p class="chart-basis-line cpi-basis-line">
					Inflation-adjusted figures are unavailable — no CPI-U data on record. Showing nominal figures.
				</p>
			{:else if coverageThrough}
				<p class="chart-basis-line cpi-basis-line">
					CPI-U through <span class="basis-value">{monthYearFmt(coverageThrough)}</span>.
				</p>
			{/if}
			{#if showUnclassifiedNotice}
				<p class="chart-basis-line unclassified-caption">
					Bars partial — {unclassifiedCount} unclassified.
				</p>
			{/if}
		</div>

		<div class="chart-canvas">
			<LayerCake
				data={rows}
				x={(d: HistoricalExpenditurePoint) => d.month_end}
				y={(d: HistoricalExpenditurePoint) => d[barField] ?? 0}
				xDomain={rows.map((d) => d.month_end)}
				{yDomain}
				xScale={scaleBand().paddingInner(0.25).paddingOuter(0.1)}
				yScale={scaleLinear()}
				padding={{ top: 16, right: 16, bottom: 32, left: 64 }}
			>
				<Svg>
					<HistoricalExpendituresBars
						points={rows}
						{barField}
						{activeMonthEnd}
						onHoverChange={(m) => (activeMonthEnd = m)}
					/>
				</Svg>
			</LayerCake>

			<!-- AC8 tooltip — presentational only; the SAME content is also the active bar's
			     aria-label (screen-reader parity), rendered here for sighted hover/focus users. -->
			{#if activePoint}
				<div class="chart-tooltip" role="status">
					<p class="tooltip-month">{monthYearFmt(activePoint.month_end)}</p>
					<dl class="tooltip-fields">
						<dt>Nominal</dt>
						<dd>{usd.format(activePoint.expense_monthly_nominal)}</dd>
						<dt>Inflation-adjusted</dt>
						<dd>
							{activePoint.expense_monthly_inflation_adjusted === null
								? 'Unavailable'
								: usd.format(activePoint.expense_monthly_inflation_adjusted)}
						</dd>
						<dt>12-mo rolling avg</dt>
						<dd>
							{activePoint.rolling_12mo_avg_inflation_adjusted === null
								? 'Not yet available'
								: usd.format(activePoint.rolling_12mo_avg_inflation_adjusted)}
						</dd>
					</dl>
				</div>
			{/if}
		</div>
	{/if}
</section>

<style>
	/* Component-scoped intrinsic constant, shared by the empty state and the real chart canvas —
	   same "component-intrinsic constant" category as NavHistoryChart's own --_chart-canvas-height
	   (Visual's ruling there: no design-system token needed). */
	.hist-expenditures {
		--_chart-canvas-height: 20rem;
	}

	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		margin-bottom: var(--space-2);
	}

	.section-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}

	.chart-notice {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}

	/* ── chart-placeholder empty state (mirrors NavHistoryChart's, plus AC10's CTA) ──────── */
	.chart-placeholder.is-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		height: var(--_chart-canvas-height);
		border: 1px dashed var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		text-align: center;
		padding: var(--space-5);
	}
	.empty-title {
		margin: 0;
		font: var(--weight-med) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
		font-style: italic;
	}
	.empty-cta {
		color: var(--c-link);
		font-size: var(--fs-small);
		text-decoration: underline;
	}
	.empty-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	/* ── AC9 unclassified banner — CashflowRollupTable.svelte's own canary-register styling,
	     reproduced verbatim (§5 fence 8: a genuine, actionable, financially-material fact). ── */
	.unclassified-banner {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
		align-self: flex-start;
		margin-bottom: var(--space-2);
	}
	.unclassified-tag {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		padding: var(--space-1) var(--space-2);
		border: 1px solid var(--c-attn-border);
		border-left: var(--space-1) solid var(--c-attn-solid);
		border-radius: var(--radius-sm);
		background: var(--c-attn-bg);
		color: var(--c-attn-text);
		font: var(--weight-semi) var(--fs-small) / 1 var(--font-ui);
	}
	.unclassified-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		flex: 0 0 auto;
	}
	.unclassified-cta {
		color: var(--c-attn-text);
		font-weight: var(--weight-semi);
		text-decoration: underline;
		white-space: nowrap;
	}
	.unclassified-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.unclassified-caption {
		font-style: italic;
	}

	/* ── legend row ───────────────────────────────────────────────────────────────────── */
	.chart-legend-row {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-3);
		margin-bottom: var(--space-2);
	}
	.chart-legend-entry {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.swatch-fill {
		display: inline-block;
		width: 14px;
		height: 10px;
		background: var(--c-viz-fill);
		vertical-align: middle;
	}
	.swatch-line {
		display: inline-block;
		width: 18px;
		height: 2px;
		background: var(--c-viz-infl);
		vertical-align: middle;
	}

	/* ── basis-line family (NavHistoryChart's own token set, reused verbatim) ───────────── */
	.chart-basis-stack {
		display: flex;
		flex-direction: column;
		gap: 2px;
		margin-bottom: var(--space-2);
	}
	.chart-basis-line {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		line-height: var(--lh-body);
	}
	.chart-basis-line .basis-value {
		font-family: var(--font-num);
		color: var(--c-text-primary);
		font-weight: var(--weight-med);
	}

	/* ── chart canvas ─────────────────────────────────────────────────────────────────── */
	.chart-canvas {
		position: relative;
		width: 100%;
		height: var(--_chart-canvas-height);
	}

	.chart-tooltip {
		position: absolute;
		top: var(--space-2);
		right: var(--space-2);
		max-width: 16rem;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		box-shadow: var(--shadow-2);
		pointer-events: none;
	}
	.tooltip-month {
		margin: 0 0 var(--space-1);
		font: var(--weight-semi) var(--fs-small) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.tooltip-fields {
		display: grid;
		grid-template-columns: auto auto;
		column-gap: var(--space-2);
		row-gap: 2px;
		margin: 0;
	}
	.tooltip-fields dt {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.tooltip-fields dd {
		margin: 0;
		font-family: var(--font-num);
		font-size: var(--fs-small);
		color: var(--c-text-primary);
		text-align: right;
	}
</style>
