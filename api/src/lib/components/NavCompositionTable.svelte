<!--
	NavCompositionTable.svelte — the §2.1.5 NAV-composition build-up (SELF-226 · V1.1).
	Frontend-owned browser surface. Consumes the ratified `fn_nav_composition` JSONB
	(migration 051) threaded through `+page.server.ts` as `data.composition`; authors NO
	server logic. Presentational shell over the types + ladder ordering in $lib/nav-composition.

	The "composition foot" of the single-canvas §2.1 surface (P2 dense number-first): it sits
	below the SELF-211 NAV headline on the root dashboard.

	RATIFIED SHAPE (F/CTO 2026-08-02; SELF-268 V1.4 flip amends the tax-row treatment below):
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
	  • Debt sign (D5): Debt row = −magnitude (subtraction). SELF-268 (R3 rider 5 / AC 2-3-7):
	    the V1.1 tax-placeholder shape (`isTaxPlaceholder`, `$0` + a "V1.4 ramp" caption) is REMOVED
	    — the two tax rows now render their real `displayValue`, UNFLIPPED (debt stays the ladder's
	    only negation; see $lib/nav-composition.ts). ⚠ THIS WAS THE SILENT LAYER (R3 rider 5 part
	    3): fixing 105 + nav-composition.ts and missing this file would still render `$0` here
	    against correct upstream data, with a green suite. Empty categories are omitted upstream →
	    simply absent (D3).
	  • Whole-dollar, tabular-nums (D9): the NAV foot reads identical to the §2.1.1 headline and
	    subtotals never appear off-by-rounding.
	  • SELF-268 AC 9a — the §2.5.4 disclaimer (PRD verbatim) renders as a VISIBLE footnote under
	    the Unrealized Tax Liability row (never hover-only — survives print/PDF/AT, same posture
	    §2.4.4 requires of its informational marker).
	  • SELF-268 AC 6 (EXPECTED CONTRACT, provisional pending migration 105 / Architect's A-vs-B
	    ruling) — when `composition.tax_components` marks a tax scalar unavailable, its cell
	    renders an "unavailable" notice instead of the dollar figure: `buildups.*_tax_liab` is 0 in
	    that state per 105's own arithmetic constraint (can't subtract a JSON null), and rendering
	    that 0 as a determination would be exactly the silent-zero defect this ruling exists to
	    avoid. Absent `tax_components` → no notice (the field simply hasn't landed on 105 yet).
	  • SELF-268 AC 10a / R3 riders 0b + 6 (EXPECTED CONTRACT, provisional) — `composition
	    .excluded_tax_ledgers`, when present, names the accounts AC 3a excluded from the buildup as
	    tax-authority ledgers. Rendering it (even when the list is empty) is what makes an UNMARKED
	    designated account visible as "not excluded" — rider 0b's whole point. Absent the field →
	    nothing renders here (a real payload gap to close with Architect/Backend, not invented via a
	    second component-level query).

	D1 stale-data-marker (SELF-229 ramp): the AGGREGATION-level badge is wired below off the SAME
	whole-user `046` fn_aggregation_has_stale_constituent() payload the §2.1.1 headline already
	consumes (+page.server.ts's `data.staleness`, threaded down unchanged). This component now owns
	its own section heading (moved in from +page.svelte's wrapper) so the badge sits adjacent to it,
	matching NavHistoryChart / NavDeltaPanel / NavReferenceDatesPanel's self-contained pattern.
	Per ADR-013 D1 (staleness-marking surface scope is illustrative, not exhaustive), further
	surfaces ramp later — Sec F4 (AMBER round): read D1 live, this line is a paraphrase not a quote.

	PER-ROW LEAF staleness (AC#2 — a per-account indicator IN ADDITION to the aggregation badge
	above): Backend delivers `NavCompositionLeaf.is_stale` via a SERVER-SIDE join in the loader
	(pfin.account.linked_source_id ↔ staleness.stale_items[].linked_source_id — NO 051 change, no
	migration; see $lib/nav-composition.ts's header). TRI-STATE, not a plain boolean:
	  • true  → CONFIRMED stale. Rendered as an italic, canary-hued (--c-attn-text) inline tag next
	    to the account name — the SAME signal family as the aggregation badge above (a server
	    discriminator, never inferred here), just localized to this leaf. No duplicate re-auth CTA
	    at leaf level; the aggregation badge above already carries that action.
	  • false → confirmed NOT stale. Renders nothing (plain leaf row).
	  • null  → UNKNOWN (the server-side join query itself failed). Rendered DISTINCTLY from `true`
	    — a quiet, muted (--c-text-muted) note, matching the house idiom for "couldn't confirm X"
	    (`+page.svelte`'s own `data.accountPresence === 'unknown'` notice under the headline NAV).
	    NEVER collapsed with `false` (that would silently present an unconfirmed row as fresh — the
	    exact SELF-220 Sec round 2 defect this tri-state shape exists to avoid) and NEVER collapsed
	    with `true` (an unconfirmed row is not evidence of staleness either).

	Tokens only (var(--c-*)); no hardcoded hex/px-spacing/font (ADR-013 P5).
-->
<script lang="ts">
	import type { NavComposition, TaxComponentStatus } from '$lib/nav-composition';
	import { buildupRows } from '$lib/nav-composition';
	import { accountTypeLabel } from '$lib/account-display';
	import type { StalenessData } from '$lib/staleness/stale-constituent';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';

	// Sec F3(B) (F/CTO-ruled): `staleness` is REQUIRED, no default — a caller that forgets to
	// thread real staleness data now fails at TYPECHECK, not as a silent "confirmed healthy"
	// fallback. The live mount (+page.svelte) already passes the real loader value unconditionally.
	let { composition, staleness }: { composition: NavComposition; staleness: StalenessData } =
		$props();

	const groups = $derived(composition.groups);
	const ladder = $derived(buildupRows(composition.buildups));

	// SELF-268 AC 6 EXPECTED CONTRACT (provisional — see $lib/nav-composition.ts header).
	// `??` here is safe (unlike the ADR-013 staleness fallbacks elsewhere in this codebase): an
	// ABSENT `tax_components` means "105 doesn't emit this yet," not "confirmed available" — and
	// `null` renders NO notice either way, never a fabricated availability claim.
	const taxComponents = $derived(composition.tax_components ?? null);
	function taxStatusFor(key: string): TaxComponentStatus | null {
		if (!taxComponents) return null;
		if (key === 'realized_tax_liab') return taxComponents.realized_tax_liab;
		if (key === 'unrealized_tax_liab') return taxComponents.unrealized_tax_liab;
		return null;
	}
	// Stable machine `reason` codes (104's vocabulary) → user-facing copy. Minimal V1.4 wording;
	// UX/PM own the final phrasing (bubble-up) — this exists so an unavailable scalar never
	// silently renders as its 0-for-arithmetic value (AC 6).
	const UNAVAILABLE_REASON_COPY: Record<string, string> = {
		no_schedule_any_year: 'no tax bracket schedule on file',
		ytd_paid_unavailable: 'no tax-authority ledger designated',
		no_ledger_designated: 'no tax-authority ledger designated'
	};
	function unavailableCopy(status: TaxComponentStatus): string {
		if (status.status !== 'unavailable') return '';
		return UNAVAILABLE_REASON_COPY[status.reason] ?? 'currently unavailable';
	}

	// SELF-268 AC 10a / R3 riders 0b + 6 EXPECTED CONTRACT (provisional — see $lib/nav-composition.ts
	// header). `undefined`/`null` → render nothing (a real payload gap, not a "no exclusions" claim
	// this component would have to invent). An empty ARRAY is a genuine, renderable fact — it means
	// zero accounts are currently designated, which is exactly the unmarked-ledger state rider 0b
	// needs made visible, so it is NOT treated the same as "field absent."
	const excludedLedgers = $derived(composition.excluded_tax_ledgers ?? undefined);

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

<section class="composition" aria-labelledby="composition-label">
	<h2 id="composition-label" class="section-label">Composition</h2>
	<!-- D1 stale-data-marker: marks stale contribution beside the surface, never hides it.
	     Per-leaf marking (AC#2) is BLOCKED — see the module header. -->
	<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />

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
								<!-- AC#2 per-leaf staleness (SELF-229) — TRI-STATE, `false` renders nothing. -->
								{#if a.is_stale === true}
									<span
										class="leaf-stale-flag"
										title="This account is contributing possibly-stale data — see the staleness notice above."
										>May be stale</span
									>
								{:else if a.is_stale === null}
									<span
										class="leaf-stale-unknown"
										title="Couldn't confirm whether this account is contributing stale data."
										>Staleness unknown</span
									>
								{/if}
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
				{@const taxStatus = taxStatusFor(row.key)}
				<tr class="subtotal">
					<th scope="row">
						{row.label}
						{#if row.key === 'unrealized_tax_liab'}
							<!-- AC 9a — PRD §2.5.4 disclaimer VERBATIM, a visible footnote (never hover-only:
							     survives print/PDF export and assistive technology, same posture §2.4.4
							     requires of its informational marker). -->
							<span class="tax-disclaimer">
								Treat this as an LT-aware floor estimate, not a precise tax forecast.
							</span>
						{/if}
					</th>
					{#if taxStatus?.status === 'unavailable'}
						<!-- AC 6 (EXPECTED CONTRACT, provisional — see $lib/nav-composition.ts header): the
						     underlying buildups value is 0 here purely for 105's arithmetic (it cannot
						     subtract a JSON null); rendering that 0 as though it were a determination is the
						     exact silent-zero defect this branch exists to prevent. -->
						<td class="num tax-unavailable">
							Unavailable
							<span class="tax-unavailable-reason">— {unavailableCopy(taxStatus)}</span>
						</td>
					{:else}
						<td class="num">{usd.format(row.displayValue)}</td>
					{/if}
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

<!-- AC 10a / R3 riders 0b + 6 (EXPECTED CONTRACT, provisional — see $lib/nav-composition.ts
     header). Rendered even when the list is EMPTY: an unmarked tax-authority account becomes
     visible as "not excluded" only because this note names what IS excluded — hiding an empty
     state here would hide the exact default-state failure rider 0b names. Absent the field
     entirely (105 doesn't emit it yet) → nothing renders; that gap is reported upstream, never
     papered over with a second component-level query. -->
{#if excludedLedgers !== undefined}
	<div class="exclusion-note">
		{#if excludedLedgers.length > 0}
			<p class="exclusion-line">
				Excluded from Net Worth above as tax-authority ledgers (their balance moves NAV only
				through the Realized Tax Liability line):
			</p>
			<ul class="exclusion-list">
				{#each excludedLedgers as ledger (ledger.account_id)}
					<li><a class="leaf-link" href={`/accounts/${ledger.account_id}`}>{ledger.account_name}</a></li>
				{/each}
			</ul>
		{:else}
			<p class="exclusion-line">
				No accounts are currently designated as tax-authority ledgers — none are excluded from
				Net Worth above.
			</p>
		{/if}
	</div>
{/if}
</section>

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

	/* §2.1.5 composition foot section shell — moved in from +page.svelte's wrapper (SELF-229) so
	   the D1 stale-data-marker badge can sit adjacent to this surface's own heading, matching
	   NavHistoryChart / NavDeltaPanel / NavReferenceDatesPanel's self-contained pattern. */
	.composition {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.section-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
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

	/* AC#2 per-leaf staleness (SELF-229) — TRI-STATE, two DISTINCT treatments, never merged:
	   confirmed-stale uses the RESERVED canary hue (same signal family as the aggregation badge
	   above — a server discriminator, not decoration, per §5 fence 8); unknown is the QUIET
	   muted-informational register this codebase already uses for "couldn't confirm X"
	   (+page.svelte's accountPresence==='unknown' notice) — never the canary hue, since an
	   unconfirmed row is not evidence of staleness either. */
	.leaf-stale-flag {
		display: inline-block;
		margin-left: var(--space-2);
		font-style: italic;
		font-size: var(--fs-small);
		color: var(--c-attn-text);
	}
	.leaf-stale-unknown {
		display: inline-block;
		margin-left: var(--space-2);
		font-style: italic;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
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
	/* AC 9a — the §2.5.4 disclaimer: a quiet sub-line beneath the Unrealized Tax Liability row
	   label, VISIBLE without hover (not a title attribute — survives print/PDF/AT). Same
	   treatment family as the old V1.1 tax caption this replaces: muted, fs-small, regular
	   weight, roman (NOT italic — italic is reserved for .disclaimer/empty elsewhere). */
	.tax-disclaimer {
		display: block;
		margin-top: var(--space-1);
		font-size: var(--fs-small);
		font-weight: var(--weight-reg);
		color: var(--c-text-muted);
	}

	/* AC 6 (EXPECTED CONTRACT, provisional) — an unavailable tax scalar's cell. Muted, NOT
	   --c-neg/--c-attn: this is an availability fact, not a bad value or an actionable warning
	   (same register as the CPI-unavailable / insufficient-history cells elsewhere in this
	   surface family). */
	.tax-unavailable {
		font-weight: var(--weight-reg);
		font-style: italic;
		color: var(--c-text-muted);
	}
	.tax-unavailable-reason {
		font-size: var(--fs-small);
	}

	/* ── Tier 3 — NAV foot (locked tr.foot; dominant, echoes the §2.1.1 headline). ── */
	tr.foot th,
	tr.foot td {
		border-top: 2px solid var(--c-border-strong);
		border-bottom: none;
		font-weight: var(--weight-bold);
		background: var(--c-surface-alt);
	}

	/* AC 10a / R3 riders 0b + 6 (EXPECTED CONTRACT, provisional) — the excluded-tax-ledger note
	   below the table. Same basis-line register NavHistoryChart / NavDeltaPanel use for their
	   own disclosures, so this surface's provisional notice reads as part of the same system. */
	.exclusion-note {
		margin-top: var(--space-3);
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.exclusion-line {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		line-height: var(--lh-body);
	}
	.exclusion-list {
		margin: 0;
		padding-left: var(--space-5);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
</style>
