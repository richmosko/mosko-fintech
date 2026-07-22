<!--
	settings/security/+page.svelte — MFA (TOTP) security hub (SELF-291 / Auth-3b Slice 1,
	AC#2 enrollment UI). Frontend-owned browser surface. Consumes
	/settings/security/+page.server.ts via the `data` (PageData) + `form` (ActionData)
	interface; authors NO server logic.

	CONTRACT (Backend, authoritative — see +page.server.ts):
	  data.status : MfaStatus — render off `hasVerifiedTotp` (the REAL, AAL-derived state;
	                mfaPolicy is display-only and deliberately NOT gated on here).
	  data.recovery : { unused: number } — live unused backup-code count (0 when MFA off).
	  action ?/enrollStart  → { action:'enrollStart', enroll:{ factorId, qrCode, secret, uri } }
	                          | { action:'enrollStart', errors:{ _form } }
	  action ?/enrollVerify → { action:'enrollVerify', enrolled:true, recoveryCodes:string[],
	                            recoveryCodesError:boolean }  (SUCCESS — no longer redirects,
	                            so it can carry the display-once plaintext codes)
	                          | { action:'enrollVerify', factorId, errors:{ code | _form } }
	  action ?/disable      → 303 /settings/security on success
	                          | { action:'disable', errors:{ _form } }
	  action ?/regenerateRecoveryCodes → { action:'regenerateRecoveryCodes', recoveryCodes }
	                          | { action:'regenerateRecoveryCodes', errors:{ _form } }  (403
	                            when the session isn't aal2 → prompt step-up)

	Slice 2b — DISPLAY-ONCE recovery codes: `recoveryCodes` arrives ONLY on an action return
	(enrollVerify / regenerate success). We render it through RecoveryCodesPanel, which shows
	it exactly once and never persists it. On reload the action data is gone and the codes
	cannot reappear. INV-1 plain text; no value-color / attention hue on the codes.

	Plain <form method="POST"> per action — progressive-enhancement + CSP-safe, mirroring
	/login + /signup (no use:enhance, no inline handlers). The server-side .strict() schema
	is the security boundary; the browser gets fast feedback from the field primitive's
	native validation (inputmode/maxlength/pattern) + the client Zod mirror shape-of-record.

	QR: `enroll.qrCode` is a raw server-generated SVG string from Supabase/GoTrue (not a
	URL). Rendered via {@html} inside an accessible role="img" wrapper — the source is
	trusted (GoTrue) and script-free, so this needs no CSP `img-src data:` allowance nor a
	client-side data-URI construction. The `secret`/`uri` manual-entry fallback is always
	shown alongside for authenticator apps that can't scan.

	Tokens only (var(--c-*)); no hardcoded hex/px/font (ADR-013 P5).
-->
<script lang="ts">
	import { page } from '$app/state';
	import TextField from '$lib/components/TextField.svelte';
	import Button from '$lib/components/Button.svelte';
	import RecoveryCodesPanel from '$lib/components/RecoveryCodesPanel.svelte';
	import type { PageData, ActionData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	const status = $derived(data.status);
	const recovery = $derived(data.recovery);
	// Backend's fail() branches are all string-keyed `{ field: string[] }` maps at runtime.
	const errors = $derived((form?.errors ?? {}) as Record<string, string[]>);

	// enrollStart success surfaces the full enrollment material (QR + secret + uri +
	// factorId). A bad verify code echoes ONLY factorId (no QR) — so the verify panel must
	// survive on factorId alone (`'enroll' in form` / `'factorId' in form` narrow the union).
	const enroll = $derived(form && 'enroll' in form ? form.enroll : undefined);
	const verifyFactorId = $derived(
		enroll?.factorId ?? (form && 'factorId' in form ? form.factorId : undefined)
	);
	const showVerify = $derived(Boolean(verifyFactorId));

	// ── Slice 2b: display-once recovery codes + count ──────────────────────────
	// Codes are present ONLY as action-return data (enrollVerify / regenerate success). We
	// read them straight from `form` — never into a persistent store (display-once).
	const recoveryCodes = $derived(
		form && 'recoveryCodes' in form && Array.isArray(form.recoveryCodes) && form.recoveryCodes.length > 0
			? form.recoveryCodes
			: undefined
	);
	// enrollment succeeded but the code batch couldn't be issued → prompt regenerate.
	const recoveryCodesError = $derived(
		form?.action === 'enrollVerify' && 'recoveryCodesError' in form
			? Boolean(form.recoveryCodesError)
			: false
	);
	// A fresh regenerate batch supersedes the old — warn the user their old codes died.
	const regenerated = $derived(
		form?.action === 'regenerateRecoveryCodes' && recoveryCodes !== undefined
	);
	// Regenerate refused (server-side aal2 gate, 403) → nudge to step up first.
	const regenerateNeedsStepUp = $derived(
		form?.action === 'regenerateRecoveryCodes' && Boolean(errors._form)
	);
	// Low unused-code balance → a gentle regenerate nudge (only meaningful when MFA is on).
	const lowRecovery = $derived(status.hasVerifiedTotp && recovery.unused <= 2);

	// The /mfa/recover flow lands here as ?recovered=1 — MFA is now off; prompt re-enroll.
	const justRecovered = $derived(page.url.searchParams.get('recovered') === '1');
</script>

<svelte:head>
	<title>Security · mosko-fintech</title>
</svelte:head>

<main class="settings">
	<header class="head">
		<h1 class="title">Security</h1>
		<p class="lead">Protect your account with two-factor authentication.</p>
	</header>

	{#if justRecovered}
		<!-- Landed from /mfa/recover: the dead factor is gone + MFA is off. Neutral notice
		     (NOT the attention hue — reserved for staleness/re-auth), prompting re-enrollment. -->
		<p class="notice" role="status">
			You're signed in with a backup code. Two-factor authentication has been turned off — set
			up a fresh authenticator below to protect your account again.
		</p>
	{/if}

	{#if recoveryCodes}
		<!-- DISPLAY-ONCE: rendered straight from the action return, shown exactly once. -->
		<section class="card" aria-label="Backup codes">
			{#if regenerated}
				<p class="notice" role="status">
					These new codes replace your previous backup codes — the old ones no longer work.
				</p>
			{/if}
			<RecoveryCodesPanel codes={recoveryCodes} />
		</section>
	{/if}

	<section class="card" aria-labelledby="mfa-title">
		{#if status.hasVerifiedTotp}
			<!-- ── MFA ON: verified factor exists (AAL truth) → offer disable ─────────── -->
			<h2 id="mfa-title" class="card-title">Two-factor authentication is on</h2>
			<p class="body">
				You'll be asked for a code from your authenticator app when you sign in.
			</p>

			<!-- Recovery-code balance + regenerate (aal2-gated server-side). -->
			<div class="recovery">
				<p class="body">
					<span class="count">{recovery.unused} of 10</span> backup codes remaining.
				</p>
				{#if recoveryCodesError}
					<p class="notice" role="status">
						Two-factor authentication is on, but your backup codes couldn't be issued.
						Regenerate a fresh set below.
					</p>
				{:else if lowRecovery}
					<p class="notice" role="status">
						You're running low on backup codes. Regenerate a fresh set so you always have a way
						back in.
					</p>
				{/if}
				{#if regenerateNeedsStepUp}
					<p class="banner" role="alert">
						{errors._form.join(' ')} <a href="/mfa/step-up">Verify it's you</a> and try again.
					</p>
				{/if}
				<form method="POST" action="?/regenerateRecoveryCodes" class="row">
					<Button type="submit">Regenerate backup codes</Button>
				</form>
			</div>

			{#if form?.action === 'disable' && errors._form}
				<p class="banner" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<form method="POST" action="?/disable" class="row">
				<Button type="submit">Disable two-factor authentication</Button>
			</form>
		{:else if showVerify}
			<!-- ── ENROLL step 2: verify the code (survives a bad-code retry) ─────────── -->
			<h2 id="mfa-title" class="card-title">Verify your authenticator</h2>

			{#if enroll}
				<p class="body">
					Scan this QR code with your authenticator app (or enter the key manually), then
					enter the 6-digit code it shows.
				</p>
				<div class="qr" role="img" aria-label="Two-factor setup QR code — scan with your authenticator app">
					<!-- eslint-disable-next-line svelte/no-at-html-tags -- trusted GoTrue SVG (see file header) -->
					{@html enroll.qrCode}
				</div>
				<dl class="manual">
					<dt>Setup key</dt>
					<dd class="mono">{enroll.secret}</dd>
				</dl>
			{:else}
				<p class="body">Enter the 6-digit code from your authenticator app to finish.</p>
			{/if}

			{#if errors._form}
				<p class="banner" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<form method="POST" action="?/enrollVerify" class="form">
				<input type="hidden" name="factorId" value={verifyFactorId} />
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
				<Button variant="primary" type="submit">Verify and turn on</Button>
			</form>
		{:else}
			<!-- ── MFA OFF: no verified factor → offer enrollment ─────────────────────── -->
			<h2 id="mfa-title" class="card-title">Two-factor authentication is off</h2>
			<p class="body">
				Add a time-based one-time code (TOTP) from an authenticator app as a second step
				when you sign in.
			</p>

			{#if form?.action === 'enrollStart' && errors._form}
				<p class="banner" role="alert">{errors._form.join(' ')}</p>
			{/if}

			<form method="POST" action="?/enrollStart" class="row">
				<Button variant="primary" type="submit">Enable two-factor authentication</Button>
			</form>
		{/if}
	</section>
</main>

<style>
	.settings {
		max-width: 40rem;
		margin: 0 auto;
		padding: var(--space-7) var(--space-5);
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
	}
	.head {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.title {
		margin: 0;
		font: var(--weight-bold) var(--fs-h1) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.lead {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.card {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
		background: var(--c-surface);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-1);
		padding: var(--space-6);
		box-sizing: border-box;
	}
	.card-title {
		margin: 0;
		font: var(--weight-semi) var(--fs-h3) / var(--lh-tight) var(--font-ui);
		color: var(--c-text-primary);
	}
	.body {
		margin: 0;
		font: var(--weight-reg) var(--fs-body) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}
	.row {
		display: flex;
	}
	.recovery {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding-top: var(--space-4);
		border-top: 1px solid var(--c-border);
	}
	.count {
		font-family: var(--font-num);
		font-weight: var(--weight-semi);
		color: var(--c-text-primary);
	}
	/* Neutral notice — NOT the attention hue (reserved for staleness/re-auth per the
	   design-system fence). Informational nudges, not alerts. */
	.notice {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		font: var(--weight-reg) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	/* QR wrapper: constrain the inline SVG to a sane render box on a light chip so it
	   scans on any theme (GoTrue SVGs are black-on-transparent). */
	.qr {
		align-self: flex-start;
		padding: var(--space-3);
		background: var(--c-surface-alt);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		width: 12rem;
		height: 12rem;
		box-sizing: content-box;
	}
	.qr :global(svg) {
		display: block;
		width: 100%;
		height: 100%;
	}
	.manual {
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	.manual dt {
		font: var(--weight-semi) var(--fs-small) / var(--lh-body) var(--font-ui);
		color: var(--c-text-secondary);
	}
	.manual dd {
		margin: 0;
	}
	.mono {
		font-family: var(--font-num);
		font-size: var(--fs-small);
		color: var(--c-text-primary);
		word-break: break-all;
		user-select: all;
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
