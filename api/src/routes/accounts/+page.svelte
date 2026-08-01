<!--
	accounts/+page.svelte — the Accounts Hub (§2.4 wireframe §1; sidebar destination #1).
	Frontend-owned browser surface. Consumes +page.server.ts's `data` (HubAccount[] with the
	chip inputs resolved server-side); authors NO server logic.

	The account list grouped by account-type category (the §2.1.5 vocabulary), the two
	onboarding CTAs (Connect institution / Add manual), a collapsed Inactive group, and links
	out to Net Worth + Connections. Each row deep-links to Account Detail.

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

	const active = $derived(accounts.filter((a) => a.is_active));
	const inactive = $derived(accounts.filter((a) => !a.is_active));

	// Active accounts grouped by type, in the locked category order; empty groups dropped.
	const activeGroups = $derived(
		TYPE_ORDER.map((type) => ({
			type,
			label: typeLabel(type),
			rows: active.filter((a) => a.account_type === type)
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
		{#each activeGroups as group (group.type)}
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
								<ConnectionStatusChip
									connection_status={a.connection_status}
									provider={a.provider}
									is_active={a.is_active}
								/>
							</a>
						</li>
					{/each}
				</ul>
			</section>
		{/each}

		{#if active.length === 0}
			<!-- Every account is inactive: no active groups rendered, so nudge toward the Inactive
			     group below rather than showing a blank hub. -->
			<p class="card-note all-inactive">
				All of your accounts are inactive. Expand the group below to review them, or add a new one.
			</p>
		{/if}

		{#if inactive.length > 0}
			<details class="inactive-group card">
				<summary>Inactive ({inactive.length})</summary>
				<ul class="acct-list inactive-list">
					{#each inactive as a (a.account_id)}
						<li>
							<a class="acct-row" href="/accounts/{a.account_id}">
								<span class="acct-id">
									<span class="acct-name">{a.name}</span>
									<span class="acct-meta">
										{typeLabel(a.account_type)} · {a.scope} · {taxLabel(a.tax_treatment)}
									</span>
								</span>
								<ConnectionStatusChip
									connection_status={a.connection_status}
									provider={a.provider}
									is_active={a.is_active}
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
	.all-inactive {
		margin: 0;
	}
	.empty-cta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-1);
	}

	/* ── inactive group ───────────────────────────────────────────────────── */
	.inactive-group {
		padding: var(--space-3) var(--space-5);
	}
	.inactive-group summary {
		cursor: pointer;
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.inactive-group summary:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.inactive-list {
		margin-top: var(--space-3);
	}
	.inactive-list .acct-row {
		padding: var(--space-3) 0;
		border-top: 1px solid var(--c-border);
	}
	.inactive-list .acct-name {
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
