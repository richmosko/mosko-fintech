<!--
	SplitEditor.svelte — CREATE / REPLACE a balanced split set for a transaction
	(SELF-202, ?/splitTrans). ≥2 lines; each line is a SIGNED amount; Σ(children) MUST equal
	the parent amount. A live running sum shows how much is allocated vs the parent and blocks
	submit until it balances (the 029 deferred trigger is the authoritative backstop server-side).

	Split children carry the parent's sign, so line amounts are entered signed here (this is a
	power-user action, distinct from the entry form's positive-magnitude + toggle UX). The
	client splitSetSchema mirror runs on submit; per-line issues bucket under errors.lines.

	load() embeds category LABELS (not ids) on existing split children, so re-opening the
	editor on an already-split parent best-effort recovers each sub_cat_id by label
	(matchSubCatId); no match → Unsorted. `lines` is POSTed as a JSON array string.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { splitSetSchema, fieldErrors } from '$lib/schemas/transaction';
	import { sanitizeCurrencyAmount } from '$lib/validation/numeric';
	import { money, toUnits, matchSubCatId, type SubCatGroup, type TransactionView } from '$lib/transaction-util';

	let {
		transaction,
		subCatGroups,
		ondone
	}: {
		transaction: TransactionView;
		subCatGroups: SubCatGroup[];
		ondone: () => void;
	} = $props();

	type Line = { amount: string; sub_cat_id: string; note: string };

	function seed(): Line[] {
		if (transaction.split_count > 0) {
			return transaction.splits.map((s) => ({
				amount: String(s.amount),
				sub_cat_id: matchSubCatId(subCatGroups, s.cat, s.sub_cat),
				note: s.note ?? ''
			}));
		}
		return [
			{ amount: '', sub_cat_id: '', note: '' },
			{ amount: '', sub_cat_id: '', note: '' }
		];
	}

	let lines = $state<Line[]>(seed());
	let errors = $state<Record<string, string[]>>({});
	let submitting = $state(false);

	function addLine() {
		lines = [...lines, { amount: '', sub_cat_id: '', note: '' }];
	}
	function removeLine(i: number) {
		if (lines.length <= 2) return; // a split needs at least two lines
		lines = lines.filter((_, idx) => idx !== i);
	}

	// Live running sum in ten-thousandths (numeric(20,4) scale) for float-safe balancing.
	const parsedLines = $derived(lines.map((l) => sanitizeCurrencyAmount(l.amount)));
	const parentUnits = $derived(toUnits(transaction.amount));
	const allocatedUnits = $derived(
		parsedLines.reduce((acc, r) => acc + (r.ok ? toUnits(r.value) : 0), 0)
	);
	const remainingUnits = $derived(parentUnits - allocatedUnits);
	const allLinesValid = $derived(parsedLines.every((r) => r.ok && r.value !== 0));
	const balanced = $derived(remainingUnits === 0);
	const canSubmit = $derived(lines.length >= 2 && allLinesValid && balanced);

	const handler: SubmitFunction = ({ formData, cancel }) => {
		const payload = lines.map((l, i) => ({
			amount: l.amount,
			sub_cat_id: l.sub_cat_id === '' ? null : l.sub_cat_id,
			note: l.note === '' ? null : l.note,
			display_order: i
		}));
		const parsed = splitSetSchema.safeParse({ trans_id: transaction.trans_id, lines: payload });
		if (!parsed.success) {
			errors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		if (!balanced) {
			errors = { lines: [`Split lines must add up to ${money(transaction.amount)}.`] };
			cancel();
			return;
		}
		errors = {};
		// Server reads only trans_id + lines; drop the per-line helper inputs.
		for (const key of [...formData.keys()]) {
			if (key.startsWith('line-')) formData.delete(key);
		}
		formData.set('trans_id', String(transaction.trans_id));
		formData.set('lines', JSON.stringify(payload));
		submitting = true;
		return async ({ result, update }) => {
			submitting = false;
			if (result.type === 'success') {
				await update();
				ondone();
			} else if (result.type === 'failure') {
				errors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not save the split. Please try again.'] };
			} else {
				await update();
			}
		};
	};
</script>

<form method="POST" action="?/splitTrans" use:enhance={handler} class="split-editor" novalidate>
	<p class="lede">
		Split this {money(transaction.amount)} transaction into two or more categories. The parts
		must add up to the transaction total.
	</p>

	{#if errors._form}
		<p class="form-error" role="alert">{errors._form.join(' ')}</p>
	{/if}
	{#if errors.lines}
		<p class="form-error" role="alert">{errors.lines.join(' ')}</p>
	{/if}

	<ul class="lines">
		{#each lines as line, i (i)}
			<li class="line">
				<div class="line-fields">
					<TextField
						label="Amount"
						name={`line-amount-${i}`}
						bind:value={line.amount}
						numeric
						inputmode="decimal"
						hint={i === 0 ? 'Signed — negative for money out (e.g. -20.00).' : ''}
						placeholder="0.00"
						autocomplete="off"
					/>
					<SelectField
						label="Category"
						name={`line-cat-${i}`}
						bind:value={line.sub_cat_id}
						placeholder={{ value: '', label: 'Unsorted' }}
						groups={subCatGroups}
					/>
					<TextField
						label="Note"
						name={`line-note-${i}`}
						bind:value={line.note}
						hint={i === 0 ? 'Optional.' : ''}
						autocomplete="off"
					/>
				</div>
				<div class="line-remove">
					<Button
						variant="link"
						type="button"
						onclick={() => removeLine(i)}
						disabled={lines.length <= 2}
						aria-label={`Remove split line ${i + 1}`}
					>
						Remove
					</Button>
				</div>
			</li>
		{/each}
	</ul>

	<div class="line-add">
		<Button variant="secondary" type="button" onclick={addLine}>+ Add line</Button>
	</div>

	<div class="sum" aria-live="polite">
		<span class="sum-label">Allocated</span>
		<span class="sum-val">{money(allocatedUnits / 10000)} of {money(transaction.amount)}</span>
		<span class="sum-state">
			{#if balanced}
				Balanced
			{:else}
				{money(remainingUnits / 10000)} left
			{/if}
		</span>
	</div>

	<div class="actions">
		<Button variant="link" type="button" onclick={ondone}>Cancel</Button>
		<Button variant="primary" type="submit" loading={submitting} disabled={!canSubmit}>
			Save split
		</Button>
	</div>
</form>

<style>
	.split-editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.lede {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.form-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.lines {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.line {
		display: flex;
		align-items: flex-end;
		gap: var(--space-3);
		padding-bottom: var(--space-3);
		border-bottom: 1px solid var(--c-border);
	}
	.line-fields {
		display: grid;
		grid-template-columns: 8rem 1fr 1fr;
		gap: var(--space-3);
		flex: 1;
		min-width: 0;
	}
	@media (max-width: 560px) {
		.line-fields {
			grid-template-columns: 1fr;
		}
		.line {
			flex-direction: column;
			align-items: stretch;
		}
	}
	.sum {
		display: flex;
		align-items: baseline;
		gap: var(--space-2);
		flex-wrap: wrap;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
	}
	.sum-label {
		font-size: var(--fs-small);
		text-transform: uppercase;
		letter-spacing: 0.03em;
		color: var(--c-text-muted);
		font-weight: var(--weight-semi);
	}
	.sum-val {
		font-family: var(--font-num);
		color: var(--c-text-primary);
	}
	.sum-state {
		margin-left: auto;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		gap: var(--space-3);
	}
</style>
