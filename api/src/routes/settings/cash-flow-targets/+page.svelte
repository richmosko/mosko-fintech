<!--
	settings/cash-flow-targets/+page.svelte — the §2.3.2 cash-flow targets editor page
	(SELF-252 AC1/AC2/AC8). Frontend-owned browser surface. Consumes
	settings/cash-flow-targets/+page.server.ts's `data` (PageData) — Backend's
	`loadCashflowTarget` query, landed on this branch (commit 6ef4463); authors NO server
	logic.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import CashflowTargetEditor from '$lib/components/CashflowTargetEditor.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Cash-flow Targets · mosko-fintech</title>
</svelte:head>

<main class="cft">
	<header class="head">
		<h1 class="title">Cash-flow targets</h1>
		<p class="lead">
			Set an annual income target and a monthly expense target. Leave a field blank for "no
			target set" — clearing a value removes it entirely rather than storing a zero.
		</p>
	</header>

	<CashflowTargetEditor initialTargets={data.targets} />
</main>

<style>
	.cft {
		max-width: 44rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.lead {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
