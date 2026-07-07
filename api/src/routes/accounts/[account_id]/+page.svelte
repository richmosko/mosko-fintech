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
	import { reassignSubCatSchema, fieldErrors } from '$lib/schemas/account';
	import Button from '$lib/components/Button.svelte';
	import SelectField from '$lib/components/SelectField.svelte';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const account = $derived(data.account);
	const transactions = $derived(data.transactions);

	let toggling = $state(false);

	// ── Sub-Cat reassignment (SELF-236 §2.2.1.c) ──────────────────────────────
	let editing = $state(false);
	let saving = $state(false);
	// Editor selection; '' = Unsorted (posts empty → server coerces null). Seeded to the
	// current assignment by openEditor() each time the editor opens (starts collapsed).
	let selected = $state('');
	// Scoped to the reassign action (NOT the shared `form` prop) so a toggleActive
	// failure can't bleed its errors into this editor and vice-versa.
	let reassignErrors = $state<Record<string, string[]>>({});

	const currentSubCatLabel = $derived(
		account.cat ? `${account.cat} › ${account.sub_cat}` : account.sub_cat
	);

	// Sub-Cat options grouped by `cat` (accessible <optgroup>) — same shape as the
	// create form's picker (AC #2: reuse the SelectField component). Server order kept.
	const subCatGroups = $derived.by(() => {
		const byCat = new Map<string, { value: string; label: string }[]>();
		for (const s of data.subCats) {
			if (!byCat.has(s.cat)) byCat.set(s.cat, []);
			byCat.get(s.cat)!.push({ value: String(s.id), label: s.sub_cat });
		}
		return [...byCat.entries()].map(([cat, options]) => ({ label: cat, options }));
	});

	function openEditor() {
		selected = String(account.sub_cat_id ?? ''); // re-sync to current on each open
		reassignErrors = {};
		editing = true;
	}
	function cancelEditor() {
		editing = false;
		reassignErrors = {};
	}

	// use:enhance — client-validate, POST the reassign, refresh the label via invalidation.
	const reassignHandler: SubmitFunction = ({ cancel }) => {
		const parsed = reassignSubCatSchema.safeParse({ sub_cat_id: selected });
		if (!parsed.success) {
			reassignErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		reassignErrors = {};
		saving = true;
		return async ({ result, update }) => {
			saving = false;
			if (result.type === 'success') {
				await update(); // invalidates → load re-runs → cat/sub_cat label refreshes
				editing = false;
			} else if (result.type === 'failure') {
				reassignErrors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not update the sub-category. Please try again.'] };
			} else {
				await update();
			}
		};
	};

	const toggleHandler: SubmitFunction = () => {
		toggling = true;
		return async ({ update }) => {
			await update(); // success → load reruns → is_active refreshes; failure → form.errors
			toggling = false;
		};
	};

	// Neutral money formatting (NOT pos/neg coloured — ledger amount, not performance).
	function money(raw: string | number): string {
		const n = typeof raw === 'number' ? raw : Number(raw);
		if (!Number.isFinite(n)) return String(raw);
		return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
	}

	function humanize(v: string | null): string {
		if (!v) return '—';
		return v.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());
	}
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
			</div>
			<div class="attr">
				<dt>Scope</dt>
				<dd>{account.scope}</dd>
			</div>
			<div class="attr">
				<dt>Tax treatment</dt>
				<dd>{taxTreatmentLabel(account.tax_treatment)}</dd>
			</div>
		</dl>
	</section>

	<!--
		SELF-197+ FORK-B: gate this whole section on `plaid_item_id IS NULL` (manual-only)
		once a Plaid-vs-manual discriminator exists. For now the picker shows on ALL accounts
		— the AC #4 manual-only gate is deferred per F/CTO (no discriminator yet).
	-->
	<section class="region" aria-label="Sub-category">
		<div class="subcat-head">
			<div class="subcat-current">
				<h2 class="section-title">Sub-category</h2>
				<p class="current">{currentSubCatLabel}</p>
			</div>
			{#if !editing}
				<Button
					variant="secondary"
					type="button"
					onclick={openEditor}
					aria-expanded={editing}
					aria-controls="subcat-editor"
				>
					Edit
				</Button>
			{/if}
		</div>

		{#if editing}
			<form
				id="subcat-editor"
				method="POST"
				action="?/reassignSubCat"
				use:enhance={reassignHandler}
				class="subcat-form"
				novalidate
			>
				<SelectField
					label="Sub-category"
					name="sub_cat_id"
					bind:value={selected}
					errors={reassignErrors.sub_cat_id}
					hint="Choose a sub-category, or Unsorted to leave it uncategorised."
					placeholder={{ value: '', label: 'Unsorted' }}
					groups={subCatGroups}
				/>
				{#if reassignErrors._form}
					<p class="form-error" role="alert">{reassignErrors._form.join(' ')}</p>
				{/if}
				<div class="actions">
					<Button variant="link" type="button" onclick={cancelEditor}>Cancel</Button>
					<Button variant="primary" type="submit" loading={saving}>Save</Button>
				</div>
			</form>
		{/if}
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
							<th scope="col">Type</th>
							<th scope="col">Vendor</th>
							<th scope="col">Description</th>
							<th scope="col" class="num">Amount</th>
						</tr>
					</thead>
					<tbody>
						{#each transactions as t (t.trans_id)}
							<tr>
								<td class="num-cell">{t.transaction_date}</td>
								<td>
									{humanize(t.transaction_type)}
									{#if t.is_reverse}<span class="rev-tag">Reversal</span>{/if}
								</td>
								<td>{t.vendor ?? '—'}</td>
								<td>{t.description ?? '—'}</td>
								<td class="num num-cell">{money(t.amount)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}
	</section>
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
	.subcat-head {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.subcat-current .section-title {
		margin-bottom: var(--space-1);
	}
	.current {
		margin: 0;
		color: var(--c-text-primary);
		overflow-wrap: anywhere;
	}
	.subcat-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		margin-top: var(--space-4);
		max-width: 22rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		align-items: center;
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
	.tbl th,
	.tbl td {
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
	.tbl td.num,
	.tbl th.num {
		text-align: right;
	}
	.num-cell {
		font-family: var(--font-num);
	}
	.tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}
	.rev-tag {
		display: inline-block;
		margin-left: var(--space-1);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-sm);
		padding: 0 var(--space-1);
		font-size: var(--fs-micro);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--c-text-muted);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
	}
</style>
