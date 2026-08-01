<!--
	accounts/connections/+page.svelte — connections-redesign aggregator-connection list
	(SELF-207 §2.4.4.b, redesigned). Frontend-owned browser surface.

	The page is organised by DATA AGGREGATOR CONNECTION, not by account. Each card leads with the
	provider (Plaid / SimpleFIN) — the connection's identity is its provider (a system value, not a
	user nickname). The provider name is the click target to the per-connection use/ignore edit page
	(`/accounts/connections/{source_id}`); a small external "↗" links out to the provider's public
	home page (new tab). institution_name is a secondary detail line, not the primary label. Under
	each connection: an indented list of its accounts (each → Account Detail), with an "Ignored"
	marker for inactive (ignored) accounts.

	DATA (server-known at render → boring-Svelte loader, not client fetch): consumes
	`data.connections: ConnectionWithAccounts[]` from Backend's `+page.server.ts` load — each row is
	a ConnectionState PLUS `accounts` (active AND inactive; management view, not NAV).
	`last_successful_sync_at` is DERIVED server-side (ADR-037). Keeps the `ConnectionStatusChip` +
	last-synced + `SyncNowControl`, and the per-connection `ReauthControl` for re-auth-actionable states.

	Tokens ONLY (var(--c-*)). a11y: semantic lists, chip carries an sr-only status prefix, the
	external link names itself + "opens in a new tab", errors role="alert", controls keyboard-native.
-->
<script lang="ts">
	import type { PageData } from './$types';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import ReauthControl from '$lib/components/ReauthControl.svelte';
	import SyncNowControl from '$lib/components/SyncNowControl.svelte';
	import { needsReauth } from '$lib/schemas/connection-status-constants';
	import { providerLabel, providerHomeUrl } from '$lib/accounts/connection-display';

	let { data }: { data: PageData } = $props();

	// `error` distinguishes a read failure (retriable message) from a true-empty (empty state).
	const connections = $derived(data.connections);
	const loadError = $derived(data.error);

	function formatSyncTime(iso: string | null): string {
		if (!iso) return 'Never synced';
		const d = new Date(iso);
		if (Number.isNaN(d.getTime())) return '—';
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(d);
	}
</script>

<svelte:head>
	<title>Data aggregator connections — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">Data aggregator connections</span>
	</nav>

	<h1>Data aggregator connections</h1>
	<p class="lede">
		The data aggregators you've linked — one entry per connection, not per account. Open a
		connection to choose which of its accounts to use or ignore, or re-authenticate any that need
		attention to keep their data up to date.
	</p>

	{#if loadError}
		<p class="form-error" role="alert">
			We couldn't load your connection status. Please refresh the page to try again.
		</p>
	{:else if connections.length === 0}
		<section class="region card empty" aria-labelledby="empty-heading">
			<h2 id="empty-heading">No connected aggregators yet</h2>
			<p class="card-note">
				Link a bank, card, or brokerage through an aggregator to sync it automatically — or add an
				account you'll update by hand.
			</p>
			<a class="cta" href="/accounts/connect">Connect an institution</a>
		</section>
	{:else}
		<ul class="conn-list">
			{#each connections as c (c.source_id)}
				{@const homeUrl = providerHomeUrl(c.provider)}
				<li class="conn-row region card">
					<div class="conn-main">
						<div class="conn-id">
							<div class="conn-name-row">
								<a
									class="conn-name"
									href="/accounts/connections/{c.source_id}"
									aria-label="Manage {providerLabel(c.provider)} connection accounts"
								>
									{providerLabel(c.provider)}
								</a>
								{#if homeUrl}
									<a
										class="provider-home"
										href={homeUrl}
										target="_blank"
										rel="noopener noreferrer"
										aria-label="Open the {providerLabel(c.provider)} home page (opens in a new tab)"
									>
										<span aria-hidden="true">↗</span>
									</a>
								{/if}
							</div>
							{#if c.institution_name}
								<span class="conn-inst">{c.institution_name}</span>
							{/if}
							<span class="conn-sync">Last synced: {formatSyncTime(c.last_successful_sync_at)}</span>
						</div>
						<ConnectionStatusChip
							connection_status={c.connection_status}
							provider={c.provider}
							is_active={c.is_active}
						/>
					</div>

					{#if c.accounts.length > 0}
						<ul class="acct-sublist" aria-label="Accounts under this connection">
							{#each c.accounts as a (a.account_id)}
								<li class="acct-subrow">
									<a class="acct-sublink" href="/accounts/{a.account_id}">{a.name}</a>
									{#if !a.is_active}
										<span class="ignored-marker">Ignored</span>
									{/if}
								</li>
							{/each}
						</ul>
					{:else}
						<p class="acct-empty">No accounts under this connection yet.</p>
					{/if}

					{#if c.is_active}
						<div class="conn-action">
							<SyncNowControl
								source_id={c.source_id}
								institution_name={c.institution_name}
								lastSyncedAt={c.last_successful_sync_at}
							/>
							{#if needsReauth(c.connection_status)}
								<ReauthControl
									source_id={c.source_id}
									provider={c.provider}
									institution_name={c.institution_name}
								/>
							{/if}
						</div>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</main>

<style>
	.page {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
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
	h1 {
		margin: 0;
		font-size: var(--fs-h1);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-text-primary);
	}
	.lede {
		margin: 0;
		color: var(--c-text-secondary);
	}
	.card {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-5);
		box-shadow: var(--shadow-1);
	}
	.card h2 {
		margin: 0 0 var(--space-2);
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.card-note {
		margin: 0 0 var(--space-3);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.empty {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
	}
	.cta {
		color: var(--c-link);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
	}
	.conn-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.conn-row {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.conn-main {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.conn-id {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.conn-name-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.conn-name {
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-link);
		text-decoration: none;
	}
	.conn-name:hover {
		text-decoration: underline;
	}
	.conn-name:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.provider-home {
		display: inline-flex;
		align-items: center;
		color: var(--c-text-muted);
		text-decoration: none;
		font-size: var(--fs-small);
		line-height: 1;
	}
	.provider-home:hover {
		color: var(--c-link);
	}
	.provider-home:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.conn-inst {
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.conn-sync {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.acct-sublist {
		list-style: none;
		margin: 0;
		padding: 0 0 0 var(--space-4);
		border-left: 1px solid var(--c-border);
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.acct-subrow {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}
	.acct-sublink {
		font-size: var(--fs-small);
		color: var(--c-link);
		text-decoration: none;
	}
	.acct-sublink:hover {
		text-decoration: underline;
	}
	.acct-sublink:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.ignored-marker {
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-muted);
		border: 1px dashed var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: 0 var(--space-2);
	}
	.acct-empty {
		margin: 0 0 0 var(--space-4);
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		font-style: italic;
	}
	.conn-action {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
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
