<!--
	CountBadge.svelte — a small numeric notification-count pill (SELF-200 header badge).

	DESIGN-SYSTEM FENCE: this is a NOTIFICATION COUNT, not a staleness/re-auth signal. The
	attention hue (`--c-attn-*`, canary) is RESERVED for staleness/re-auth ONLY (design-system-spec
	§5 fence) — this badge uses the ACCENT ramp (solid `--c-accent` pill + `--c-accent-contrast`
	text), the canonical count treatment. Tokens ONLY (var(--c-*)); no hardcoded hex/px/font.

	Renders nothing when count <= 0 (zero footprint). The badge itself is aria-hidden — the count is
	conveyed by the enclosing link's accessible name (aria-label) so screen readers aren't read the
	number twice. `max` caps the display ("9+") without changing the true value in the label.
-->
<script lang="ts">
	let { count, max = 99 }: { count: number; max?: number } = $props();

	const display = $derived(count > max ? `${max}+` : String(count));
</script>

{#if count > 0}
	<span class="count-badge" aria-hidden="true">{display}</span>
{/if}

<style>
	.count-badge {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 1.25rem;
		height: 1.25rem;
		padding: 0 var(--space-1);
		box-sizing: border-box;
		border-radius: var(--radius-pill);
		background: var(--c-accent);
		color: var(--c-accent-contrast);
		font: var(--weight-semi) var(--fs-small) / 1 var(--font-num);
	}
</style>
