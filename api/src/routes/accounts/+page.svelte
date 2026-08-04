<!--
	accounts/+page.svelte — the Accounts Hub (§2.4 wireframe §1; sidebar destination #1).
	Frontend-owned browser surface. Consumes +page.server.ts's `data` (HubAccount[] with the
	chip inputs resolved server-side); authors NO server logic.

	The account list grouped by account-type category (the §2.1.5 vocabulary), the two
	onboarding CTAs (Connect institution / Add manual), a collapsed Closed group, and links
	out to Net Worth + Connections. Each row deep-links to Account Detail.

	CLOSURE IS A DATE, NOT A FLAG (ADR-042 / `059`). `pfin.account.is_active` is gone; the hub
	partitions on `HubAccount.closed_at !== null` and the collapsed group is "Closed", not
	"Inactive". This is a MANAGEMENT surface, so it deliberately shows closed accounts rather
	than filtering them — only NAV / current-state / aggregation scopes narrow (api/CLAUDE.md).
	The closed rows carry their closure DATE, which is the thing a boolean could never say.

	SCOPE (v1.129 — kills the /accounts 404): this is the locked Hub MINUS the per-account
	gross-value column + the "Gross total (pre-tax-adjustment)" footer — those need a new
	per-account valuation read (no such DB function exists yet; fn_compute_nav is whole-position)
	and land as a follow-up. Per PM-2, this page shows NO NAV / hero number — the net-worth
	number lives on the dashboard; a footer link points there.

	Tokens ONLY (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). a11y: semantic lists, the
	chip carries its own sr-only status prefix, rows + disclosure are keyboard-native.
-->
<script lang="ts">
	import type { PageData } from './$types';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import { closedAtLabel } from '$lib/account-display';

	let { data }: { data: PageData } = $props();

	type HubAccount = PageData['accounts'][number];

	// `error` distinguishes a read failure (retriable) from a true-empty (onboarding nudge).
	const loadError = $derived(data.error);
	const accounts = $derived(data.accounts);

	// The account-type display order + labels — the §2.1.5 category vocabulary (wireframe §1).
	const TYPE_ORDER = [
		'depository',
		'investment',
		'retirement',
		'crypto',
		'manual_other',
		'real_estate',
		'liability'
	] as const;
	const TYPE_LABEL: Record<string, string> = {
		depository: 'Depository',
		investment: 'Investment',
		retirement: 'Retirement',
		crypto: 'Crypto',
		manual_other: 'Manual / Other',
		real_estate: 'Real estate',
		liability: 'Liabilities'
	};
	const TAX_LABEL: Record<string, string> = {
		taxable: 'taxable',
		tax_deferred: 'tax-deferred',
		tax_free: 'tax-free'
	};

	const typeLabel = (t: string) => TYPE_LABEL[t] ?? t;
	const taxLabel = (t: string) => TAX_LABEL[t] ?? t;

	// ADR-042 / `059`: partition on the closure DATE. `closed_at === null` is the current-state
	// question this page asks ("is it closed now?"), which is the one question the naive form
	// answers correctly — the as-of form (`closed_at is null or closed_at > <as_of>`) belongs to
	// surfaces that read a date, and this one reads none. Noted because the two are easy to swap.
	const open = $derived(accounts.filter((a) => a.closed_at === null));
	const closed = $derived(accounts.filter((a) => a.closed_at !== null));

	// Open accounts grouped by type, in the locked category order; empty groups dropped.
	const openGroups = $derived(
		TYPE_ORDER.map((type) => ({
			type,
			label: typeLabel(type),
			rows: open.filter((a) => a.account_type === type)
		})).filter((g) => g.rows.length > 0)
	);
</script>

<svelte:head>
	<title>Accounts · mosko-fintech</title>
</svelte:head>

<main class="page">
	<header class="hub-header">
		<h1>Accounts</h1>
		<div class="actions">
			<a class="cta cta-primary" href="/accounts/connect">+ Connect institution</a>
			<a class="cta" href="/accounts/new">+ Add manual</a>
		</div>
	</header>

	{#if loadError}
		<p class="form-error" role="alert">
			We couldn't load your accounts. Please refresh the page to try again.
		</p>
	{:else if accounts.length === 0}
		<!-- Empty state (wireframe §1): no accounts → onboarding nudge with the two actions. -->
		<section class="region card empty" aria-labelledby="empty-heading">
			<h2 id="empty-heading">No accounts yet</h2>
			<p class="card-note">
				Connect your first institution to sync it automatically, or add an account you'll update by
				hand.
			</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts/connect">Connect an institution</a>
				<a class="cta" href="/accounts/new">Add a manual account</a>
			</div>
		</section>
	{:else}
		{#each openGroups as group (group.type)}
			<section class="group" aria-labelledby="grp-{group.type}">
				<h2 class="group-heading" id="grp-{group.type}">{group.label}</h2>
				<ul class="acct-list">
					{#each group.rows as a (a.account_id)}
						<li>
							<a class="acct-row card" href="/accounts/{a.account_id}">
								<span class="acct-id">
									<span class="acct-name">{a.name}</span>
									<span class="acct-meta">{a.scope} · {taxLabel(a.tax_treatment)}</span>
								</span>
								<!--
									⚠ `is_active` is NOT passed any more, and the omission is load-bearing.
									This chip's `is_active` prop means `linked_source.is_active` — the
									CONNECTION lifecycle flag, "sync is paused" (see connectionChipState's
									own precedence note). This page was feeding it `pfin.account.is_active`,
									a different column with accounting semantics, so a *closed* account
									rendered as a *paused connection*. Both spell `is_active`, so no text
									search could see it. Post-`059` the account column is gone; closedness
									is carried by the Closed group and the detail page's pill, and the chip
									falls back to its `true` default so it describes the connection alone.

									STILL OWED: the hub cannot yet pass the connection's REAL flag, because
									`HubAccount` does not carry it (Backend resolves `provider` +
									`connection_status` from the connection but not `is_active`). Until it
									does, a linked account under a DEACTIVATED connection shows a health
									chip instead of "paused". Requested from Backend; tracked in the PR
									report rather than papered over with `closed_at`, which would re-commit
									the conflation under the new column.
								-->
								<ConnectionStatusChip
									connection_status={a.connection_status}
									provider={a.provider}
								/>
							</a>
						</li>
					{/each}
				</ul>
			</section>
		{/each}

		{#if open.length === 0}
			<!-- Every account is closed: no open groups rendered, so nudge toward the Closed
			     group below rather than showing a blank hub. -->
			<p class="card-note all-closed">
				All of your accounts are closed. Expand the group below to review them, or add a new one.
			</p>
		{/if}

		{#if closed.length > 0}
			<details class="closed-group card">
				<summary>Closed ({closed.length})</summary>
				<ul class="acct-list closed-list">
					{#each closed as a (a.account_id)}
						<li>
							<a class="acct-row" href="/accounts/{a.account_id}">
								<span class="acct-id">
									<span class="acct-name">{a.name}</span>
									<!-- The closure DATE is the whole reason `closed_at` replaced a boolean;
									     a management view that can only say THAT an account is closed, not
									     WHEN, throws away the field's only added information. -->
									<span class="acct-meta">
										{typeLabel(a.account_type)} · {a.scope} · {taxLabel(a.tax_treatment)} ·
										Closed {closedAtLabel(a.closed_at)}
									</span>
								</span>
								<ConnectionStatusChip
									connection_status={a.connection_status}
									provider={a.provider}
								/>
							</a>
						</li>
					{/each}
				</ul>
			</details>
		{/if}
	{/if}

	<!-- Footer links (NO gross total / NAV per PM-2 — the number lives on the dashboard). -->
	<footer class="hub-footer">
		<a class="foot-link" href="/">See your net worth →</a>
		<a class="foot-link" href="/accounts/connections">Manage aggregator connections →</a>
	</footer>
</main>

<style>
	.page {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.hub-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	h1 {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}

	/* Anchor CTAs styled to the locked `.btn` language (Button.svelte renders a <button>, so
	   nav CTAs style anchors directly — tokens only; mirrors the root dashboard). */
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

	.card {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-1);
	}

	/* ── grouped list ─────────────────────────────────────────────────────── */
	.group {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.group-heading {
		margin: 0;
		font: var(--weight-semi) var(--fs-small) / 1 var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}
	.acct-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.acct-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-4) var(--space-5);
		text-decoration: none;
		color: inherit;
	}
	.acct-row:hover {
		background: var(--c-surface-alt);
	}
	.acct-row:active {
		background: var(--c-surface-alt2);
	}
	.acct-row:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.acct-id {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.acct-name {
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.acct-meta {
		font: var(--weight-reg) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-text-muted);
	}

	/* ── empty state ──────────────────────────────────────────────────────── */
	.empty {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		padding: var(--space-5);
	}
	.card h2 {
		margin: 0 0 var(--space-2);
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.card-note {
		margin: 0 0 var(--space-3);
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.all-closed {
		margin: 0;
	}
	.empty-cta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}

	/* ── closed group ─────────────────────────────────────────────────────── */
	.closed-group {
		padding: var(--space-3) var(--space-5);
	}
	.closed-group summary {
		cursor: pointer;
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.closed-group summary:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.closed-list {
		margin-top: var(--space-3);
	}
	.closed-list .acct-row {
		padding: var(--space-3) 0;
		border-top: 1px solid var(--c-border);
	}
	.closed-list .acct-name {
		color: var(--c-text-secondary);
	}

	/* ── footer links ─────────────────────────────────────────────────────── */
	.hub-footer {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-4);
		padding-top: var(--space-2);
		border-top: 1px solid var(--c-border);
	}
	.foot-link {
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.foot-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.foot-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	/* ── error ────────────────────────────────────────────────────────────── */
	.form-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
</style>
