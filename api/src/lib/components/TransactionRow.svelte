<!--
	TransactionRow.svelte — one transaction in the account-detail ledger table + its inline
	editors (SELF-202). Renders as a fragment of <tr> siblings (placed inside <tbody>): the
	parent row, its split children (when split_count>0), and — one at a time — an inline
	editor row for Edit / Recategorize / Split.

	Actions (all POST to accounts/[account_id]; use:enhance re-invalidates load on success):
	  • Edit        → ?/editTransFact  — reverse-and-replace the fact (corrected fields).
	  • Recategorize→ ?/recategorize   — category/note only (023 annotation; no ledger touch).
	  • Split       → ?/splitTrans     — a balanced child set (SplitEditor).
	  • Unsplit     → ?/unsplitTrans   — drop the child set (shown when split_count>0).

	Each editor keeps SCOPED error state (result.data.errors), never the shared page `form`
	prop, so one row's failure can't bleed into another (mirrors the reassignSubCat pattern).
	Values are neutral (ledger amounts) — NEVER --c-pos/--c-neg (design §5 fence 1). INV-1:
	vendor/description/note render as plain text. Per-row action gating (e.g. hiding actions
	on is_reverse audit rows) is a UX Designer flow decision — kept uniform here.

	SELF-249: the Category cell now hosts SubCatPicker, a per-row quick-classify control
	(fetch+JSON to the SELF-248 classify endpoint — NOT this file's form-action editors, which
	stay for the combined category+note "Categorize" flow). Three cases share this cell:
	  · split parent (split_count>0)  → no picker at all (AC7); children carry the real
	    Sub-Cats, read-only, below.
	  · frozen                        → plain label, same as every other control on this row.
	  · otherwise                     → <SubCatPicker>, which renders itself DISABLED with
	    affordance copy when `transaction.classifiable` is false (AC6) — including reversal
	    rows: is_reverse is one of classifiable()'s five enumerated legs, so it gets the SAME
	    uniform disabled-render treatment as the other four rather than a special-cased hide.
	    (Team-lead's dispatch leaned toward hiding the picker on a reversal row; this ships the
	    AC's own general rule instead — see the PR report for the full reasoning.)

	SELF-340 (F/CTO ruled, A+C-deferred): Edit is UI-mirror-gated OFF a security-linked row
	(`transaction.security_id != null`) — reverseAndReplaceTrans's corrected-row insert hardcodes
	`security_id: null` on the replacement, and there is no security-aware §2.4.3 edit form in V1,
	so editing a trade/security row via this cash-only form would silently drop the security link.
	⚠ THIS IS DEFENSE-IN-DEPTH, NOT THE BOUNDARY: Backend's server-side refusal is what actually
	stops the write; this only stops OFFERING a control that would just be refused (an absent
	button reads as a rule; a rendered-then-refused one reads as a bug — same "not a fence" framing
	as `frozen`/`058` elsewhere on this page). Categorize STAYS visible on a security row — the row
	isn't fully inert, since the 023 annotation overlay legitimately allows Trade-cat-consistent
	corrections (that path is unaffected by this issue). `security_id` undefined (an unwired loader
	— see TransactionView's own EXPECTED-CONTRACT note) is treated as "possibly security-linked" and
	ALSO hides Edit — the opposite default direction from every other EXPECTED-CONTRACT field on
	this row, because unlike those, nothing else currently refuses a security-row edit on every tip
	(see transaction-util.ts's note for why fail-open would be a live corruption window here).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import TransactionFactFields from '$lib/components/TransactionFactFields.svelte';
	import SplitEditor from '$lib/components/SplitEditor.svelte';
	import SubCatPicker from '$lib/components/SubCatPicker.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { manualTransEditSchema, recategorizeSchema, fieldErrors } from '$lib/schemas/transaction';
	import {
		money,
		toSignedAmount,
		fromSignedAmount,
		matchSubCatId,
		type Direction,
		type SubCatGroup,
		type TransactionView
	} from '$lib/transaction-util';

	let {
		transaction,
		subCatGroups,
		columns,
		frozen = false
	}: {
		transaction: TransactionView;
		subCatGroups: SubCatGroup[];
		columns: number;
		/**
		 * The owning account is CLOSED (ADR-042 Decision 3), so every write into it is rejected by
		 * `058`'s fence. Suppresses this row's edit / re-categorize / split controls and any open
		 * inline editor — the row's DATA stays fully visible (SELF-201 AC #4: a closed account
		 * keeps its history; only the write paths change).
		 *
		 * Defaults to `false` so every existing call site keeps today's behaviour untouched.
		 *
		 * ⚠ Not a fence — a UI affordance. The write is still reachable from a stale tab or a
		 * provider sync; `058` is the enforcement. This stops the user being offered a control
		 * whose only outcome is a refusal.
		 */
		frozen?: boolean;
	} = $props();

	type Mode = null | 'edit' | 'recat' | 'split';
	let mode = $state<Mode>(null);

	// The mode the row actually RENDERS. `frozen` can flip while an editor is open — the close
	// lands in another tab, the load reruns, and an edit form for a now-frozen account would be
	// left on screen posting into `058`'s fence. Derived ONCE rather than guarding each editor
	// block, so a fourth editor added later inherits the guard instead of needing to remember it.
	const activeMode = $derived(frozen ? null : mode);

	// SELF-340 — fail-closed: `undefined` (unwired loader) reads as "possibly security-linked",
	// same as an explicit non-null id. See this field's own note (transaction-util.ts) and the
	// header comment above for why this direction is deliberate, unlike every other
	// EXPECTED-CONTRACT field on this row.
	const isSecurityLinked = $derived(transaction.security_id !== null);

	const catLabel = $derived(
		transaction.category
			? transaction.category.cat
				? `${transaction.category.cat} › ${transaction.category.sub_cat}`
				: transaction.category.sub_cat
			: 'Unsorted'
	);

	function childLabel(c: { cat: string | null; sub_cat: string }): string {
		return c.cat ? `${c.cat} › ${c.sub_cat}` : c.sub_cat;
	}

	// ── Edit (reverse-and-replace) ────────────────────────────────────────────
	let editDirection = $state<Direction>('out');
	let editAmount = $state('');
	let editDate = $state('');
	let editVendor = $state('');
	let editDescription = $state('');
	let editSubCat = $state('');
	let editNote = $state('');
	let editErrors = $state<Record<string, string[]>>({});
	let editSaving = $state(false);

	function openEdit() {
		const { direction, magnitude } = fromSignedAmount(transaction.amount);
		editDirection = direction;
		editAmount = magnitude;
		editDate = transaction.transaction_date;
		editVendor = transaction.vendor ?? '';
		editDescription = transaction.description ?? '';
		editSubCat = matchSubCatId(subCatGroups, transaction.category?.cat ?? null, transaction.category?.sub_cat ?? '');
		editNote = transaction.note ?? '';
		editErrors = {};
		mode = 'edit';
	}

	const editHandler: SubmitFunction = ({ formData, cancel }) => {
		const signed = toSignedAmount(editDirection, editAmount);
		const parsed = manualTransEditSchema.safeParse({
			orig_trans_id: transaction.trans_id,
			transaction_date: editDate,
			amount: signed,
			vendor: editVendor,
			description: editDescription,
			sub_cat_id: editSubCat,
			note: editNote
		});
		if (!parsed.success) {
			editErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		editErrors = {};
		formData.set('amount', signed);
		formData.delete('direction');
		editSaving = true;
		return async ({ result, update }) => {
			editSaving = false;
			if (result.type === 'success') {
				await update();
				mode = null;
			} else if (result.type === 'failure') {
				editErrors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not save the changes. Please try again.'] };
			} else {
				await update();
			}
		};
	};

	// ── Recategorize (category / note only) ───────────────────────────────────
	let recatSubCat = $state('');
	let recatNote = $state('');
	let recatErrors = $state<Record<string, string[]>>({});
	let recatSaving = $state(false);

	function openRecat() {
		recatSubCat = matchSubCatId(subCatGroups, transaction.category?.cat ?? null, transaction.category?.sub_cat ?? '');
		recatNote = transaction.note ?? '';
		recatErrors = {};
		mode = 'recat';
	}

	const recatHandler: SubmitFunction = ({ cancel }) => {
		const parsed = recategorizeSchema.safeParse({
			trans_id: transaction.trans_id,
			sub_cat_id: recatSubCat,
			note: recatNote
		});
		if (!parsed.success) {
			recatErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		recatErrors = {};
		recatSaving = true;
		return async ({ result, update }) => {
			recatSaving = false;
			if (result.type === 'success') {
				await update();
				mode = null;
			} else if (result.type === 'failure') {
				recatErrors =
					(result.data?.errors as Record<string, string[]> | undefined) ??
					{ _form: ['Could not update the category. Please try again.'] };
			} else {
				await update();
			}
		};
	};

	// ── Unsplit ───────────────────────────────────────────────────────────────
	let unsplitting = $state(false);
	const unsplitHandler: SubmitFunction = () => {
		unsplitting = true;
		return async ({ update }) => {
			await update();
			unsplitting = false;
		};
	};

	function cancelEditor() {
		mode = null;
	}
</script>

<tr class="trans" class:is-reverse={transaction.is_reverse}>
	<td class="num-cell">{transaction.transaction_date}</td>
	<td class="subcat-cell">
		{#if transaction.split_count > 0}
			<!-- AC7: a split parent's row offers NO parent-level picker — its children carry the
			     real Sub-Cats (rendered read-only below) and any correction routes through Split. -->
			<span class="split-tag">Split · {transaction.split_count}</span>
		{:else if frozen}
			<!-- Frozen mirrors every other per-row control on this page (row-actions below) —
			     hidden, not disabled-with-affordance; `058` refuses the write regardless. -->
			<span class="cat">{catLabel}</span>
		{:else}
			<SubCatPicker {transaction} {subCatGroups} />
		{/if}
	</td>
	<td>{transaction.vendor ?? '—'}</td>
	<td>
		{transaction.description ?? '—'}
		{#if transaction.note}<span class="note">{transaction.note}</span>{/if}
	</td>
	<td class="num num-cell">
		{money(transaction.amount)}
		{#if transaction.is_reverse}<span class="rev-tag">Reversal</span>{/if}
	</td>
	<!--
		⚠ THE CELL STAYS WHEN FROZEN — only its CONTENTS go. Dropping the <td> would desynchronize
		this row from the page's `TABLE_COLUMNS`, and that constant is what every full-width editor
		row below spans via `colspan`. An empty cell, never a missing one. (UX caught this; the
		coupling is invisible from here, since the header lives in the page and the colspan lives
		in this file.)
	-->
	<td class="actions-cell">
		{#if !frozen}
			<div class="row-actions">
				{#if !isSecurityLinked}
					<Button variant="link" type="button" onclick={openEdit}>Edit</Button>
				{/if}
				<Button variant="link" type="button" onclick={openRecat}>Categorize</Button>
				{#if transaction.split_count > 0}
					<form method="POST" action="?/unsplitTrans" use:enhance={unsplitHandler} class="inline-form">
						<input type="hidden" name="trans_id" value={transaction.trans_id} />
						<Button variant="link" type="submit" loading={unsplitting}>Unsplit</Button>
					</form>
				{:else}
					<Button variant="link" type="button" onclick={() => (mode = 'split')}>Split</Button>
				{/if}
			</div>
		{/if}
	</td>
</tr>

{#if transaction.split_count > 0}
	{#each transaction.splits as s (s.id)}
		<tr class="split-child">
			<td></td>
			<td class="child-cat">↳ {childLabel(s)}</td>
			<td></td>
			<td>{s.note ?? '—'}</td>
			<td class="num num-cell">{money(s.amount)}</td>
			<td></td>
		</tr>
	{/each}
{/if}

{#if activeMode === 'edit'}
	<tr class="editor-row">
		<td colspan={columns}>
			<form method="POST" action="?/editTransFact" use:enhance={editHandler} class="editor" novalidate>
				<h3 class="editor-title">Edit transaction</h3>
				<p class="editor-help">
					Saving records a correction — the original entry is reversed and replaced (the
					ledger keeps a full history).
				</p>
				<input type="hidden" name="orig_trans_id" value={transaction.trans_id} />
				{#if editErrors._form}
					<p class="form-error" role="alert">{editErrors._form.join(' ')}</p>
				{/if}
				<TransactionFactFields
					idPrefix={`edit-${transaction.trans_id}`}
					{subCatGroups}
					errors={editErrors}
					bind:direction={editDirection}
					bind:amount={editAmount}
					bind:transaction_date={editDate}
					bind:vendor={editVendor}
					bind:description={editDescription}
					bind:sub_cat_id={editSubCat}
					bind:note={editNote}
				/>
				<div class="editor-actions">
					<Button variant="link" type="button" onclick={cancelEditor}>Cancel</Button>
					<Button variant="primary" type="submit" loading={editSaving}>Save changes</Button>
				</div>
			</form>
		</td>
	</tr>
{/if}

{#if activeMode === 'recat'}
	<tr class="editor-row">
		<td colspan={columns}>
			<form method="POST" action="?/recategorize" use:enhance={recatHandler} class="editor" novalidate>
				<h3 class="editor-title">Categorize transaction</h3>
				<input type="hidden" name="trans_id" value={transaction.trans_id} />
				{#if recatErrors._form}
					<p class="form-error" role="alert">{recatErrors._form.join(' ')}</p>
				{/if}
				<SelectField
					label="Category"
					name="sub_cat_id"
					bind:value={recatSubCat}
					errors={recatErrors.sub_cat_id}
					hint="Leave as Unsorted to clear the category."
					placeholder={{ value: '', label: 'Unsorted' }}
					groups={subCatGroups}
				/>
				<TextField label="Note" name="note" bind:value={recatNote} errors={recatErrors.note} hint="Optional." autocomplete="off" />
				<div class="editor-actions">
					<Button variant="link" type="button" onclick={cancelEditor}>Cancel</Button>
					<Button variant="primary" type="submit" loading={recatSaving}>Save</Button>
				</div>
			</form>
		</td>
	</tr>
{/if}

{#if activeMode === 'split'}
	<tr class="editor-row">
		<td colspan={columns}>
			<div class="editor">
				<h3 class="editor-title">Split transaction</h3>
				<SplitEditor {transaction} {subCatGroups} ondone={cancelEditor} />
			</div>
		</td>
	</tr>
{/if}

<style>
	.cat {
		color: var(--c-text-primary);
	}
	.split-tag {
		display: inline-block;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-sm);
		padding: 0 var(--space-1);
		font-size: var(--fs-micro);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--c-text-secondary);
	}
	.note {
		display: block;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
		white-space: normal;
		overflow-wrap: anywhere;
	}
	.rev-tag {
		display: inline-block;
		margin-left: var(--space-1);
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-sm);
		padding: 0 var(--space-1);
		font-size: var(--fs-micro);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--c-text-muted);
	}
	.trans.is-reverse td {
		color: var(--c-text-muted);
	}
	.actions-cell {
		white-space: nowrap;
	}
	.row-actions {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}
	.inline-form {
		display: inline;
	}
	.split-child td {
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border);
	}
	.child-cat {
		color: var(--c-text-secondary);
	}
	.editor-row td {
		background: var(--c-surface-alt);
		border-bottom: 1px solid var(--c-border-strong);
		padding: var(--space-4);
		white-space: normal;
	}
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		max-width: 34rem;
	}
	.editor-title {
		margin: 0;
		font-size: var(--fs-h3, var(--fs-body));
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.editor-help {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
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
	.editor-actions {
		display: flex;
		justify-content: flex-end;
		align-items: center;
		gap: var(--space-3);
	}
</style>
