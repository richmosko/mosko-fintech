<!--
	GenerateMonthlyReportControl.svelte — the §2.6.3.b target-month selector + on-demand
	generation CTA (SELF-357 / P5 AC3, E15 items 9-10). Posts to the parent route's own
	`?/generate` form action (+page.server.ts, a Backend-surface file authored under this
	ticket's dispatch).

	EXACTLY TWO CANDIDATES (AC3): the prior month (default-selected) and the current
	month-in-progress, both computed SERVER-SIDE (`serverTodayAsOf()`) and passed in as props —
	this component never computes "today" itself. The `<select>` IS the "target-month selection"
	AC3 names; the CTA button's label reacts to the selected option's own server-computed
	`state`, using data already loaded (no round trip needed to know whether the selected month
	already has a draft):
	  - state 'none'  → "Generate monthly report" (AC1's empty-state CTA copy, reused verbatim)
	  - state 'draft' → "Continue {Month YYYY}" (E15 item 9 — this OPENS the existing draft, the
	                    RPC never produces a second one; no confirmation dialog, verbatim)
	  - state 'final' → the button is disabled with an explanatory note; Regenerate is a
	                    DIFFERENT affordance that lives on the listing's own row for that month
	                    (E15 item 10 — Regenerate is `final`-only and is not this control's job)

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import Button from '$lib/components/Button.svelte';

	type CandidateState = 'none' | 'draft' | 'final';
	type Candidate = { targetMonth: string; label: string; plainLabel: string; state: CandidateState };

	let { candidates }: { candidates: Candidate[] } = $props();

	// ONE-TIME capture of the default selection — correct by construction, same posture
	// CashflowTargetEditor.svelte / TaxBracketScheduleEditor.svelte already document for their
	// own `$state` initializers: this component has no remount-with-changed-`candidates` concern
	// (one instance per page load; `candidates` is fixed for the life of the mount). The
	// svelte-check `state_referenced_locally` warning here is EXPECTED and safe, not a residual
	// smell to silence.
	let selected = $state(candidates[0]?.targetMonth ?? '');

	const current = $derived(candidates.find((c) => c.targetMonth === selected) ?? candidates[0]);

	const ctaLabel = $derived(
		current?.state === 'draft' ? `Continue ${current.plainLabel}` : 'Generate monthly report'
	);
	const ctaDisabled = $derived(!current || current.state === 'final');
</script>

<form class="generate-control" method="POST" action="?/generate">
	<label class="select-label" for="target-month-select">Target month</label>
	<select id="target-month-select" name="target_month" bind:value={selected}>
		{#each candidates as c (c.targetMonth)}
			<option value={c.targetMonth}>{c.label}</option>
		{/each}
	</select>
	{#if current?.state === 'final'}
		<p class="hint">
			{current.plainLabel} is already generated. Use Regenerate on that report below to replace it.
		</p>
	{/if}
	<Button variant="primary" type="submit" disabled={ctaDisabled}>{ctaLabel}</Button>
</form>

<style>
	.generate-control {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-3);
	}
	.select-label {
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	select {
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-primary);
		background: var(--c-surface);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
	}
	select:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.hint {
		margin: 0;
		flex-basis: 100%;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
</style>
