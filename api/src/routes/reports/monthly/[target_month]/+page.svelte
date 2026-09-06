<!--
	reports/monthly/[target_month]/+page.svelte — the §2.6.1.b monthly report page (SELF-354 / P2).
	Frontend-owned browser surface. Consumes +page.server.ts's `data` (PageData) verbatim; owns
	page-only chrome (title, page padding) — all report CONTENT lives in MonthlyReportView.svelte,
	the shared template A5's PDF composition path also renders (R2 (C)), so this file must never
	grow report-content markup of its own.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import MonthlyReportView from '$lib/components/MonthlyReportView.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Monthly Report · mosko-fintech</title>
</svelte:head>

<main class="page">
	<MonthlyReportView
		header={data.header}
		payload={data.payload}
		taxCharacters={data.taxCharacters}
		seedDeltaMigration={data.seedDeltaMigration}
	/>
</main>

<style>
	.page {
		padding: var(--space-6) var(--space-5);
		max-width: 72rem;
		margin: 0 auto;
	}
</style>
