<!--
	cash-flow/[account_id]/+page.svelte — the §2.3.3.b per-account cash-flow drill-down page
	(SELF-254). Frontend-owned browser surface. Consumes +page.server.ts's `data` (PageData) —
	Backend-owned; authors NO server logic.

	CONTRACT: `data.drilldown : CashflowPerAccount | null` — `null` on either a genuine read
	failure OR an as-of validation failure (`data.asOfError !== null` distinguishes the two —
	AC4 item 3: an out-of-range/malformed `as_of` renders a SANE INLINE ERROR, never the generic
	"temporarily unavailable" notice, since nothing actually failed to load).

	AC8 — ONE empty-state message ("No transactions in [year] for this account."), gated on
	`perAccountHasNoRows(drilldown) && drilldown.unclassified.count_ytd === 0` — i.e. LITERALLY
	nothing exists for this account in the rendered year, not merely nothing classified yet. When
	rows are empty but `count_ytd > 0` (items exist, none classified), the page still renders the
	(per-section-empty) table: CashflowPerAccountTable's own AC7 banner already carries the
	actionable "classify" message for that case, so a second dedicated empty-state text is not
	needed and AC8's own wording doesn't ask for one (unlike SELF-251's two-way split).

	AC3 — CLOSED accounts remain fully selectable and renderable: `closed_at !== null` renders the
	"Closed" pill using accounts/[account_id]/+page.svelte's OWN `.status.closed` treatment
	verbatim (muted + dashed border, never --c-neg — a closed account is a bookkeeping state, not
	an error), with `closedAtLabel` (UTC per ADR-043) appended.

	AC5 — the back-to-251 breadcrumb renders IFF `?from=cross-account-rollup` is present; every
	re-navigation this page performs (the as-of toggle, the account picker) builds off
	`new URL(page.url)` and therefore preserves it automatically.

	AC9 / SELF-258: no staleness marker wired — CashflowPerAccountTable.svelte's own seam comment
	is the one home for that note.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { page } from '$app/state';
	import CashflowPerAccountTable from '$lib/components/CashflowPerAccountTable.svelte';
	import CashflowAsOfToggle from '$lib/components/CashflowAsOfToggle.svelte';
	import CashflowAccountPicker from '$lib/components/CashflowAccountPicker.svelte';
	import { closedAtLabel } from '$lib/account-display';
	import { perAccountHasNoRows, renderedYear } from '$lib/cashflow-per-account';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const accountIdParam = $derived(page.params.account_id);
	const currentAccountId = $derived(Number(accountIdParam));
	// The current account's own display fields, resolved from the SAME account-list read the
	// picker uses (no second per-account read). A hand-typed URL for an id outside the caller's
	// own list (foreign / nonexistent — indistinguishable by `094`'s own construction) falls back
	// to a bare "Account #<id>" label rather than a blank header; it never blocks the cashflow
	// render below, which has its own, independently-validated data.
	const currentAccount = $derived(
		data.accounts.find((a) => a.account_id === currentAccountId) ?? null
	);
	const isClosed = $derived(currentAccount?.closed_at !== null && currentAccount?.closed_at !== undefined);

	const showBackToRollup = $derived(page.url.searchParams.get('from') === 'cross-account-rollup');

	const noRows = $derived(data.drilldown !== null && perAccountHasNoRows(data.drilldown));
	const trulyEmpty = $derived(noRows && data.drilldown!.unclassified.count_ytd === 0);

	// The as-of widget's displayed value: the server-APPLIED as-of when a payload loaded, else the
	// raw `?as_of=` the URL carried into a failed validation, else today (maxAsOf) — never a
	// client-derived date at any point in this fallback chain.
	const asOfDisplayValue = $derived(
		data.drilldown?.as_of ?? page.url.searchParams.get('as_of') ?? data.maxAsOf
	);
</script>

<svelte:head>
	<title>{currentAccount?.name ?? 'Account'} · Cash Flow · mosko-fintech</title>
</svelte:head>

<main class="page">
	{#if showBackToRollup}
		<a class="back-link" href="/cash-flow">← Back to Cash Flow</a>
	{/if}

	<header class="head">
		<div class="title">
			<h1>{currentAccount?.name ?? `Account #${accountIdParam}`}</h1>
			{#if isClosed}
				<!-- Verbatim reproduction of accounts/[account_id]'s own `.status.closed` pill —
				     tone carried by weight + border style, never --c-neg. -->
				<span class="status closed">Closed {closedAtLabel(currentAccount?.closed_at ?? null)}</span>
			{/if}
		</div>
	</header>

	<div class="toolbar">
		{#if data.accounts.length > 0}
			<CashflowAccountPicker accounts={data.accounts} {currentAccountId} />
		{/if}
		<CashflowAsOfToggle
			value={asOfDisplayValue}
			floor={data.asOfFloor}
			max={data.maxAsOf}
			serverError={data.asOfError}
		/>
	</div>

	{#if data.asOfError !== null}
		<!-- AC4 item 3 — a sane inline error state, not a crash. The toggle above already shows
		     the same message inline on its own field; this banner restates it at the page level
		     since no cashflow data exists to render underneath it. -->
		<p class="page-error" role="alert">
			{data.asOfError} Pick a date between {data.asOfFloor} and {data.maxAsOf}.
		</p>
	{:else if data.drilldown === null}
		<section class="unavailable" aria-labelledby="unavail-title">
			<h2 id="unavail-title" class="sr-only">Cash flow unavailable</h2>
			<p class="unavail-msg">Cash flow is temporarily unavailable. Please try again shortly.</p>
		</section>
	{:else if trulyEmpty}
		<!-- AC8 — the one empty-state message. -->
		<p class="empty-msg">No transactions in {renderedYear(data.drilldown.as_of)} for this account.</p>
	{:else}
		<CashflowPerAccountTable
			drilldown={data.drilldown}
			classifyHref={`/accounts/${data.drilldown.account_id}`}
			otherCashFlowsNote={data.otherCashFlowsNote}
		/>
	{/if}
</main>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.back-link {
		align-self: flex-start;
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.back-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.back-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.title {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	h1 {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	/* Verbatim reproduction of accounts/[account_id]/+page.svelte's own `.status.closed` pill. */
	.status {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: 1px var(--space-2);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
		background: var(--c-surface);
	}
	.status.closed {
		color: var(--c-text-muted);
		border-style: dashed;
	}

	.toolbar {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--space-4);
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
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
	.page-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.empty-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
