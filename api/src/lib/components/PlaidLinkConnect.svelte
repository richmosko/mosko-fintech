<!--
	PlaidLinkConnect.svelte — SELF-198 §2.4.1 institution-connect widget (Plaid path).
	Transport-agnostic browser leg: identical whether the app→worker handoff is Option C
	or fallback B. Renders the "Connect institution" button and drives the client-side
	state machine across the two relay legs (SELF-197) + the Plaid Link modal.

	FLOW (PRD §2.4.1): click → leg-1 fetch link_token → Plaid.create({token}).open() →
	user authenticates at the institution + selects accounts → onSuccess(public_token) →
	leg-2 POST public_token → on 200 route to the account-mapping/attribute-capture flow.

	This is a genuinely CLIENT-INITIATED op (the Plaid SDK + onSuccess callback are
	client-side), so it uses fetch (via plaidLinkFlow) — NOT a SvelteKit form action.
	That is the sanctioned exception to the forms-through-actions rule (api/CLAUDE.md).

	SECURITY (AC #5): the only Plaid tokens this component touches are `link_token`
	(held transiently, never rendered) and `public_token` (passed straight to leg-2).
	No `access_token`, no Plaid secret — those live behind the relay/worker only.

	Tokens-only styling (var(--c-*)); attention hue is reserved (staleness/re-auth) so it
	is NOT used here. Accessible: labelled button, aria-live status, role="alert" error.
-->
<script lang="ts">
	import { goto } from '$app/navigation';
	import Button from '$lib/components/Button.svelte';
	import {
		fetchLinkToken as defaultFetchLinkToken,
		exchangePublicToken as defaultExchange,
		PlaidRelayError,
		type PlaidRelayLeg
	} from '$lib/plaid/plaidLinkFlow';
	import {
		createPlaidHandler as defaultCreateHandler,
		type PlaidHandler,
		type PlaidLinkError,
		type PlaidCreateConfig
	} from '$lib/plaid/loadPlaidLink';
	import type { ConnectResult } from '$lib/accounts/account-ref';

	type Status = 'idle' | 'initializing' | 'linking' | 'exchanging' | 'error';

	let {
		// Destination for the account-mapping / attribute-capture flow (PRD §2.4.1
		// "per-account attributes after share selection"). NOTE: that route is a later
		// SELF-# — path is a prop so the host wires the real target when it lands.
		mappingPath = '/accounts/connect/attributes',
		/** Optional override: called with the connect result instead of navigating. The host
		 *  (the connect page) uses this to carry the refs + linked_source_id to the attributes
		 *  route per the client-carries-refs seam (SELF-199 seam (b)). */
		onConnected,
		// Injectable seams (defaults are the real relay/SDK fns) — kept for unit-testing
		// the widget against a mocked relay without touching the network or the CDN.
		fetchLinkTokenFn = defaultFetchLinkToken,
		exchangeFn = defaultExchange,
		createHandlerFn = defaultCreateHandler
	}: {
		mappingPath?: string;
		onConnected?: (result: ConnectResult) => void;
		fetchLinkTokenFn?: typeof defaultFetchLinkToken;
		exchangeFn?: typeof defaultExchange;
		createHandlerFn?: typeof defaultCreateHandler;
	} = $props();

	let status = $state<Status>('idle');
	let errorMessage = $state('');
	let failedLeg = $state<PlaidRelayLeg | 'sdk' | null>(null);
	// Stashed so an exchange-leg failure can retry WITHOUT re-opening Plaid (AC #4).
	let pendingPublicToken: string | null = null;
	let handler: PlaidHandler | null = null;

	const busy = $derived(status === 'initializing' || status === 'exchanging');

	function friendlyMessage(leg: PlaidRelayLeg | 'sdk'): string {
		switch (leg) {
			case 'link-token':
				return "We couldn't start the secure connection. Please try again.";
			case 'sdk':
				return "The secure connection window couldn't open. Please try again.";
			case 'exchange':
				return "We couldn't finish connecting your institution. Please try again.";
		}
	}

	function toError(leg: PlaidRelayLeg | 'sdk') {
		failedLeg = leg;
		errorMessage = friendlyMessage(leg);
		status = 'error';
	}

	function cleanup() {
		handler?.destroy();
		handler = null;
	}

	async function runExchange(publicToken: string, metadata: unknown) {
		pendingPublicToken = publicToken;
		status = 'exchanging';
		try {
			const { accounts, linked_source_id } = await exchangeFn(publicToken, metadata);
			pendingPublicToken = null;
			cleanup();
			status = 'idle';
			// Carry the provider-blind result to the host (connect page). linked_source_id is
			// the pfin.linked_source row the relay created (ADR-037 substrate); null-coalesced
			// until Backend confirms the relay always returns it — the attributes route
			// fail-closes when it is absent.
			if (onConnected) onConnected({ accounts, linkedSourceId: linked_source_id ?? null });
			else await goto(mappingPath);
		} catch (e) {
			const leg = e instanceof PlaidRelayError ? e.leg : 'exchange';
			toError(leg);
		}
	}

	async function begin() {
		errorMessage = '';
		failedLeg = null;
		status = 'initializing';
		let token: string;
		try {
			({ link_token: token } = await fetchLinkTokenFn());
		} catch (e) {
			const leg = e instanceof PlaidRelayError ? e.leg : 'link-token';
			toError(leg);
			return;
		}

		const config: PlaidCreateConfig = {
			token,
			onSuccess: (publicToken, metadata) => {
				void runExchange(publicToken, metadata);
			},
			onExit: (err: PlaidLinkError | null) => {
				// User cancelled (no err) → clean return to entry state (AC #4).
				// A real Plaid error → surface a retry against the link-token leg.
				cleanup();
				if (err) toError('sdk');
				else status = 'idle';
			}
		};

		try {
			handler = await createHandlerFn(config);
			status = 'linking';
			handler.open();
		} catch {
			cleanup();
			toError('sdk');
		}
	}

	// Retry affordance (AC #4 / ARCH §7.1 retry posture): resume from the failed leg.
	// exchange-leg failure retries the stashed public_token (no re-auth); everything
	// else restarts from leg-1.
	function retry() {
		if (failedLeg === 'exchange' && pendingPublicToken) {
			void runExchange(pendingPublicToken, undefined);
		} else {
			void begin();
		}
	}
</script>

<div class="connect">
	{#if status === 'error'}
		<p class="connect-error" role="alert">{errorMessage}</p>
		<div class="connect-actions">
			<Button variant="primary" onclick={retry}>Try again</Button>
		</div>
	{:else}
		<Button
			variant="primary"
			onclick={begin}
			loading={busy}
			disabled={status === 'linking'}
			aria-describedby="connect-status"
		>
			Connect institution
		</Button>
	{/if}

	<!-- Non-visual live region: announces flow transitions to assistive tech. -->
	<p id="connect-status" class="connect-status" aria-live="polite">
		{#if status === 'initializing'}Starting a secure connection…
		{:else if status === 'linking'}Complete the steps in the secure window.
		{:else if status === 'exchanging'}Finishing up…
		{/if}
	</p>
</div>

<style>
	.connect {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
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
	/* Visually hide the status line when empty is fine, but keep it in the a11y tree. */
	.connect-status:empty {
		min-height: 0;
	}
</style>
