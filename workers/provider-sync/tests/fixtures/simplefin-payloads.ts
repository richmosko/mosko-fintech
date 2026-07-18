// simplefin-payloads.ts — fixture SimpleFIN /accounts payloads mirroring temp/simplefin-test.mjs
// shapes. SHARE-SAFE synthetic values (no real account data). Used by the SimpleFINAdapter
// normalizer + admission unit tests; the tests NEVER hit the live SimpleFIN Bridge.
//
// Empirical shape (probe + aggregator memo):
//   account: { id, name, currency, balance (SIGNED string), available-balance, balance-date
//              (epoch), org{name,domain}, transactions[], holdings[] }  — NO `type` field.
//   txn: { id, posted (epoch), transacted_at, amount (SIGNED string), description, payee,
//          memo, mcc }
//   holding: { symbol|ticker, description, shares, market_value, cost_basis, purchase_price }

// balance-date / posted are epoch seconds. 1751500800 = 2025-07-03.
const BAL_DATE = 1751500800;

// ── Depository (bank) — positive balance, cash txns ──
export const acctChecking = {
	id: 'sfin_acct_chk',
	name: 'Everyday Checking',
	currency: 'USD',
	balance: '3200.55', // SimpleFIN sends decimals as STRINGS
	'available-balance': '3150.00',
	'balance-date': BAL_DATE,
	org: { name: 'Capital One', domain: 'capitalone.com' },
	transactions: [
		{
			id: 'sfin_txn_debit',
			posted: 1751414400, // 2025-07-02
			amount: '-52.10', // SIGNED: negative = debit/outflow (already R-7, no flip)
			description: 'COFFEE SHOP #42',
			payee: 'Coffee Shop',
			memo: 'card purchase',
			mcc: '5814'
		},
		{
			id: 'sfin_txn_credit',
			posted: 1751328000, // 2025-07-01
			transacted_at: 1751300000,
			amount: '1500.00', // SIGNED: positive = credit/inflow
			description: 'PAYROLL DEPOSIT',
			payee: null,
			memo: null,
			mcc: null
		}
	],
	holdings: []
};

// ── Credit card (liability) — NATIVELY NEGATIVE balance (already R-7; no negation needed) ──
export const acctCard = {
	id: 'sfin_acct_card',
	name: 'Quicksilver Card',
	currency: 'USD',
	balance: '-875.40', // liability: SimpleFIN signs it negative natively
	'balance-date': BAL_DATE,
	org: { name: 'Capital One', domain: 'capitalone.com' },
	transactions: [],
	holdings: []
};

// ── Investment account — holdings (one real ticker + one BLANK-symbol sweep) ──
export const acctInvestment = {
	id: 'sfin_acct_inv',
	name: 'Brokerage',
	currency: 'USD',
	balance: '12000.00',
	'balance-date': BAL_DATE,
	org: { name: 'Fidelity', domain: 'fidelity.com' },
	transactions: [],
	holdings: [
		{
			symbol: 'VOO',
			description: 'Vanguard S&P 500 ETF',
			shares: '10',
			market_value: '4500.00',
			cost_basis: '4000.00',
			purchase_price: '400.00'
		},
		{
			// blank symbol sweep (money-market) → description-fallback (SELF-200 unvalued).
			symbol: '   ',
			ticker: null,
			description: 'FIDELITY GOVERNMENT MONEY MARKET',
			shares: '250.00',
			market_value: '250.00',
			cost_basis: null,
			purchase_price: null
		}
	]
};

/** A full /accounts set (no per-account errors). */
export const accountsSetClean = {
	accounts: [acctChecking, acctCard, acctInvestment],
	errors: [],
	errlist: []
};

/** A /accounts set with a per-account errlist entry (gappy institution — must be surfaced). */
export const accountsSetWithErrlist = {
	accounts: [acctChecking],
	errors: [],
	errlist: [{ account: 'sfin_acct_gappy', error: 'act.missingdata' }]
};

// ── A valid base64 setup token whose decoded value is the claim URL. ──
export const CLAIM_URL = 'https://bridge.example.test/simplefin/claim/abc123';
export const SETUP_TOKEN = Buffer.from(CLAIM_URL, 'utf8').toString('base64');

// The Access URL a claim returns — embeds basic-auth (splitAuth must lift it to a header).
export const ACCESS_URL = 'https://user:pass@bridge.example.test/simplefin/access/token-xyz';
