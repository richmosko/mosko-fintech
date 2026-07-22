<!--
	mfa/recover/+page.svelte — MFA recovery via a one-time backup code (SELF-291 /
	Auth-3b Slice 2b, AC#4). Frontend-owned browser surface. Consumes
	/mfa/recover/+page.server.ts via the `data` (PageData) + `form` (ActionData) interface;
	authors NO server logic.

	CONTRACT (Backend, authoritative — see +page.server.ts):
	  data.mode : 'ready'  — the only case rendered. The server 303s away when there's
	              nothing to recover (no verified factor / already aal2), so this page only
	              ever renders the redeem form.
	  action ?/redeem — field `code` (the user pastes/types a backup code; the server
	              normalizes lowercase + strips spaces/dashes to 16-char base32).
	    success  → 303 /settings/security?recovered=1 (no ActionData).
	    'invalid'→ fail(400, { errors:{ _form } }).
	    'locked' → fail(429, { errors:{ _form } }).
	  The `_form` error envelope matches /login + /mfa/step-up.

	Plain <form method="POST"> — progressive-enhancement + CSP-safe (no use:enhance, no
	inline handlers), mirroring /login + /mfa/step-up. The server-side .strict() schema is
	the security boundary; the client Zod mirror (schemas/mfa.recoveryCodeSchema) is the
	shape-of-record for the normalized 16-char base32 code — deliberately tolerant of the
	grouped `abcd-efgh-ijkl-mnop` display form (the server normalizes; we don't over-restrict).

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	// Single indexable error shape across the fail() branches (all `{ _form: string[] }`).
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);
	// `data.mode` is always 'ready' here (the server redirects every other case away);
	// referenced so the contract stays visible and typechecked.
	const ready = $derived(data.mode === 'ready');
</script>

<svelte:head>
	<title>Use a backup code · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		<h1 id="auth-title" class="title">Use a backup code</h1>
		<p class="lead">
			Lost access to your authenticator app? Enter one of the one-time backup codes you saved
			when you set up two-factor authentication. You'll be signed in and asked to set up a fresh
			authenticator.
		</p>

		{#if errors._form}
			<p class="banner" role="alert">{errors._form.join(' ')}</p>
		{/if}

		{#if ready}
			<form method="POST" action="?/redeem" class="form">
				<TextField
					label="Backup code"
					name="code"
					type="text"
					inputmode="text"
					autocomplete="one-time-code"
					hint="Looks like abcd-efgh-ijkl-mnop. Spaces and dashes are fine."
					required
					errors={errors.code ?? []}
				/>
				<Button variant="primary" type="submit">Sign in with backup code</Button>
			</form>
		{/if}

		<p class="alt">
			Have your authenticator? <a href="/mfa/step-up">Enter a code instead</a>
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
	.alt {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	/* Hard error — mirrors the field-error semantic color (see TextField.svelte / login). */
	.banner {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: color-mix(in srgb, var(--c-neg) 10%, transparent);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		font: var(--weight-med) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-neg);
	}
</style>
