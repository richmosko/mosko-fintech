<!--
	allocation/us-equity/+page.svelte — the §2.2.3 US Equity sub-allocation drill-down page
	(SELF-241). Frontend-owned browser surface. Consumes allocation/us-equity/+page.server.ts's
	`data` (PageData) — Backend-owned, NOT YET LANDED as of this file's authoring (same precedent
	as settings/allocation/+page.svelte at SELF-242 hand-off: authors NO server logic, builds
	ahead of the loader against a proposed contract, and flags the gap at hand-off rather than
	blocking on it).

	EXPECTED CONTRACT (proposed here for Backend to build against or correct):
	  data.usEquityAllocation : UsEquityAllocation | null — $lib/server/queries/usEquityAllocation.ts's
	                            `loadUsEquityAllocation()` result (SELF-240, already landed and
	                            tested server-side), `.ok` collapsed to `null` on failure — mirrors
	                            the /allocation loader's own null-on-failure convention for
	                            `data.allocation`. NEVER a fabricated all-zero table.
	  data.staleness          : StalenessData — the SAME whole-tenant `loadStaleness()` read
	                            /allocation's own loader already consumes — NOT a re-derived or
	                            table-scoped call. Degrades to UNKNOWN_STALENESS on failure.

	ROUTE CHOICE (file-layout judgment call, per role charter "just decide"): `/allocation/us-equity`
	nested under the §2.2.2 page — matches the design flow doc's F-2.2.C framing ("drill INTO the
	US Equity sub-allocation" off the §2.2.2 "US - Sector Diversified" row), never a top-level nav
	destination (the wireframe / flow doc name no third level, no separate sidebar entry — reached
	only via the §2.2.2 drill-down link, symmetric with the back-link here).

	Zero-holding drill state (flow doc §5 F-2.2.C failure surface: "Total US Equity = 0 → degenerate/
	empty drill state; table not fabricated") is handled BY the table itself
	(UsEquityAllocationTable's own `.ratio-unset-note`, matching §2.2.2's AC6 shape) rather than a
	separate page-level empty state — the twelve rows still render (AC1's "regardless of held/target
	state"), just with every ratio column unset, which already satisfies "not fabricated."

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import UsEquityAllocationTable from '$lib/components/UsEquityAllocationTable.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>US Equity Sub-Allocation · mosko-fintech</title>
</svelte:head>

<main class="page">
	<a class="back-link" href="/allocation">&larr; Back to Allocation</a>

	{#if data.usEquityAllocation === null}
		<section class="unavailable" aria-labelledby="unavail-title">
			<h1 id="unavail-title" class="page-title">US Equity Sub-Allocation</h1>
			<p class="unavail-msg">
				US Equity sub-allocation is temporarily unavailable. Please try again shortly.
			</p>
		</section>
	{:else}
		<h1 class="page-title">US Equity Sub-Allocation</h1>
		<UsEquityAllocationTable allocation={data.usEquityAllocation} staleness={data.staleness} />
	{/if}
</main>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.back-link {
		align-self: flex-start;
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-text-secondary);
		text-decoration: none;
	}
	.back-link:hover {
		color: var(--c-text-primary);
		text-decoration: underline;
	}
	.back-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.page-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.unavail-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
