<!--
	SelectField.svelte — the `select` primitive (design-system-spec.md §4; seeded lists,
	no "+ new"). Label + native <select> + inline error, accessible: <label for>,
	aria-required/invalid/describedby, role="alert" error. Supports a flat `options`
	list AND grouped `groups` (rendered as <optgroup> — used for Sub-Cat grouped by cat).
	Native <select> is retained (keyboard + screen-reader semantics come for free);
	tokens ONLY (var(--c-*)), reproducing the locked screen.css `.select` focus/error.
-->
<script lang="ts">
	type Opt = { value: string; label: string };
	type Group = { label: string; options: Opt[] };

	let {
		label,
		name,
		value = $bindable(''),
		required = false,
		disabled = false,
		errors = [],
		hint = '',
		placeholder,
		options = [],
		groups = [],
		id
	}: {
		label: string;
		name: string;
		value?: string;
		required?: boolean;
		disabled?: boolean;
		errors?: string[];
		hint?: string;
		/** A leading option (e.g. "Select…" for required, or "Unsorted" for optional). */
		placeholder?: Opt;
		options?: Opt[];
		groups?: Group[];
		/** Explicit control id — REQUIRED when the same `name` renders more than once on a page
		 *  (e.g. a per-row classify select) so ids/label-associations stay unique. Defaults to
		 *  `f-${name}` for the common single-instance case. */
		id?: string;
	} = $props();

	const fieldId = $derived(id ?? `f-${name}`);
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
	<div class="select-wrap" class:is-error={hasError}>
		<select
			id={fieldId}
			{name}
			bind:value
			class="select-input"
			{disabled}
			aria-required={required}
			aria-invalid={hasError}
			aria-describedby={describedby}
		>
			{#if placeholder}
				<option value={placeholder.value}>{placeholder.label}</option>
			{/if}
			{#each options as opt (opt.value)}
				<option value={opt.value}>{opt.label}</option>
			{/each}
			{#each groups as group (group.label)}
				<optgroup label={group.label}>
					{#each group.options as opt (opt.value)}
						<option value={opt.value}>{opt.label}</option>
					{/each}
				</optgroup>
			{/each}
		</select>
	</div>
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
	.select-wrap {
		position: relative;
		display: flex;
	}
	.select-input {
		width: 100%;
		box-sizing: border-box;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		color: var(--c-text-primary);
		padding: var(--space-2) var(--space-3);
		font: var(--fs-body) / 1.2 var(--font-ui);
		cursor: pointer;
	}
	.select-input:hover {
		border-color: var(--c-text-muted);
	}
	.select-input:disabled {
		background: var(--c-disabled-bg);
		color: var(--c-disabled-text);
		border-color: var(--c-disabled-border);
		cursor: not-allowed;
	}
	.select-input:focus {
		border-color: var(--c-accent);
		box-shadow: 0 0 0 3px var(--c-accent-soft);
		outline: none;
	}
	.select-wrap.is-error .select-input {
		border-color: var(--c-neg);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--c-neg) 18%, transparent);
	}
	.field-error-msg {
		display: block;
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
</style>
