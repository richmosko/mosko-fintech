<!--
	accounts/[account_id]/+page.svelte — account detail + inactive toggle.
	SELF-201 §2.4.2 AC #3/#4. Renders the account attributes + its transaction history
	(the AcctSetup opening-balance row appears here), and an inactive toggle wired to the
	`toggleActive` named action. Marking inactive = is_active=false; history is RETAINED
	(AC #4) — the transactions list still shows — but the account is excluded from
	current-value surfaces (other issues' backend concern).

	FENCES: no --c-pos/--c-neg on values (those are ACTUAL-performance only; ledger amounts
	are neutral). No staleness banner — a manual account has no Plaid re-auth. INV-1: name +
	scope are free-text → plain text. acct_number is not exposed (SD-15; masked-only posture).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { PageData, ActionData } from './$types';
	import { accountTypeLabel, taxTreatmentLabel } from '$lib/account-display';
	import Button from '$lib/components/Button.svelte';
	import TransactionEntryForm from '$lib/components/TransactionEntryForm.svelte';
	import StockSplitEntryForm from '$lib/components/StockSplitEntryForm.svelte';
	import DuplicateCandidateList from '$lib/components/DuplicateCandidateList.svelte';
	import SyncHistoryTable from '$lib/components/SyncHistoryTable.svelte';
	import SyncNowControl from '$lib/components/SyncNowControl.svelte';
	import TransactionRow from '$lib/components/TransactionRow.svelte';
	import { subCatGroupsOf } from '$lib/transaction-util';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const account = $derived(data.account);
	const transactions = $derived(data.transactions);

	// SELF-203 stock split — held-security picker options (Backend derives via fn_holdings_as_of).
	// The affordance is source-of-truth gated (OWD-2 / ADR-033): rendered ONLY when the account is
	// NOT provider-linked (linked_source_id IS NULL). A provider-linked account's splits arrive via
	// reconciliation (SELF-204); the fn_create_stock_split RPC is the DB-level backstop.
	const heldSecurities = $derived(data.heldSecurities ?? []);
	const isSourceOfTruth = $derived(account.linked_source_id == null);

	// SELF-204 read-only surfaces (Backend exposes both view row-sets from load()):
	//  - dupCandidates: manual↔provider candidate-duplicate pairs for THIS account
	//    (pfin.manual_provider_dup_candidate). DETECTION-ONLY — no action affordance.
	//  - syncHistory: per-account provider sync history (pfin.linked_source_sync_history),
	//    rendered only for provider-linked accounts (a manual account has no sync history).
	const dupCandidates = $derived(data.dupCandidates ?? []);
	const syncHistory = $derived(data.syncHistory ?? []);

	// Cashflow-domain Sub-Cat picker groups for the transaction entry/edit/split/categorize
	// surfaces (per-transaction annotation category — the cashflow domain, not asset taxonomy).
	const cashflowGroups = $derived(subCatGroupsOf(data.cashflowSubCats));

	// The ledger table column count — shared with each row so its full-width editor rows
	// (<td colspan>) span correctly: Date | Category | Vendor | Description | Amount | Actions.
	const TABLE_COLUMNS = 6;

	let toggling = $state(false);

	const toggleHandler: SubmitFunction = () => {
		toggling = true;
		return async ({ update }) => {
			await update(); // success → load reruns → is_active refreshes; failure → form.errors
			toggling = false;
		};
	};
</script>

<svelte:head>
	<title>{account.name} — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">{account.name}</span>
	</nav>

	<header class="head">
		<div class="title">
			<h1>{account.name}</h1>
			<span class="status" class:inactive={!account.is_active}>
				{account.is_active ? 'Active' : 'Inactive'}
			</span>
		</div>
	</header>

	<section class="region" aria-label="Account details">
		<dl class="attrs">
			<div class="attr">
				<dt>Type</dt>
				<dd>{accountTypeLabel(account.account_type)}</dd>
				<p class="attr-hint">How this account is grouped — depository (cash), investment, retirement, crypto, real estate, or liability.</p>
			</div>
			<div class="attr">
				<dt>Scope</dt>
				<dd>{account.scope}</dd>
				<p class="attr-hint">Your own ownership label (e.g. personal, joint, trust) — used to group accounts across views.</p>
			</div>
			<div class="attr">
				<dt>Tax treatment</dt>
				<dd>{taxTreatmentLabel(account.tax_treatment)}</dd>
				<p class="attr-hint">How the account is taxed: taxable, tax-deferred, or tax-free. Feeds the estimated-tax view.</p>
			</div>
		</dl>
	</section>

	<section class="region" aria-label="Account status">
		<h2 class="section-title">Account status</h2>
		<p class="help">
			Mark this account inactive when it's closed or sold. Its transaction history is kept, but
			it's excluded from your current balances and totals. You can reactivate it any time.
		</p>

		{#if form && 'errors' in form && form.errors?._form}
			<p class="form-error" role="alert">{form.errors._form.join(' ')}</p>
		{/if}

		<form method="POST" action="?/toggleActive" use:enhance={toggleHandler}>
			<input type="hidden" name="is_active" value={String(!account.is_active)} />
			<Button
				type="submit"
				variant={account.is_active ? 'secondary' : 'primary'}
				loading={toggling}
			>
				{account.is_active ? 'Mark account inactive' : 'Reactivate account'}
			</Button>
		</form>
	</section>

	<section class="region" aria-label="Add a transaction">
		<h2 class="section-title">Add a transaction</h2>
		<TransactionEntryForm subCatGroups={cashflowGroups} />
	</section>

	<!--
		Stock-split entry (SELF-203). Source-of-truth gate (OWD-2 / ADR-033): only rendered for
		non-provider-linked accounts. A provider-linked account's splits come via reconciliation
		(SELF-204) — showing manual entry there would be a conflicting write path.
	-->
	{#if isSourceOfTruth}
		<section class="region" aria-label="Record a stock split">
			<h2 class="section-title">Record a stock split</h2>
			{#if heldSecurities.length === 0}
				<p class="empty">No securities held in this account to split.</p>
			{:else}
				<StockSplitEntryForm securities={heldSecurities} />
			{/if}
		</section>
	{/if}

	<!--
		Candidate-duplicate DETECTION surface (SELF-204). Read-only — surfaces manual entries that
		look like a synced provider transaction so the user can reconcile them through existing
		mechanisms. NO action affordance here (resolution is SELF-205). Empty-state when none.
	-->
	<section class="region" aria-label="Possible duplicates">
		<h2 class="section-title">Possible duplicates</h2>
		<DuplicateCandidateList candidates={dupCandidates} />
	</section>

	<section class="region" aria-label="Transactions">
		<h2 class="section-title">Transactions</h2>
		{#if transactions.length === 0}
			<p class="empty">No transactions yet.</p>
		{:else}
			<div class="table-scroll">
				<table class="tbl">
					<thead>
						<tr>
							<th scope="col">Date</th>
							<th scope="col">Category</th>
							<th scope="col">Vendor</th>
							<th scope="col">Description</th>
							<th scope="col" class="num">Amount</th>
							<th scope="col">Actions</th>
						</tr>
					</thead>
					<tbody>
						{#each transactions as t (t.trans_id)}
							<TransactionRow transaction={t} subCatGroups={cashflowGroups} columns={TABLE_COLUMNS} />
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>

	<!--
		Per-account sync history (SELF-204). Rendered ONLY for provider-linked accounts (a manual
		account has no sync history); the component's empty-state covers a linked account with no
		history rows yet. Read-only — no edit/delete affordance (AC requirement, RBAC-tested).
	-->
	{#if !isSourceOfTruth}
		<section class="region" aria-label="Sync history">
			<div class="sync-head">
				<h2 class="section-title">Sync history</h2>
				<!--
					Per-account "Sync now" (SELF-317) — the account's own linked source. On accept the
					control polls via loader invalidation, so this panel re-fetches and the new
					`source='manual'` row appears once the sync lands. No `lastSyncedAt` scalar on this
					surface, so the poll runs its full window rather than short-circuiting on advance.
				-->
				<SyncNowControl source_id={String(account.linked_source_id)} />
			</div>
			<SyncHistoryTable rows={syncHistory} />
		</section>
	{/if}
</main>

<style>
	.page {
		max-width: 52rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.breadcrumb {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.breadcrumb a {
		color: var(--c-link);
		text-decoration: none;
	}
	.breadcrumb a:hover {
		text-decoration: underline;
	}
	.breadcrumb .sep {
		color: var(--c-text-muted);
	}
	.breadcrumb .crumb-current {
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
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
		font-size: var(--fs-h1);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-text-primary);
	}
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
	.status.inactive {
		color: var(--c-text-muted);
		border-style: dashed;
	}
	.region {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		box-shadow: var(--shadow-1);
	}
	.section-title {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.attrs {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--space-4);
		margin: 0;
	}
	@media (max-width: 560px) {
		.attrs {
			grid-template-columns: 1fr;
		}
	}
	.attr {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.attr dt {
		font-size: var(--fs-small);
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--c-text-muted);
		font-weight: var(--weight-semi);
	}
	.attr dd {
		margin: 0;
		color: var(--c-text-primary);
		overflow-wrap: anywhere;
	}
	.attr-hint {
		margin: var(--space-1) 0 0;
		font-size: var(--fs-small);
		line-height: var(--lh-body);
		color: var(--c-text-muted);
	}
	.help {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	.form-error {
		margin: 0 0 var(--space-3);
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.sync-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.table-scroll {
		overflow-x: auto;
	}
	.tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	/* Header cells live in this component; body cells (<td>) are rendered by TransactionRow,
	   so the td-level rules are :global-scoped to this page-owned .tbl to reach them. */
	.tbl th,
	.tbl :global(td) {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
		white-space: nowrap;
	}
	.tbl th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.tbl :global(td.num),
	.tbl th.num {
		text-align: right;
	}
	.tbl :global(.num-cell) {
		font-family: var(--font-num);
	}
	.tbl :global(tbody tr:hover td) {
		background: var(--c-surface-alt);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
	}
</style>
