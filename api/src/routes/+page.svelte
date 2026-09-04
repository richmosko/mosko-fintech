<!--
	+page.svelte — root dashboard = the §2.1.1 headline Net Worth surface (SELF-211).
	Frontend-owned browser surface. Consumes +page.server.ts's `data` (fn_compute_nav
	via the RLS-scoped server load); authors NO server logic.

	V1.0 Option A (F/CTO-ratified): a SINGLE trustworthy number (PRD §2.1.1 verbatim —
	"a single trustworthy whole-position number"). Number-first single canvas per the
	Phase-2 P2 lock (ADR-013). The GAV/Debt/tax composition table is §2.1.5 = V1.1
	(SELF-225) — deliberately absent here.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
	VALUE-COLOR FENCE (design-system-spec.md §5 fence 1): --c-pos/--c-neg are scoped to
	ACTUAL performance (deltas) ONLY — the NAV headline is a position, not a delta, so a
	negative net worth is NOT rendered red. It shows a minus sign in --c-text-primary.

	Staleness marker (AC#4) attaches here (SELF-208): the D1 stale-data-marker off the `046`
	fn_aggregation_has_stale_constituent primitive, threaded through the loader as `data.staleness`
	({ is_stale, stale_items }). It MARKS beside the number, never suppresses it (D1).

	SELF-268 (Sec item 3, relayed by team-lead) — this headline reads the SAME composed value as the
	§2.1.5 foot (R3 rider 0), so it carries the SAME three-state tax-adjustment basis note (Sec P-5 /
	option (C): tax-adjusted / partial / unadjusted — never a boolean), in short form, plus the AC 4a
	fact that the trend chart further down is a different, permanently-gross basis. Derived from
	`data.composition.buildups` (already loaded for the §2.1.5 table below — no second query) via
	`navHeadlineBasisNote()`. VISIBLE without hover (this codebase's house discipline, PRD §2.4.4 /
	ADR-013 — never ADR-049, a retracted attribution per Sec D-1). Absent when `composition` is
	null (a composition-read failure): rather than fabricate a basis claim from no data, the
	headline simply omits the note — the number itself still stands (fail-soft, matching every
	other `composition`-gated affordance on this page).

	SELF-229 RAMP: the SAME `staleness` object (the fn takes no scope filter — it is a whole-user
	aggregate, not per-surface) is threaded down unchanged as a `staleness` prop to
	NavHistoryChart / NavDeltaPanel / NavReferenceDatesPanel / NavCompositionTable below, each of
	which renders its own <StaleConstituentBadge> adjacent to its own section heading. This is why
	NavCompositionTable now owns its "Composition" heading + wrapping <section> itself (moved in
	from this file) rather than this file rendering a bare h2 around it — every consuming surface
	follows the same self-contained badge-beside-heading pattern.
-->
<script lang="ts">
	import type { PageData } from './$types';
	import StaleConstituentBadge from '$lib/components/StaleConstituentBadge.svelte';
	import NavReferenceDatesPanel from '$lib/components/NavReferenceDatesPanel.svelte';
	import NavDeltaPanel from '$lib/components/NavDeltaPanel.svelte';
	import NavCompositionTable from '$lib/components/NavCompositionTable.svelte';
	import NavHistoryChart from '$lib/components/NavHistoryChart.svelte';
	import { EMPTY_NAV_BOUNDARY } from '$lib/nav-boundary';
	import { navHeadlineBasisNote } from '$lib/nav-composition';

	let { data }: { data: PageData } = $props();

	// Sec F3(B) (F/CTO-ruled, AMBER round): NO `?? EMPTY_STALENESS` fallback here anymore.
	// +page.server.ts's loader always returns a real StalenessData value — UNKNOWN_STALENESS on a
	// read failure, never absent — so a `?? EMPTY_STALENESS` guard on this line could only ever
	// have MASKED a genuine contract violation by silently reading it as "confirmed healthy," which
	// is the exact fail-open shape this whole framework exists to rule out. `data.staleness` is
	// passed straight through.
	const staleness = $derived(data.staleness);

	// §2.1.4 NAV-at-three-reference-dates panel (SELF-223 · V1.1). Backend threads
	// `pfin.fn_nav_reference_dates()` (migration 073 — authored in parallel, not yet merged as
	// of this loader) rows through the loader as `data.navReferenceDates`, FAIL-SOFT to `null`
	// on a read failure — same convention as `data.navDeltaPanel` below.
	const navReferenceDates = $derived(data.navReferenceDates ?? null);

	// §2.1.3 multi-horizon NAV-delta panel (SELF-222 · V1.1). Backend threads the `071`
	// fn_nav_delta_panel() rows through the loader as `data.navDeltaPanel`, FAIL-SOFT to `null`
	// on a read failure (NavDeltaPanel renders its own unavailable notice) — same convention as
	// `data.composition` below.
	const navDeltaPanel = $derived(data.navDeltaPanel ?? null);

	// §2.1.5 composition build-up (SELF-226). Backend threads the `051` fn_nav_composition tree
	// through the loader as `data.composition`, FAIL-SOFT to `null` (composition-read failure must
	// never take down the headline). `null` → the table simply doesn't render; the headline stays.
	const composition = $derived(data.composition ?? null);

	// SELF-268 (Sec item 3) — the headline's short-form basis note, derived from the SAME
	// composition object (no second query). `null` when composition failed to load: the headline
	// number still renders (fail-soft), it just carries no tax-adjustment-basis claim rather than
	// fabricate one from data that didn't arrive.
	const headlineBasisNote = $derived(composition ? navHeadlineBasisNote(composition.buildups) : null);

	// SELF-268 AC 10a — the accounts AC 3a excludes from the §2.1.5 buildup as tax-authority
	// ledgers. Backend's ROOT loader returns this as `data.excludedTaxLedgers`, a SIBLING field
	// beside `composition` (NOT nested in it). Passed straight through, no `?? null` — `null`
	// (the loader's reads failed) and `[]` (confirmed none designated) are DISTINCT real states
	// NavCompositionTable.svelte renders differently; collapsing them here would re-introduce the
	// exact silent-failure shape AC 10a exists to prevent.
	const excludedTaxLedgers = $derived(data.excludedTaxLedgers);

	// Whole-dollar USD — the headline reads cleaner without cents. Negative values render
	// a leading minus (in primary ink, per the value-color fence above).
	const usd = new Intl.NumberFormat('en-US', {
		style: 'currency',
		currency: 'USD',
		minimumFractionDigits: 0,
		maximumFractionDigits: 0
	});

	// asOf is a plain ISO date (YYYY-MM-DD) from the server; anchor it to local midnight
	// so the display date matches the value's as-of date (no timezone off-by-one).
	const asOfLabel = $derived(
		new Date(`${data.asOf}T00:00:00`).toLocaleDateString('en-US', {
			year: 'numeric',
			month: 'long',
			day: 'numeric'
		})
	);
</script>

<svelte:head>
	<title>Net Worth · mosko-fintech</title>
</svelte:head>

<main class="dashboard">
	<!--
		⚠ THE ORDER OF THIS CHAIN IS THE FIX. DO NOT "TIDY" IT BACK.

		It used to open with `{#if !data.hasAccounts}` — presence tested FIRST, ahead of both the
		compute-failure check and the number itself. That is the one position where a failed
		account count can override evidence that outranks it, and it is how a read error rendered
		"connect your first account" to a user with a real net worth. The type change alone would
		NOT have fixed that: re-pointing the flag while leaving it first in the chain yields a
		narrower version of the same bug, and a narrower one is HARDER to find, because the obvious
		fix has been applied and looks done.

		The rule, from `NetWorthView.accountPresence`'s own contract: **check the NAV first.**
		`accountPresence` is load-bearing ONLY when `netWorth === 0` — the sole cell where the
		number cannot distinguish "no accounts" from "a real $0 position", because fn_compute_nav
		returns 0 for both. A non-zero NAV is itself proof that accounts exist and OUTRANKS this
		field, including when it is 'unknown'.

		  netWorth === null   → unavailable          (presence moot: the compute failed)
		  netWorth === 0      → presence decides     ('none' onboarding · 'some'/'unknown' below)
		  netWorth !== 0      → the number, always   (presence cannot overrule it)
	-->
	{#if data.netWorth === null}
		<!-- Degrade: the compute failed (logged server-side). Never render a wrong number. -->
		<section class="unavailable" aria-labelledby="unavail-title">
			<h1 id="unavail-title" class="nav-label">Net Worth</h1>
			<p class="unavail-msg">Net worth is temporarily unavailable. Please try again shortly.</p>
		</section>
	{:else if data.netWorth === 0 && data.accountPresence === 'none'}
		<!-- Empty-state (AC#5): the count SUCCEEDED and found zero → onboarding CTAs.
		     Reachable only on a MEASURED zero. 'unknown' must never land here — that claim is
		     precisely what we cannot make when the read failed. -->
		<section class="empty" aria-labelledby="empty-title">
			<h1 id="empty-title" class="empty-title">Net Worth</h1>
			<p class="empty-msg">Connect your first account to see your net worth.</p>
			<div class="empty-cta">
				<a class="cta cta-primary" href="/accounts/connect">Connect an account</a>
				<a class="cta" href="/accounts/new">Add a manual account</a>
			</div>
		</section>
	{:else}
		<!-- The single trustworthy number (AC#1). -->
		<section class="nav-hero" aria-labelledby="nav-label">
			<h1 id="nav-label" class="nav-label">Net Worth</h1>
			<p class="nav-value">{usd.format(data.netWorth)}</p>
			<p class="nav-asof">as of {asOfLabel}</p>
			<!-- SELF-268 (Sec item 3) — same three-state basis as the §2.1.5 foot, short form. Visible
			     without hover (PRD §2.4.4 / ADR-013). Absent when composition failed to load. -->
			{#if headlineBasisNote}
				<p class="nav-basis-note">{headlineBasisNote}</p>
			{/if}
			<!-- D1 stale-data-marker (AC#4): marks stale contribution beside the number, never
			     hides it. Zero-footprint when all constituents are healthy. -->
			<StaleConstituentBadge
				isStale={staleness.is_stale}
				staleItems={staleness.stale_items}
			/>

			<!--
				THE THIRD STATE — and it is a NOTICE INSIDE THE NUMBER SURFACE, not a fourth branch
				replacing it. That structure is deliberate, for two reasons:

				(1) The number always renders. `netWorth === 0` is a successful compute and is never
				    wrong — what the failed count costs us is the ability to INTERPRET it, not the
				    value. An error screen here would discard a number we actually have.
				(2) INV-1 (ADR-013 D1). Any surface rendering this aggregation must carry the
				    staleness marker; a separate branch that re-rendered the hero would have been one
				    NAV render path with no badge on it, i.e. silent staleness — a V1 ship-block
				    defect — introduced by the shape of a fix for something else. Nesting the notice
				    means the badge above is present by construction rather than by remembering.

				Only reachable at netWorth === 0 with the count unknown: the one cell where the
				number genuinely does not stand alone. At any non-zero NAV this is deliberately
				SILENT — the headline already proves accounts exist, so a "couldn't confirm your
				account list" note there would warn about a resolved question during a transient
				blip, and noise that trains people to ignore the honest warning is worse than
				silence. (Ratified: team-lead.) Copy provisional — PM/UX.
			-->
			{#if data.netWorth === 0 && data.accountPresence === 'unknown'}
				<p class="notice">
					We couldn't load your account list just now. Please try again shortly.
				</p>
			{/if}
		</section>

		<!-- §2.1.4 NAV-at-three-reference-dates panel (SELF-223 · V1.1 — AC4: sub-surface order
		     matches Finance_Report page 3, the §2.1.4 table ABOVE the §2.1.3 panel, both below
		     the headline under the ADR-013 P2 lock). NavReferenceDatesPanel owns its own
		     fail-soft/unavailable-notice gating internally, same posture as NavDeltaPanel below. -->
		<NavReferenceDatesPanel rows={navReferenceDates} {staleness} />

		<!-- §2.1.3 multi-horizon NAV-delta panel (SELF-222 · V1.1) — Phase 2 P2 lock (ADR-013
		     Decision 3): "Headline NAV + deltas lead → 60-mo trend → composition table." Mounted
		     directly below the headline, ahead of composition/chart, visually subordinate to it
		     (NavDeltaPanel's own `.section-label` heading, not a second hero number).
		     NavDeltaPanel owns its own fail-soft/unavailable-notice gating internally — a delta
		     read failure never takes down the headline above. -->
		<NavDeltaPanel rows={navDeltaPanel} {staleness} />

		<!-- §2.1.5 composition foot (SELF-226) — the build-up below the headline on the single
		     canvas (P2 number-first). Fail-soft: renders only when the composition load succeeded;
		     absent → the headline still stands on its own. -->
		{#if composition}
			<NavCompositionTable {composition} {staleness} {excludedTaxLedgers} />
		{/if}

		<!-- §2.1.2.d NAV-over-time chart (SELF-220 · V1.1) — mounted below composition,
		     per flows/phase-2-flows-2.1-net-worth.md §12 "Mount point" (merged dba7bf1).
		     NavHistoryChart owns its own fail-soft/error/empty-state gating internally
		     (data.navSeries is independently fail-soft per +page.server.ts — a chart-data
		     read failure never took down the headline above, and doesn't gate on it here
		     either). `data.navBoundary` is 069's (pfin.fn_first_cron_checkpoint) signal,
		     fetched fresh every load() — `null` on a read failure degrades to
		     EMPTY_NAV_BOUNDARY (every point treated as post-boundary, the safe default);
		     a genuinely returned empty-store row is NOT this — it flows straight through,
		     never collapsed with the failure case (nav-boundary.ts's own header). -->
		<NavHistoryChart
			points={data.navSeries}
			paramsError={data.navSeriesParamsError}
			params={data.navSeriesParams}
			boundary={data.navBoundary ?? EMPTY_NAV_BOUNDARY}
			{staleness}
		/>
	{/if}
</main>

<style>
	.dashboard {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-7) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

	/* ── headline ─────────────────────────────────────────────────────────── */
	.nav-hero {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.nav-label {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--c-text-secondary);
	}
	.nav-value {
		margin: 0;
		/* Number-first: the dominant element on the canvas. Tabular mono for numerics. */
		font: var(--weight-bold) var(--fs-hero) / var(--lh-tight) var(--font-num);
		color: var(--c-text-primary);
		font-variant-numeric: tabular-nums;
	}
	.nav-asof {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-muted);
	}

	/* SELF-268 (Sec item 3) — the three-state tax-adjustment basis note. Same quiet register as
	   `.nav-asof` (it qualifies the number's basis, same family as the as-of date). */
	.nav-basis-note {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-muted);
	}

	/* Retriable notice under the number — the third state. Muted and secondary on purpose:
	   it qualifies the number's INTERPRETATION, it does not impeach the number. Deliberately
	   not --c-neg and not the .unavail-msg treatment; nothing here failed that the user did. */
	.notice {
		margin: var(--space-2) 0 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-muted);
	}

	/* ── unavailable (degrade) ────────────────────────────────────────────── */
	.unavailable {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.unavail-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}

	/* ── empty-state ──────────────────────────────────────────────────────── */
	.empty {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		align-items: flex-start;
	}
	.empty-title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.empty-msg {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.empty-cta {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}

	/* Anchor CTAs styled to the locked `.btn` visual language (Button.svelte renders a
	   <button>, not a link, so nav CTAs style anchors directly — tokens only). */
	.cta {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
	}
	.cta:hover {
		background: var(--c-surface-alt);
	}
	.cta:active {
		background: var(--c-surface-alt2);
	}
	.cta-primary {
		background: var(--c-accent);
		color: var(--c-accent-contrast);
		border-color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	.cta-primary:hover {
		background: var(--c-accent-hover);
		border-color: var(--c-accent-hover);
	}
	.cta-primary:active {
		background: var(--c-accent-active);
		border-color: var(--c-accent-active);
	}
</style>
