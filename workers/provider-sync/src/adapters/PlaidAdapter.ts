// PlaidAdapter.ts — Plaid (PRIMARY provider) → normalized DTOs (design §1.3 field map
// + §6 empirical invariants).
//
// STRUCTURE: the NORMALIZERS are PURE functions (raw Plaid payload → DTO) exported for
// unit testing WITHOUT the SDK or the network. The fetch* methods are thin: they call
// the Plaid SDK and delegate to the normalizers. Tests exercise the normalizers against
// fixture payloads (mirroring temp/plaid-test.mjs shapes) — never the live API.
//
// EMPIRICAL INVARIANTS (design §6, all adapter-contract invariants):
//   1. Plaid sign is INVERTED (positive = money OUT) → normalize amount × −1 so the DTO
//      is R-7 positive=inflow. (temp/plaid-test.mjs closing note.)
//   2. CUR:USD cash sweeps are a currency-code "holding" → route to the CASH leg, NEVER
//      mint a security. The account's cash is already captured by fetchBalances
//      (accounts.balances.current), so a CUR: security is EXCLUDED from holdings.
//   3. Fixed-income "symbols" are CUSIP-ish/descriptive, not clean tickers → carry cusip
//      through; ingest/resolution.ts keys cusip-FIRST.
//   4. Blank symbol AND blank cusip → security_id NULL downstream (unvalued; SELF-200).
//   5. Corrections (modified/removed/cancel) are LOGGED to sync_audit.detail, NOT applied
//      (OWD-2a DEFERRED to V1.3). getLastSyncDiagnostics() surfaces the counts.

import { z } from 'zod';
import type {
	BalanceDTO,
	CorrectionCounts,
	DateRange,
	HoldingDTO,
	ProviderAccountRef,
	ProviderAdapter,
	SourceRef,
	TransactionDTO
} from './ProviderAdapter.js';

// ── Defensive Zod shapes for the Plaid response fields we read (harden the normalize
//    boundary — external-API input discipline). Non-`.strict()`: Plaid payloads carry
//    many fields we intentionally ignore; we validate ONLY the fields we consume, and
//    reject a malformed value rather than coerce it. ──────────────────────────────────
const num = z.number().finite();
const numOrNull = z.number().finite().nullable().optional();

export const plaidSecuritySchema = z.object({
	security_id: z.string(),
	ticker_symbol: z.string().nullable().optional(),
	cusip: z.string().nullable().optional(),
	isin: z.string().nullable().optional(),
	name: z.string().nullable().optional(),
	type: z.string().nullable().optional(),
	iso_currency_code: z.string().nullable().optional()
});
export type PlaidSecurity = z.infer<typeof plaidSecuritySchema>;

export const plaidHoldingSchema = z.object({
	account_id: z.string(),
	security_id: z.string(),
	quantity: num,
	institution_value: numOrNull,
	cost_basis: numOrNull,
	iso_currency_code: z.string().nullable().optional()
});

export const plaidAccountSchema = z.object({
	account_id: z.string(),
	name: z.string().nullable().optional(),
	type: z.string().nullable().optional(),
	subtype: z.string().nullable().optional(),
	balances: z
		.object({
			current: z.number().nullable().optional(),
			iso_currency_code: z.string().nullable().optional()
		})
		.optional()
});

export const plaidTxnSchema = z.object({
	account_id: z.string(),
	transaction_id: z.string(),
	amount: num,
	date: z.string(),
	name: z.string().nullable().optional(),
	merchant_name: z.string().nullable().optional(),
	iso_currency_code: z.string().nullable().optional(),
	personal_finance_category: z.object({ primary: z.string().nullable().optional() }).nullable().optional()
});

export const plaidInvestmentTxnSchema = z.object({
	account_id: z.string(),
	investment_transaction_id: z.string(),
	security_id: z.string().nullable().optional(),
	cancel_transaction_id: z.string().nullable().optional(),
	amount: num,
	quantity: num,
	price: numOrNull,
	date: z.string(),
	name: z.string().nullable().optional(),
	type: z.string().nullable().optional(),
	subtype: z.string().nullable().optional(),
	iso_currency_code: z.string().nullable().optional()
});

// ── Helpers ────────────────────────────────────────────────────────────────────

const blank = (s: string | null | undefined): boolean => s === null || s === undefined || s.trim() === '';

/** A Plaid security whose ticker denotes a currency-code cash sweep (CUR:USD, CUR:EUR…). */
export function isCurrencyHolding(security: Pick<PlaidSecurity, 'ticker_symbol' | 'type'>): boolean {
	const t = security.ticker_symbol ?? '';
	return t.toUpperCase().startsWith('CUR:') || (security.type ?? '').toLowerCase() === 'cash';
}

/** Map a Plaid security.type → the pfin.asset.asset_type vocab (016 R-9). Unknown market
 *  securities default to 'equity' (the least-wrong market bucket; logged upstream). */
export function normalizeAssetType(plaidType: string | null | undefined): string {
	switch ((plaidType ?? '').toLowerCase()) {
		case 'equity':
			return 'equity';
		case 'etf':
			return 'etf';
		case 'mutual fund':
		case 'mutual_fund':
			return 'fund';
		case 'money market':
		case 'money_market':
			return 'money_market';
		case 'fixed income':
		case 'fixed_income':
			return 'bond';
		case 'cryptocurrency':
		case 'crypto':
			return 'crypto';
		case 'derivative':
			return 'option';
		case 'cash':
			return 'currency';
		default:
			return 'equity';
	}
}

// ── PURE NORMALIZERS (exported for unit testing) ─────────────────────────────────

/** Bank/card transaction → TransactionDTO. Plaid amount is POSITIVE=out → × −1 (§6.1). */
export function normalizeBankTransaction(raw: unknown): TransactionDTO {
	const t = plaidTxnSchema.parse(raw);
	return {
		providerAccountId: t.account_id,
		providerTxnId: t.transaction_id,
		cancelsTxnId: null,
		date: t.date,
		amount: t.amount * -1, // R-7: Plaid +=out → flip so +=inflow
		quantity: 0, // pure cash
		symbol: null,
		cusip: null,
		price: null,
		costBasis: null,
		vendor: t.merchant_name ?? null,
		description: t.name ?? null,
		providerCategory: t.personal_finance_category?.primary ?? null,
		currency: t.iso_currency_code ?? 'USD'
	};
}

/** Investment transaction → TransactionDTO. amount × −1 (§6.1); quantity is signed
 *  (+buy/−sell, Plaid convention already R-7). Security identity resolved downstream. */
export function normalizeInvestmentTransaction(
	raw: unknown,
	securitiesById: ReadonlyMap<string, PlaidSecurity>
): TransactionDTO {
	const t = plaidInvestmentTxnSchema.parse(raw);
	const sec = t.security_id ? securitiesById.get(t.security_id) : undefined;
	return {
		providerAccountId: t.account_id,
		providerTxnId: t.investment_transaction_id,
		cancelsTxnId: t.cancel_transaction_id ?? null,
		date: t.date,
		amount: t.amount * -1, // R-7
		quantity: t.quantity, // signed shares (+buy/−sell)
		symbol: sec?.ticker_symbol ?? null,
		cusip: sec?.cusip ?? null,
		price: t.price ?? null,
		costBasis: null,
		vendor: null,
		description: t.name ?? sec?.name ?? null,
		providerCategory: t.subtype ? `${t.type ?? ''}/${t.subtype}` : (t.type ?? null),
		currency: t.iso_currency_code ?? sec?.iso_currency_code ?? 'USD'
	};
}

/**
 * Holding position → HoldingDTO, OR a cash-route signal. A CUR:USD/cash security is a
 * currency sweep: return { cash: true } and DO NOT mint a security (§6.2) — the account's
 * cash is already captured by fetchBalances. Otherwise return { dto }.
 */
export function normalizeHolding(
	rawHolding: unknown,
	securitiesById: ReadonlyMap<string, PlaidSecurity>,
	asOfDate: string
): { cash: true } | { dto: HoldingDTO } {
	const h = plaidHoldingSchema.parse(rawHolding);
	const sec = securitiesById.get(h.security_id);
	if (sec && isCurrencyHolding(sec)) return { cash: true };
	const symbol = sec?.ticker_symbol ?? null;
	const cusip = sec?.cusip ?? null;
	return {
		dto: {
			providerAccountId: h.account_id,
			symbol: blank(symbol) ? null : symbol,
			cusip: blank(cusip) ? null : cusip,
			isin: sec?.isin ?? null,
			description: sec?.name ?? null,
			assetType: normalizeAssetType(sec?.type),
			quantity: h.quantity,
			marketValue: h.institution_value ?? 0,
			costBasis: h.cost_basis ?? null,
			currency: h.iso_currency_code ?? sec?.iso_currency_code ?? 'USD',
			asOfDate
		}
	};
}

/** Account balance → BalanceDTO. Liabilities (credit/loan) negated to R-7 signed (§1.2). */
export function normalizeBalance(rawAccount: unknown, syncDate: string): BalanceDTO {
	const a = plaidAccountSchema.parse(rawAccount);
	const current = a.balances?.current ?? 0;
	const isLiability = (a.type ?? '').toLowerCase() === 'credit' || (a.type ?? '').toLowerCase() === 'loan';
	return {
		providerAccountId: a.account_id,
		balance: isLiability ? -Math.abs(current) : current,
		currency: a.balances?.iso_currency_code ?? 'USD',
		asOfDate: syncDate
	};
}

/** Account ref (connect() mapping output). */
export function normalizeAccountRef(rawAccount: unknown): ProviderAccountRef {
	const a = plaidAccountSchema.parse(rawAccount);
	return {
		providerAccountId: a.account_id,
		name: a.name ?? a.account_id,
		type: a.type ?? 'other',
		subtype: a.subtype ?? null,
		currency: a.balances?.iso_currency_code ?? 'USD'
	};
}

// ── The adapter ──────────────────────────────────────────────────────────────────

// Minimal structural type for the Plaid SDK client (the subset of methods we call).
// Kept structural so the adapter does not hard-couple to a specific SDK major at the
// type level; the real client is injected at construction.
export interface PlaidClientLike {
	accountsGet(req: { access_token: string }): Promise<{ data: { accounts: unknown[] } }>;
	transactionsSync(req: {
		access_token: string;
		cursor?: string;
		count?: number;
	}): Promise<{
		data: { added: unknown[]; modified: unknown[]; removed: unknown[]; next_cursor: string; has_more: boolean };
	}>;
	investmentsHoldingsGet(req: {
		access_token: string;
	}): Promise<{ data: { holdings: unknown[]; securities: unknown[] } }>;
	investmentsTransactionsGet(req: {
		access_token: string;
		start_date: string;
		end_date: string;
		options?: { count?: number; offset?: number };
	}): Promise<{
		data: { investment_transactions: unknown[]; securities: unknown[]; total_investment_transactions: number };
	}>;
}

export class PlaidAdapter implements ProviderAdapter {
	readonly provider = 'plaid' as const;
	readonly #client: PlaidClientLike;
	#lastCorrections: CorrectionCounts = { modified: 0, removed: 0, cancelled: 0 };

	constructor(client: PlaidClientLike) {
		this.#client = client;
	}

	/** Correction counts from the most recent fetchTransactions — for sync_audit.detail
	 *  (OWD-2a: logged, not applied). */
	getLastSyncDiagnostics(): CorrectionCounts {
		return { ...this.#lastCorrections };
	}

	async fetchBalances(source: SourceRef): Promise<BalanceDTO[]> {
		const { data } = await this.#client.accountsGet({ access_token: source.accessToken });
		return data.accounts.map((a) => normalizeBalance(a, source.syncDate));
	}

	async fetchHoldings(source: SourceRef): Promise<HoldingDTO[]> {
		const { data } = await this.#client.investmentsHoldingsGet({ access_token: source.accessToken });
		const secById = indexSecurities(data.securities);
		const out: HoldingDTO[] = [];
		for (const h of data.holdings) {
			const r = normalizeHolding(h, secById, source.syncDate);
			if ('dto' in r) out.push(r.dto); // CUR:USD sweeps excluded (§6.2 cash leg)
		}
		return out;
	}

	async fetchTransactions(source: SourceRef, range: DateRange): Promise<TransactionDTO[]> {
		const out: TransactionDTO[] = [];
		let modified = 0;
		let removed = 0;
		let cancelled = 0;

		// (a) Bank/card: /transactions/sync (cursor drain; cursor persistence is PR #2).
		let cursor: string | undefined = undefined;
		for (let page = 0; page < 50; page++) {
			const { data } = await this.#client.transactionsSync({
				access_token: source.accessToken,
				cursor,
				count: 500
			});
			for (const t of data.added) out.push(normalizeBankTransaction(t));
			modified += data.modified.length; // OWD-2a: counted, NOT applied
			removed += data.removed.length;
			cursor = data.next_cursor;
			if (!data.has_more) break;
		}

		// (b) Investment transactions (offset-paginated, NOT the sync/cursor model).
		let offset = 0;
		let total = Infinity;
		while (offset < total && offset < 5000) {
			const { data } = await this.#client.investmentsTransactionsGet({
				access_token: source.accessToken,
				start_date: range.start,
				end_date: range.end,
				options: { count: 500, offset }
			});
			const secById = indexSecurities(data.securities);
			const batch = data.investment_transactions;
			for (const t of batch) {
				const dto = normalizeInvestmentTransaction(t, secById);
				out.push(dto);
				if (dto.cancelsTxnId) cancelled += 1; // OWD-2a: counted, NOT applied
			}
			total = data.total_investment_transactions ?? out.length;
			offset += 500;
			if (batch.length === 0) break;
		}

		this.#lastCorrections = { modified, removed, cancelled };
		return out;
	}

	// ── connect() / revoke() — Vault credential admission surface. ──────────────────
	// DEFERRED beyond PR #1: both touch linked_source (015) service_role writes +
	// vault.create_secret / provider-side revoke (a distinct Sec-sensitive credential-
	// admission surface). PR #1 is the INGEST core (fetch normalize + landing). These
	// are stubbed explicit-throw so the interface is satisfied without a half-built
	// credential path. Flagged for the follow-up (connect/revoke + Vault + linked_source).
	async connect(): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }> {
		throw new Error(
			'PlaidAdapter.connect (Vault credential admission → linked_source) is a follow-up ' +
				'surface, not built in PR #1 (ingest core). Route the credential-admission design to Sec.'
		);
	}

	async revoke(): Promise<void> {
		throw new Error(
			'PlaidAdapter.revoke (provider-side revoke + linked_source/Vault delete; retention ' +
				'hard-gate) is a follow-up surface, not built in PR #1.'
		);
	}
}

/** Index a Plaid securities[] array by security_id (validated). */
export function indexSecurities(rawSecurities: unknown[]): Map<string, PlaidSecurity> {
	const m = new Map<string, PlaidSecurity>();
	for (const s of rawSecurities) {
		const parsed = plaidSecuritySchema.parse(s);
		m.set(parsed.security_id, parsed);
	}
	return m;
}
