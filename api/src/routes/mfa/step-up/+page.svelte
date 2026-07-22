<!--
	mfa/step-up/+page.svelte — TOTP step-up challenge (SELF-291 / Auth-3b Slice 1, AC#3).
	Frontend-owned browser surface. Consumes /mfa/step-up/+page.server.ts via the `data`
	(PageData) + `form` (ActionData) interface; authors NO server logic.

	CONTRACT (Backend, authoritative — see +page.server.ts):
	  data (discriminated):
	    { mode:'ready',       redirectTo } → render the code form.
	    { mode:'unavailable', redirectTo } → AAL indeterminate: a DEAD-END. Explain, link to
	                                         /settings/security + a sign-out affordance. Do
	                                         NOT auto-navigate (the fail-closed guard would
	                                         loop). The server 303s away for already-aal2 /
	                                         no-factor, so those never reach this page.
	  action (default) — fields code (6-digit) + redirectTo (hidden, round-trip).
	    success → 303 to the target. fail → { errors:{ code | _form } }.

	Plain <form method="POST"> — progressive-enhancement + CSP-safe, mirroring /login. The
	server-side .strict() schema is the security boundary; the browser gets fast feedback
	from the field primitive's native validation + the client Zod mirror shape-of-record.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);
</script>

<svelte:head>
	<title>Verify it's you · mosko-fintech</title>
</svelte:head>

<main class="auth">
	<section class="card" aria-labelledby="auth-title">
		{#if data.mode === 'ready'}
			<h1 id="auth-title" class="title">Verify it's you</h1>
			<p class="lead">Enter the 6-digit code from your authenticator app to continue.</p>

			{#if errors._form}
				<p class="banner" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<form method="POST" class="form">
				<!-- Round-trip the guarded target (same-site fence lives server-side). -->
				<input type="hidden" name="redirectTo" value={data.redirectTo} />
				<TextField
					label="6-digit code"
					name="code"
					type="text"
					inputmode="numeric"
					autocomplete="one-time-code"
					maxlength={6}
					pattern={'\\d{6}'}
					required
					numeric
					errors={errors.code ?? []}
				/>
				<Button variant="primary" type="submit">Verify</Button>
			</form>
		{:else}
			<!-- mode === 'unavailable': indeterminate AAL. Actionable dead-end, no auto-nav. -->
			<h1 id="auth-title" class="title">Verification unavailable</h1>
			<p class="lead">
				We can't verify your second factor right now. Please try again shortly. If this keeps
				happening, sign out and sign back in, or review your security settings.
			</p>
			<div class="actions">
				<a class="cta" href="/settings/security">Security settings</a>
				<form method="POST" action="/auth/signout">
					<Button type="submit">Sign out</Button>
				</form>
			</div>
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
	.actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--space-2);
	}
	/* Anchor styled to the locked `.btn` visual language (Button renders a <button>, so a
	   nav link styles the anchor directly — tokens only). */
	.cta {
		display: inline-flex;
		align-items: center;
		border: 1px solid var(--c-border-strong);
		background: var(--c-surface);
		color: var(--c-text-primary);
		border-radius: var(--radius-md);
		padding: var(--space-2) var(--space-3);
		font: var(--weight-med) var(--fs-small) / 1 var(--font-ui);
		text-decoration: none;
	}
	.cta:hover {
		background: var(--c-surface-alt);
	}
	.cta:active {
		background: var(--c-surface-alt2);
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
