<!--
	accounts/connect/+page.svelte — institution-connect onboarding entry (§2.4.1).
	Hosts a provider picker (RF-1 Option A, OQ-2) that routes to the automated-aggregator
	connect widget for the chosen provider — Plaid (SDK modal) or SimpleFIN (paste a Bridge
	setup token) — plus a link to the manual (§2.4.2) path. Pure browser surface: both connect
	flows are client-initiated (fetch to the relay legs), so there is NO +page.server.ts here;
	auth-gating rides the shared hooks.server.ts session chokepoint + the route group's loaders.

	The picker is the ONLY provider knowledge this shell accretes (Option A). Adding a 3rd
	provider = add a radio + a component; if that ever gets painful, promote to a registry
	(Option B) — a data-migration-free refactor, deferred until a 3rd provider forcing function.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import PlaidLinkConnect from '$lib/components/PlaidLinkConnect.svelte';
	import SimpleFINConnect from '$lib/components/SimpleFINConnect.svelte';
	import { stashConnectResult } from '$lib/accounts/connect-handoff.svelte';
	import type { ConnectResult } from '$lib/accounts/account-ref';

	type Provider = 'plaid' | 'simplefin';
	let provider = $state<Provider>('plaid');

	// Client-carries-refs seam (SELF-199 seam (b)): on a successful connect, stash the
	// provider-blind result (AccountRef[] + linked_source_id) into the in-memory handoff and
	// navigate to the attributes-capture route. No server round trip carries this — the
	// attributes route consumes the carry on entry and fail-closes if it is empty.
	const ATTRIBUTES_ROUTE = '/accounts/connect/attributes';
	async function onConnected(result: ConnectResult) {
		stashConnectResult(result);
		await goto(ATTRIBUTES_ROUTE);
	}
</script>

<svelte:head>
	<title>Connect an institution — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">Connect institution</span>
	</nav>

	<h1>Connect an institution</h1>
	<p class="lede">
		Securely link a bank, card, brokerage, or retirement account. You'll sign in at your
		institution and choose which accounts to share — mosko-fintech only ever reads the
		accounts you select, and never sees your institution login.
	</p>

	<section class="region card" aria-labelledby="connect-heading">
		<h2 id="connect-heading">Automatic connection</h2>
		<p class="card-note">
			Recommended for institutions we can sync automatically. After you connect, you'll set
			each account's scope, tax treatment, and type.
		</p>

		<!--
			Provider picker (RF-1 Option A). Native radios in a fieldset give a keyboard-native
			radiogroup (arrow-key navigation, roving focus) for free; the <legend> names the group.
		-->
		<fieldset class="provider-picker">
			<legend>How would you like to connect?</legend>
			<div class="provider-options">
				<label class="provider-option" class:selected={provider === 'plaid'}>
					<input type="radio" name="provider" value="plaid" bind:group={provider} />
					<span class="provider-name">Connect automatically</span>
					<span class="provider-desc">Sign in at your institution through Plaid.</span>
				</label>
				<label class="provider-option" class:selected={provider === 'simplefin'}>
					<input type="radio" name="provider" value="simplefin" bind:group={provider} />
					<span class="provider-name">Connect with SimpleFIN</span>
					<span class="provider-desc">Paste a one-time setup token from the SimpleFIN Bridge.</span>
				</label>
			</div>
		</fieldset>

		{#if provider === 'plaid'}
			<PlaidLinkConnect {onConnected} />
		{:else}
			<SimpleFINConnect {onConnected} />
		{/if}
	</section>

	<section class="region card" aria-labelledby="manual-heading">
		<h2 id="manual-heading">Prefer to add it by hand?</h2>
		<p class="card-note">
			Track an account you'll update manually — no connection required.
		</p>
		<a class="manual-link" href="/accounts/new">Add a manual account</a>
	</section>
</main>

<style>
	.page {
		max-width: 34rem;
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
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		margin-top: var(--space-2);
	}
	h2 {
		margin: 0;
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.card-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.manual-link {
		align-self: flex-start;
		color: var(--c-link);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
	}
	.provider-picker {
		border: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.provider-picker legend {
		padding: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.provider-options {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.provider-option {
		display: grid;
		grid-template-columns: auto 1fr;
		column-gap: var(--space-2);
		row-gap: var(--space-0);
		align-items: baseline;
		padding: var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		cursor: pointer;
	}
	.provider-option:hover {
		border-color: var(--c-border-strong);
	}
	.provider-option.selected {
		border-color: var(--c-accent);
		box-shadow: 0 0 0 1px var(--c-accent);
	}
	.provider-option input {
		grid-row: 1 / span 2;
		align-self: center;
		accent-color: var(--c-accent);
	}
	.provider-name {
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.provider-desc {
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
</style>
