<!--
	UnpricedMarker.svelte — the "no price available" LOUD marker (SELF-325 / 088 UNPRICED-
	BUT-LOUD posture). F/CTO + Architect ruling (2026-08-21, relayed verbatim by team-lead):
	"if the loud state is descoped this becomes F3 shipped as a feature" — this is a HARD
	CONDITION of the ratified design, not polish.

	CONTRACT: `priced` is the 088 RPC's own composite-return flag — TRUE iff an eod_price
	row exists for the asset at the maximum price_date <= the trade date with price > 0.
	Architect's verbatim constraint: "`priced` is a rendering indicator, NOT a valuation
	primitive — nothing may compute money from it." This component obeys that by taking
	NO money value as a prop at all — only the boolean. Zero-footprint when `priced` is
	true (mirrors StaleConstituentBadge / InformationalMarkerBadge's zero-footprint
	discipline for every OTHER degraded-state marker in this codebase).

	REUSE-BEFORE-INVENT (frontend-engineer discipline #3): this is NOT the same signal as
	`stale-constituent.ts`'s pending-re-auth staleness — a global asset with no market
	price is a DIFFERENT fact (no provider has ever priced it, not "this account's feed
	went stale") — so it is its own component rather than a StaleConstituentBadge prop
	variant. But the VISUAL REGISTER is reused rather than invented: this borrows
	StaleConstituentBadge's `--c-attn-*` "confirmed, actionable-adjacent" tag vocabulary
	(border/bg/text + solid-edge + dot), because an unpriced position is a definite,
	financially material fact about THIS render, same register as a confirmed-stale tag —
	never the quieter `InformationalMarkerBadge` neutral-chip register, which is reserved
	for a fact with no bearing on money (§5 fence 8: the canary hue is reserved for a real
	staleness/attention signal, and "excluded from net worth" qualifies). Flagged to Visual
	Designer as a candidate for its own design-system token pairing if a THIRD consumer of
	this exact visual shape shows up — two is not yet a pattern.

	Two render modes, chosen by call site rather than by a variant prop (the JSX/markup
	differs enough — a full sentence at confirmation vs. an inline tag beside a value —
	that one component branching on a boolean would be harder to read than two thin
	entry points sharing one visual vocabulary):
	  - `<UnpricedMarker context="confirmation" />` — the full sentence, used right after a
	    purchase RPC call returns `priced: false` (PurchaseEntryForm's confirmation state).
	  - `<UnpricedMarker context="inline" />` — a compact tag for beside a rendered value.
	    NOT YET WIRED to any holding-value render surface (account-detail ledger, NAV
	    composition, allocation) — see the bubble-up note in the SELF-325 handoff: none of
	    those read-time queries currently expose a per-holding `priced` signal, so there is
	    no data to drive this mode yet. The component ships ready for that wiring the
	    moment Backend extends those loaders.
-->
<script lang="ts">
	let {
		priced,
		context = 'inline'
	}: {
		/** 088's own composite-return flag. `true` or `null`/`undefined` → zero-footprint. */
		priced: boolean | null | undefined;
		/** 'confirmation' = full sentence (purchase result). 'inline' = compact tag (beside
		 *  a rendered value on a holding/NAV/allocation surface). */
		context?: 'confirmation' | 'inline';
	} = $props();

	const show = $derived(priced === false);
</script>

{#if show}
	{#if context === 'confirmation'}
		<p class="unpriced-note" role="status">
			<span class="unpriced-tag">
				<span class="unpriced-dot" aria-hidden="true"></span>
				<span class="unpriced-tag-text">No price available</span>
			</span>
			<span class="unpriced-detail">
				No market price is on record for this security yet, so it's excluded from your net
				worth until one is. The purchase itself was recorded.
			</span>
		</p>
	{:else}
		<span class="unpriced-tag" role="status" aria-label="No price available — excluded from net worth">
			<span class="unpriced-dot" aria-hidden="true"></span>
			<span class="unpriced-tag-text">No price available</span>
		</span>
	{/if}
{/if}

<style>
	/* Same `--c-attn-*` register StaleConstituentBadge's confirmed-stale `.stale-tag` uses
	   (§5 fence 8 canary hue) — tokens only, no hardcoded hex/px-spacing/font. */
	.unpriced-tag {
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
		white-space: nowrap;
	}
	.unpriced-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		flex: 0 0 auto;
	}
	.unpriced-note {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2);
		margin: 0;
		max-width: 32rem;
	}
	.unpriced-detail {
		font-size: var(--fs-small);
		line-height: var(--lh-body);
		color: var(--c-text-secondary);
	}
</style>
