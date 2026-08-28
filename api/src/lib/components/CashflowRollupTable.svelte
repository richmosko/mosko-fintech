<!--
	CashflowRollupTable.svelte — the §2.3.2.b cross-account cash-flow rollup table (SELF-251).
	Frontend-owned browser surface. Consumes the ratified `CashflowCrossAccountRollup` shape
	($lib/cashflow-rollup.ts, a browser-safe mirror of Backend's SELF-250
	cashflowCrossAccountRollup.ts wrapper); authors NO server logic and performs NO re-derivation
	of any reader rule (netting/exclusion/classification predicates) — every number rendered here
	is exactly what the server computed.

	SHAPE (2 sections, in order, per AC1): Income → Expenses. Each section is its OWN table:
	  - a header caption (section label + target value, AC2) with NO caption when the target is
	    NULL (a stored $0 target still gets a caption — only NULL suppresses it);
	  - flat Sub-Cat rows (AC3 — no Cat-group headers, no Cat-level subtotals: `093`'s own reader
	    already resolved these sections at the Cat level, so there is no group tier left to render);
	  - six period columns, Month emphasized (AC4);
	  - one Total foot row that sums DOWN each column only (AC5 — the columns overlap, so a
	    cross-column sum would be actively wrong; `section.total` is rendered as-is, never re-summed
	    here) and carries the "partial — N unclassified" footnote iff N > 0 (AC9);
	  - AC6: no actual-vs-target delta, no over/under color — every cell here is a flat, static
	    currency render, tokens only.
	  - AC10: a negative total/row renders with its REAL sign — `fmtPeriodCell` (cashflow-
	    rollup.ts) never calls `Math.abs()`; `Intl.NumberFormat`'s own currency formatting already
	    renders a leading minus.

	AC9 — ONE-SOURCE BANNER: `unclassified.count_ytd` (N) arrives in the SAME payload as every sum
	above (093's own contract — see cashflowCrossAccountRollup.ts's AC8 note). This component
	issues NO second request and derives N nowhere else: the banner above the sections and every
	section's "partial" footnote read the SAME `unclassified.count_ytd` prop value. Both render iff
	N > 0, both absent at N = 0. CTA routes to `classifyHref` (default `/accounts` — see the
	module's own header note on why: SELF-249 built classification INLINE on per-account
	transaction lists, not as a dedicated queue page, so there is no single "classification
	surface" URL to deep-link to yet; `/accounts` is the best-available entry point pending a real
	§2.3.1 queue surface — flagged at hand-off, not a silent guess).

	AC11 / SELF-258 SEAM: the section-level `StaleConstituentBadge` this surface will eventually
	carry (`docs/records/v13-preflight/rederived-acs.md`'s SELF-258 AC1 — dispatched AFTER this
	issue) is NOT wired here. Each section header below carries an explicit HTML-comment seam
	marking exactly where that badge mounts once SELF-258 lands — see the two
	`SELF-258 seam` comments in the markup. Nothing renders at that seam today (a real
	`StaleConstituentBadge` mount, per its own Sec F3(B) ruling, requires REQUIRED non-default
	`isStale`/`staleItems` props this component has no source for yet — wiring a fake/undefined
	value here would be worse than leaving the seam visibly marked).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import {
		sectionsToRender,
		sectionTargetCaption,
		fmtPeriodCell,
		type CashflowCrossAccountRollup
	} from '$lib/cashflow-rollup';

	let {
		rollup,
		classifyHref = '/accounts',
		editTargetsHref = '/settings/cash-flow-targets'
	}: {
		rollup: CashflowCrossAccountRollup;
		/** AC9 CTA target — see the module header for why this defaults to `/accounts`. */
		classifyHref?: string;
		/** AC7 — routes to the SELF-252 editor, which does not exist yet; a 404 there is expected
		 *  and is this issue's own AC (routing only). */
		editTargetsHref?: string;
	} = $props();

	const sections = $derived(sectionsToRender(rollup.sections));
	const unclassifiedCount = $derived(rollup.unclassified.count_ytd);

	// Whole-dollar USD, no signDisplay override — AC10's real-sign requirement is already
	// satisfied by Intl's own default negative rendering (a leading minus), and AC6 forbids any
	// delta styling a forced "+" on positives would suggest.
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
</script>

<section class="cashflow" aria-labelledby="cashflow-label">
	<header class="head">
		<h2 id="cashflow-label" class="section-label">Cash Flow</h2>
		<a class="edit-link" href={editTargetsHref}>Edit cash-flow targets</a>
	</header>

	<!-- AC9 — the S-2 unclassified banner. Single-source with every section footnote below: both
	     read `rollup.unclassified.count_ytd` and nothing else. -->
	{#if unclassifiedCount > 0}
		<div class="unclassified-banner" role="status">
			<span class="unclassified-tag">
				<span class="unclassified-dot" aria-hidden="true"></span>
				<span class="unclassified-text">{unclassifiedCount} items unclassified</span>
			</span>
			<span class="unclassified-sep" aria-hidden="true">—</span>
			<a class="unclassified-cta" href={classifyHref}>classify</a>
		</div>
	{/if}

	{#each sections as section (section.cat)}
		{@const caption = sectionTargetCaption(section, rollup.targets, usd)}
		<div class="table-scroll">
			<table class="cf-tbl">
				<caption class="section-caption">
					<span class="caption-label">{section.label}</span>
					{#if caption}
						<span class="caption-target">{caption}</span>
					{/if}
				</caption>
				<!-- SELF-258 seam: <StaleConstituentBadge> mounts here, adjacent to this section's
				     own caption, once the §2.3.x staleness ramp (SELF-258 AC1) lands. Renders
				     nothing today — see this file's own module header. -->
				<thead>
					<tr>
						<th scope="col">Sub-Cat</th>
						<th scope="col" class="num month">Month</th>
						<th scope="col" class="num">Q1</th>
						<th scope="col" class="num">Q2</th>
						<th scope="col" class="num">Q3</th>
						<th scope="col" class="num">Q4</th>
						<th scope="col" class="num">YTD</th>
					</tr>
				</thead>

				<tbody>
					{#if section.rows.length === 0}
						<tr class="is-empty">
							<td colspan="7">No Sub-Cats in this section.</td>
						</tr>
					{/if}
					{#each section.rows as row (row.sub_cat)}
						<tr>
							<td class="rowlabel">{row.sub_cat}</td>
							<td class="num month">{fmtPeriodCell(row.month, usd)}</td>
							<td class="num">{fmtPeriodCell(row.q1, usd)}</td>
							<td class="num">{fmtPeriodCell(row.q2, usd)}</td>
							<td class="num">{fmtPeriodCell(row.q3, usd)}</td>
							<td class="num">{fmtPeriodCell(row.q4, usd)}</td>
							<td class="num">{fmtPeriodCell(row.ytd, usd)}</td>
						</tr>
					{/each}
				</tbody>

				<tfoot>
					<tr class="foot">
						<th scope="row">
							Total
							<!-- AC9 footnote — same single-source count as the banner above. -->
							{#if unclassifiedCount > 0}
								<span class="footnote">partial — {unclassifiedCount} unclassified</span>
							{/if}
						</th>
						<td class="num month">{fmtPeriodCell(section.total.month, usd)}</td>
						<td class="num">{fmtPeriodCell(section.total.q1, usd)}</td>
						<td class="num">{fmtPeriodCell(section.total.q2, usd)}</td>
						<td class="num">{fmtPeriodCell(section.total.q3, usd)}</td>
						<td class="num">{fmtPeriodCell(section.total.q4, usd)}</td>
						<td class="num">{fmtPeriodCell(section.total.ytd, usd)}</td>
					</tr>
				</tfoot>
			</table>
		</div>
	{/each}
</section>

<style>
	.cashflow {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
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
	/* Reproduces NonReAllocationTable's `.edit-link` (locked screen.css `.btn.secondary` look)
	   verbatim — same convention, tokens only. */
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

	/* AC9 — the S-2 banner. Reuses the RESERVED canary --c-attn-* register (StaleConstituentBadge /
	   UnpricedMarker's own vocabulary) — a genuine, actionable, financially-material fact about
	   this render, same register as those two markers (§5 fence 8). */
	.unclassified-banner {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
		align-self: flex-start;
	}
	.unclassified-tag {
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
	.unclassified-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		flex: 0 0 auto;
	}
	.unclassified-cta {
		color: var(--c-attn-text);
		font-weight: var(--weight-semi);
		text-decoration: underline;
		white-space: nowrap;
	}
	.unclassified-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css `table.tbl` with tokens only, matching
	   NonReAllocationTable / NavCompositionTable's own reproduction. */
	.cf-tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.cf-tbl th,
	.cf-tbl td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.cf-tbl thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.cf-tbl td.num,
	.cf-tbl th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.cf-tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}
	.cf-tbl tbody tr.is-empty td {
		color: var(--c-text-muted);
		font-style: italic;
		text-align: center;
	}

	/* Section caption (AC2) — label + optional target, rendered as the table's own <caption> (an
	   accessible-name element, not a decorative heading) so AT announces it as the table's title. */
	.section-caption {
		caption-side: top;
		text-align: left;
		padding: 0 0 var(--space-2) 0;
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.caption-label {
		font-weight: var(--weight-semi);
	}
	.caption-target {
		margin-left: var(--space-2);
		font-weight: var(--weight-reg);
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
	}

	/* AC4 — Month column visually emphasized: bolder + bg tint, both via existing tokens
	   (`--weight-semi` / `--c-surface-alt2` — the SAME "emphasized band" tint
	   NonReAllocationTable's `.group-row` / this app's own accounts/allocation/root pages already
	   use for an emphasized row; applied here to a COLUMN instead of a row). No new token. */
	.cf-tbl th.month,
	.cf-tbl td.month {
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt2);
	}

	/* AC5 / AC9 — Total foot row (locked tr.foot look, reproduced verbatim from
	   NonReAllocationTable / NavCompositionTable). */
	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}
	/* The Month column's own tint still shows through the foot row's emphasis rather than being
	   overridden by it — foot cells keep their own background per-cell via specificity below. */
	tr.foot td.month {
		background: color-mix(in srgb, var(--c-surface-alt) 50%, var(--c-surface-alt2));
	}

	/* AC9 footnote — quiet, informational register (a math/process state, not a staleness/re-auth
	   signal) — mirrors NonReAllocationTable's `.ratio-unset-note` register choice. */
	.footnote {
		display: block;
		margin-top: var(--space-1);
		font-size: var(--fs-small);
		font-weight: var(--weight-reg);
		font-style: italic;
		color: var(--c-text-muted);
	}
</style>
