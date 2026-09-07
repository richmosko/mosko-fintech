<!--
	TextAreaField.svelte -- the multi-line sibling of `field-input` (design-system-spec.md §4
	component inventory extends here: TextField.svelte's shape reproduced over a <textarea>
	instead of an <input>, for a field whose content legitimately WRAPS rather than truncates).
	SELF-265's first consumer -- `schedule_label`, up to 500 characters (the seeded CA label runs
	473). No design-system primitive supported multi-line free text before this; flagged to Visual
	Designer as a candidate for formal inventory entry if a second consumer appears -- one is not
	yet a pattern, and this file's job today is to not invent a new visual register: same label +
	hint + error id-wiring, same focus/error token treatment, same font-ui text field convention
	TextField.svelte already uses, just wrapping.

	Tokens ONLY (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5). Same accessibility wiring as
	TextField: <label for>, aria-required, aria-invalid, aria-describedby -> hint + error ids,
	role="alert" on the error.

	`disabled` (SELF-355 addition): a plain passthrough to the native `<textarea disabled>` — no
	existing consumer passed this, so every prior call site is unaffected by the default `false`.
-->
<script lang="ts">
	let {
		label,
		name,
		id,
		value = $bindable(''),
		required = false,
		disabled = false,
		errors = [],
		hint = '',
		placeholder = '',
		maxlength,
		rows = 3
	}: {
		label: string;
		name: string;
		/** Overrides the derived `f-${name}` DOM id — see TextField.svelte's own note (SELF-265:
		 *  several TaxBracketScheduleEditor instances on one page share a server-required
		 *  `name` across different <form>s). */
		id?: string;
		value?: string;
		required?: boolean;
		disabled?: boolean;
		errors?: string[];
		hint?: string;
		placeholder?: string;
		maxlength?: number;
		rows?: number;
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
	<textarea
		id={fieldId}
		{name}
		{placeholder}
		{maxlength}
		{rows}
		{disabled}
		bind:value
		class="field-input"
		class:is-error={hasError}
		aria-required={required}
		aria-invalid={hasError}
		aria-describedby={describedby}
	></textarea>
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
		font: var(--fs-body) / var(--lh-body) var(--font-ui);
		resize: vertical;
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
