<!--
	DeleteScheduleControl.svelte -- inline-confirm delete control for a `pfin.tax_bracket_schedule`
	row (SELF-265). Frontend-owned browser surface. Posts to the `?/deleteSchedule` form action
	(api/src/routes/settings/tax-brackets/+page.server.ts, Backend-owned) — cascade removes the
	schedule's `tax_bracket_row` set (migration 101 ON DELETE CASCADE).

	INLINE, NOT window.confirm() -- per this issue's own brief: a native confirm() dialog blocks
	all further browser events and breaks browser automation. Two-step disclosure instead: a
	"Delete" link-button reveals an inline "Delete <item>? Yes, delete / Cancel" row; nothing is
	destructive until the second click.

	IDEMPOTENT-DELETE CONTRACT (the action's own header): the action always returns 200-shaped
	success with a `deleted: boolean` disclosure rather than a 404/409 -- `deleted: false` covers
	both "already gone" and "exists but hidden below aal2" indistinguishably, by design. This
	control does not attempt to tell those apart either; it reports what the action reports.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import Button from '$lib/components/Button.svelte';

	let { scheduleId, itemLabel }: { scheduleId: number; itemLabel: string } = $props();

	let confirming = $state(false);
	let deleting = $state(false);
	let resultMessage = $state('');

	type DeleteFailure = { action: 'deleteSchedule'; errors: Record<string, string[]> };

	const handleDelete: SubmitFunction = () => {
		deleting = true;
		resultMessage = '';
		return async ({ result, update }) => {
			deleting = false;
			confirming = false;

			if (result.type === 'success' && result.data && (result.data as { deleted?: boolean }).deleted === false) {
				resultMessage = 'Not removed — refresh to confirm its current state.';
			} else if (result.type === 'failure') {
				// Sec F-3: the action's own 409 refusal (e.g. E38's seed-template guard, reachable
				// even when this control's OWN fail-open `is_seed_template` gate is stale from a
				// transient loader failure — the server is the actual boundary either way) was
				// previously swallowed here: neither this component nor +page.svelte/List reads
				// the page's shared `form` prop, so nothing ever rendered `errors._form`. Every
				// message across every field, joined, since this control has no per-field UI of
				// its own to attach them to individually.
				const data = result.data as DeleteFailure | undefined;
				const messages = Object.values(data?.errors ?? {}).flat();
				resultMessage =
					messages.length > 0 ? messages.join(' ') : 'Could not delete this schedule. Please try again.';
			} else if (result.type === 'error') {
				resultMessage = 'Something went wrong. Please try again.';
			}

			await update({ reset: false });
		};
	};
</script>

{#if confirming}
	<div class="confirm-row">
		<span class="confirm-text">Delete {itemLabel}?</span>
		<form method="POST" action="?/deleteSchedule" use:enhance={handleDelete}>
			<input type="hidden" name="schedule_id" value={scheduleId} />
			<Button variant="primary" type="submit" loading={deleting}>Yes, delete</Button>
		</form>
		<Button variant="secondary" type="button" onclick={() => (confirming = false)} disabled={deleting}>
			Cancel
		</Button>
	</div>
{:else}
	<Button variant="link" type="button" onclick={() => (confirming = true)} aria-label={`Delete ${itemLabel}`}>
		Delete
	</Button>
{/if}
{#if resultMessage}
	<p class="delete-note" role="status">{resultMessage}</p>
{/if}

<style>
	.confirm-row {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
	}
	.confirm-text {
		font: var(--weight-med) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.delete-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
</style>
