// connection-status-constants.ts — browser-safe canonical value-sets + predicates for the
// SELF-207 connection-state surfaces (§2.4.4.b). Provider-BLIND (ADR-037): these are the
// normalized, provider-agnostic status values, not any provider's raw error codes.
//
// NON-server module (imports nothing server-only) so BOTH sides import the SAME canonical
// value-set + predicates: Backend (the `043` linked_source_connection_state loader / the
// +layout.server.ts health summary) AND Frontend's chip/banner rendering. Single anti-drift
// point — the enum can never diverge because there is only one definition.
//
// Value-set is copied VERBATIM from the `015` DB CHECK on pfin.linked_source.connection_status
// (and the identical linked_source_state_history.status_class CHECK) — the DB CHECK is the
// authoritative backstop. If `015`'s CHECK changes, update here (Backend-sourced; tracks the
// migration, not UI preference).

/** connection_status / status_class — VERBATIM from the `015` pfin CHECK constraints. */
export const CONNECTION_STATUSES = [
	'healthy',
	'login_required',
	'institution_down',
	'revoked',
	'disconnected'
] as const;
export type ConnectionStatus = (typeof CONNECTION_STATUSES)[number];

/**
 * The re-auth-actionable set (SELF-207 AC #2): the account owner can fix these by
 * re-authenticating. `institution_down` is deliberately EXCLUDED — it is a transient
 * provider-side outage that re-auth cannot fix (the banner's no-CTA info variant); `healthy`
 * needs nothing. This set is the single source for "show the re-auth affordance".
 */
export const REAUTH_STATUSES = ['login_required', 'revoked', 'disconnected'] as const;
export type ReauthStatus = (typeof REAUTH_STATUSES)[number];

/** Providers with no automated sync / no credential to re-auth (manual + file import). */
export const MANUAL_PROVIDERS = ['manual', 'import'] as const;

/** True when the account owner can resolve the state by re-authenticating (AC #2 gate). */
export function needsReauth(status: string): status is ReauthStatus {
	return (REAUTH_STATUSES as readonly string[]).includes(status);
}

/** True for any non-healthy connection state (drives the D1/banner "unhealthy" branch). */
export function isUnhealthy(status: string): boolean {
	return status !== 'healthy';
}

/** True for the transient provider-side outage (info-only; no re-auth CTA). */
export function isInstitutionDown(status: string): boolean {
	return status === 'institution_down';
}

/**
 * The distinct visual states of the design-system `connection-status-chip`
 * (design-system-spec.md §4): fresh · re-auth(actionable) · institution-down(info) ·
 * grant-revoked · manual · inactive—sync-paused. Derived from the raw row fields — a chip's
 * look depends on more than `connection_status` alone (an inactive account is sync-paused
 * regardless of status; a manual source has no connection to be un/healthy).
 */
export type ConnectionChipState =
	| 'fresh'
	| 'login_required'
	| 'institution_down'
	| 'revoked'
	| 'disconnected'
	| 'manual'
	| 'inactive';

/**
 * Map a connection-state row → its chip state. Precedence is deliberate:
 *   1. inactive (is_active=false) — sync is paused regardless of connection health;
 *   2. manual/import provider — no automated connection to describe;
 *   3. otherwise the normalized connection_status (healthy → 'fresh').
 */
export function connectionChipState(row: {
	connection_status: string;
	provider: string;
	is_active: boolean;
}): ConnectionChipState {
	if (!row.is_active) return 'inactive';
	if ((MANUAL_PROVIDERS as readonly string[]).includes(row.provider)) return 'manual';
	switch (row.connection_status) {
		case 'healthy':
			return 'fresh';
		case 'login_required':
			return 'login_required';
		case 'institution_down':
			return 'institution_down';
		case 'revoked':
			return 'revoked';
		case 'disconnected':
			return 'disconnected';
		default:
			// Unknown/forward-compat value: fail safe to a neutral, non-actionable chip rather
			// than mis-signalling health. (Belt-and-braces against a future `015` CHECK change.)
			return 'inactive';
	}
}
