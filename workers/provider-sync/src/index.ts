// index.ts — provider-sync public surface (PR #1: Foundation + Plaid path).
//
// PR #1 SCOPE: the transport (TenantBoundClient), the Plaid adapter + normalizers, the
// symbol→security_id resolution, and the DTO→landing mapper/orchestrator. The full sync
// SCHEDULER (cron entrypoint, per-source cursor advance, linked_source_sync_audit writes,
// SimpleFINAdapter, connect/revoke Vault admission) is DEFERRED to PR #2 — the Dockerfile
// CMD stays the DevOps placeholder until then.

export { TenantBoundClient } from './db/TenantBoundClient.js';
export type { Tx } from './db/TenantBoundClient.js';
export { loadConfig } from './config/env.js';
export type { WorkerConfig } from './config/env.js';

export type {
	BalanceDTO,
	HoldingDTO,
	TransactionDTO,
	ProviderAdapter,
	ProviderAccountRef,
	SourceRef,
	DateRange,
	CorrectionCounts
} from './adapters/ProviderAdapter.js';

export { PlaidAdapter } from './adapters/PlaidAdapter.js';

export {
	syncProviderData,
	buildIngestRows,
	providerImpliedPrice,
	collectResolvableAssets
} from './ingest/mapper.js';
export type { ProviderData, SyncResult } from './ingest/mapper.js';

export { resolveSecurityId, resolveSecurityIds, assetKey, pricingSourceForAssetType } from './ingest/resolution.js';
