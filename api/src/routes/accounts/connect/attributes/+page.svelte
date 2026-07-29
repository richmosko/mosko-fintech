<!--
	accounts/connect/attributes/+page.svelte — SELF-199 §2.4.1.d per-account attribute capture.

	The step AFTER the automated-aggregator connect (Plaid / SimpleFIN). The connect widget
	returned a provider-blind AccountRef[] (+ linked_source_id) for the accounts the user chose
	to share; here the user gives each one the four V1 attributes the app needs before it can
	track it:
	  • name          — editable label (seeded from the institution's account name)
	  • scope         — free-text ownership label (ADR-004 Dec B; NOT an isolation boundary)
	  • tax_treatment — TAX_TREATMENTS enum
	  • account_type  — ACCOUNT_TYPES enum, SEEDED from the adapter subtype as a confirm/override
	                    recommendation (ADR-037 SELF-199: "adapter metadata seeds the form;
	                    absent → user sets") — SimpleFIN's type:'unknown' starts it unselected.

	CLIENT-CARRIES-REFS SEAM (SELF-199 seam (b)): the AccountRef[] + linked_source_id are read
	from the in-memory handoff (consumed once on entry) — NOT from a server loader (this data is
	not server-known at render time; it came from a client-initiated relay call on the previous
	screen). FAIL-CLOSED: a direct nav / reload / back-forward finds an empty carry and renders
	the "start a connection" empty state instead of a broken form. Unselected accounts never
	reached the connect result, so they never reach here.

	VALIDATION: the client-side connect-attributes Zod .strict() mirror runs per-row on submit
	for fast field-level feedback. The SERVER schema (Backend, +page.server.ts action) is the
	security boundary — this mirror is never looser (same .strict(), same value-sets, same
	min/max). a11y: every control labelled (per-row unique ids), errors role="alert", the
	per-account group is a titled <fieldset>.

	SUBMIT — LIVE (Backend persist action verified end-to-end against the fixed 042 RPC): the
	form POSTs to Backend's `+page.server.ts` default action, which JSON.parses the single hidden
	`payload` field, `.strict()`-validates it (landLinkedAccountsSchema), maps each account →
	the fn_land_linked_accounts INVOKER RPC (account_id → provider_account_id server-side), and
	303-redirects to /accounts on success. Errors return `fail()` with `{ errors: { _form: [...] } }`
	(403 + a distinct message for the cross-tenant #6-fence) — rendered form-level below. The
	server schema is the security boundary; the client `.strict()` mirror is UX fast-feedback.

	Tokens ONLY (var(--c-*)). No staleness surface here (this is a capture form, not an
	aggregation). No planning-value inline edit (P5 n/a — these are new-account attributes).
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { ActionData } from './$types';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';
	import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';
	import { ACCOUNT_TYPE_LABELS, TAX_TREATMENT_LABELS } from '$lib/account-display';
	import { consumeConnectHandoff } from '$lib/accounts/connect-handoff.svelte';
	import { recommendAccountType, type AccountRef } from '$lib/accounts/account-ref';
	import {
		connectAccountAttributesSchema,
		connectAttributesSubmitSchema,
		fieldErrors
	} from '$lib/schemas/connect-attributes';

	// Server action result — form-level errors on fail(); success 303-redirects to /accounts.
	let { form }: { form: ActionData } = $props();

	// ── Consume the client-carried handoff ONCE on entry (single-use; see fail-closed note) ─
	const handoff = consumeConnectHandoff();
	const linkedSourceId = handoff?.linkedSourceId ?? null;

	type Row = {
		ref: AccountRef;
		recommended: boolean; // was account_type pre-seeded from adapter metadata?
		name: string;
		scope: string;
		tax_treatment: string;
		account_type: string;
		errors: Record<string, string[]>;
	};

	let rows = $state<Row[]>(
		(handoff?.accounts ?? []).map((ref) => {
			const rec = recommendAccountType(ref);
			return {
				ref,
				recommended: rec !== undefined,
				name: ref.name ?? '',
				scope: '',
				tax_treatment: '',
				account_type: rec ?? '',
				errors: {}
			};
		})
	);

	const hasAccounts = $derived(rows.length > 0);
	// linked_source_id is required to persist (it ties the accounts to their pfin.linked_source
	// row). If the carry is present but the id is missing, we can render/validate but not save.
	const canPersist = $derived(hasAccounts && linkedSourceId !== null);

	let submitState = $state<'idle' | 'submitting'>('idle');
	let formError = $state('');

	// Server-side action errors, form-level. Backend's fieldErrors buckets under `_form` (plus
	// `linked_source_id` / `accounts` on a schema reject); the 401/400/403/422 paths all arrive
	// as `_form`. Fold every server error array in so nothing is silently dropped.
	const serverFormError = $derived(
		Object.values((form?.errors ?? {}) as Record<string, string[]>)
			.flat()
			.join(' ')
	);

	const typeOptions = ACCOUNT_TYPES.map((t) => ({ value: t, label: ACCOUNT_TYPE_LABELS[t] }));
	const taxOptions = TAX_TREATMENTS.map((t) => ({ value: t, label: TAX_TREATMENT_LABELS[t] }));

	/** Build the validated submit envelope from row state (also the JSON `payload` shape). */
	function buildEnvelope() {
		return {
			linked_source_id: linkedSourceId ?? '',
			accounts: rows.map((r) => ({
				account_id: r.ref.account_id,
				name: r.name,
				scope: r.scope,
				tax_treatment: r.tax_treatment,
				account_type: r.account_type
			}))
		};
	}

	// JSON payload the form action receives (proposed encoding — Backend confirms). Kept live
	// via $derived so the hidden input reflects current row state at submit time.
	const payloadJson = $derived(JSON.stringify(buildEnvelope()));

	/** Per-row + envelope client validation. Returns true when everything is valid. */
	function validate(): boolean {
		let ok = true;
		for (const r of rows) {
			const parsed = connectAccountAttributesSchema.safeParse({
				account_id: r.ref.account_id,
				name: r.name,
				scope: r.scope,
				tax_treatment: r.tax_treatment,
				account_type: r.account_type
			});
			r.errors = parsed.success ? {} : fieldErrors(parsed.error);
			if (!parsed.success) ok = false;
		}
		// Envelope-level checks (linked_source_id present, ≥1 account).
		const env = connectAttributesSubmitSchema.safeParse(buildEnvelope());
		if (!env.success) {
			ok = false;
			const fe = fieldErrors(env.error);
			formError = fe.linked_source_id?.length
				? "This connection can't be saved — please reconnect the institution."
				: (fe.accounts?.join(' ') ?? fe._form?.join(' ') ?? 'Please fix the errors above.');
		} else {
			formError = '';
		}
		return ok;
	}

	// use:enhance handler — client-validate first; the SERVER action is the boundary.
	const enhanceHandler: SubmitFunction = ({ cancel }) => {
		if (!validate()) {
			cancel();
			return;
		}
		submitState = 'submitting';
		return async ({ update }) => {
			// reset:false keeps the typed values on a server-side fail(); success 303-redirects.
			await update({ reset: false });
			submitState = 'idle';
		};
	};

	/** Recognition line for an account: mask / subtype / currency (display-only). */
	function refDetail(ref: AccountRef): string {
		const bits: string[] = [];
		if (ref.mask) bits.push(`••${ref.mask}`);
		if (ref.subtype) bits.push(ref.subtype);
		else if (ref.type && ref.type !== 'unknown') bits.push(ref.type);
		if (ref.currency) bits.push(ref.currency);
		return bits.join(' · ');
	}
</script>

<svelte:head>
	<title>Set up your accounts — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<a href="/accounts/connect">Connect institution</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">Set up accounts</span>
	</nav>

	<h1>Set up your accounts</h1>

	{#if !hasAccounts}
		<!-- FAIL-CLOSED empty state: no carried refs (direct nav / reload / back-forward). -->
		<section class="region card empty" aria-labelledby="empty-heading">
			<h2 id="empty-heading">Nothing to set up yet</h2>
			<p class="card-note">
				Connect an institution first, then choose which accounts to share — you'll set each
				one's details here.
			</p>
			<a class="cta" href="/accounts/connect">Connect an institution</a>
		</section>
	{:else}
		<p class="lede">
			You connected {rows.length}
			{rows.length === 1 ? 'account' : 'accounts'}. Give each one a name and tell us how to
			track it. We suggested a type where we could — change it if it's not right.
		</p>

		{#if !canPersist}
			<!-- Refs carried but linked_source_id missing → can't persist. Non-error advisory. -->
			<p class="notice" role="status">
				We couldn't fully register this connection. You can review the details below, but you'll
				need to <a href="/accounts/connect">reconnect the institution</a> before saving.
			</p>
		{/if}

		<form method="POST" use:enhance={enhanceHandler} class="accounts-form" novalidate>
			<!-- Proposed FormData encoding (Backend confirms): the whole envelope as one JSON
			     field the action JSON.parses then .strict()-validates. -->
			<input type="hidden" name="payload" value={payloadJson} />

			{#each rows as row, i (row.ref.account_id)}
				<fieldset class="region card account" aria-labelledby={`acct-${i}-title`}>
					<legend class="account-legend">
						<span class="account-index">Account {i + 1} of {rows.length}</span>
						<span id={`acct-${i}-title`} class="account-title">
							{row.ref.name || 'New account'}
						</span>
						{#if refDetail(row.ref)}
							<span class="account-detail">{refDetail(row.ref)}</span>
						{/if}
					</legend>

					<TextField
						label="Account name"
						name={`name-${i}`}
						bind:value={row.name}
						required
						errors={row.errors.name}
						autocomplete="off"
						placeholder="e.g. Vanguard brokerage"
					/>

					<TextField
						label="Scope"
						name={`scope-${i}`}
						bind:value={row.scope}
						required
						errors={row.errors.scope}
						hint="Whose account this is or how you group it (e.g. Personal, Trust, Retirement-IRA)."
						autocomplete="off"
					/>

					<SelectField
						label="Account type"
						name={`account_type-${i}`}
						id={`f-account_type-${i}`}
						bind:value={row.account_type}
						required
						errors={row.errors.account_type}
						hint={row.recommended
							? 'Suggested from your institution — change it if this looks wrong.'
							: 'Choose how to classify this account.'}
						placeholder={{ value: '', label: 'Select…' }}
						options={typeOptions}
					/>

					<SelectField
						label="Tax treatment"
						name={`tax_treatment-${i}`}
						id={`f-tax_treatment-${i}`}
						bind:value={row.tax_treatment}
						required
						errors={row.errors.tax_treatment}
						placeholder={{ value: '', label: 'Select…' }}
						options={taxOptions}
					/>
				</fieldset>
			{/each}

			{#if formError || serverFormError}
				<p class="form-error" role="alert">{formError || serverFormError}</p>
			{/if}

			<div class="actions">
				<Button variant="link" type="button" onclick={() => history.back()}>Back</Button>
				<Button
					variant="primary"
					type="submit"
					loading={submitState === 'submitting'}
					disabled={!canPersist}
				>
					Save accounts
				</Button>
			</div>
		</form>
	{/if}
</main>

<style>
	.page {
		max-width: 34rem;
		margin: 0 auto;
		padding: var(--space-6) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.breadcrumb {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.breadcrumb a {
		color: var(--c-link);
		text-decoration: none;
	}
	.breadcrumb a:hover {
		text-decoration: underline;
	}
	.breadcrumb .sep {
		color: var(--c-text-muted);
	}
	.breadcrumb .crumb-current {
		color: var(--c-text-primary);
		font-weight: var(--weight-semi);
	}
	h1 {
		margin: 0;
		font-size: var(--fs-h1);
		font-weight: var(--weight-bold);
		line-height: var(--lh-tight);
		color: var(--c-text-primary);
	}
	.lede {
		margin: 0;
		color: var(--c-text-secondary);
	}
	.card {
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		padding: var(--space-5);
		box-shadow: var(--shadow-1);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		margin-top: var(--space-2);
	}
	.card h2 {
		margin: 0;
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.card-note {
		margin: 0;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.empty {
		align-items: flex-start;
		gap: var(--space-3);
	}
	.cta {
		align-self: flex-start;
		color: var(--c-link);
		font-size: var(--fs-small);
		font-weight: var(--weight-med);
	}
	.accounts-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	/* Each account is a titled fieldset styled as a card. Reset the native fieldset chrome. */
	.account {
		border: 1px solid var(--c-border);
		min-inline-size: 0; /* let the fieldset shrink in flex/grid contexts */
	}
	.account-legend {
		/* A <legend> can't be flex; lay its parts out with inline spacing instead. */
		padding: 0;
		display: block;
	}
	.account-index {
		display: block;
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.account-title {
		display: block;
		font-size: var(--fs-h2);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	.account-detail {
		display: block;
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
		font-family: var(--font-num);
	}
	.notice {
		margin: 0;
		padding: var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
	}
	.notice a {
		color: var(--c-link);
		font-weight: var(--weight-med);
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
		margin-top: var(--space-2);
	}
</style>
