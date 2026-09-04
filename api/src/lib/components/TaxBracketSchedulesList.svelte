<!--
	TaxBracketSchedulesList.svelte -- top-level list for the §2.5.2 /settings/tax-brackets
	editor (SELF-265 AC1). Frontend-owned browser surface. Groups the loader's flat `schedules`
	array into the three named jurisdictions/types (PRD §2.5.2 (λ) Federal ordinary + Federal LT
	CG, (κ) CA FTB ordinary), in that fixed order, and renders one TaxBracketScheduleEditor per
	present schedule.

	RECONCILIATION NOTE (read before trusting the dispatch brief's provisional contract): the
	brief handed to this issue described SvelteKit form actions (`?/saveSchedule`,
	`?/createSchedule`, `?/deleteSchedule`) as Backend's in-flight shape. Neither exists on the
	tree this branch is built from (`feature/self-262`, which already carries SELF-259's LANDED
	work) -- confirmed by reading migration 101 and
	api/src/routes/api/settings/tax-brackets/[schedule_id]/+server.ts directly, not by trusting
	the brief. The REAL, landed contract is a single REST endpoint,
	POST /api/settings/tax-brackets/{schedule_id}, replace-all, on an EXISTING schedule row only
	-- its own file header states plainly that the RPC "NEVER creates a schedule... a first-time
	INSERT is a separate, out-of-scope write path" (SELF-260's seed/backfill function is the only
	current first-row writer). There is therefore NO create or delete affordance in this
	component or its editor: every schedule this page can show already exists (seeded at signup
	by `fn_provision_tax_brackets`, backfilled for existing users at migration 103), and the write
	surface this milestone shipped only supports editing one.

	MISSING-SCHEDULE RENDERING (AC7a's "never coalesced, never silent" posture, applied to the
	one case this component can actually observe: a TYPE absent from the loader's array
	entirely -- not a null field inside an existing row, which the editor itself handles).
	Per the V1.4 execution log's E22 ruling, the READ surfaces (§2.5.3, SELF-262/266) already
	define the current-year-else-latest-prior-year fallback and render the basis year rather
	than ever going silent or `$0`; that logic and its "add the next year's schedule" CTA belong
	to SELF-266's read surface, which routes its "Edit tax brackets" affordance HERE (AC6). This
	editor has no create endpoint to offer, so an absent type renders an INFORMATIONAL note
	stating the gap honestly rather than a non-functional "Add schedule" button -- never a
	silently-skipped jurisdiction and never a fabricated affordance this milestone's backend
	cannot honor.

	CONTRACT (props): `schedules` -- the loader's already-deduplicated array (at most one row per
	`schedule_type`, the latest `tax_year` on file for that type -- the loader's job, per its own
	header, not re-derived here).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TaxBracketScheduleEditor from '$lib/components/TaxBracketScheduleEditor.svelte';

	type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';

	type BracketRow = { bracket_floor: number; bracket_rate: number };

	type Schedule = {
		id: number;
		tax_year: number;
		schedule_type: ScheduleType;
		schedule_label: string;
		standard_deduction: number;
		tax_balance_prior_year: number | null;
		rows: BracketRow[];
	};

	let { schedules }: { schedules: Schedule[] } = $props();

	// PRD §2.5.2 order (λ) Federal ordinary, Federal LT CG, then (κ) CA FTB ordinary (AC1).
	const TYPE_ORDER: ScheduleType[] = ['federal_ordinary', 'federal_lt_cg', 'california_ordinary'];

	const TYPE_LABELS: Record<ScheduleType, string> = {
		federal_ordinary: 'Federal — Ordinary Income',
		federal_lt_cg: 'Federal — Long-Term Capital Gains',
		california_ordinary: 'California (FTB) — Ordinary Income'
	};

	const groups = $derived(
		TYPE_ORDER.map((type) => ({
			type,
			label: TYPE_LABELS[type],
			schedule: schedules.find((s) => s.schedule_type === type) ?? null
		}))
	);
</script>

<div class="list">
	{#each groups as group (group.type)}
		{#if group.schedule}
			<TaxBracketScheduleEditor schedule={group.schedule} />
		{:else}
			<div class="missing-note" role="status">
				<span class="missing-dot" aria-hidden="true"></span>
				<div class="missing-text">
					<p class="missing-title">No {group.label} schedule on file yet.</p>
					<p class="missing-detail">
						Estimated-tax figures for this jurisdiction will read as unavailable until a schedule
						is entered. New schedules are provisioned by the tax-year rollover process — none is
						editable here until it exists.
					</p>
				</div>
			</div>
		{/if}
	{/each}
</div>

<style>
	.list {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
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
		gap: var(--space-1);
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
</style>
