<!--
	accounts/connections/+page.svelte — SELF-207 §2.4.4.b per-account connection-state view.

	Provider-blind. Lists each connected source with its connection health (ConnectionStatusChip),
	last successful sync, and — for re-auth-actionable states (login_required / revoked /
	disconnected, per REAUTH_STATUSES) — a "Re-authenticate" affordance. This is the page the P4
	layout banner's CTA routes to.

	DATA (server-known at render → boring-Svelte loader, not client fetch): consumes
	`data.connections: AccountConnectionState[]` from Backend's `+page.server.ts` load, which reads
	the Architect-authored `043` linked_source_connection_state INVOKER view (RLS-scoped). Scaffolded
	against the AC fields; wired 1:1 when Backend publishes the loader. `last_successful_sync_at` is
	DERIVED server-side from the sync-audit log (ADR-037 OWD-A A3 — no persisted scalar).

	RE-AUTH (LIVE, both providers): the per-connection re-auth affordance is the `ReauthControl`
	component — connect-flow-shaped (NOT a form action), scoped to one source, branching on provider
	(Plaid update-mode Link / SimpleFIN fresh-setup-token re-collect). On success it invalidates the
	loaders so this row + the layout banner refresh to healthy.

	Tokens ONLY (var(--c-*)). a11y: semantic list, chip carries an sr-only status prefix, errors
	role="alert", the re-auth control is keyboard-native. No email/SMS path (AC #5 — in-session only).
-->
<script lang="ts">
	import type { PageData } from './$types';
	import ConnectionStatusChip from '$lib/components/ConnectionStatusChip.svelte';
	import ReauthControl from '$lib/components/ReauthControl.svelte';
	import { needsReauth } from '$lib/schemas/connection-status-constants';

	/** The connection-state row shape — tied to Backend's loader return (anti-drift). `source_id`
	 *  === the account's `linked_source_id` FK (same bigint, different column by role). */
	type AccountConnectionState = PageData['connections'][number];

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
	<title>Connections — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">Connections</span>
	</nav>

	<h1>Connected accounts</h1>
	<p class="lede">
		The institutions you've linked and their current sync status. Re-authenticate any that need
		attention to keep their data up to date.
	</p>

	{#if loadError}
		<p class="form-error" role="alert">
			We couldn't load your connection status. Please refresh the page to try again.
		</p>
	{:else if connections.length === 0}
		<section class="region card empty" aria-labelledby="empty-heading">
			<h2 id="empty-heading">No connected institutions yet</h2>
			<p class="card-note">
				Link a bank, card, or brokerage to sync it automatically — or add an account you'll update
				by hand.
			</p>
			<a class="cta" href="/accounts/connect">Connect an institution</a>
		</section>
	{:else}
		<ul class="conn-list">
			{#each connections as c (c.source_id)}
				<li class="conn-row region card">
					<div class="conn-main">
						<div class="conn-id">
							<span class="conn-name">{c.institution_name || 'Connected institution'}</span>
							<span class="conn-sync">Last synced: {formatSyncTime(c.last_successful_sync_at)}</span>
						</div>
						<ConnectionStatusChip
							connection_status={c.connection_status}
							provider={c.provider}
							is_active={c.is_active}
						/>
					</div>

					{#if c.is_active && needsReauth(c.connection_status)}
						<div class="conn-action">
							<ReauthControl
								source_id={c.source_id}
								provider={c.provider}
								institution_name={c.institution_name}
							/>
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
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.conn-id {
		display: flex;
		flex-direction: column;
		gap: var(--space-0);
		min-width: 0;
	}
	.conn-name {
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.conn-sync {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
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
