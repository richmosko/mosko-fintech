<!--
	TaxBracketScheduleEditor.svelte -- the per-schedule §2.5.2 tax-bracket editor (SELF-265).
	Frontend-owned browser surface. Renders and replace-all-saves ONE
	pfin.tax_bracket_schedule row plus its FULL pfin.tax_bracket_row set, against Backend's
	landed write path (SELF-259, migration 101, feature/self-262 base -- read live, not the
	dispatch brief's provisional `?/saveSchedule` form-action shape, which does not exist on the
	tree: see the file-header note on the parent list component for the full reconciliation).

	CONTRACT (props):
	  schedule : {
	    id: number; tax_year: number;
	    schedule_type: 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';
	    schedule_label: string; standard_deduction: number;
	    tax_balance_prior_year: number | null;
	    rows: { bracket_floor: number; bracket_rate: number }[]; -- pre-sorted ascending by
	      bracket_floor (the loader's job, not this component's).
	  }
	  READ VERBATIM from the settings/tax-brackets loader, which reads
	  pfin.tax_bracket_schedule / pfin.tax_bracket_row directly (migration 101; SELF-259's
	  own +server.ts ownership-read pattern) -- no Backend query module exists yet for this
	  list shape (EXPECTED CONTRACT gap, flagged at hand-off), so the loader is this branch's
	  own thin read, following the SELF-242/241/325 "+page.svelte ahead of Backend's loader"
	  precedent one level up (a +page.server.ts loader ahead of a query module, not a
	  component ahead of a loader -- the underlying tables + RLS + write endpoint are
	  landed and confirmed against 101 and self259-sec-review.md).

	WRITE PATH -- REAL, LANDED CONTRACT (not the dispatch brief's guess): POST
	/api/settings/tax-brackets/{schedule_id}, replace-all, every scalar field REQUIRED on every
	POST (101: "the schedule and its rows are replaced as ONE unit" -- there is no partial
	UPSERT and therefore no dirty-diff-omit-untouched-fields shape the Planning/Cashflow editors
	use; every Save sends the FULL current form state). `tax_year` / `schedule_type` are sent
	back UNCHANGED as an identity guard the endpoint enforces (409 schedule_identity_mismatch on
	a mismatch) -- this component never offers to edit them. WHY FETCH, NOT A FORM ACTION: same
	carve-out PlanningTargetEditor / CashflowTargetEditor state -- the endpoint is a raw JSON
	REST route (+server.ts), not a page form action, and there IS no `?/saveSchedule` action on
	this tree to bind to.

	PERCENT <-> FRACTION BOUNDARY (E1 / migration 101's ruling): `bracket_rate` is a FRACTION in
	the DB (0.22, checked 0<=x<=1) -- this editor shows and edits PERCENT (22) because that is
	how the IRS/FTB publish these tables and how a human types them, per 101's own recorded
	rationale. The conversion happens at `sanitizeBracketRatePercent` / `fractionRateToPercentDisplay`
	($lib/validation/numeric.ts) -- the ONLY place the boundary is crossed; every other function
	in this file (courtesy row-ordering, the payload builder) operates on the FRACTION value.

	VALIDATION (Lock 14 mod #2, client mirror -- $lib/validation/numeric.ts +
	$lib/validation/scheduleLabel.ts + $lib/validation/taxBracketRows.ts): the SAME shared
	numeric battery the server enforces, shaped per-field to 101's own typmods, plus a courtesy
	mirror of the write endpoint's own `precheckRowOrdering` (zero-floor + rate-monotonicity,
	AC5 / R4 rider 8 item 5). ⚠ STATED PER Lock 14 mod #2's own posture: the DB's deferred
	CONSTRAINT TRIGGER is the control; this is UX fast-feedback that can reject BEFORE a round
	trip, never a claim that passing it guarantees the DB will accept the write.

	STANDARD DEDUCTION ZERO ("this schedule takes no deduction", AC2): `federal_lt_cg` is seeded
	with `standard_deduction = 0` meaning "this schedule takes no deduction" (SELF-260 AC1), a
	stated fact rather than an unset value -- the column is NOT NULL, so there is no separate
	"blank" representation to render here at all. This editor renders an explanatory caption on
	that field WHENEVER `schedule_type === 'federal_lt_cg'`, regardless of the current entered
	value, framing a `0` there as the schedule's known nature rather than an accidental omission.

	FIRST-ROW FLOOR IS STRUCTURALLY FIXED AT 0, NOT MERELY VALIDATED (judgment call, flagged at
	hand-off): 101's own zero-floor leg makes any non-zero first floor a guaranteed rejection --
	rather than only catching that after a courtesy-check message or a round trip, the first
	row's floor field renders disabled at "0" and is excluded from user editing entirely. Every
	OTHER row's floor is a free currency field. This makes the wrong choice unreachable for the
	one row where "wrong" is unconditional, the same "structural picker over validation-only
	rejection" pattern SELF-325's account-type field used (Architect-praised precedent).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). No staleness-marker here --
	a tax-bracket schedule is user-authored settings data, not a derived aggregation over account
	balances (same ADR-013 D1 exemption Planning/CashflowTargetEditor's own headers state).
-->
<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import TextField from '$lib/components/TextField.svelte';
	import TextAreaField from '$lib/components/TextAreaField.svelte';
	import Button from '$lib/components/Button.svelte';
	import {
		sanitizeCurrencyAmount,
		sanitizeBracketRatePercent,
		fractionRateToPercentDisplay
	} from '$lib/validation/numeric';
	import { sanitizeScheduleLabel } from '$lib/validation/scheduleLabel';
	import { precheckRowOrdering, type BracketRowInput } from '$lib/validation/taxBracketRows';

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

	let { schedule }: { schedule: Schedule } = $props();

	// Working row shape: STRING fields, one per input, the rate held as the PERCENT string the
	// field displays (never the fraction) -- see file header's percent/fraction boundary note.
	type RowDraft = { floor: string; ratePercent: string };

	function toDraftRows(rows: BracketRow[]): RowDraft[] {
		return rows.map((r) => ({
			floor: String(r.bracket_floor),
			ratePercent: fractionRateToPercentDisplay(r.bracket_rate)
		}));
	}

	let label = $state(schedule.schedule_label);
	let standardDeduction = $state(String(schedule.standard_deduction));
	let priorYearBalance = $state(
		schedule.tax_balance_prior_year === null ? '' : String(schedule.tax_balance_prior_year)
	);
	let rows = $state<RowDraft[]>(toDraftRows(schedule.rows));

	let serverFieldErrors = $state<Record<string, string[]>>({});
	let formError = $state('');
	let statusMessage = $state('');
	let saving = $state(false);

	function addRow() {
		rows.push({ floor: '', ratePercent: '' });
	}

	function removeRow(index: number) {
		if (rows.length <= 1) return; // the endpoint requires at least one row (AC2/101)
		rows.splice(index, 1);
	}

	function labelError(): string | null {
		const r = sanitizeScheduleLabel(label);
		return r.ok ? null : r.reason;
	}

	function standardDeductionError(): string | null {
		const r = sanitizeCurrencyAmount(standardDeduction);
		if (!r.ok) return r.reason;
		if (r.value < 0) return 'Enter a non-negative amount.';
		return null;
	}

	/** `tax_balance_prior_year` is nullable and carries no sign bound (101: "a prior-year
	 *  balance can be an overpayment and is then legitimately negative") -- an empty field is
	 *  the unset representation, never an error. */
	function priorYearBalanceError(): string | null {
		if (priorYearBalance === '') return null;
		const r = sanitizeCurrencyAmount(priorYearBalance);
		return r.ok ? null : r.reason;
	}

	function rowFloorError(index: number): string | null {
		if (index === 0) return null; // structurally fixed at 0 -- see file header
		const r = sanitizeCurrencyAmount(rows[index].floor);
		if (!r.ok) return r.reason;
		if (r.value < 0) return 'Enter a non-negative amount.';
		return null;
	}

	function rowRateError(index: number): string | null {
		const r = sanitizeBracketRatePercent(rows[index].ratePercent);
		return r.ok ? null : r.reason;
	}

	/** Parses every row into the FRACTION-unit shape the endpoint expects, or null if any cell
	 *  fails its own per-field check (caller shows those per-field messages; this is only the
	 *  gate for whether the courtesy row-ordering check and the submit payload can run at all). */
	function parsedRowsOrNull(): BracketRowInput[] | null {
		const out: BracketRowInput[] = [];
		for (let i = 0; i < rows.length; i++) {
			const floorRaw = i === 0 ? '0' : rows[i].floor;
			const floorResult = sanitizeCurrencyAmount(floorRaw);
			const rateResult = sanitizeBracketRatePercent(rows[i].ratePercent);
			if (!floorResult.ok || floorResult.value < 0 || !rateResult.ok) return null;
			out.push({ bracket_floor: floorResult.value, bracket_rate: rateResult.value });
		}
		return out;
	}

	const rowOrderingMessage = $derived.by(() => {
		const parsed = parsedRowsOrNull();
		if (parsed === null) return null; // per-field errors already cover this case
		const result = precheckRowOrdering(parsed);
		return result.ok ? null : result.reason;
	});

	const anyFieldError = $derived(
		labelError() !== null ||
			standardDeductionError() !== null ||
			priorYearBalanceError() !== null ||
			rows.some((_, i) => rowFloorError(i) !== null || rowRateError(i) !== null)
	);

	const saveDisabled = $derived(anyFieldError || rowOrderingMessage !== null || saving);

	const SCHEDULE_TYPE_LABELS: Record<ScheduleType, string> = {
		federal_ordinary: 'Federal — Ordinary Income',
		federal_lt_cg: 'Federal — Long-Term Capital Gains',
		california_ordinary: 'California (FTB) — Ordinary Income'
	};

	async function extractError(res: Response): Promise<{ formError: string; fieldErrors?: Record<string, string[]> }> {
		let body: unknown = null;
		try {
			body = await res.json();
		} catch {
			/* fall through to generic message */
		}
		const b = body as { error?: string; fieldErrors?: Record<string, string[]>; reason?: string } | null;
		if (res.status === 401) return { formError: 'Please sign in again.' };
		if (res.status === 403 && b?.error === 'step_up_required') {
			return { formError: "Verify it's you and try again." };
		}
		if (res.status === 404) return { formError: 'This schedule could not be found. Refresh and try again.' };
		if (res.status === 409 && b?.error === 'schedule_identity_mismatch') {
			return { formError: 'This schedule’s year or type changed elsewhere. Refresh and try again.' };
		}
		if (res.status === 409 && b?.error === 'schedule_conflict') {
			return { formError: 'A schedule for this year and type already exists.' };
		}
		if (res.status === 409 && b?.error === 'concurrent_update_retry') {
			return { formError: 'Someone else is editing this schedule right now. Try saving again.' };
		}
		if (res.status === 400 && b?.error === 'invalid_row_order') {
			return { formError: b.reason ?? 'The bracket rows are not in a valid order.' };
		}
		if (res.status === 400 && b?.fieldErrors) {
			return { formError: 'Some changes could not be saved — see the fields below.', fieldErrors: b.fieldErrors };
		}
		if (b?.error === 'invalid_schedule') return { formError: 'This schedule could not be saved.' };
		return { formError: 'Something went wrong saving your changes. Please try again.' };
	}

	async function handleSave(event: SubmitEvent) {
		event.preventDefault();
		if (saveDisabled) return;

		const parsedRows = parsedRowsOrNull();
		const labelResult = sanitizeScheduleLabel(label);
		const deductionResult = sanitizeCurrencyAmount(standardDeduction);
		const priorYearResult = priorYearBalance === '' ? null : sanitizeCurrencyAmount(priorYearBalance);
		if (
			parsedRows === null ||
			!labelResult.ok ||
			!deductionResult.ok ||
			(priorYearResult !== null && !priorYearResult.ok)
		) {
			return; // saveDisabled already guards this; defensive no-op
		}

		formError = '';
		serverFieldErrors = {};
		statusMessage = '';
		saving = true;

		try {
			const res = await fetch(`/api/settings/tax-brackets/${schedule.id}`, {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify({
					tax_year: schedule.tax_year,
					schedule_type: schedule.schedule_type,
					schedule_label: labelResult.value,
					standard_deduction: deductionResult.value,
					tax_balance_prior_year: priorYearResult === null ? null : priorYearResult.value,
					rows: parsedRows
				})
			});

			if (!res.ok) {
				const { formError: fe, fieldErrors } = await extractError(res);
				formError = fe;
				if (fieldErrors) serverFieldErrors = fieldErrors;
				saving = false;
				return;
			}

			statusMessage = 'Changes saved.';
			saving = false;
			await invalidateAll();
		} catch {
			formError = 'Something went wrong saving your changes. Please try again.';
			saving = false;
		}
	}
</script>

<form class="editor" onsubmit={handleSave}>
	<div class="editor-head">
		<h3 class="schedule-title">{SCHEDULE_TYPE_LABELS[schedule.schedule_type]}</h3>
		<span class="tax-year">Tax year {schedule.tax_year}</span>
	</div>

	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}
	{#if statusMessage}
		<p class="sr-only" role="status">{statusMessage}</p>
	{/if}

	<TextAreaField
		label="Schedule label"
		name={`schedule-label-${schedule.id}`}
		bind:value={label}
		required
		rows={3}
		maxlength={500}
		hint="States the filing status, basis year, and any composed statute this schedule's numbers rest on. You can revise this."
		errors={[...(serverFieldErrors.schedule_label ?? []), ...(labelError() ? [labelError() as string] : [])]}
	/>

	<div class="scalar-row">
		<TextField
			label="Standard deduction"
			name={`std-deduction-${schedule.id}`}
			bind:value={standardDeduction}
			inputmode="decimal"
			numeric
			placeholder="0.00"
			hint={schedule.schedule_type === 'federal_lt_cg'
				? 'Federal long-term capital gains takes no separate standard deduction — 0 is a stated fact for this schedule, not a blank.'
				: undefined}
			errors={[
				...(serverFieldErrors.standard_deduction ?? []),
				...(standardDeductionError() ? [standardDeductionError() as string] : [])
			]}
		/>
		<TextField
			label="Prior-year tax balance"
			name={`prior-balance-${schedule.id}`}
			bind:value={priorYearBalance}
			inputmode="decimal"
			numeric
			placeholder="—"
			hint="Informational only — never enters the estimated-tax computation. Leave blank if unset."
			errors={[
				...(serverFieldErrors.tax_balance_prior_year ?? []),
				...(priorYearBalanceError() ? [priorYearBalanceError() as string] : [])
			]}
		/>
	</div>

	<div class="rows-section">
		<div class="rows-head">
			<h4 class="rows-title">Bracket rows</h4>
			<Button variant="secondary" type="button" onclick={addRow}>Add bracket</Button>
		</div>

		{#if rowOrderingMessage}
			<p class="banner" role="alert">{rowOrderingMessage}</p>
		{/if}
		{#if serverFieldErrors.rows}
			<p class="banner" role="alert">{serverFieldErrors.rows.join(' ')}</p>
		{/if}

		<div class="table-scroll">
			<table class="rows-table">
				<thead>
					<tr>
						<th scope="col">Bracket floor ($)</th>
						<th scope="col">Marginal rate (%)</th>
						<th scope="col"><span class="sr-only">Remove</span></th>
					</tr>
				</thead>
				<tbody>
					{#each rows as row, i (i)}
						<tr>
							<td>
								{#if i === 0}
									<div class="fixed-floor-field">
										<span class="fixed-floor-label" id={`fixed-floor-label-${schedule.id}`}
											>Bracket 1 floor</span
										>
										<input
											class="field-input num-input fixed-floor"
											type="text"
											inputmode="decimal"
											value="0"
											disabled
											aria-labelledby={`fixed-floor-label-${schedule.id}`}
										/>
									</div>
								{:else}
									<TextField
										label={`Bracket ${i + 1} floor`}
										name={`row-floor-${schedule.id}-${i}`}
										bind:value={row.floor}
										inputmode="decimal"
										numeric
										placeholder="0.00"
										errors={rowFloorError(i) ? [rowFloorError(i) as string] : []}
									/>
								{/if}
							</td>
							<td>
								<TextField
									label={`Bracket ${i + 1} rate`}
									name={`row-rate-${schedule.id}-${i}`}
									bind:value={row.ratePercent}
									inputmode="decimal"
									numeric
									placeholder="0.00"
									errors={rowRateError(i) ? [rowRateError(i) as string] : []}
								/>
							</td>
							<td>
								<Button
									variant="link"
									type="button"
									disabled={rows.length <= 1}
									onclick={() => removeRow(i)}
									aria-label={`Remove bracket ${i + 1}`}
								>
									Remove
								</Button>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</div>

	<div class="actions">
		<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>
			Save changes
		</Button>
	</div>
</form>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.editor-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.schedule-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / 1.2 var(--font-ui);
		color: var(--c-text-primary);
	}
	.tax-year {
		font-family: var(--font-num);
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.scalar-row {
		display: flex;
		gap: var(--space-4);
		flex-wrap: wrap;
	}
	.scalar-row :global(.field) {
		flex: 1 1 14rem;
	}
	.rows-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}
	.rows-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.rows-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.02em;
	}
	.table-scroll {
		overflow-x: auto;
	}
	.rows-table {
		width: 100%;
		border-collapse: collapse;
	}
	.rows-table th {
		text-align: left;
		font: var(--weight-semi) var(--fs-small) / 1.2 var(--font-ui);
		color: var(--c-text-secondary);
		padding: var(--space-1) var(--space-2);
	}
	.rows-table td {
		padding: var(--space-1) var(--space-2);
		vertical-align: bottom;
	}
	.rows-table :global(.field) {
		min-width: 8rem;
	}
	.fixed-floor-field {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.fixed-floor-label {
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.fixed-floor {
		width: 100%;
		box-sizing: border-box;
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
		color: var(--c-text-secondary);
		padding: var(--space-2) var(--space-3);
		font: var(--fs-body) / 1.2 var(--font-num);
		text-align: right;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
	}
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-neg);
	}
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
</style>
