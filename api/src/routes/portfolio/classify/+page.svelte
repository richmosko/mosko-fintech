<!--
	portfolio/classify/+page.svelte — SELF-235 (§2.2.1.b) full symbols list: every security the
	caller has ever transacted, each carrying its current Cat/Sub-Cat or the classification-pending
	state. Generalized from the SELF-200 (§2.4.1.e) pending-only queue this page used to be (that
	surface's "Pending classification" framing is retired — this is now the full holding-to-bucket
	assignment list, with pending as ONE state a row can be in, not the page's whole subject).

	Frontend-owned browser surface. Consumes +page.server.ts's `data` ({ symbols, subCats,
	loadError }) and POSTs the classify action via SymbolClassifyRow; authors NO server logic.

	The header badge (root +layout.svelte) still links here and still counts ONLY the pending
	subset (countPendingSymbols, untouched by this generalization) — AC5: the notification-queue
	entry point keeps working unchanged.

	⚠ "Pending" here is the classification-pending concept (SELF-200/SELF-235) — NOT the SELF-208
	staleness framework (stale re-auth data). No staleness props are read or rendered on this page;
	--c-attn-* stays reserved for that surface (design-system fence).

	State precedence (loadError must WIN so a read failure never masquerades as "nothing held"):
	  1. loadError            → retriable error (gap 1). Backend's fail-soft [] is distinguished from
	                            a genuine empty set by the `loadError` flag; retry re-runs the load.
	  2. symbols & no taxonomy → defensive no-taxonomy notice (gap 2); Classify/Change disabled on
	                            every row. Unreachable in single-user V1 (taxonomy is provisioned at
	                            setup) — kept quiet, NO error styling, NO CTA.
	  3. no symbols           → "nothing here yet" empty state (never transacted anything).
	  4. otherwise            → the full list, each row classified or pending.

	a11y (gap 3): a row stays mounted after a (re)classify (AC4 — it updates in place, it does not
	unmount), so the page owns a polite aria-live region ("Category saved — N pending.") that
	announces the new pending count; SymbolClassifyRow itself returns focus to its own
	Classify/Change button (the row is still there to receive it).

	The Cat → Sub-Cat cascade (catOptionsOf / subCatOptionsForCat) lives in asset-classify.ts and is
	owned per-row (SymbolClassifyRow) so one row's in-progress edit can't bleed into another's.
	Tokens ONLY.
-->
<script lang="ts">
	import { tick } from 'svelte';
	import { invalidateAll } from '$app/navigation';
	import type { PageData } from './$types';
	import SymbolClassifyRow from '$lib/components/SymbolClassifyRow.svelte';
	import Button from '$lib/components/Button.svelte';

	let { data }: { data: PageData } = $props();

	const symbols = $derived(data.symbols);
	const hasTaxonomy = $derived(data.subCats.length > 0);
	const pendingCount = $derived(symbols.filter((s) => s.classification === null).length);

	// Polite SR announcement anchor for the post-save moment.
	let liveMsg = $state('');
	let regionEl: HTMLElement | undefined = $state();

	async function handleClassified() {
		// Called after the row's load-invalidation resolves, so `symbols`/`pendingCount` already
		// reflect the change.
		liveMsg =
			pendingCount === 0 ? 'Category saved — none pending.' : `Category saved — ${pendingCount} pending.`;
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
	<title>Securities & categories — mosko-fintech</title>
</svelte:head>

<p class="visually-hidden" aria-live="polite" aria-atomic="true">{liveMsg}</p>

<main class="page">
	<header class="head">
		<h1>Securities &amp; categories</h1>
		<p class="lede">
			Every security you've ever held, with its current category. Until a security is
			categorized, it rolls up under Uncategorized › Unsorted in your allocation and net-worth
			views — visible, just not yet categorized.
		</p>
	</header>

	<section class="region" aria-label="Securities and categories" tabindex="-1" bind:this={regionEl}>
		{#if data.loadError}
			<div class="load-error" role="alert">
				<p class="load-error-msg">Couldn't load your securities — retry.</p>
				<Button variant="secondary" type="button" onclick={retry} loading={retrying}>Retry</Button>
			</div>
		{:else if symbols.length > 0 && !hasTaxonomy}
			<div class="notice">
				<p class="notice-msg">No asset categories are set up yet, so classification is unavailable.</p>
				<p class="notice-sub">Your category taxonomy is provisioned during setup.</p>
			</div>
			<ul class="list">
				{#each symbols as s (s.asset_id)}
					<SymbolClassifyRow symbol={s} subCats={data.subCats} disabled />
				{/each}
			</ul>
		{:else if symbols.length === 0}
			<p class="empty">
				Nothing here yet — once you record a security transaction, it'll show up here for
				categorization.
			</p>
		{:else}
			<p class="count">
				{symbols.length}
				{symbols.length === 1 ? 'security' : 'securities'}
				{#if pendingCount > 0}
					· {pendingCount} pending a category
				{:else}
					· all categorized
				{/if}
			</p>
			<ul class="list">
				{#each symbols as s (s.asset_id)}
					<SymbolClassifyRow symbol={s} subCats={data.subCats} onclassified={handleClassified} />
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
