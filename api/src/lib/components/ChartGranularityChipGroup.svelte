<!--
	ChartGranularityChipGroup.svelte — the locked `chart-granularity chip-group`
	(design-system-spec.md §4, INV-3). SELF-220 §2.1.2 AC#2. Reproduces the locked
	screen.css `.chip-group .seg` segmented visual spec with tokens ONLY, matching
	the ConnectionStatusChip / NavCompositionTable convention of re-implementing a
	proofed screen.css pattern inside a component's own scoped styles (app-side
	CSS doesn't load screen.css — that file is the visual-proof/gallery demo).

	Keyboard-native segmented control: a `role="radiogroup"` of `role="radio"`
	buttons (not a native <select> — the locked visual IS a segmented chip row, and
	a <select> would not reproduce it). Roving tabindex: only the selected segment
	is in the tab order; arrow-key navigation moves selection between segments
	(standard radiogroup pattern), Home/End jump to the first/last.

	Pure presentational + emits a callback prop on change — this component owns NO
	navigation/URL logic itself (that is NavHistoryChart's job, which composes this
	with the §12.7 auto-narrow rule). Consumers pass `selected` + `onSelect`.
-->
<script lang="ts">
	import { NAV_SERIES_GRANULARITIES, type NavSeriesGranularity } from '$lib/nav-series';

	let {
		selected,
		onSelect,
		/** §12.7: a suggested (not forced) granularity — rendered as a visual hint
		 * on that segment, distinct from `selected`. The user can still pick any
		 * segment; this never disables or auto-applies. */
		suggested = null
	}: {
		selected: NavSeriesGranularity;
		onSelect: (g: NavSeriesGranularity) => void;
		suggested?: NavSeriesGranularity | null;
	} = $props();

	const LABEL: Record<NavSeriesGranularity, string> = {
		monthly: 'Monthly',
		weekly: 'Weekly',
		daily: 'Daily'
	};

	function onKeydown(event: KeyboardEvent, index: number) {
		const last = NAV_SERIES_GRANULARITIES.length - 1;
		let nextIndex: number | null = null;
		if (event.key === 'ArrowRight' || event.key === 'ArrowDown') {
			nextIndex = index === last ? 0 : index + 1;
		} else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') {
			nextIndex = index === 0 ? last : index - 1;
		} else if (event.key === 'Home') {
			nextIndex = 0;
		} else if (event.key === 'End') {
			nextIndex = last;
		}
		if (nextIndex !== null) {
			event.preventDefault();
			onSelect(NAV_SERIES_GRANULARITIES[nextIndex]);
		}
	}
</script>

<div class="chip-group" role="radiogroup" aria-label="Chart granularity">
	{#each NAV_SERIES_GRANULARITIES as g, i (g)}
		<button
			type="button"
			role="radio"
			aria-checked={selected === g}
			tabindex={selected === g ? 0 : -1}
			class="seg"
			class:sel={selected === g}
			class:is-suggested={suggested === g && suggested !== selected}
			onclick={() => onSelect(g)}
			onkeydown={(e) => onKeydown(e, i)}
		>
			{LABEL[g]}
			{#if suggested === g && suggested !== selected}
				<span class="sr-only"> (suggested)</span>
			{/if}
		</button>
	{/each}
</div>

<style>
	.chip-group {
		display: inline-flex;
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		overflow: hidden;
	}
	.seg {
		font: var(--weight-reg) var(--fs-small) / 1 var(--font-ui);
		padding: 3px var(--space-3);
		color: var(--c-text-secondary);
		background: var(--c-surface);
		border: none;
		border-left: 1px solid var(--c-border);
		cursor: pointer;
	}
	.seg:first-child {
		border-left: none;
	}
	.seg:hover {
		background: var(--c-surface-alt);
	}
	.seg.sel {
		background: var(--c-accent-soft);
		color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	/* Suggested-but-not-selected: a quiet outline hint, never a color that could be
	   mistaken for `.sel` — the user must still see this is a suggestion, not the
	   active state (§12.7: "a suggestion... the user can override"). */
	.seg.is-suggested {
		box-shadow: inset 0 0 0 1px var(--c-border-strong);
	}
	.seg:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		position: relative;
		z-index: 1;
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
