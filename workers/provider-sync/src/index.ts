// index.ts — provider-sync public surface.
//
// Landed across slices: the transport (TenantBoundClient), the Plaid + SimpleFIN adapters +
// normalizers, credential admission (connect/revoke), account mapping, the symbol→security_id
// resolution, the DTO→landing mapper/orchestrator (syncProviderData), and — slice 3b — the
// SYNC SCHEDULER (the Coolify-cron `poll` entrypoint that enumerates active linked_source rows
// and drives syncProviderData per source across both adapters, with per-source failure
// isolation + scheduled_poll audit). DevOps owns the Dockerfile CMD / cron container.

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
export { SimpleFINAdapter } from './adapters/SimpleFINAdapter.js';

export {
	syncProviderData,
	buildIngestRows,
	providerImpliedPrice,
	collectResolvableAssets
} from './ingest/mapper.js';
export type { ProviderData, SyncResult } from './ingest/mapper.js';

export { resolveSecurityId, resolveSecurityIds, assetKey, pricingSourceForAssetType } from './ingest/resolution.js';

// Slice 3b — the SYNC SCHEDULER (Coolify-cron entrypoint `node dist/cli/poll.js`).
export {
	runPoll,
	runPollLoop,
	enumerateSources,
	resolveCredential,
	buildAdapter,
	createPollHandlers,
	trailingRange,
	todayIso,
	POLL_PROVIDERS
} from './cli/poll.js';
export type {
	PollProvider,
	SourceRow,
	AuditDetail,
	SourceSyncOutcome,
	PollSummary,
	PollHandlers,
	PollClient,
	FetchAdapter,
	PollWiring,
	SyncFn,
	RunPollDeps
} from './cli/poll.js';
