// syncProviderData.g2.integration.test.ts — QA G2: land-path + guard-#3 upsert idempotency,
// LIVE-DB (slice 3b). Design ref: temp/provider-sync-scheduler-design.md §2 (map-straight-in
// landing) + §8 (idempotency contract). Consumes the SHIPPED mapper.ts syncProviderData end-
// to-end against ALL migrations applied — QA authors the test only; the landing functions +
// resolution.ts are Backend/Architect-owned and NOT re-implemented here.
//
// ── THE PROPERTY UNDER TEST (load-bearing) ──────────────────────────────────────────────
// syncProviderData lands ONE provider pull across four write-paths, each with its own
// idempotency posture that a same-day RE-SYNC must honor WITHOUT double-counting:
//   • holdings   → holdings_checkpoint    : APPEND (service_role). A re-sync appends a
//                  SUPERSEDED snapshot; holdings_checkpoint_latest (checkpoint_id desc)
//                  ignores it → the read sees ONE current row, never a doubled position.
//   • balances   → account_balance_checkpoint : ON CONFLICT (account_id, as_of_date, source)
//                  DO NOTHING — a same-day re-sync keeps the FIRST snapshot (immutable).
//   • txns       → fn_ingest_transactions  : dedup on (source_provider, provider_txn_id) —
//                  re-appearing txns are skipped (inserted=0), never a second ledger row.
//   • prices     → eod_price               : guard-#3 SHARED-FLOOR upsert ON CONFLICT
//                  (asset_id, price_date, source) DO UPDATE — a same-day provider_implied
//                  price is UPDATED IN PLACE, never duplicated. THE load-bearing assertion.
// The second sync mutates the holding's marketValue (2000 → 2200) so the derived
// provider_implied price changes (200 → 220): proving the upsert UPDATES (price → 220, still
// ONE row) rather than inserting a duplicate is only non-vacuous when the value actually moves.
//
// ── FIDELITY + DETERMINISM (QA discipline: no silent green, no flaky CI) ─────────────────
// The two sync runs COMMIT (idempotency is a cross-transaction property — a rolled-back tx
// could not model it), so the fixture is torn down explicitly. makeLiveTenantClient runs
// withTenant under `set local role authenticated` (RLS-enforced fn_ingest_transactions) and
// withServiceRole under `set local role service_role` (append/register/upsert) — the exact two
// contexts production's TenantBoundClient establishes (see _liveDb.ts). The provider network is
// out of scope: the DTOs are constructed directly (the adapters have their own unit + admission
// batteries) — this test exercises the DB landing path, not the fetch path.
//
// GATED behind RUN_DB_INTEGRATION=1 (see _liveDb.ts) — a visible skip when the stack is absent,
// never a false pass. Local run: `RUN_DB_INTEGRATION=1 npx vitest run tests/integration`.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Sql } from 'postgres';
import type { BalanceDTO, HoldingDTO, TransactionDTO } from '../../src/adapters/ProviderAdapter.js';
import { syncProviderData, type ProviderData, type SyncResult } from '../../src/ingest/mapper.js';
import { TenantBoundClient } from '../../src/db/TenantBoundClient.js';
import { cleanupG2, makeLiveTenantClient, rawSql, RUN_DB_INTEGRATION } from './_liveDb.js';

const d = RUN_DB_INTEGRATION ? describe : describe.skip;

// A synthetic tenant (seeded into auth.users; NOT a real user — SD §4.5 posture: no PII).
const TENANT = 'c42c42c4-2c42-4c42-8c42-c42c42c42c42';
const PROVIDER = 'simplefin';
const PROVIDER_ACCT = 'ZZTG2-ACCT-1'; // provider-native account id → pfin.account.provider_account_id
const SYMBOL = 'ZZTG2'; // ZZ-namespaced global test asset (clean miss → auto-register)
const AS_OF = '2026-07-15';

// The provider pull. `mv` parameterizes the holding market value so the two syncs differ
// (price 200 → 220) — making the guard-#3 "upsert in place, not duplicate" assertion non-vacuous.
function providerData(mv: number): ProviderData {
	const balance: BalanceDTO = {
		providerAccountId: PROVIDER_ACCT,
		balance: 1234.56,
		currency: 'USD',
		asOfDate: AS_OF
	};
	const holding: HoldingDTO = {
		providerAccountId: PROVIDER_ACCT,
		symbol: SYMBOL,
		cusip: null,
		isin: null,
		description: 'G2 Test ETF',
		assetType: 'etf',
		quantity: 10,
		marketValue: mv,
		costBasis: 1800,
		currency: 'USD',
		asOfDate: AS_OF
	};
	// One investment BUY (qty≠0 + symbol → security_id required by the 017 CHECK) + one pure
	// cash txn (qty=0 / no symbol) — exercises both fn_ingest_transactions arms.
	const buy: TransactionDTO = {
		providerAccountId: PROVIDER_ACCT,
		providerTxnId: 'ZZTG2-TXN-BUY',
		cancelsTxnId: null,
		date: AS_OF,
		amount: -2000,
		quantity: 10,
		symbol: SYMBOL,
		cusip: null,
		price: 200,
		costBasis: 1800,
		vendor: null,
		description: 'Buy G2 ETF',
		providerCategory: null,
		currency: 'USD'
	};
	const cash: TransactionDTO = {
		providerAccountId: PROVIDER_ACCT,
		providerTxnId: 'ZZTG2-TXN-CASH',
		cancelsTxnId: null,
		date: AS_OF,
		amount: 500,
		quantity: 0,
		symbol: null,
		cusip: null,
		price: null,
		costBasis: null,
		vendor: 'ACME',
		description: 'Dividend',
		providerCategory: null,
		currency: 'USD'
	};
	return { balances: [balance], holdings: [holding], transactions: [buy, cash] };
}

interface Snapshot {
	holdingsRows: number;
	balanceRows: number;
	balanceValue: string | null;
	priceRows: number; // provider_implied rows for the asset+date
	priceValue: string | null;
	txnRows: number;
	latestRows: number; // holdings_checkpoint_latest rows for (account, symbol)
	latestQuantity: string | null;
	latestBalance: string | null;
}

let db: Sql;
let accountId: number;
let assetId: number | null = null;
let result1: SyncResult;
let result2: SyncResult;
let snap1: Snapshot;
let snap2: Snapshot;

async function resolveAssetId(): Promise<number | null> {
	const r = await db<{ asset_id: string }[]>`
		select asset_id from pfin.asset where users_id is null and symbol = ${SYMBOL} limit 1`;
	return r[0] ? Number(r[0].asset_id) : null;
}

async function snapshot(): Promise<Snapshot> {
	const aid = assetId; // captured after sync1
	const h = await db<{ n: string }[]>`select count(*)::text as n from pfin.holdings_checkpoint where account_id = ${accountId}`;
	const b = await db<{ n: string; v: string | null }[]>`
		select count(*)::text as n, max(balance)::text as v from pfin.account_balance_checkpoint where account_id = ${accountId}`;
	const p = aid === null
		? [{ n: '0', v: null }]
		: await db<{ n: string; v: string | null }[]>`
			select count(*)::text as n, max(price)::text as v from pfin.eod_price
			where asset_id = ${aid} and price_date = ${AS_OF} and source = 'provider_implied'`;
	const t = await db<{ n: string }[]>`
		select count(*)::text as n from pfin.account_trans
		where account_id = ${accountId} and source_provider = ${PROVIDER}`;
	const l = await db<{ n: string; q: string | null; bal: string | null }[]>`
		select count(*)::text as n, max(quantity)::text as q, max(balance)::text as bal
		from pfin.holdings_checkpoint_latest where account_id = ${accountId} and symbol = ${SYMBOL}`;
	return {
		holdingsRows: Number(h[0]!.n),
		balanceRows: Number(b[0]!.n),
		balanceValue: b[0]!.v,
		priceRows: Number(p[0]!.n),
		priceValue: p[0]!.v,
		txnRows: Number(t[0]!.n),
		latestRows: Number(l[0]!.n),
		latestQuantity: l[0]!.q,
		latestBalance: l[0]!.bal
	};
}

beforeAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	db = rawSql();
	// Defensive pre-clean (a prior aborted run may have left committed rows), then seed the
	// synthetic tenant (only `id` is NOT-NULL-without-default on auth.users — login-less stub).
	await cleanupG2(db, TENANT, [SYMBOL]);
	await db`insert into auth.users (id) values (${TENANT}) on conflict do nothing`;

	// linked_source (the poll-eligible source the account links to).
	const ls = await db<{ source_id: string }[]>`
		insert into pfin.linked_source (users_id, provider, connection_status, is_active, institution_name)
		values (${TENANT}, ${PROVIDER}, 'healthy', true, 'G2 Test Bank')
		returning source_id`;
	const sourceId = Number(ls[0]!.source_id);

	// pfin.account — investment account linked to the source. is_active is NOT in the column
	// list: it was DROPPED at 059 (ADR-042), and the row is open by construction because
	// closed_at defaults to NULL. ⚠ The pfin.linked_source insert above KEEPS its is_active —
	// that is a DIFFERENT COLUMN on a different table (connection lifecycle, ADR-013 A1-A3) and
	// it is preserved. Two `is_active` inserts ten lines apart, one dropped and one kept, is
	// exactly the conflation ADR-042 records being made three times. The AFTER INSERT
	// fn_grant_creator_access DEFINER trigger auto-creates the account_users (rd+wr) grant for
	// TENANT, so both account_select (owner) and the account_trans_insert wr_access-JOIN pass.
	const acct = await db<{ account_id: string }[]>`
		insert into pfin.account
			(users_id, name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
		values (${TENANT}, 'G2 Brokerage', 'investment', 'self', 'taxable', ${sourceId}, ${PROVIDER_ACCT})
		returning account_id`;
	accountId = Number(acct[0]!.account_id);

	const client = makeLiveTenantClient(TENANT);
	try {
		// FIRST sync — the land path (all four write-paths populate from empty).
		result1 = await syncProviderData(client as unknown as TenantBoundClient, BigInt(sourceId), PROVIDER, providerData(2000));
		assetId = await resolveAssetId();
		snap1 = await snapshot();

		// SECOND sync — SAME provider keys + as-of-date, mutated marketValue (2000 → 2200).
		result2 = await syncProviderData(client as unknown as TenantBoundClient, BigInt(sourceId), PROVIDER, providerData(2200));
		snap2 = await snapshot();
	} finally {
		await client.end();
	}
});

afterAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	await cleanupG2(db, TENANT, [SYMBOL]);
	await db.end();
});

d('G2 — first sync lands correctly across all four write-paths (live DB)', () => {
	it('SyncResult reports 1 holding, 1 balance, 1 price, 2 txns inserted (0 skipped/dropped)', () => {
		expect(result1.holdingsLanded).toBe(1);
		expect(result1.balancesLanded).toBe(1);
		expect(result1.pricesUpserted).toBe(1);
		expect(result1.transactionsInserted).toBe(2);
		expect(result1.transactionsSkipped).toBe(0);
		expect(result1.droppedTransactions).toEqual([]);
		expect(result1.unresolvedAccounts).toEqual([]);
	});

	it('holdings_checkpoint holds exactly one snapshot row', () => {
		expect(snap1.holdingsRows).toBe(1);
	});

	it('account_balance_checkpoint holds exactly one row carrying the reported balance', () => {
		expect(snap1.balanceRows).toBe(1);
		expect(Number(snap1.balanceValue)).toBe(1234.56);
	});

	it('the holding auto-registered ONE global provider_implied eod_price of 2000/10 = 200', () => {
		expect(assetId).not.toBeNull();
		expect(snap1.priceRows).toBe(1);
		expect(Number(snap1.priceValue)).toBe(200);
	});

	it('account_trans holds exactly the two provider txns', () => {
		expect(snap1.txnRows).toBe(2);
	});
});

d('G2 — a same-day RE-SYNC is idempotent: no double-count (load-bearing)', () => {
	it('txns DEDUP on (source_provider, provider_txn_id): 0 inserted, 2 skipped — no second ledger row', () => {
		expect(result2.transactionsInserted).toBe(0);
		expect(result2.transactionsSkipped).toBe(2);
		expect(snap2.txnRows).toBe(2); // still 2 — the immutable ledger did not grow
	});

	it('balances DO NOTHING on conflict: still one row, still the FIRST value (not overwritten, not doubled)', () => {
		expect(snap2.balanceRows).toBe(1);
		expect(Number(snap2.balanceValue)).toBe(1234.56);
	});

	it('guard-#3 eod_price upsert UPDATES IN PLACE: still ONE provider_implied row, price 200 → 220', () => {
		// The load-bearing guard-#3 assertion: ON CONFLICT (asset_id, price_date, source) DO
		// UPDATE — a same-day provider_implied price is corrected in place, NOT duplicated.
		expect(snap2.priceRows).toBe(1); // NOT 2 — no duplicate floor row
		expect(Number(snap2.priceValue)).toBe(220); // updated to the new 2200/10
	});

	it('holdings APPEND a superseded snapshot (2 rows), but the checkpoint_id-desc latest read sees ONE current position', () => {
		expect(snap2.holdingsRows).toBe(2); // append-only: the 2000 snapshot is retained, superseded
		expect(snap2.latestRows).toBe(1); // holdings_checkpoint_latest collapses to one row per (account, symbol)
		expect(Number(snap2.latestQuantity)).toBe(10);
		expect(Number(snap2.latestBalance)).toBe(2200); // the latest snapshot wins the tie-break, not the superseded 2000
	});
});
