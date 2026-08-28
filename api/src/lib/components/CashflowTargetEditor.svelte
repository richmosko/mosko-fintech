<!--
	CashflowTargetEditor.svelte — the §2.3.2 cash-flow targets editor (SELF-252 AC2/AC6).
	Frontend-owned browser surface. Mirrors PlanningTargetEditor.svelte's idiom (SELF-242) —
	same fetch+JSON shape, same dirty-diff-driven three-state field model, same step-up
	handling — applied to Backend's single-object UPSERT contract
	(POST /api/settings/cashflow-target; migration 090 / ADR-011 Decision 18) instead of
	that editor's per-row POST/DELETE pair.

	CONTRACT (props):
	  initialTargets : { income_target_annual: number | null; expense_target_monthly: number | null }
	                   — `loadCashflowTarget`'s return shape (cashflowTarget.ts), READ
	                   VERBATIM from Backend's pushed query module. A NULL column renders its
	                   field BLANK — never a seeded "0" (AC2: a stored $0 IS a target and
	                   would render as "0"; absence must render empty, since SELF-251's
	                   cash-flow caption branches on that exact distinction).

	THREE-STATE-PER-FIELD PAYLOAD (AC3/AC6 UI half — the crux Backend's schema/handler mirror
	on the server side): the payload is built ONLY from fields whose current text value
	differs from the field's own frozen baseline (same `values[f] !== baseline[f]` dirty
	predicate PlanningTargetEditor already uses, generalized from a per-row map to this
	component's two named fields):
	  - untouched (values[f] === baseline[f])         → key OMITTED from the POST body
	  - dirty + emptied to '' (via the Clear control,
	    or by manually deleting the text)              → key sent as JSON `null` (explicit
	                                                       unset — never a DELETE; this table
	                                                       carries two independent scalars in
	                                                       one row, so a DELETE would silently
	                                                       drop the OTHER field too — SELF-246
	                                                       AC7 / +server.ts header)
	  - dirty + a valid non-negative number            → key sent as that `number`
	This is the same shape the allocation editor's own dirty-diff already produces (empty ⇒
	unset intent, no separate boolean flag needed) — a Clear button is offered per field
	purely as a discoverable affordance (AC6's "a control that sends explicit null"), not a
	distinct code path from manually backspacing to empty. A field never sends BOTH "leave
	alone" and "clear" — omission and explicit-null are mutually exclusive by construction
	(one boolean predicate, `values[f] !== baseline[f]`, selects between them).

	VALIDATION (Lock 14 mod #2): field-level feedback is `sanitizeCurrencyAmount`
	($lib/validation/numeric.ts, the client mirror of the server's shared numeric battery)
	plus the SAME explicit non-negative refine the server layers on top of it
	(schemas/cashflow-target.ts mirrors this exactly) — the shared battery itself carries no
	sign stance for this shape. Server + DB CHECK remain the actual security boundary; this
	is UX fast-feedback only, and Save is disabled while any dirty field fails it.

	WHY FETCH, NOT A FORM ACTION: same carve-out PlanningTargetEditor states — the endpoint
	is a raw JSON REST route (+server.ts), not a page form action; a native
	<form method="POST"> cannot express "POST this JSON object, read structured field
	errors back". Not batched-many-rows here (only two fields), but the endpoint shape is
	the same JSON contract either way.

	States (design-system-spec.md §4): default · editing(dirty) · saving · disabled(no valid
	change) · error(per-field) · empty(bootstrap) · saved. No staleness-marker here — a
	cash-flow target is user-authored planning data, not a derived aggregation over account
	balances (same ADR-013 D1 exemption PlanningTargetEditor's header already states for
	%Target).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { sanitizeCurrencyAmount } from '$lib/validation/numeric';

	type Field = 'income_annual' | 'expense_monthly';
	const FIELDS: Field[] = ['income_annual', 'expense_monthly'];

	type InitialTargets = { income_target_annual: number | null; expense_target_monthly: number | null };

	let { initialTargets }: { initialTargets: InitialTargets } = $props();

	function formatInitial(v: number | null): string {
		return v === null || v === undefined ? '' : String(v);
	}

	// Frozen baseline for dirty-diffing, captured once from the props this component mounted
	// with — same deliberate non-`$derived` choice PlanningTargetEditor documents (the
	// editor's own life cycle ends in a redirect on success, so a stale baseline across a
	// long-lived session is not a concern here).
	const baseline: Record<Field, string> = {
		income_annual: formatInitial(initialTargets.income_target_annual),
		expense_monthly: formatInitial(initialTargets.expense_target_monthly)
	};

	let values = $state<Record<Field, string>>({ ...baseline });
	let serverErrors = $state<Partial<Record<Field, string>>>({});
	let formError = $state('');
	let saving = $state(false);
	let statusMessage = $state('');

	const dirtyFields = $derived(FIELDS.filter((f) => values[f] !== baseline[f]));
	const hasDirty = $derived(dirtyFields.length > 0);

	/** Mirrors the server's `nonNegativeCurrencyAmount` refine — sanitizeCurrencyAmount
	 *  itself carries no sign stance for this shape. */
	function clientErrorFor(f: Field): string | null {
		const raw = values[f];
		if (raw === '') return null; // empty = unset, not an error (empty(bootstrap) state)
		const r = sanitizeCurrencyAmount(raw);
		if (!r.ok) return r.reason;
		if (r.value < 0) return 'Enter a non-negative amount.';
		return null;
	}

	const anyClientError = $derived(dirtyFields.some((f) => clientErrorFor(f) !== null));
	const saveDisabled = $derived(!hasDirty || anyClientError || saving);

	function errorsFor(f: Field): string[] {
		const server = serverErrors[f];
		if (server) return [server];
		const client = dirtyFields.includes(f) ? clientErrorFor(f) : null;
		return client ? [client] : [];
	}

	function clearField(f: Field) {
		values[f] = '';
	}

	const FIELD_LABELS: Record<Field, string> = {
		income_annual: 'Annual income target',
		expense_monthly: 'Monthly expense target'
	};

	async function extractError(res: Response): Promise<{ formError: string; fieldErrors?: Partial<Record<Field, string>> }> {
		let body: unknown = null;
		try {
			body = await res.json();
		} catch {
			/* fall through to generic message */
		}
		if (res.status === 401) return { formError: 'Please sign in again.' };
		const b = body as { error?: string; fieldErrors?: Record<string, string[]> } | null;
		if (res.status === 403 && b?.error === 'step_up_required') {
			return { formError: "Verify it's you and try again." };
		}
		if (res.status === 400 && b?.fieldErrors) {
			const fieldErrors: Partial<Record<Field, string>> = {};
			for (const f of FIELDS) {
				const msg = b.fieldErrors[f]?.[0];
				if (msg) fieldErrors[f] = msg;
			}
			if (Object.keys(fieldErrors).length > 0) {
				return { formError: 'Some changes could not be saved — see the fields below.', fieldErrors };
			}
		}
		if (b?.error === 'invalid_amount') return { formError: 'One of the amounts could not be saved.' };
		return { formError: 'Something went wrong saving your changes. Please try again.' };
	}

	async function handleSave(event: SubmitEvent) {
		event.preventDefault();
		if (saveDisabled) return;

		formError = '';
		serverErrors = {};
		saving = true;

		// Three-state payload — see the file header. Only DIRTY fields are keys at all;
		// an empty dirty field sends explicit `null`, never both keys unconditionally.
		const body: Partial<Record<Field, number | null>> = {};
		for (const f of dirtyFields) {
			if (values[f] === '') {
				body[f] = null;
				continue;
			}
			const r = sanitizeCurrencyAmount(values[f]);
			if (r.ok && r.value >= 0) body[f] = r.value;
		}

		try {
			const res = await fetch('/api/settings/cashflow-target', {
				method: 'POST',
				headers: { 'content-type': 'application/json' },
				body: JSON.stringify(body)
			});

			if (!res.ok) {
				const { formError: fe, fieldErrors } = await extractError(res);
				if (fieldErrors) serverErrors = fieldErrors;
				formError = fe;
				saving = false;
				return;
			}

			statusMessage = 'Changes saved.';
			await goto('/cash-flow');
		} catch {
			formError = 'Something went wrong saving your changes. Please try again.';
			saving = false;
		}
	}
</script>

<form class="editor" onsubmit={handleSave}>
	{#if formError}
		<p class="banner" role="alert">{formError}</p>
	{/if}
	{#if statusMessage}
		<p class="sr-only" role="status">{statusMessage}</p>
	{/if}

	<div class="fields">
		{#each FIELDS as f (f)}
			<div class="row">
				<TextField
					label={FIELD_LABELS[f]}
					name={f}
					bind:value={values[f]}
					inputmode="decimal"
					numeric
					placeholder="0.00"
					hint="Leave blank for no target."
					errors={errorsFor(f)}
				/>
				<Button
					variant="link"
					type="button"
					disabled={values[f] === ''}
					onclick={() => clearField(f)}
					aria-label={`Clear ${FIELD_LABELS[f]}`}
				>
					Clear
				</Button>
			</div>
		{/each}
	</div>

	<div class="actions">
		<Button variant="primary" type="submit" loading={saving} disabled={saveDisabled}>
			Save changes
		</Button>
	</div>
</form>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}
	.fields {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-2);
	}
	.row :global(.field) {
		flex: 1;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
	}
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-neg);
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
