<!--
	TaxBracketSchedulesList.svelte -- top-level list for the §2.5.2 /settings/tax-brackets
	editor (SELF-265 AC1/AC7/AC7a). Frontend-owned browser surface. Consumes the loader's
	`jurisdictions` array VERBATIM (queries/taxBracketSchedules.ts, Backend-owned,
	feature/self-265-backend @ caebbec) -- always exactly three entries, in
	federal_ordinary / federal_lt_cg / california_ordinary order, each carrying every schedule
	of that type plus `current_year_present` + `basis_year` computed server-side.

	RECONCILIATION NOTE, KEPT FOR THE RECORD (this component's second full contract): an earlier
	revision of this file was built against a provisional, guessed contract before Backend's
	actions landed, then reconciled here against the REAL, landed shape once
	`feature/self-265-backend @ caebbec` existed (`jurisdictions[]` with `current_year_present` /
	`basis_year`, not the earlier `schedules[]` + `basis` guess; real `?/saveSchedule` /
	`?/createSchedule` / `?/deleteSchedule` form actions, which now DO exist, superseding the
	prior "no create/delete affordance" scoping this component carried before those actions
	shipped).

	PER-JURISDICTION LAYOUT (a judgment call, flagged at hand-off -- the ACs fix the three
	groups and the AC7a CTA, not this exact composition):
	  - The BASIS schedule (the one at `basis_year` -- current year if present, else the latest
	    prior year on file, per E22) renders as the primary, always-visible editor when one
	    exists.
	  - When `current_year_present` is false, an AC7a/E22-styled informational note renders
	    ABOVE the basis editor (or in its place, when no basis exists at all), naming the exact
	    gap honestly, plus an "Add {currentTaxYear} schedule" toggle that reveals a `mode="create"`
	    editor prefilled from the basis schedule as a starting TEMPLATE (or blank, one zero-floor
	    row, when no basis exists) -- this is what actually answers the CTA now that
	    `?/createSchedule` exists, unlike this component's prior revision.
	  - Any OTHER schedule on file for the type (an old year superseded by a newer one) renders
	    in a compact "Other years on file" list with its own inline-confirm delete control,
	    never a full second editor -- keeps the common case (one schedule per type) visually
	    dominant while still exposing the real delete capability for a stray old year.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxBracketScheduleEditor from '$lib/components/TaxBracketScheduleEditor.svelte';
	import DeleteScheduleControl from '$lib/components/DeleteScheduleControl.svelte';
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

	function otherSchedules(j: Jurisdiction): ScheduleRecord[] {
		const basis = basisSchedule(j);
		return j.schedules.filter((s) => s.id !== basis?.id);
	}

	// Auto-open the create panel only when there's truly nothing else to show for this
	// jurisdiction (no basis at all); otherwise it opens on click. One-time capture from the
	// loader's own initial props -- same deliberate `state_referenced_locally` shape
	// Planning/CashflowTargetEditor's own baselines document (a fresh load() after a save
	// re-derives this from the NEW `jurisdictions` prop via a full component remount at the
	// page level, which is what SvelteKit's `invalidateAll`-on-`update()` produces here).
	let openCreate = $state<Record<ScheduleType, boolean>>(
		Object.fromEntries(jurisdictions.map((j) => [j.schedule_type, j.basis_year === null])) as Record<
			ScheduleType,
			boolean
		>
	);
</script>

<div class="list">
	{#each jurisdictions as j (j.schedule_type)}
		{@const basis = basisSchedule(j)}
		{@const others = otherSchedules(j)}
		<section class="jurisdiction" aria-labelledby={`jur-${j.schedule_type}`}>
			<h2 id={`jur-${j.schedule_type}`} class="jurisdiction-title">{TYPE_LABELS[j.schedule_type]}</h2>

			{#if !j.current_year_present}
				<div class="missing-note" role="status">
					<span class="missing-dot" aria-hidden="true"></span>
					<div class="missing-text">
						{#if basis}
							<p class="missing-title">
								{TYPE_LABELS[j.schedule_type]} for {currentTaxYear} hasn't been entered yet — figures
								currently run on the {basis.tax_year} schedule.
							</p>
						{:else}
							<p class="missing-title">No {TYPE_LABELS[j.schedule_type]} schedule on file yet.</p>
							<p class="missing-detail">
								Estimated-tax figures for this jurisdiction render as unavailable until one is
								entered.
							</p>
						{/if}
						{#if !openCreate[j.schedule_type]}
							<Button variant="secondary" type="button" onclick={() => (openCreate[j.schedule_type] = true)}>
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
					onSaved={() => (openCreate[j.schedule_type] = false)}
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
				/>
			{/if}

			{#if others.length > 0}
				<div class="other-schedules">
					<h3 class="other-title">Other years on file</h3>
					<ul class="other-list">
						{#each others as s (s.id)}
							<li class="other-row">
								<span class="other-label">{s.tax_year} — {s.schedule_label}</span>
								<DeleteScheduleControl
									scheduleId={s.id}
									itemLabel={`${TYPE_LABELS[j.schedule_type]} (tax year ${s.tax_year})`}
								/>
							</li>
						{/each}
					</ul>
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
	.missing-detail {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-attn-text);
	}
	.other-schedules {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.other-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	.other-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.other-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
		padding: var(--space-2) var(--space-3);
		background: var(--c-surface-alt);
		border-radius: var(--radius-md);
	}
	.other-label {
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
