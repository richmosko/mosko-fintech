<!--
	portfolio/classify/+page.svelte — SELF-200 (§2.4.1.e) pending-symbol classification surface.
	Frontend-owned browser surface. Consumes +page.server.ts's `data` ({ pending, subCats,
	loadError }) and POSTs the classify action; authors NO server logic.

	The header badge (root +layout.svelte) links here. Each held-but-unclassified security is a
	PendingClassifyRow: click-into detail shows the linked-provider metadata as a NON-preselected
	hint (AC3) + the Cat › Sub-Cat picker; Save POSTs ?/classify; on success the item drops from the
	list off the re-run load (no manual mutation).

	State precedence (loadError must WIN so a read failure never masquerades as "all caught up"):
	  1. loadError            → retriable error (gap 1). Backend's fail-soft [] is distinguished from
	                            a genuine empty set by the `loadError` flag; retry re-runs the load.
	  2. pending & no taxonomy → defensive no-taxonomy notice (gap 2); Classify disabled on every row.
	                            Unreachable in single-user V1 (taxonomy is provisioned at setup) —
	                            kept quiet, NO error styling, NO CTA.
	  3. no pending           → "all caught up" empty state.
	  4. otherwise            → the classify list.

	a11y (gap 3): a row unmounts on success, so the page owns a polite aria-live region
	("Classified — N remaining.") and moves focus to the stable region wrapper after each classify.

	Sub-Cat options are grouped by `cat` into accessible <optgroup> (subCatGroupsOf — the SAME
	flatten the SELF-236 reassign picker uses, so the two pickers never drift). Tokens ONLY.
-->
<script lang="ts">
	import { tick } from 'svelte';
	import { invalidateAll } from '$app/navigation';
	import type { PageData } from './$types';
	import PendingClassifyRow from '$lib/components/PendingClassifyRow.svelte';
	import Button from '$lib/components/Button.svelte';
	import { subCatGroupsOf } from '$lib/transaction-util';

	let { data }: { data: PageData } = $props();

	const pending = $derived(data.pending);
	const subCatGroups = $derived(subCatGroupsOf(data.subCats));
	const hasTaxonomy = $derived(subCatGroups.length > 0);

	// Polite SR announcement + focus anchor for the post-classify moment (the row unmounts).
	let liveMsg = $state('');
	let regionEl: HTMLElement | undefined = $state();

	async function handleClassified() {
		// Called after the row's load-invalidation resolves, so `pending` already reflects the drop.
		const remaining = pending.length;
		liveMsg =
			remaining === 0 ? 'Classified — none remaining.' : `Classified — ${remaining} remaining.`;
		await tick();
		regionEl?.focus();
	}

	// Gap 1 retry — re-run the loader (recovers a transient read failure without a full reload).
	let retrying = $state(false);
	async function retry() {
		retrying = true;
		await invalidateAll();
		retrying = false;
	}
</script>

<svelte:head>
	<title>Pending classification — mosko-fintech</title>
</svelte:head>

<p class="visually-hidden" aria-live="polite" aria-atomic="true">{liveMsg}</p>

<main class="page">
	<header class="head">
		<h1>Pending classification</h1>
		<p class="lede">
			Assign a category to each security you hold. Until you do, it rolls up under Uncategorized ›
			Unsorted in your allocation and net-worth views — visible, just not yet categorized.
		</p>
	</header>

	<section
		class="region"
		aria-label="Securities pending classification"
		tabindex="-1"
		bind:this={regionEl}
	>
		{#if data.loadError}
			<div class="load-error" role="alert">
				<p class="load-error-msg">Couldn't load your pending securities — retry.</p>
				<Button variant="secondary" type="button" onclick={retry} loading={retrying}>Retry</Button>
			</div>
		{:else if pending.length > 0 && !hasTaxonomy}
			<div class="notice">
				<p class="notice-msg">No asset categories are set up yet, so classification is unavailable.</p>
				<p class="notice-sub">Your category taxonomy is provisioned during setup.</p>
			</div>
			<ul class="list">
				{#each pending as p (p.asset_id)}
					<PendingClassifyRow symbol={p} {subCatGroups} disabled />
				{/each}
			</ul>
		{:else if pending.length === 0}
			<p class="empty">You're all caught up — no securities are waiting for a category.</p>
		{:else}
			<p class="count">
				{pending.length}
				{pending.length === 1 ? 'security' : 'securities'} awaiting a category.
			</p>
			<ul class="list">
				{#each pending as p (p.asset_id)}
					<PendingClassifyRow symbol={p} {subCatGroups} onclassified={handleClassified} />
				{/each}
			</ul>
		{/if}
	</section>
</main>

<style>
	/* Functional screen-reader-only clip (standard sr-only recipe) — not a design value. */
	.visually-hidden {
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
		max-width: 52rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	h1 {
		margin: 0;
		font-size: var(--fs-h1);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-text-primary);
	}
	.lede {
		margin: 0;
		font-size: var(--fs-body);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	.region {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-1);
		overflow: hidden;
	}
	/* The region is a focus target after each classify — keep the programmatic-focus ring subtle
	   (it's a container, not an interactive control) but present for sighted keyboard users. */
	.region:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.count {
		margin: 0;
		padding: var(--space-3) var(--space-4);
		border-bottom: 1px solid var(--c-border);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
	}
	.empty {
		margin: 0;
		padding: var(--space-5) var(--space-4);
		text-align: center;
		color: var(--c-text-muted);
		font-style: italic;
	}
	/* Gap 1 — retriable load error. This IS an error, so error styling is appropriate. */
	.load-error {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
		padding: var(--space-4);
		border-left: 3px solid var(--c-neg);
		background: color-mix(in srgb, var(--c-neg) 6%, var(--c-surface));
	}
	.load-error-msg {
		margin: 0;
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	/* Gap 2 — defensive no-taxonomy notice. NOT an error: calm/muted, no CTA. */
	.notice {
		padding: var(--space-4);
		border-bottom: 1px solid var(--c-border);
		background: var(--c-surface-alt);
	}
	.notice-msg {
		margin: 0;
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
	}
	.notice-sub {
		margin: var(--space-1) 0 0;
		color: var(--c-text-muted);
		font-size: var(--fs-small);
	}
</style>
