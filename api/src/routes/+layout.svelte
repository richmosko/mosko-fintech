<!--
	+layout.svelte — root layout shell (SELF-285).
	Frontend-owned browser surface. Consumes +layout.server.ts's `data`
	(LayoutData { userEmail: string | null }); authors NO server logic.

	Renders an authed header ONLY when a user is signed in (data.userEmail present):
	brand link → /, primary nav (Net Worth / Accounts / Allocation — the latter added SELF-239 —
	/ Cash Flow / Taxes — the latter added SELF-264, §2.5.1's own route; a primary-nav entry, not
	a /settings rail entry, since §2.5 is a read surface like Allocation/Cash Flow, not a
	planning-value editor — see settings/+layout.svelte's own header for that shell's scope),
	a Classify link carrying the SELF-200 pending-symbol count badge
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
	import { page } from '$app/state';
	import type { LayoutData } from './$types';

	let { data, children }: { data: LayoutData; children: import('svelte').Snippet } = $props();

	// Primary-nav active state. Net Worth is the root; Accounts owns the whole /accounts/* subtree.
	// Allocation added at SELF-239 (the §2.2.2 table's own route, distinct from the
	// /settings/allocation %Target editor). Cash Flow added at SELF-251 (the §2.3.2.b
	// cross-account rollup's own route, `/cash-flow` per SELF-252 AC8). Taxes added at SELF-264
	// (the §2.5.1 decomposition table's own route, `/taxes/decomposition`) — owns the whole
	// /taxes/* subtree so later §2.5.2/§2.5.3/§2.5.4 sibling routes stay under this one nav entry.
	// Only the surfaces that exist today are linked — the rest of the locked app-sidebar (Monthly
	// Report / Settings) lands as those V1.x surfaces are built.
	const path = $derived(page.url.pathname);
	const isNetWorth = $derived(path === '/');
	const isAccounts = $derived(path === '/accounts' || path.startsWith('/accounts/'));
	const isAllocation = $derived(path === '/allocation');
	const isCashFlow = $derived(path === '/cash-flow');
	// No bare `/taxes` index route exists (only `/taxes/decomposition` / `/taxes/quarterly`), so
	// `path === '/taxes'` is unreachable per SvelteKit's own generated route-id union — that
	// comparison was a svelte-check ERROR (no type overlap), not a lint nit. `startsWith` alone
	// covers every real /taxes/* route.
	const isTaxes = $derived(path.startsWith('/taxes/'));

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
		<div class="header-left">
			<a class="brand" href="/">mosko-fintech</a>
			<nav class="primary-nav" aria-label="Primary">
				<a class="nav-link" href="/" aria-current={isNetWorth ? 'page' : undefined}>Net Worth</a>
				<a class="nav-link" href="/accounts" aria-current={isAccounts ? 'page' : undefined}>
					Accounts
				</a>
				<a class="nav-link" href="/allocation" aria-current={isAllocation ? 'page' : undefined}>
					Allocation
				</a>
				<a class="nav-link" href="/cash-flow" aria-current={isCashFlow ? 'page' : undefined}>
					Cash Flow
				</a>
				<a
					class="nav-link"
					href="/taxes/decomposition"
					aria-current={isTaxes ? 'page' : undefined}
				>
					Taxes
				</a>
			</nav>
		</div>
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
	.header-left {
		display: flex;
		align-items: center;
		gap: var(--space-4);
	}
	.brand {
		font: var(--weight-semi) var(--fs-body) / 1 var(--font-ui);
		color: var(--c-text-primary);
		text-decoration: none;
	}
	.primary-nav {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	/* The current surface reads as active — heavier weight + primary ink, no underline. */
	.primary-nav .nav-link[aria-current='page'] {
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	.primary-nav .nav-link[aria-current='page']:hover {
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
