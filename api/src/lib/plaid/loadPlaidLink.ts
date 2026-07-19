// loadPlaidLink.ts — client-side loader + typed wrapper for the Plaid Link Web SDK.
//
// ⚠️ VENDORING FLAG (open question for Architect / DevOps / Security — see the SELF-198
//    deliverable note): Plaid MANDATES loading Link from `cdn.plaid.com`; self-hosting the
//    initialize script is unsupported and ToS-restricted (unlike the vendored Mermaid
//    runtime). This is an explicit exception to the project no-CDN convention and needs:
//      • a CSP `script-src https://cdn.plaid.com` + `connect-src`/`frame-src` allowlist
//        entry (Plaid Link opens an iframe to the institution), and
//      • sign-off recorded as an ADR amendment before this ships.
//    Until then this loader is inert in tests (the flow module is DOM-free and testable
//    without it) and the script only injects on first real `open()`.
//
// Ships to the browser (non-`server`). No Plaid secret / access_token here by design —
// only the short-TTL `link_token` is passed to `Plaid.create({ token })`.

const PLAID_LINK_SRC = 'https://cdn.plaid.com/link/v2/stable/link-initialize.js';

// ── Minimal typings for the subset of the Plaid Link global we use ───────────────────
export interface PlaidHandler {
	open(): void;
	exit(opts?: { force?: boolean }): void;
	destroy(): void;
}

/** Plaid onExit error object (non-secret). We only read code/message for display. */
export interface PlaidLinkError {
	error_type?: string;
	error_code?: string;
	display_message?: string | null;
}

export interface PlaidCreateConfig {
	/** The leg-1 `link_token` — the ONLY credential the browser passes to the SDK. */
	token: string;
	onSuccess: (publicToken: string, metadata: unknown) => void;
	onExit: (err: PlaidLinkError | null, metadata: unknown) => void;
	onEvent?: (eventName: string, metadata: unknown) => void;
}

interface PlaidGlobal {
	create(config: PlaidCreateConfig): PlaidHandler;
}

declare global {
	interface Window {
		Plaid?: PlaidGlobal;
	}
}

let scriptPromise: Promise<PlaidGlobal> | null = null;

/**
 * Idempotently inject the Plaid Link script and resolve the `Plaid` global. Rejects if
 * the script fails to load (offline / CSP block) — the caller surfaces a retry (AC #4).
 */
export function loadPlaidScript(): Promise<PlaidGlobal> {
	if (typeof window === 'undefined') {
		return Promise.reject(new Error('Plaid Link is browser-only.'));
	}
	if (window.Plaid) return Promise.resolve(window.Plaid);
	if (scriptPromise) return scriptPromise;

	scriptPromise = new Promise<PlaidGlobal>((resolve, reject) => {
		const existing = document.querySelector<HTMLScriptElement>(`script[src="${PLAID_LINK_SRC}"]`);
		const el = existing ?? document.createElement('script');
		const onLoad = () => {
			if (window.Plaid) resolve(window.Plaid);
			else reject(new Error('Plaid Link loaded but window.Plaid is undefined.'));
		};
		const onError = () => {
			scriptPromise = null; // allow a later retry
			reject(new Error('Failed to load Plaid Link script.'));
		};
		el.addEventListener('load', onLoad, { once: true });
		el.addEventListener('error', onError, { once: true });
		if (!existing) {
			el.src = PLAID_LINK_SRC;
			el.async = true;
			document.head.appendChild(el);
		} else if (window.Plaid) {
			onLoad();
		}
	});
	return scriptPromise;
}

/**
 * Load the SDK and build a Plaid handler for a given link_token. The handler's `open()`
 * shows the Plaid modal; `onSuccess`/`onExit` are the flow's continuation points.
 */
export async function createPlaidHandler(config: PlaidCreateConfig): Promise<PlaidHandler> {
	const Plaid = await loadPlaidScript();
	return Plaid.create(config);
}
