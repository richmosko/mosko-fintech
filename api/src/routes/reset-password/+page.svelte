<!--
	reset-password/+page.svelte — set a new password on the recovery session
	(SELF-288 / Auth-5, AC #1). Frontend-owned browser surface. Consumes
	/reset-password/+page.server.ts via the `data` (PageData) + `form` (ActionData)
	interface; authors NO server logic.

	Reached via the email recovery link → /auth/callback mints a recovery session →
	bounces here. If NO recovery session exists, the server load() already threw
	redirect(303, '/forgot-password?expired=1'), so by the time this renders we can
	assume data.ready === true.

	CONTRACT (Backend, authoritative — reset-password/+page.server.ts):
	  load → { ready: true }
	  form (success)   : server 303 → /login?reset=success (NO ActionData; nothing to render).
	  form (fail 400)  : { errors: Record<string,string[]> }
	                     keys: password / confirm / _form → too short (min 8) / mismatch / invalid.
	  form (fail 401)  : { errors: { _form: string[] } } → recovery session expired → form banner.

	Plain <form method="POST"> — progressive-enhancement + CSP-safe (no use:enhance, no inline
	handlers). The server-side .strict() resetPasswordSchema is the security boundary (min 8 /
	max 72 / password===confirm); the client match hint below is fast-feedback UX ONLY — the
	server is authoritative.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	// Backend's fail() branches return two error shapes (a full field map vs. just `_form`);
	// both are string-keyed `{ field: string[] }` maps at runtime. Normalize to one indexable
	// type so per-field lookups typecheck across the union.
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);

	// data.ready is always true here (see header) — reference it so the prop is consumed and
	// stays in the contract's typecheck surface.
	const ready = $derived(data.ready);

	// Client-side match hint — fast feedback ONLY (the server .refine() is authoritative).
	// Show it once the user has typed into confirm and the two values diverge.
	let password = $state('');
	let confirm = $state('');
	const mismatch = $derived(confirm.length > 0 && password !== confirm);
</script>

<svelte:head>
	<title>Set a new password · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		<h1 id="auth-title" class="title">Set a new password</h1>

		{#if errors._form}
			<p class="banner" role="alert">{errors._form.join(' ')}</p>
		{/if}

		{#if ready}
			<form method="POST" class="form">
				<TextField
					label="New password"
					name="password"
					type="password"
					autocomplete="new-password"
					hint="At least 8 characters."
					required
					bind:value={password}
					errors={errors.password ?? []}
				/>
				<TextField
					label="Confirm new password"
					name="confirm"
					type="password"
					autocomplete="new-password"
					required
					bind:value={confirm}
					errors={errors.confirm ?? []}
				/>

				{#if mismatch}
					<!-- Client match hint: informational fast-feedback, NOT an alert (aria-live polite,
					     not assertive) — the server .refine() is the authoritative check. -->
					<p class="match-hint" role="status" aria-live="polite">
						Passwords don't match yet.
					</p>
				{/if}

				<Button variant="primary" type="submit">Update password</Button>
			</form>
		{/if}

		<p class="alt">
			<a href="/login">Back to sign in</a>
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
	/* Neutral, informational — deliberately NOT the --c-neg error hue: the server refine is
	   authoritative, this is a live nudge while typing. */
	.match-hint {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-muted);
	}
	.alt {
		margin: 0;
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
</style>
