<!--
	settings/tax-brackets/+page.svelte -- the §2.5.2 tax-bracket schedules editor page
	(SELF-265 AC1/AC6/AC7). Frontend-owned browser surface. Consumes
	settings/tax-brackets/+page.server.ts's `data` (PageData) -- Backend's `jurisdictions` +
	`currentTaxYear` (feature/self-265-backend @ caebbec), read verbatim; authors NO server
	logic. This is the stable route SELF-266's "Edit tax brackets" affordance targets (AC6) — no
	inline edit on the §2.5.3 tables themselves (ADR-013 P5).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxBracketSchedulesList from '$lib/components/TaxBracketSchedulesList.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Tax Brackets · mosko-fintech</title>
</svelte:head>

<main class="tbs">
	<header class="head">
		<h1 class="title">Tax brackets</h1>
		<p class="lead">
			Edit the Federal and California bracket schedules used for §2.5's estimated-tax figures.
			Rates are entered as percentages; the lowest bracket always starts at $0.
		</p>
	</header>

	<TaxBracketSchedulesList jurisdictions={data.jurisdictions} currentTaxYear={data.currentTaxYear} />
</main>

<style>
	.tbs {
		max-width: 52rem;
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
