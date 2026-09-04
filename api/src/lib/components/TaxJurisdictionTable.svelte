<!--
	TaxJurisdictionTable.svelte — one §2.5.3.b jurisdiction's quarterly estimated-tax table
	(SELF-266). Frontend-owned browser surface. Presentational shell over $lib/tax-quarterly;
	authors NO server logic and performs NO re-derivation of any tax math — every figure rendered
	here is exactly what ADR-067 Decision 5's payload carries. Instantiated twice by
	routes/taxes/quarterly/+page.svelte — once per `TaxJurisdictionKey` — the two tables ARE the
	"two parallel tables" the issue title names; this component owns one of them.

	ROW SHAPE (dispatch item 1, PRD §2.5.3): Tax Balance Prior Year (informational only, μ-2 — never
	drives anything below it) · four installment rows with their own due dates (never Federal's
	dates assumed for California — `installment.due_date` is read per row) · a Sub-Total row that is
	the SUM of the first `installments_due_through_next` installment amounts (never a multiply — see
	`subTotalThroughNext`'s own header) · YTD Paid · Estimated Funds Due, which closes the table and
	renders a negative (overpayment) on the SAME line, sign-flipped, no separate refund row (ν-1).

	AC3 / ξ-1 — CURRENT QUARTER EMPHASIS: `.current-row` on the one installment row whose `quarter`
	equals `installments_due_through_next` — that ordinal is already capped at 4 by the payload
	(ADR-067 Decision 5(i)), so it stays on the Q4 row through the whole Sep 16–Jan 15 window with
	no date logic duplicated here. Visual treatment mirrors CashflowRollupTable's AC4 Month-column
	emphasis (bolder + `--c-surface-alt2`), applied to a ROW instead of a column — same tokens, same
	"emphasized band" register already used app-wide, no new token invented.

	AC 7 / 7a (SELF-265's own AC, cited not restated) — a jurisdiction with NO usable schedule in
	ANY year (`status === 'unavailable'`, `reason === 'no_schedule_any_year'`) renders the
	UNAVAILABLE-with-a-reason empty state INSTEAD of the table body — never a table full of blank or
	`$0` cells. `next_due_date` still renders even here (Sec N-11 — a due date is true regardless of
	computability; deliberately NOT gated on `status`).

	AC 6(ii)/(iii) — the "no tax-authority account" empty state is TWO renders of the same fact at
	two granularities: the page (`TaxQuarterlyTables.svelte`) renders the page-level banner once
	when `noTaxAuthorityDesignated` is true; THIS component renders the narrower per-jurisdiction case
	inline on the YTD Paid row whenever `ytd_paid.reason === 'no_ledger_designated'` — which can fire
	even when the OTHER jurisdiction's ledger IS designated (federal/california designate
	independently), so it is not redundant with the page banner.

	AC 2a / R8 — the prior tax year's outstanding Q4 row, shown while `priorYearQ4` is non-null
	(the page's own `+page.server.ts` gates the SECOND `fn_compute_tax_liability` call — E39,
	`loadPriorYearQ4` — on `liability.prior_year_q4_window.open`, so a non-null prop here already
	means the window is open; this component re-checks nothing). Team-lead ruling (relayed after
	Backend's real loader landed): obligation (`priorYearQ4.{key}.q4_installment` — the Dec-31
	read's own last installment, never derived from the CURRENT year's rows) with the prior year's
	`annual_liability` as a secondary figure, and Funds Due (`priorYearQ4.{key}.funds_due_envelope`,
	verbatim) LABELLED "as of Dec 31, {prior year}" so it is never mistaken for a live number. NO
	YTD Paid cell in this block — R8's own rider (ADR-067 Decision 5(f)) states YTD Paid is the
	designated ledger's balance SINCE INCEPTION, not year-scoped, and the ruling is explicit that
	this block must not invent a prior-year-scoped one; a copy line instead tells the user where a
	January payment lands ("appears in {current tax year}'s YTD Paid").

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). No inline edit anywhere in this
	table (AC 8a) — every cell is plain text; the only interactive elements are the two CTA links.
-->
<script lang="ts">
	import {
		JURISDICTION_TABLE_TITLE,
		JURISDICTION_AUTHORITY_LABEL,
		subTotalThroughNext,
		isCurrentInstallmentRow,
		federalRateCaption,
		californiaRateCaption,
		basisYearNotes,
		standardDeductionIgnored,
		reasonCopy,
		fmtDueDate,
		type TaxJurisdictionPayload,
		type TaxJurisdictionKey,
		type PriorYearQ4
	} from '$lib/tax-quarterly';

	// Sec F3(B)-style discipline (mirrors StaleConstituentBadge / NonReAllocationTable): the payload
	// props are REQUIRED, no default — a caller that forgets to thread real data fails at
	// TYPECHECK, not as a silent "confirmed healthy" empty-table fallback. `priorYearQ4` IS allowed
	// to be null (that null IS the "window closed" state — see the module header) so it is typed
	// `PriorYearQ4 | null` rather than optional; a caller must decide, not omit.
	let {
		jurisdiction,
		jurisdictionKey,
		taxYear,
		priorYearQ4,
		editBracketsHref = '/settings/tax-brackets',
		designateAccountHref = '/accounts'
	}: {
		jurisdiction: TaxJurisdictionPayload;
		jurisdictionKey: TaxJurisdictionKey;
		taxYear: number;
		priorYearQ4: PriorYearQ4 | null;
		/** AC7 — routes to the SELF-265 editor. */
		editBracketsHref?: string;
		/** AC6(ii)/(iii) CTA target — the §2.4.2 account form's tax-authority field lives per-account
		 *  at /accounts/[account_id]; /accounts is the entry point (no dedicated queue page, same
		 *  reasoning CashflowRollupTable's `classifyHref` default documents for its own CTA). */
		designateAccountHref?: string;
	} = $props();

	const priorYearDetail = $derived(
		priorYearQ4 ? (jurisdictionKey === 'federal' ? priorYearQ4.federal : priorYearQ4.california) : null
	);

	const title = $derived(JURISDICTION_TABLE_TITLE[jurisdictionKey]);
	const authorityLabel = $derived(JURISDICTION_AUTHORITY_LABEL[jurisdictionKey]);
	const rateCaption = $derived(
		jurisdictionKey === 'federal'
			? federalRateCaption(jurisdiction)
			: californiaRateCaption(jurisdiction)
	);
	const basisNotes = $derived(basisYearNotes(jurisdiction, taxYear));
	const showDeductionNote = $derived(standardDeductionIgnored(jurisdiction));
	const subTotal = $derived(subTotalThroughNext(jurisdiction));

	// Whole-dollar USD — matches this app's house convention (NavCompositionTable / CashflowRollupTable
	// / NonReAllocationTable all format money whole-dollar; no 2dp departure invented here). Intl's
	// own default rendering already produces a leading minus for a negative (ν-1 overpayment; AC5) —
	// no signDisplay override, no Math.abs anywhere below.
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
</script>

<section class="jur-table" aria-labelledby="tax-{jurisdictionKey}-label">
	<header class="head">
		<h3 id="tax-{jurisdictionKey}-label" class="section-label">{title}</h3>
	</header>

	{#if jurisdiction.status === 'unavailable'}
		<!-- AC 7a (SELF-265's own shape, cited) — UNAVAILABLE-with-a-reason, never $0, never a blank
		     table. -->
		<div class="unavailable-block" role="status">
			<p class="unavailable-line">
				{reasonCopy(jurisdiction.reason ?? 'no_schedule_any_year')}
			</p>
			<!-- Sec N-11 — next_due_date is true regardless of computability; shown even here. -->
			<p class="unavailable-detail">
				Next installment due {fmtDueDate(jurisdiction.next_due_date)}.
			</p>
			<a class="cta-link" href={editBracketsHref}>Edit tax brackets</a>
		</div>
	{:else}
		<p class="rate-caption">{rateCaption}</p>
		{#each basisNotes as note (note.scheduleType)}
			<p class="basis-note">{note.text}</p>
		{/each}
		{#if showDeductionNote}
			<p class="basis-note">
				We ignored the standard deduction you entered for LT Capital Gains — the law provides none
				for that schedule.
			</p>
		{/if}

		{#if priorYearQ4 && priorYearDetail}
			<!-- AC 2a / R8 — prior tax year's outstanding Q4 (team-lead ruling, E39, relayed after
			     Backend's real loader landed): obligation (`q4_installment`, with the prior year's
			     `annual_liability` as a secondary figure) + the Dec-31 read's OWN Funds Due envelope,
			     labelled "as of Dec 31, {year}" so it is never mistaken for a live figure. NO YTD Paid
			     cell here — R8's rider keeps YTD Paid as the ledger balance as-of; this block does not
			     invent a prior-year-scoped one. The copy line states explicitly where a January
			     payment lands, since this table renders nothing for it otherwise. -->
			<div class="prior-q4" role="status">
				<div class="prior-q4-head">
					<span class="prior-q4-tag">
						<span class="prior-q4-dot" aria-hidden="true"></span>
						<span class="prior-q4-tag-text">{priorYearQ4.tax_year} Q4 still outstanding</span>
					</span>
					<span class="prior-q4-detail">
						Pay by {fmtDueDate(priorYearQ4.due_date)}. Payments made this January appear in {taxYear}'s
						YTD Paid.
					</span>
				</div>
				<table class="jur-tbl prior-q4-tbl">
					<caption class="sr-only">
						{title} — {priorYearQ4.tax_year} Q4, outstanding.
					</caption>
					<tbody>
						<tr>
							<th scope="row">Q4 {priorYearQ4.tax_year} Payment</th>
							<td class="num">
								{#if priorYearDetail.q4_installment === null}
									<span class="unavailable-cell">Unavailable</span>
								{:else}
									{usd.format(priorYearDetail.q4_installment)}
									{#if priorYearDetail.annual_liability !== null}
										<span
											class="prior-q4-annual"
											title="{priorYearQ4.tax_year} annual liability">
											({priorYearQ4.tax_year} annual: {usd.format(priorYearDetail.annual_liability)})
										</span>
									{/if}
								{/if}
							</td>
						</tr>
						<tr class="foot">
							<th scope="row">Funds Due (as of Dec 31, {priorYearQ4.tax_year})</th>
							<td class="num">
								{#if priorYearDetail.funds_due_envelope.status === 'computed'}
									{usd.format(priorYearDetail.funds_due_envelope.amount)}
								{:else}
									<span class="unavailable-cell"
										>{reasonCopy(priorYearDetail.funds_due_envelope.reason)}</span
									>
								{/if}
							</td>
						</tr>
					</tbody>
				</table>
			</div>
		{/if}

		<div class="table-scroll">
			<table class="jur-tbl">
				<caption class="sr-only">{title} — quarterly estimated payments for {taxYear}.</caption>
				<thead>
					<tr>
						<th scope="col">Item</th>
						<th scope="col">Due</th>
						<th scope="col" class="num">Amount</th>
					</tr>
				</thead>
				<tbody>
					<tr class="info-row">
						<th scope="row">Tax Balance Prior Year</th>
						<td>—</td>
						<td class="num">
							{jurisdiction.tax_balance_prior_year === null
								? 'Not entered'
								: usd.format(jurisdiction.tax_balance_prior_year)}
						</td>
					</tr>

					{#if jurisdiction.installments}
						{#each jurisdiction.installments as installment (installment.quarter)}
							<tr class:current-row={isCurrentInstallmentRow(installment, jurisdiction)}>
								<th scope="row">Q{installment.quarter} Estimated Payment</th>
								<td>{fmtDueDate(installment.due_date)}</td>
								<td class="num">{usd.format(installment.amount)}</td>
							</tr>
						{/each}
					{:else}
						<tr>
							<th scope="row">Estimated Payments</th>
							<td>{fmtDueDate(jurisdiction.next_due_date)}</td>
							<td class="num">Unavailable</td>
						</tr>
					{/if}

					<tr class="subtotal">
						<th scope="row">Sub-Total (through next due date)</th>
						<td></td>
						<td class="num">{subTotal === null ? 'Unavailable' : usd.format(subTotal)}</td>
					</tr>

					<tr>
						<th scope="row">YTD Paid</th>
						<td></td>
						<td class="num">
							{#if jurisdiction.ytd_paid.status === 'designated'}
								{usd.format(jurisdiction.ytd_paid.amount)}
							{:else}
								<span class="unavailable-cell">{reasonCopy(jurisdiction.ytd_paid.reason)}</span>
								{#if jurisdiction.ytd_paid.reason === 'no_ledger_designated'}
									<a class="cta-link inline" href={designateAccountHref}
										>Designate an {authorityLabel} account</a
									>
								{/if}
							{/if}
						</td>
					</tr>

					<tr class="foot">
						<th scope="row">Estimated Funds Due</th>
						<td></td>
						<td class="num">
							{#if jurisdiction.funds_due.status === 'computed'}
								{usd.format(jurisdiction.funds_due.amount)}
							{:else}
								<span class="unavailable-cell">{reasonCopy(jurisdiction.funds_due.reason)}</span>
							{/if}
						</td>
					</tr>
				</tbody>
			</table>
		</div>
	{/if}
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

	.jur-table {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		min-width: 0;
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
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}

	.rate-caption {
		margin: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
	}
	.basis-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		font-style: italic;
	}

	/* AC 7a — UNAVAILABLE-with-a-reason register (informational, not the canary hue: this is a
	   "not set up yet" state, not a confirmed staleness/attention signal). */
	.unavailable-block {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2);
		padding: var(--space-3);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.unavailable-line {
		margin: 0;
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.unavailable-detail {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}

	/* AC 2a — canary/attn register (§5 fence 8): a genuine, actionable, financially-material fact
	   about this render, same register StaleConstituentBadge / UnpricedMarker use. */
	.prior-q4 {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-2);
		border: 1px solid var(--c-attn-border);
		border-radius: var(--radius-md);
		background: var(--c-attn-bg);
	}
	.prior-q4-head {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-2);
	}
	.prior-q4-tag {
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		padding: var(--space-1) var(--space-2);
		border: 1px solid var(--c-attn-border);
		border-left: var(--space-1) solid var(--c-attn-solid);
		border-radius: var(--radius-sm);
		background: var(--c-surface);
		color: var(--c-attn-text);
		font: var(--weight-semi) var(--fs-small) / 1 var(--font-ui);
		white-space: nowrap;
	}
	.prior-q4-dot {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		flex: 0 0 auto;
	}
	.prior-q4-detail {
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-attn-text);
	}
	.prior-q4-annual {
		margin-left: var(--space-2);
		font-size: var(--fs-small);
		font-weight: var(--weight-reg);
		font-style: italic;
		color: var(--c-text-muted);
	}
	.prior-q4-tbl {
		background: var(--c-surface);
		border-radius: var(--radius-sm);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css `table.tbl` with tokens only, matching every
	   other Frontend-owned table in this codebase. */
	.jur-tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.jur-tbl th,
	.jur-tbl td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.jur-tbl thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.jur-tbl td.num,
	.jur-tbl th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.jur-tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}

	.info-row th,
	.info-row td {
		color: var(--c-text-secondary);
		font-weight: var(--weight-reg);
	}

	/* AC3 / ξ-1 — current-quarter emphasis. Same tokens CashflowRollupTable's AC4 Month-column
	   emphasis uses (`--weight-semi` + `--c-surface-alt2`), applied to a row instead of a column. */
	:global(.jur-tbl) tr.current-row th,
	:global(.jur-tbl) tr.current-row td {
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt2);
	}

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

	.unavailable-cell {
		color: var(--c-text-muted);
		font-style: italic;
		font-weight: var(--weight-reg);
	}

	.cta-link {
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
	.cta-link:hover {
		background: var(--c-surface-alt);
	}
	.cta-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	.cta-link.inline {
		display: inline;
		border: none;
		background: none;
		padding: 0;
		margin-left: var(--space-2);
		color: var(--c-accent);
		text-decoration: underline;
		font-weight: var(--weight-med);
	}
	.cta-link.inline:hover {
		color: var(--c-accent-hover);
	}
	.cta-link.inline:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
</style>
