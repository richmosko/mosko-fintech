<!--
	TaxQuarterlyTables.svelte — the §2.5.3.b page-level shell (SELF-266): the page-wide
	`noTaxAuthorityDesignated` empty state (AC 6(ii)) plus the two parallel jurisdiction tables
	(Federal / California), each owned by TaxJurisdictionTable.svelte. Consumed by
	routes/taxes/quarterly/+page.svelte — prop names below are typed VERBATIM against that loader's
	own return shape (`{ liability, noTaxAuthorityDesignated, priorYearQ4 }`), never a paraphrase.

	AC 6(ii) vs 6(iii), stated once so the split isn't rediscovered per-reviewer: `noTaxAuthorityDesignated`
	is a PAGE-level fact ("does any account carry a tax_jurisdiction value at all", measured via
	`pfin.fn_tax_authority_ledgers()` — see +page.server.ts's own header) rendered ONCE, here, above
	both tables. It is deliberately NOT the same predicate as either jurisdiction's own
	`ytd_paid.reason === 'no_ledger_designated'` (AC 6(iii), TaxJurisdictionTable's own inline CTA) —
	a user can have exactly one of IRS/FTB designated, in which case this page banner is absent
	(`noTaxAuthorityDesignated` is false) while the OTHER jurisdiction's table still shows its own
	inline CTA. Both facts can be true independently; neither is derived from the other here.

	`priorYearQ4` (E39) is passed straight through to both jurisdiction tables — each reads its own
	`.federal` / `.california` half; `null` means the R8 render window is closed (+page.server.ts's
	own gate), and both tables render nothing prior-year-Q4-shaped in that case.

	AC 8a — no as-of toggle anywhere on this page (every §2.5 surface reads server-derived today,
	Seam C) — this component takes no as-of prop and has nothing that could grow one.

	Team-lead ruling — an in-page cross-link to /taxes/decomposition ("Income decomposition →")
	beside the heading, the §2.5.1 sibling surface (SELF-264). A plain navigation link, never a
	form/action. SELF-264's own +page.svelte has not merged into this branch yet, so the target
	404s until that branch lands — expected, same posture CashflowRollupTable's `editTargetsHref`
	documents for its own not-yet-built sibling route.

	QA-walk DEFECT fix (relayed by team-lead): "Edit tax brackets" (AC 7) is a STANDING affordance
	per ADR-013 P5 — the no-inline-edit escape hatch must always be reachable, not only from the
	AC-7a unavailable state. It previously lived ONLY inside TaxJurisdictionTable's `unavailable`
	branch, so a tenant with resolved brackets (the ordinary case) had no way back to the editor
	from this page. Rendered HERE, page-level, beside the heading, UNCONDITIONALLY — alongside the
	decomposition cross-link. TaxJurisdictionTable's own AC-7a CTA is UNCHANGED and stays (a second,
	narrower entry point that's also the ONLY affordance visible when a jurisdiction table has
	collapsed to its empty state and this page-level header is still the fallback either way).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).

	STALENESS (SELF-361 / P9): `staleness` (a REQUIRED prop, `+page.server.ts`'s own whole-tenant
	`loadStaleness()` read, threaded verbatim) is rendered via ONE page-level
	`<StaleConstituentBadge>` beside the `<h2>` below — mirrors NavDeltaPanel's own "badge beside
	the section heading" convention. This page has no per-account row to tint (each jurisdiction
	table is a fixed set of computed lines, not an account list), so a single page-level mount
	covers both jurisdiction tables — no second mount inside TaxJurisdictionTable.svelte.

	⚠ SEPARATION (AC3, stated here because this is where all three registers are actually composed
	on this page): the `<StaleConstituentBadge>` covers ONLY §2.4.4 Plaid-connection staleness
	("your brokerage needs re-auth"). It is NOT the same signal as (a) the
	`noTaxAuthorityDesignated` banner just below ("no account is marked as a tax authority" — a
	designation gap, not a connection problem) or (b) `reasonCopy()`'s `{status:'unavailable',
	reason}` envelopes and the `basis_year` fallback rendered inside each `TaxJurisdictionTable`
	(ADR-067 Decision 5 — "no schedule published yet" / "no ledger designated", capability/
	configuration facts, not connection facts). Three distinct registers, three distinct user
	actions; none may collapse into another, and no new copy is owed for any of them — all three
	are already shipped.
-->
<script lang="ts">
	import TaxJurisdictionTable from './TaxJurisdictionTable.svelte';
	import StaleConstituentBadge from './StaleConstituentBadge.svelte';
	import type { TaxQuarterlyLiability, PriorYearQ4 } from '$lib/tax-quarterly';
	import type { StalenessData } from '$lib/staleness/stale-constituent';

	// Sec F3(B)-style discipline: all four REQUIRED, no default — a caller that forgets to thread
	// real loader data fails at TYPECHECK, not as a silent "confirmed healthy" fallback.
	// `priorYearQ4` is typed `PriorYearQ4 | null` rather than optional — null IS the closed-window
	// state, a caller must decide, not omit.
	let {
		liability,
		noTaxAuthorityDesignated,
		priorYearQ4,
		staleness,
		editBracketsHref = '/settings/tax-brackets',
		designateAccountHref = '/accounts',
		decompositionHref = '/taxes/decomposition'
	}: {
		liability: TaxQuarterlyLiability;
		noTaxAuthorityDesignated: boolean;
		priorYearQ4: PriorYearQ4 | null;
		/** SELF-361 / P9 — the whole-tenant `046` read; rendered via the page-level badge below. */
		staleness: StalenessData;
		editBracketsHref?: string;
		designateAccountHref?: string;
		/** Team-lead ruling — cross-link to the §2.5.1 sibling (SELF-264). */
		decompositionHref?: string;
	} = $props();
</script>

<section class="quarterly" aria-labelledby="quarterly-label">
	<header class="page-head">
		<div class="page-title-group">
			<h2 id="quarterly-label" class="page-label">Estimated Quarterly Taxes</h2>
			<!-- D1 stale-data-marker (SELF-361 / P9): marks stale contribution beside the surface,
			     never hides it. See this file's own header for the three-register separation. -->
			<StaleConstituentBadge isStale={staleness.is_stale} staleItems={staleness.stale_items} />
		</div>
		<div class="page-actions">
			<a class="decomposition-link" href={decompositionHref}>Income decomposition →</a>
			<!-- AC 7 — standing affordance, unconditional (QA-walk defect fix). -->
			<a class="page-edit-brackets-link" href={editBracketsHref}>Edit tax brackets</a>
		</div>
	</header>

	{#if noTaxAuthorityDesignated}
		<!-- AC 6(ii) — page-level: no account at all carries a tax_jurisdiction value. -->
		<div class="no-authority-banner" role="status">
			<span class="banner-text">No account is marked as a tax authority.</span>
			<a class="banner-cta" href={designateAccountHref}>Designate an account</a>
		</div>
	{/if}

	<div class="tables-grid">
		<TaxJurisdictionTable
			jurisdiction={liability.jurisdictions.federal}
			jurisdictionKey="federal"
			taxYear={liability.tax_year}
			{priorYearQ4}
			{editBracketsHref}
			{designateAccountHref}
		/>
		<TaxJurisdictionTable
			jurisdiction={liability.jurisdictions.california}
			jurisdictionKey="california"
			taxYear={liability.tax_year}
			{priorYearQ4}
			{editBracketsHref}
			{designateAccountHref}
		/>
	</div>
</section>

<style>
	.quarterly {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.page-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.page-title-group {
		display: flex;
		align-items: baseline;
		gap: var(--space-3);
		flex-wrap: wrap;
	}
	.page-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.page-actions {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		flex-wrap: wrap;
	}
	.decomposition-link {
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		color: var(--c-accent);
		text-decoration: none;
		white-space: nowrap;
	}
	.decomposition-link:hover {
		color: var(--c-accent-hover);
		text-decoration: underline;
	}
	.decomposition-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}
	/* Reproduces the locked screen.css `.btn.secondary` look — same convention NonReAllocationTable /
	   CashflowRollupTable's own `.edit-link` uses. AC 7's standing affordance, unconditional. */
	.page-edit-brackets-link {
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
	.page-edit-brackets-link:hover {
		background: var(--c-surface-alt);
	}
	.page-edit-brackets-link:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}

	/* AC 6(ii) — same informational (non-canary) register as TaxJurisdictionTable's AC 7a block:
	   a "not set up yet" state, not a confirmed staleness/attention signal. */
	.no-authority-banner {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-3);
		padding: var(--space-3);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.banner-text {
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.banner-cta {
		color: var(--c-accent);
		font-weight: var(--weight-med);
		text-decoration: underline;
	}
	.banner-cta:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
		border-radius: var(--radius-sm);
	}

	/* "Two parallel tables" — side by side ≥ this breakpoint, stacked below it. Each table already
	   carries its own `.table-scroll` for narrower overflow, so a stacked single column never
	   forces the page itself to scroll horizontally. */
	.tables-grid {
		display: grid;
		grid-template-columns: 1fr;
		gap: var(--space-5);
	}
	@media (min-width: 900px) {
		.tables-grid {
			grid-template-columns: 1fr 1fr;
			align-items: start;
		}
	}
</style>
