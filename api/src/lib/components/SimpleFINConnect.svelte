<!--
	SimpleFINConnect.svelte — OQ-2 §2.4.1 institution-connect widget (SimpleFIN path).
	Sibling to PlaidLinkConnect.svelte under the RF-1 Option A provider-picker seam. Where
	Plaid is an async SDK modal (2 legs: mint link_token → exchange), SimpleFIN is a single
	synchronous paste-and-submit (1 leg): the user obtains a one-time setup token from the
	SimpleFIN Bridge out-of-band, pastes it here, and we relay it once to the claim leg.

	FLOW (temp/oq2-connect-seam-design.md §2/§3): paste setup token (+ optional label) →
	POST /api/simplefin/connect → on 200 route to the SAME shared account-attributes flow
	the Plaid path uses (mappingPath), handing off the same AccountRef[]. SimpleFIN refs
	carry type='unknown', so the attributes flow simply starts each account's type
	unselected rather than pre-filled — a UX nicety, not a gap.

	This is a genuinely CLIENT-INITIATED op (no server-known data at render time), so it
	uses fetch via submitSetupToken — the sanctioned exception to the forms-through-actions
	rule (api/CLAUDE.md). It is NOT a <form method="POST"> action because there is no
	+page.server.ts here (the connect page is a pure browser surface).

	CREDENTIAL HYGIENE (OQ-2 §4 — the setup token is an SD-03-class bearer credential):
	  • posted ONCE over the session-authed relay body (never a URL query);
	  • never rendered back, never console.log'd, never persisted (no localStorage);
	  • the field value is captured to a local const and CLEARED from component state the
	    instant we submit — it is held no longer than the single post needs it.
	  • autocomplete / autocorrect / autocapitalize / spellcheck are all OFF so the token
	    never lands in a browser autofill store or a spellcheck dictionary.
	No SimpleFIN Access URL, no service_role key, no private env is ever touched here — those
	live exclusively behind the relay/worker.

	Tokens-only styling (var(--c-*)). NOTE the design-system fence: the attention hue
	(--c-attn-*, canary) is RESERVED for staleness / re-auth ONLY — so the RF-3 revoke
	advisory below uses NEUTRAL surface tokens, not the attention hue. Accessible: labelled
	textarea, aria-live status, role="alert" error, keyboard-native controls.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import TextField from '$lib/components/TextField.svelte';
	import {
		submitSetupToken as defaultSubmit,
		SimplefinRelayError,
		type SimplefinFailureKind,
		type FetchLike
	} from '$lib/simplefin/simplefinConnectFlow';
	import type { AccountRef } from '$lib/simplefin/contract';
	import type { ConnectResult } from '$lib/accounts/account-ref';

	type Status = 'idle' | 'submitting' | 'error';

	let {
		// Destination for the shared account-mapping / attribute-capture flow — the SAME
		// route the Plaid path uses (OQ-2 §3c: account-mapping reuses the shipped attributes
		// slice; no new leg). Path is a prop so the host wires the real target.
		mappingPath = '/accounts/connect/attributes',
		/** Optional override: called with the connect result instead of navigating. The host
		 *  (the connect page) uses this to carry the refs + linked_source_id to the attributes
		 *  route per the client-carries-refs seam (SELF-199 seam (b)). */
		onConnected,
		// Injectable seam (default is the real relay fn) — lets a unit test drive the widget
		// against a mocked relay without touching the network.
		submitFn = defaultSubmit
	}: {
		mappingPath?: string;
		onConnected?: (result: ConnectResult) => void;
		submitFn?: (
			setupToken: string,
			institutionName: string | undefined,
			fetchFn?: FetchLike
		) => Promise<{ success: true; linked_source_id?: string | null; accounts: AccountRef[] }>;
	} = $props();

	// Bound to the textarea (two-way). Cleared the instant we submit (credential hygiene).
	let setupToken = $state('');
	let institutionName = $state('');

	let status = $state<Status>('idle');
	let errorMessage = $state('');
	// Client-side mirror of the server `.min(1)` check — fast UX feedback, NOT the security
	// boundary. Shown inline on the field before we ever hit the network.
	let fieldError = $state('');

	const busy = $derived(status === 'submitting');

	function failureMessage(failure: SimplefinFailureKind): string {
		switch (failure) {
			case 'invalid-token':
				return 'That setup token was invalid or has already been used. Setup tokens are one-time — get a fresh one from your SimpleFIN Bridge and paste it here.';
			case 'unauthenticated':
				return 'Your session has expired. Please sign in again, then reconnect.';
			case 'unavailable':
				return "We couldn't reach the connection service. Please paste your setup token and try again in a moment.";
		}
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;

		errorMessage = '';
		fieldError = '';

		// Client-side `.strict()`/`.min(1)` mirror (UX only): reject an empty token before
		// the network round-trip. The server re-validates — this is fast feedback, not trust.
		const token = setupToken.trim();
		if (token.length === 0) {
			fieldError = 'Paste the one-time setup token from your SimpleFIN Bridge.';
			return;
		}
		const label = institutionName.trim() || undefined;

		// Credential hygiene: capture to a local const, then CLEAR the field from component
		// state immediately — the token lives no longer than this single submit needs it.
		setupToken = '';
		status = 'submitting';

		try {
			const { accounts, linked_source_id } = await submitFn(token, label);
			status = 'idle';
			institutionName = '';
			// Carry the provider-blind result to the host (connect page). linked_source_id is
			// null-coalesced until Backend confirms the relay always returns it — the
			// attributes route fail-closes when it is absent.
			if (onConnected) onConnected({ accounts, linkedSourceId: linked_source_id ?? null });
			else await goto(mappingPath);
		} catch (e) {
			const failure = e instanceof SimplefinRelayError ? e.failure : 'unavailable';
			errorMessage = failureMessage(failure);
			status = 'error';
		}
	}
</script>

<div class="connect">
	<!--
		RF-3 revoke-at-Bridge advisory (OQ-2 §5.2 / SECURITY §4.2 C7 residual). Surfaced at
		connect time so the user understands the app's revoke is local-delete-only. NEUTRAL
		surface tokens — NOT the attention hue (reserved for staleness/re-auth per the
		design-system fence).
	-->
	<p class="advisory" role="note">
		<strong>Before you connect:</strong> SimpleFIN access is granted and revoked at the
		<a
			class="advisory-link"
			href="https://bridge.simplefin.org/"
			target="_blank"
			rel="noopener noreferrer">SimpleFIN Bridge</a
		>, not here. Disconnecting an account in mosko-fintech stops syncing and removes its
		local data, but it does <strong>not</strong> revoke the Bridge's access — to fully cut off
		access, revoke it at the SimpleFIN Bridge as well.
	</p>

	<form class="connect-form" onsubmit={submit} novalidate>
		<div class="field">
			<label for="sf-setup-token">
				SimpleFIN setup token<span class="req" aria-hidden="true">*</span>
			</label>
			<span id="sf-setup-token-hint" class="hint">
				Paste the one-time setup token from your SimpleFIN Bridge. It's used once to connect
				and is never stored in your browser.
			</span>
			<textarea
				id="sf-setup-token"
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
					? 'sf-setup-token-hint sf-setup-token-err'
					: 'sf-setup-token-hint'}
				placeholder="Paste your setup token"
			></textarea>
			{#if fieldError !== ''}
				<span id="sf-setup-token-err" class="field-error-msg" role="alert">{fieldError}</span>
			{/if}
		</div>

		<TextField
			label="Institution name (optional)"
			name="sf-institution"
			bind:value={institutionName}
			hint="A label to help you recognize this connection (e.g. “Capital One”)."
			autocomplete="off"
		/>

		{#if status === 'error'}
			<p class="connect-error" role="alert">{errorMessage}</p>
		{/if}

		<div class="connect-actions">
			<Button variant="primary" type="submit" loading={busy} aria-describedby="connect-status">
				Connect with SimpleFIN
			</Button>
		</div>
	</form>

	<!-- Non-visual live region: announces flow transitions to assistive tech. -->
	<p id="connect-status" class="connect-status" aria-live="polite">
		{#if status === 'submitting'}Connecting your accounts…{/if}
	</p>
</div>

<style>
	.connect {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.advisory {
		margin: 0;
		padding: var(--space-3);
		border: 1px solid var(--c-border);
		border-radius: var(--radius-md);
		background: var(--c-surface-alt);
		color: var(--c-text-secondary);
		font-size: var(--fs-small);
		line-height: var(--lh-body);
	}
	.advisory-link {
		color: var(--c-link);
		font-weight: var(--weight-med);
	}
	.connect-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}
	label {
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
	.connect-actions {
		display: flex;
		gap: var(--space-3);
	}
	.connect-error {
		margin: 0;
		padding: var(--space-2) var(--space-3);
		border: 1px solid var(--c-neg);
		border-radius: var(--radius-md);
		background: color-mix(in srgb, var(--c-neg) 8%, var(--c-surface));
		color: var(--c-neg);
		font-size: var(--fs-small);
	}
	.connect-status {
		margin: 0;
		min-height: var(--fs-small);
		font-size: var(--fs-small);
		color: var(--c-text-secondary);
	}
	.connect-status:empty {
		min-height: 0;
	}
</style>
