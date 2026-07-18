// mapper.ts — normalized DTOs → the shipped landing tables (design §2.1 map-straight-in,
// Option A; no raw-staging table). Landing paths:
//   TransactionDTO[] → fn_ingest_transactions(jsonb) (017)  — TENANT / INVOKER / caller-RLS.
//   HoldingDTO[]     → holdings_checkpoint (018/019)         — service_role (append-only).
//   BalanceDTO[]     → account_balance_checkpoint (018)      — service_role (append-only).
//   provider_implied → eod_price upsert (019)                — service_role (shared floor).
//
// The pure builders (buildIngestRows, providerImpliedPrice) are exported for unit
// testing without a DB. The land*() functions do the actual writes on a supplied tx.

import type { BalanceDTO, HoldingDTO, TransactionDTO } from '../adapters/ProviderAdapter.js';
import { TenantBoundClient, type Tx } from '../db/TenantBoundClient.js';
import { assetKey, resolveSecurityIds, type ResolvableAsset } from './resolution.js';

/** The jsonb row shape fn_ingest_transactions(p_rows jsonb) shreds via jsonb_to_recordset
 *  (017 column list — EXACT names/order do not matter to jsonb_to_recordset, names do). */
export interface IngestRow {
	account_id: number;
	transaction_date: string;
	amount: number;
	vendor: string | null;
	description: string | null;
	transaction_type: string | null; // null → RPC COALESCEs to 'standard'
	security_id: number | null;
	quantity: number;
	cost_basis: number | null;
	price: number | null;
	source_provider: string;
	provider_txn_id: string;
	provider_category: string | null;
	import_hash: string | null; // provider path dedups on (source_provider, provider_txn_id)
}

/** Reason a TransactionDTO was dropped from the ingest batch (surfaced for sync_audit). */
export interface DroppedRow {
	providerTxnId: string;
	reason: 'unknown_account';
}

/**
 * PURE: build the jsonb rows for fn_ingest_transactions. Maps each TransactionDTO through
 * the account-id map (providerAccountId → pfin account_id) and the security-id map
 * (assetKey → security_id). A txn whose account is not mapped is DROPPED (surfaced, not
 * silently swallowed) — that account is not linked to this source for this tenant.
 */
export function buildIngestRows(
	dtos: readonly TransactionDTO[],
	accountIdByProvider: ReadonlyMap<string, number>,
	securityIdByKey: ReadonlyMap<string, number>,
	provider: string
): { rows: IngestRow[]; dropped: DroppedRow[] } {
	const rows: IngestRow[] = [];
	const dropped: DroppedRow[] = [];
	for (const t of dtos) {
		const accountId = accountIdByProvider.get(t.providerAccountId);
		if (accountId === undefined) {
			dropped.push({ providerTxnId: t.providerTxnId, reason: 'unknown_account' });
			continue;
		}
		const key = assetKey({ symbol: t.symbol, cusip: t.cusip });
		const securityId = key ? (securityIdByKey.get(key) ?? null) : null;
		rows.push({
			account_id: accountId,
			transaction_date: t.date,
			amount: t.amount,
			vendor: t.vendor,
			description: t.description,
			transaction_type: null,
			security_id: securityId,
			quantity: t.quantity,
			cost_basis: t.costBasis,
			price: t.price,
			source_provider: provider,
			provider_txn_id: t.providerTxnId,
			provider_category: t.providerCategory,
			import_hash: null
		});
	}
	return { rows, dropped };
}

/**
 * PURE: provider_implied price = marketValue ÷ quantity, with Sec guard #1 (div-by-zero)
 * + non-finite rejection. Returns null when the price must NOT be written (quantity 0 or a
 * non-finite result) — the caller skips the eod_price upsert for that holding.
 */
export function providerImpliedPrice(marketValue: number, quantity: number): number | null {
	if (quantity === 0) return null; // Sec guard #1: never divide by zero (qty=0 ≠ a real holding)
	const price = marketValue / quantity;
	if (!Number.isFinite(price)) return null; // NaN/±Infinity → skip (eod_price CHECK would reject NaN anyway)
	return price;
}

/** Collect the distinct resolvable assets from holdings + investment txns (for resolution). */
export function collectResolvableAssets(
	holdings: readonly HoldingDTO[],
	transactions: readonly TransactionDTO[]
): ResolvableAsset[] {
	const seen = new Set<string>();
	const out: ResolvableAsset[] = [];
	const add = (a: ResolvableAsset) => {
		const key = assetKey(a);
		if (key === null || seen.has(key)) return;
		seen.add(key);
		out.push(a);
	};
	for (const h of holdings) {
		add({ symbol: h.symbol, cusip: h.cusip, assetType: h.assetType, name: h.description, currency: h.currency });
	}
	for (const t of transactions) {
		if (t.quantity === 0 && !t.symbol && !t.cusip) continue; // pure cash txn → no security
		// investment txns carry no assetType; default to 'equity' market bucket (adapter has
		// no security.type at txn grain — resolution registers a minimal global row).
		add({ symbol: t.symbol, cusip: t.cusip, assetType: 'equity', name: t.description, currency: t.currency });
	}
	return out;
}

// ── DB landing (service_role + tenant transactions) ─────────────────────────────

/** Land holdings snapshots (service_role, append-only INSERT). */
export async function landHoldings(
	tx: Tx,
	holdings: readonly HoldingDTO[],
	accountIdByProvider: ReadonlyMap<string, number>,
	securityIdByKey: ReadonlyMap<string, number>
): Promise<number> {
	let n = 0;
	for (const h of holdings) {
		const accountId = accountIdByProvider.get(h.providerAccountId);
		if (accountId === undefined) continue; // account not linked to this source
		const key = assetKey(h);
		const securityId = key ? (securityIdByKey.get(key) ?? null) : null;
		await tx`
			insert into pfin.holdings_checkpoint (account_id, symbol, security_id, as_of_date, quantity, balance)
			values (${accountId}, ${h.symbol}, ${securityId}, ${h.asOfDate}, ${h.quantity}, ${h.marketValue})`;
		n += 1;
	}
	return n;
}

/** Land cash balances (service_role, append-only; ON CONFLICT DO NOTHING — table is
 *  immutable so a same-day re-sync keeps the first snapshot). */
export async function landBalances(
	tx: Tx,
	balances: readonly BalanceDTO[],
	accountIdByProvider: ReadonlyMap<string, number>,
	provider: string
): Promise<number> {
	let n = 0;
	for (const b of balances) {
		const accountId = accountIdByProvider.get(b.providerAccountId);
		if (accountId === undefined) continue;
		await tx`
			insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
			values (${accountId}, ${b.balance}, ${b.currency}, ${b.asOfDate}, ${provider})
			on conflict (account_id, as_of_date, source) do nothing`;
		n += 1;
	}
	return n;
}

/** Upsert provider_implied prices (service_role; Sec guard #3 shared-floor upsert). */
export async function landProviderImpliedPrices(
	tx: Tx,
	holdings: readonly HoldingDTO[],
	securityIdByKey: ReadonlyMap<string, number>
): Promise<number> {
	let n = 0;
	for (const h of holdings) {
		const key = assetKey(h);
		const securityId = key ? securityIdByKey.get(key) : undefined;
		if (securityId === undefined) continue; // unvalued (no security_id) → nothing to price
		const price = providerImpliedPrice(h.marketValue, h.quantity); // Sec guard #1
		if (price === null) continue;
		await tx`
			insert into pfin.eod_price (asset_id, price_date, source, price)
			values (${securityId}, ${h.asOfDate}, 'provider_implied', ${price})
			on conflict (asset_id, price_date, source)          -- Sec guard #3: shared-floor upsert
			do update set price = excluded.price, updated_at = now()`;
		n += 1;
	}
	return n;
}

/** Land transactions via the INVOKER RPC under the tenant's RLS context. Returns the RPC
 *  (inserted, skipped) counts. */
export async function landTransactions(tx: Tx, rows: readonly IngestRow[]): Promise<{ inserted: number; skipped: number }> {
	if (rows.length === 0) return { inserted: 0, skipped: 0 };
	// tx.json() serializes the row array as a single jsonb param for jsonb_to_recordset.
	const payload = tx.json(rows as unknown as Parameters<typeof tx.json>[0]);
	const res = await tx<{ inserted: number; skipped: number }[]>`
		select inserted, skipped from pfin.fn_ingest_transactions(${payload}::jsonb)`;
	return res[0] ?? { inserted: 0, skipped: 0 };
}

/** Resolve providerAccountId → pfin account_id under the TENANT RLS context (so the map is
 *  scoped to the bound tenant's accounts — cross-tenant-safe). */
export async function resolveAccountIds(
	tx: Tx,
	sourceId: bigint,
	providerAccountIds: readonly string[]
): Promise<Map<string, number>> {
	const map = new Map<string, number>();
	if (providerAccountIds.length === 0) return map;
	const rows = await tx<{ account_id: number; provider_account_id: string }[]>`
		select account_id, provider_account_id from pfin.account
		where linked_source_id = ${Number(sourceId)}
		  and provider_account_id in ${tx(providerAccountIds as string[])}`;
	for (const r of rows) map.set(r.provider_account_id, r.account_id);
	return map;
}

// ── Orchestration (foundation; NO scheduler — that's PR #2) ──────────────────────

export interface ProviderData {
	balances: readonly BalanceDTO[];
	holdings: readonly HoldingDTO[];
	transactions: readonly TransactionDTO[];
}

export interface SyncResult {
	holdingsLanded: number;
	balancesLanded: number;
	pricesUpserted: number;
	transactionsInserted: number;
	transactionsSkipped: number;
	droppedTransactions: DroppedRow[];
	unresolvedAccounts: string[];
}

/**
 * Land one provider pull for the bound tenant. Sequences the two access modes cleanly:
 *   (1) TENANT: resolve providerAccountId → account_id (RLS-scoped).
 *   (2) SERVICE_ROLE: resolve/register global security_ids; land holdings, balances,
 *       provider_implied prices.
 *   (3) TENANT: land transactions via fn_ingest_transactions (caller-RLS, all-or-nothing).
 *
 * NOTE (non-atomic across the two modes; acceptable V1): a failure after the service_role
 * writes but before the tenant txn insert leaves holdings/prices written and no txns; the
 * next sync is idempotent (balances DO NOTHING; prices upsert; txns dedup on the provider
 * key; holdings append a fresh snapshot the _latest view supersedes).
 */
export async function syncProviderData(
	client: TenantBoundClient,
	sourceId: bigint,
	provider: string,
	data: ProviderData
): Promise<SyncResult> {
	const providerAccountIds = [
		...new Set([
			...data.balances.map((b) => b.providerAccountId),
			...data.holdings.map((h) => h.providerAccountId),
			...data.transactions.map((t) => t.providerAccountId)
		])
	];

	// (1) TENANT — RLS-scoped account resolution.
	const accountIdByProvider = await client.withTenant((tx) =>
		resolveAccountIds(tx, sourceId, providerAccountIds)
	);
	const unresolvedAccounts = providerAccountIds.filter((id) => !accountIdByProvider.has(id));

	// (2) SERVICE_ROLE — global-asset resolution/register + privileged snapshot writes.
	const resolvable = collectResolvableAssets(data.holdings, data.transactions);
	const { securityIdByKey, holdingsLanded, balancesLanded, pricesUpserted } = await client.withServiceRole(
		async (tx) => {
			const map = await resolveSecurityIds(tx, resolvable);
			const hl = await landHoldings(tx, data.holdings, accountIdByProvider, map);
			const bl = await landBalances(tx, data.balances, accountIdByProvider, provider);
			const pu = await landProviderImpliedPrices(tx, data.holdings, map);
			return { securityIdByKey: map, holdingsLanded: hl, balancesLanded: bl, pricesUpserted: pu };
		}
	);

	// (3) TENANT — INVOKER ingest (all-or-nothing, caller-RLS).
	const { rows, dropped } = buildIngestRows(data.transactions, accountIdByProvider, securityIdByKey, provider);
	const ingest = await client.withTenant((tx) => landTransactions(tx, rows));

	return {
		holdingsLanded,
		balancesLanded,
		pricesUpserted,
		transactionsInserted: ingest.inserted,
		transactionsSkipped: ingest.skipped,
		droppedTransactions: dropped,
		unresolvedAccounts
	};
}
