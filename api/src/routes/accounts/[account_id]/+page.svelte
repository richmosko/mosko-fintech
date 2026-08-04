<!--
	accounts/[account_id]/+page.svelte — account detail + the CLOSE / REOPEN control.
	SELF-201 §2.4.2 AC #3/#4, re-pointed at `059` per ADR-042. Renders the account attributes +
	its transaction history (the AcctSetup opening-balance row appears here).

	CLOSURE IS A DATED EVENT, NOT A FLAG (ADR-042 Decision 1 + 2). `pfin.account.is_active` was
	dropped at `059`; the account carries `closed_at timestamptz` (NULL = open) and the page
	branches on `closed_at !== null`. Two named actions, NOT a toggle: `?/closeAccount` (posts a
	required `reason_code`) and `?/reopenAccount` (posts NOTHING — its server schema is
	`z.object({}).strict()`, so any stray field is a 400 rather than an ignored value).

	WHAT THIS PAGE MUST NOT IMPLY. The old copy here read "marking inactive = is_active=false …
	the account is excluded from current-value surfaces (other issues' backend concern)". Both
	halves are now false. There is no flag; and the exclusion is not delegated — Decision 3 makes
	ZERO VALUE A PRECONDITION `058` ENFORCES, so a close is REFUSED while the account still holds
	securities or cash as of the closing date, or has activity dated after it. The user must learn
	that BEFORE they press the button, which is why the help text names the gate rather than
	describing a label change. History is still RETAINED (AC #4) — and a closed account is
	additionally FROZEN: corrections go reopen → correct → re-close.

	COPY IS PROVISIONAL — the closure help text, the status pill wording and the reason labels are
	placeholders pending PM/UX. Flagged at authoring, not settled here.

	FENCES: no --c-pos/--c-neg on values (those are ACTUAL-performance only; ledger amounts
	are neutral). No staleness banner — a manual account has no Plaid re-auth. INV-1: name +
	scope are free-text → plain text. acct_number is not exposed (SD-15; masked-only posture).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { PageData, ActionData } from './$types';
	import { CLOSURE_REASONS, CLOSURE_REASON_LABELS } from '$lib/schemas/account-constants';
	import { accountTypeLabel, taxTreatmentLabel, closedAtLabel } from '$lib/account-display';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import TransactionEntryForm from '$lib/components/TransactionEntryForm.svelte';
	import StockSplitEntryForm from '$lib/components/StockSplitEntryForm.svelte';
	import DuplicateCandidateList from '$lib/components/DuplicateCandidateList.svelte';
	import SyncHistoryTable from '$lib/components/SyncHistoryTable.svelte';
	import SyncNowControl from '$lib/components/SyncNowControl.svelte';
	import TransactionRow from '$lib/components/TransactionRow.svelte';
	import { subCatGroupsOf } from '$lib/transaction-util';
	import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';
	import { updateAttributesSchema, closeAccountSchema, fieldErrors } from '$lib/schemas/account';
	import { providerLabel } from '$lib/accounts/connection-display';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const account = $derived(data.account);
	const transactions = $derived(data.transactions);

	// ADR-042 / `059`: closure is a DATE, not a flag. This is a RENDER surface — it asks "is this
	// account closed right now?" — so `closed_at !== null` is the correct AND COMPLETE answer
	// (api/CLAUDE.md closure contract, render-vs-valuation split).
	//
	// The as-of form (`closed_at is null or closed_at > <as_of>`) is not merely heavier here, it
	// is WRONG: it needs an `as_of` this page has no business choosing, to answer a question
	// nobody asked. That form is mandatory on VALUATION surfaces (NAV, aggregation, any
	// presence-check paired with a NAV read) BECAUSE THAT IS WHERE THE SILENT-FLIP RISK LIVES —
	// there the two forms are behaviourally identical until a closed account exists, so no test
	// on today's data separates them. No such trap here: the current-state answer is the one
	// being asked for, and it is verifiable by looking at the screen.
	const isClosed = $derived(account.closed_at !== null);

	// Connections-redesign Aggregation section: THIS account's connection state (provider + health +
	// last-sync), resolved server-side from its linked_source_id. null = manual / non-linked account.
	const connection = $derived(data.connection);
	const isLinked = $derived(account.linked_source_id != null);

	// Select options for the attribute-edit form — labels via account-display, values from the
	// shared account-constants (anti-drift with the DB CHECK; same value-sets the server enforces).
	const accountTypeOptions = ACCOUNT_TYPES.map((v) => ({ value: v, label: accountTypeLabel(v) }));
	const taxTreatmentOptions = TAX_TREATMENTS.map((v) => ({ value: v, label: taxTreatmentLabel(v) }));

	function formatSyncTime(iso: string | null): string {
		if (!iso) return 'Never synced';
		const d = new Date(iso);
		if (Number.isNaN(d.getTime())) return '—';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(d);
	}

	// ── Attribute edit (updateAttributes) ────────────────────────────────────────────────────
	// The Edit affordance swaps the read-only attribute display for an inline form. Client-side
	// `.strict()` mirror (updateAttributesSchema) gives fast field-level feedback before the POST;
	// the SERVER schema is the security boundary (Lock 14). Values live in local $state seeded from
	// the account on open, so a cancel discards cleanly and a save closes on the success result.
	let editing = $state(false);
	let saving = $state(false);
	let editErrors = $state<Record<string, string[]>>({});
	let editName = $state('');
	let editType = $state('');
	let editScope = $state('');
	let editTax = $state('');

	function openEditor() {
		editName = account.name;
		editType = account.account_type;
		editScope = account.scope;
		editTax = account.tax_treatment;
		editErrors = {};
		editing = true;
	}
	function cancelEditor() {
		editing = false;
		editErrors = {};
	}

	const editHandler: SubmitFunction = ({ formData, cancel }) => {
		// Client mirror of the server .strict() schema — reject an obviously-bad submit before the
		// round-trip. Same value-sets + posture as the server; never looser (api/CLAUDE.md).
		const parsed = updateAttributesSchema.safeParse(Object.fromEntries(formData));
		if (!parsed.success) {
			editErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		editErrors = {};
		saving = true;
		return async ({ update, result }) => {
			await update({ reset: false }); // success → load reruns → name/attrs refresh
			saving = false;
			if (result.type === 'success') {
				editing = false;
			} else if (result.type === 'failure' && result.data && 'errors' in result.data) {
				editErrors = (result.data.errors as Record<string, string[]>) ?? {};
			}
		};
	};

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

	// ── Close / reopen (ADR-042 Decision 1) ──────────────────────────────────────────────────
	// One `submitting` flag, because the two forms are mutually exclusive by `isClosed` — only
	// ever one of them is on the page.
	let submitting = $state(false);
	let closeErrors = $state<Record<string, string[]>>({});
	// Seeded EMPTY, not to the first reason — see the placeholder note on the form below.
	let reasonCode = $state('');

	const closureReasonOptions = CLOSURE_REASONS.map((r) => ({
		value: r,
		label: CLOSURE_REASON_LABELS[r]
	}));

	// CLOSE — the client `.strict()` mirror runs before the POST (fast field feedback). It is
	// NOT the boundary: `058`'s gate is, and it is the only thing that can answer "does this
	// account still hold value?", which no client check can. All the mirror does is refuse a
	// missing/out-of-set reason_code before a round trip.
	const closeHandler: SubmitFunction = ({ formData, cancel }) => {
		const parsed = closeAccountSchema.safeParse(Object.fromEntries(formData));
		if (!parsed.success) {
			closeErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		closeErrors = {};
		submitting = true;
		return async ({ update }) => {
			await update(); // success → load reruns → closed_at refreshes; failure → form.errors
			submitting = false;
		};
	};

	// REOPEN — posts nothing at all, so there is nothing to validate client-side. See
	// `reopenAccountSchema` in $lib/schemas/account for why the empty mirror is deliberately NOT
	// wired here (a client cancel() on a stray field would be silent; the server 400 is visible).
	const reopenHandler: SubmitFunction = () => {
		submitting = true;
		return async ({ update }) => {
			await update();
			submitting = false;
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
			<!-- The pill carries the STATE only; the DATE lives in the Account status section
			     below. Splitting them keeps the pill short next to a free-text account name that
			     can be 200 characters, and puts the date next to the copy that explains it. -->
			<span class="status" class:closed={isClosed}>
				{isClosed ? 'Closed' : 'Open'}
			</span>
		</div>
	</header>

	<section class="region" aria-label="Account details">
		<div class="section-head">
			<h2 class="section-title">Account details</h2>
			{#if !editing}
				<Button variant="secondary" onclick={openEditor}>Edit</Button>
			{/if}
		</div>

		{#if editing}
			<!-- Inline attribute editor (updateAttributes) — replaces the read-only display while open.
			     name / account_type / scope / tax_treatment. Client `.strict()` mirror guards submit. -->
			<form method="POST" action="?/updateAttributes" use:enhance={editHandler} class="edit-form">
				{#if editErrors._form}
					<p class="form-error" role="alert">{editErrors._form.join(' ')}</p>
				{/if}
				<TextField
					label="Name"
					name="name"
					bind:value={editName}
					required
					maxlength={200}
					errors={editErrors.name ?? []}
				/>
				<SelectField
					label="Type"
					name="account_type"
					bind:value={editType}
					required
					options={accountTypeOptions}
					hint="How this account is grouped — cash, investment, retirement, crypto, real estate, or liability."
					errors={editErrors.account_type ?? []}
				/>
				<TextField
					label="Scope"
					name="scope"
					bind:value={editScope}
					required
					maxlength={200}
					hint="Your own ownership label (e.g. personal, joint, trust) — used to group accounts across views."
					errors={editErrors.scope ?? []}
				/>
				<SelectField
					label="Tax treatment"
					name="tax_treatment"
					bind:value={editTax}
					required
					options={taxTreatmentOptions}
					hint="How the account is taxed: taxable, tax-deferred, or tax-free. Feeds the estimated-tax view."
					errors={editErrors.tax_treatment ?? []}
				/>
				<div class="edit-actions">
					<Button type="submit" variant="primary" loading={saving}>Save changes</Button>
					<Button type="button" variant="secondary" onclick={cancelEditor}>Cancel</Button>
				</div>
			</form>
		{:else}
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
		{/if}
	</section>

	<!--
		Account linking & aggregation (connections-redesign). Shows how this account is fed:
		aggregator service (provider or manual), connection health, last sync, the descriptive
		daily-sync line + per-account "Sync now" for linked accounts, and a discoverable (grayed)
		"Change aggregator" placeholder — the affordance is present now; the backend lands later.
	-->
	<section class="region" aria-label="Account linking &amp; aggregation">
		<h2 class="section-title">Account linking &amp; aggregation</h2>
		<dl class="attrs">
			<div class="attr">
				<dt>Aggregator service</dt>
				<dd>{connection ? providerLabel(connection.provider) : 'None (manual)'}</dd>
				<p class="attr-hint">
					The data aggregator that syncs this account. Manual accounts have no aggregator — you
					update them by hand.
				</p>
			</div>
			{#if connection}
				<div class="attr">
					<dt>Connection status</dt>
					<dd>
						<ConnectionStatusChip
							connection_status={connection.connection_status}
							provider={connection.provider}
						/>
					</dd>
				</div>
				<div class="attr">
					<dt>Last synced</dt>
					<dd>{formatSyncTime(connection.last_successful_sync_at)}</dd>
				</div>
			{/if}
		</dl>

		{#if isLinked}
			<p class="sync-note">Syncs automatically (daily).</p>
			<div class="agg-actions">
				<SyncNowControl source_id={String(account.linked_source_id)} />
			</div>
		{/if}

		<div class="agg-change">
			<Button variant="secondary" disabled aria-describedby="change-agg-note">
				Change aggregator
			</Button>
			<p id="change-agg-note" class="agg-note">
				Coming soon — switching an account's aggregator isn't available yet.
			</p>
		</div>
	</section>

	<section class="region" aria-label="Account status">
		<h2 class="section-title">Account status</h2>

		{#if isClosed}
			<p class="help">
				Closed {closedAtLabel(account.closed_at)}. Its transaction history is kept, and it no
				longer counts toward balances or totals dated on or after that day. While it's closed
				it can't take new entries — including automatic ones from a connected institution. To
				correct something, reopen it, make the correction, and close it again.
			</p>
		{:else}
			<!--
				This copy NAMES THE GATE rather than describing a label change, because `058` refuses
				a close that the user has every reason to expect will succeed. Learning about the
				precondition from a refusal is the *gate-with-no-way-forward* shape ADR-042 Decision 1
				fences for elsewhere. Provisional wording — PM/UX own the final text.
			-->
			<p class="help">
				Close this account once it's been emptied. Closing is only allowed when the account
				holds nothing on the closing date — no securities, no cash — and has no activity dated
				after it. If it still holds value, record the sale or transfer out first, then close.
				Its transaction history is always kept, and you can reopen it at any time.
			</p>
		{/if}

		{#if form && 'errors' in form && form.errors?._form}
			<p class="form-error" role="alert">{form.errors._form.join(' ')}</p>
		{/if}

		<!--
			TWO FORMS, NOT A TOGGLE — mirroring Backend's two named actions, which mirror the two
			INVOKER RPCs (`fn_close_account` / `fn_reopen_account`). One form posting a direction
			boolean is what `059` retired; the directions carry different payloads.
		-->
		{#if isClosed}
			<!--
				REOPEN posts NOTHING. `reopenAccountSchema` is `z.object({}).strict()` server-side, so
				a stray field is a 400, not an ignored value. Keep it that way: no hidden inputs, and
				`Button` must stay `name`-less (a named submit button posts its own name/value).
				Reopening is deliberately UNGATED (Decision 3) — a closed account is already at zero
				by the gate that admitted it, so gating the exit would be incoherent.
			-->
			<form method="POST" action="?/reopenAccount" use:enhance={reopenHandler}>
				<Button type="submit" variant="primary" loading={submitting}>Reopen account</Button>
			</form>
		{:else}
			<form method="POST" action="?/closeAccount" use:enhance={closeHandler} class="close-form">
				<!--
					reason_code is MANDATORY on the into-closed transition (`057`'s CHECK; `058`'s audit
					writer refuses without it and will not invent one). Values come from the shared
					account-constants, copied verbatim from the CHECK — the LABELS are placeholders
					pending PM + UX copy. Reopening carries no reason vocabulary at all, which is why
					this control lives only on the close branch.

					THE EMPTY PLACEHOLDER IS DELIBERATE and is a change from the hand-rolled <select>
					that stood here, which auto-selected the first reason. That reason is written into
					`pfin.account_event`, which is IMMUTABLE audit-class (ADR-011 Decision 2) — so a
					defaulted reason records a fact the user never asserted, in the one table that
					cannot later be corrected. "Sold" and "no longer used" are not interchangeable to
					anyone reading that history back. The empty value fails the client mirror's
					`z.enum` and renders inline, so the cost of requiring a choice is one visible
					error rather than a silent falsehood.

					Rendered through the design-system SelectField rather than a raw <select>: the
					hand-rolled one carried no token styling, no aria-invalid/describedby wiring and
					no error slot at all.
				-->
				<SelectField
					label="Reason for closing"
					name="reason_code"
					bind:value={reasonCode}
					required
					placeholder={{ value: '', label: 'Select a reason…' }}
					options={closureReasonOptions}
					errors={closeErrors.reason_code ?? []}
				/>
				<div class="close-actions">
					<Button type="submit" variant="secondary" loading={submitting}>Close account</Button>
				</div>
			</form>
		{/if}
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
			<h2 class="section-title">Sync history</h2>
			<!--
				The per-account "Sync now" (SELF-317) control now lives in the "Account linking &
				aggregation" section above (its canonical connections-redesign home) — deduped so a
				linked account shows a single Sync-now affordance. This panel keeps the history table.
			-->
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
	/* Closed = muted + dashed. Deliberately NOT --c-neg: a closed account is a bookkeeping
	   state, not an error or a negative value, and --c-neg is reserved for ACTUAL-performance
	   amounts (the page's standing fence). Tone is carried by weight + border style. */
	.status.closed {
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
	.section-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		margin-bottom: var(--space-3);
	}
	.section-head .section-title {
		margin: 0;
	}
	.edit-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.edit-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}
	/* Close form — same column rhythm as .edit-form so the two forms on this page match. */
	.close-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		max-width: 24rem;
	}
	.close-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.sync-note {
		margin: var(--space-3) 0 var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.agg-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.agg-change {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		margin-top: var(--space-4);
		padding-top: var(--space-3);
		border-top: 1px solid var(--c-border);
	}
	.agg-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
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
