<!--
	accounts/new/+page.svelte — manual (non-Plaid) account onboarding form.
	SELF-201 §2.4.2 AC #1/#2. Single-pass form; six attributes + Sub-Cat in ONE pass.
	POSTs to the default (unnamed) action in +page.server.ts via <form method="POST"
	use:enhance>. NO Plaid Link, NO credential prompt (PRD §2.4.2 verbatim).

	Client Zod .strict() mirror ($lib/schemas/account) runs on submit for fast field-
	level feedback; the SERVER schema is the security boundary. On a client-invalid
	submit we cancel() the POST and render client errors; server-side fail() returns
	{ errors, values } which render through the SAME code path. On success the server
	303-redirects to /accounts/{id} — no client handling needed.
-->
<script lang="ts">
	import { enhance } from '$app/forms';
	import type { SubmitFunction } from '@sveltejs/kit';
	import type { ActionData } from './$types';
	import { ACCOUNT_TYPES, TAX_TREATMENTS } from '$lib/schemas/account-constants';
	import { ACCOUNT_TYPE_LABELS, TAX_TREATMENT_LABELS } from '$lib/account-display';
	import { manualAccountCreateSchema, fieldErrors } from '$lib/schemas/account';
	import TextField from '$lib/components/TextField.svelte';
	import SelectField from '$lib/components/SelectField.svelte';
	import Button from '$lib/components/Button.svelte';

	let { form }: { form: ActionData } = $props();

	// Sticky field values. Seeded from the server echo (`form.values`) so a no-JS POST
	// still repopulates; with JS the bound state is the live source across a failed submit.
	// svelte-ignore state_referenced_locally -- init-only sticky seed; the bound state is
	// the live source thereafter (we keep typed values on a failed submit via reset:false).
	const v0 = (form?.values ?? {}) as Record<string, string>;
	let name = $state(v0.name ?? '');
	let account_type = $state(v0.account_type ?? '');
	let scope = $state(v0.scope ?? '');
	let tax_treatment = $state(v0.tax_treatment ?? '');
	let initial_value = $state(v0.initial_value ?? '');
	let as_of_date = $state(v0.as_of_date ?? '');

	let clientErrors = $state<Record<string, string[]>>({});
	let submitting = $state(false);

	// Merge: client errors take precedence over the last server error envelope.
	// The server ActionData is a union of fail() shapes; flatten to a plain field→messages
	// map so per-field access (errors.name, …) is well-typed regardless of which branch.
	const errors = $derived(
		{ ...(form?.errors ?? {}), ...clientErrors } as Record<string, string[]>
	);

	const typeOptions = ACCOUNT_TYPES.map((t) => ({ value: t, label: ACCOUNT_TYPE_LABELS[t] }));
	const taxOptions = TAX_TREATMENTS.map((t) => ({ value: t, label: TAX_TREATMENT_LABELS[t] }));

	// use:enhance handler — client-validate, then let the POST proceed (server is boundary).
	const enhanceHandler: SubmitFunction = ({ cancel }) => {
		const parsed = manualAccountCreateSchema.safeParse({
			name,
			account_type,
			scope,
			tax_treatment,
			initial_value,
			as_of_date
		});
		if (!parsed.success) {
			clientErrors = fieldErrors(parsed.error);
			cancel();
			return;
		}
		clientErrors = {};
		submitting = true;
		return async ({ update }) => {
			// Keep typed values on a server-side failure (reset:false); success redirects.
			await update({ reset: false });
			submitting = false;
		};
	};
</script>

<svelte:head>
	<title>Add account — mosko-fintech</title>
</svelte:head>

<main class="page">
	<nav class="breadcrumb" aria-label="Breadcrumb">
		<a href="/accounts">Accounts</a>
		<span class="sep" aria-hidden="true">/</span>
		<span class="crumb-current" aria-current="page">Add account</span>
	</nav>

	<h1>Add a manual account</h1>
	<p class="lede">
		Track an account you'll update by hand — no bank connection. Enter its details and an
		opening balance.
	</p>

	<form
		method="POST"
		use:enhance={enhanceHandler}
		class="region form"
		novalidate
		aria-describedby={errors._form ? 'form-error' : undefined}
	>
		{#if errors._form}
			<p id="form-error" class="form-error" role="alert">{errors._form.join(' ')}</p>
		{/if}

		<TextField
			label="Account name"
			name="name"
			bind:value={name}
			required
			errors={errors.name}
			autocomplete="off"
			placeholder="e.g. Vanguard brokerage"
		/>

		<SelectField
			label="Account type"
			name="account_type"
			bind:value={account_type}
			required
			errors={errors.account_type}
			placeholder={{ value: '', label: 'Select…' }}
			options={typeOptions}
		/>

		<TextField
			label="Scope"
			name="scope"
			bind:value={scope}
			required
			errors={errors.scope}
			hint="Whose account this is or how you group it (e.g. Personal, Joint)."
			autocomplete="off"
		/>

		<SelectField
			label="Tax treatment"
			name="tax_treatment"
			bind:value={tax_treatment}
			required
			errors={errors.tax_treatment}
			placeholder={{ value: '', label: 'Select…' }}
			options={taxOptions}
		/>

		<TextField
			label="Opening balance"
			name="initial_value"
			bind:value={initial_value}
			required
			numeric
			inputmode="decimal"
			errors={errors.initial_value}
			hint="Plain digits — no currency symbol or commas (e.g. 1500.00)."
			placeholder="0.00"
			autocomplete="off"
		/>

		<TextField
			label="As-of date"
			name="as_of_date"
			type="date"
			bind:value={as_of_date}
			required
			errors={errors.as_of_date}
			hint="The date the opening balance is accurate as of."
		/>

		<div class="actions">
			<Button variant="link" type="button" onclick={() => history.back()}>Cancel</Button>
			<Button variant="primary" type="submit" loading={submitting}>Create account</Button>
		</div>
	</form>
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
	.form {
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
