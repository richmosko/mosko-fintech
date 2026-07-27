<!--
	StockSplitEntryForm.svelte — manual stock-split ENTRY (SELF-203 / ADR-033, ?/createStockSplit).
	Mirrors TransactionEntryForm.svelte: client Zod .strict() mirror (stockSplitCreateSchema) runs
	on submit for fast field-level feedback (cancel() the POST on client-invalid); the SERVER schema
	+ the fn_create_stock_split RPC guards are the security boundary. On success use:enhance
	re-invalidates load() so the derived holdings reflect the split.

	A stock split is a book-neutral corp_action: the user picks the held security, the split ratio
	(new : old — e.g. 2 : 1 forward, 1 : 2 reverse) and the ex-date; the RPC derives the quantity
	delta from the held position (there is NO amount field — the split moves no money). account_id
	is the route param, not a field. The four posted fields (security_id, ratio_num, ratio_den,
	ex_date) carry their own `name`s so they POST natively — no FormData rewrite needed.

	SOURCE-OF-TRUTH gate (OWD-2 / ADR-033) is enforced by the PARENT (+page.svelte only renders this
	for non-provider-linked accounts, linked_source_id IS NULL); the RPC is the DB backstop.

	Tokens only (var(--c-*)). The ratio pair is a standard fieldset + two numeric TextFields, NOT a
	new design-system primitive. No --c-pos/--c-neg (ratios are neutral, not ACTUAL performance).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { stockSplitCreateSchema, fieldErrors } from '$lib/schemas/transaction';
	import { securityLabel, type SecurityOption } from '$lib/transaction-util';

	let { securities }: { securities: SecurityOption[] } = $props();

	let security_id = $state('');
	let ratio_num = $state('');
	let ratio_den = $state('');
	let ex_date = $state('');

	let errors = $state<Record<string, string[]>>({});
	let submitting = $state(false);

	// Held-security picker options (value = asset_id as string; label composed browser-side).
	const options = $derived(
		securities.map((s) => ({ value: String(s.security_id), label: securityLabel(s) }))
	);

	function resetFields() {
		security_id = '';
		ratio_num = '';
		ratio_den = '';
		ex_date = '';
	}

	const handler: SubmitFunction = ({ cancel }) => {
		const parsed = stockSplitCreateSchema.safeParse({ security_id, ratio_num, ratio_den, ex_date });
		if (!parsed.success) {
			errors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		errors = {};
		submitting = true;
		return async ({ result, update }) => {
			submitting = false;
			if (result.type === 'success') {
				resetFields();
				await update({ reset: false }); // re-invalidate load(); we cleared state ourselves
			} else if (result.type === 'failure') {
				errors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not record the split. Please try again.'] };
			} else {
				await update();
			}
		};
	};
</script>

<form method="POST" action="?/createStockSplit" use:enhance={handler} class="entry-form" novalidate>
	{#if errors._form}
		<p class="form-error" role="alert">{errors._form.join(' ')}</p>
	{/if}

	<SelectField
		label="Security"
		name="security_id"
		bind:value={security_id}
		required
		errors={errors.security_id}
		hint="The holding being split."
		placeholder={{ value: '', label: 'Select a security…' }}
		options={options}
	/>

	<fieldset class="ratio">
		<legend>Split ratio</legend>
		<div class="ratio-row">
			<TextField
				label="New shares"
				name="ratio_num"
				bind:value={ratio_num}
				required
				numeric
				inputmode="decimal"
				errors={errors.ratio_num}
				placeholder="2"
				autocomplete="off"
			/>
			<span class="ratio-sep" aria-hidden="true">:</span>
			<TextField
				label="For every"
				name="ratio_den"
				bind:value={ratio_den}
				required
				numeric
				inputmode="decimal"
				errors={errors.ratio_den}
				placeholder="1"
				autocomplete="off"
			/>
		</div>
		<span class="ratio-hint">
			New shares held for every old share — e.g. 2 : 1 for a 2-for-1 forward split, 1 : 2 for a
			reverse split.
		</span>
	</fieldset>

	<TextField
		label="Ex-date"
		name="ex_date"
		type="date"
		bind:value={ex_date}
		required
		errors={errors.ex_date}
		hint="The date the split takes effect."
	/>

	<div class="actions">
		<Button variant="primary" type="submit" loading={submitting}>Record split</Button>
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
	.ratio {
		border: 0;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.ratio legend {
		padding: 0;
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	/* Two numeric fields with a ":" between; align the colon to the input row (labels sit above). */
	.ratio-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-2);
	}
	.ratio-row :global(.field) {
		flex: 1 1 0;
	}
	.ratio-sep {
		padding-bottom: var(--space-2);
		font-size: var(--fs-body);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.ratio-hint {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
	}
</style>
