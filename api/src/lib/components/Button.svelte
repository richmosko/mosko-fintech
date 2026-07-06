<!--
	Button.svelte — the `btn` primitive (design-system-spec.md §4 component inventory).
	Reproduces the locked screen.css `.btn` visual spec with tokens ONLY (var(--c-*)).
	Variants: primary / secondary (default) / link. States: default · hover · pressed ·
	loading (spinner) · disabled. Focus ring is applied globally (app.css button:focus-visible).
-->
<script lang="ts">
	import type { Snippet } from 'svelte';

	type Variant = 'primary' | 'secondary' | 'link';

	let {
		variant = 'secondary',
		type = 'button',
		loading = false,
		disabled = false,
		children,
		...rest
	}: {
		variant?: Variant;
		type?: 'button' | 'submit' | 'reset';
		loading?: boolean;
		disabled?: boolean;
		children: Snippet;
		[key: string]: unknown;
	} = $props();
</script>

<button
	{type}
	class="btn"
	class:primary={variant === 'primary'}
	class:link-style={variant === 'link'}
	class:is-loading={loading}
	disabled={disabled || loading}
	aria-busy={loading}
	{...rest}
>
	{@render children()}
</button>

<style>
	.btn {
		position: relative;
		display: inline-flex;
		align-items: center;
		gap: var(--space-1);
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		cursor: pointer;
	}
	.btn:hover {
		background: var(--c-surface-alt);
	}
	.btn:active {
		background: var(--c-surface-alt2);
	}
	.btn.primary {
		background: var(--c-accent);
		color: var(--c-accent-contrast);
		border-color: var(--c-accent);
		font-weight: var(--weight-semi);
	}
	.btn.primary:hover {
		background: var(--c-accent-hover);
		border-color: var(--c-accent-hover);
	}
	.btn.primary:active {
		background: var(--c-accent-active);
		border-color: var(--c-accent-active);
	}
	.btn.link-style {
		border-color: transparent;
		background: transparent;
		color: var(--c-link);
		padding-left: 0;
		padding-right: 0;
	}
	.btn:disabled {
		background: var(--c-disabled-bg);
		color: var(--c-disabled-text);
		border-color: var(--c-disabled-border);
		cursor: not-allowed;
	}
	.btn.is-loading {
		color: transparent;
		pointer-events: none;
	}
	.btn.is-loading::after {
		content: '';
		position: absolute;
		inset: 0;
		margin: auto;
		width: 13px;
		height: 13px;
		border: 2px solid currentColor;
		border-top-color: transparent;
		border-radius: 50%;
		color: var(--c-accent-contrast);
		animation: spin 0.7s linear infinite;
	}
	.btn:not(.primary).is-loading::after {
		color: var(--c-text-secondary);
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
