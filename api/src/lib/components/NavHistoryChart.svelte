<!--
	NavHistoryChart.svelte — the §2.1.2.d NAV-over-time chart (SELF-220 · V1.1).
	Frontend-owned browser surface. Consumes `data.navSeries` / `data.navSeriesParams`
	/ `data.navSeriesParamsError` (Backend's +page.server.ts loader over 067) and
	`data.navBoundary` (069 — NOT YET WIRED by Backend as of this build; the caller
	passes EMPTY_NAV_BOUNDARY until that load-path lands, which safely renders as
	"no boundary" — every point treated as post-boundary, matching today's actual
	behavior with zero cron/imported disposition since the caller has no way to know
	otherwise yet). Authors NO server logic.

	Mount point: below `NavCompositionTable` on the existing dashboard route (§7 Open
	Decision 1 / the P2 single-canvas pattern), per flows/phase-2-flows-2.1-net-worth.md
	§12 (merged dba7bf1) — the interaction/marker spec this component implements.

	Rendering approach: LayerCake (F/CTO-ratified 2026-08-12, round 3 of the charting
	proposal — headless scaffolding only; every drawing/interaction primitive below
	is hand-built, per that ratify). See NavChartLines.svelte for the actual SVG
	drawing layer (rendered as a LayerCake child so it can read the shared scales).

	Chart-placeholder states (design-system-spec.md §4): this component gates among
	them; NavChartLines only ever renders in the `default` state.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). CSS for the
	legend row / basis-line family / informational badge is Visual Designer's
	deliverable (temp/visual-designer-self220-tokens.md), reproduced verbatim.

	D1 stale-data-marker (SELF-229 ramp): `staleness` is the SAME whole-user
	`046` fn_aggregation_has_stale_constituent() payload the §2.1.1 headline already
	consumes (+page.server.ts's `data.staleness`, threaded down unchanged — the fn takes
	no scope filter, so every consuming surface reads the identical aggregate). Rendered
	beside this surface's own section heading (D1: mark adjacent to the surface, never a
	floating banner — that's the separate P4 reauth-staleness-banner, SELF-207 territory).
	Per ADR-013 D1 (staleness-marking surface scope is illustrative, not exhaustive), further
	surfaces ramp later — Sec F4 (AMBER round): read D1 live, this line is a paraphrase not a quote.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { LayerCake, Svg } from 'layercake';
	import { scaleTime, scaleLinear } from 'd3-scale';
	import {
		isCpiUnavailable,
		isSparseHistory,
		type NavSeriesPoint,
		type NavSeriesGranularity
	} from '$lib/nav-series';
	import { EMPTY_NAV_BOUNDARY, resolutionDisclosureFires, type NavBoundary } from '$lib/nav-boundary';
	import { sharedYDomain, suggestGranularity, autoNarrowWindow } from '$lib/nav-chart-domain';
	import { NAV_SERIES_PARAM_PREFIX } from '$lib/schemas/nav-series-params';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import ChartGranularityChipGroup from './ChartGranularityChipGroup.svelte';
	import InformationalMarkerBadge from './InformationalMarkerBadge.svelte';
	import NavChartLines from './NavChartLines.svelte';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B) (F/CTO-ruled): `staleness` is REQUIRED, no default — a caller that forgets to
	// thread real staleness data now fails at TYPECHECK, not as a silent "confirmed healthy"
	// fallback. The live mount (+page.svelte) already passes the real loader value unconditionally.
	// (`boundary` keeps its own pre-existing EMPTY_NAV_BOUNDARY default — a different signal, out
	// of scope for this Sec finding.)
	let {
		points,
		paramsError,
		params,
		boundary = EMPTY_NAV_BOUNDARY,
		staleness
	}: {
		points: NavSeriesPoint[] | null;
		paramsError: string | null;
		params: { granularity: NavSeriesGranularity; start: string; end: string };
		boundary?: NavBoundary;
		staleness: StalenessData;
	} = $props();

	// ---- state classification — see the module header for why these are checked
	// in this order (an error never reaches a "read failed" state; a failed read
	// never reaches an "empty" state — each is a DIFFERENT problem, not a ladder of
	// increasingly-bad news about the same one). ----
	const hasError = $derived(paramsError !== null);
	const readFailed = $derived(!hasError && points === null);
	const rows = $derived(points ?? []);
	const empty = $derived(!hasError && points !== null && rows.length === 0);
	const showChart = $derived(!hasError && !readFailed && !empty);
	const sparse = $derived(showChart && isSparseHistory(rows));
	const cpiUnavailable = $derived(showChart && isCpiUnavailable(rows));

	// ---- basis-line / badge derivations ----
	const discloseResolution = $derived(resolutionDisclosureFires(boundary, rows));
	const carriedCpiPoints = $derived(rows.filter((p) => p.cpi_is_carried && p.cpi_period_was_due));
	const carriedPeriods = $derived(new Set(carriedCpiPoints.map((p) => p.cpi_period)));
	const carriedCount = $derived(carriedPeriods.size);
	const latestCarried = $derived(
		carriedCpiPoints.length > 0 ? carriedCpiPoints[carriedCpiPoints.length - 1] : null
	);
	const cpiCoverageThrough = $derived(rows.find((p) => p.cpi_coverage_through !== null)?.cpi_coverage_through ?? null);

	const monthYear = (iso: string) =>
		new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });

	// ---- chart geometry ----
	const xDomain = $derived<[Date, Date]>([
		new Date(`${params.start}T00:00:00Z`),
		new Date(`${params.end}T00:00:00Z`)
	]);
	const yDomain = $derived(sharedYDomain(rows));
	const windowMonths = $derived(monthsBetween(params.start, params.end));

	function monthsBetween(startIso: string, endIso: string): number {
		const start = new Date(`${startIso}T00:00:00Z`);
		const end = new Date(`${endIso}T00:00:00Z`);
		return (
			(end.getUTCFullYear() - start.getUTCFullYear()) * 12 + (end.getUTCMonth() - start.getUTCMonth())
		);
	}

	// ---- §12.7 granularity toggle + zoom/drill navigation ----
	const suggested = $derived(suggestGranularity(params.start, params.end));
	// NAMESPACED (F/CTO-ratified 2026-08-13, Sec's param-fence finding): scoped to whether
	// THIS surface's own chart_* params are present, not whether the URL carries ANY query
	// string at all — a stray unrelated param (a tracker's ?utm_source=, anything) must not
	// make the breadcrumb claim "you've drilled into a custom range" when nothing chart-
	// related has changed. Same reasoning as the schema-level namespace fix in
	// $lib/schemas/nav-series-params.ts: this surface's state is scoped to keys it owns.
	const showResetBreadcrumb = $derived(
		Array.from(page.url.searchParams.keys()).some((k) => k.startsWith(NAV_SERIES_PARAM_PREFIX))
	);

	function navigateTo(granularity: NavSeriesGranularity, start: string, end: string) {
		const url = new URL(page.url);
		url.searchParams.set(`${NAV_SERIES_PARAM_PREFIX}granularity`, granularity);
		url.searchParams.set(`${NAV_SERIES_PARAM_PREFIX}start`, start);
		url.searchParams.set(`${NAV_SERIES_PARAM_PREFIX}end`, end);
		goto(url.toString(), { keepFocus: true, noScroll: true });
	}

	function selectGranularity(g: NavSeriesGranularity) {
		// §12.7 density-bound: switching to Weekly/Daily on a too-wide view narrows
		// to a shorter recent default; Monthly (or an already-narrow view) is a no-op
		// on the range, only the granularity itself changes.
		const narrowed = autoNarrowWindow(g, params.start, params.end);
		navigateTo(g, narrowed?.start ?? params.start, narrowed?.end ?? params.end);
	}

	function handleZoom(start: string, end: string) {
		// A drilled range auto-applies its suggested granularity (§12.7) — the
		// chip-group still shows it and the user can immediately pick a different one.
		navigateTo(suggestGranularity(start, end), start, end);
	}

	function resetWindow() {
		// NAMESPACED: clears only this surface's own chart_* keys, not `url.search = ''`
		// wholesale — the prior form wiped ANY other page param a reset click happened to
		// find on the URL, which is exactly the page-scoped blast radius the namespace fix
		// closes everywhere else on this surface too.
		const url = new URL(page.url);
		for (const key of Array.from(url.searchParams.keys())) {
			if (key.startsWith(NAV_SERIES_PARAM_PREFIX)) url.searchParams.delete(key);
		}
		goto(url.toString(), { keepFocus: true, noScroll: true });
	}
</script>

<section class="nav-history" aria-labelledby="nav-history-label">
	<h2 id="nav-history-label" class="section-label">Net Worth Over Time</h2>
	<!-- D1 stale-data-marker: marks stale contribution beside the surface, never hides it. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

	{#if hasError}
		<p class="chart-notice">Chart parameters were invalid: {paramsError}</p>
		<button type="button" class="chart-reset-link" onclick={resetWindow}>Reset to default view</button>
	{:else if readFailed}
		<p class="chart-notice">Net worth history is temporarily unavailable. Please try again shortly.</p>
	{:else if empty}
		<div class="chart-placeholder is-empty">
			<p class="empty-title">Collect data over time.</p>
			<p class="empty-subtext">Your net-worth trend will appear here once monthly reviews accumulate history.</p>
		</div>
	{:else}
		<div class="chart-legend-row">
			<span class="chart-legend-entry">
				<span class="swatch-line nominal" aria-hidden="true"></span>
				Net Worth (Nominal)
			</span>
			{#if !cpiUnavailable}
				<span class="chart-legend-entry">
					<span class="swatch-line infl" aria-hidden="true"></span>
					Net Worth (Inflation-Adjusted)
					{#if latestCarried}
						<InformationalMarkerBadge
							{carriedCount}
							cpiPeriod={latestCarried.cpi_period}
							carriedFrom={latestCarried.cpi_carried_from}
							nonpublicationOnRecord={latestCarried.cpi_nonpublication_on_record}
						/>
					{/if}
				</span>
			{/if}
		</div>

		<div class="chart-basis-stack">
			{#if cpiUnavailable}
				<p class="chart-basis-line cpi-basis-line">
					Inflation-adjusted figures are unavailable for this range — no CPI-U data on record.
				</p>
			{:else if cpiCoverageThrough}
				<p class="chart-basis-line cpi-basis-line">
					Real terms, CPI-U through <span class="basis-value">{monthYear(cpiCoverageThrough)}</span>.
				</p>
			{/if}
			{#if discloseResolution}
				<p class="chart-basis-line resolution-disclosure">
					{#if boundary.first_cron_checkpoint}
						Monthly resolution before <span class="basis-value">{monthYear(boundary.first_cron_checkpoint)}</span>.
					{:else}
						Monthly resolution — daily/weekly tracking hasn't started yet.
					{/if}
				</p>
			{/if}
		</div>

		<!-- LayerCake's generated .d.ts under-types xDomain (omits Date[] even though
		     a scaleTime() domain is exactly what it's for) — the runtime passes this
		     straight to d3-scale's own .domain(), which accepts Date[] for a time
		     scale. Cast narrowly below rather than fight the .d.ts. -->
		<div class="chart-canvas">
			<LayerCake
				data={rows}
				x={(d: NavSeriesPoint) => new Date(`${d.point_date}T00:00:00Z`)}
				y={(d: NavSeriesPoint) => d.nav_nominal}
				xDomain={xDomain as unknown as [number, number]}
				{yDomain}
				xScale={scaleTime()}
				yScale={scaleLinear()}
				padding={{ top: 16, right: 16, bottom: 32, left: 64 }}
			>
				<Svg>
					<NavChartLines points={rows} {boundary} {sparse} {windowMonths} onZoom={handleZoom} />
				</Svg>
			</LayerCake>
		</div>

		<div class="chart-controls">
			<ChartGranularityChipGroup selected={params.granularity} {suggested} onSelect={selectGranularity} />
			{#if showResetBreadcrumb}
				<button type="button" class="chart-reset-link" onclick={resetWindow}>
					Reset to 60 months
				</button>
			{:else}
				<span class="chart-range-label">Showing: {monthYear(params.start)} – {monthYear(params.end)}</span>
			{/if}
		</div>
	{/if}
</section>

<style>
	/* Component-scoped custom property, set once and referenced by both the empty
	   placeholder and the real chart canvas below — Visual Designer's optional DRY
	   suggestion, taken: keeps the two states' height from silently drifting apart
	   if one is ever tuned without the other. NOT a design-system token (Visual's
	   ruling: no token needed here — same "component-intrinsic constant" category
	   as count-badge's 1.25rem, per design-system-spec.md §4). */
	.nav-history {
		--_chart-canvas-height: 20rem;
	}

	.section-label {
		margin: 0 0 var(--space-3);
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

	/* ── chart-placeholder empty state (§12.8) ───────────────────────────── */
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
	.empty-subtext {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}

	/* ── legend row (Visual Designer §4 — static flex row, not an absolute overlay) ── */
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
	.swatch-line {
		display: inline-block;
		width: 18px;
		height: 2px;
		vertical-align: middle;
	}
	.swatch-line.nominal {
		background: var(--c-viz-nominal);
	}
	.swatch-line.infl {
		background: var(--c-viz-infl);
	}

	/* ── chart-basis-line family (Visual Designer §2, verbatim) ──────────── */
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

	/* ── chart canvas — LayerCake needs an explicit sized container ─────── */
	.chart-canvas {
		width: 100%;
		/* Visual Designer's ruling: no design-system token needed for a chart-canvas
		   intrinsic dimension (component-intrinsic constant, same category as
		   count-badge's 1.25rem — design-system-spec.md §4). Shared with the empty
		   placeholder above via --_chart-canvas-height so the two never drift apart. */
		height: var(--_chart-canvas-height);
	}

	.chart-controls {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: var(--space-3);
		margin-top: var(--space-3);
	}
	.chart-reset-link {
		background: none;
		border: none;
		padding: 0;
		color: var(--c-link);
		font-size: var(--fs-small);
		cursor: pointer;
		text-decoration: underline;
	}
	.chart-reset-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.chart-range-label {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
</style>
