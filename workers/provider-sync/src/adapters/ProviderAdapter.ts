// ProviderAdapter.ts — the per-provider adapter interface + the 3 normalized DTOs.
//
// OWD-1 (design §1, SOFT one-way door; R-13 refine-at-build). Each provider adapter
// (PlaidAdapter here; SimpleFINAdapter DEFERRED to PR #2) turns its native payload
// into these shared DTOs at the fetch* NORMALIZE boundary. Sign/scale normalization
// is an adapter-contract invariant (design §6): the DTO is uniform R-7 (positive =
// inflow; liabilities negative) regardless of provider quirks — the ledger +
// fn_compute_nav never see the provider-specific convention.

// ── Normalized DTOs (design §1.2) ──────────────────────────────────────────────

/**
 * BalanceDTO — one per account: the cash / current balance → account_balance_checkpoint
 * (018). R-7 SIGNED (liabilities negative; the adapter normalizes the provider's sign).
 */
export interface BalanceDTO {
	/** Plaid account_id / SimpleFIN account id → resolves to pfin.account.provider_account_id. */
	providerAccountId: string;
	/** R-7 SIGNED balance (adapter negates liabilities). */
	balance: number;
	/** ISO 4217; default 'USD'. */
	currency: string;
	/** Plaid: no native balance date → the sync date. SimpleFIN: balance-date. */
	asOfDate: string;
}

/**
 * HoldingDTO — one per position snapshot → holdings_checkpoint (018/019).
 * `marketValue` is the holdings_checkpoint.balance AND the provider_implied NUMERATOR
 * (eod_price price = marketValue ÷ quantity, guarded — design §4 / Sec guard #1).
 */
export interface HoldingDTO {
	providerAccountId: string;
	/** Ticker; null for a blank sweep (SELF-200). */
	symbol: string | null;
	/** Plaid securities.cusip — the REQUIRED path for fixed income (design §6.3). */
	cusip: string | null;
	isin: string | null;
	/** Security NAME (the blank-symbol fallback identifier). */
	description: string | null;
	/** Normalized → pfin.asset.asset_type vocab (equity/etf/fund/money_market/bond/…). */
	assetType: string;
	/** Shares. */
	quantity: number;
	/** Provider position value → holdings_checkpoint.balance; provider_implied numerator. */
	marketValue: number;
	costBasis: number | null;
	currency: string;
	asOfDate: string;
}

/**
 * TransactionDTO — unified cash + investment → account_trans via fn_ingest_transactions
 * (017). `amount` R-7 SIGNED positive=inflow (Plaid FLIPPED by the adapter, design §6.1).
 * `quantity` signed shares (+buy/−sell); 0 for pure cash (017 qty_requires_security CHECK).
 */
export interface TransactionDTO {
	providerAccountId: string;
	/** Plaid transaction_id / investment_transaction_id / SimpleFIN id → dedup key half. */
	providerTxnId: string;
	/** Plaid cancel_transaction_id → correction model (OWD-2a; LOGGED not applied in V1, design §6). */
	cancelsTxnId: string | null;
	date: string;
	/** R-7 SIGNED positive=inflow. */
	amount: number;
	/** Signed shares (+buy/−sell); 0 for pure cash. */
	quantity: number;
	/** Investment txn → resolves to security_id (ingest/resolution.ts). */
	symbol: string | null;
	cusip: string | null;
	/** Per-share transacted price. */
	price: number | null;
	costBasis: number | null;
	/** Plaid merchant_name / SimpleFIN payee. */
	vendor: string | null;
	/** Plaid name / SimpleFIN description. */
	description: string | null;
	/** Plaid personal_finance_category.primary / SimpleFIN mcc — DISPLAY HINT ONLY (R-18). */
	providerCategory: string | null;
	currency: string;
}

// ── Provider account reference (connect() output) ──────────────────────────────

/** A provider account surfaced at connect() time, to map onto pfin.account rows. */
export interface ProviderAccountRef {
	providerAccountId: string;
	name: string;
	type: string;
	subtype: string | null;
	currency: string;
}

/** Correction counts LOGGED to linked_source_sync_audit.detail but NOT applied in V1
 *  (OWD-2a DEFERRED to V1.3 reconciliation — design §2.3 / §6). */
export interface CorrectionCounts {
	modified: number;
	removed: number;
	cancelled: number;
}

/** Date range for a transactions pull. */
export interface DateRange {
	start: string;
	end: string;
}

// ── The interface each adapter satisfies (design §1.1) ─────────────────────────

export interface ProviderAdapter {
	readonly provider: 'plaid' | 'simplefin';
	/**
	 * Credential admission → persists an SD-03 Vault handle on a linked_source row
	 * (service_role). Returns the source_id + the provider's account list.
	 */
	connect(setup: unknown): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }>;
	fetchBalances(source: SourceRef): Promise<BalanceDTO[]>;
	fetchHoldings(source: SourceRef): Promise<HoldingDTO[]>;
	fetchTransactions(source: SourceRef, range: DateRange): Promise<TransactionDTO[]>;
	/** Provider-side revoke-then-delete (retention hard-gate). */
	revoke(source: SourceRef): Promise<void>;
}

/**
 * The linked_source coordinates an adapter needs to fetch: the pfin source row id, the
 * decrypted provider access credential (Vault-resolved by the caller), and the sync date.
 */
export interface SourceRef {
	sourceId: bigint;
	/** Provider access token / credential (Plaid access_token; SimpleFIN access url). */
	accessToken: string;
	/** The date this sync runs (Plaid balance as-of; holdings as-of when provider omits it). */
	syncDate: string;
}
