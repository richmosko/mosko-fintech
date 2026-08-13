<!--
	NavChartLines.svelte — the SVG drawing layer for the §2.1.2.d NAV chart
	(SELF-220). Rendered as a LayerCake child (inside <Svg>) so it can read the
	shared x/y scales via `getContext('LayerCake')` — LayerCake's context is set BY
	the <LayerCake> component and is only reachable from ITS descendants, which is
	why this drawing logic can't live in the parent orchestrator (NavHistoryChart)
	directly.

	Draws, in order: axis ticks, the solid nominal line (SPLIT at the cron/imported
	boundary into a stepped pre-boundary segment and a normal post-boundary segment
	— §12.6 "honest stepped/plateaued shape... never a smoothed interpolation"), the
	gap-aware dashed inflation-adjusted line (one <path> per contiguous non-NULL
	run — §12.5, never interpolated across a NULL), post-boundary staleness markers
	(§12.1/§12.2 — pre-boundary carried points get NO marker, by construction, since
	they're excluded from the filter below), and a drag-to-zoom overlay (§12.7).

	Tokens only (var(--c-*)) for every stroke/fill; no hardcoded hex.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import type { Readable } from 'svelte/store';
	import { line as d3line, curveStepAfter, curveLinear } from 'd3-shape';
	import type { ScaleTime, ScaleLinear } from 'd3-scale';
	import {
		inflationAdjustedSegments,
		isCarriedNavPoint,
		type NavSeriesPoint
	} from '$lib/nav-series';
	import { isImportedEraPoint, shouldSuppressCarryStaleness, type NavBoundary } from '$lib/nav-boundary';

	/** The slice of LayerCake's context this component reads. LayerCake's own
	 * .d.ts types the context as a slot-prop bag (its Svelte-4-legacy internals
	 * expose these as stores via getContext, not as slot props — see the module
	 * header); this local interface documents the actual runtime shape rather
	 * than fighting the library's generated types. */
	interface LayerCakeContext {
		xScale: Readable<ScaleTime<number, number>>;
		yScale: Readable<ScaleLinear<number, number>>;
		width: Readable<number>;
		height: Readable<number>;
		padding: Readable<{ top: number; right: number; bottom: number; left: number }>;
	}

	let {
		points,
		boundary,
		sparse = false,
		windowMonths = 60,
		onZoom
	}: {
		points: NavSeriesPoint[];
		boundary: NavBoundary;
		/** §12.9: fewer than 12 distinct months of history — draws the LEFT hatch
		 * region between the frame's left edge and the line's own tracking-start. */
		sparse?: boolean;
		/** Total requested window width in whole months (the "of N" denominator for
		 * the §12.9 calibration label) — computed by the parent from params.start/end,
		 * never hardcoded to 60: a drilled/zoomed sub-range has a narrower window. */
		windowMonths?: number;
		/** Called with (startIso, endIso) once a drag or point-click selection completes. */
		onZoom: (startIso: string, endIso: string) => void;
	} = $props();

	const { xScale, yScale, width, height, padding } = getContext<LayerCakeContext>('LayerCake');

	const toDate = (p: NavSeriesPoint) => new Date(`${p.point_date}T00:00:00Z`);
	const toIso = (d: Date) => d.toISOString().slice(0, 10);

	// ---- nominal line, split at the boundary (§12.6) ----
	// isImportedEraPoint, NOT isPreBoundaryPoint directly — the imported-only state
	// (has_cron_rows === false) has NO boundary date to compare against, and every
	// point in it is imported by definition of the state. Using isPreBoundaryPoint
	// alone here was a real bug (Architect, 2026-08-13): it classified every point
	// as post-boundary in that state (since "before null" is false), so the WHOLE
	// imported-only series lost its stepped/plateau treatment. See nav-boundary.ts's
	// isImportedEraPoint header for the full four-state reasoning.
	const preBoundaryPoints = $derived(points.filter((p) => isImportedEraPoint(p.point_date, boundary)));
	const postBoundaryPoints = $derived(points.filter((p) => !isImportedEraPoint(p.point_date, boundary)));
	// The two segments share their join point (the last pre-boundary point re-appears
	// as the first post-boundary point isn't guaranteed — nav_daily rows are keyed by
	// distinct dates, so the boundary date itself is POST-boundary by construction
	// (isImportedEraPoint is strict '<' in the states where a boundary date exists).
	// To avoid a visible gap at the join, the pre-boundary path is extended with the
	// first post-boundary point as its final vertex — drawn once by the pre-boundary
	// path (stepped) and again as the start of the post-boundary path (linear); the
	// two agree exactly at that shared vertex so no seam is visible.
	const preBoundaryJoined = $derived(
		postBoundaryPoints.length > 0 ? [...preBoundaryPoints, postBoundaryPoints[0]] : preBoundaryPoints
	);

	const nominalPreBoundaryPath = $derived(
		preBoundaryJoined.length > 0
			? d3line<NavSeriesPoint>()
					.x((d) => $xScale(toDate(d)))
					.y((d) => $yScale(d.nav_nominal))
					.curve(curveStepAfter)(preBoundaryJoined)
			: null
	);
	const nominalPostBoundaryPath = $derived(
		postBoundaryPoints.length > 0
			? d3line<NavSeriesPoint>()
					.x((d) => $xScale(toDate(d)))
					.y((d) => $yScale(d.nav_nominal))
					.curve(curveLinear)(postBoundaryPoints)
			: null
	);

	// ---- inflation-adjusted dashed line, gap-aware (§12.5) ----
	const inflSegments = $derived(inflationAdjustedSegments(points));
	const inflPaths = $derived(
		inflSegments.map(
			(seg) =>
				d3line<NavSeriesPoint>()
					.x((d) => $xScale(toDate(d)))
					.y((d) => $yScale(d.nav_inflation_adjusted as number))
					.curve(curveLinear)(seg) ?? ''
		)
	);

	// ---- post-boundary staleness markers (§12.1/§12.2) ----
	// Pre-boundary carried points are excluded HERE, by construction — not filtered
	// out of a larger set, never rendered as stale at all.
	const staleMarkers = $derived(
		points.filter((p) => isCarriedNavPoint(p) && !shouldSuppressCarryStaleness(p.point_date, boundary))
	);

	// ---- sparse-history hatch region (§12.9) ----
	// The line is right-anchored (ends at today, the frame's right edge); the hatch
	// occupies the LEFT span between the frame's left edge and the line's own
	// tracking-start (points[0]) — months that predate this user's tracking, never
	// "months not yet lived". A flat right edge (at tracking-start), never the
	// open/rounded-stub treatment used for an isolated CPI/NULL gap (§12.5) — a
	// truncation is a deliberate boundary, not an absence, and must not read the same.
	const trackingStartPx = $derived(points.length > 0 ? $xScale(toDate(points[0])) : 0);
	const monthsOfHistory = $derived(points.length > 0 ? uniqueMonthCount(points) : 0);

	function uniqueMonthCount(pts: NavSeriesPoint[]): number {
		return new Set(pts.map((p) => p.point_date.slice(0, 7))).size;
	}

	// ---- axis ticks ----
	const xTicks = $derived($xScale.ticks(6));
	const yTicks = $derived($yScale.ticks(5));
	const dateFmt = new Intl.DateTimeFormat('en-US', { month: 'short', year: '2-digit', timeZone: 'UTC' });
	const currencyFmt = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		notation: 'compact',
		maximumFractionDigits: 1
	});

	// ---- drag-to-zoom (§12.7: click-drag a range, or click a point) ----
	let dragStartPx: number | null = $state(null);
	let dragCurrentPx: number | null = $state(null);
	const dragging = $derived(dragStartPx !== null && dragCurrentPx !== null);
	// Control-flow narrowing (an early return after the null-check) rather than an
	// `as number` cast — cleaner and sidesteps `dragStartPx`/`dragCurrentPx`'s
	// `number | null` type not narrowing across the separate `dragging` derivation.
	const dragRectX = $derived.by(() => {
		if (dragStartPx === null || dragCurrentPx === null) return 0;
		return Math.min(dragStartPx, dragCurrentPx);
	});
	const dragRectWidth = $derived.by(() => {
		if (dragStartPx === null || dragCurrentPx === null) return 0;
		return Math.abs(dragCurrentPx - dragStartPx);
	});

	function plotAreaX(clientX: number, svgEl: SVGSVGElement): number {
		const rect = svgEl.getBoundingClientRect();
		return clientX - rect.left;
	}

	function onPointerDown(event: PointerEvent) {
		const svg = (event.currentTarget as SVGElement).ownerSVGElement ?? (event.currentTarget as unknown as SVGSVGElement);
		dragStartPx = plotAreaX(event.clientX, svg);
		dragCurrentPx = dragStartPx;
		(event.target as Element).setPointerCapture(event.pointerId);
	}
	function onPointerMove(event: PointerEvent) {
		if (dragStartPx === null) return;
		const svg = (event.currentTarget as SVGElement).ownerSVGElement ?? (event.currentTarget as unknown as SVGSVGElement);
		dragCurrentPx = plotAreaX(event.clientX, svg);
	}
	function onPointerUp() {
		if (dragStartPx === null || dragCurrentPx === null) return;
		const pxDelta = Math.abs(dragCurrentPx - dragStartPx);
		// Below-threshold movement reads as a POINT CLICK (§12.7 "or click a point"):
		// zoom to a small window centered on that date rather than requiring a real drag.
		const CLICK_THRESHOLD_PX = 4;
		let startDate: Date;
		let endDate: Date;
		if (pxDelta < CLICK_THRESHOLD_PX) {
			const centerDate = $xScale.invert(dragCurrentPx);
			startDate = new Date(centerDate.getTime() - 15 * 86_400_000);
			endDate = new Date(centerDate.getTime() + 15 * 86_400_000);
		} else {
			const a = $xScale.invert(Math.min(dragStartPx, dragCurrentPx));
			const b = $xScale.invert(Math.max(dragStartPx, dragCurrentPx));
			startDate = a;
			endDate = b;
		}
		dragStartPx = null;
		dragCurrentPx = null;
		onZoom(toIso(startDate), toIso(endDate));
	}
</script>

<!-- Sparse-history hatch region (§12.9) — LEFT span, flat right edge at tracking-start -->
{#if sparse && points.length > 0}
	<defs>
		<pattern id="sparse-hatch" patternUnits="userSpaceOnUse" width="8" height="8" patternTransform="rotate(135)">
			<rect width="8" height="8" class="sparse-region-bg" />
			<line x1="0" y1="0" x2="0" y2="8" class="sparse-region-hatch-line" />
		</pattern>
	</defs>
	<rect x={0} y={0} width={trackingStartPx} height={$height} fill="url(#sparse-hatch)" aria-hidden="true" />
	<text
		x={Math.max(4, trackingStartPx - 8)}
		y={$height - 8}
		class="sparse-label"
		text-anchor="end"
	>
		{monthsOfHistory} of {windowMonths} months of history
	</text>
{/if}

<!-- Axis gridlines + ticks -->
<g class="axis axis-y" aria-hidden="true">
	{#each yTicks as t (t)}
		<line x1={0} x2={$width} y1={$yScale(t)} y2={$yScale(t)} class="gridline" />
		<text x={-8} y={$yScale(t)} class="tick-label tick-label-y" text-anchor="end" dominant-baseline="middle">
			{currencyFmt.format(t)}
		</text>
	{/each}
</g>
<g class="axis axis-x" aria-hidden="true">
	{#each xTicks as t (t.getTime())}
		<text x={$xScale(t)} y={$height + 16} class="tick-label tick-label-x" text-anchor="middle">
			{dateFmt.format(t)}
		</text>
	{/each}
</g>

<!-- Pre-boundary nominal segment: honest stepped/plateaued shape (§12.6) -->
{#if nominalPreBoundaryPath}
	<path d={nominalPreBoundaryPath} class="line line-nominal line-stepped" />
{/if}
<!-- Post-boundary nominal segment: normal linear join between real day-close checkpoints -->
{#if nominalPostBoundaryPath}
	<path d={nominalPostBoundaryPath} class="line line-nominal" />
{/if}

<!-- Inflation-adjusted dashed line, one <path> per gap-free run (§12.5) -->
{#each inflPaths as d, i (i)}
	<path {d} class="line line-infl" />
{/each}

<!-- Post-boundary staleness markers (§12.1/§12.2) -->
{#each staleMarkers as p (p.point_date)}
	<circle
		cx={$xScale(toDate(p))}
		cy={$yScale(p.nav_nominal)}
		r="4"
		class="stale-marker"
		role="img"
		aria-label={`NAV checkpoint carried from ${p.checkpoint_date} to ${p.point_date}`}
	>
		<title>NAV checkpoint carried from {p.checkpoint_date} to {p.point_date}</title>
	</circle>
{/each}

<!-- Drag-to-zoom overlay (§12.7) -->
<rect
	x={0}
	y={0}
	width={$width}
	height={$height}
	class="zoom-overlay"
	role="button"
	tabindex="0"
	aria-label="Drag to zoom into a date range, or press Enter for keyboard zoom instructions"
	onpointerdown={onPointerDown}
	onpointermove={onPointerMove}
	onpointerup={onPointerUp}
/>
{#if dragging}
	<rect x={dragRectX} y={0} width={dragRectWidth} height={$height} class="zoom-selection" aria-hidden="true" />
{/if}

<style>
	/* §12.9 sparse-history hatch — Visual Designer's spec (temp/visual-designer-
	   self220-tokens.md §3), ported from a CSS repeating-linear-gradient (the
	   original was written for an HTML div) to an SVG <pattern>, same visual
	   result: a diagonal hatch on a muted neutral fill. Deliberately NOT
	   --c-viz-fill — that token means "area under a real value"; reusing it here
	   would visually claim data exists where it doesn't. */
	.sparse-region-bg {
		fill: var(--c-surface-alt);
	}
	.sparse-region-hatch-line {
		stroke: var(--c-border);
		stroke-width: 1;
	}
	.sparse-label {
		font-size: var(--fs-small);
		fill: var(--c-text-muted);
		font-style: italic;
	}
	.gridline {
		stroke: var(--c-border);
		stroke-width: 1;
	}
	.tick-label {
		font-family: var(--font-num);
		font-size: var(--fs-small);
		fill: var(--c-text-muted);
	}
	.line {
		fill: none;
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
	}
	.line-nominal {
		stroke: var(--c-viz-nominal);
	}
	/* .line-stepped carries no styling of its own — the pre-boundary segment uses
	   the SAME token/weight as the rest of the nominal line. The STEPPED SHAPE
	   itself (curveStepAfter, applied in script) is the pre-boundary signal, not a
	   color change (§12.6: "the resolution limit is legible even before any text
	   is read" — via shape, not a second hue). The class is kept on the element as
	   a query hook (tests / future styling) even though it adds no rules today. */
	.line-infl {
		stroke: var(--c-viz-infl);
		stroke-dasharray: 6 4;
	}
	.stale-marker {
		fill: var(--c-attn-solid);
		stroke: var(--c-surface);
		stroke-width: 1.5;
		cursor: help;
	}
	.zoom-overlay {
		fill: transparent;
		cursor: crosshair;
	}
	.zoom-overlay:focus-visible {
		outline: none;
		stroke: var(--c-accent);
		stroke-width: 2;
	}
	.zoom-selection {
		fill: var(--c-accent-soft);
		opacity: 0.5;
		pointer-events: none;
	}
</style>
