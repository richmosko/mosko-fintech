// reauthShared.ts — provider-blind re-auth helpers (SELF-207 §2.4.4.b; spec temp/self-207-
// reauth-vault-spec.md). Both adapters' reauthComplete() converge on the SAME healthy
// normalization; Plaid's reauthStart() also needs to resolve the existing access_token to mint
// the update-mode link_token. Kept as free functions (not on a base class) so each adapter
// unit-tests against a mocked AdmissionDb with NO live Postgres — matching the connect/revoke
// admission style.
//
// SECURITY: all writes are service_role (Decision 1 privileged-context-write); the tenant is
// bound in code (auth.uid() is NULL under service_role, so the WHERE users_id = ownerUserId is
// the ONLY fail-closed guard that a wrong/foreign source cannot be touched). The credential is
// read ONLY via the service_role-only pfin.decrypted_source_credential view and NEVER logged.

import type { AdmissionDb } from './PlaidAdapter.js';
import type { Tx } from '../db/TenantBoundClient.js';

/**
 * Append the healthy audit transition row (linked_source_state_history — immutable audit-class,
 * INSERT-only). tx-LEVEL so a provider's rotation can include it in the SAME atomic txn.
 * source_id is the sole tenant anchor (no own users_id) — the caller MUST have proven ownership
 * of this source_id earlier in the SAME transaction (a tenant-bound UPDATE that affected 1 row).
 */
export async function appendHealthyStateHistoryTx(tx: Tx, sourceId: bigint): Promise<void> {
	await tx`
		insert into pfin.linked_source_state_history (source_id, status_class)
		values (${String(sourceId)}::bigint, 'healthy')`;
}

/**
 * The shared healthy transition both providers write on a successful re-auth: flip
 * connection_status → 'healthy' on the EXISTING linked_source + append a healthy
 * linked_source_state_history row (the 043 view surfaces it as the latest status_class; the
 * P4 banner reads connection_status). ONE service_role transaction. Tenant-bound + fail-closed:
 * the UPDATE filters users_id = ownerUserId and must affect exactly one row — a cross-tenant or
 * nonexistent source affects zero rows → raise (no state-history row is written).
 */
export async function writeHealthyTransition(
	db: AdmissionDb,
	sourceId: bigint,
	ownerUserId: string
): Promise<void> {
	const sid = String(sourceId); // postgres.js: bind bigint as text + ::bigint cast.
	await db.withServiceRole(async (tx) => {
		const updated = await tx<{ source_id: string }[]>`
			update pfin.linked_source
			   set connection_status = 'healthy', updated_at = now()
			 where source_id = ${sid}::bigint and users_id = ${ownerUserId}
			returning source_id`;
		if (updated.length !== 1) {
			// Fail-closed: source not found OR not owned by this tenant. Never write the audit
			// row for a source we could not flip (no orphaned state-history rows).
			throw new Error(
				'provider-sync reauth: linked_source not found for tenant (fail-closed).'
			);
		}
		// Append the healthy audit transition — safe because the UPDATE above proved ownership of
		// this exact source_id in the same transaction (shared helper; SimpleFIN rotation reuses it).
		await appendHealthyStateHistoryTx(tx, sourceId);
	});
}

/**
 * Resolve the decrypted provider credential (Plaid access_token / SimpleFIN Access URL) for a
 * source via the service_role-only decrypt view, tenant-scoped + fail-closed. Used by Plaid
 * reauthStart to mint the update-mode link_token against the existing (UNCHANGED) access_token.
 * Never logged; the caller must not surface it. Throws if the source has no credential or is not
 * owned by the tenant.
 */
export async function resolveAccessToken(
	db: AdmissionDb,
	sourceId: bigint,
	ownerUserId: string
): Promise<string> {
	const sid = String(sourceId);
	const token = await db.withServiceRole(async (tx) => {
		const rows = await tx<{ decrypted_credential: string }[]>`
			select decrypted_credential
			  from pfin.decrypted_source_credential
			 where source_id = ${sid}::bigint and users_id = ${ownerUserId}`;
		return rows[0]?.decrypted_credential ?? null;
	});
	if (token === null) {
		throw new Error('provider-sync reauth: no credential for source/tenant (fail-closed).');
	}
	return token;
}
