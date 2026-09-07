<!--
	SkipFinalizeControl.svelte — the P4 (SELF-356 AC1/AC3/AC5) "Skip commentary and finalize"
	secondary CTA on a pending report's own list item. Posts to the parent route's `?/skip` form
	action (reports/monthly/+page.server.ts's own new action, a Backend-surface file authored under
	this ticket's dispatch) — calls migration 115 (pfin.fn_finalize_monthly_report) with the
	`'skipped'` disposition, the ONE user-reachable path that writes that durable fact.

	INLINE, NOT window.confirm() — same convention DeleteScheduleControl.svelte / P5's own
	RegenerateReportControl.svelte already established: a native `confirm()` dialog blocks all
	further browser events and breaks browser automation. Two-step disclosure instead: a "Skip
	commentary and finalize" link-button reveals an inline confirm row; nothing is written until
	the second click.

	CONFIRM COPY (PM, verbatim — AC3): "Finalize {Month YYYY} without commentary? The Rebalancing
	Targets section will show its four headings with empty bodies. You can regenerate this month
	later."

	On success the action REDIRECTS into P2's final view for the newly-finalized month —
	`use:enhance`'s default `update()` call follows a redirect ActionResult the same as it applies
	a success/failure one (RegenerateReportControl's own documented posture), so no special-casing
	is needed here beyond calling it unconditionally.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import Button from '$lib/components/Button.svelte';

	let { targetMonth, monthLabel }: { targetMonth: string; monthLabel: string } = $props();

	let confirming = $state(false);
	let finalizing = $state(false);
	let errorMessage = $state('');

	type SkipFailure = { errors: Record<string, string[]> };

	const handleSkip: SubmitFunction = () => {
		finalizing = true;
		errorMessage = '';
		return async ({ result, update }) => {
			finalizing = false;
			if (result.type === 'failure') {
				const data = result.data as SkipFailure | undefined;
				const messages = Object.values(data?.errors ?? {}).flat();
				errorMessage =
					messages.length > 0 ? messages.join(' ') : 'Could not finalize this report. Please try again.';
			} else if (result.type === 'error') {
				errorMessage = 'Something went wrong. Please try again.';
			}
			await update();
		};
	};
</script>

{#if confirming}
	<div class="confirm-row">
		<span class="confirm-text">
			Finalize {monthLabel} without commentary? The Rebalancing Targets section will show its
			four headings with empty bodies. You can regenerate this month later.
		</span>
		<form method="POST" action="?/skip" use:enhance={handleSkip}>
			<input type="hidden" name="target_month" value={targetMonth} />
			<Button variant="primary" type="submit" loading={finalizing}>Yes, finalize</Button>
		</form>
		<Button variant="secondary" type="button" onclick={() => (confirming = false)} disabled={finalizing}>
			Cancel
		</Button>
	</div>
{:else}
	<Button
		variant="link"
		type="button"
		onclick={() => (confirming = true)}
		aria-label={`Skip commentary and finalize ${monthLabel}`}
	>
		Skip commentary and finalize
	</Button>
{/if}
{#if errorMessage}
	<p class="skip-error" role="alert">{errorMessage}</p>
{/if}

<style>
	.confirm-row {
		display: inline-flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.confirm-text {
		font: var(--weight-med) var(--fs-small) / 1.3 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.confirm-row form {
		margin: 0;
	}
	.skip-error {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-neg);
	}
</style>
