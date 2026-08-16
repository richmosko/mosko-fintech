<!--
	SymbolClassifyRow.svelte — one ever-transacted security in the SELF-235 (§2.2.1.b) full
	symbols list. Generalized from the SELF-200 pending-only PendingClassifyRow: a row now carries
	its CURRENT classification (or `null` = pending, the AC5 badge state) and stays in the list
	after a successful (re)classify — it updates in place rather than unmounting.

	Collapsed: the security label + its raw asset_type, a status chip (neutral "Pending" pill when
	unclassified, else "Cat › Sub-Cat"), and a Classify/Change button. Click-into (AC2) expands the
	detail: the linked-provider metadata HINT (symbol / name / asset_type + scalar metadata fields,
	labelled via labelForHintKey) shown as a NON-preselected hint (still AC3 for the metadata hint —
	unrelated to the classification pickers below it), plus a CASCADING Cat → Sub-Cat picker
	(catOptionsOf / subCatOptionsForCat — replaces SELF-200's single flat-grouped select so the two
	selects can filter independently). AC2: the current assignment IS pre-selected on open (both
	fields) when the row is already classified; a pending row opens with both fields empty (same
	AC3 posture the metadata hint already had — nothing is ever silently defaulted in). Submit
	POSTs to ?/classify — same UPSERT action classifies AND reassigns (idempotent).

	On success the enhance handler invalidates (→ the page load re-runs → this row's `symbol` prop
	is replaced with the fresh classification from the parent's keyed #each) then COLLAPSES the
	editor itself (the row stays mounted — AC4 propagation is "reflects immediately", not "the row
	disappears") and calls `onclassified()` so the PAGE can announce the new pending count. Client
	Zod mirror (classifySchema) gives fast feedback; the server action is the security boundary.

	Owns its OWN state (expanded / selected Cat+Sub-Cat / saving / errors) so one row's error can't
	bleed into another's. a11y: focus moves into the Cat select on expand and back to the
	Classify/Change button on Cancel or after a successful Save; the selects are disabled while
	saving. Tokens ONLY (var(--c-*)); no --c-attn-* here (not a staleness surface — the pending
	chip is a neutral pill, same treatment as the existing asset_type tag, per the design-system
	fence CountBadge.svelte documents: --c-attn-* is reserved for staleness/re-auth only).
-->
<script lang="ts">
	import { tick } from 'svelte';
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { classifySchema } from '$lib/schemas/classification';
	import { fieldErrors } from '$lib/schemas/account';
	import {
		type SymbolListItem,
		type SubCatOption,
		pendingLabel,
		displayName,
		hintEntries,
		classificationLabel,
		catOptionsOf,
		subCatOptionsForCat
	} from '$lib/asset-classify';

	let {
		symbol,
		subCats,
		disabled = false,
		onclassified
	}: {
		symbol: SymbolListItem;
		subCats: SubCatOption[];
		/** No-taxonomy guard (gap 2): when true the row can't be classified — the Classify/Change
		 *  button is disabled (the page shows the explanatory notice). */
		disabled?: boolean;
		/** Called after a successful (re)classify + load-invalidation, so the page can announce the
		 *  new pending count. The row itself stays mounted. */
		onclassified?: () => void;
	} = $props();

	let expanded = $state(false);
	// AC2: pre-selected to the CURRENT assignment when classified; both empty for a pending row
	// (AC3's "never auto-applied" posture — nothing is defaulted in from provider metadata).
	let selectedCat = $state('');
	let selectedSubCat = $state('');
	let saving = $state(false);
	let errors = $state<Record<string, string[]>>({});

	const label = $derived(pendingLabel(symbol));
	const name = $derived(displayName(symbol)); // first-class name, else promoted description
	const hints = $derived(hintEntries(symbol.metadata));
	const statusLabel = $derived(classificationLabel(symbol.classification));

	const catOptions = $derived(catOptionsOf(subCats));
	const subCatOptions = $derived(subCatOptionsForCat(subCats, selectedCat));

	// Cascade reset: when the Cat changes to one that doesn't own the current Sub-Cat selection,
	// clear it. Self-correcting rather than edge-guarded — on open() the pre-selected pair is set
	// together and is by construction still valid for its own Cat, so this does NOT clobber AC2's
	// pre-selection; it only fires once the user actually changes the Cat.
	$effect(() => {
		selectedCat;
		if (!expanded) return;
		const stillValid = subCatOptionsForCat(subCats, selectedCat).some(
			(o) => o.value === selectedSubCat
		);
		if (!stillValid) selectedSubCat = '';
	});

	// Unique per-row ids — the same `name="sub_cat_id"` can render on several expanded rows at once,
	// so ids must not collide (label association + focus target).
	const editorId = $derived(`classify-editor-${symbol.asset_id}`);
	const catSelectId = $derived(`classify-cat-${symbol.asset_id}`);
	const subCatSelectId = $derived(`classify-subcat-${symbol.asset_id}`);
	const classifyBtnId = $derived(`classify-btn-${symbol.asset_id}`);

	async function open() {
		const c = symbol.classification;
		selectedCat = c?.cat ?? ''; // AC2 pre-select
		selectedSubCat = c ? String(c.sub_cat_id) : ''; // AC2 pre-select
		errors = {};
		expanded = true;
		await tick();
		document.getElementById(catSelectId)?.focus();
	}
	async function close() {
		expanded = false;
		errors = {};
		await tick();
		document.getElementById(classifyBtnId)?.focus();
	}

	// use:enhance — client-validate against the Zod mirror, POST, then invalidate on success so the
	// load re-runs and this row's `symbol` prop carries the new classification; the editor closes
	// (row stays mounted, unlike the SELF-200 pending-only queue where it unmounted).
	const handler: SubmitFunction = ({ cancel }) => {
		const parsed = classifySchema.safeParse({ asset_id: symbol.asset_id, sub_cat_id: selectedSubCat });
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
				await update(); // invalidates → load reruns → symbol prop carries the new classification
				await close(); // collapse the editor, return focus to the Classify/Change button
				onclassified?.(); // page announces the new pending count
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
			<span class="status-chip" class:is-pending={!statusLabel}>{statusLabel ?? 'Pending'}</span>
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
				{statusLabel ? 'Change' : 'Classify'}
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

			<!-- Empty-taxonomy dead-end (gap 2) is guarded at the PAGE level: when there are no Sub-Cat
			     options at all, the page disables Classify/Change on every row (so this form never
			     opens) and shows an explanatory notice. This form therefore always has a non-empty
			     Cat picker. -->
			<form method="POST" action="?/classify" use:enhance={handler} class="classify-form" novalidate>
				<input type="hidden" name="asset_id" value={symbol.asset_id} />
				<!-- name="" is DELIBERATE: per the HTML forms spec, a control with an empty name
				     attribute is skipped when the form's data set is constructed, so this field never
				     reaches the network request. Cat is a CLIENT-ONLY filter for the Sub-Cat cascade
				     below — the server schema (Lock 14 mass-assignment fence, .strict()) accepts only
				     { asset_id, sub_cat_id }; a submitted `cat` key would 400 as an unrecognized field. -->
				<SelectField
					id={catSelectId}
					label="Category"
					name=""
					bind:value={selectedCat}
					required
					disabled={saving}
					hint="Choose the top-level category first."
					placeholder={{ value: '', label: 'Select a category…' }}
					options={catOptions}
				/>
				<SelectField
					id={subCatSelectId}
					label="Sub-category"
					name="sub_cat_id"
					bind:value={selectedSubCat}
					required
					disabled={saving || !selectedCat}
					errors={errors.sub_cat_id}
					hint={selectedCat
						? 'Choose the sub-category this security belongs to.'
						: 'Choose a category above first.'}
					placeholder={{ value: '', label: 'Select a sub-category…' }}
					options={subCatOptions}
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
	/* Same neutral pill treatment as .type-tag (design-system fence: --c-attn-* is reserved for
	   staleness/re-auth ONLY — classification-pending is a distinct, non-staleness concept, so it
	   gets the same quiet register the asset_type tag already uses, not a recolor of it). */
	.status-chip {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-pill);
		padding: var(--space-0) var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		background: var(--c-surface-alt);
	}
	.status-chip.is-pending {
		font-style: italic;
		color: var(--c-text-muted);
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
