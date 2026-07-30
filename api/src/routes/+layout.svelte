<!--
	+layout.svelte — root layout shell (SELF-285).
	Frontend-owned browser surface. Consumes +layout.server.ts's `data`
	(LayoutData { userEmail: string | null }); authors NO server logic.

	Renders an authed header ONLY when a user is signed in (data.userEmail present):
	brand link → /, a Classify link carrying the SELF-200 pending-symbol count badge
	(zero footprint when the count is 0), the signed-in email, a Security link →
	/settings/security (the MFA hub — makes TOTP enrollment/recovery discoverable at GA, not
	URL-only), and the POST sign-out affordance. Sign-out is a plain
	<form method="POST" action="/auth/signout"> — state-changing, so never a GET link; matches
	Backend's POST-only /auth/signout handler.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). The count badge uses the
	ACCENT ramp — NOT `--c-attn-*` (canary is reserved for staleness/re-auth; §5 fence).
-->
<script lang="ts">
	import '../app.css';
	import favicon from '$lib/assets/favicon.svg';
	import Button from '$lib/components/Button.svelte';
	import CountBadge from '$lib/components/CountBadge.svelte';
	import ReauthStalenessBanner from '$lib/components/ReauthStalenessBanner.svelte';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// SELF-207 P4 re-auth banner health summary — from +layout.server.ts (Backend-computed via the
	// shared needsReauth/isInstitutionDown predicates, active-connections-only, fail-soft to {0,0}).
	// {0,0} → the banner renders nothing (zero-footprint fence 3).
	const connectionHealth = $derived(data.connectionHealth);
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

{#if data.userEmail}
	<header class="app-header">
		<a class="brand" href="/">mosko-fintech</a>
		<div class="account">
			{#if data.pendingClassificationCount > 0}
				<a
					class="nav-link classify-link"
					href="/portfolio/classify"
					aria-label="Classify securities — {data.pendingClassificationCount} pending"
				>
					Classify
					<CountBadge count={data.pendingClassificationCount} />
				</a>
			{/if}
			<span class="email">{data.userEmail}</span>
			<a class="nav-link" href="/settings/security">Security</a>
			<form method="POST" action="/auth/signout">
				<Button type="submit">Sign out</Button>
			</form>
		</div>
	</header>

	<!-- P4 re-auth banner (SELF-207): full-width, persistent, non-dismissible; zero footprint
	     when healthy. Sits directly below the app header so it is the first thing seen on any page
	     when a connection needs attention. -->
	<ReauthStalenessBanner
		reauthCount={connectionHealth.reauthCount}
		institutionDownCount={connectionHealth.institutionDownCount}
	/>
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
	/* Keyboard focus visibility — explicit ring on the nav links (the small radius gives the
	   box-shadow ring rounded corners on these inline links). */
	.nav-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	/* The Classify link keeps its badge on the baseline and never underlines the pill. */
	.classify-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
	}
	.classify-link:hover {
		text-decoration: none;
	}
	.classify-link:hover :global(.count-badge) {
		background: var(--c-accent-hover);
	}
	/* The sign-out form is layout-transparent — it exists only to carry the POST. */
	.account form {
		margin: 0;
	}
</style>
