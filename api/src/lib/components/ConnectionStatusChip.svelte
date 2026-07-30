<!--
	ConnectionStatusChip.svelte — the design-system `connection-status-chip` (design-system-spec.md
	§4). SELF-207 §2.4.4.b. Provider-blind per-account connection-health indicator.

	Renders one of the chip states derived from the row (fresh · re-auth-actionable · institution-
	down(info) · grant-revoked · manual · inactive—sync-paused) — the derivation + value-set are
	canonical in connection-status-constants.ts (anti-drift vs the `015` DB CHECK); the label + tone
	are presentation (connection-display.ts, provisional copy → UX).

	FENCE (§5 fence 8): the ATTENTION hue (`--c-attn-*`, canary) is used ONLY for the re-auth /
	staleness states — never for 'fresh' (positive dot) or 'manual'/'inactive' (neutral/muted).
	Colour is NOT the sole signal: every chip carries its text label, and an sr-only prefix names
	it as a connection status for assistive tech.

	Tokens ONLY (var(--c-*)). No interactivity here — the re-auth affordance is a separate control
	on the connection-state view (this chip is a status indicator, not a button).
-->
<script lang="ts">
	import { connectionChipState } from '$lib/schemas/connection-status-constants';
	import { chipPresentation } from '$lib/accounts/connection-display';

	let {
		connection_status,
		provider,
		is_active = true
	}: {
		connection_status: string;
		provider: string;
		is_active?: boolean;
	} = $props();

	const state = $derived(connectionChipState({ connection_status, provider, is_active }));
	const pres = $derived(chipPresentation(state));
</script>

<span class="chip tone-{pres.tone}">
	<span class="sr-only">Connection status:</span>
	{#if pres.tone === 'pos'}
		<span class="dot" aria-hidden="true"></span>
	{/if}
	<span class="chip-label">{pres.label}</span>
</span>

<style>
	.chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		padding: var(--space-0) var(--space-2);
		border-radius: var(--radius-pill);
		border: 1px solid transparent;
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		line-height: 1.6;
		white-space: nowrap;
	}
	.chip-label {
		display: inline-block;
	}

	/* pos: a healthy dot + neutral text (dot-only colour per the spec — no attn fill). */
	.tone-pos {
		background: var(--c-surface-alt);
		border-color: var(--c-border);
		color: var(--c-text-secondary);
	}
	.tone-pos .dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-pos);
	}

	/* attn: the reserved canary staleness/re-auth hue (fence 8) — fill + border + text. */
	.tone-attn {
		background: var(--c-attn-bg);
		border-color: var(--c-attn-border);
		color: var(--c-attn-text);
		font-weight: var(--weight-semi);
	}

	/* muted: neutral (manual / inactive) — NOT an attention signal. */
	.tone-muted {
		background: var(--c-surface-alt);
		border-color: var(--c-border-strong);
		color: var(--c-text-muted);
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
