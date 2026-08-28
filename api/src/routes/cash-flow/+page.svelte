<!--
	cash-flow/+page.svelte — the §2.3.2.b cross-account cash-flow rollup page (SELF-251).
	Frontend-owned browser surface. Consumes cash-flow/+page.server.ts's `data` (PageData) —
	Backend-owned; authors NO server logic.

	CONTRACT: `data.rollup : CashflowCrossAccountRollup | null` — `loadCashflowCrossAccountRollup`'s
	result, `null` on any read failure (never a fabricated zero-valued rollup).

	AC8 — TWO DISTINCT empty states, both reachable only when `rollup` loaded successfully AND
	BOTH sections have zero Sub-Cat rows (`rollupHasNoRows`); discriminated by
	`rollup.unclassified.count_ytd` — the SAME single-source count AC9's banner/footnote use,
	never a second signal:
	  count_ytd === 0  → zero-TRANSACTION state: nothing has ever been recorded. "Add transactions
	                      via Onboarding" + the SAME onboarding CTA pair allocation/+page.svelte's
	                      own AC10 empty state uses (Connect an account / Add a manual account) —
	                      reused verbatim, not reinvented, since this is the identical "no accounts
	                      or no transaction history yet" entry point.
	  count_ytd > 0    → zero-CLASSIFIED state: transactions exist but none are classified into a
	                      Sub-Cat yet (every item is still in the §2.3.1 queue), so no section has
	                      anything to group by. "Classify your transactions" + a CTA to the SELF-249
	                      classification surface.

	⚠ BUBBLE-UP (flagged at hand-off, not a silent guess): SELF-249 built classification INLINE on
	  per-account transaction lists (`docs/records/v13-preflight/rederived-acs.md`'s own title:
	  "§2.3.1.b Classify UI (inline on transaction lists)") — there is no dedicated cash-flow
	  classification QUEUE page today, so no single URL exists to deep-link this empty state's CTA
	  (or AC9's banner/footnote CTA) to. Both route to `/accounts` — the accounts list, the entry
	  point into that inline classification UI — as the best available target. If/when a real
	  §2.3.1 aggregated queue surface lands, this CTA (and CashflowRollupTable's `classifyHref`
	  default) should repoint there.

	A real POSITIVE rollup (either section has ≥1 row) always renders the table — same "check the
	number/rows first" discipline as allocation/+page.svelte's own AC10 gate (a real table
	outranks an empty-state heuristic).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import CashflowRollupTable from '$lib/components/CashflowRollupTable.svelte';
	import { rollupHasNoRows } from '$lib/cashflow-rollup';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const noRows = $derived(data.rollup !== null && rollupHasNoRows(data.rollup));
	const zeroTransaction = $derived(noRows && data.rollup!.unclassified.count_ytd === 0);
	const zeroClassified = $derived(noRows && !zeroTransaction);
</script>

<svelte:head>
	<title>Cash Flow · mosko-fintech</title>
</svelte:head>

<main class="page">
	{#if data.rollup === null}
		<section class="unavailable" aria-labelledby="unavail-title">
			<h1 id="unavail-title" class="page-title">Cash Flow</h1>
			<p class="unavail-msg">Cash flow is temporarily unavailable. Please try again shortly.</p>
		</section>
	{:else if zeroTransaction}
		<!-- AC8 — zero-transaction empty state. Same onboarding CTA pair as allocation's AC10
		     empty state, reused verbatim. -->
		<section class="empty" aria-labelledby="empty-title">
			<h1 id="empty-title" class="empty-title">Cash Flow</h1>
			<p class="empty-msg">Add transactions via Onboarding to see your cash flow.</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts/connect">Connect an account</a>
				<a class="cta" href="/accounts/new">Add a manual account</a>
			</div>
		</section>
	{:else if zeroClassified}
		<!-- AC8 — zero-classified empty state. CTA target: see the module header's bubble-up
		     note on why this points to /accounts. -->
		<section class="empty" aria-labelledby="empty-title">
			<h1 id="empty-title" class="empty-title">Cash Flow</h1>
			<p class="empty-msg">Classify your transactions to see your cash flow.</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts">Classify transactions</a>
			</div>
		</section>
	{:else}
		<h1 class="page-title">Cash Flow</h1>
		<CashflowRollupTable rollup={data.rollup} />
	{/if}
</main>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
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

	/* Mirrors allocation/+page.svelte's own `.empty` onboarding-CTA treatment verbatim (tokens
	   only). */
	.empty {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		align-items: flex-start;
	}
	.empty-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.empty-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.empty-cta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}
	.cta {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
	}
	.cta:hover {
		background: var(--c-surface-alt);
	}
	.cta:active {
		background: var(--c-surface-alt2);
	}
	.cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.cta-primary {
		background: var(--c-accent);
		color: var(--c-accent-contrast);
		border-color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	.cta-primary:hover {
		background: var(--c-accent-hover);
		border-color: var(--c-accent-hover);
	}
	.cta-primary:active {
		background: var(--c-accent-active);
		border-color: var(--c-accent-active);
	}
</style>
