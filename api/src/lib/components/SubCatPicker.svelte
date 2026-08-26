<!--
	SubCatPicker.svelte — SELF-249 §2.3.1.b per-row Sub-Cat picker (AC1/AC2/AC3/AC4/AC6). One
	instance per classifiable transaction row, rendered by TransactionRow in place of the old
	read-only category label. NOT rendered at all for a split-parent row (AC7 — see TransactionRow,
	which keeps its own split-tag branch and never mounts this component there) or when the account
	is frozen (TransactionRow's existing `frozen` convention — a closed account's row goes fully
	read-only, same as every other per-row control on that page).

	THREE RENDER STATES (AC2), independent of the DISABLED gate below:
	  · solid    — `transaction.sub_cat_id` is non-null (a real Sub-Cat has been chosen). Value =
	                that id directly. ⚠ Sec FLAG-D: keyed on `sub_cat_id`, NOT on `category` —
	                `subCatLabel` (taxonomy.ts) never returns null, so a note-only annotation (an
	                annotation row exists, but sub_cat_id itself is null) still produces a non-null
	                `category`. Keying on `category` misread that case as "classified" and
	                suppressed the hint/suggestion this row should still show — see
	                TransactionView's `sub_cat_id` note (transaction-util.ts).
	  · suggested — no override, but `fn_suggest_subcat_for_vendor()` (092) returned a match. The
	                select PRE-FILLS to that suggestion (SelectField `muted` = dashed border +
	                muted text) — a real, selectable value, just not yet confirmed. A "Confirm"
	                submit button is enabled from the start so agreeing with the suggestion doesn't
	                require touching the control first (a native <select>'s `change` event never
	                fires on a value the user didn't alter).
	  · hint      — no override, no suggestion. Value stays '' (Unsorted) — 017's provider_category
	                hint renders through SelectField's own `hint` slot (already an accessible,
	                aria-describedby-wired, muted-styled slot — reused, not duplicated). ⚠ 017's
	                constraint, verbatim: "IMMUTABLE display hint only (R-18). All txns land
	                Unsorted; NO auto-map / NO provider_category→sub_cat routing in V1." Applied
	                here: the hint text is NEVER the select's value and NEVER auto-submitted. The
	                only way this state produces a write is the user actively picking a Sub-Cat and
	                pressing Save.

	DISABLED GATE (AC6): `transaction.classifiable === false` disables the select AND replaces the
	submit control with affordance text (`classifyRefusalCopy`) routing the correction to Edit
	above (§2.4.3) — never a promise that a classified transfer "cancels out" (PM copy constraint;
	none of the copy table's strings make that claim — see transaction-util.ts).

	⚠ EXPECTED CONTRACT: `classifiable` / `classifiableReason` / `provider_category` /
	`suggested_sub_cat_id` / `sub_cat_id` are Backend load()-extension fields that may not be wired
	in every tree yet (SELF-249 runs frontend/backend concurrently — see TransactionView's own
	note, transaction-util.ts). Absent reads as `classifiable: true` with no hint/suggestion, and
	`sub_cat_id` absent reads as unclassified (falls through to suggested/hint, never a false
	solid) — this component never treats "missing" as "refused" or as "confirmed."

	SUBMIT is a `fetch`+JSON relay (classifyFlow.ts), NOT a form action — the classify endpoint
	(SELF-248) is a `+server.ts` JSON API route, not a form action (api/CLAUDE.md forms rule: fetch
	is correct precisely because that's the real transport already shipped). On success this
	re-validates the loader (`invalidateAll`, injectable — mirrors SyncNowControl's `onPoll`) so
	`category` / `classifiable` / the suggestion all refresh from the server's own re-derivation,
	rather than this component guessing the post-write shape locally.
-->
<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import {
		classifyRefusalCopy,
		type SubCatGroup,
		type TransactionView
	} from '$lib/transaction-util';
	import { classifyTrans as defaultClassifyFn, ClassifyError, type FetchLike } from '$lib/transactions/classifyFlow';

	let {
		transaction,
		subCatGroups,
		disabled = false,
		classifyFn = defaultClassifyFn,
		onSuccess = invalidateAll,
		fetchFn
	}: {
		transaction: TransactionView;
		subCatGroups: SubCatGroup[];
		/** Parent-level override (e.g. a frozen/closed account) — combines with `!classifiable`;
		 *  either one disables the control. */
		disabled?: boolean;
		/** Injectable relay seam (default is the real classifyFlow) — unit-test without network. */
		classifyFn?: typeof defaultClassifyFn;
		/** Re-validate the page's data after a successful classify. Default invalidates every
		 *  loader (mirrors SyncNowControl's `onPoll`); injectable for narrower invalidation/tests. */
		onSuccess?: () => void | Promise<void>;
		/** Forwarded to classifyFn when provided — lets a test drive classifyFn's own default
		 *  fetch injection without also injecting classifyFn itself. */
		fetchFn?: FetchLike;
	} = $props();

	// Sec FLAG-D: keyed on the raw id, not the label pair — see the header note above.
	const classified = $derived(transaction.sub_cat_id != null);
	const suggestion = $derived(transaction.suggested_sub_cat_id ?? null);
	const providerCategory = $derived(transaction.provider_category ?? null);
	// EXPECTED CONTRACT default: undefined (unwired loader) reads as classifiable — see header note.
	const classifiable = $derived(transaction.classifiable ?? true);

	// Sec FLAG-B (option C): a classifiable row's security_id is NULL by definition
	// (classifiabilityOf's own M2 leg, transactions.ts), so 'Trade' can never be a legal pick from
	// THIS picker — filtered here, at the point of use, rather than in loadCashflowSubCats
	// (shared with entry/edit/split, where narrowing would reach flows this issue doesn't own).
	// Backend's raise-time classifier is the real defense; this is the UI-side narrowing of what's
	// offered so the invalid choice isn't reachable in the first place.
	const pickerGroups = $derived(subCatGroups.filter((g) => g.label !== 'Trade'));

	function seedValue(): string {
		if (classified) return String(transaction.sub_cat_id);
		if (suggestion != null) return String(suggestion);
		return '';
	}

	type Style = 'solid' | 'suggested' | 'hint';
	const style = $derived<Style>(classified ? 'solid' : suggestion != null ? 'suggested' : 'hint');

	const pickerHint = $derived(
		style === 'suggested'
			? 'Suggested from your vendor history — not saved until confirmed.'
			: style === 'hint' && providerCategory
				? `Provider category: ${providerCategory}`
				: ''
	);

	let value = $state(seedValue());
	let saving = $state(false);
	let error = $state('');

	// Re-seed the local value whenever the underlying row data changes (e.g. a sibling save
	// invalidated the loader, or this row's own submit just succeeded) — but never while a submit
	// is in flight, so a landed re-render can't clobber a click the user is still mid-way through.
	$effect(() => {
		void transaction.sub_cat_id;
		void suggestion;
		if (!saving) value = seedValue();
	});

	const isDirty = $derived(value !== '');
	const submitDisabled = $derived(!classifiable || disabled || saving || !isDirty);

	async function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		if (submitDisabled) return;
		const subCatId = Number(value);
		if (!Number.isInteger(subCatId) || subCatId <= 0) return;
		error = '';
		saving = true;
		try {
			await classifyFn(transaction.trans_id, subCatId, fetchFn);
			await onSuccess();
		} catch (e) {
			error = classifyRefusalCopy(e instanceof ClassifyError ? e.code : null);
		} finally {
			saving = false;
		}
	}
</script>

<form class="picker" onsubmit={handleSubmit}>
	<SelectField
		label={`Sub-Cat — ${transaction.vendor ?? transaction.description ?? 'transaction'}`}
		labelHidden
		name="sub_cat_id"
		id={`subcat-${transaction.trans_id}`}
		bind:value
		disabled={!classifiable || disabled || saving}
		muted={style !== 'solid'}
		hint={pickerHint}
		placeholder={{ value: '', label: 'Unsorted' }}
		groups={pickerGroups}
		errors={error ? [error] : []}
	/>
	{#if !classifiable}
		<p class="disabled-note">{classifyRefusalCopy(transaction.classifiableReason)}</p>
	{:else}
		<Button type="submit" variant="link" loading={saving} disabled={submitDisabled}>
			{style === 'suggested' ? 'Confirm' : classified ? 'Update' : 'Save'}
		</Button>
	{/if}
</form>

<style>
	.picker {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: var(--space-1);
		min-width: 12rem;
	}
	.disabled-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		max-width: 20rem;
	}
</style>
