<!--
	login/+page.svelte — password sign-in UI (SELF-285 AC #1).
	Frontend-owned browser surface. Consumes /login/+page.server.ts via the `data`
	(PageData) + `form` (ActionData) interface; authors NO server logic.

	CONTRACT (Backend, authoritative):
	  data.redirectTo : string  — same-site-guarded server-side; round-tripped as a
	                              hidden field so the action can honor it on success.
	  form (on failure) : { errors: Record<string,string[]>, email: string }
	                      keys: email / password / _form.
	                      bad credentials → errors._form = ['Invalid email or password.']
	  success → server-side redirect (no ActionData).
	  ?error=confirmation in the URL → show the invalid/expired-link notice.

	Plain <form method="POST"> — progressive-enhancement + CSP-safe (no use:enhance,
	no inline handlers; the app-global strict CSP forbids inline style/script). The
	server-side .strict() schema is the security boundary; the browser gets fast
	feedback from the field primitives + native validation.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { page } from '$app/state';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	// Backend's fail() branches return two error shapes (a full field map vs. just
	// `_form`); both are string-keyed `{ field: string[] }` maps at runtime. Normalize
	// to one indexable type so per-field lookups typecheck across the union.
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);

	// The /auth/callback handler bounces an invalid/expired confirmation link back to
	// /login?error=confirmation. Read it off the live URL (SvelteKit 2 / Svelte 5 idiom).
	const confirmationError = $derived(page.url.searchParams.get('error') === 'confirmation');

	// A completed password reset (SELF-288) 303s here with ?reset=success — nudge the user to
	// sign in with the new password. Positive/neutral status, not an error.
	const resetSuccess = $derived(page.url.searchParams.get('reset') === 'success');
</script>

<svelte:head>
	<title>Sign in · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		<h1 id="auth-title" class="title">Sign in</h1>

		{#if resetSuccess}
			<p class="notice" role="status">
				Password updated — sign in with your new password.
			</p>
		{/if}

		{#if confirmationError}
			<p class="notice" role="status">
				That confirmation link was invalid or expired — please sign in or try again.
			</p>
		{/if}

		{#if errors._form}
			<p class="banner" role="alert">{errors._form.join(' ')}</p>
		{/if}

		<form method="POST" class="form">
			<!-- Round-trip the guarded redirect target (open-redirect fence lives server-side). -->
			<input type="hidden" name="redirectTo" value={data.redirectTo} />

			<TextField
				label="Email"
				name="email"
				type="email"
				autocomplete="username"
				required
				value={form?.email ?? ''}
				errors={errors.email ?? []}
			/>
			<TextField
				label="Password"
				name="password"
				type="password"
				autocomplete="current-password"
				required
				errors={errors.password ?? []}
			/>

			<p class="forgot">
				<a href="/forgot-password">Forgot password?</a>
			</p>

			<Button variant="primary" type="submit">Sign in</Button>
		</form>

		<p class="alt">
			New here? <a href="/signup">Create an account</a>
		</p>
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
	/* Right-aligned inline link directly under the password field; small type, secondary weight. */
	.forgot {
		margin: calc(var(--space-2) * -1) 0 0;
		text-align: right;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
	}
</style>
