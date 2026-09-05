<!--
	RegenerateReportControl.svelte — inline-confirm regenerate control for a `final`
	pfin.monthly_report row (SELF-357 / P5, E15 item 10). Posts to the parent route's
	`?/regenerate` form action (reports/monthly/+page.server.ts, a Backend-surface file
	authored under this ticket's dispatch) — calls migration 114
	(pfin.fn_regenerate_monthly_report), the only user-reachable `final -> superseded` path.

	INLINE, NOT window.confirm() — same convention DeleteScheduleControl.svelte already
	established (SELF-265): a native `confirm()` dialog blocks all further browser events and
	breaks browser automation. Two-step disclosure instead: a "Regenerate" link-button reveals
	an inline confirm row; nothing is written until the second click.

	CONFIRM COPY (PM, verbatim — AC4): "Regenerate {Month YYYY}? The current report is
	replaced; your existing commentary is loaded into the editor to edit or keep."

	This control renders ONLY on a `final` row's own listing entry (E15 item 10 — Regenerate is
	a final-only affordance; a `draft` month's affordances are P4's "Write commentary" /
	"Skip commentary and finalize", not this control). On success the action REDIRECTS into
	P3's commentary editor for the new draft — `use:enhance`'s default `update()` call follows a
	redirect ActionResult the same as it applies a success/failure one, so no special-casing is
	needed here beyond calling it unconditionally.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import Button from '$lib/components/Button.svelte';

	let { targetMonth, monthLabel }: { targetMonth: string; monthLabel: string } = $props();

	let confirming = $state(false);
	let regenerating = $state(false);
	let errorMessage = $state('');

	type RegenerateFailure = { errors: Record<string, string[]> };

	const handleRegenerate: SubmitFunction = () => {
		regenerating = true;
		errorMessage = '';
		return async ({ result, update }) => {
			regenerating = false;
			if (result.type === 'failure') {
				const data = result.data as RegenerateFailure | undefined;
				const messages = Object.values(data?.errors ?? {}).flat();
				errorMessage = messages.length > 0 ? messages.join(' ') : 'Could not regenerate this report. Please try again.';
			} else if (result.type === 'error') {
				errorMessage = 'Something went wrong. Please try again.';
			}
			// Default apply: follows the redirect on success, or re-renders with `form` set on
			// failure — same call, every branch, mirroring DeleteScheduleControl's own convention.
			await update();
		};
	};
</script>

{#if confirming}
	<div class="confirm-row">
		<span class="confirm-text">
			Regenerate {monthLabel}? The current report is replaced; your existing commentary is
			loaded into the editor to edit or keep.
		</span>
		<form method="POST" action="?/regenerate" use:enhance={handleRegenerate}>
			<input type="hidden" name="target_month" value={targetMonth} />
			<Button variant="primary" type="submit" loading={regenerating}>Yes, regenerate</Button>
		</form>
		<Button
			variant="secondary"
			type="button"
			onclick={() => (confirming = false)}
			disabled={regenerating}
		>
			Cancel
		</Button>
	</div>
{:else}
	<Button
		variant="link"
		type="button"
		onclick={() => (confirming = true)}
		aria-label={`Regenerate ${monthLabel}`}
	>
		Regenerate
	</Button>
{/if}
{#if errorMessage}
	<p class="regen-error" role="alert">{errorMessage}</p>
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
	.regen-error {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-neg);
	}
</style>
