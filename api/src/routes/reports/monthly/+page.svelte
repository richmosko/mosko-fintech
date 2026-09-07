<!--
	reports/monthly/+page.svelte — the §2.6.3.b report listing + pending queue + on-demand
	generation surface (SELF-357 / P5). Consumes +page.server.ts's `data` (PageData) and `form`
	(ActionData from `?/generate` / `?/regenerate`) — Backend-surface file, authored by Frontend
	under this ticket's explicit dispatch; authors no server logic itself.

	SECTIONS, per AC 1-4:
	  - Generate control (AC3/AC5/E15 items 9-10): GenerateMonthlyReportControl.svelte — a plain
	    `<form method="POST" action="?/generate">` (no `use:enhance`; the action REDIRECTS on
	    success, so the well-understood no-JS-required pattern is the default winner). JS is
	    used only for that component's own CTA-label reactivity, not the submission itself.
	  - Pending queue (AC2): draft rows awaiting commentary — links into P3's editor. "Pending"
	    is NOT a job-state queue (no queued/in-flight/done, no generation-failed notice — struck
	    at the amendment; this section names months, nothing more).
	  - Generated reports (AC1/AC4/AC7): one row per `final` target_month, linking into P2's
	    view; RegenerateReportControl.svelte per row (E15 item 10 — final-only) — an INLINE
	    two-step confirm, NOT `window.confirm()` (this codebase's own DeleteScheduleControl.svelte
	    convention: a native confirm() blocks all further browser events and breaks browser
	    automation), which is why that control uses `use:enhance` rather than a plain form.
	  - Empty state (AC1, verbatim PM copy) renders in place of the generated list only — the
	    pending queue and generate control are independent of whether any report has ever been
	    generated.
	  - A page-level generic error banner surfaces a `?/generate` or `?/regenerate` FAILURE that
	    isn't RegenerateReportControl's own inline error (e.g. a `?/generate` 400/500) — `form` is
	    the page's single ActionData slot shared by both actions, so this banner does not attempt
	    to attribute which action failed beyond the message itself.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import GenerateMonthlyReportControl from '$lib/components/GenerateMonthlyReportControl.svelte';
	import RegenerateReportControl from '$lib/components/RegenerateReportControl.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const formError = $derived((form as { errors?: { _form?: string[] } } | null)?.errors?._form?.join(' ') ?? '');
</script>

<svelte:head>
	<title>Monthly Reports · mosko-fintech</title>
</svelte:head>

<main class="page">
	<h1 class="page-title">Monthly Reports</h1>

	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}

	<section class="generate-section" aria-labelledby="generate-heading">
		<h2 id="generate-heading">Generate a report</h2>
		<GenerateMonthlyReportControl candidates={data.candidates} />
	</section>

	{#if data.pending.length > 0}
		<section class="pending-section" aria-labelledby="pending-heading">
			<h2 id="pending-heading">Pending — awaiting commentary</h2>
			<ul class="pending-list">
				{#each data.pending as p (p.reportId)}
					<li>
						<a href={`/reports/monthly/${p.targetMonth.slice(0, 7)}/commentary`}>
							{p.monthLabel} — write commentary
						</a>
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	<section class="listing-section" aria-labelledby="listing-heading">
		<h2 id="listing-heading">Generated reports</h2>
		{#if data.generated.length === 0}
			<p class="empty-msg">
				No monthly reports yet. Your first report is generated on the 1st of next month, or
				generate one now.
			</p>
		{:else}
			<ul class="report-list">
				{#each data.generated as r (r.reportId)}
					<li class="report-row">
						<a href={`/reports/monthly/${r.targetMonth.slice(0, 7)}`}>{r.monthLabel}</a>
						<RegenerateReportControl targetMonth={r.targetMonth} monthLabel={r.monthLabel} />
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</main>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		max-width: 800px;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		box-sizing: border-box;
	}
	.page-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	h2 {
		margin: 0 0 var(--space-3) 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.generate-section,
	.pending-section,
	.listing-section {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.empty-msg {
		margin: 0;
		color: var(--c-text-secondary);
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
	}
	.pending-list,
	.report-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.report-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-2) 0;
		border-bottom: 1px solid var(--c-border);
	}
	.report-row:last-child {
		border-bottom: none;
	}
	.pending-list a,
	.report-row a {
		color: var(--c-accent);
		font: var(--weight-med) var(--fs-body) / var(--lh-body) var(--font-ui);
		text-decoration: none;
	}
	.pending-list a:hover,
	.report-row a:hover {
		text-decoration: underline;
	}
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		color: var(--c-neg);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
</style>
