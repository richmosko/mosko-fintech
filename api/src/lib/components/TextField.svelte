<!--
	TextField.svelte — the `field-input` primitive (design-system-spec.md §4).
	Label + text/number/date input + inline error, wired for accessibility:
	<label for>, aria-required, aria-invalid, aria-describedby → hint + error ids,
	role="alert" on the error so it's announced. Tokens ONLY (var(--c-*)); reproduces
	the locked screen.css `.field-input` states (focus/error). INV-1: free-text fields
	render as plain text — no rich-text affordance.
-->
<script lang="ts">
	import type { HTMLInputAttributes } from 'svelte/elements';

	let {
		label,
		name,
		value = $bindable(''),
		type = 'text',
		required = false,
		errors = [],
		hint = '',
		numeric = false,
		inputmode,
		placeholder = '',
		autocomplete
	}: {
		label: string;
		name: string;
		value?: string;
		type?: 'text' | 'date' | 'email' | 'password';
		required?: boolean;
		errors?: string[];
		hint?: string;
		numeric?: boolean;
		inputmode?: 'text' | 'decimal' | 'numeric';
		placeholder?: string;
		autocomplete?: HTMLInputAttributes['autocomplete'];
	} = $props();

	const fieldId = $derived(`f-${name}`);
	const errId = $derived(`${fieldId}-err`);
	const hintId = $derived(`${fieldId}-hint`);

	const hasError = $derived(errors.length > 0);
	const describedby = $derived(
		[hint ? hintId : null, hasError ? errId : null].filter(Boolean).join(' ') || undefined
	);
</script>

<div class="field">
	<label for={fieldId}>
		{label}{#if required}<span class="req" aria-hidden="true">*</span>{/if}
	</label>
	{#if hint}
		<span id={hintId} class="hint">{hint}</span>
	{/if}
	<input
		id={fieldId}
		{name}
		{type}
		{placeholder}
		{inputmode}
		{autocomplete}
		bind:value
		class="field-input"
		class:num-input={numeric}
		class:is-error={hasError}
		aria-required={required}
		aria-invalid={hasError}
		aria-describedby={describedby}
	/>
	{#if hasError}
		<span id={errId} class="field-error-msg" role="alert">{errors.join(' ')}</span>
	{/if}
</div>

<style>
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	label {
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.req {
		color: var(--c-neg);
		margin-left: 2px;
	}
	.hint {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.field-input {
		width: 100%;
		box-sizing: border-box;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		color: var(--c-text-primary);
		padding: var(--space-2) var(--space-3);
		font: var(--fs-body) / 1.2 var(--font-ui);
	}
	.field-input.num-input {
		font-family: var(--font-num);
		text-align: right;
	}
	.field-input:hover {
		border-color: var(--c-text-muted);
	}
	.field-input:focus {
		border-color: var(--c-accent);
		box-shadow: 0 0 0 3px var(--c-accent-soft);
		outline: none;
	}
	.field-input.is-error {
		border-color: var(--c-neg);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--c-neg) 18%, transparent);
	}
	.field-error-msg {
		display: block;
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
</style>
