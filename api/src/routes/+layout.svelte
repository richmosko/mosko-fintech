<!--
	+layout.svelte — root layout shell (SELF-285).
	Frontend-owned browser surface. Consumes +layout.server.ts's `data`
	(LayoutData { userEmail: string | null }); authors NO server logic.

	Renders an authed header ONLY when a user is signed in (data.userEmail present):
	brand link → /, the signed-in email, a Security link → /settings/security (the MFA
	hub — makes TOTP enrollment/recovery discoverable at GA, not URL-only), and the POST
	sign-out affordance. Sign-out is a plain <form method="POST" action="/auth/signout">
	— state-changing, so never a GET link; matches Backend's POST-only /auth/signout handler.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import '../app.css';
	import favicon from '$lib/assets/favicon.svg';
	import Button from '$lib/components/Button.svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

{#if data.userEmail}
	<header class="app-header">
		<a class="brand" href="/">mosko-fintech</a>
		<div class="account">
			<span class="email">{data.userEmail}</span>
			<a class="nav-link" href="/settings/security">Security</a>
			<form method="POST" action="/auth/signout">
				<Button type="submit">Sign out</Button>
			</form>
		</div>
	</header>
{/if}

{@render children()}

<style>
	.app-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-5);
		background: var(--c-surface);
		border-bottom: 1px solid var(--c-border);
	}
	.brand {
		font: var(--weight-semi) var(--fs-body) / 1 var(--font-ui);
		color: var(--c-text-primary);
		text-decoration: none;
	}
	.account {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.email {
		font: var(--weight-reg) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.nav-link {
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
	}
	.nav-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	/* The sign-out form is layout-transparent — it exists only to carry the POST. */
	.account form {
		margin: 0;
	}
</style>
