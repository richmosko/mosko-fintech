<!--
	HistoricalExpendituresBars.svelte — the SVG drawing layer for the §2.3.4 Historical
	Expenditures chart (SELF-256). Rendered as a LayerCake child (inside <Svg>) so it can read
	the shared x/y scales via `getContext('LayerCake')` — same wiring pattern as NavChartLines.svelte
	(SELF-220), which this component otherwise diverges from: a BAND x-scale over discrete months
	(not a continuous time scale — there is no zoom/drill on this surface, AC7), one bar series
	(the ACTIVE field — inflation-adjusted normally, nominal under the whole-series-unavailable
	fallback; never both), and one overlay line (the 12-month rolling average, gap-aware).

	Draws, in order: axis gridlines/ticks, per-month bars (a hatched "unavailable" swatch in place
	of a real bar wherever isAdjustedUnavailable — AC6's per-row 066-consumer rule, reusing the
	design-system-spec.md §4 sparse-history hatch tokens for the SAME semantic, "no real value
	here", never --c-viz-fill for that swatch), the rolling-average overlay as one <path> per
	contiguous non-null run (AC5's first-11-months gap falls out of this for free), and a
	per-month invisible hit-target (keyboard + hover) driving the parent's tooltip (AC8).

	Tokens only (var(--c-*)) for every stroke/fill; no hardcoded hex. NO --c-pos/--c-neg — that
	pair is FENCED to actual-performance surfaces only and explicitly forbidden on §2.3
	(tokens.css's own FENCES note) — sign is expressed by bar DIRECTION (above/below the y=0
	baseline), never by color.
-->
<script lang="ts">
	import { getContext } from 'svelte';
	import type { Readable } from 'svelte/store';
	import { line as d3line, curveLinear } from 'd3-shape';
	import type { ScaleBand, ScaleLinear } from 'd3-scale';
	import {
		isAdjustedUnavailable,
		adjustedUnavailableReason,
		rollingAverageSegments,
		type HistoricalExpenditurePoint
	} from '$lib/historical-expenditures';

	/** The slice of LayerCake's context this component reads — same runtime-shape note as
	 * NavChartLines.svelte's own interface (LayerCake's generated .d.ts under-documents this). */
	interface LayerCakeContext {
		xScale: Readable<ScaleBand<string>>;
		yScale: Readable<ScaleLinear<number, number>>;
		width: Readable<number>;
		height: Readable<number>;
	}

	let {
		points,
		barField,
		activeMonthEnd = null,
		onHoverChange
	}: {
		points: HistoricalExpenditurePoint[];
		/** Which field is the ACTIVE bar series — 'expense_monthly_inflation_adjusted' normally,
		 * 'expense_monthly_nominal' under the whole-series-CPI-unavailable fallback. The parent
		 * decides which; this component never inspects isCpiWhollyUnavailable itself. */
		barField: 'expense_monthly_inflation_adjusted' | 'expense_monthly_nominal';
		activeMonthEnd?: string | null;
		onHoverChange: (monthEnd: string | null) => void;
	} = $props();

	const { xScale, yScale, width, height } = getContext<LayerCakeContext>('LayerCake');

	// Under the nominal fallback, `expense_monthly_nominal` is NEVER null (096's contract), so
	// isAdjustedUnavailable (which only inspects the adjusted field) never fires in that mode —
	// consistent with the fallback existing precisely because the adjusted field is unusable
	// wholesale; there is no PER-ROW unavailable state left to show once the fallback is active.
	const barUnavailable = (p: HistoricalExpenditurePoint) =>
		barField === 'expense_monthly_inflation_adjusted' && isAdjustedUnavailable(p);

	const y0 = $derived($yScale(0));

	// ---- rolling-average overlay, gap-aware (mirrors nav-series.ts's inflationAdjustedSegments
	// pattern via rollingAverageSegments — see that module for why this is the only sanctioned
	// way to consume a nullable series column). Never drawn under the nominal fallback: there is
	// no rolling-average-of-nominal field on this surface, so the parent passes points whose
	// rolling_12mo_avg_inflation_adjusted the segmenter will find null throughout, producing zero
	// segments naturally — no separate fallback branch needed here.
	const segments = $derived(rollingAverageSegments(points));
	const bandCenter = (p: HistoricalExpenditurePoint) =>
		($xScale(p.month_end) ?? 0) + $xScale.bandwidth() / 2;
	const overlayPaths = $derived(
		segments.map(
			(seg) =>
				d3line<HistoricalExpenditurePoint>()
					.x(bandCenter)
					.y((d) => $yScale(d.rolling_12mo_avg_inflation_adjusted as number))
					.curve(curveLinear)(seg) ?? ''
		)
	);

	// ---- axis ticks — a band scale has no .ticks(); label every 6th month (roughly Jan/Jul of
	// each year across the 60-month window) rather than one label per bar, which a 60-bar axis
	// cannot legibly carry.
	const xTickPoints = $derived(points.filter((_, i) => i % 6 === 0));
	const yTicks = $derived($yScale.ticks(5));
	const monthFmt = new Intl.DateTimeFormat('en-US', { month: 'short', year: '2-digit', timeZone: 'UTC' });
	const currencyFmt = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		notation: 'compact',
		maximumFractionDigits: 1
	});
	const tooltipCurrencyFmt = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

	function toDate(iso: string): Date {
		return new Date(`${iso}T00:00:00Z`);
	}

	/** AC8 tooltip content, also doubling as the per-bar aria-label (screen-reader parity — the
	 * SAME text a sighted hover sees is what a keyboard/AT user gets on focus). */
	function tooltipText(p: HistoricalExpenditurePoint): string {
		const month = monthFmt.format(toDate(p.month_end));
		const nominal = tooltipCurrencyFmt.format(p.expense_monthly_nominal);
		const adjusted = isAdjustedUnavailable(p)
			? `Unavailable — ${adjustedUnavailableReason(p)}`
			: tooltipCurrencyFmt.format(p.expense_monthly_inflation_adjusted as number);
		const rolling =
			p.rolling_12mo_avg_inflation_adjusted === null
				? 'Not yet available'
				: tooltipCurrencyFmt.format(p.rolling_12mo_avg_inflation_adjusted);
		return `${month}: nominal ${nominal}, inflation-adjusted ${adjusted}, 12-mo rolling avg ${rolling}`;
	}
</script>

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
	{#each xTickPoints as p (p.month_end)}
		<text
			x={($xScale(p.month_end) ?? 0) + $xScale.bandwidth() / 2}
			y={$height + 16}
			class="tick-label tick-label-x"
			text-anchor="middle"
		>
			{monthFmt.format(toDate(p.month_end))}
		</text>
	{/each}
</g>

<!-- Bars — the ACTIVE field only (see barField). A hatched swatch replaces the bar wherever the
     per-row value is unavailable (AC6), spanning the full plot height so it reads as "no data
     here" rather than "spent nothing" — never the same visual as a real $0 bar. -->
<defs>
	<pattern id="unavailable-hatch" patternUnits="userSpaceOnUse" width="8" height="8" patternTransform="rotate(135)">
		<rect width="8" height="8" class="unavailable-region-bg" />
		<line x1="0" y1="0" x2="0" y2="8" class="unavailable-region-hatch-line" />
	</pattern>
</defs>
{#each points as p (p.month_end)}
	{@const bx = $xScale(p.month_end) ?? 0}
	{@const bw = $xScale.bandwidth()}
	{@const value = p[barField]}
	{#if barUnavailable(p)}
		<rect x={bx} y={0} width={bw} height={$height} fill="url(#unavailable-hatch)" aria-hidden="true" />
	{:else if value !== null}
		{@const by = $yScale(Math.max(0, value))}
		{@const bh = Math.abs($yScale(value) - y0)}
		<rect x={bx} y={by} width={bw} height={bh} class="bar" class:bar-active={activeMonthEnd === p.month_end} aria-hidden="true" />
	{/if}
{/each}

<!-- Rolling-average overlay — one <path> per gap-free run (AC5: first 11 months, no line yet) -->
{#each overlayPaths as d, i (i)}
	<path {d} class="overlay-line" />
{/each}

<!-- Per-month hit targets — keyboard + hover, drives the parent's tooltip (AC8). Full-height,
     full-band-width so the target is easy to reach with a mouse and by Tab in month order.
     role="button" (not "img"): Svelte's a11y linter treats "img" as non-interactive and refuses
     tabindex on it — this element genuinely IS a keyboard-reachable disclosure target (focus
     reveals the tooltip), which is what "button" communicates, even though nothing is "clicked". -->
{#each points as p (`hit-${p.month_end}`)}
	<rect
		x={$xScale(p.month_end) ?? 0}
		y={0}
		width={$xScale.bandwidth()}
		height={$height}
		class="hit-target"
		role="button"
		tabindex="0"
		aria-label={tooltipText(p)}
		onmouseenter={() => onHoverChange(p.month_end)}
		onmouseleave={() => onHoverChange(null)}
		onfocus={() => onHoverChange(p.month_end)}
		onblur={() => onHoverChange(null)}
	/>
{/each}

<!-- y = 0 baseline, drawn last so it reads above the bars — a refund-dominated month (AC/SIGN
     CONVENTION: reachable, renders negative) needs a visible zero line to read correctly. -->
<line x1={0} x2={$width} y1={y0} y2={y0} class="zero-line" aria-hidden="true" />

<style>
	.unavailable-region-bg {
		fill: var(--c-surface-alt);
	}
	.unavailable-region-hatch-line {
		stroke: var(--c-border);
		stroke-width: 1;
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
	.bar {
		fill: var(--c-viz-fill);
	}
	.bar-active {
		fill: var(--c-viz-infl);
	}
	.overlay-line {
		fill: none;
		stroke: var(--c-viz-infl);
		stroke-width: 2;
		stroke-linejoin: round;
		stroke-linecap: round;
	}
	.zero-line {
		stroke: var(--c-border-strong);
		stroke-width: 1;
	}
	.hit-target {
		fill: transparent;
		cursor: pointer;
	}
	.hit-target:focus-visible {
		outline: none;
		fill: var(--c-accent-soft);
		opacity: 0.35;
	}
</style>
