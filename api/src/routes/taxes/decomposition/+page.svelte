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

	SIBLING LINK (team-lead ruling, 2026-09-04): the single "Taxes" primary-nav entry is
	frontend-266's (`/taxes/quarterly`, active-matched on the whole `/taxes/*` prefix — SELF-264
	carries NO nav entry of its own, see `+layout.svelte`'s own history). This page cross-links to
	its §2.5.3 sibling in-page instead, beside the heading — same `.page-actions` convention
	`cash-flow/+page.svelte` uses for its own "By account →" cross-link.

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
	<div class="page-actions">
		<a class="quarterly-link" href="/taxes/quarterly">Quarterly estimated taxes →</a>
	</div>
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

	/* Mirrors cash-flow/+page.svelte's own `.page-actions` / `.by-account-link` cross-link
	   convention verbatim (tokens only). */
	.page-actions {
		display: flex;
		justify-content: flex-end;
	}
	.quarterly-link {
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.quarterly-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.quarterly-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
</style>
