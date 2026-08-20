<!--
	NonReAllocationTable.svelte — the §2.2.2 Non-RE allocation table (SELF-239).
	Frontend-owned browser surface. Presentational shell over the types + helpers in
	$lib/nonre-allocation; authors NO server logic. Consumed by routes/allocation/+page.svelte.

	Ratified ACs realized here (2026-08-20):

	AC1 — exactly four Cat-group headers, Cash → Bonds → Marketable Securities → Alternatives; no
	Liabilities, no Real Estate. `groupsToRender()` filters + fixes the order — matches Backend's
	own `CAT_GROUP_ORDER` (also four values as of SELF-239; see $lib/nonre-allocation.ts's header)
	field-for-field. The filter-by-name in `groupsToRender()` is defensive robustness against a
	malformed/legacy payload shape, not something the current contract actually produces.

	AC2 — full enumeration (incl. zero-held rows), the collapsed "US - Sector Diversified" row
	inside Marketable Securities, and the Unsorted row are all rendered exactly as Backend's
	`groups[].rows[]` / `unsorted` arrive — no client-side filtering of rows within a group. Five
	columns in PRD order: % Target | % Alloc | $ Target | $ Alloc | $ ReAlloc (positive $ReAlloc =
	underweight — nonReAllocation.ts's own `dollar_target - market_value` sign).

	AC4 — per-Cat-group subtotal rows (`tr.subtotal`, bold + top divider, reproducing the locked
	screen.css `table.tbl` spec) computed via `groupSubtotal()`; a `tr.foot` "Total Non-RE" row
	foots every group + Unsorted to `total_non_re`. The foot's $Alloc cell displays
	`allocation.total_non_re` directly (the authoritative anchor), not a client-re-derived sum —
	AC4's exact-footing invariant is Backend's to hold; this table never re-asserts it by
	overriding the anchor with its own arithmetic. JUDGMENT CALL (flagged at hand-off): the foot's
	$ReAlloc is `grandDollarTarget − total_non_re` — i.e. target vs. the FULL actual total
	including Unsorted money, so an un-classified balance honestly widens the overall gap rather
	than vanishing from the total the way it already vanishes from any per-Sub-Cat target. Not
	spelled out in the ACs; a different aggregation (excluding Unsorted from the total gap too)
	would also have been defensible.

	AC5 (reverses the pre-SELF-238 spec) — $ReAlloc / %Target / $Target render NEUTRAL via
	`.val-target` (design-system-spec.md §5 fence 1, screen.css `.val-target`). No pos/neg color,
	no over/under indicator, gauge, or arrow anywhere in this table. %Alloc / $Alloc are plain
	`.num` — AC5 names only the three target-comparison columns, so only those three carry the
	class (functionally identical color either way; kept faithful to the letter of the AC for a
	clean DOM-test surface).

	AC6 — when `total_non_re <= 0`, every ratio column (%Target/%Alloc/$Target/$ReAlloc) renders
	"—" via `ratioColumnsUnset()` + `fmtRatio*()` — computed from `total_non_re` itself, never
	trusting a raw per-cell value (see $lib/nonre-allocation.ts's file-header note: this render
	layer enforces AC6 independently of whatever Backend's own contract sends, as a second,
	redundant implementation of the same rule — belt-and-suspenders on a financial-correctness
	surface, not a gap-filler as of SELF-239). $Alloc always renders. One explanatory line
	(`.ratio-unset-note`, cause-neutral, PM-adjacent — draft copy, not yet PM-reviewed) appears
	directly under the header when this state is active.

	AC8 — no inline edit affordance anywhere in this table: every data cell is plain text, no
	<input>/<button>/<select>/[contenteditable]. %Target cells carry `.val-target` (fence 5,
	static-value-only).

	AC9 — the "Edit allocation targets" action lives in this table's own header, routing to
	`/settings/allocation` (the SELF-242 editor's default default `editHref` prop) via a plain
	navigation `<a>` — never a form/button that mutates anything on THIS page.

	AC11 — staleness per §2.4.4 / ADR-013 D1, TWO parts:
	  (1) SECTION-level `StaleConstituentBadge` fed by the whole-tenant `staleness` prop (the SAME
	      aggregate primitive root's dashboard + NavCompositionTable already consume — StaleConstituentBadge's
	      own module header already lists §2.2.2 as a planned V1.1+ ramp target). WORKING TODAY.
	  (2) PER-ROW inline `.stale-tag` + `tr.stale-row` tint (screen.css's own D1 shape — "tag + faint
	      row tint (informational, on aggregation rows)", distinct from NavCompositionTable's
	      leaf-level italic-text-only treatment) keyed on `AllocationRow.is_stale`. TRI-STATE,
	      mirroring NavCompositionLeaf: `true` → tag + `tr.stale-row` tint; `null` → quiet
	      "Staleness unknown" text, no tint; `undefined`/`false` → nothing. DORMANT until Backend
	      adds the per-row join (nonReAllocation.ts has no such join yet — flagged at hand-off);
	      the markup + CSS are real and tested now so wiring it later is a data-only change.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import type { NonReAllocation } from '$lib/nonre-allocation';
	import { groupsToRender, ratioColumnsUnset, groupSubtotal, fmtRatioPct, fmtRatioUsd } from '$lib/nonre-allocation';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B)-style discipline (mirrors StaleConstituentBadge / NavCompositionTable): both props
	// REQUIRED, no default — a caller that forgets to thread real data fails at TYPECHECK, not as
	// a silent "confirmed healthy" / empty-table fallback.
	let {
		allocation,
		staleness,
		editHref = '/settings/allocation'
	}: {
		allocation: NonReAllocation;
		staleness: StalenessData;
		editHref?: string;
	} = $props();

	const groups = $derived(groupsToRender(allocation.groups));
	const unsetRatios = $derived(ratioColumnsUnset(allocation.total_non_re));

	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});

	// AC4 grand totals — foot to `allocation.total_non_re` (the authoritative anchor for $Alloc;
	// see the module header's JUDGMENT CALL note on $ReAlloc).
	const groupSubtotals = $derived(groups.map((g) => groupSubtotal(g.rows)));
	const grandPctTarget = $derived(groupSubtotals.reduce((s, gs) => s + gs.pct_target, 0));
	const grandDollarTarget = $derived(groupSubtotals.reduce((s, gs) => s + gs.dollar_target, 0));
	const grandDollarAlloc = $derived(
		groupSubtotals.reduce((s, gs) => s + gs.dollar_alloc, 0) + (allocation.unsorted?.dollar_alloc ?? 0)
	);
	const grandPctAlloc = $derived(
		allocation.total_non_re > 0 ? (grandDollarAlloc / allocation.total_non_re) * 100 : 0
	);
	const grandDollarRealloc = $derived(grandDollarTarget - allocation.total_non_re);
</script>

<section class="alloc" aria-labelledby="alloc-label">
	<header class="head">
		<h2 id="alloc-label" class="section-label">Non-RE Allocation</h2>
		<a class="edit-link" href={editHref}>Edit allocation targets</a>
	</header>

	<!-- AC11(1): section-level D1 marker, fed by the whole-tenant staleness read. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

	{#if unsetRatios}
		<!-- AC6: cause-neutral, one line — draft copy, PM/UX not yet consulted. -->
		<p class="ratio-unset-note" role="status">
			Percent and target comparisons aren't shown below because your Non-RE holdings currently
			total zero or less — dollar values are still accurate.
		</p>
	{/if}

	<div class="table-scroll">
		<table class="alloc-tbl">
			<caption class="sr-only"
				>Non-RE allocation by category and sub-category, target vs. actual.</caption
			>
			<thead>
				<tr>
					<th scope="col">Cat / Sub-Cat</th>
					<th scope="col" class="num">% Target</th>
					<th scope="col" class="num">% Alloc</th>
					<th scope="col" class="num">$ Target</th>
					<th scope="col" class="num">$ Alloc</th>
					<th scope="col" class="num">$ ReAlloc</th>
				</tr>
			</thead>

			{#each groups as g, gi (g.cat)}
				{@const sub = groupSubtotals[gi]}
				<tbody class="group">
					<tr class="group-row">
						<th scope="colgroup" colspan="6" class="grp-cell">{g.cat}</th>
					</tr>

					{#if g.rows.length === 0}
						<tr class="is-empty">
							<td colspan="6">No Sub-Cats in this group.</td>
						</tr>
					{/if}

					{#each g.rows as row (row.sub_cat_id ?? row.sub_cat)}
						<tr class:stale-row={row.is_stale === true}>
							<td class="rowlabel">
								{row.sub_cat}
								<!-- AC11(2): per-row TRI-STATE marker — dormant until Backend wires is_stale. -->
								{#if row.is_stale === true}
									<span
										class="stale-tag"
										title="This Sub-Cat includes possibly-stale account data.">May be stale</span
									>
								{:else if row.is_stale === null}
									<span class="stale-unknown"
										title="Couldn't confirm whether this Sub-Cat includes stale account data."
										>Staleness unknown</span
									>
								{/if}
							</td>
							<td class="num val-target">{fmtRatioPct(row.pct_target, allocation.total_non_re)}</td>
							<td class="num">{fmtRatioPct(row.pct_alloc, allocation.total_non_re)}</td>
							<td class="num val-target">{fmtRatioUsd(row.dollar_target, allocation.total_non_re, usd)}</td>
							<td class="num">{usd.format(row.dollar_alloc)}</td>
							<td class="num val-target"
								>{fmtRatioUsd(row.dollar_realloc, allocation.total_non_re, usd)}</td
							>
						</tr>
					{/each}

					<tr class="subtotal">
						<th scope="row">{g.cat} subtotal</th>
						<td class="num val-target">{fmtRatioPct(sub.pct_target, allocation.total_non_re)}</td>
						<td class="num">{fmtRatioPct(sub.pct_alloc, allocation.total_non_re)}</td>
						<td class="num val-target">{fmtRatioUsd(sub.dollar_target, allocation.total_non_re, usd)}</td>
						<td class="num">{usd.format(sub.dollar_alloc)}</td>
						<td class="num val-target">{fmtRatioUsd(sub.dollar_realloc, allocation.total_non_re, usd)}</td>
					</tr>
				</tbody>
			{/each}

			{#if allocation.unsorted}
				{@const u = allocation.unsorted}
				<tbody class="group unsorted">
					<tr class="group-row">
						<th scope="colgroup" colspan="6" class="grp-cell">Unsorted</th>
					</tr>
					<tr class:stale-row={u.is_stale === true}>
						<td class="rowlabel">
							{u.sub_cat}
							{#if u.is_stale === true}
								<span class="stale-tag" title="This Sub-Cat includes possibly-stale account data."
									>May be stale</span
								>
							{:else if u.is_stale === null}
								<span
									class="stale-unknown"
									title="Couldn't confirm whether this Sub-Cat includes stale account data."
									>Staleness unknown</span
								>
							{/if}
						</td>
						<td class="num val-target">{fmtRatioPct(u.pct_target, allocation.total_non_re)}</td>
						<td class="num">{fmtRatioPct(u.pct_alloc, allocation.total_non_re)}</td>
						<td class="num val-target">{fmtRatioUsd(u.dollar_target, allocation.total_non_re, usd)}</td>
						<td class="num">{usd.format(u.dollar_alloc)}</td>
						<td class="num val-target">{fmtRatioUsd(u.dollar_realloc, allocation.total_non_re, usd)}</td>
					</tr>
				</tbody>
			{/if}

			<tbody class="ladder">
				<tr class="foot">
					<th scope="row">Total Non-RE</th>
					<td class="num val-target">{fmtRatioPct(grandPctTarget, allocation.total_non_re)}</td>
					<td class="num">{fmtRatioPct(grandPctAlloc, allocation.total_non_re)}</td>
					<td class="num val-target">{fmtRatioUsd(grandDollarTarget, allocation.total_non_re, usd)}</td>
					<td class="num">{usd.format(allocation.total_non_re)}</td>
					<td class="num val-target">{fmtRatioUsd(grandDollarRealloc, allocation.total_non_re, usd)}</td>
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
	/* Reproduces the locked screen.css `.btn.secondary` look, as a plain navigation <a> (AC9 is a
	   route, never a form action). Locally scoped, tokens only — same convention NavCompositionTable
	   uses for reproducing screen.css classes it needs. */
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

	/* AC6 explanatory note — informational register, not the canary hue (this is a math state,
	   not a staleness/re-auth signal). */
	.ratio-unset-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css `table.tbl` with tokens only. */
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

	/* Cat-group header row — reproduces screen.css's `.group-row` (uppercase, muted, surface-alt2). */
	.group-row th {
		background: var(--c-surface-alt2);
		font-size: var(--fs-small);
		letter-spacing: 0.04em;
		text-transform: uppercase;
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}

	.alloc-tbl tbody tr.is-empty td {
		color: var(--c-text-muted);
		font-style: italic;
		text-align: center;
	}

	/* AC4 — subtotal (bold + top divider) and Total foot (locked tr.foot look), reproducing
	   screen.css verbatim. */
	tr.subtotal th,
	tr.subtotal td {
		border-top: 1px solid var(--c-border-strong);
		font-weight: var(--weight-semi);
	}
	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}

	/* AC5 fence 1 (§2.3 non-goal): .val-target keeps target/$ReAlloc/%Target cells NEUTRAL —
	   identical ink to a plain cell; no pos/neg, no comparative color, ever. */
	.val-target {
		color: var(--c-text-primary);
	}

	/* AC11(2) — screen.css's own D1 shape: inline tag + faint row tint (informational). Locally
	   reproduced verbatim (tokens only) — dormant until Backend wires per-row is_stale. */
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
	/* UNKNOWN tri-state — quiet, muted register, NEVER the canary hue (mirrors
	   NavCompositionTable's .leaf-stale-unknown / StaleConstituentBadge's "unknown" branch: "we
	   don't know" must read calmer than "this is stale"). No row tint for this state either — a
	   tint asserts something IS wrong, which an unconfirmed row does not warrant. */
	.stale-unknown {
		display: inline-block;
		margin-left: var(--space-2);
		font-style: italic;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
</style>
