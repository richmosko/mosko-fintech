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

export { PlaidAdapter, PublicTokenInvalidError, isPublicTokenInvalidity } from './adapters/PlaidAdapter.js';
export { SimpleFINAdapter } from './adapters/SimpleFINAdapter.js';

export {
	syncProviderData,
	buildIngestRows,
	providerImpliedPrice,
	collectResolvableAssets
} from './ingest/mapper.js';
export type { ProviderData, SyncResult } from './ingest/mapper.js';

export { resolveSecurityId, resolveSecurityIds, assetKey, pricingSourceForAssetType } from './ingest/resolution.js';

// SELF-212 Option C — inbound admission HTTP endpoint (leg-1 link_token mint + leg-2
// exchange/admit). Entrypoint: `node dist/cli/serve-admission.js` (DevOps owns Dockerfile CMD).
export { createAdmissionServer } from './http/admissionServer.js';
export type { AdmissionServerDeps, ExchangeInput, AdmissionAccountRef } from './http/admissionServer.js';
export { mintLinkToken } from './http/linkToken.js';
export { verifySharedSecret, ADMISSION_SECRET_HEADER } from './http/sharedSecret.js';
export { assertPrivateOnly, detectPublicRouteSignal, PUBLIC_ROUTE_ENV_MATCHERS } from './http/admissionGuard.js';
export { loadAdmissionConfig } from './http/admissionConfig.js';
export type { AdmissionConfig } from './http/admissionConfig.js';

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
