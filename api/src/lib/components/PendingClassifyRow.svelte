<!--
	PendingClassifyRow.svelte — one held-but-unclassified security in the SELF-200 classify queue.

	Collapsed: the security label + its raw asset_type, and a "Classify" button. Click-into
	(AC-shaped: "a click-into/detail per symbol") expands the detail: the linked-provider metadata
	HINT (symbol / name / asset_type + scalar metadata fields, labelled via labelForHintKey) shown
	as a NON-preselected hint (AC3 — the hint is displayed, NEVER auto-applied), plus the
	Cat › Sub-Cat picker (SelectField grouped by cat into <optgroup>, mirroring the SELF-236
	reassign pattern). Submit POSTs to ?/classify.

	On success the enhance handler invalidates → the page load re-runs → this asset falls out of
	`data.pending` → this row unmounts (the item "drops from the list" off the derived data; no
	manual list mutation), then calls `onclassified()` so the PAGE can announce + move focus (the
	row itself is gone, so SR focus/announcement can't live here). Client Zod mirror (classifySchema)
	gives fast feedback; the server action is the security boundary.

	Owns its OWN state (expanded / selected / saving / errors) so one row's error can't bleed into
	another's. a11y: focus moves into the Category select on expand and back to the Classify button
	on Cancel; the select is disabled while saving. Tokens ONLY (var(--c-*)); no --c-attn-* here
	(not a staleness surface).
-->
<script lang="ts">
	import { tick } from 'svelte';
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { classifySchema } from '$lib/schemas/classification';
	import { fieldErrors } from '$lib/schemas/account';
	import type { SubCatGroup } from '$lib/transaction-util';
	import { type PendingSymbol, pendingLabel, displayName, hintEntries } from '$lib/asset-classify';

	let {
		symbol,
		subCatGroups,
		disabled = false,
		onclassified
	}: {
		symbol: PendingSymbol;
		subCatGroups: SubCatGroup[];
		/** No-taxonomy guard (gap 2): when true the row can't be classified — the Classify button
		 *  is disabled (the page shows the explanatory notice). */
		disabled?: boolean;
		/** Called after a successful classify + load-invalidation, so the page can announce the
		 *  new remaining count and move focus (this row is unmounting). */
		onclassified?: () => void;
	} = $props();

	let expanded = $state(false);
	// The picker selection. ALWAYS starts empty — never seeded from the metadata hint (AC3).
	let selected = $state('');
	let saving = $state(false);
	let errors = $state<Record<string, string[]>>({});

	const label = $derived(pendingLabel(symbol));
	const name = $derived(displayName(symbol)); // first-class name, else promoted description
	const hints = $derived(hintEntries(symbol.metadata));

	// Unique per-row ids — the same `name="sub_cat_id"` can render on several expanded rows at once,
	// so ids must not collide (label association + focus target).
	const editorId = $derived(`classify-editor-${symbol.asset_id}`);
	const selectId = $derived(`classify-subcat-${symbol.asset_id}`);
	const classifyBtnId = $derived(`classify-btn-${symbol.asset_id}`);

	async function open() {
		selected = ''; // AC3: reset to unselected on every open
		errors = {};
		expanded = true;
		await tick();
		document.getElementById(selectId)?.focus();
	}
	async function close() {
		expanded = false;
		errors = {};
		await tick();
		document.getElementById(classifyBtnId)?.focus();
	}

	// use:enhance — client-validate against the Zod mirror, POST, then invalidate on success so
	// the load re-runs and this row drops from data.pending.
	const handler: SubmitFunction = ({ cancel }) => {
		const parsed = classifySchema.safeParse({ asset_id: symbol.asset_id, sub_cat_id: selected });
		if (!parsed.success) {
			errors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		errors = {};
		saving = true;
		return async ({ result, update }) => {
			saving = false;
			if (result.type === 'success') {
				await update(); // invalidates → load reruns → this asset leaves the list → row unmounts
				onclassified?.(); // page announces "Classified — N remaining" + moves focus
			} else if (result.type === 'failure') {
				errors = (result.data?.errors as Record<string, string[]> | undefined) ?? {
					_form: ["Couldn't save — please try again."]
				};
			} else {
				await update();
			}
		};
	};
</script>

<li class="row">
	<div class="row-head">
		<div class="ident">
			<span class="label">{label}</span>
			<span class="type-tag">{symbol.asset_type}</span>
		</div>
		{#if !expanded}
			<Button
				variant="secondary"
				type="button"
				id={classifyBtnId}
				{disabled}
				onclick={open}
				aria-expanded={expanded}
				aria-controls={editorId}
			>
				Classify
			</Button>
		{/if}
	</div>

	{#if expanded}
		<div id={editorId} class="detail">
			<div class="hint" aria-label="Provider details">
				<p class="hint-caption">Provider details — a hint only, never applied automatically.</p>
				<dl class="hint-list">
					{#if symbol.symbol}
						<div class="hint-item">
							<dt>Ticker</dt>
							<dd>{symbol.symbol}</dd>
						</div>
					{/if}
					{#if name}
						<div class="hint-item">
							<dt>Name</dt>
							<dd>{name}</dd>
						</div>
					{/if}
					<div class="hint-item">
						<dt>Type</dt>
						<dd>{symbol.asset_type}</dd>
					</div>
					{#each hints as h (h.label)}
						<div class="hint-item">
							<dt>{h.label}</dt>
							<dd>{h.value}</dd>
						</div>
					{/each}
				</dl>
			</div>

			<!-- Empty-taxonomy dead-end (gap 2) is guarded at the PAGE level: when subCatGroups is
			     empty the page disables Classify on every row (so this form never opens) and shows an
			     explanatory notice. This form therefore always has a non-empty picker. -->
			<form method="POST" action="?/classify" use:enhance={handler} class="classify-form" novalidate>
				<input type="hidden" name="asset_id" value={symbol.asset_id} />
				<SelectField
					id={selectId}
					label="Category"
					name="sub_cat_id"
					bind:value={selected}
					required
					disabled={saving}
					errors={errors.sub_cat_id}
					hint="Grouped by category — choose the sub-category this security belongs to."
					placeholder={{ value: '', label: 'Select a category…' }}
					groups={subCatGroups}
				/>
				{#if errors._form}
					<p class="form-error" role="alert">{errors._form.join(' ')}</p>
				{/if}
				<div class="actions">
					<Button variant="link" type="button" onclick={close}>Cancel</Button>
					<Button variant="primary" type="submit" loading={saving}>Save</Button>
				</div>
			</form>
		</div>
	{/if}
</li>

<style>
	.row {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		border-bottom: 1px solid var(--c-border);
	}
	.row:last-child {
		border-bottom: none;
	}
	.row-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
	}
	.ident {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-width: 0;
		flex-wrap: wrap;
	}
	.label {
		font: var(--weight-semi) var(--fs-body) / var(--lh-tight) var(--font-num);
		color: var(--c-text-primary);
		overflow-wrap: anywhere;
	}
	.type-tag {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: var(--space-0) var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		background: var(--c-surface-alt);
	}
	.detail {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		max-width: 30rem;
	}
	.hint {
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-3);
	}
	.hint-caption {
		margin: 0 0 var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.hint-list {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: var(--space-1) var(--space-3);
		margin: 0;
	}
	.hint-item {
		display: contents;
	}
	.hint-item dt {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		font-weight: var(--weight-semi);
	}
	.hint-item dd {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		overflow-wrap: anywhere;
	}
	.classify-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
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
		align-items: center;
		gap: var(--space-3);
	}
</style>
