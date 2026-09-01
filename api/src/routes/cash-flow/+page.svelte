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

	§2.3.4 HISTORICAL EXPENDITURES PANEL (SELF-256; AC1 placement RULED by Visual Designer —
	relayed by team-lead, not re-derived here): panel on THIS route, stacked below
	CashflowRollupTable, no dedicated route. Mounted OUTSIDE the `{#if data.rollup === null}...`
	chain above (deliberately) — VD's ruling: "Chart must own its own fail-soft/empty/error gating
	independent of the rollup table — a chart-data failure must never take down the rollup above
	it" (mirrors NavHistoryChart vs. the §2.1.1 NAV headline on the net-worth page). The inverse
	holds too: a rollup failure/empty-state must not suppress the chart either, so it always
	mounts, with `HistoricalExpendituresChart` doing its OWN internal read-failed/empty/populated
	gating on `data.historicalExpenditures`. The `.page` flex-column's existing `--space-4` gap
	already satisfies VD's "stacked with --space-4 gap, no extra wrapping chrome from the page
	itself" — no new wrapper/CSS added here.

	EXPECTED LOADER CONTRACT (Backend's +page.server.ts, NOT YET LANDED as of this file's
	authoring — the underlying query layer, pfin.fn_historical_expenditures/096, IS merged —
	PR #586 — so this is sequencing, not a missing read path; SELF-242/241/325 precedent):
	  - `data.historicalExpenditures: HistoricalExpenditurePoint[] | null` — `null` on read
	    failure (fail-soft, logged, never thrown, matching `loadNavSeries`'s posture); `[]` = read
	    succeeded, zero qualifying expense in the trailing 5-year window (096's own contract — a
	    real, distinguishable state, not an error).
	  - `data.historicalExpendituresUnclassifiedCount: number | null` — BLOCKING GAP, reported at
	    SELF-256 hand-off: no server-side source exists yet (096 has no 12th column; 093's
	    `unclassified.count_ytd` is YTD-scoped, a DIFFERENT window than this surface's trailing 5
	    years). `null` until a new migration adds it — `HistoricalExpendituresChart` already
	    degrades this to "no banner, no caption" (verified in its own dom test).
	`npm run check` surfaces real `Property does not exist on PageData` errors against both of the
	above until Backend lands the loader — the correct, visible signal per established precedent;
	not worked around with `any` or a parallel type.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import CashflowRollupTable from '$lib/components/CashflowRollupTable.svelte';
	import HistoricalExpendituresChart from '$lib/components/HistoricalExpendituresChart.svelte';
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
	<!-- SELF-254 entry point (drill-from, kept minimal per hand-off judgment call): this page's
	     own `rollup` payload is account-AGGREGATE (093's reader) and carries no per-account id, so
	     there is no single account to link straight to `/cash-flow/[account_id]` from here without
	     new data on THIS loader (out of this issue's scope, flagged onward). `/accounts` — the
	     same target the empty-state / AC9 classify CTAs already use — is the best available
	     "choose an account" entry; the account-detail page (accounts/[account_id]/+page.svelte)
	     carries the actual `?from=cross-account-rollup`-marked link into SELF-254's drill-down. -->
	<div class="page-actions">
		<a class="by-account-link" href="/accounts">By account →</a>
	</div>

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

	<!-- §2.3.4 (SELF-256) — VD-ruled placement (see module header): always mounted, independent
	     of the rollup's own state above. -->
	<HistoricalExpendituresChart
		points={data.historicalExpenditures ?? null}
		unclassifiedCount={data.historicalExpendituresUnclassifiedCount ?? null}
	/>
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
	.page-actions {
		display: flex;
		justify-content: flex-end;
	}
	.by-account-link {
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.by-account-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.by-account-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
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
