<!--
	MonthlyReportStaleBanner.svelte — the §2.6.5 report-level summary banner (SELF-360 / P8 AC3 /
	AC7). Names, by account, every one of THIS report's own contributing accounts that is
	currently in a re-auth/credential-error state — additive to (never a substitute for) the
	per-section inline `<StaleConstituentBadge>`s (PRD §2.6.5: both halves required, banner-only
	is a named rejected alternative).

	COPY, VERBATIM (AC7): "These accounts are currently in re-auth state; sections sourced from
	them are marked stale as of today, not as of {Month YYYY}: {account list}." The "as of
	today, not as of {Month}" clause is load-bearing prose, not decoration — it is how the AC2
	live-marker-over-a-frozen-payload distinction reaches the reader in the one place this report
	states it in words.

	`accountNames` arrives ALREADY RESOLVED and ALREADY SORTED by the loader
	(reports/monthly/[target_month]/+page.server.ts) — this component does no lookups, no
	filtering, no re-sorting. Renders NOTHING when empty (zero footprint — mirrors
	ReauthStalenessBanner's own "renders nothing when healthy" convention), which covers both "no
	account is currently stale" and "an upstream read failed and degraded to no names" alike —
	this component cannot and does not distinguish those two, matching every other UNKNOWN-vs-
	nothing-to-report ambiguity this codebase already accepts at the presentation layer (see
	StaleConstituentBadge's own ambient-badge posture) rather than inventing a third rendered
	state nothing in the AC asks for.

	Uses the CANARY `--c-attn-*` hue (design-system-spec.md §5 fence 8) — the reserved staleness/
	re-auth register, same as ReauthStalenessBanner — never decoration elsewhere.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	let { accountNames, monthLabel }: { accountNames: string[]; monthLabel: string } = $props();

	// Computed as ONE string (mirrors ReauthStalenessBanner's own reauthMessage/
	// institutionDownMessage convention) rather than interpolated inline across multiple
	// template lines — Svelte preserves template-source whitespace/newlines verbatim in the
	// rendered text node, which would otherwise embed spurious linebreaks into AC7's exact copy.
	const bannerText = $derived(
		`These accounts are currently in re-auth state; sections sourced from them are marked stale as of today, not as of ${monthLabel}: ${accountNames.join(', ')}.`
	);
</script>

{#if accountNames.length > 0}
	<aside class="stale-banner" role="status" aria-live="polite">
		<span class="stale-banner-icon" aria-hidden="true">!</span>
		<span class="stale-banner-text">{bannerText}</span>
	</aside>
{/if}

<style>
	.stale-banner {
		display: flex;
		align-items: flex-start;
		gap: var(--space-2);
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-md);
		background: var(--c-attn-bg);
		border: 1px solid var(--c-attn-border);
		color: var(--c-attn-text);
	}
	.stale-banner-icon {
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.25rem;
		height: 1.25rem;
		border-radius: 50%;
		background: var(--c-attn-solid);
		color: var(--c-attn-text);
		font: var(--weight-bold) var(--fs-small) / 1 var(--font-ui);
	}
	.stale-banner-text {
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
</style>
