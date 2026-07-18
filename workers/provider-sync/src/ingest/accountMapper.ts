// accountMapper.ts — the account-mapping slice (ADR-027 amendment). Writes pfin.account
// rows for the ProviderAccountRef[] that the shipped connect() returned, so the downstream
// resolveAccountIds() map (mapper.ts) is no longer always-empty and the ingest path becomes
// functionally reachable.
//
// STRUCTURE mirrors mapper.ts: a PURE builder (buildAccountRows — no DB, unit-testable) +
// a land function (landAccounts — the actual writes on a tenant tx). The Plaid-specific
// type/subtype → account_type map lives on PlaidAdapter (mapAccountType), since it is the
// one provider-specific piece; this module is provider-agnostic and takes the map as a fn.
//
// ── WRITE-IDENTITY (ratified Q1 / ADR-027 amendment) — TENANT / INVOKER, NOT service_role.
//   landAccounts writes under client.withTenant() (SET LOCAL ROLE authenticated + jwt-sub
//   GUC bound to the tenant). Three shipped DB fences then compose exactly as the 013
//   fn_create_manual_account INVOKER precedent:
//     (1) account_insert RLS WITH CHECK (users_id = auth.uid()) + DEFAULT auth.uid() →
//         the row's own users_id is the bound tenant, UN-FORGEABLE (we NEVER set users_id
//         in code — the DB stamps it).
//     (2) fn_account_matched_linked_source BEFORE INSERT (015 STEP 8, Decision-3 canonical
//         instance #6) → the bound tenant must own linked_source_id, else RAISE (NULL-safe
//         fail-closed). Under authenticated it composes with linked_source_select RLS
//         (a foreign source is invisible → the fence raises).
//     (3) fn_grant_creator_access AFTER INSERT (DEFINER) → seeds account_users for
//         NEW.users_id in the same tx.
//   No new DB function, no service_role, no new DDL in the write path (021 is a pure
//   dedup index). DEFINER allowlist unchanged at 3; §10 unchanged at 2; Decision-3
//   unchanged at 8 (this EXERCISES #6, adds none).

import type { ProviderAccountRef } from '../adapters/ProviderAdapter.js';
import type { TenantBoundClient } from '../db/TenantBoundClient.js';
import { resolveAccountIds } from './mapper.js';

/** The 003 tax_treatment CHECK domain. */
export type TaxTreatment = 'taxable' | 'tax_deferred' | 'tax_free';

/**
 * Slice-wide PROVISIONAL defaults for the non-provider-derivable columns (ratified Q4 /
 * §4.2). `scope` (a free-text user-data ownership label, NOT a tenant boundary) and
 * `taxTreatment` are operator-supplied for the batch; every value is provisional and
 * corrected at SELF-212. A retirement account nudges taxTreatment → 'tax_deferred'
 * (buildAccountRows), regardless of the batch default.
 */
export interface AccountMapDefaults {
	scope: string;
	taxTreatment: TaxTreatment;
}

/** One insert-ready pfin.account row. NOTE: users_id is DELIBERATELY absent — it defaults
 *  to auth.uid() under the tenant tx (003), so the tenant stamp is un-forgeable. */
export interface AccountInsertRow {
	name: string;
	account_type: string;
	scope: string;
	tax_treatment: TaxTreatment;
	currency: string;
	linked_source_id: number;
	provider_account_id: string;
}

/** A Plaid type/subtype → 003 account_type CHECK enum mapper (PlaidAdapter.mapAccountType). */
export type AccountTypeMapper = (type: string, subtype: string | null) => string;

/**
 * PURE: build insert-ready pfin.account rows from the connect() account refs. No DB.
 *   - name              ← ref.name
 *   - account_type      ← mapType(ref.type, ref.subtype)   (Plaid map; manual_other fallback)
 *   - scope             ← defaults.scope                    (provisional)
 *   - tax_treatment     ← defaults.taxTreatment, EXCEPT account_type='retirement' → 'tax_deferred'
 *   - currency          ← ref.currency
 *   - linked_source_id  ← sourceId
 *   - provider_account_id ← ref.providerAccountId
 * users_id is NOT built here (DEFAULT auth.uid() stamps it — §Q1); backfill_cutover_date
 * stays NULL (import/reconciliation → SELF-212); is_active defaults true.
 */
export function buildAccountRows(
	refs: readonly ProviderAccountRef[],
	sourceId: bigint,
	defaults: AccountMapDefaults,
	mapType: AccountTypeMapper
): AccountInsertRow[] {
	const linkedSourceId = Number(sourceId);
	return refs.map((ref) => {
		const accountType = mapType(ref.type, ref.subtype);
		// Retirement nudge (§4.2): a retirement account is tax_deferred by default,
		// regardless of the batch default (which typically targets taxable brokerage/cash).
		const taxTreatment: TaxTreatment = accountType === 'retirement' ? 'tax_deferred' : defaults.taxTreatment;
		return {
			name: ref.name,
			account_type: accountType,
			scope: defaults.scope,
			tax_treatment: taxTreatment,
			currency: ref.currency,
			linked_source_id: linkedSourceId,
			provider_account_id: ref.providerAccountId
		};
	});
}

/**
 * Land the account rows for `refs` under the TENANT RLS context (INVOKER / authenticated;
 * ratified Q1). Idempotent via the 021 partial unique index arbiter:
 *   ON CONFLICT (linked_source_id, provider_account_id) WHERE linked_source_id IS NOT NULL
 *   DO NOTHING
 * — the WHERE clause is REQUIRED to match the partial index (021). A re-run of connect+map
 * on the same source is a no-op, never a duplicate row.
 *
 * N1 (Sec non-blocking build-correctness): RETURNING omits rows skipped by DO NOTHING, so
 * on a re-run the freshly-inserted map is incomplete. After the inserts we resolveAccountIds
 * (the shipped tenant-scoped SELECT) for this source and merge, so the returned map is
 * COMPLETE whether each row was freshly inserted OR already present.
 *
 * `ownerUserId` must equal the client's bound tenant — asserted fail-closed (defense-in-
 * depth: the DB stamp already guarantees the tenant, but a client bound to a different
 * tenant than the caller intends is a caller bug we refuse rather than silently honor).
 *
 * @returns Map<providerAccountId, account_id> — the same shape resolveAccountIds produces.
 */
export async function landAccounts(
	client: TenantBoundClient,
	sourceId: bigint,
	ownerUserId: string,
	refs: readonly ProviderAccountRef[],
	defaults: AccountMapDefaults,
	mapType: AccountTypeMapper
): Promise<Map<string, number>> {
	if (ownerUserId !== client.usersId) {
		throw new Error(
			'landAccounts: ownerUserId does not match the tenant-bound client (fail-closed) — ' +
				'the client must be forTenant(ownerUserId).'
		);
	}
	const rows = buildAccountRows(refs, sourceId, defaults, mapType);
	const providerAccountIds = refs.map((r) => r.providerAccountId);

	return client.withTenant(async (tx) => {
		const map = new Map<string, number>();
		for (const row of rows) {
			// INSERT under `authenticated`: account_insert WITH CHECK + DEFAULT auth.uid()
			// stamp users_id (un-forgeable); fn_account_matched_linked_source BEFORE INSERT
			// enforces the tenant owns linked_source_id (#6 fence); fn_grant_creator_access
			// AFTER INSERT seeds the ACL. The 021 partial arbiter dedups a re-run.
			const inserted = await tx<{ account_id: number; provider_account_id: string }[]>`
				insert into pfin.account
					(name, account_type, scope, tax_treatment, currency, linked_source_id, provider_account_id)
				values
					(${row.name}, ${row.account_type}, ${row.scope}, ${row.tax_treatment}, ${row.currency},
					 ${row.linked_source_id}, ${row.provider_account_id})
				on conflict (linked_source_id, provider_account_id) where linked_source_id is not null
				do nothing
				returning account_id, provider_account_id`;
			for (const r of inserted) map.set(r.provider_account_id, r.account_id);
		}
		// N1: complete the map with any rows skipped by DO NOTHING (pre-existing on a re-run).
		const existing = await resolveAccountIds(tx, sourceId, providerAccountIds);
		for (const [pid, aid] of existing) map.set(pid, aid);
		return map;
	});
}
