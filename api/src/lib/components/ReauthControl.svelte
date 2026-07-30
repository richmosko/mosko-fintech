<!--
	ReauthControl.svelte — SELF-207 Phase-2 per-connection re-authentication (§2.4.4.b AC #2/#4).
	Rendered on the connection-state view for any active connection whose status is re-auth-
	actionable (login_required / revoked / disconnected).

	CONNECT-FLOW-SHAPED, not a form action (ADR-037 AC #4): re-auth repairs a connection the same
	way it was made. Both providers now LIVE off the shared `/api/reauth/start` → `/api/reauth/complete`
	relay legs (provider resolved server-side; we branch the UI on the provider from the row):
	  • PLAID — start → `{ kind:'link_update', link_token }`; open Plaid Link in UPDATE mode (reuses
	    loadPlaidLink); the user repairs the login; onSuccess fires with NO public_token → complete
	    (no setup_token).
	  • SIMPLEFIN — start → `{ kind:'recollect_credential' }`; the user pastes a FRESH Bridge setup
	    token (credential rotates in place on the same source — 021 mappings preserved) → complete
	    with that token → `{ rotated:true }`.
	On success we `invalidateAll()` so the row + layout banner refresh to healthy.

	CREDENTIAL HYGIENE (SimpleFIN, mirrors SimpleFINConnect — the setup token is SD-03-class):
	posted ONCE over the session-authed relay body (never a URL query), never rendered back, never
	logged/persisted; the field is CLEARED from component state the instant we submit; autocomplete /
	autocapitalize / autocorrect / spellcheck are OFF. The only Plaid credential the browser holds is
	the short-TTL update-mode `link_token` (transient, never rendered). No access_token / Access URL.

	a11y: labelled button, labelled paste field, aria-live status, role="alert" errors, keyboard-
	native. Tokens ONLY (var(--c-*)); the paste field uses NEUTRAL tokens (not the attention hue).
-->
<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import {
		startReauth as defaultStart,
		completeReauth as defaultComplete,
		ReauthError,
		type ReauthFailureKind,
		type ReauthLeg
	} from '$lib/accounts/reauthFlow';
	import {
		createPlaidHandler as defaultCreateHandler,
		type PlaidHandler,
		type PlaidCreateConfig,
		type PlaidLinkError
	} from '$lib/plaid/loadPlaidLink';

	let {
		source_id,
		provider,
		institution_name = null,
		// Called after a successful complete → refresh all loaders (banner + row flip to healthy).
		onReauthed = invalidateAll,
		// Injectable relay/SDK seams (defaults are the real fns) — unit-test without network/CDN.
		startFn = defaultStart,
		completeFn = defaultComplete,
		createHandlerFn = defaultCreateHandler
	}: {
		source_id: string;
		provider: string;
		institution_name?: string | null;
		onReauthed?: () => void | Promise<void>;
		startFn?: typeof defaultStart;
		completeFn?: typeof defaultComplete;
		createHandlerFn?: typeof defaultCreateHandler;
	} = $props();

	// 'completing' = Plaid complete in flight; 'recollecting' = SimpleFIN token submit in flight
	// (kept distinct so the paste form stays mounted with a loading button during submit).
	type Status =
		| 'idle'
		| 'starting'
		| 'linking'
		| 'recollect'
		| 'recollecting'
		| 'completing'
		| 'error';
	let status = $state<Status>('idle');
	let errorMessage = $state('');
	let handler: PlaidHandler | null = null;

	// SimpleFIN re-collect field (bound; cleared the instant we submit — credential hygiene).
	let setupToken = $state('');
	let fieldError = $state('');

	const busy = $derived(
		status === 'starting' || status === 'completing' || status === 'recollecting'
	);
	const label = $derived(
		institution_name ? `Re-authenticate ${institution_name}` : 'Re-authenticate'
	);

	function cleanup() {
		handler?.destroy();
		handler = null;
	}

	function friendly(leg: ReauthLeg, failure: ReauthFailureKind): string {
		switch (failure) {
			case 'unauthenticated':
				return 'Your session has expired. Please sign in again, then try re-authenticating.';
			case 'not_found':
				return "We couldn't find this connection. Please refresh the page and try again.";
			case 'invalid_request':
				return "We couldn't start re-authentication. Please try again.";
			default:
				return leg === 'complete'
					? "We couldn't finish re-authenticating this connection. Please try again."
					: "We couldn't reach the re-authentication service. Please try again.";
		}
	}

	function fail(message: string) {
		errorMessage = message;
		status = 'error';
	}

	/** Plaid completion — update-mode success carries no public_token, so no setup_token. */
	async function completePlaid() {
		status = 'completing';
		try {
			await completeFn(source_id);
			cleanup();
			status = 'idle';
			await onReauthed();
		} catch (e) {
			cleanup();
			if (e instanceof ReauthError) fail(friendly(e.leg, e.failure));
			else fail(friendly('complete', 'reauth_failed'));
		}
	}

	async function begin() {
		errorMessage = '';
		fieldError = '';
		status = 'starting';

		let handoff: Awaited<ReturnType<typeof defaultStart>>;
		try {
			handoff = await startFn(source_id);
		} catch (e) {
			if (e instanceof ReauthError) fail(friendly(e.leg, e.failure));
			else fail(friendly('start', 'network'));
			return;
		}

		if (handoff.kind === 'link_update') {
			// Plaid update mode — open Link with the update-mode token; success carries no
			// public_token, so onSuccess just proceeds to complete.
			const config: PlaidCreateConfig = {
				token: handoff.link_token,
				onSuccess: () => {
					void completePlaid();
				},
				onExit: (err: PlaidLinkError | null) => {
					cleanup();
					if (err) fail('The secure window closed before finishing. Please try again.');
					else status = 'idle';
				}
			};
			try {
				handler = await createHandlerFn(config);
				status = 'linking';
				handler.open();
			} catch {
				cleanup();
				fail("The secure window couldn't open. Please try again.");
			}
		} else {
			// SimpleFIN — reveal the fresh-setup-token paste field.
			status = 'recollect';
		}
	}

	/** SimpleFIN completion — submit the freshly-pasted setup token. */
	async function submitRecollect(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;

		fieldError = '';
		const token = setupToken.trim();
		if (token.length === 0) {
			fieldError = 'Paste the one-time setup token from your SimpleFIN Bridge.';
			return;
		}
		// Credential hygiene: capture to a const, then CLEAR the field immediately.
		setupToken = '';
		status = 'recollecting';
		try {
			await completeFn(source_id, token);
			status = 'idle';
			await onReauthed();
		} catch (e) {
			if (e instanceof ReauthError && e.failure === 'invalid_request') {
				// Burned / invalid / already-used token → stay on the field for a fresh paste.
				status = 'recollect';
				fieldError =
					'That setup token was invalid or already used. Get a fresh one from your SimpleFIN Bridge and paste it here.';
			} else if (e instanceof ReauthError) {
				fail(friendly(e.leg, e.failure));
			} else {
				fail(friendly('complete', 'reauth_failed'));
			}
		}
	}
</script>

<div class="reauth">
	{#if status === 'error'}
		<p class="reauth-error" role="alert">{errorMessage}</p>
		<Button variant="primary" onclick={begin}>Try again</Button>
	{:else if status === 'recollect' || status === 'recollecting'}
		<form class="recollect" onsubmit={submitRecollect} novalidate>
			<label for="reauth-token-{source_id}">
				Paste a fresh SimpleFIN setup token<span class="req" aria-hidden="true">*</span>
			</label>
			<span id="reauth-token-hint-{source_id}" class="hint">
				Get a new one-time setup token from your SimpleFIN Bridge and paste it to reconnect. It's
				used once and never stored in your browser.
			</span>
			<textarea
				id="reauth-token-{source_id}"
				class="token-input"
				class:is-error={fieldError !== ''}
				bind:value={setupToken}
				rows="3"
				required
				autocomplete="off"
				autocapitalize="off"
				spellcheck={false}
				{...{ autocorrect: 'off' }}
				aria-required="true"
				aria-invalid={fieldError !== ''}
				aria-describedby={fieldError !== ''
					? `reauth-token-hint-${source_id} reauth-token-err-${source_id}`
					: `reauth-token-hint-${source_id}`}
				placeholder="Paste your setup token"
			></textarea>
			{#if fieldError !== ''}
				<span id="reauth-token-err-{source_id}" class="field-error-msg" role="alert">{fieldError}</span>
			{/if}
			<div class="recollect-actions">
				<Button variant="primary" type="submit" loading={status === 'recollecting'}>Reconnect</Button>
			</div>
		</form>
	{:else}
		<Button variant="primary" onclick={begin} loading={busy} disabled={status === 'linking'}>
			{label}
		</Button>
	{/if}

	<p class="reauth-status" aria-live="polite">
		{#if status === 'starting'}Starting secure re-authentication…
		{:else if status === 'linking'}Complete the steps in the secure window.
		{:else if status === 'completing' || status === 'recollecting'}Finishing up…
		{/if}
	</p>
</div>

<style>
	.reauth {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		align-items: flex-start;
	}
	.reauth-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.reauth-status {
		margin: 0;
		min-height: var(--fs-small);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.reauth-status:empty {
		min-height: 0;
	}
	.recollect {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		width: 100%;
		max-width: 28rem;
	}
	.recollect label {
		font-size: var(--fs-small);
		font-weight: var(--weight-semi);
		color: var(--c-text-secondary);
	}
	.req {
		color: var(--c-neg);
		margin-left: 2px;
	}
	.hint {
		font-size: var(--fs-small);
		color: var(--c-text-muted);
	}
	.token-input {
		width: 100%;
		box-sizing: border-box;
		resize: vertical;
		border: 1px solid var(--c-border-strong);
		border-radius: var(--radius-md);
		background: var(--c-surface);
		color: var(--c-text-primary);
		padding: var(--space-2) var(--space-3);
		font: var(--fs-body) / 1.4 var(--font-num);
	}
	.token-input:hover {
		border-color: var(--c-text-muted);
	}
	.token-input:focus {
		border-color: var(--c-accent);
		box-shadow: 0 0 0 3px var(--c-accent-soft);
		outline: none;
	}
	.token-input.is-error {
		border-color: var(--c-neg);
		box-shadow: 0 0 0 3px color-mix(in srgb, var(--c-neg) 18%, transparent);
	}
	.field-error-msg {
		display: block;
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.recollect-actions {
		margin-top: var(--space-2);
	}
</style>
