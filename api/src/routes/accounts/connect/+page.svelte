<!--
	accounts/connect/+page.svelte — institution-connect onboarding entry (SELF-198 §2.4.1).
	Hosts the Plaid Link connect widget (automated-aggregator path) and links to the
	manual (§2.4.2) path as the alternative. Pure browser surface — the Plaid flow is
	client-initiated (fetch to the SELF-197 relay legs), so there is NO +page.server.ts
	here; auth-gating rides the shared hooks.server.ts session chokepoint + the route
	group's existing loaders.

	DRAFT (SELF-198): builds against the assumed SELF-197 relay contract; do not ship
	until leg-1/leg-2 land and the C6 gate clears.
-->
<script lang="ts">
	import PlaidLinkConnect from '$lib/components/PlaidLinkConnect.svelte';
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
		<PlaidLinkConnect />
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
</style>
