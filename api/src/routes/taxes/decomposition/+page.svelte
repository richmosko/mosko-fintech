<!--
	taxes/decomposition/+page.svelte — the §2.5.1.c tax-relevant income decomposition page
	(SELF-264). Frontend-owned browser surface. Consumes +page.server.ts's `data` (PageData) —
	Backend-owned; authors NO server logic.

	CONTRACT (verified against +page.server.ts post-merge, commit 570a4d6): `data.liability` is
	the FULL `TaxLiabilityPayload` (non-nullable — the loader is FAIL-LOUD, throwing rather than
	degrading to null on an RPC or shape failure; SvelteKit's default 500 page handles that case,
	not a null-check here — see taxLiability.ts's own module header for why this surface diverges
	from the dominant fail-soft convention). `data.taxCharacters` is the `pfin.tax_character`
	catalog (5 seeded rows). `data.inventorySeedDeltaMigration` is AC11's seed-delta migration
	name.

	No page-level empty state: TaxDecompositionTable.svelte owns both of AC9's two empty states
	(Income section / Capital Gains capability banner) internally, since they are section-scoped,
	not page-scoped.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxDecompositionTable from '$lib/components/TaxDecompositionTable.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Taxes · mosko-fintech</title>
</svelte:head>

<main class="page">
	<h1 class="sr-only">Taxes</h1>
	<TaxDecompositionTable
		liability={data.liability}
		taxCharacters={data.taxCharacters}
		seedDeltaMigration={data.inventorySeedDeltaMigration}
	/>
</main>

<style>
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

	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
</style>
