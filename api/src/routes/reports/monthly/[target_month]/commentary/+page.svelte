<!--
	reports/monthly/[target_month]/commentary/+page.svelte — thin wrapper over
	MonthlyCommentaryEditor.svelte, consuming +page.server.ts's loader `data` (Backend-surface
	file, authored by Frontend under this ticket's explicit dispatch — see that file's own
	AUTHORSHIP NOTE). SELF-355 / P3, §2.6.2.b.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import MonthlyCommentaryEditor from '$lib/components/MonthlyCommentaryEditor.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>{data.targetMonthLabel} commentary · mosko-fintech</title>
</svelte:head>

<main class="page">
	<h1 class="page-title">Rebalancing Targets commentary — {data.targetMonthLabel}</h1>
	<MonthlyCommentaryEditor
		targetMonthLabel={data.targetMonthLabel}
		isDraft={data.isDraft}
		commentary={data.commentary}
		priorMonthLabel={data.priorMonthLabel}
		priorCommentary={data.priorCommentary}
		allocation={data.allocation}
		staleness={data.staleness}
		noLedgerDesignated={data.noLedgerDesignated}
	/>
</main>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		max-width: 1200px;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		box-sizing: border-box;
	}
	.page-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
</style>
