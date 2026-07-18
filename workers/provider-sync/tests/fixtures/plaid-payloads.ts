// plaid-payloads.ts — fixture Plaid payloads mirroring temp/plaid-test.mjs shapes.
// SHARE-SAFE synthetic values (no real account data). Used by the normalizer unit tests;
// the tests NEVER hit the live Plaid API.

// ── Securities (investments/holdings + investments/transactions carry a securities[]) ──
export const secEquity = {
	security_id: 'sec_equity_voo',
	ticker_symbol: 'VOO',
	cusip: '922908363',
	isin: 'US9229083632',
	name: 'Vanguard S&P 500 ETF',
	type: 'etf',
	iso_currency_code: 'USD'
};

// Fixed income: descriptive/CUSIP-ish "symbol", cusip is the real key (design §6.3).
export const secBond = {
	security_id: 'sec_bond_tbill',
	ticker_symbol: 'CILH4422711',
	cusip: '912797KL5',
	isin: null,
	name: 'US Treasury Bill - 3.52% 08/2026',
	type: 'fixed income',
	iso_currency_code: 'USD'
};

// CUR:USD cash sweep — a currency-code "holding" that must route to the cash leg (§6.2).
export const secCashSweep = {
	security_id: 'sec_cur_usd',
	ticker_symbol: 'CUR:USD',
	cusip: null,
	isin: null,
	name: 'US Dollar',
	type: 'cash',
	iso_currency_code: 'USD'
};

// Blank symbol AND blank cusip → security_id NULL downstream (§6.4 unvalued, SELF-200).
export const secBlank = {
	security_id: 'sec_blank',
	ticker_symbol: null,
	cusip: null,
	isin: null,
	name: 'Private Placement XYZ',
	type: 'other',
	iso_currency_code: 'USD'
};

export const securities = [secEquity, secBond, secCashSweep, secBlank];

// ── Holdings (/investments/holdings/get holdings[]) ──
export const holdingEquity = {
	account_id: 'acct_invest_1',
	security_id: 'sec_equity_voo',
	quantity: 10,
	institution_value: 4500.0,
	cost_basis: 4000.0,
	iso_currency_code: 'USD'
};
export const holdingBond = {
	account_id: 'acct_invest_1',
	security_id: 'sec_bond_tbill',
	quantity: 5,
	institution_value: 5010.0,
	cost_basis: 5000.0,
	iso_currency_code: 'USD'
};
export const holdingCashSweep = {
	account_id: 'acct_invest_1',
	security_id: 'sec_cur_usd',
	quantity: 250.0,
	institution_value: 250.0,
	cost_basis: null,
	iso_currency_code: 'USD'
};
export const holdingBlank = {
	account_id: 'acct_invest_1',
	security_id: 'sec_blank',
	quantity: 1,
	institution_value: 0,
	cost_basis: null,
	iso_currency_code: 'USD'
};
// A zero-quantity position — exercises the div-by-zero guard (Sec guard #1).
export const holdingZeroQty = {
	account_id: 'acct_invest_1',
	security_id: 'sec_equity_voo',
	quantity: 0,
	institution_value: 0,
	cost_basis: null,
	iso_currency_code: 'USD'
};

// ── Accounts (/accounts/get accounts[]) ──
export const acctDepository = {
	account_id: 'acct_checking_1',
	name: 'Everyday Checking',
	type: 'depository',
	subtype: 'checking',
	balances: { current: 3200.55, iso_currency_code: 'USD' }
};
export const acctCredit = {
	account_id: 'acct_card_1',
	name: 'Rewards Card',
	type: 'credit',
	subtype: 'credit card',
	balances: { current: 875.4, iso_currency_code: 'USD' } // Plaid reports owed as positive
};
export const acctInvestment = {
	account_id: 'acct_invest_1',
	name: 'Brokerage',
	type: 'investment',
	subtype: 'brokerage',
	balances: { current: 9760.0, iso_currency_code: 'USD' }
};

// ── Bank/card transactions (/transactions/sync added[]) ──
// Plaid convention: POSITIVE amount = money OUT. So a $52.10 purchase is amount: 52.10.
export const bankPurchase = {
	account_id: 'acct_checking_1',
	transaction_id: 'txn_purchase_1',
	amount: 52.1, // money OUT → normalizes to −52.10 (R-7)
	date: '2026-07-10',
	name: 'COFFEE SHOP #42',
	merchant_name: 'Coffee Shop',
	iso_currency_code: 'USD',
	personal_finance_category: { primary: 'FOOD_AND_DRINK' }
};
export const bankDeposit = {
	account_id: 'acct_checking_1',
	transaction_id: 'txn_deposit_1',
	amount: -1500.0, // money IN → normalizes to +1500.00 (R-7)
	date: '2026-07-01',
	name: 'PAYROLL',
	merchant_name: null,
	iso_currency_code: 'USD',
	personal_finance_category: { primary: 'INCOME' }
};

// ── Investment transactions (/investments/transactions/get investment_transactions[]) ──
export const invBuy = {
	account_id: 'acct_invest_1',
	investment_transaction_id: 'itxn_buy_1',
	security_id: 'sec_equity_voo',
	cancel_transaction_id: null,
	amount: 900.0, // cash OUT to buy → −900.00 (R-7)
	quantity: 2, // +buy
	price: 450.0,
	date: '2026-07-05',
	name: 'BUY VOO',
	type: 'buy',
	subtype: 'buy',
	iso_currency_code: 'USD'
};
export const invSellCancelled = {
	account_id: 'acct_invest_1',
	investment_transaction_id: 'itxn_sell_2',
	security_id: 'sec_equity_voo',
	cancel_transaction_id: 'itxn_sell_1', // a correction — LOGGED not applied (OWD-2a)
	amount: -450.0,
	quantity: -1, // −sell
	price: 450.0,
	date: '2026-07-06',
	name: 'SELL VOO (cancel)',
	type: 'sell',
	subtype: 'sell',
	iso_currency_code: 'USD'
};
