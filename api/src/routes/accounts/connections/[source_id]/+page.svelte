<!--
	accounts/connections/[source_id]/+page.svelte — connections-redesign per-connection view.
	Frontend-owned browser surface. Consumes Backend's `[source_id]/+page.server.ts`:
	load → { connection: ConnectionState, accounts: ConnectionAccount[] }.

	The page titles the provider + connection and lists every account under it. READ-ONLY: the
	per-row "Use / Ignore" control was REMOVED per ADR-042 Decision 1b — a control whose two
	positions are "In use" and "Ignored" persists exactly the selection state concept 3 says must
	not exist, and it is deliberately NOT re-pointed onto `closed_at` (*ignored* and *closed* are
	different facts). Import selection lives at connect time; closing is done from the account's
	own control at `accounts/[account_id]`.

	Accepted cost, per Decision 1b: someone who closes an account by mistake has no path back from
	here and must find the account itself. Preferred over a second close control, or a reopen prompt
	inside a flow about connecting rather than about bookkeeping.

	Tokens ONLY (var(--c-*)). a11y: semantic list, keyboard-native. No secrets, no server imports.
--><script lang="ts">
	import type { PageData } from './$types';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import { accountTypeLabel, closedAtLabel } from '$lib/account-display';
	import { providerLabel, providerHomeUrl } from '$lib/accounts/connection-display';

	let { data }: { data: PageData } = $props();

	const connection = $derived(data.connection);
	const accounts = $derived(data.accounts);
	const homeUrl = $derived(providerHomeUrl(connection.provider));
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

	<!--
		The accessible name is "Accounts in this connection", matching this section's own <h2>.
		It read "Use or ignore accounts" until now — the name of a control REMOVED at `496c405`
		(ADR-042 Decision 1b). The file's header comment correctly said the page was read-only, so
		a sighted reader of either the page or the source was fine; the ACCESSIBLE NAME was the one
		surface still announcing the removed control, telling a screen-reader user the section does
		something everyone else can see it does not. A stale comment misleads a developer; a stale
		accessible name misleads a user, and only one class of user.
	-->
	<section class="region" aria-label="Accounts in this connection">
		<h2 class="section-title">Accounts in this connection</h2>
		<p class="help">
			Every account imported from this aggregator. Which accounts get imported is chosen when you
			connect. To close an account, open it and use its close control.
		</p>

		{#if accounts.length === 0}
			<p class="empty">No accounts under this connection yet.</p>
		{:else}
			<ul class="acct-list">
				{#each accounts as a (a.account_id)}
					<li class="acct-row">
						<div class="acct-id">
							<a class="acct-name" href="/accounts/{a.account_id}">{a.name}</a>
							<!--
								`a.closed_at` — the ACCOUNT column. `loadAccountsForSource` has always mapped
								it into `ConnectionAccount`; this template simply ignored it, so the SAME
								account read as open here and as closed-with-a-date on the accounts hub.
								One account, two truths, decided by the route you arrived through.

								"Closed account", not bare "Closed" — pm-copy's asymmetric-cost ruling, and
								it binds harder on this page than on the parent list: a `ConnectionStatusChip`
								sits directly above in the header, so a bare "Closed" invites reading the
								CONNECTION as closed and sends the user off to re-link something that is fine.

								Guarded on `a.closed_at`, NOT on `closedAtLabel(...)` being non-empty — the
								helper returns '' for null, and leaning on that would make the render depend
								on a formatter's null-handling rather than on the fact itself.
							-->
							<span class="acct-meta">
								{accountTypeLabel(a.account_type)}
								{#if a.closed_at}
									<span class="acct-closed">· Closed account · {closedAtLabel(a.closed_at)}</span>
								{/if}
							</span>
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
	/* No `justify-content: space-between` — it was residue from the per-row use/ignore control
	   removed at `496c405`, and with a single child it did nothing. Removed rather than left,
	   because a space-between with one child reads as "an element is missing here". */
	.acct-row {
		display: flex;
		align-items: center;
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
	/* Same muted register as the rest of the meta line — closure is a bookkeeping state, not an
	   error, so no --c-neg (the page's standing value-color fence). */
	.acct-closed {
		color: var(--c-text-muted);
	}
	.empty {
		margin: 0;
		color: var(--c-text-muted);
		font-style: italic;
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
