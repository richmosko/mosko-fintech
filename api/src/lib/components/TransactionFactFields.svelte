<!--
	TransactionFactFields.svelte — the shared fact-input block for the manual cash ENTRY
	form and the EDIT (reverse-and-replace) form (SELF-202). One definition so the two
	fact surfaces can never drift on field shape / order / labels.

	AMOUNT SIGN UX (F/CTO-ratified): the amount is ALWAYS a positive magnitude; a
	Money in / Money out toggle sets direction. The parent form derives the SIGNED amount
	(toSignedAmount) in its use:enhance handler and POSTs the signed value — the user never
	types a minus sign. The `direction` radio is a helper input (name="direction"); the
	parent deletes it from the FormData and overwrites `amount` with the signed value before
	the POST, so the server sees exactly the .strict() schema keys.

	Tokens only (var(--c-*)); the toggle is standard radio-group semantics styled from
	tokens — NOT a new design-system primitive. INV-1: vendor/description/note are free-text
	→ plain text (TextField supplies no rich-text affordance).
-->
<script lang="ts">
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import type { Direction, SubCatGroup } from '$lib/transaction-util';

	let {
		direction = $bindable('out'),
		amount = $bindable(''),
		transaction_date = $bindable(''),
		vendor = $bindable(''),
		description = $bindable(''),
		sub_cat_id = $bindable(''),
		note = $bindable(''),
		subCatGroups,
		errors = {},
		idPrefix
	}: {
		direction?: Direction;
		amount?: string;
		transaction_date?: string;
		vendor?: string;
		description?: string;
		sub_cat_id?: string;
		note?: string;
		subCatGroups: SubCatGroup[];
		errors?: Record<string, string[]>;
		idPrefix: string;
	} = $props();
</script>

<fieldset class="direction">
	<legend>Direction</legend>
	<div id={`${idPrefix}-direction`} class="seg" role="radiogroup" aria-label="Money in or out">
		<label class="seg-opt" class:active={direction === 'out'}>
			<input type="radio" name="direction" value="out" bind:group={direction} />
			<span>Money out</span>
		</label>
		<label class="seg-opt" class:active={direction === 'in'}>
			<input type="radio" name="direction" value="in" bind:group={direction} />
			<span>Money in</span>
		</label>
	</div>
</fieldset>

<TextField
	label="Amount"
	name="amount"
	bind:value={amount}
	required
	numeric
	inputmode="decimal"
	errors={errors.amount}
	hint="Always a positive number — the toggle above sets money in or out."
	placeholder="0.00"
	autocomplete="off"
/>

<TextField
	label="Date"
	name="transaction_date"
	type="date"
	bind:value={transaction_date}
	required
	errors={errors.transaction_date}
/>

<TextField
	label="Vendor"
	name="vendor"
	bind:value={vendor}
	errors={errors.vendor}
	hint="Optional — who the transaction was with."
	autocomplete="off"
/>

<TextField
	label="Description"
	name="description"
	bind:value={description}
	errors={errors.description}
	hint="Optional."
	autocomplete="off"
/>

<SelectField
	label="Category"
	name="sub_cat_id"
	bind:value={sub_cat_id}
	errors={errors.sub_cat_id}
	hint="Optional — leave as Unsorted to categorise later."
	placeholder={{ value: '', label: 'Unsorted' }}
	groups={subCatGroups}
/>

<TextField
	label="Note"
	name="note"
	bind:value={note}
	errors={errors.note}
	hint="Optional."
	autocomplete="off"
/>

<style>
	.direction {
		border: 0;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.direction legend {
		padding: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.seg {
		display: inline-flex;
		gap: 0;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		overflow: hidden;
		width: fit-content;
	}
	.seg-opt {
		display: inline-flex;
		align-items: center;
		padding: var(--space-2) var(--space-3);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
		color: var(--c-text-secondary);
		cursor: pointer;
	}
	.seg-opt + .seg-opt {
		border-left: 1px solid var(--c-border-strong);
	}
	.seg-opt.active {
		background: var(--c-accent-soft);
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	/* Visually-hidden native radio — the label chrome is the affordance; keyboard + a11y
	   semantics stay on the real input. Focus ring shows on the label when focused-within. */
	.seg-opt input {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0 0 0 0);
		white-space: nowrap;
		border: 0;
	}
	.seg-opt:focus-within {
		box-shadow: inset 0 0 0 2px var(--c-accent);
	}
</style>
