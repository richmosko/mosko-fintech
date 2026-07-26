<!--
	TransactionEntryForm.svelte — manual cash-transaction ENTRY (SELF-202 §2.4.3, ?/createTrans).
	Mirrors the accounts/new create pattern: client Zod .strict() mirror runs on submit for
	fast field-level feedback (cancel() the POST on client-invalid); the SERVER schema is the
	security boundary. On success use:enhance re-invalidates load() so the new row appears.

	The amount is entered as a positive magnitude + a Money in/out toggle; the signed amount
	is derived here (toSignedAmount) and written onto the FormData before the POST — the user
	never types a minus sign (F/CTO-ratified). account_id is the route param, not a field.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TransactionFactFields from '$lib/components/TransactionFactFields.svelte';
	import Button from '$lib/components/Button.svelte';
	import { manualTransCreateSchema, fieldErrors } from '$lib/schemas/transaction';
	import { toSignedAmount, type Direction, type SubCatGroup } from '$lib/transaction-util';

	let { subCatGroups }: { subCatGroups: SubCatGroup[] } = $props();

	let direction = $state<Direction>('out');
	let amount = $state('');
	let transaction_date = $state('');
	let vendor = $state('');
	let description = $state('');
	let sub_cat_id = $state('');
	let note = $state('');

	let errors = $state<Record<string, string[]>>({});
	let submitting = $state(false);

	function resetFields() {
		direction = 'out';
		amount = '';
		transaction_date = '';
		vendor = '';
		description = '';
		sub_cat_id = '';
		note = '';
	}

	const handler: SubmitFunction = ({ formData, cancel }) => {
		const signed = toSignedAmount(direction, amount);
		const parsed = manualTransCreateSchema.safeParse({
			transaction_date,
			amount: signed,
			vendor,
			description,
			sub_cat_id,
			note
		});
		if (!parsed.success) {
			errors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		errors = {};
		// POST exactly the .strict() keys: signed `amount`, drop the `direction` helper.
		formData.set('amount', signed);
		formData.delete('direction');
		submitting = true;
		return async ({ result, update }) => {
			submitting = false;
			if (result.type === 'success') {
				resetFields();
				await update({ reset: false }); // re-invalidate load(); we cleared state ourselves
			} else if (result.type === 'failure') {
				errors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not save the transaction. Please try again.'] };
			} else {
				await update();
			}
		};
	};
</script>

<form method="POST" action="?/createTrans" use:enhance={handler} class="entry-form" novalidate>
	{#if errors._form}
		<p class="form-error" role="alert">{errors._form.join(' ')}</p>
	{/if}

	<TransactionFactFields
		idPrefix="entry"
		{subCatGroups}
		{errors}
		bind:direction
		bind:amount
		bind:transaction_date
		bind:vendor
		bind:description
		bind:sub_cat_id
		bind:note
	/>

	<div class="actions">
		<Button variant="primary" type="submit" loading={submitting}>Add transaction</Button>
	</div>
</form>

<style>
	.entry-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		max-width: 30rem;
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
	.actions {
		display: flex;
		justify-content: flex-end;
	}
</style>
