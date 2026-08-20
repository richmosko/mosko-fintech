<!--
	UsEquityAllocationTable.svelte — the §2.2.3 US Equity sub-allocation table (SELF-241).
	Frontend-owned browser surface. Presentational shell over the types + helpers in
	$lib/us-equity-allocation + $lib/allocation-taxonomy; authors NO server logic. Consumed by
	routes/allocation/us-equity/+page.svelte.

	Reuses SELF-239's shipped §2.2.2 patterns (NonReAllocationTable.svelte, PR #516) rather than
	inventing parallel ones, per team-lead instruction — screen.css table shape, staleness
	machinery, edit-link affordance, no-inline-edit posture.

	AC1 — exactly twelve rows, in `US_EQUITY_SUB_CATS` canonical order (US-01 Basic Materials →
	US-10 Utilities → Index_Non_Sector → Growth_Non_Sector). The row SET/ORDER comes from
	`allocation.rows` as Backend already returns it (SELF-240's own contract: exactly twelve, in
	that order, regardless of held/target state) — this component does not re-sort or filter.

	AC2 — same 5 columns as §2.2.2: % Target | % Alloc | $ Target | $ Alloc | $ ReAlloc.

	AC3 — a `tr.foot` "Total US Equity" row aggregates `$ Alloc` via `allocation.total.dollar_alloc`
	(the SAME drill-down-identity anchor SELF-240's own AC3 ratifies against the §2.2.2 collapsed
	"US - Sector Diversified" row's dollar_alloc — see usEquityAllocation.drilldown-identity.test.ts
	server-side). Renders a visual cross-reference via a `title` tooltip on the row header
	("Equals the § 2.2.2 'US - Sector Diversified' row") plus a visible parenthetical, matching the
	wireframe's "Total US Equity (= parent row)" shape (docs/DESIGN/wireframes/2.2-asset-allocation.html).

	AC4 — a zero-allocation Sub-Cat (market_value = 0 AND pct_target = 0, `isZeroAllocSubCat()`)
	renders de-emphasized (`.zero-alloc`, muted text) but PRESENT — never filtered out. All twelve
	rows always render regardless of this state.

	AC5 — NO inline edit (ADR-013 P5): every data cell is plain text, no
	<input>/<button>/<select>/[contenteditable]. The "Edit US Equity targets" action is a plain
	navigation `<a>` in the header, routing to `/settings/allocation#us-equity-heading` — the
	SELF-242 editor already renders a distinct "US Equity" sub-section at that anchor
	(PlanningTargetEditor.svelte's own `id="us-equity-heading"`), which is what "scoped to US
	Equity Sub-Cats" resolves to today: an anchor-scroll into the existing single editor, not a
	second, separately-routed editor page (file-layout/routing judgment call, per role charter
	"just decide" — flagged at hand-off since a dedicated scoped route would also have been
	defensible).

	SIGN TREATMENT — flagged discrepancy at hand-off: this ticket's brief says "$ ReAlloc positive
	= green, negative = red," but the ACTUALLY SHIPPED §2.2.2 table (NonReAllocationTable.svelte,
	merged PR #516, 2026-08-20) uses AC5's reversed-neutral treatment — `.val-target` renders
	%Target/$Target/$ReAlloc with NO pos/neg color anywhere (a deliberate spec reversal from an
	earlier pre-SELF-238 draft). Per this ticket's OWN instruction to "reuse the shipped §2.2.2
	components/patterns," this table matches the shipped neutral treatment, not the brief's
	pos/neg color line — the two instructions conflict, and shipped code + its own ratified AC
	text outrank an unverified brief line. Escalate if the brief's color line was intentional
	scope for THIS table specifically.

	AC6 — drill-down navigation FROM this table: none (US Equity is a leaf; no third level per
	the design flow doc's F-2.2.C). The §2.2.2→§2.2.3 entry link lives on NonReAllocationTable.svelte
	(the "US - Sector Diversified" row); the back-link lives on this route's +page.svelte header.

	AC7 — staleness per §2.4.4 / ADR-013 D1, same two-part shape as §2.2.2:
	  (1) SECTION-level `StaleConstituentBadge` fed by the whole-tenant `staleness` prop.
	  (2) PER-ROW inline `.stale-tag` + `tr.stale-row` tint keyed on `UsEquityRow.is_stale`, run
	      through the SAME `staleDisplayState()` helper §2.2.2 uses (reused from
	      nonre-allocation.ts, not reimplemented — one tri-state normalization for the whole app).
	      DORMANT today (usEquityAllocation.ts has no per-row producer yet, same gap
	      nonReAllocation.ts has) — every row shows "Staleness unknown" honestly until Backend
	      wires the contributor join, never silently "fresh" (the SELF-220/229 hazard).

	Sec F-1 fix (PR #520 review, AMBER, resolved): the render-boundary gate on the degenerate US
	Equity denominator (`allocation.total.dollar_alloc`) — REUSED `ratioColumnsUnset()` from
	`$lib/nonre-allocation`, not a second predicate. Sec's finding: the landed server core
	(`computeUsEquityAllocation`, SELF-240) nulls `pct_alloc` on `totalUsEquity === 0` and nulls
	`pct_target`/`dollar_target`/`dollar_realloc` on a SEPARATE `sumTargets === 0` guard — the two
	do not null together, and neither is `<= 0` (a negative total passes both `=== 0` checks
	un-gated). That let the banner assert "No US Equity holdings" while a real %Target column
	rendered (zero-holdings-with-configured-targets — the ordinary onboarding state), or assert it
	falsely outright at a negative total while every ratio column rendered real figures. `isDegenerate`
	and every `fmtPct`/`fmtUsd` call below now gate on the SAME single predicate
	(`ratioColumnsUnset(allocation.total.dollar_alloc)`, `<= 0` — a domain guard, not the server's
	`=== 0` NaN-guard), applied uniformly to all four ratio columns on both the data rows and the
	Total row, regardless of what the (possibly non-null) server payload says underneath. $Alloc
	stays exempt (the real figure, never gated). See us-equity-allocation.ts's own header for why
	this render-boundary gate is LOAD-BEARING here, not redundant belt-and-suspenders the way
	nonre-allocation.ts's equivalent gate is.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import type { UsEquityAllocation } from '$lib/us-equity-allocation';
	import { isZeroAllocSubCat, fmtPct, fmtUsd } from '$lib/us-equity-allocation';
	import { staleDisplayState, ratioColumnsUnset } from '$lib/nonre-allocation';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B)-style discipline (mirrors NonReAllocationTable): both props REQUIRED, no default —
	// a caller that forgets to thread real data fails at TYPECHECK, not as a silent
	// "confirmed healthy" / empty-table fallback.
	let {
		allocation,
		staleness,
		editHref = '/settings/allocation#us-equity-heading'
	}: {
		allocation: UsEquityAllocation;
		staleness: StalenessData;
		editHref?: string;
	} = $props();

	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});

	// Sec F-1: the SINGLE degenerate-denominator predicate for this table — reused for the banner
	// AND every ratio-column render below, so the two can never disagree with each other again.
	const isDegenerate = $derived(ratioColumnsUnset(allocation.total.dollar_alloc));
</script>

<section class="alloc" aria-labelledby="us-equity-label">
	<header class="head">
		<h2 id="us-equity-label" class="section-label">US Equity Sub-Allocation</h2>
		<a class="edit-link" href={editHref}>Edit US Equity targets</a>
	</header>

	<!-- AC7(1): section-level D1 marker, fed by the whole-tenant staleness read. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

	{#if isDegenerate}
		<!-- Sec F-1: sign-honest, cause-neutral — matches the shipped §2.2.2 wording shape
		     (nonre-allocation.ts's own note). "currently total zero or less" is true whether the
		     total is exactly zero OR negative; the earlier "No US Equity holdings" phrasing was
		     false at a negative total, where real dollar figures are still on screen. -->
		<p class="ratio-unset-note" role="status">
			Percent and target comparisons aren't shown below because your US Equity holdings
			currently total zero or less — dollar values are still accurate.
		</p>
	{/if}

	<div class="table-scroll">
		<table class="alloc-tbl">
			<caption class="sr-only"
				>US Equity sub-allocation by Sub-Cat, target vs. actual, evaluated against Total US
				Equity.</caption
			>
			<thead>
				<tr>
					<th scope="col">Sub-Cat</th>
					<th scope="col" class="num">% Target</th>
					<th scope="col" class="num">% Alloc</th>
					<th scope="col" class="num">$ Target</th>
					<th scope="col" class="num">$ Alloc</th>
					<th scope="col" class="num">$ ReAlloc</th>
				</tr>
			</thead>

			<tbody>
				{#each allocation.rows as row (row.sub_cat_id ?? row.sub_cat)}
					{@const rowStale = staleDisplayState(row.is_stale)}
					{@const deemphasize = isZeroAllocSubCat(row)}
					<tr class:stale-row={rowStale === 'stale'} class:zero-alloc={deemphasize}>
						<td class="rowlabel">
							{row.sub_cat}
							<!-- AC7(2): per-row NORMALIZED tri-state marker, dormant until Backend wires a
							     real is_stale producer (same posture as §2.2.2). -->
							{#if rowStale === 'stale'}
								<span
									class="stale-tag"
									title="This Sub-Cat includes possibly-stale account data.">May be stale</span
								>
							{:else if rowStale === 'unknown'}
								<span
									class="stale-unknown"
									title="Couldn't confirm whether this Sub-Cat includes stale account data."
									>Staleness unknown</span
								>
							{/if}
						</td>
						<td class="num val-target">{fmtPct(row.pct_target, allocation.total.dollar_alloc)}</td>
						<td class="num">{fmtPct(row.pct_alloc, allocation.total.dollar_alloc)}</td>
						<td class="num val-target">{fmtUsd(row.dollar_target, allocation.total.dollar_alloc, usd)}</td>
						<td class="num">{usd.format(row.dollar_alloc)}</td>
						<td class="num val-target">{fmtUsd(row.dollar_realloc, allocation.total.dollar_alloc, usd)}</td>
					</tr>
				{/each}
			</tbody>

			<tbody class="ladder">
				<!-- AC3: drill-down-identity anchor — $Alloc equals the §2.2.2 collapsed row exactly. -->
				<tr class="foot">
					<th scope="row" title="Equals the §2.2.2 &quot;US - Sector Diversified&quot; row exactly.">
						Total US Equity <span class="parent-ref">(= §2.2.2 parent row)</span>
					</th>
					<td class="num val-target">{fmtPct(allocation.total.pct_target, allocation.total.dollar_alloc)}</td>
					<td class="num">{fmtPct(allocation.total.pct_alloc, allocation.total.dollar_alloc)}</td>
					<td class="num val-target">{fmtUsd(allocation.total.dollar_target, allocation.total.dollar_alloc, usd)}</td>
					<td class="num">{usd.format(allocation.total.dollar_alloc)}</td>
					<td class="num val-target">{fmtUsd(allocation.total.dollar_realloc, allocation.total.dollar_alloc, usd)}</td>
				</tr>
			</tbody>
		</table>
	</div>
</section>

<style>
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

	.alloc {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.section-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}
	/* Reproduces the locked screen.css `.btn.secondary` look, as a plain navigation <a> — same
	   convention NonReAllocationTable.svelte uses for its own "Edit allocation targets" link. */
	.edit-link {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
		white-space: nowrap;
	}
	.edit-link:hover {
		background: var(--c-surface-alt);
	}
	.edit-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}

	.ratio-unset-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css `table.tbl` with tokens only, same rules as
	   NonReAllocationTable.svelte. */
	.alloc-tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.alloc-tbl th,
	.alloc-tbl td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.alloc-tbl thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.alloc-tbl td.num,
	.alloc-tbl th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.alloc-tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}

	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}
	.parent-ref {
		font-weight: var(--weight-reg);
		text-transform: none;
		letter-spacing: normal;
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
	}

	/* AC5 (matches the ACTUALLY SHIPPED §2.2.2 treatment — see header note): .val-target keeps
	   target/$ReAlloc/%Target cells NEUTRAL — identical ink to a plain cell; no pos/neg color. */
	.val-target {
		color: var(--c-text-primary);
	}

	/* AC4 — zero-allocation, still-present Sub-Cats render de-emphasized: muted text, no
	   strikethrough/hidden — the row stays fully legible, just visually quieter. Only `<td>`s
	   ever carry `.zero-alloc` (data rows have no `<th>`; the foot row's `<th scope="row">`
	   never carries this class). */
	tr.zero-alloc td {
		color: var(--c-text-muted);
	}

	/* AC7(2) — reproduces NonReAllocationTable.svelte's own D1 shape verbatim (tokens only). */
	.stale-tag {
		display: inline-block;
		margin-left: var(--space-2);
		font-size: var(--fs-micro);
		font-weight: var(--weight-bold);
		letter-spacing: 0.05em;
		color: var(--c-attn-text);
		background: var(--c-attn-bg);
		border: 1px solid var(--c-attn-solid);
		border-radius: var(--radius-sm);
		padding: 0 5px;
		cursor: help;
	}
	tr.stale-row td {
		background: color-mix(in srgb, var(--c-attn-bg) 55%, var(--c-surface));
	}
	.stale-unknown {
		display: inline-block;
		margin-left: var(--space-2);
		font-style: italic;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
</style>
