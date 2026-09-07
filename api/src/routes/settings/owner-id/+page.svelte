<!--
	settings/owner-id/+page.svelte — the §2.6.4.b owner-identification Settings editor page
	(SELF-359 AC1/AC2). Frontend-owned browser surface. Consumes
	settings/owner-id/+page.server.ts's `data.ownerIdHeaderText` (pfin.owner_identification,
	migration 106 / SELF-352).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import OwnerIdentificationEditor from '$lib/components/OwnerIdentificationEditor.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Report Header · mosko-fintech</title>
</svelte:head>

<main class="oid">
	<header class="head">
		<h1 class="title">Report header</h1>
	</header>

	<OwnerIdentificationEditor initialHeaderText={data.ownerIdHeaderText} />
</main>

<style>
	.oid {
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
</style>
