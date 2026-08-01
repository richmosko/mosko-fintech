<!--
	accounts/connections/[source_id]/+page.svelte — connections-redesign per-connection USE / IGNORE
	edit page. Frontend-owned browser surface. Consumes Backend's `[source_id]/+page.server.ts`:
	load → { connection: ConnectionState, accounts: ConnectionAccount[] } (active AND inactive —
	management view, not NAV); action `?/toggleAccount` (body { account_id, is_active }, `.strict()`)
	flips one account's is_active.

	The page titles the provider + connection and lists every account under it. Each row carries a
	"Use / Ignore" control: one `<form method="POST" action="?/toggleAccount">` per row (hidden
	account_id + the is_active FLIP), use:enhance. "Use" = is_active true; "Ignore" = false. Ignored
	accounts are hidden from balances/totals but their history is kept — stated up front.

	Tokens ONLY (var(--c-*)). a11y: semantic list, current state carries an sr-only prefix, the flip
	button names the account + the action it performs, per-connection error role="alert",
	keyboard-native. No secrets, no server imports.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { PageData, ActionData } from './$types';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import Button from '$lib/components/Button.svelte';
	import { accountTypeLabel } from '$lib/account-display';
	import { providerLabel, providerHomeUrl } from '$lib/accounts/connection-display';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const connection = $derived(data.connection);
	const accounts = $derived(data.accounts);
	const homeUrl = $derived(providerHomeUrl(connection.provider));

	// Which account row is mid-submit — a per-row loading state so only its button spins.
	let togglingId = $state<number | null>(null);

	const toggleHandler: (accountId: number) => SubmitFunction = (accountId) => () => {
		togglingId = accountId;
		return async ({ update }) => {
			await update(); // success → load reruns → the row's is_active refreshes; failure → form.errors
			togglingId = null;
		};
	};
</script>

<svelte:head>
	<title>{providerLabel(connection.provider)} connection — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<a href="/accounts/connections">Data aggregator connections</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">{providerLabel(connection.provider)}</span>
	</nav>

	<header class="head">
		<div class="title">
			<h1>{providerLabel(connection.provider)} connection</h1>
			<ConnectionStatusChip
				connection_status={connection.connection_status}
				provider={connection.provider}
				is_active={connection.is_active}
			/>
		</div>
		{#if connection.institution_name}
			<p class="subtitle">{connection.institution_name}</p>
		{/if}
		{#if homeUrl}
			<a
				class="provider-home"
				href={homeUrl}
				target="_blank"
				rel="noopener noreferrer"
			>
				Visit {providerLabel(connection.provider)}
				<span aria-hidden="true">↗</span>
				<span class="sr-only">(opens in a new tab)</span>
			</a>
		{/if}
	</header>

	<section class="region" aria-label="Use or ignore accounts">
		<h2 class="section-title">Accounts in this connection</h2>
		<p class="help">
			Choose which accounts from this aggregator to <strong>use</strong>. Ignored accounts are
			hidden from your balances and totals, but their transaction history is kept — you can bring an
			account back into use any time.
		</p>

		{#if form && 'errors' in form && form.errors?._form}
			<p class="form-error" role="alert">{form.errors._form.join(' ')}</p>
		{/if}

		{#if accounts.length === 0}
			<p class="empty">No accounts under this connection yet.</p>
		{:else}
			<ul class="acct-list">
				{#each accounts as a (a.account_id)}
					<li class="acct-row">
						<div class="acct-id">
							<a class="acct-name" href="/accounts/{a.account_id}">{a.name}</a>
							<span class="acct-meta">{accountTypeLabel(a.account_type)}</span>
						</div>
						<div class="acct-control">
							<span class="state" class:ignored={!a.is_active}>
								<span class="sr-only">Current state:</span>
								{a.is_active ? 'In use' : 'Ignored'}
							</span>
							<form
								method="POST"
								action="?/toggleAccount"
								use:enhance={toggleHandler(a.account_id)}
							>
								<input type="hidden" name="account_id" value={a.account_id} />
								<input type="hidden" name="is_active" value={String(!a.is_active)} />
								<Button
									type="submit"
									variant={a.is_active ? 'secondary' : 'primary'}
									loading={togglingId === a.account_id}
								>
									{a.is_active ? `Ignore ${a.name}` : `Use ${a.name}`}
								</Button>
							</form>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
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
	.breadcrumb {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
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
	.subtitle {
		margin: 0;
		color: var(--c-text-secondary);
	}
	.provider-home {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		width: fit-content;
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-link);
		text-decoration: none;
	}
	.provider-home:hover {
		text-decoration: underline;
	}
	.provider-home:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.region {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		box-shadow: var(--shadow-1);
	}
	.section-title {
		margin: 0 0 var(--space-2);
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.help {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		max-width: 44rem;
	}
	.acct-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
	}
	.acct-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-3) 0;
		border-top: 1px solid var(--c-border);
	}
	.acct-row:first-child {
		border-top: none;
	}
	.acct-id {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.acct-name {
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-link);
		text-decoration: none;
		overflow-wrap: anywhere;
	}
	.acct-name:hover {
		text-decoration: underline;
	}
	.acct-name:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.acct-meta {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.acct-control {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		flex-shrink: 0;
	}
	.state {
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
	}
	.state.ignored {
		color: var(--c-text-muted);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
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
	.sr-only {
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
</style>
