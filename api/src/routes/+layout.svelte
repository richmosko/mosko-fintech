<!--
	+layout.svelte — root layout shell (SELF-285).
	Frontend-owned browser surface. Consumes +layout.server.ts's `data`
	(LayoutData { userEmail: string | null }); authors NO server logic.

	Renders an authed header ONLY when a user is signed in (data.userEmail present):
	brand link → /, primary nav (Net Worth / Accounts / Allocation — the latter added SELF-239),
	a Classify link carrying the SELF-200 pending-symbol count badge
	(zero footprint when the count is 0), the signed-in email, a Security link →
	/settings/security (the MFA hub — makes TOTP enrollment/recovery discoverable at GA, not
	URL-only), and the POST sign-out affordance. Sign-out is a plain
	<form method="POST" action="/auth/signout"> — state-changing, so never a GET link; matches
	Backend's POST-only /auth/signout handler.

	"Taxes" added at SELF-266 → /taxes/quarterly (the first §2.5 surface to land; team-lead ruling —
	renamed from the original "Est. Taxes" draft), active-matched on the /taxes/ subtree via
	`path.startsWith('/taxes/')` (WITH the trailing slash — `path === '/taxes'` is a svelte-check
	type error, since no bare /taxes route exists; frontend-264 found this on its own now-reverted
	nav hunk) so it stays highlighted once SELF-264's /taxes/decomposition lands alongside it. This
	is now the ONE nav edit for both §2.5 surfaces — frontend-264 reverted its own.

	"Monthly Report" — RECONCILED at the P2/P3/P5 rebase-integration (2026-09-05) from two
	independent additions built on separate branches (P2's own bare link, P5's badge-carrying
	one; see each ticket's own commit for the individual history). Added at SELF-354 (P2 AC1's
	"sidebar entry owed" note) → /reports/monthly, active-matched on the WHOLE /reports/monthly
	subtree (WITH the trailing-slash-or-exact form, same `/taxes/` rationale — covers P2's
	per-month view and P3's commentary editor under it, not just P5's listing itself). Carries
	the SAME pending-count badge treatment the Classify link established (SELF-200, P5's own
	AC2) — zero footprint when `pendingMonthlyReportCount` is 0, ACCENT ramp (not `--c-attn-*`),
	sourced from +layout.server.ts's own tenant-scoped read (AC2's Sec F-8).

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
	// cross-account rollup's own route, `/cash-flow` per SELF-252 AC8). Taxes added at SELF-266
	// (owns the whole /taxes/* subtree — see the module header). Only the surfaces that exist today
	// are linked — the rest of the locked app-sidebar (Monthly Report / Settings) lands as those
	// V1.x surfaces are built.
	const path = $derived(page.url.pathname);
	const isNetWorth = $derived(path === '/');
	const isAccounts = $derived(path === '/accounts' || path.startsWith('/accounts/'));
	const isAllocation = $derived(path === '/allocation');
	const isCashFlow = $derived(path === '/cash-flow');
	const isTaxes = $derived(path.startsWith('/taxes/'));
	const isMonthlyReport = $derived(path.startsWith('/reports/monthly/') || path === '/reports/monthly');

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
				<a class="nav-link" href="/taxes/quarterly" aria-current={isTaxes ? 'page' : undefined}>
					Taxes
				</a>
				<a
					class="nav-link monthly-report-link"
					href="/reports/monthly"
					aria-current={isMonthlyReport ? 'page' : undefined}
					aria-label={data.pendingMonthlyReportCount > 0
						? `Monthly Report — ${data.pendingMonthlyReportCount} pending`
						: undefined}
				>
					Monthly Report
					{#if data.pendingMonthlyReportCount > 0}
						<CountBadge count={data.pendingMonthlyReportCount} />
					{/if}
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
	/* The Monthly Report nav link's pending-count badge — same treatment as the Classify link's
	   own badge below (SELF-200 precedent), applied inside .primary-nav instead of .account. */
	.monthly-report-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
	}
	.monthly-report-link:hover {
		text-decoration: none;
	}
	.monthly-report-link:hover :global(.count-badge) {
		background: var(--c-accent-hover);
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
