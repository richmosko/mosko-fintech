<!--
	allocation/+page.svelte — the §2.2.2 Non-RE allocation table page (SELF-239).
	Frontend-owned browser surface. Consumes allocation/+page.server.ts's `data` (PageData) —
	Backend-owned; authors NO server logic.

	ROUTE CHOICE (file-layout judgment call, per role charter — "just decide"): `/allocation`, a
	top-level nav destination, distinct from `/settings/allocation` (the SELF-242 %Target EDITOR).
	Matches +layout.svelte's own comment naming "Allocation" as one of the locked top-level
	sidebar destinations (parallel to Net Worth / Accounts / Cash Flow / Est. Taxes / Monthly
	Report), and the §2.2 UX flow doc's "Asset Allocation surface (top-level surface; nav model
	deferred to Step 3)". A nav-link was added to +layout.svelte alongside this page, mirroring how
	the /portfolio/classify link was added when that surface landed.

	CONTRACT (confirmed at commit — Backend's allocation/+page.server.ts, landed alongside this
	file on the same branch; an earlier draft of this comment proposed a contract for Backend to
	confirm or correct, written before that loader existed):

	  data.allocation      : NonReAllocation | null — loadNonReAllocation()'s result, `.ok`
	                          collapsed to `null` on failure (mirrors netWorth's own
	                          null-on-failure convention). NEVER a fabricated zero-valued table.
	  data.staleness        : StalenessData — the SAME whole-tenant `loadStaleness()` read every
	                          other V1.1 NAV/composition surface already consumes (staleness.ts) —
	                          NOT a re-derived or table-scoped call. Degrades to UNKNOWN_STALENESS
	                          on failure, never EMPTY_STALENESS (SELF-229 convention).
	  data.accountPresence  : 'some' | 'none' | 'unknown' — REUSED from loadNetWorthView (root
	                          +page.server.ts's own producer), not a second independently-computed
	                          count — see Backend's loader header for why that reuse is sound.
	                          Load-bearing ONLY when `data.allocation === null ||
	                          data.allocation.total_non_re <= 0`, per root's own "check the number
	                          first" discipline (see the comment below) — distinguishes AC10's true
	                          zero-holding empty state from AC6's degenerate-but-render state.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import NonReAllocationTable from '$lib/components/NonReAllocationTable.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<svelte:head>
	<title>Allocation · mosko-fintech</title>
</svelte:head>

<main class="page">
	<!--
		⚠ SAME CHAIN ORDER AS root `+page.svelte`, deliberately — that file's own header explains
		why the order is the fix, not a stylistic choice: `accountPresence` is load-bearing ONLY at
		the degenerate total (here: total_non_re <= 0, or the read failed outright), never checked
		ahead of the number. A real positive total is itself proof holdings exist and OUTRANKS
		'none'/'unknown' — AC10's empty state must never fire in front of a real table.

		  data.allocation === null                                    → unavailable (read failed)
		  data.allocation.total_non_re <= 0 && accountPresence==='none' → AC10 empty state
		  otherwise                                                    → the table (AC6 handles its
		                                                                  own degenerate-render case
		                                                                  internally when total<=0
		                                                                  but presence isn't 'none')
	-->
	{#if data.allocation === null}
		<section class="unavailable" aria-labelledby="unavail-title">
			<h1 id="unavail-title" class="page-title">Allocation</h1>
			<p class="unavail-msg">Allocation is temporarily unavailable. Please try again shortly.</p>
		</section>
	{:else if data.allocation.total_non_re <= 0 && data.accountPresence === 'none'}
		<!-- AC10: zero-holding empty state — reachable only on a MEASURED zero-holding count
		     ('unknown' must never land here; a failed count can't tell us "add accounts"). -->
		<section class="empty" aria-labelledby="empty-title">
			<h1 id="empty-title" class="empty-title">Allocation</h1>
			<p class="empty-msg">Add accounts via Onboarding to see your allocation.</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts/connect">Connect an account</a>
				<a class="cta" href="/accounts/new">Add a manual account</a>
			</div>
		</section>
	{:else}
		<h1 class="page-title">Allocation</h1>
		<NonReAllocationTable allocation={data.allocation} staleness={data.staleness} />
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

	/* Mirrors root +page.svelte's own `.empty` onboarding-CTA treatment verbatim (tokens only). */
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
