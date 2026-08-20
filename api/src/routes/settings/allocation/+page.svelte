<!--
	settings/allocation/+page.svelte — the §2.2.2 %Target editor page (SELF-242 AC2/AC6/AC7).
	Frontend-owned browser surface. Consumes settings/allocation/+page.server.ts's `data`
	(PageData) — Backend-owned, NOT YET LANDED as of this file's authoring; authors NO server
	logic.

	EXPECTED CONTRACT (proposed here for Backend to build against or correct — see the
	SELF-242 hand-off note for the exact ask):
	  data.catalog : { id: number; cat: string; sub_cat: string; display_order: number | null }[]
	                 — the caller's full asset-domain Sub-Cat catalog, RLS-scoped via
	                 locals.supabase (mirrors nonReAllocation.ts's own `user_taxonomy` read —
	                 `select id, cat, sub_cat, display_order from pfin.user_taxonomy`, no
	                 domain filter needed post-084). Real Estate rows may be included or
	                 pre-filtered; PlanningTargetEditor filters them out independently either
	                 way (see its own header comment).
	  data.targets  : Record<sub_cat_id, target_percent> — one entry per EXISTING
	                 pfin.planning_target row for this user (074's own "row exists iff a
	                 target is set" contract) — built from
	                 `select sub_cat_id, target_percent from pfin.planning_target` keyed by
	                 sub_cat_id. A Sub-Cat with no row is simply absent from this map — never
	                 present with a 0 (that would assert a target the user never set).

	This page renders NO fallback UI for a missing/malformed `data` shape — until Backend's
	loader lands with the shape above, `data.catalog`/`data.targets` will not resolve at the
	type level (see the file-level note in the SELF-242 hand-off). PlanningTargetEditor owns
	all editing/save/unset/sum-readout behavior; this page is a thin loader-to-editor wire.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import PlanningTargetEditor from '$lib/components/PlanningTargetEditor.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Allocation · mosko-fintech</title>
</svelte:head>

<main class="alloc">
	<header class="head">
		<h1 class="title">Allocation targets</h1>
		<p class="lead">
			Set a target % of your total Non-RE net worth for each Sub-Cat. Leave a field blank for
			"no target set" — clearing a value removes it entirely rather than storing a zero.
		</p>
	</header>

	<PlanningTargetEditor catalog={data.catalog} initialTargets={data.targets} />
</main>

<style>
	.alloc {
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
