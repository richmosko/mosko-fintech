// connect-handoff.svelte.ts — the CLIENT-SIDE carry for the connect → attributes handoff
// (SELF-199 seam (b): "client-carries-refs"; team-lead-ratified, fail-closed).
//
// WHY THIS EXISTS: the automated-aggregator connect step (Plaid / SimpleFIN) produces an
// `AccountRef[]` + a `linked_source_id` that the attributes-capture route needs, but that
// data is NOT server-known at the attributes route's render time (it originates from a
// client-initiated relay call on the previous screen). Seam (b) carries it IN MEMORY on the
// client instead of a server-side transient store — there is deliberately NO server round
// trip that stashes it. `goto()` cannot carry structured payloads, so this tiny module-level
// rune store is the carrier: the connect page writes it and navigates; the attributes route
// consumes it on entry.
//
// FAIL-CLOSED (the ratified rationale): the carry is single-use and in-memory only. A direct
// navigation to /accounts/connect/attributes, a browser reload, or a back-then-forward all
// find an empty store — the attributes route then shows its "start a connection" empty state
// and routes back to /accounts/connect. Nothing is persisted (no localStorage / sessionStorage):
// the refs are non-secret, but there is no reason to widen their lifetime beyond the single
// navigation, and keeping them ephemeral means a reload can never replay a stale connection.
//
// This is a browser-only, non-`server` lib surface: no credential, no secret, no server logic.

import type { AccountRef, ConnectResult } from '$lib/accounts/account-ref';

type Handoff = {
	linkedSourceId: string | null;
	accounts: AccountRef[];
};

// Module-level rune state — one live carry at a time. Reset to null on full page reload
// (module re-evaluates) and after consumption.
let handoff = $state<Handoff | null>(null);

/**
 * Called by the connect page's `onConnected` handler: stash the just-connected result so the
 * attributes route can pick it up after `goto()`. Overwrites any prior un-consumed carry
 * (only the most recent connection is ever relevant).
 */
export function stashConnectResult(result: ConnectResult): void {
	handoff = { linkedSourceId: result.linkedSourceId, accounts: result.accounts };
}

/**
 * Consume the carry (read-and-clear). Single-use by design: the attributes route calls this
 * once on entry, copies the result into its own component state, and the store is emptied so
 * a back-forward navigation can't replay it. Returns null when there is nothing to carry
 * (direct nav / reload) → the route fail-closes to its empty state.
 */
export function consumeConnectHandoff(): Handoff | null {
	const h = handoff;
	handoff = null;
	return h;
}

/** Explicit clear (e.g. if the user abandons the attributes step). Idempotent. */
export function clearConnectHandoff(): void {
	handoff = null;
}
