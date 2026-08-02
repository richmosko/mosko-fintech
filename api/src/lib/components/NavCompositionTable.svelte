<!--
	NavCompositionTable.svelte — the §2.1.5 NAV-composition build-up (SELF-226 · V1.1).
	Frontend-owned browser surface. Consumes the ratified `fn_nav_composition` JSONB
	(migration 051) threaded through `+page.server.ts` as `data.composition`; authors NO
	server logic. Presentational shell over the types + ladder ordering in $lib/nav-composition.

	The "composition foot" of the single-canvas §2.1 surface (P2 dense number-first): it sits
	below the SELF-211 NAV headline on the root dashboard.

	RATIFIED SHAPE (F/CTO 2026-08-02):
	  • 3 visual tiers (AC#4 · VD Item A, F/CTO-ratified): category group-header (normal row band,
	    BOLD label + caret disclosure, row-hover) < buildup .subtotal (border-top-strong delimiter)
	    < NAV .foot (2px border, bold, surface-alt) — tokens only (screen.css not loaded app-side).
	  • Collapse default COLLAPSED (AC#2): each category is a keyboard-native <button
	    aria-expanded> disclosure (StaleConstituentBadge pattern) expanding ONE level to leaf
	    rows. Buildup ladder + NAV foot are always visible.
	  • Leaf account-name links to /accounts/[account_id] (AC#3 / D1 — the drill-down exists,
	    SELF-321), via --c-link.
	  • VALUE-COLOR FENCE: --c-pos/--c-neg is ACTUAL-performance only → applied ONLY to the
	    Unrealized G/L column. Positions (current value, negative liability subtotals, the
	    Debt subtraction, a negative NAV) render in NEUTRAL ink (design-system-spec §5 fence 1).
	  • Debt/tax signs (D5/D7): Debt row = −magnitude (subtraction); tax rows = `$0` + a V1.4
	    caption (AC#6). Empty categories are omitted upstream → simply absent (D3).
	  • Whole-dollar, tabular-nums (D9): the NAV foot reads identical to the §2.1.1 headline and
	    subtotals never appear off-by-rounding.

	Per-row STALENESS is deferred to SELF-229 (D4) — the JSONB carries no staleness flags yet.
	Tokens only (var(--c-*)); no hardcoded hex/px-spacing/font (ADR-013 P5).
-->
<script lang="ts">
	import type { NavComposition } from '$lib/nav-composition';
	import { buildupRows } from '$lib/nav-composition';
	import { accountTypeLabel } from '$lib/account-display';

	let { composition }: { composition: NavComposition } = $props();

	const groups = $derived(composition.groups);
	const ladder = $derived(buildupRows(composition.buildups));

	// Whole-dollar USD — matches the §2.1.1 headline so the NAV foot reads identical to it
	// (foot-to-NAV visual consistency; the exactness is a backend invariant on the raw numbers).
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
	// Unrealized G/L is ACTUAL performance → signed (+/−); the value-color fence applies to it.
	const usdSigned = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0,
		signDisplay: 'exceptZero'
	});

	// Default COLLAPSED (AC#2): categories start closed; expand one level to leaf rows.
	let open = $state<Record<string, boolean>>({});
	function toggle(key: string) {
		open[key] = !open[key];
	}
</script>

<div class="table-scroll">
	<table class="comp">
		<caption class="sr-only">Net worth composition by account category, with the build-up to net assets value.</caption>
		<thead>
			<tr>
				<th scope="col">Account / group</th>
				<th scope="col" class="num">Current value</th>
				<th scope="col" class="num">Unrealized G/L</th>
			</tr>
		</thead>

		{#each groups as g (g.category)}
			{@const isOpen = open[g.category] ?? false}
			<tbody class="group" id={`comp-grp-${g.category}`}>
				<tr class="group-head">
					<th scope="row" class="grp-cell">
						<button
							type="button"
							class="grp-toggle"
							aria-expanded={isOpen}
							aria-controls={`comp-grp-${g.category}`}
							onclick={() => toggle(g.category)}
						>
							<span class="disclosure" aria-hidden="true">{isOpen ? '▾' : '▸'}</span>
							<span class="grp-label">{accountTypeLabel(g.category)}</span>
						</button>
					</th>
					<td class="num">{usd.format(g.subtotal)}</td>
					<!-- Group-level G/L is not in the contract → left blank (never invented). -->
					<td class="num"></td>
				</tr>

				{#if isOpen}
					{#each g.accounts as a (a.account_id)}
						<tr class="leaf">
							<td class="indent">
								<a class="leaf-link" href={`/accounts/${a.account_id}`}>{a.account_name}</a>
							</td>
							<td class="num">{usd.format(a.current_market_value)}</td>
							<td
								class="num gl"
								class:pos={a.unrealized_gl != null && a.unrealized_gl > 0}
								class:neg={a.unrealized_gl != null && a.unrealized_gl < 0}
							>
								{a.unrealized_gl == null ? '—' : usdSigned.format(a.unrealized_gl)}
							</td>
						</tr>
					{/each}
				{/if}
			</tbody>
		{/each}

		<tbody class="ladder">
			{#each ladder as row (row.key)}
				<tr class="subtotal">
					<th scope="row">
						{row.label}
						{#if row.isTaxPlaceholder}
							<!-- AC#6 / D7 (VD Item B): extend the §2.5 source tag with the V1.4 trace.
							     $0 stays a clean tabular value in the num column; this prose lives left. -->
							<span class="tax-note">(from §2.5) · full estimate arrives in V1.4</span>
						{/if}
					</th>
					<td class="num">{row.isTaxPlaceholder ? usd.format(0) : usd.format(row.displayValue)}</td>
					<td class="num"></td>
				</tr>
			{/each}
			<tr class="foot">
				<th scope="row">Net Assets Value (NAV)</th>
				<td class="num">{usd.format(composition.nav)}</td>
				<td class="num"></td>
			</tr>
		</tbody>
	</table>
</div>

<style>
	/* Accessible-name-only caption (visually hidden; keeps the table named for AT). */
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

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css table.tbl with tokens only. */
	.comp {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.comp th,
	.comp td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.comp thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.comp td.num,
	.comp th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}

	/* ── Tier 1 — category group header (VD Item A). A NORMAL row band (base 1px --c-border
	   bottom, no top border) with a BOLD label + caret; clickable → row hover; value neutral. ── */
	.group-head:hover th,
	.group-head:hover td {
		background: var(--c-surface-alt);
	}
	.group-head td.num {
		color: var(--c-text-primary);
	}
	.grp-toggle {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		background: none;
		border: none;
		padding: 0;
		margin: 0;
		cursor: pointer;
		font: inherit;
		color: var(--c-text-primary);
	}
	.grp-toggle:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	.grp-label {
		font-weight: var(--weight-bold);
	}
	.disclosure {
		color: var(--c-text-muted);
	}

	/* ── Leaf account rows. ────────────────────────────────────────────────────── */
	.leaf td.indent {
		padding-left: var(--space-5);
	}
	.comp tbody tr.leaf:hover td {
		background: var(--c-surface-alt);
	}
	.leaf-link {
		color: var(--c-link);
		text-decoration: none;
	}
	.leaf-link:hover {
		text-decoration: underline;
	}
	.leaf-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	/* VALUE-COLOR FENCE (§5 fence 1): pos/neg ONLY on the Unrealized G/L column. */
	.gl.pos {
		color: var(--c-pos);
	}
	.gl.neg {
		color: var(--c-neg);
	}

	/* ── Tier 2 — buildup subtotals (locked tr.subtotal). ──────────────────────── */
	tr.subtotal th,
	tr.subtotal td {
		border-top: 1px solid var(--c-border-strong);
		font-weight: var(--weight-semi);
	}
	/* The V1.4 tax caption (AC#6 / VD Item B): quiet sub-line beneath the row label. Muted,
	   fs-small, regular weight, roman (NOT italic — italic is reserved for .disclaimer/empty). */
	.tax-note {
		display: block;
		margin-top: var(--space-1);
		font-size: var(--fs-small);
		font-weight: var(--weight-reg);
		color: var(--c-text-muted);
	}

	/* ── Tier 3 — NAV foot (locked tr.foot; dominant, echoes the §2.1.1 headline). ── */
	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}
</style>
