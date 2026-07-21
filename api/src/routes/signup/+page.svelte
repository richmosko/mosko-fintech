<!--
	signup/+page.svelte — email+password signup UI (SELF-285 AC #2).
	Frontend-owned browser surface. Consumes /signup/+page.server.ts via the `form`
	(ActionData) interface; authors NO server logic.

	CONTRACT (Backend, authoritative):
	  load → no data.
	  form (on failure) : { errors: Record<string,string[]>, email: string }
	                      keys: email / password / confirm / _form.
	  success outcome A (confirmations OFF) → server-side redirect (no ActionData).
	  success outcome B (confirmations ON)  → { emailSent: true, email: string }
	                                          → render the "Check your email" state.

	Plain <form method="POST"> — progressive-enhancement + CSP-safe (no use:enhance,
	no inline handlers). The server-side .strict() schema is the security boundary;
	the browser gets fast feedback from the field primitives + native validation.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { ActionData } from './$types';

	let { form }: { form: ActionData } = $props();

	// Backend's fail() branches return two error shapes (a full field map vs. just
	// `_form`); both are string-keyed `{ field: string[] }` maps at runtime. Normalize
	// to one indexable type so per-field lookups typecheck across the union.
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);
</script>

<svelte:head>
	<title>Create account · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		{#if form?.emailSent}
			<!-- Success outcome B: confirmation email dispatched; account blocked until link followed. -->
			<h1 id="auth-title" class="title">Check your email</h1>
			<p class="lead">
				We sent a confirmation link to <strong>{form.email}</strong>. Follow it to finish
				setting up your account.
			</p>
			<p class="alt">
				Already confirmed? <a href="/login">Sign in</a>
			</p>
		{:else}
			<h1 id="auth-title" class="title">Create account</h1>

			{#if errors._form}
				<p class="banner" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<form method="POST" class="form">
				<TextField
					label="Email"
					name="email"
					type="email"
					autocomplete="email"
					required
					value={form?.email ?? ''}
					errors={errors.email ?? []}
				/>
				<TextField
					label="Password"
					name="password"
					type="password"
					autocomplete="new-password"
					hint="At least 8 characters."
					required
					errors={errors.password ?? []}
				/>
				<TextField
					label="Confirm password"
					name="confirm"
					type="password"
					autocomplete="new-password"
					required
					errors={errors.confirm ?? []}
				/>

				<Button variant="primary" type="submit">Create account</Button>
			</form>

			<p class="alt">
				Already have an account? <a href="/login">Sign in</a>
			</p>
		{/if}
	</section>
</main>

<style>
	.auth {
		min-height: 100vh;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: var(--space-5);
		box-sizing: border-box;
	}
	.card {
		width: 100%;
		max-width: 24rem;
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-2);
		padding: var(--space-6);
		box-sizing: border-box;
	}
	.title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h2) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.lead {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	/* Hard error — mirrors the field-error semantic color (see TextField.svelte). */
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-neg);
	}
	.alt {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
