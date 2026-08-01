<!--
	SyncNowControl.svelte — SELF-317 per-connection manual "Sync now" trigger (ADR-037 amendment).
	Rendered on the connection-state view (one per active connection) and, for provider-linked
	accounts, in the account-detail sync-history section.

	CLIENT-INITIATED action, so a `fetch`+JSON relay (via the DOM-free `requestSync`), NOT a form
	action (api/CLAUDE.md forms rule). The interaction (A2 return-fast, ADR-037 §4):
	  1. Click → POST /api/sync { source_id } → 202 { sources:[{ disposition }] }.
	  2. On accept, DISABLE the button for 60s (matches the worker's per-source debounce — fast
	     feedback; the worker's in-memory Map is the real enforcement) and show a "Syncing…" status.
	  3. POLL for freshness: invalidate the loader every few seconds for ~30s (or until this
	     connection's `lastSyncedAt` advances), then settle. The 040/043 sync-state views ARE the
	     status channel (A2) — "accepted" ≠ "succeeded"; the views carry the real outcome.
	  4. On 404/502/network → an inline role="alert" error; the button re-enables to retry. The
	     row is never blocked.

	`disposition:'debounced'` (a recent trigger is still inside the 60s window) → a quiet
	"already up to date" status; the button still holds disabled for the local 60s (defense-in-depth).

	TOKENS ONLY (var(--c-*)). The control uses the NEUTRAL/accent ramp (Button `secondary`) — the
	attention hue (`--c-attn-*`, canary) stays RESERVED for staleness / re-auth (design §5 fence 8),
	never a sync affordance. a11y: labelled button, aria-live status, role="alert" error, disabled
	state announced (Button sets aria-busy while requesting), keyboard-native.
-->
<script lang="ts">
	import { onDestroy } from 'svelte';
	import { invalidateAll } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import { requestSync as defaultSync, SyncError } from '$lib/accounts/syncFlow';

	let {
		source_id,
		institution_name = null,
		// This connection's current last-successful-sync timestamp (043 view). Optional: when
		// provided, the poll short-circuits the moment it advances; when absent (e.g. the account
		// page has no such scalar), the poll simply runs its full window.
		lastSyncedAt = null,
		// Re-fetch the server data so `lastSyncedAt` (and the sync-history panel) refresh. Default
		// invalidates all loaders; injectable for tests / narrower invalidation.
		onPoll = invalidateAll,
		// Injectable relay seam (default is the real fn) — unit-test without network.
		syncFn = defaultSync,
		// Timing knobs (overridable in tests to avoid real 60s/30s waits).
		disableMs = 60_000,
		pollIntervalMs = 3_000,
		pollWindowMs = 30_000
	}: {
		source_id: string;
		institution_name?: string | null;
		lastSyncedAt?: string | null;
		onPoll?: () => void | Promise<void>;
		syncFn?: typeof defaultSync;
		disableMs?: number;
		pollIntervalMs?: number;
		pollWindowMs?: number;
	} = $props();

	type Status = 'idle' | 'requesting' | 'syncing' | 'error';
	let status = $state<Status>('idle');
	let statusMessage = $state('');
	let errorMessage = $state('');

	const busy = $derived(status === 'requesting' || status === 'syncing');
	const label = $derived(institution_name ? `Sync ${institution_name} now` : 'Sync now');

	// Cancellation + single-timer tracking so an unmount can't leave a dangling timeout or let the
	// async lifecycle mutate a destroyed component's state.
	let cancelled = false;
	let activeTimer: ReturnType<typeof setTimeout> | null = null;
	onDestroy(() => {
		cancelled = true;
		if (activeTimer) clearTimeout(activeTimer);
	});

	function sleep(ms: number): Promise<void> {
		return new Promise((resolve) => {
			activeTimer = setTimeout(() => {
				activeTimer = null;
				resolve();
			}, ms);
		});
	}

	function friendly(failure: SyncError['failure']): string {
		switch (failure) {
			case 'unauthenticated':
				return 'Your session has expired. Please sign in again, then try syncing.';
			case 'not_found':
				return "We couldn't find this connection. Please refresh the page and try again.";
			case 'unavailable':
				return "The sync service is unavailable right now. Please try again in a moment.";
			default:
				return "Couldn't start the sync — please try again.";
		}
	}

	async function start() {
		if (busy) return;
		errorMessage = '';
		statusMessage = '';
		status = 'requesting';

		let disposition: 'triggered' | 'debounced';
		try {
			const res = await syncFn(source_id);
			// Per-source request → the single entry for our source (fall back to the first).
			const entry = res.sources.find((s) => s.source_id === source_id) ?? res.sources[0];
			disposition = entry?.disposition ?? 'triggered';
		} catch (e) {
			if (cancelled) return;
			errorMessage = friendly(e instanceof SyncError ? e.failure : 'sync_failed');
			status = 'error';
			return;
		}
		if (cancelled) return;
		await runSyncing(disposition);
	}

	/** Post-accept lifecycle: hold disabled for the debounce window; poll for freshness meanwhile. */
	async function runSyncing(disposition: 'triggered' | 'debounced') {
		const startedAt = Date.now();
		status = 'syncing';
		statusMessage = disposition === 'debounced' ? 'Already up to date.' : 'Syncing…';
		const baseline = lastSyncedAt ?? null;

		if (disposition === 'triggered') {
			let advanced = false;
			while (!cancelled && Date.now() - startedAt < pollWindowMs) {
				await sleep(pollIntervalMs);
				if (cancelled) return;
				try {
					await onPoll(); // re-run the loader → `lastSyncedAt` (+ sync-history panel) refresh
				} catch {
					/* a transient invalidate failure just means we poll again next tick */
				}
				if (cancelled) return;
				if (lastSyncedAt && lastSyncedAt !== baseline) {
					advanced = true;
					statusMessage = 'Updated just now.';
					break;
				}
			}
			if (!cancelled && !advanced) {
				// Window elapsed with no observed advance (a no-op/empty sync leaves the timestamp
				// unchanged, or this surface doesn't track it) — the trigger still succeeded.
				statusMessage = 'Sync started — this can take a moment.';
			}
		}

		// Keep the button disabled for the remainder of the 60s worker-debounce window.
		const remaining = disableMs - (Date.now() - startedAt);
		if (remaining > 0) await sleep(remaining);
		if (cancelled) return;
		status = 'idle';
		statusMessage = '';
	}
</script>

<div class="sync">
	<Button
		variant="secondary"
		onclick={start}
		loading={status === 'requesting'}
		disabled={busy}
		aria-label={label}
	>
		Sync now
	</Button>

	<p class="sync-status" aria-live="polite">{statusMessage}</p>

	{#if status === 'error'}
		<p class="sync-error" role="alert">{errorMessage}</p>
	{/if}
</div>

<style>
	.sync {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		align-items: flex-start;
	}
	.sync-status {
		margin: 0;
		min-height: var(--fs-small);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.sync-status:empty {
		min-height: 0;
	}
	.sync-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
</style>
