// mapper.test.ts — pure DTO→landing builders: provider_implied guards (Sec guard #1),
// the ingest-row build (account/security mapping + drop-on-unknown-account), and the
// resolvable-asset collection. No DB.

import { describe, it, expect } from 'vitest';
import {
	buildIngestRows,
	collectResolvableAssets,
	providerImpliedPrice
} from '../src/ingest/mapper.js';
import type { HoldingDTO, TransactionDTO } from '../src/adapters/ProviderAdapter.js';
import { computeImportHash } from '../src/shared/importHash.js';

describe('providerImpliedPrice (Sec guard #1 — div-by-zero + non-finite)', () => {
	it('computes marketValue ÷ quantity', () => {
		expect(providerImpliedPrice(4500, 10)).toBe(450);
	});
	it('returns null when quantity is 0 (never divides by zero)', () => {
		expect(providerImpliedPrice(0, 0)).toBeNull();
		expect(providerImpliedPrice(100, 0)).toBeNull();
	});
	it('returns null for a non-finite result', () => {
		expect(providerImpliedPrice(Infinity, 1)).toBeNull();
		expect(providerImpliedPrice(NaN, 1)).toBeNull();
	});
});

const tx = (over: Partial<TransactionDTO>): TransactionDTO => ({
	providerAccountId: 'p1',
	providerTxnId: 't1',
	cancelsTxnId: null,
	date: '2026-07-10',
	amount: -50,
	quantity: 0,
	symbol: null,
	cusip: null,
	price: null,
	costBasis: null,
	vendor: 'V',
	description: 'D',
	providerCategory: 'CAT',
	currency: 'USD',
	...over
});

describe('buildIngestRows', () => {
	const accountIds = new Map([['p1', 1001]]);
	const securityIds = new Map([['symbol:VOO', 500]]);

	it('maps a cash txn (security_id null, quantity 0) with provider dedup fields', () => {
		const { rows, dropped } = buildIngestRows([tx({})], accountIds, securityIds, 'plaid');
		expect(dropped).toHaveLength(0);
		expect(rows[0]).toMatchObject({
			account_id: 1001,
			amount: -50,
			quantity: 0,
			security_id: null,
			source_provider: 'plaid',
			provider_txn_id: 't1',
			transaction_type: null // RPC COALESCEs to 'standard'
		});
		// SELF-204 (ADR-034 D4): the mapper stamps the SHARED canonical content hash (account +
		// date + amount + normalized descriptor), enabling manual↔provider dedup detection. Assert
		// it equals the shared fn over the resolved pfin account_id — proves no per-tier drift.
		expect(rows[0]?.import_hash).toBe(
			computeImportHash({ accountId: 1001, date: '2026-07-10', amount: -50, vendor: 'V', description: 'D' })
		);
	});

	it('resolves security_id via the key map for an investment txn', () => {
		const invest = tx({ providerTxnId: 't2', symbol: 'VOO', quantity: 2, price: 450, amount: -900 });
		const { rows } = buildIngestRows([invest], accountIds, securityIds, 'plaid');
		expect(rows[0]?.security_id).toBe(500);
		expect(rows[0]?.quantity).toBe(2);
	});

	it('DROPS (surfaces, not swallows) a txn whose account is not linked to this source', () => {
		const orphan = tx({ providerAccountId: 'unknown', providerTxnId: 't3' });
		const { rows, dropped } = buildIngestRows([orphan], accountIds, securityIds, 'plaid');
		expect(rows).toHaveLength(0);
		expect(dropped).toEqual([{ providerTxnId: 't3', reason: 'unknown_account' }]);
	});
});

describe('collectResolvableAssets', () => {
	const holding = (over: Partial<HoldingDTO>): HoldingDTO => ({
		providerAccountId: 'p1',
		symbol: null,
		cusip: null,
		isin: null,
		description: null,
		assetType: 'equity',
		quantity: 1,
		marketValue: 0,
		costBasis: null,
		currency: 'USD',
		asOfDate: '2026-07-15',
		...over
	});

	it('dedups holdings + investment txns by cusip-first key; skips pure cash', () => {
		const assets = collectResolvableAssets(
			[holding({ symbol: 'VOO', cusip: '922908363' }), holding({ symbol: 'VOO', cusip: '922908363' })],
			[
				tx({ symbol: 'VOO', cusip: '922908363', quantity: 2 }), // same key as the holding → deduped
				tx({ symbol: 'AAPL', quantity: 1 }), // new
				tx({}) // pure cash → skipped
			]
		);
		// VOO (by cusip) once + AAPL (by symbol) once = 2.
		expect(assets).toHaveLength(2);
		const symbols = assets.map((a) => a.symbol).sort();
		expect(symbols).toEqual(['AAPL', 'VOO']);
	});
});
