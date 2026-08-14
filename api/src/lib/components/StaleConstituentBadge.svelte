<!--
	StaleConstituentBadge.svelte — the D1 `stale-data-marker` (design-system-spec.md §4 + §5
	fences 2 / 8) for the headline NAV surface (SELF-208 · §2.4.4.c AC#4).

	ADR-013 D1: the surface list at PRD §2.4.4 is ILLUSTRATIVE-not-exhaustive; this framework
	applies to EVERY aggregation consuming Plaid-sourced data. V1.0 wires the NAV headline
	(§2.1.1) off the `046` fn_aggregation_has_stale_constituent primitive; §2.1.2 / §2.1.5 /
	§2.2.2 / §2.3.2 / §2.3.4 / §2.6 reuse this same component + payload at V1.1+.

	CONTRACT: props mirror one `046` aggregate row — { is_stale, stale_items[] }. Zero-footprint
	(renders NOTHING) when not stale / empty list — mirrors CountBadge's zero-footprint discipline.
	When stale it MARKS, never SUPPRESSES: it sits beside the net-worth number, never hides it (D1).

	PER-STATUS AFFORDANCE (keyed on connection_status via the canonical predicates in
	stale-constituent.ts → connection-status-constants.ts):
	  • REAUTH set {login_required, revoked, disconnected} → a "Re-authenticate" link routing to
	    `/accounts/connections` (the SELF-207 connection-state list; same target as the P4
	    ReauthStalenessBanner reviewHref) where the per-account re-auth affordance lives.
	  • institution_down (+ any forward-compat unknown) → INFORMATIONAL text, NO link (re-auth
	    cannot fix a provider-side outage — marked-but-not-reauth, per the `046` contract).

	HUE FENCE (§5 fence 8): uses the RESERVED canary attention hue `--c-attn-*` — this IS a
	staleness signal. NOT the accent ramp CountBadge uses (that is a notification count). Tokens
	only (var(--c-*)); no hardcoded hex/px-spacing/font.

	A11Y: the design-spec shape is "tag + hover→tooltip", but the panel carries an interactive
	re-auth link, so a pure hover-tooltip would be an anti-pattern (focusable content in a tooltip,
	no keyboard path). Realized instead as a keyboard-native DISCLOSURE: a <button aria-expanded>
	tag toggling a labelled region. The decorative dot is aria-hidden; the button's text + the
	aria-label carry the accessible name (CountBadge a11y pattern — signal is named on the control,
	not the decoration). Visual-treatment shape (disclosure vs. hover-tooltip realization of the
	spec tag) → flagged to Visual Designer.
-->
<script lang="ts">
	import {
		staleAffordance,
		hasReauthActionable,
		type StaleConstituentItem
	} from '$lib/staleness/stale-constituent';

	let {
		isStale = false,
		staleItems = [],
		/** Where the re-auth affordance routes — the connection-state list (SELF-207). */
		reviewHref = '/accounts/connections'
	}: {
		isStale?: boolean;
		staleItems?: StaleConstituentItem[];
		reviewHref?: string;
	} = $props();

	// Zero-footprint gate: honour BOTH the flag and a non-empty list (defensive — never render
	// an empty marker if the flag and the list ever disagree).
	const show = $derived(isStale && staleItems.length > 0);

	const count = $derived(staleItems.length);
	const anyReauth = $derived(hasReauthActionable(staleItems));

	// Accessible standing-condition summary (named on the control, per the CountBadge pattern).
	const summary = $derived(
		count === 1
			? '1 account is contributing possibly-stale data to this total.'
			: `${count} accounts are contributing possibly-stale data to this total.`
	);

	let open = $state(false);
</script>

{#if show}
	<!-- CLASS NAME: `.stale-connection-marker`, not the shorter `.stale-marker` — QA flagged
	     (SELF-229) that NavChartLines.svelte's UNRELATED checkpoint-carry marker
	     (<g class="stale-marker" role="img">, a per-point chart annotation) already owns that
	     name and both render inside NavHistoryChart's tree; a bare `.stale-marker` DOM query
	     would silently sum two different signals. Renamed here (this component's own class,
	     not NavChartLines') to remove the landmine — the two are discriminable by `role`
	     ("group" here vs "img" there) but a distinct class name is cheaper than relying on
	     every future query remembering that. -->
	<div class="stale-connection-marker" role="group" aria-label={summary}>
		<button
			type="button"
			class="stale-tag"
			aria-expanded={open}
			aria-controls="stale-constituent-list"
			onclick={() => (open = !open)}
		>
			<span class="stale-dot" aria-hidden="true"></span>
			<span class="stale-tag-text">May be stale</span>
		</button>

		{#if open}
			<div id="stale-constituent-list" class="stale-panel">
				<p class="stale-panel-lead">{summary}</p>
				<ul class="stale-list">
					{#each staleItems as item (item.linked_source_id)}
						{@const kind = staleAffordance(item.connection_status)}
						<li class="stale-item">
							<span class="stale-inst">{item.institution_name}</span>
							{#if kind === 'reauth'}
								<a class="stale-action" href={reviewHref}>Re-authenticate</a>
							{:else}
								<!-- name-once: institution_name is already in .stale-inst above. -->
								<span class="stale-info">temporarily unavailable</span>
							{/if}
						</li>
					{/each}
				</ul>
				{#if anyReauth}
					<a class="stale-review" href={reviewHref}>Review connections</a>
				{/if}
			</div>
		{/if}
	</div>
{/if}

<style>
	.stale-connection-marker {
		display: inline-flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2);
	}

	/* The tag: attn-solid edge + attn-bg/text (spec: stale-data-marker → attn-solid(edge),
	   attn-bg/text). The RESERVED staleness hue — never the accent ramp (§5 fence 8). */
	.stale-tag {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		padding: var(--space-1) var(--space-2);
		border: 1px solid var(--c-attn-border);
		border-left: var(--space-1) solid var(--c-attn-solid);
		border-radius: var(--radius-sm);
		background: var(--c-attn-bg);
		color: var(--c-attn-text);
		font: var(--weight-semi) var(--fs-small) / 1 var(--font-ui);
		cursor: pointer;
	}
	.stale-tag:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.stale-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
	}

	.stale-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		max-width: 20rem;
		padding: var(--space-3);
		border: 1px solid var(--c-attn-border);
		border-radius: var(--radius-md);
		background: var(--c-attn-bg);
		color: var(--c-attn-text);
		box-shadow: var(--shadow-2);
	}
	.stale-panel-lead {
		margin: 0;
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
	.stale-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.stale-item {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
	.stale-inst {
		font-weight: var(--weight-semi);
	}
	.stale-info {
		color: var(--c-attn-text);
		font-style: italic;
	}
	.stale-action,
	.stale-review {
		color: var(--c-attn-text);
		font-weight: var(--weight-semi);
		text-decoration: underline;
		white-space: nowrap;
	}
	.stale-review {
		align-self: flex-start;
	}
	.stale-action:focus-visible,
	.stale-review:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
</style>
