<!--
	forgot-password/+page.svelte — request a password-reset link (SELF-288 / Auth-5, AC #1).
	Frontend-owned browser surface. Consumes /forgot-password/+page.server.ts via the `form`
	(ActionData) interface; authors NO server logic.

	CONTRACT (Backend, authoritative — forgot-password/+page.server.ts):
	  load → no data.
	  form (success)      : { done: true }
	                        → render the UNIFORM anti-enumeration message. This is the SAME
	                          message whether or not the email is registered — there is NO
	                          "email not found" state, by design (AC #4, SECURITY-load-bearing).
	  form (fail 400)     : { errors: Record<string,string[]>, email: string }
	                        keys: email / _form → malformed-email field error.
	  form (fail 429)     : { rateLimited: true, errors: { _form: string[] } }
	                        → form-level rate-limit banner.
	  ?expired=1 in URL   → info banner (a stale reset link was followed).

	Plain <form method="POST"> — progressive-enhancement + CSP-safe (no use:enhance, no inline
	handlers). The server-side .strict() forgotPasswordSchema is the security boundary; the
	browser gets fast feedback from the field primitive + native email validation.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { page } from '$app/state';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { ActionData } from './$types';

	let { form }: { form: ActionData } = $props();

	// Backend's fail() branches return two error shapes (a full field map vs. just `_form`);
	// both are string-keyed `{ field: string[] }` maps at runtime. Normalize to one indexable
	// type so per-field lookups typecheck across the union.
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);

	// A stale/expired reset link bounces the user here with ?expired=1 (reset-password load()
	// throws redirect(303, '/forgot-password?expired=1')). Informational, not an error.
	const expired = $derived(page.url.searchParams.get('expired') === '1');
</script>

<svelte:head>
	<title>Reset your password · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		{#if form?.done}
			<!-- UNIFORM anti-enumeration outcome. Identical for registered / unregistered / errored
			     email — never render a state that reveals whether an account exists (AC #4). -->
			<h1 id="auth-title" class="title">Check your email</h1>
			<p class="lead" role="status">
				If an account exists, a reset link has been sent.
			</p>
			<p class="alt">
				<a href="/login">Back to sign in</a>
			</p>
		{:else}
			<h1 id="auth-title" class="title">Reset your password</h1>
			<p class="lead">
				Enter your email and we'll send you a link to set a new password.
			</p>

			{#if expired}
				<p class="notice" role="status">
					Your reset link expired — request a new one below.
				</p>
			{/if}

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

				<Button variant="primary" type="submit">Send reset link</Button>
			</form>

			<p class="alt">
				Remembered it? <a href="/login">Sign in</a>
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
	/* Neutral notice — NOT the attention hue (reserved for staleness/re-auth per the
	   design-system fence). A stale-link nudge is informational, not an alert. */
	.notice {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
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
