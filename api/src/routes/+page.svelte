<!--
	+page.svelte — root dashboard = the §2.1.1 headline Net Worth surface (SELF-211).
	Frontend-owned browser surface. Consumes +page.server.ts's `data` (fn_compute_nav
	via the RLS-scoped server load); authors NO server logic.

	V1.0 Option A (F/CTO-ratified): a SINGLE trustworthy number (PRD §2.1.1 verbatim —
	"a single trustworthy whole-position number"). Number-first single canvas per the
	Phase-2 P2 lock (ADR-013). The GAV/Debt/tax composition table is §2.1.5 = V1.1
	(SELF-225) — deliberately absent here.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
	VALUE-COLOR FENCE (design-system-spec.md §5 fence 1): --c-pos/--c-neg are scoped to
	ACTUAL performance (deltas) ONLY — the NAV headline is a position, not a delta, so a
	negative net worth is NOT rendered red. It shows a minus sign in --c-text-primary.

	Staleness badge (AC#4) is DEFERRED: it needs the per-item staleness primitive (its own
	issue), which does not exist yet. When that lands, the D1 stale-data-marker attaches here.
-->
<script lang="ts">
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	// Whole-dollar USD — the headline reads cleaner without cents. Negative values render
	// a leading minus (in primary ink, per the value-color fence above).
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});

	// asOf is a plain ISO date (YYYY-MM-DD) from the server; anchor it to local midnight
	// so the display date matches the value's as-of date (no timezone off-by-one).
	const asOfLabel = $derived(
		new Date(`${data.asOf}T00:00:00`).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'long',
			day: 'numeric'
		})
	);
</script>

<svelte:head>
	<title>Net Worth · mosko-fintech</title>
</svelte:head>

<main class="dashboard">
	{#if !data.hasAccounts}
		<!-- Empty-state (AC#5): zero active accounts → onboarding CTAs. -->
		<section class="empty" aria-labelledby="empty-title">
			<h1 id="empty-title" class="empty-title">Net Worth</h1>
			<p class="empty-msg">Connect your first account to see your net worth.</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts/connect">Connect an account</a>
				<a class="cta" href="/accounts/new">Add a manual account</a>
			</div>
		</section>
	{:else if data.netWorth === null}
		<!-- Degrade: the compute failed (logged server-side). Never render a wrong number. -->
		<section class="unavailable" aria-labelledby="unavail-title">
			<h1 id="unavail-title" class="nav-label">Net Worth</h1>
			<p class="unavail-msg">Net worth is temporarily unavailable. Please try again shortly.</p>
		</section>
	{:else}
		<!-- The single trustworthy number (AC#1). -->
		<section class="nav-hero" aria-labelledby="nav-label">
			<h1 id="nav-label" class="nav-label">Net Worth</h1>
			<p class="nav-value">{usd.format(data.netWorth)}</p>
			<p class="nav-asof">as of {asOfLabel}</p>
		</section>
	{/if}
</main>

<style>
	.dashboard {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-7) var(--space-5);
	}

	/* ── headline ─────────────────────────────────────────────────────────── */
	.nav-hero {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.nav-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}
	.nav-value {
		margin: 0;
		/* Number-first: the dominant element on the canvas. Tabular mono for numerics. */
		font: var(--weight-bold) var(--fs-hero) / var(--lh-tight) var(--font-num);
		color: var(--c-text-primary);
		font-variant-numeric: tabular-nums;
	}
	.nav-asof {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-muted);
	}

	/* ── unavailable (degrade) ────────────────────────────────────────────── */
	.unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.unavail-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}

	/* ── empty-state ──────────────────────────────────────────────────────── */
	.empty {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		align-items: flex-start;
	}
	.empty-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.empty-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.empty-cta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}

	/* Anchor CTAs styled to the locked `.btn` visual language (Button.svelte renders a
	   <button>, not a link, so nav CTAs style anchors directly — tokens only). */
	.cta {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
	}
	.cta:hover {
		background: var(--c-surface-alt);
	}
	.cta:active {
		background: var(--c-surface-alt2);
	}
	.cta-primary {
		background: var(--c-accent);
		color: var(--c-accent-contrast);
		border-color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	.cta-primary:hover {
		background: var(--c-accent-hover);
		border-color: var(--c-accent-hover);
	}
	.cta-primary:active {
		background: var(--c-accent-active);
		border-color: var(--c-accent-active);
	}
</style>
