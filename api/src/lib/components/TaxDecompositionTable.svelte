<!--
	TaxDecompositionTable.svelte — the §2.5.1.c tax-relevant income decomposition table
	(SELF-264). Frontend-owned browser surface. Presentational shell over the types + helpers in
	$lib/tax-decomposition; authors NO server logic and performs NO re-derivation of any
	tax-routing rule — every rendered amount is exactly what the server computed, and every
	client-side arithmetic here is plain addition over server-supplied per-row figures, not a
	money-path decision.

	SHAPE, reusing the §2.2.2 pattern (NonReAllocationTable.svelte) rather than inventing a
	parallel one: Cat-grouped section headers, Sub-Cat detail rows beneath, per-Cat-group
	subtotal rows, one footing Total row (AC4). `tax_year` is DB-derived (ADR-044), never computed
	in Node.

	⚠ CONTRACT GAP, surfaced at hand-off rather than patched (AC2 vs. the shipped payload): AC2
	calls for a "three-column table — Ordinary Income / ST CG / LT CG at Sub-Cat granularity."
	Backend's shipped `decomposition.ordinary_income.rows[]` (verified against
	`taxLiability.ts` / `+page.server.ts` post-merge) carries exactly ONE `amount` per row, and
	`capital_gains` carries no `rows` key at all under R1 (ADR-067 Decision 5(b)) — there is no
	per-Sub-Cat ST CG or LT CG figure anywhere in the payload to place in those columns. This
	component renders all three column HEADERS (the table is shaped for when a sale-recording
	capability lands and `capital_gains` gains rows — SELF-302/303), routes every row's `amount`
	into the Ordinary column, and renders "—" in ST CG / LT CG for EVERY row UNCONDITIONALLY — not
	derived from that row's own `tax_character`, because mapping a character to a column would be
	re-deriving Backend's own hardcoded tax-routing rule (migration `011`'s header) client-side.
	`tax_character` is shown only as an informational chip (AC5) — it communicates ROUTING INTENT
	("this row's character is qualified_dividend, which the §2.5.3 walk treats as LT CG-eligible")
	without moving money to a column no payload key currently supplies. Matches the "vacuous under
	R1-A" framing already carried for this reader (the Trade/STC-exclusion fence) — the shape is
	forward-built, the data isn't there yet.

	TWO SECTIONS (AC3): Income (posting_prototype-sourced, `decomposition.ordinary_income`) and
	Capital Gains (`decomposition.capital_gains`) — a UNION discriminated by domain, never a join
	on id (PM's A-1 pointer; see the basis note at the foot of this component and
	$lib/tax-decomposition.ts's own header for the two disjoint id spaces).

	CAPITAL GAINS, AC 3a / R1 (A): renders the UNAVAILABLE-with-a-reason capability banner, never
	a table of zeros — `decomposition.capital_gains.status === 'unavailable'` is the ONLY
	reachable V1.4 shape (ADR-067 Decision 5(b); R11's unmatched-sell disposition ships dormant).
	The copy names the missing CAPABILITY (recording a sale), never a milestone name — R1 rider 2.

	UNCLASSIFIED LINE (AC 3b): `decomposition.unclassified.count_ytd`, PM's copy rendered
	verbatim via `unclassifiedCopyPrefix()` + a literal "classify" link — ONE source, no second
	count. Links to `/accounts`, the SAME classify-surface default CashflowRollupTable.svelte
	already uses for this identical S-2 one-source mechanism (SELF-249 built classification
	inline on per-account transaction lists; there is no dedicated queue page to deep-link to —
	see that component's own header). This is NOT `/portfolio/classify` — that page classifies
	un-Sub-Cat'd SECURITIES (SELF-235), a different domain from unclassified CASH ITEMS.

	TAX_CHARACTER (AC5): each row carries only `tax_character` (a code, nullable). The LABEL is
	resolved against the `taxCharacters` catalog prop (the loader's own fetch of
	`pfin.tax_character`, migration `011`, 5 seeded codes) via `lookupTaxCharacter()` — this
	component maintains NO client-side code→label switch of its own. A `null` character renders
	no chip at all (nothing to legend).

	tax_relevant = FALSE ROWS (AC7): simply absent from the payload — this component never
	renders an "excluded" marker or otherwise presents exclusion as an examined determination
	(R10 / Sec M-5 — that determination is NOT made at this reader).

	EMPTY STATES, TWO, DIFFERENT CONDITIONS (AC9): (i) Income section, reachable — "no
	tax-relevant activity this tax year yet" when there are zero rows. (ii) Capital Gains section
	— the AC 3a capability banner (always active in V1.4 under R1). Neither offers a CTA to a
	route that does not exist.

	NO INLINE EDIT (AC10 / ADR-013 P5): every data cell is plain text, no
	<input>/<button>/<select>/[contenteditable] anywhere in this table.

	BASIS NOTE (AC11): names the SELF-263 seed-delta migration this page was built against, and
	carries PM's A-1 disjoint-id-space pointer.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).

	STALENESS (SELF-361 / P9, closing the gap this file's own header used to flag at SELF-264
	hand-off): this table's Income section aggregates over `pfin.posting_prototype` — the SAME
	substrate §2.3.2's CashflowRollupTable reads, which carries a D1 staleness marker (SELF-258).
	PRD §2.4.4's named-surface list is illustrative-not-exhaustive per ADR-013 D1; §2.5.1 is now
	ramped. `staleness` (a REQUIRED prop, `+page.server.ts`'s own whole-tenant `loadStaleness()`
	read, threaded verbatim) is rendered via ONE page-level `<StaleConstituentBadge>` beside the
	`<h2>` below — NOT a per-row join (unlike SELF-330's NonReAllocationTable / SELF-229's
	NavCompositionTable): this table's rows are Sub-Cat aggregates over posting_prototype, not
	individual accounts, so there is no per-row `linked_source_id` to tint against.

	⚠ SEPARATION (AC3, stated here because this is where both registers are actually composed on
	this page): the `<StaleConstituentBadge>` below covers ONLY §2.4.4 Plaid-connection staleness
	("your brokerage needs re-auth"). It is NOT the same signal as the Capital Gains section's own
	`{status:'unavailable', reason}`-shaped capability notice a few lines down ("this app doesn't
	yet support recording a sale") — an ADR-067 Decision 5 envelope, a missing-CAPABILITY fact, not
	a missing-CONNECTION fact. Different facts, different (non-)actions for the user; neither
	register may ever collapse into the other, and no new copy is owed for either — both are
	already shipped (StaleConstituentBadge here; the capability note inline below).
-->
<script lang="ts">
	import {
		hasUnclassifiedItems,
		unclassifiedCopyPrefix,
		groupSubtotal,
		groupByCat,
		incomeIsEmpty,
		lookupTaxCharacter,
		type TaxLiabilitySlice,
		type TaxCharacterCatalog
	} from '$lib/tax-decomposition';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';
	import type { StalenessData } from '$lib/staleness/stale-constituent';

	// All four data props REQUIRED, no default (Sec F3(B)-style discipline, mirrors every
	// §2.2/§2.3 aggregation table in this codebase) — a caller that forgets to thread real data
	// fails at TYPECHECK, not as a silent "confirmed healthy" empty-table fallback.
	let {
		liability,
		taxCharacters,
		seedDeltaMigration,
		staleness,
		classifyHref = '/accounts'
	}: {
		liability: TaxLiabilitySlice;
		/** AC5 — the `pfin.tax_character` catalog rows resolve against; never a client-side list. */
		taxCharacters: TaxCharacterCatalog;
		/** AC11 — the SELF-263 seed-delta migration filename this page was built against. */
		seedDeltaMigration: string;
		/** SELF-361 / P9 — the whole-tenant `046` read; rendered via the page-level badge below. */
		staleness: StalenessData;
		classifyHref?: string;
	} = $props();

	const decomposition = $derived(liability.decomposition);
	const incomeRows = $derived(decomposition.ordinary_income.rows);
	const incomeGroups = $derived(groupByCat(incomeRows));
	const incomeEmpty = $derived(incomeIsEmpty(incomeRows));
	const showUnclassified = $derived(hasUnclassifiedItems(decomposition.unclassified));

	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});
</script>

<section class="tax-decomp" aria-labelledby="tax-decomp-label">
	<header class="head">
		<h2 id="tax-decomp-label" class="section-label">
			Tax-Relevant Income Decomposition — Tax Year {liability.tax_year}
		</h2>
		<!-- D1 stale-data-marker (SELF-361 / P9): marks stale contribution beside the surface,
		     never hides it. See this file's own header for why this is a page-level badge, not a
		     per-row join, and why it must not merge with the Capital Gains section's own
		     capability-unavailable notice below. -->
		<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />
	</header>

	<!-- AC3b — the S-2 one-source unclassified line. -->
	{#if showUnclassified}
		<div class="unclassified-banner" role="status">
			<span class="unclassified-tag">
				<span class="unclassified-dot" aria-hidden="true"></span>
				<span class="unclassified-text"
					>{unclassifiedCopyPrefix(decomposition.unclassified)}
					<a class="unclassified-cta" href={classifyHref}>classify</a></span
				>
			</span>
		</div>
	{/if}

	<!-- Income section -->
	<div class="tax-section">
		<h3 class="subsection-label">Income</h3>

		{#if incomeEmpty}
			<p class="empty-note" role="status">No tax-relevant activity this tax year yet.</p>
		{:else}
			<div class="table-scroll">
				<table class="tax-tbl">
					<caption class="sr-only"
						>Tax-relevant income by category and sub-category. Ordinary Income is populated
						per Sub-Cat; ST CG and LT CG are shown for a future capital-gains capability and
						carry no figures yet.</caption
					>
					<thead>
						<tr>
							<th scope="col">Cat / Sub-Cat</th>
							<th scope="col">Tax Character</th>
							<th scope="col" class="num">Ordinary</th>
							<th scope="col" class="num">ST CG</th>
							<th scope="col" class="num">LT CG</th>
						</tr>
					</thead>

					{#each incomeGroups as g (g.cat)}
						{@const subtotal = groupSubtotal(g.rows)}
						<tbody class="group">
							<tr class="group-row">
								<th scope="colgroup" colspan="5" class="grp-cell">{g.cat}</th>
							</tr>

							{#each g.rows as row (row.sub_cat_id)}
								{@const character = lookupTaxCharacter(taxCharacters, row.tax_character)}
								<tr>
									<td class="rowlabel">{row.sub_cat}</td>
									<td class="char-cell">
										{#if character}
											<span class="char-chip" title={character.code}>{character.label}</span>
										{/if}
									</td>
									<td class="num">{usd.format(row.amount)}</td>
									<!-- No per-row ST CG / LT CG figure exists in V1.4's payload — see this
									     component's own header CONTRACT GAP note. Never $0, never derived
									     from tax_character. -->
									<td class="num">—</td>
									<td class="num">—</td>
								</tr>
							{/each}

							<tr class="subtotal">
								<th scope="row" colspan="2">{g.cat} subtotal</th>
								<td class="num">{usd.format(subtotal)}</td>
								<td class="num">—</td>
								<td class="num">—</td>
							</tr>
						</tbody>
					{/each}

					<tbody class="ladder">
						<tr class="foot">
							<th scope="row" colspan="2">Total</th>
							<!-- Server-authoritative footing total — read directly, never re-summed. -->
							<td class="num">{usd.format(decomposition.ordinary_income.total)}</td>
							<td class="num">—</td>
							<td class="num">—</td>
						</tr>
					</tbody>
				</table>
			</div>
		{/if}
	</div>

	<!-- Capital Gains section — AC 3a / R1 (A): UNAVAILABLE-with-a-reason, never a table. -->
	<div class="tax-section">
		<h3 class="subsection-label">Capital Gains</h3>
		{#if decomposition.capital_gains.status === 'unavailable'}
			<p class="cg-unavailable-note" role="status">
				Capital gains aren't shown here yet — this app doesn't yet support recording a
				security sale, so there is no realized-gain figure to report.
			</p>
		{/if}
	</div>

	<!-- AC11 basis note + PM A-1 disjoint-id-space pointer. -->
	<p class="basis-note">
		Built against the SELF-263 tax-value seed-delta migration ({seedDeltaMigration}). Income
		and Capital Gains rows are read from two disjoint id spaces — <code
			>pfin.posting_prototype</code
		> ids and <code>pfin.user_taxonomy</code> ids — and are rendered as a union discriminated by
		section, never joined on id.
	</p>
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

	.tax-decomp {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.section-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}
	.subsection-label {
		margin: 0 0 var(--space-2) 0;
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.tax-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	/* Unclassified banner — reuses the RESERVED canary --c-attn-* register (StaleConstituentBadge /
	   CashflowRollupTable's own vocabulary): a genuine, actionable, financially-material fact. */
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

	.empty-note,
	.cg-unavailable-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}

	.table-scroll {
		overflow-x: auto;
	}

	/* Base table — reproduces the locked screen.css `table.tbl` with tokens only, same rules as
	   NonReAllocationTable.svelte. */
	.tax-tbl {
		border-collapse: collapse;
		width: 100%;
		font-size: var(--fs-num);
	}
	.tax-tbl th,
	.tax-tbl td {
		padding: var(--space-2) var(--space-3);
		border-bottom: 1px solid var(--c-border);
		text-align: left;
	}
	.tax-tbl thead th {
		font-size: var(--fs-small);
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
		font-weight: var(--weight-semi);
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
	}
	.tax-tbl td.num,
	.tax-tbl th.num {
		text-align: right;
		font-family: var(--font-num);
		font-variant-numeric: tabular-nums;
	}
	.tax-tbl tbody tr:hover td {
		background: var(--c-surface-alt);
	}

	/* Cat-group header row — reproduces screen.css's `.group-row` (uppercase, muted, surface-alt2),
	   same rule NonReAllocationTable.svelte uses. */
	.group-row th {
		background: var(--c-surface-alt2);
		font-size: var(--fs-small);
		letter-spacing: 0.04em;
		text-transform: uppercase;
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}

	/* AC4 — subtotal (bold + top divider) and Total foot (locked tr.foot look), reproducing
	   screen.css verbatim, same rule NonReAllocationTable.svelte / CashflowRollupTable.svelte use. */
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

	/* AC5 — the tax_character label, an informational chip (quiet register — this is routing
	   context, not a staleness/attention signal, so it does NOT use --c-attn-*). */
	.char-chip {
		display: inline-block;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-sm);
		padding: 0 var(--space-2);
	}

	.basis-note {
		margin: 0;
		font-size: var(--fs-small);
		font-style: italic;
		color: var(--c-text-muted);
	}
	.basis-note code {
		font-family: var(--font-num);
		font-size: 0.95em;
	}
</style>
