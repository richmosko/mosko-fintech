<!--
	CashflowPerAccountTable.svelte — the §2.3.3 per-account cash-flow drill-down table (SELF-254
	AC1/AC2/AC7). Frontend-owned browser surface. Consumes the ratified `CashflowPerAccount` shape
	($lib/cashflow-per-account.ts, a browser-safe mirror of Backend's SELF-253
	cashflowPerAccount.ts wrapper); authors NO server logic and performs NO re-derivation of any
	reader rule — every number rendered here is exactly what `094` computed.

	SHAPE (3 sections, in order, per AC1): Income → Other Cash Flows → Expenses. Each section is
	its OWN table — same 6-column structure, flat Sub-Cat rows, Month-emphasized, one Total foot
	row summing DOWN each column only (AC2, the §2.3.2 idiom). ⚠ NO target caption (AC7 of
	cashflowPerAccount.ts's own contract — targets are §2.3.2 aggregate concepts that do not attach
	to a single-account scope); each caption is a PLAIN label only.

	COMPONENT REUSE — DELIBERATELY A SEPARATE FILE FROM CashflowRollupTable.svelte, not a shared
	base: this codebase's own established convention is that each table component reproduces the
	locked base-table CSS independently rather than sharing it (CashflowRollupTable's own header
	names NonReAllocationTable / NavCompositionTable as prior instances of the SAME reproduction,
	not a shared component) — three sections vs two, a per-row `cat` identity, no `targets` prop,
	a per-account `classifyHref`, and the AC8 honest-transfer note together make this table's
	OUTER shape different enough that forcing a shared component would be the param explosion the
	frontend-engineer brief warns against, not a cleanup. The one genuinely shape-agnostic piece —
	`fmtPeriodCell` — IS reused, imported from cashflow-rollup.ts rather than re-derived.

	AC7 — ONE-SOURCE BANNER, verbatim copy ("N items unclassified — classify"): `unclassified.count_ytd`
	arrives in the SAME payload as every sum above (`094`'s own contract — see
	cashflowPerAccount.ts's module header). This component issues NO second request and derives N
	nowhere else. CTA routes to `classifyHref` (the account's own transaction list — SELF-249's
	inline classify UI — not the generic `/accounts` §2.3.2 fallback, since this surface already
	knows which account it's showing).

	The `other_cash_flows` section additionally renders `otherCashFlowsNote` beneath its caption —
	threaded from `+page.server.ts`'s page data, which is the ONLY module that may import
	`CASHFLOW_OTHER_CASH_FLOWS_NOTE` (cashflowSections.ts is Backend-owned, `$lib/server/**`,
	unreachable from this browser component) — this component renders whatever string arrives,
	never a second hand-copy of the sentence.

	AC9 / SELF-258 SEAM: no live `StaleConstituentBadge` mount — see the `SELF-258 seam` comment
	below, mirroring CashflowRollupTable's own seam marker verbatim.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { sectionsToRender, type CashflowPerAccount } from '$lib/cashflow-per-account';
	import { fmtPeriodCell } from '$lib/cashflow-rollup';

	let {
		drilldown,
		classifyHref,
		otherCashFlowsNote
	}: {
		drilldown: CashflowPerAccount;
		/** AC7 CTA target — this account's own transaction list (SELF-249 inline classify UI). */
		classifyHref: string;
		/** AC8 of cashflowSections.ts — the one home for this copy; rendered, never paraphrased. */
		otherCashFlowsNote: string;
	} = $props();

	const sections = $derived(sectionsToRender(drilldown.sections));
	const unclassifiedCount = $derived(drilldown.unclassified.count_ytd);

	// Whole-dollar USD, no signDisplay override — a negative total/row renders with its REAL sign
	// (Intl's own default negative rendering already does this; NEVER Math.abs() anywhere here —
	// 094's own header: the other_cash_flows section has no normal balance, and abs() would hide
	// half of it).
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
</script>

<section class="cashflow-detail" aria-label="Cash flow by category">
	<!-- AC7 — the S-2 unclassified banner. Single-source with every section footnote below: both
	     read `drilldown.unclassified.count_ytd` and nothing else. -->
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

	{#each sections as section (section.sectionKey)}
		<div class="table-scroll">
			<table class="cf-tbl">
				<caption class="section-caption">
					<span class="caption-label">{section.label}</span>
				</caption>
				<!-- SELF-258 seam: <StaleConstituentBadge> mounts here, adjacent to this section's
				     own caption, once the §2.3.x staleness ramp (SELF-258 AC1) lands. Renders
				     nothing today — mirrors CashflowRollupTable.svelte's own seam verbatim. -->
				<thead>
					{#if section.sectionKey === 'other_cash_flows'}
						<!-- AC8 of cashflowSections.ts — the honest-transfer note, this file's ONE
						     render site. Not a caption (it's prose, not a target value) — a note row
						     ahead of the column headers, inside <thead> (a bare <tr> is not valid
						     directly inside <table>, and this row is header-adjacent context, not
						     a data row). -->
						<tr class="section-note-row"><td colspan="7" class="section-note">{otherCashFlowsNote}</td></tr>
					{/if}
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
					{#each section.rows as row (row.cat + '|' + row.sub_cat)}
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
							<!-- AC7 footnote — same single-source count as the banner above. -->
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
	.cashflow-detail {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	/* AC7 — the S-2 banner. Reuses the RESERVED canary --c-attn-* register, same as
	   CashflowRollupTable's AC9 banner (§5 fence 8). */
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
	   CashflowRollupTable / NonReAllocationTable / NavCompositionTable's own reproduction. */
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

	/* The honest-transfer note (AC8 of cashflowSections.ts) — a quiet, informational register, the
	   same one CashflowRollupTable's AC9 footnote uses for a process/context note that isn't a
	   staleness/re-auth signal. Rendered as a table row so it stays inside the same accessible
	   table structure as its section, ahead of the column headers. */
	.section-note-row td {
		border-bottom: none;
		padding: 0 var(--space-3) var(--space-2) var(--space-3);
	}
	.section-note {
		font-size: var(--fs-small);
		font-style: italic;
		color: var(--c-text-muted);
	}

	.cf-tbl th.month,
	.cf-tbl td.month {
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt2);
	}

	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}
	tr.foot td.month {
		background: color-mix(in srgb, var(--c-surface-alt) 50%, var(--c-surface-alt2));
	}

	.footnote {
		display: block;
		margin-top: var(--space-1);
		font-size: var(--fs-small);
		font-weight: var(--weight-reg);
		font-style: italic;
		color: var(--c-text-muted);
	}
</style>
