<!--
	+page.svelte — the §2.5.3.b two parallel quarterly estimated-tax tables (SELF-266). Frontend-
	owned browser surface. Thin wrapper over TaxQuarterlyTables.svelte; authors NO server logic and
	performs NO re-derivation of any tax math. `data` is typed via SvelteKit's generated `PageData`,
	which resolves against Backend's `+page.server.ts` (SELF-264/266) — its own header documents the
	`{ liability, noTaxAuthorityDesignated, priorYearQ4 }` shape threaded straight through below,
	verbatim, no reshaping.

	No form actions on this page (AC 8 — no inline edit, ADR-013 P5): the "Edit tax brackets" CTA
	(TaxJurisdictionTable's own AC7) and the "Designate an account" CTA (AC 6(ii)/(iii)) are both
	plain client-side navigation links, never a form/action that writes anything here.

	SELF-361 / P9: `data.staleness` — the SAME whole-tenant `loadStaleness()` read every other
	V1.1+ surface consumes — threaded straight through to TaxQuarterlyTables.svelte, which mounts
	the D1 `<StaleConstituentBadge>` beside the page heading.
-->
<script lang="ts">
	import TaxQuarterlyTables from '$lib/components/TaxQuarterlyTables.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Estimated Quarterly Taxes</title>
</svelte:head>

<TaxQuarterlyTables
	liability={data.liability}
	noTaxAuthorityDesignated={data.noTaxAuthorityDesignated}
	priorYearQ4={data.priorYearQ4}
	staleness={data.staleness}
/>
