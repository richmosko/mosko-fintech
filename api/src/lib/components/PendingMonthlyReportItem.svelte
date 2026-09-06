<!--
	PendingMonthlyReportItem.svelte — one row of P5's pending queue (reports/monthly/+page.svelte),
	rebuilt under P4 (SELF-356 AC1-AC4) from a plain link into the full author-before-generate gate:
	item copy, the no-ledger-designated prompt, and the two CTAs ("Write commentary" / "Skip
	commentary and finalize").

	COPY (PM, verbatim — AC3): "{Month YYYY} — awaiting your Rebalancing Targets commentary." CTA
	"Write commentary" (routes into P3's editor, unchanged from P5's own original link) · secondary
	"Skip commentary and finalize" (SkipFinalizeControl.svelte's own inline two-step confirm — see
	that component's header for why not window.confirm()).

	NO-LEDGER PROMPT (AC4, R1 rider 6): rendered when `noLedgerDesignated` is true — see
	+page.server.ts's own `load()` for how that boolean is derived (composed draft payload, not a
	second query) and NoLedgerDesignatedPrompt.svelte for the shared copy/link.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import SkipFinalizeControl from '$lib/components/SkipFinalizeControl.svelte';
	import NoLedgerDesignatedPrompt from '$lib/components/NoLedgerDesignatedPrompt.svelte';

	let {
		targetMonth,
		monthLabel,
		noLedgerDesignated
	}: { targetMonth: string; monthLabel: string; noLedgerDesignated: boolean } = $props();
</script>

<li class="pending-item">
	<p class="pending-copy">{monthLabel} — awaiting your Rebalancing Targets commentary.</p>
	{#if noLedgerDesignated}
		<NoLedgerDesignatedPrompt />
	{/if}
	<div class="pending-actions">
		<a class="write-commentary-link" href={`/reports/monthly/${targetMonth.slice(0, 7)}/commentary`}>
			Write commentary
		</a>
		<SkipFinalizeControl {targetMonth} {monthLabel} />
	</div>
</li>

<style>
	.pending-item {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3) 0;
		border-bottom: 1px solid var(--c-border);
	}
	.pending-item:last-child {
		border-bottom: none;
	}
	.pending-copy {
		margin: 0;
		font: var(--weight-med) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-primary);
	}
	.pending-actions {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-4);
	}
	.write-commentary-link {
		color: var(--c-accent);
		font: var(--weight-med) var(--fs-body) / var(--lh-body) var(--font-ui);
		text-decoration: none;
	}
	.write-commentary-link:hover {
		text-decoration: underline;
	}
	.write-commentary-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
</style>
