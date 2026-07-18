// PlaidAdapter.test.ts — normalization invariants (design §1.3 field map + §6 empirical).
// Pure normalizers only; no SDK, no network, no DB.

import { describe, it, expect } from 'vitest';
import {
	indexSecurities,
	isCurrencyHolding,
	normalizeAssetType,
	normalizeBalance,
	normalizeBankTransaction,
	normalizeHolding,
	normalizeInvestmentTransaction,
	PlaidAdapter,
	type PlaidClientLike
} from '../src/adapters/PlaidAdapter.js';
import * as fx from './fixtures/plaid-payloads.js';

const secById = indexSecurities(fx.securities);

describe('sign normalization (§6.1 — Plaid +=out → R-7 +=inflow)', () => {
	it('flips a bank purchase (money OUT) to negative', () => {
		const dto = normalizeBankTransaction(fx.bankPurchase);
		expect(dto.amount).toBe(-52.1);
		expect(dto.quantity).toBe(0);
	});
	it('flips a bank deposit (money IN) to positive', () => {
		const dto = normalizeBankTransaction(fx.bankDeposit);
		expect(dto.amount).toBe(1500.0);
	});
	it('flips an investment buy (cash OUT) to negative and keeps +buy quantity', () => {
		const dto = normalizeInvestmentTransaction(fx.invBuy, secById);
		expect(dto.amount).toBe(-900.0);
		expect(dto.quantity).toBe(2);
	});
	// G1 (QA): the sell branch. Raw fixture amount -450 → flipped to +450 (cash IN);
	// quantity stays SIGNED -1. Guards against a Math.abs(quantity) regression that would
	// corrupt a −sell into a +buy — which the +buy test above would NOT catch.
	it('flips an investment sell (cash IN) to positive and keeps −sell (signed) quantity', () => {
		const dto = normalizeInvestmentTransaction(fx.invSellCancelled, secById);
		expect(dto.amount).toBe(450.0);
		expect(dto.quantity).toBe(-1);
	});
});

describe('field map (§1.3)', () => {
	it('maps bank txn fields', () => {
		const dto = normalizeBankTransaction(fx.bankPurchase);
		expect(dto.providerTxnId).toBe('txn_purchase_1');
		expect(dto.vendor).toBe('Coffee Shop'); // merchant_name
		expect(dto.description).toBe('COFFEE SHOP #42'); // name
		expect(dto.providerCategory).toBe('FOOD_AND_DRINK'); // personal_finance_category.primary
		expect(dto.cancelsTxnId).toBeNull();
	});
	it('maps investment txn fields incl. cusip carry + cancel', () => {
		const dto = normalizeInvestmentTransaction(fx.invSellCancelled, secById);
		expect(dto.providerTxnId).toBe('itxn_sell_2'); // investment_transaction_id
		expect(dto.symbol).toBe('VOO');
		expect(dto.cusip).toBe('922908363');
		expect(dto.price).toBe(450.0);
		expect(dto.cancelsTxnId).toBe('itxn_sell_1'); // correction handle (LOGGED not applied)
	});
});

describe('CUR:USD cash sweep (§6.2 — route to cash leg, never mint a security)', () => {
	it('detects a currency holding', () => {
		expect(isCurrencyHolding(fx.secCashSweep)).toBe(true);
		expect(isCurrencyHolding(fx.secEquity)).toBe(false);
	});
	it('excludes a CUR:USD holding from HoldingDTOs (no minted security)', () => {
		const r = normalizeHolding(fx.holdingCashSweep, secById, '2026-07-15');
		expect(r).toEqual({ cash: true });
	});
});

describe('cusip-first fixed income (§6.3)', () => {
	it('carries cusip through for a bond with a CUSIP-ish symbol', () => {
		const r = normalizeHolding(fx.holdingBond, secById, '2026-07-15');
		expect('dto' in r).toBe(true);
		if ('dto' in r) {
			expect(r.dto.symbol).toBe('CILH4422711'); // descriptive symbol preserved
			expect(r.dto.cusip).toBe('912797KL5'); // the real resolution key
			expect(r.dto.assetType).toBe('bond');
		}
	});
});

describe('blank symbol + blank cusip (§6.4 — unvalued downstream)', () => {
	it('yields null symbol and null cusip', () => {
		const r = normalizeHolding(fx.holdingBlank, secById, '2026-07-15');
		expect('dto' in r).toBe(true);
		if ('dto' in r) {
			expect(r.dto.symbol).toBeNull();
			expect(r.dto.cusip).toBeNull();
			expect(r.dto.description).toBe('Private Placement XYZ'); // name fallback identity
		}
	});
});

describe('balance sign (§1.2 — liabilities negative)', () => {
	it('keeps a depository balance positive', () => {
		const dto = normalizeBalance(fx.acctDepository, '2026-07-15');
		expect(dto.balance).toBe(3200.55);
		expect(dto.asOfDate).toBe('2026-07-15'); // Plaid has no native balance date → sync date
	});
	it('negates a credit-card (liability) balance', () => {
		const dto = normalizeBalance(fx.acctCredit, '2026-07-15');
		expect(dto.balance).toBe(-875.4);
	});
});

describe('asset-type normalization → pfin.asset vocab', () => {
	it('maps Plaid types', () => {
		expect(normalizeAssetType('etf')).toBe('etf');
		expect(normalizeAssetType('mutual fund')).toBe('fund');
		expect(normalizeAssetType('fixed income')).toBe('bond');
		expect(normalizeAssetType('cryptocurrency')).toBe('crypto');
		expect(normalizeAssetType('something-unknown')).toBe('equity'); // least-wrong market bucket
	});
});

describe('PlaidAdapter fetch* delegate to normalizers (mocked SDK, no network)', () => {
	const client: PlaidClientLike = {
		accountsGet: async () => ({ data: { accounts: [fx.acctDepository, fx.acctCredit, fx.acctInvestment] } }),
		transactionsSync: async () => ({
			data: {
				added: [fx.bankPurchase, fx.bankDeposit],
				modified: [{ transaction_id: 'm1' }],
				removed: [{ transaction_id: 'r1' }],
				next_cursor: 'cur_end',
				has_more: false
			}
		}),
		investmentsHoldingsGet: async () => ({
			data: { holdings: [fx.holdingEquity, fx.holdingBond, fx.holdingCashSweep, fx.holdingBlank], securities: fx.securities }
		}),
		investmentsTransactionsGet: async () => ({
			data: { investment_transactions: [fx.invBuy, fx.invSellCancelled], securities: fx.securities, total_investment_transactions: 2 }
		})
	};
	const adapter = new PlaidAdapter(client);
	const source = { sourceId: 1n, accessToken: 'access-sandbox-x', syncDate: '2026-07-15' };

	it('fetchBalances returns one BalanceDTO per account', async () => {
		const b = await adapter.fetchBalances(source);
		expect(b).toHaveLength(3);
		expect(b.find((x) => x.providerAccountId === 'acct_card_1')?.balance).toBe(-875.4);
	});
	it('fetchHoldings excludes the CUR:USD sweep (3 of 4)', async () => {
		const h = await adapter.fetchHoldings(source);
		expect(h).toHaveLength(3);
		expect(h.some((x) => x.symbol === 'CUR:USD')).toBe(false);
	});
	it('fetchTransactions merges bank + investment and LOGS correction counts (not applied)', async () => {
		const t = await adapter.fetchTransactions(source, { start: '2024-07-15', end: '2026-07-15' });
		expect(t).toHaveLength(4); // 2 bank + 2 investment
		const diag = adapter.getLastSyncDiagnostics();
		expect(diag.modified).toBe(1);
		expect(diag.removed).toBe(1);
		expect(diag.cancelled).toBe(1); // the cancelled sell
	});
});
