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

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxJurisdictionTable from './TaxJurisdictionTable.svelte';
	import type { TaxQuarterlyLiability, PriorYearQ4 } from '$lib/tax-quarterly';

	// Sec F3(B)-style discipline: all three REQUIRED, no default — a caller that forgets to thread
	// real loader data fails at TYPECHECK, not as a silent "confirmed healthy" fallback.
	// `priorYearQ4` is typed `PriorYearQ4 | null` rather than optional — null IS the closed-window
	// state, a caller must decide, not omit.
	let {
		liability,
		noTaxAuthorityDesignated,
		priorYearQ4,
		editBracketsHref = '/settings/tax-brackets',
		designateAccountHref = '/accounts'
	}: {
		liability: TaxQuarterlyLiability;
		noTaxAuthorityDesignated: boolean;
		priorYearQ4: PriorYearQ4 | null;
		editBracketsHref?: string;
		designateAccountHref?: string;
	} = $props();
</script>

<section class="quarterly" aria-labelledby="quarterly-label">
	<h2 id="quarterly-label" class="page-label">Estimated Quarterly Taxes</h2>

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
	.page-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
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
