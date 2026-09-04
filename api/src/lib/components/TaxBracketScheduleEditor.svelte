<!--
	TaxBracketScheduleEditor.svelte -- the per-schedule §2.5.2 tax-bracket editor (SELF-265).
	Frontend-owned browser surface. In `mode="edit"` replace-alls ONE EXISTING
	pfin.tax_bracket_schedule row plus its FULL pfin.tax_bracket_row set; in `mode="create"` it
	INSERTs a new schedule row (a jurisdiction's first schedule, or a new tax_year for one that
	already has schedules) and then runs the same replace-all for its rows. Both modes post
	against Backend's landed contract: `?/saveSchedule` / `?/createSchedule` form actions
	(api/src/routes/settings/tax-brackets/+page.server.ts, feature/self-265-backend @ caebbec) —
	real SvelteKit form actions, per api/CLAUDE.md's Frontend convention, not the fetch+JSON
	carve-out an earlier revision of this file used before Backend's actions landed.

	CONTRACT (props):
	  mode                     : 'edit' | 'create'
	  scheduleType             : 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary'
	  taxYear                  : the schedule's tax_year -- for 'edit' the existing row's own
	                             year (read-only, posted as a hidden identity field the action's
	                             own guard enforces); for 'create' the caller's chosen year
	                             (TaxBracketSchedulesList.svelte fixes this to `currentTaxYear`
	                             -- there is no UI to create an arbitrary past/future year).
	  scheduleId               : required when mode === 'edit' -- the existing row's id.
	  initialLabel / initialStandardDeduction / initialPriorYearBalance / initialRows :
	                             the form's starting values. For 'edit' these are the existing
	                             row's own values (READ VERBATIM from the loader). For 'create'
	                             the CALLER decides what to prefill (TaxBracketSchedulesList.svelte
	                             prefills from the jurisdiction's own basis-year schedule as a
	                             starting TEMPLATE when one exists, per AC7's "seed is a template,
	                             not a determination" posture generalized to a year-rollover
	                             template).
	  onSaved                  : optional callback fired after a successful submit (either mode)
	                             -- TaxBracketSchedulesList.svelte uses this to collapse a
	                             just-completed create panel.
	  canDelete                : edit mode only. Team-lead ruling E35: delete renders ONLY when
	                             this jurisdiction holds more than one schedule -- never on the
	                             sole schedule of a type, current-year or not. The LIST component
	                             computes this (it alone knows the jurisdiction's full schedule
	                             count); this component does not re-derive it. Ignored/absent in
	                             'create' mode (nothing exists yet to delete).

	FORM SHAPE -- HIDDEN IDENTITY FIELDS, VISIBLE DATA FIELDS NAMED TO MATCH THE ACTION'S OWN
	FormData READ (parseReplaceFormData in +page.server.ts): `tax_year` / `schedule_type` are
	hidden (never user-editable -- the action's schedule-identity guard refuses a mismatch rather
	than silently repointing a schedule); `schedule_id` is hidden and edit-mode-only;
	`schedule_label` / `standard_deduction` / `tax_balance_prior_year` are the VISIBLE fields'
	own `name` attributes (the browser's native FormData collects them directly -- no manual
	`formData.set()` needed for these, matching PurchaseEntryForm.svelte's own "declarative
	hidden/named fields over imperative FormData mutation" idiom); `rows` is a hidden field
	carrying the current row set as a JSON string (the same "no JSON-array-in-FormData
	precedent existed, so this is the chosen shape" judgment call +page.server.ts's own header
	names) -- ALWAYS the FRACTION-unit shape the shared schema expects, built by
	`parsedRowsOrNull()` from the percent strings the row table actually edits.

	Each visible <input>'s DOM `id` is namespaced per instance (`id={... }` override, added to
	TextField.svelte / TextAreaField.svelte for this issue) because several editor instances on
	one page share the SAME server-required `name` (e.g. every editor's deduction field is named
	"standard_deduction") across DIFFERENT <form>s -- `name` uniqueness is scoped per-form, `id`
	uniqueness is scoped to the whole document, and TextField previously derived one from the
	other.

	PERCENT <-> FRACTION BOUNDARY (E1 / migration 101's ruling) and the numeric/label/row-ordering
	client mirrors are UNCHANGED from this file's earlier fetch+JSON revision -- see
	$lib/validation/numeric.ts, scheduleLabel.ts, taxBracketRows.ts. STANDARD DEDUCTION ZERO
	("this schedule takes no deduction", AC2) and the FIRST-ROW-FLOOR-STRUCTURALLY-FIXED-AT-0
	judgment call are likewise unchanged -- see their own inline comments below.

	SUBMIT-RESULT HANDLING: this component reads the `result` its OWN `use:enhance` SubmitFunction
	callback receives, never the page's shared `form` prop -- with several forms on one page,
	SvelteKit's page-level `form` prop is ambiguous about which form's result it holds, but each
	form's own enhance callback is guaranteed to fire only for that form's own submission
	(PurchaseEntryForm.svelte's own pattern). ⚠ TEST-HARNESS LIMIT, stated rather than silently
	worked around: `tests/stubs/app-forms.ts`'s `enhance` stub deliberately does NOT invoke this
	returned callback (no fetch/network pipeline in that stub) -- so this file's own dom test
	cannot exercise server-error rendering after a real submit, only the pre-submit
	client-validation gate and the raw FormData a submit would carry. Same scope boundary
	PurchaseEntryForm.dom.test.ts already accepts for the same reason.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). No staleness-marker here --
	a tax-bracket schedule is user-authored settings data, not a derived aggregation over account
	balances (same ADR-013 D1 exemption Planning/CashflowTargetEditor's own headers state).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextField from '$lib/components/TextField.svelte';
	import TextAreaField from '$lib/components/TextAreaField.svelte';
	import Button from '$lib/components/Button.svelte';
	import DeleteScheduleControl from '$lib/components/DeleteScheduleControl.svelte';
	import {
		sanitizeCurrencyAmount,
		sanitizeBracketRatePercent,
		fractionRateToPercentDisplay
	} from '$lib/validation/numeric';
	import { sanitizeScheduleLabel } from '$lib/validation/scheduleLabel';
	import { precheckRowOrdering, type BracketRowInput } from '$lib/validation/taxBracketRows';

	type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';
	type BracketRow = { bracket_floor: number; bracket_rate: number };

	let {
		mode,
		scheduleType,
		taxYear,
		scheduleId,
		initialLabel,
		initialStandardDeduction,
		initialPriorYearBalance,
		initialRows,
		onSaved,
		canDelete = false
	}: {
		mode: 'edit' | 'create';
		scheduleType: ScheduleType;
		taxYear: number;
		scheduleId?: number;
		initialLabel: string;
		initialStandardDeduction: number;
		initialPriorYearBalance: number | null;
		initialRows: BracketRow[];
		onSaved?: () => void;
		canDelete?: boolean;
	} = $props();

	// Namespaces every DOM id on this instance -- see file header's id-collision note. A
	// one-time capture from props is deliberate (same `state_referenced_locally` shape
	// Planning/CashflowTargetEditor's own baselines already document): an instance's identity
	// (which schedule/year/mode it edits) does not change over its lifetime.
	const instanceKey = `${scheduleType}-${mode}-${taxYear}`;

	// Working row shape: STRING fields, one per input, the rate held as the PERCENT string the
	// field displays (never the fraction) -- see file header's percent/fraction boundary note.
	type RowDraft = { floor: string; ratePercent: string };

	function toDraftRows(rows: BracketRow[]): RowDraft[] {
		return rows.map((r) => ({
			floor: String(r.bracket_floor),
			ratePercent: fractionRateToPercentDisplay(r.bracket_rate)
		}));
	}

	let label = $state(initialLabel);
	let standardDeduction = $state(String(initialStandardDeduction));
	let priorYearBalance = $state(initialPriorYearBalance === null ? '' : String(initialPriorYearBalance));
	let rows = $state<RowDraft[]>(toDraftRows(initialRows.length > 0 ? initialRows : [{ bracket_floor: 0, bracket_rate: 0 }]));

	let serverFieldErrors = $state<Record<string, string[]>>({});
	let formError = $state('');
	let statusMessage = $state('');
	let saving = $state(false);

	function addRow() {
		rows.push({ floor: '', ratePercent: '' });
	}

	function removeRow(index: number) {
		if (rows.length <= 1) return; // the action requires at least one row (AC2/101)
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
	 *  the unset representation, never an error. The action's own FormData parsing already
	 *  translates an empty string to `null` server-side, so this field's `name` posts as-is. */
	function priorYearBalanceError(): string | null {
		if (priorYearBalance === '') return null;
		const r = sanitizeCurrencyAmount(priorYearBalance);
		return r.ok ? null : r.reason;
	}

	function rowFloorError(index: number): string | null {
		if (index === 0) return null; // structurally fixed at 0 -- see below
		const r = sanitizeCurrencyAmount(rows[index].floor);
		if (!r.ok) return r.reason;
		if (r.value < 0) return 'Enter a non-negative amount.';
		return null;
	}

	function rowRateError(index: number): string | null {
		const r = sanitizeBracketRatePercent(rows[index].ratePercent);
		return r.ok ? null : r.reason;
	}

	/** Parses every row into the FRACTION-unit shape the action expects, or null if any cell
	 *  fails its own per-field check (caller shows those per-field messages; this is only the
	 *  gate for whether the courtesy row-ordering check and the hidden `rows` field can build a
	 *  real payload at all). */
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

	// Hidden `rows` field -- always the FRACTION shape, '[]' when the draft can't parse (Save is
	// disabled in that case; this is a defensive fallback, never the guard itself).
	const rowsJson = $derived(JSON.stringify(parsedRowsOrNull() ?? []));

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

	const actionPath = mode === 'edit' ? '?/saveSchedule' : '?/createSchedule';
	const submitButtonLabel = mode === 'edit' ? 'Save changes' : 'Create schedule';

	type ActionSuccess = { action: 'saveSchedule' | 'createSchedule'; ok: true; scheduleId: number };
	type ActionFailure = {
		action: 'saveSchedule' | 'createSchedule';
		scheduleId?: number;
		errors: Record<string, string[]>;
	};

	// This component reads its OWN enhance callback's `result`, never the page's shared `form`
	// prop -- see file header for why. Not invoked under the test stub (see file header) — a
	// documented, accepted gap this file shares with PurchaseEntryForm.dom.test.ts.
	const handleSubmit: SubmitFunction = ({ cancel }) => {
		if (saveDisabled) {
			cancel();
			return;
		}
		formError = '';
		serverFieldErrors = {};
		statusMessage = '';
		saving = true;

		return async ({ result, update }) => {
			saving = false;
			if (result.type === 'success') {
				const data = result.data as ActionSuccess | undefined;
				if (data?.ok) {
					statusMessage = mode === 'edit' ? 'Changes saved.' : 'Schedule created.';
					await update();
					onSaved?.();
					return;
				}
			}
			if (result.type === 'failure') {
				const data = result.data as ActionFailure | undefined;
				serverFieldErrors = data?.errors ?? {};
				formError =
					serverFieldErrors._form?.join(' ') ?? 'Some changes could not be saved — see the fields below.';
				await update({ reset: false });
				return;
			}
			// result.type === 'error' (thrown exception) or an unrecognized shape.
			formError = 'Something went wrong saving your changes. Please try again.';
			await update({ reset: false });
		};
	};
</script>

<form class="editor" method="POST" action={actionPath} use:enhance={handleSubmit}>
	<div class="editor-head">
		<!-- Not a heading: the enclosing jurisdiction <section> (TaxBracketSchedulesList.svelte)
		     already carries an <h2> naming this schedule type via aria-labelledby -- a second
		     heading repeating the identical text here would be a duplicate `role="heading"`
		     match for the same accessible name, not extra structure. -->
		<span class="schedule-type-tag">{SCHEDULE_TYPE_LABELS[scheduleType]}</span>
		<span class="tax-year">Tax year {taxYear}</span>
	</div>

	<!-- createSchedule's 23505 (a schedule for this year+type already exists) comes back keyed
	     `tax_year` (E35 team-lead note) -- there is no separate visible tax_year field to attach
	     it to (the year is fixed, not user-typed), so it renders here, beside the year it names. -->
	{#if serverFieldErrors.tax_year}
		<p class="banner" role="alert">{serverFieldErrors.tax_year.join(' ')}</p>
	{/if}

	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}
	{#if statusMessage}
		<p class="sr-only" role="status">{statusMessage}</p>
	{/if}

	<input type="hidden" name="tax_year" value={taxYear} />
	<input type="hidden" name="schedule_type" value={scheduleType} />
	{#if mode === 'edit'}
		<input type="hidden" name="schedule_id" value={scheduleId} />
	{/if}
	<input type="hidden" name="rows" value={rowsJson} />

	<TextAreaField
		label="Schedule label"
		name="schedule_label"
		id={`f-schedule-label-${instanceKey}`}
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
			name="standard_deduction"
			id={`f-std-deduction-${instanceKey}`}
			bind:value={standardDeduction}
			inputmode="decimal"
			numeric
			placeholder="0.00"
			hint={scheduleType === 'federal_lt_cg'
				? 'Federal long-term capital gains takes no separate standard deduction — 0 is a stated fact for this schedule, not a blank.'
				: undefined}
			errors={[
				...(serverFieldErrors.standard_deduction ?? []),
				...(standardDeductionError() ? [standardDeductionError() as string] : [])
			]}
		/>
		<TextField
			label="Prior-year tax balance"
			name="tax_balance_prior_year"
			id={`f-prior-balance-${instanceKey}`}
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
										<span class="fixed-floor-label" id={`fixed-floor-label-${instanceKey}`}
											>Bracket 1 floor</span
										>
										<input
											class="field-input num-input fixed-floor"
											type="text"
											inputmode="decimal"
											value="0"
											disabled
											aria-labelledby={`fixed-floor-label-${instanceKey}`}
										/>
									</div>
								{:else}
									<TextField
										label={`Bracket ${i + 1} floor`}
										name={`row-floor-${instanceKey}-${i}`}
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
									name={`row-rate-${instanceKey}-${i}`}
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
		{#if mode === 'edit' && scheduleId !== undefined && canDelete}
			<DeleteScheduleControl
				{scheduleId}
				itemLabel={`${SCHEDULE_TYPE_LABELS[scheduleType]} (tax year ${taxYear})`}
			/>
		{/if}
		<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>
			{submitButtonLabel}
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
	.schedule-type-tag {
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
		align-items: center;
		justify-content: flex-end;
		gap: var(--space-4);
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
