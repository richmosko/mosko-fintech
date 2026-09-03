<!--
	CashflowRowStaleTag.svelte — the §2.3.2 per-row (Sub-Cat) D1 stale-data-marker (SELF-258
	AC4/AC5). Frontend-owned browser surface. Consumes ONE row's `CashflowRowStaleness`
	($lib/cashflow-row-staleness.ts, a browser-safe mirror of Backend's SELF-258
	cashflowContributors.ts wrapper); authors NO server logic and performs NO staleness
	re-derivation — `is_stale` / `staleAccountNames` are rendered exactly as computed.

	SCOPE: CashflowRollupTable.svelte (§2.3.2) ONLY. The §2.3.3 per-account drill-down's per-row
	indicator is RULED OFF (099's own R3, SELF-258 team-lead default-and-notify, 2026-09-03,
	F/CTO-reversible at PR review): every drill-down row is folded from items of ONE account, so a
	per-row marker there would be provably CONSTANT across every row and carry no information —
	that surface keeps its existing section-level StaleConstituentBadge instead. This component is
	therefore mounted from exactly one call site; a future author adding it to
	CashflowPerAccountTable.svelte is reversing that ruling, not completing unfinished wiring.

	THREE VISIBLY DISTINCT STATES (design-system-spec.md §4/§5's stale-data-marker row, "tag +
	disclosure" realization — the SAME shape StaleConstituentBadge already ships, applied at
	row grain; this is NOT a new visual pattern):
	  - 'stale'   (rowStaleness.is_stale === true) → a compact `.row-stale-tag` button, keyboard-
	                native DISCLOSURE (mirrors StaleConstituentBadge's own `<button aria-expanded>`
	                idiom — reused, not forked: same token set, same interaction shape, scaled to a
	                table-row grain) listing `staleAccountNames` (AC5's tooltip source) + ONE
	                "Re-authenticate" link to `reviewHref`. A single combined link, not one per
	                name: this row's payload (cashflowContributors.ts) carries plain account NAMES
	                only, no per-account `connection_status`, so there is no data to discriminate a
	                reauth-actionable name from an institution-down one at THIS grain (that split
	                lives on the section-level StaleConstituentBadge, which this marker does not
	                replace) — routing to the SAME connection-state review page lets the user see
	                the real per-account status there.
	  - 'unknown' (rowStaleness.is_stale === null) → the quieter muted note, mirrors
	                NonReAllocationTable's / UsEquityAllocationTable's own shipped `.stale-unknown`
	                treatment verbatim (plain text, no disclosure — there is nothing to list; a
	                `title` attribute is sufficient since no interactive affordance exists for this
	                state). NEVER the canary `--c-attn-*` hue — "we don't know" is not "this is
	                stale" (design-system-spec.md §5 fence 8).
	  - 'fresh'   (rowStaleness.is_stale === false) → renders nothing (zero-footprint,
	                self-gating — mirrors StaleConstituentBadge's own `show`/`showUnknown` gate
	                discipline; the CALLER never has to branch on state before mounting this).

	A MISSING lookup (the row's (cat, sub_cat) key absent from the caller's `cashflowRowStalenessMap`
	at either level) is the CALLER's responsibility to resolve to `UNKNOWN_ROW_STALENESS` BEFORE
	this component ever sees it — via `lookupCashflowRowStaleness()`, never a bare property access —
	so this component itself only ever receives one of the three real, already-defaulted states.

	UNIQUE PER-INSTANCE ID: `$props.id()` (Svelte 5's SSR-stable per-instance id generator) —
	CashflowRollupTable.svelte mounts this component ONCE PER ROW, so a hardcoded id would collide
	across every stale row on the page (the exact defect fixed on StaleConstituentBadge itself in
	this same PR — see that file's own SELF-258 note).

	A11Y: keyboard-native disclosure (button + aria-expanded + aria-controls + a labelled region),
	never a hover-only tooltip — a hover-only `title` cannot host the Re-authenticate link's
	keyboard path (mirrors StaleConstituentBadge's own A11Y note verbatim).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { rowStaleDisplayState, type CashflowRowStaleness } from '$lib/cashflow-row-staleness';

	let {
		rowStaleness,
		/** Where the re-auth affordance routes — the SAME connection-state list
		 *  StaleConstituentBadge's own `reviewHref` default points at (SELF-207). */
		reviewHref = '/accounts/connections'
	}: {
		rowStaleness: CashflowRowStaleness;
		reviewHref?: string;
	} = $props();

	const markerState = $derived(rowStaleDisplayState(rowStaleness));

	const uid = $props.id();
	const panelId = `cashflow-row-stale-${uid}`;
	let open = $state(false);

	const count = $derived(rowStaleness.staleAccountNames.length);
	const summary = $derived(
		count === 1
			? '1 account contributing to this row may be stale.'
			: `${count} accounts contributing to this row may be stale.`
	);
</script>

{#if markerState === 'stale'}
	<span class="row-stale-marker" role="group" aria-label={summary}>
		<button
			type="button"
			class="row-stale-tag"
			aria-expanded={open}
			aria-controls={panelId}
			onclick={() => (open = !open)}
		>
			<span class="row-stale-dot" aria-hidden="true"></span>
			<span class="row-stale-tag-text">May be stale</span>
		</button>

		{#if open}
			<div id={panelId} class="row-stale-panel">
				<p class="row-stale-panel-lead">{summary}</p>
				<ul class="row-stale-list">
					{#each rowStaleness.staleAccountNames as name (name)}
						<li class="row-stale-item">{name}</li>
					{/each}
				</ul>
				<a class="row-stale-action" href={reviewHref}>Re-authenticate</a>
			</div>
		{/if}
	</span>
{:else if markerState === 'unknown'}
	<span
		class="row-stale-unknown"
		title="Couldn't confirm whether this row includes stale account data."
	>
		Staleness unknown
	</span>
{/if}

<style>
	/* Reproduces StaleConstituentBadge's own attn-hue token set + disclosure idiom verbatim
	   (§5 fence 8: the RESERVED canary hue), scaled down to a row-level grain — same convention
	   NonReAllocationTable's `.stale-tag` already uses for its own (non-disclosure) row marker. */
	.row-stale-marker {
		display: inline-flex;
		position: relative;
		flex-direction: column;
		align-items: flex-start;
		margin-left: var(--space-2);
		vertical-align: middle;
	}
	.row-stale-tag {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		border: 1px solid var(--c-attn-solid);
		border-radius: var(--radius-sm);
		background: var(--c-attn-bg);
		color: var(--c-attn-text);
		font: var(--weight-bold) var(--fs-micro) / 1 var(--font-ui);
		letter-spacing: 0.05em;
		padding: 0 5px;
		cursor: pointer;
	}
	.row-stale-tag:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.row-stale-dot {
		width: 0.4rem;
		height: 0.4rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
	}

	.row-stale-panel {
		position: absolute;
		top: 100%;
		left: 0;
		z-index: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		width: max-content;
		max-width: 18rem;
		margin-top: var(--space-1);
		padding: var(--space-3);
		border: 1px solid var(--c-attn-border);
		border-radius: var(--radius-md);
		background: var(--c-attn-bg);
		color: var(--c-attn-text);
		box-shadow: var(--shadow-2);
	}
	.row-stale-panel-lead {
		margin: 0;
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
	.row-stale-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.row-stale-item {
		font: var(--weight-semi) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
	.row-stale-action {
		align-self: flex-start;
		color: var(--c-attn-text);
		font-weight: var(--weight-semi);
		text-decoration: underline;
		white-space: nowrap;
	}
	.row-stale-action:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	/* UNKNOWN state — mirrors NonReAllocationTable's / UsEquityAllocationTable's own
	   `.stale-unknown` treatment verbatim: muted, italic, never the canary hue. */
	.row-stale-unknown {
		display: inline-block;
		margin-left: var(--space-2);
		font-style: italic;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
</style>
