<!--
	ReauthStalenessBanner.svelte — the design-system `reauth-staleness-banner (P4)`
	(design-system-spec.md §4 + §5 fences 2/3/8). SELF-207 §2.4.4.b AC #3.

	A layout-level, provider-blind, PERSISTENT, NON-DISMISSIBLE full-width chrome bar. Reads a
	compact connection-health summary (counts only) and renders one of three states:
	  • ABSENT — zero footprint when everything is healthy (renders nothing at all).
	  • PRESENT-N (actionable) — one or more accounts need re-authentication
	    (connection_status ∈ login_required/revoked/disconnected). Carries the re-auth CTA, which
	    routes to the connection-state view where the per-account re-auth affordance lives.
	  • INSTITUTION-DOWN (info) — no accounts need re-auth but ≥1 institution is temporarily
	    unreachable. NO CTA (re-auth can't fix a provider outage — fence 3); info-only.

	FENCES:
	  • §5 fence 8 — the canary ATTENTION hue (`--c-attn-*`) is used here (this IS the reserved
	    staleness/re-auth signal), never as decoration elsewhere.
	  • §5 fence 3 — NON-DISMISSIBLE: there is deliberately no close affordance; the bar clears
	    itself only when the underlying state resolves (counts → 0 → renders nothing).

	Distinct from the D1 `stale-data-marker` (inline row tint/tag on aggregation surfaces) — this
	is the full-width chrome bar. Both share the hue; different shape/placement.

	Tokens ONLY (var(--c-*)). The CTA is a keyboard-native <a>. `role="status"` + aria-live=polite
	announces the standing condition without stealing focus (it is not a transient alert).
-->
<script lang="ts">
	let {
		reauthCount = 0,
		institutionDownCount = 0,
		/** Where the CTA routes — the connection-state view hosting per-account re-auth. */
		reviewHref = '/accounts/connections'
	}: {
		reauthCount?: number;
		institutionDownCount?: number;
		reviewHref?: string;
	} = $props();

	// Actionable (re-auth CTA) takes precedence over the info-only institution-down variant:
	// if anything is re-auth-actionable, that is the message that matters.
	const variant = $derived(
		reauthCount > 0 ? 'reauth' : institutionDownCount > 0 ? 'institution-down' : 'none'
	);

	const reauthMessage = $derived(
		reauthCount === 1
			? '1 connected account needs you to re-authenticate to keep syncing.'
			: `${reauthCount} connected accounts need you to re-authenticate to keep syncing.`
	);
	const institutionDownMessage = $derived(
		institutionDownCount === 1
			? "One of your institutions is temporarily unreachable. We'll keep retrying — no action needed."
			: "Some of your institutions are temporarily unreachable. We'll keep retrying — no action needed."
	);
</script>

{#if variant !== 'none'}
	<aside class="banner variant-{variant}" role="status" aria-live="polite">
		<div class="banner-inner">
			<span class="banner-icon" aria-hidden="true">
				{variant === 'reauth' ? '!' : 'i'}
			</span>
			<p class="banner-text">
				{variant === 'reauth' ? reauthMessage : institutionDownMessage}
			</p>
			{#if variant === 'reauth'}
				<a class="banner-cta" href={reviewHref}>Review connections</a>
			{/if}
		</div>
	</aside>
{/if}

<style>
	.banner {
		width: 100%;
		background: var(--c-attn-bg);
		/* attn-solid left stripe (spec: "solid(stripe)") + a hairline bottom border. */
		border-bottom: 1px solid var(--c-attn-border);
		border-left: var(--space-1) solid var(--c-attn-solid);
		color: var(--c-attn-text);
	}
	.banner-inner {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		max-width: 64rem;
		margin: 0 auto;
		padding: var(--space-3) var(--space-5);
	}
	.banner-icon {
		flex: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.5rem;
		height: 1.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		color: var(--c-attn-text);
		font-weight: var(--weight-bold);
		font-size: var(--fs-small);
	}
	.banner-text {
		margin: 0;
		flex: 1 1 auto;
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
	}
	.banner-cta {
		flex: none;
		padding: var(--space-1) var(--space-3);
		border-radius: var(--radius-md);
		border: 1px solid var(--c-attn-border);
		background: var(--c-attn-solid);
		color: var(--c-attn-text);
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		text-decoration: none;
		white-space: nowrap;
	}
	.banner-cta:hover {
		text-decoration: underline;
	}
	.banner-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	@media (max-width: 32rem) {
		.banner-inner {
			flex-wrap: wrap;
		}
	}
</style>
