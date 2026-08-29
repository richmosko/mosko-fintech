<!--
	SelectField.svelte — the `select` primitive (design-system-spec.md §4; seeded lists,
	no "+ new"). Label + native <select> + inline error, accessible: <label for>,
	aria-required/invalid/describedby, role="alert" error. Supports a flat `options`
	list AND grouped `groups` (rendered as <optgroup> — used for Sub-Cat grouped by cat).
	Native <select> is retained (keyboard + screen-reader semantics come for free);
	tokens ONLY (var(--c-*)), reproducing the locked screen.css `.select` focus/error.

	⚠ `required` SETS `aria-required` AND IS DELIBERATELY NOT FORWARDED TO THE NATIVE <select>.
	  This looks like an omission and is load-bearing. Forwarding it would make the BROWSER block
	  submit first, with an untokened native validation bubble — which pre-empts the page's
	  client-side Zod mirror, so the error would never reach the `.field-error-msg` slot below,
	  never be styled by the design system, and never be announced through the `role="alert"`
	  wiring this component exists to provide.

	  A live consumer depends on exactly this: the account close control
	  (`accounts/[account_id]`) renders an EMPTY placeholder option so the closure reason cannot
	  be defaulted — the reason lands in `pfin.account_event`, which is immutable audit-class, so
	  a reason nobody chose is permanent. That empty value is caught by the page's Zod mirror and
	  rendered inline HERE. "Fixing" this by forwarding `required` silently degrades that path to
	  a browser bubble, and NOTHING IN THE ACCOUNT PAGE FAILS — no test breaks, no type changes,
	  the control still refuses an empty submit. The regression is entirely in which layer
	  reports it and how it looks.

	  If a native-`required` variant is ever genuinely needed, add it as a separate opt-in prop
	  rather than changing this one. (Dependency found by UX Designer during the ADR-042 review;
	  recorded here rather than in the consuming page, because the page cannot see it.)
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
		id,
		labelHidden = false,
		muted = false,
		onchange
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
		/** SELF-249 — visually hides the `<label>` while keeping a real `<label for>` in the DOM
		 *  (never `aria-label`), so the control stays fully labelled for assistive tech. For a
		 *  compact repeated control (one per table row) where the column header already names the
		 *  field and a visible per-row label would be redundant noise. Off by default — every
		 *  existing call site is unaffected. First consumer: SubCatPicker.svelte. */
		labelHidden?: boolean;
		/** SELF-249 — an unconfirmed-value cue (e.g. a vendor-history suggestion pre-filled but
		 *  not yet saved): dashed border + muted text, reusing the SAME visual vocabulary the
		 *  account-detail "Closed" status pill already uses for "a real state, toned down" rather
		 *  than inventing a new token. Off by default. */
		muted?: boolean;
		/** Optional native `change` passthrough — SELF-254's account picker re-navigates on
		 *  selection rather than on form submit. Undefined ⇒ no listener attached, so every
		 *  existing form-field call site is unaffected. */
		onchange?: (event: Event) => void;
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
	<label for={fieldId} class:sr-only={labelHidden}>
		{label}{#if required}<span class="req" aria-hidden="true">*</span>{/if}
	</label>
	{#if hint}
		<span id={hintId} class="hint">{hint}</span>
	{/if}
	<div class="select-wrap" class:is-error={hasError} class:is-muted={muted}>
		<select
			id={fieldId}
			{name}
			bind:value
			class="select-input"
			{disabled}
			{onchange}
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
	/* SELF-249 `labelHidden` — same clip-to-1px idiom already used elsewhere in this codebase
	   (accounts/[account_id] entry-mode toggle's hidden radio inputs) for "in the accessibility
	   tree, out of the visual layout" — never `display:none`/`aria-label`, which would drop or
	   bypass the real <label for> association. */
	.sr-only {
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
	/* SELF-249 `muted` — dashed border + muted text, the SAME pairing accounts/[account_id]'s
	   `.status.closed` pill uses for "a real state, toned down" (that file's own comment: tone is
	   carried by weight + border style, deliberately not a color reserved for error/negative). */
	.select-wrap.is-muted .select-input:not(:disabled) {
		border-style: dashed;
		color: var(--c-text-muted);
	}
	.field-error-msg {
		display: block;
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
</style>
