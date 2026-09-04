<!--
	TaxBracketSchedulesList.svelte -- top-level list for the §2.5.2 /settings/tax-brackets
	editor (SELF-265 AC1/AC7/AC7a). Frontend-owned browser surface. Consumes the loader's
	`jurisdictions` array VERBATIM (queries/taxBracketSchedules.ts, Backend-owned,
	feature/self-265-backend @ e1c1845) -- always exactly three entries, in
	federal_ordinary / federal_lt_cg / california_ordinary order, each carrying every schedule
	of that type plus `current_year_present` + `basis_year` computed server-side.

	RECONCILIATION HISTORY, kept for the record (this component's THIRD contract pass):
	  (1) built against a provisional, guessed contract before any Backend branch existed;
	  (2) reconciled against the real `jurisdictions[]` shape once
	      `feature/self-265-backend @ caebbec`/`e1c1845` landed, but scoped prior-year schedules
	      to delete-only (no edit) and gated delete with no "last schedule" guard;
	  (3) THIS PASS -- team-lead ruling E35 (under F/CTO delegation), three corrections: (a) a
	      prior-year schedule is the E22 fallback basis and MUST stay fully editable, not
	      delete-only -- it renders here as a collapsed `<details>` holding a full editor; (b)
	      delete renders ONLY when a jurisdiction holds more than one schedule (never on the sole
	      schedule of a type) -- computed here as `canDelete`, passed down, never re-derived by
	      the editor; (c) the create panel prefills from the NEWEST prior-year schedule as a
	      TEMPLATE (unchanged in substance from pass 2, restated because E35 confirms it as the
	      intended AC7a/E22 mechanism, not merely this component's own guess).

	PER-JURISDICTION LAYOUT:
	  - The BASIS schedule (current year if present, else the latest prior year on file, per
	    E22 -- `basis_year`) renders as the primary, always-open editor when one exists.
	  - When `current_year_present` is false, an honest E22-styled note renders above it ("No
	    {type} schedule entered for {currentTaxYear} — using {basis_year}" when a prior year
	    exists; "No {type} schedule entered" when none), plus an "Add {currentTaxYear} schedule"
	    toggle that reveals a `mode="create"` editor prefilled from the basis schedule.
	  - Every OTHER schedule on file for the type renders collapsed under "Prior years on file",
	    each its own full `mode="edit"` editor inside a native `<details>` -- editable, not a
	    read-only or delete-only row, per E35(a).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxBracketScheduleEditor from '$lib/components/TaxBracketScheduleEditor.svelte';
	import Button from '$lib/components/Button.svelte';

	type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';
	type BracketRow = { bracket_floor: number; bracket_rate: number };

	type ScheduleRecord = {
		id: number;
		tax_year: number;
		schedule_type: ScheduleType;
		schedule_label: string;
		standard_deduction: number;
		tax_balance_prior_year: number | null;
		rows: BracketRow[];
	};

	type Jurisdiction = {
		schedule_type: ScheduleType;
		schedules: ScheduleRecord[];
		current_year_present: boolean;
		basis_year: number | null;
	};

	let { jurisdictions, currentTaxYear }: { jurisdictions: Jurisdiction[]; currentTaxYear: number } = $props();

	const TYPE_LABELS: Record<ScheduleType, string> = {
		federal_ordinary: 'Federal — Ordinary Income',
		federal_lt_cg: 'Federal — Long-Term Capital Gains',
		california_ordinary: 'California (FTB) — Ordinary Income'
	};

	function basisSchedule(j: Jurisdiction): ScheduleRecord | null {
		if (j.basis_year === null) return null;
		return j.schedules.find((s) => s.tax_year === j.basis_year) ?? null;
	}

	/** Every schedule of the type OTHER than the basis one — already tax_year DESCENDING (the
	 *  loader's own order), so "newest prior year first" falls out of this filter for free. */
	function priorSchedules(j: Jurisdiction): ScheduleRecord[] {
		const basis = basisSchedule(j);
		return j.schedules.filter((s) => s.id !== basis?.id);
	}

	/** E35(b): delete renders ONLY when this jurisdiction holds more than one schedule — never
	 *  on the sole schedule of a type, current-year or not. Computed here (the LIST is the only
	 *  place that knows a jurisdiction's full schedule count) and passed down; the editor never
	 *  re-derives it. */
	function canDelete(j: Jurisdiction): boolean {
		return j.schedules.length > 1;
	}

	// Auto-open the create panel only when there's truly nothing else to show for this
	// jurisdiction (no basis at all). CORRECTED (team-lead, post-E35): this MUST be `$derived`
	// from the LIVE `jurisdictions` prop, not a one-time capture -- verified against
	// +page.svelte, which instantiates this component with no `{#key ...}` wrapper, so
	// `invalidateAll()` (fired by every editor's own `update()` on a successful submit) does
	// NOT remount it; SvelteKit re-runs `load()` and updates the `data` prop / this component's
	// `jurisdictions` prop IN PLACE on the same instance. A one-time-captured default would have
	// gone stale the instant any OTHER jurisdiction's create/save/delete completed on the same
	// page -- e.g. a type with no schedule auto-opens its create panel, the user creates a
	// schedule for a DIFFERENT type, `jurisdictions` refreshes, and the first panel would have
	// stayed forced open even though it now has a schedule.
	const autoOpenDefault = $derived(
		Object.fromEntries(jurisdictions.map((j) => [j.schedule_type, j.basis_year === null])) as Record<
			ScheduleType,
			boolean
		>
	);

	// An explicit user action (the "Add {year} schedule" click, or this schedule type's own
	// create-panel closing itself after a successful submit) OVERRIDES the derived default for
	// that one type. Reset to {} whenever `jurisdictions` itself changes reference (a genuine
	// fresh load, not merely a click) -- `$effect` reruns only when its own reactive reads
	// change, and `jurisdictions` only gets a new reference from a real reload, never from a
	// local `userToggled` mutation, so this cannot fight a user's own in-progress click.
	let userToggled = $state<Partial<Record<ScheduleType, boolean>>>({});
	$effect(() => {
		jurisdictions;
		userToggled = {};
	});

	const openCreate = $derived(
		Object.fromEntries(
			jurisdictions.map((j) => [j.schedule_type, userToggled[j.schedule_type] ?? autoOpenDefault[j.schedule_type]])
		) as Record<ScheduleType, boolean>
	);
</script>

<div class="list">
	{#each jurisdictions as j (j.schedule_type)}
		{@const basis = basisSchedule(j)}
		{@const priors = priorSchedules(j)}
		{@const deletable = canDelete(j)}
		<section class="jurisdiction" aria-labelledby={`jur-${j.schedule_type}`}>
			<h2 id={`jur-${j.schedule_type}`} class="jurisdiction-title">{TYPE_LABELS[j.schedule_type]}</h2>

			{#if !j.current_year_present}
				<div class="missing-note" role="status">
					<span class="missing-dot" aria-hidden="true"></span>
					<div class="missing-text">
						{#if basis}
							<p class="missing-title">
								No {TYPE_LABELS[j.schedule_type]} schedule entered for {currentTaxYear} — using {basis.tax_year}.
							</p>
						{:else}
							<p class="missing-title">No {TYPE_LABELS[j.schedule_type]} schedule entered.</p>
						{/if}
						{#if !openCreate[j.schedule_type]}
							<Button variant="secondary" type="button" onclick={() => (userToggled[j.schedule_type] = true)}>
								Add {currentTaxYear} schedule
							</Button>
						{/if}
					</div>
				</div>
			{/if}

			{#if openCreate[j.schedule_type]}
				<TaxBracketScheduleEditor
					mode="create"
					scheduleType={j.schedule_type}
					taxYear={currentTaxYear}
					initialLabel={basis?.schedule_label ?? ''}
					initialStandardDeduction={basis?.standard_deduction ?? 0}
					initialPriorYearBalance={null}
					initialRows={basis?.rows ?? [{ bracket_floor: 0, bracket_rate: 0 }]}
					onSaved={() => (userToggled[j.schedule_type] = false)}
				/>
			{/if}

			{#if basis}
				<TaxBracketScheduleEditor
					mode="edit"
					scheduleType={j.schedule_type}
					taxYear={basis.tax_year}
					scheduleId={basis.id}
					initialLabel={basis.schedule_label}
					initialStandardDeduction={basis.standard_deduction}
					initialPriorYearBalance={basis.tax_balance_prior_year}
					initialRows={basis.rows}
					canDelete={deletable}
				/>
			{/if}

			{#if priors.length > 0}
				<div class="prior-schedules">
					<h3 class="prior-title">Prior years on file</h3>
					{#each priors as s (s.id)}
						<details class="prior-details">
							<summary class="prior-summary">{s.tax_year} — {s.schedule_label}</summary>
							<TaxBracketScheduleEditor
								mode="edit"
								scheduleType={j.schedule_type}
								taxYear={s.tax_year}
								scheduleId={s.id}
								initialLabel={s.schedule_label}
								initialStandardDeduction={s.standard_deduction}
								initialPriorYearBalance={s.tax_balance_prior_year}
								initialRows={s.rows}
								canDelete={deletable}
							/>
						</details>
					{/each}
				</div>
			{/if}
		</section>
	{/each}
</div>

<style>
	.list {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}
	.jurisdiction {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.jurisdiction-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	/* Same --c-attn-* "confirmed, actionable-adjacent" register UnpricedMarker.svelte /
	   StaleConstituentBadge use for a definite, financially material gap in this render. */
	.missing-note {
		display: flex;
		align-items: flex-start;
		gap: var(--space-2);
		padding: var(--space-3) var(--space-4);
		border: 1px solid var(--c-attn-border);
		border-left: var(--space-1) solid var(--c-attn-solid);
		border-radius: var(--radius-md);
		background: var(--c-attn-bg);
	}
	.missing-dot {
		width: 0.5rem;
		height: 0.5rem;
		margin-top: 6px;
		border-radius: var(--radius-pill);
		background: var(--c-attn-solid);
		flex: 0 0 auto;
	}
	.missing-text {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-2);
	}
	.missing-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-ui);
		color: var(--c-attn-text);
	}
	.prior-schedules {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.prior-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	.prior-details {
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.prior-summary {
		cursor: pointer;
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
	}
	.prior-summary:focus-visible {
		outline: none;
		box-shadow: var(--focus-ring);
	}
	/* The full editor renders inside the <details>, already carrying its own surface/border/
	   shadow — a small breathing margin keeps it from touching the disclosure's own edge. */
	.prior-details > :global(form) {
		margin: var(--space-2);
	}
</style>
