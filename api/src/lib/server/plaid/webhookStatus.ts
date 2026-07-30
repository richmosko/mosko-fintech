// webhookStatus.ts — SELF-206 AC4/AC5: normalize a Plaid webhook into the provider-agnostic
// connection-state vocabulary + classify whether it is a transactions-refresh event.
//
// PROVIDER-BLIND OUTPUT (ADR-037): the `statusClass` values are the normalized, provider-agnostic
// set copied VERBATIM from the `015` linked_source CHECK (single anti-drift source:
// connection-status-constants). The raw Plaid code is preserved separately as
// `providerErrorCode` (forensic; the `015` linked_source_state_history.provider_error_code is
// CHECK-unconstrained by design so a new provider / new code needs zero DDL).

import { CONNECTION_STATUSES, type ConnectionStatus } from '$lib/schemas/connection-status-constants';

/** A normalized connection-state transition to apply (AC4). null = this webhook carries no
 *  health change (e.g. a TRANSACTIONS refresh, or an informational ITEM code). */
export interface StatusTransition {
	statusClass: ConnectionStatus;
	/** Raw Plaid code (error_code when present, else the webhook_code) — forensic, unconstrained. */
	providerErrorCode: string;
}

/** Plaid ITEM error_code → normalized status_class. Recognized codes are mapped precisely; an
 *  UNRECOGNIZED ITEM error defaults to `login_required` (attention-actionable) rather than being
 *  silently dropped — silent staleness is a V1 ship-block (ADR-013 D1); the raw code is retained. */
const ERROR_CODE_TO_STATUS: Readonly<Record<string, ConnectionStatus>> = {
	ITEM_LOGIN_REQUIRED: 'login_required',
	ITEM_NO_ERROR: 'healthy',
	INSTITUTION_DOWN: 'institution_down',
	INSTITUTION_NOT_RESPONDING: 'institution_down',
	INSTITUTION_NOT_AVAILABLE: 'institution_down',
	INSTITUTION_NO_LONGER_SUPPORTED: 'institution_down'
};

/** Plaid ITEM webhook_code (non-ERROR) → normalized status_class. */
const ITEM_CODE_TO_STATUS: Readonly<Record<string, ConnectionStatus>> = {
	PENDING_EXPIRATION: 'login_required',
	PENDING_DISCONNECT: 'login_required',
	USER_PERMISSION_REVOKED: 'revoked',
	USER_ACCOUNT_REVOKED: 'revoked',
	LOGIN_REPAIRED: 'healthy'
};

/** Runtime guard: only ever emit a value the `015` CHECK admits (defense-in-depth vs a typo). */
function asStatus(value: ConnectionStatus): ConnectionStatus {
	return (CONNECTION_STATUSES as readonly string[]).includes(value) ? value : 'login_required';
}

/**
 * Map a Plaid webhook (type + code + optional error_code) → the connection-state transition to
 * apply, or null when there is no health change to record. Only ITEM-class webhooks carry health;
 * everything else (TRANSACTIONS / HOLDINGS / …) returns null here (their sync is AC5's concern).
 * M6: unknown ITEM codes are handled EXPLICITLY — an ITEM ERROR we don't recognize still flips to
 * an actionable state (never silently ignored); a non-error ITEM code we don't recognize is a
 * genuine no-op (WEBHOOK_UPDATE_ACKNOWLEDGED / NEW_ACCOUNTS_AVAILABLE / …).
 */
export function plaidStatusTransition(
	webhookType: string,
	webhookCode: string,
	errorCode: string | null | undefined
): StatusTransition | null {
	if (webhookType !== 'ITEM') return null;

	if (webhookCode === 'ERROR') {
		const raw = errorCode ?? 'ITEM_ERROR';
		const mapped = errorCode ? ERROR_CODE_TO_STATUS[errorCode] : undefined;
		// Unrecognized ITEM error → login_required (actionable; never silent). Raw code retained.
		return { statusClass: asStatus(mapped ?? 'login_required'), providerErrorCode: raw };
	}

	const mapped = ITEM_CODE_TO_STATUS[webhookCode];
	if (mapped) return { statusClass: asStatus(mapped), providerErrorCode: webhookCode };

	// Informational ITEM codes (WEBHOOK_UPDATE_ACKNOWLEDGED, NEW_ACCOUNTS_AVAILABLE, …) — no flip.
	return null;
}

/** AC5 gate: does this webhook indicate new transaction data to pull? Plaid signals it via the
 *  TRANSACTIONS webhook type (SYNC_UPDATES_AVAILABLE / DEFAULT_UPDATE / INITIAL_UPDATE /
 *  HISTORICAL_UPDATE / TRANSACTIONS_REMOVED). The incremental sync (worker) is idempotent, so
 *  triggering on any TRANSACTIONS code is safe. */
export function isTransactionsEvent(webhookType: string): boolean {
	return webhookType === 'TRANSACTIONS';
}
