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
import type { Tx } from '../db/TenantBoundClient.js';
import type {
	BalanceDTO,
	CorrectionCounts,
	DateRange,
	HoldingDTO,
	ProviderAccountRef,
	ProviderAdapter,
	RevokeRef,
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

/**
 * Retirement-subtype allowlist (ADR-027 amendment §4.1 / Q3). A Plaid `investment`-type
 * account whose subtype is one of these maps to account_type='retirement' (which then nudges
 * tax_treatment → 'tax_deferred'); every other investment subtype maps to 'investment'.
 * Grounded in the design memo's Q3 table (the enumerated 401k/403b/457b/ira/roth/roth 401k/
 * sep ira/simple ira/pension/retirement) + the direct US-plan Plaid equivalents. Lower-cased
 * match. The ONE provider-specific list — kept here on the Plaid adapter, not the generic mapper.
 */
const PLAID_RETIREMENT_SUBTYPES: ReadonlySet<string> = new Set([
	'401a',
	'401k',
	'403b',
	'457b',
	'ira',
	'roth',
	'roth ira',
	'roth 401k',
	'sep ira',
	'sep',
	'simple ira',
	'simple',
	'pension',
	'retirement',
	'keogh',
	'sarsep',
	'tsp'
]);

/**
 * Map a Plaid account `type`/`subtype` → the 003 account_type CHECK enum
 * (depository/investment/retirement/crypto/manual_other/real_estate/liability). ADR-027
 * amendment §4.1 (Q3), ratified:
 *   - depository            → 'depository'
 *   - credit | loan         → 'liability'
 *   - investment            → 'retirement' IFF subtype ∈ PLAID_RETIREMENT_SUBTYPES, else 'investment'
 *   - any unrecognized type → 'manual_other' (fallback; a data-quality flag, corrected at SELF-212)
 * No auto-assignment to crypto/real_estate — Plaid has no clean signal; reachable only via
 * the SELF-212 override.
 */
export function mapPlaidAccountType(type: string, subtype: string | null): string {
	const t = (type ?? '').toLowerCase().trim();
	const s = (subtype ?? '').toLowerCase().trim();
	switch (t) {
		case 'depository':
			return 'depository';
		case 'credit':
		case 'loan':
			return 'liability';
		case 'investment':
			return PLAID_RETIREMENT_SUBTYPES.has(s) ? 'retirement' : 'investment';
		default:
			return 'manual_other';
	}
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
	// Leg-1 link_token mint (SELF-212 Option C). Worker-tier only: /link/token/create needs
	// the Plaid client secret, which per ADR-027 (s) lives ONLY in the worker (never api/src).
	linkTokenCreate(req: {
		user: { client_user_id: string };
		client_name: string;
		products: string[];
		country_codes: string[];
		language: string;
		webhook?: string;
		redirect_uri?: string;
	}): Promise<{ data: { link_token: string; expiration: string } }>;
	// Credential-admission surface (connect/revoke). Structural subset of the Plaid SDK.
	itemPublicTokenExchange(req: {
		public_token: string;
	}): Promise<{ data: { access_token: string; item_id: string } }>;
	itemRemove(req: { access_token: string }): Promise<{ data: unknown }>;
	// Dev-CLI-only sandbox mint (never a production admission path — SC3-C2).
	sandboxPublicTokenCreate(req: {
		institution_id: string;
		initial_products: string[];
	}): Promise<{ data: { public_token: string } }>;
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

// ── Credential-admission plumbing (connect/revoke) ───────────────────────────────

/**
 * The minimal DB surface connect()/revoke() need: a service_role transaction runner +
 * a close(). TenantBoundClient satisfies this structurally (its withServiceRole runs
 * `SET LOCAL ROLE service_role` — Decision 1 privileged-context-write). Kept structural
 * so the admission logic unit-tests against a mocked DB with NO live Postgres.
 */
export interface AdmissionDb {
	withServiceRole<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
	end(): Promise<void>;
}

/**
 * Factory: resolve a tenant-bound service_role client for `usersId`. Production wiring is
 * `(usersId) => TenantBoundClient.forTenant(config, usersId)` — the factory (not this file)
 * constructs the raw Postgres client, so the TBC-node fence stays satisfied.
 */
export type AdmissionDbFactory = (usersId: string) => AdmissionDb;

/** Optional token-free diagnostic logger (SC3-C4: the access_token is NEVER passed here). */
export type AdmissionLogger = (message: string) => void;

/** Canonical uuid (stricter than TenantBoundClient's loose guard — fail-closed on shape). */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function assertUuid(value: string, label: string): void {
	if (!UUID_RE.test(value)) {
		// Fail-closed BEFORE any admission write (SC3-C3). Message carries the LABEL only,
		// never a credential.
		throw new Error(`provider-sync admission: ${label} must be a well-formed uuid (fail-closed).`);
	}
}

/** connect() input shape — `.strict()` (SC mass-assignment prevention, Lock 14 mod #1). */
const connectSetupSchema = z
	.object({
		provider: z.literal('plaid'),
		publicToken: z.string().min(1),
		ownerUserId: z.string().min(1),
		institutionId: z.string().optional(),
		institutionName: z.string().optional()
	})
	.strict();

/** The exchange response fields we consume (external-input boundary hardening). */
const exchangeSchema = z.object({
	access_token: z.string().min(1),
	item_id: z.string().min(1)
});

/** Extract a Plaid error_code from an SDK/axios error without touching credential-bearing
 *  fields (err.config.data carries access_token + PLAID_SECRET — never read/surface it). */
export function plaidErrorCode(err: unknown): string | null {
	const e = err as { response?: { data?: { error_code?: unknown } }; error_code?: unknown } | null | undefined;
	const code = e?.response?.data?.error_code ?? e?.error_code;
	return typeof code === 'string' ? code : null;
}

/** Build a SCRUBBED error for a failed Plaid call. SC3-C4: the raw SDK/axios error carries
 *  the access_token + client secret in err.config.data — we discard the whole object and
 *  keep only the (non-sensitive) error_code + operation label. */
export function scrubbedPlaidError(err: unknown, op: string): Error {
	const code = plaidErrorCode(err);
	return new Error(`Plaid ${op} failed${code ? ` (${code})` : ''}`);
}

/**
 * Item-2 (Sec SELF-212): the recognized Plaid token-invalidity error_code set for the
 * /item/public_token/exchange call. Plaid collapses invalid / expired / already-exchanged into
 * the SINGLE `INVALID_PUBLIC_TOKEN` code (error_type INVALID_INPUT) — which is exactly what we
 * want: ONE uniform client-correctable state, NOT a per-state taxonomy (no token-state oracle,
 * guardrail #1). Keyed STRICTLY to the exchange leg + this allowlist; every other Plaid code
 * (INVALID_API_KEYS, RATE_LIMIT_EXCEEDED, INTERNAL_SERVER_ERROR, INVALID_FIELD, …) and every
 * non-Plaid failure (DB / vault / network / unknown) stays a generic 5xx (guardrail #2, fail-safe).
 */
const PUBLIC_TOKEN_INVALIDITY_CODES: ReadonlySet<string> = new Set(['INVALID_PUBLIC_TOKEN']);

/**
 * Marker error for a client-correctable invalid/burned/expired public_token AT THE EXCHANGE
 * LEG. The HTTP admission endpoint maps this — and ONLY this — to a worker-400
 * `public_token_invalid` ("re-run Link"); everything else is 5xx. SCRUBBED (guardrail #3): the
 * message carries no token/secret; `plaidErrorCode` holds the non-sensitive Plaid code for
 * server-side logging ONLY and is never emitted in the response envelope.
 */
export class PublicTokenInvalidError extends Error {
	readonly plaidErrorCode: string;
	constructor(code: string) {
		super('Plaid public_token invalid at exchange (client-correctable; re-run Link)');
		this.name = 'PublicTokenInvalidError';
		this.plaidErrorCode = code;
	}
}

/** True iff `err` is a recognized public_token-invalidity error from the EXCHANGE call. */
export function isPublicTokenInvalidity(err: unknown): boolean {
	const code = plaidErrorCode(err);
	return code !== null && PUBLIC_TOKEN_INVALIDITY_CODES.has(code);
}

export class PlaidAdapter implements ProviderAdapter {
	readonly provider = 'plaid' as const;

	/** Plaid `type`/`subtype` → 003 account_type CHECK enum (ADR-027 amendment §4.1). The
	 *  account-mapping slice (accountMapper.landAccounts) passes this as its AccountTypeMapper. */
	static mapAccountType(type: string, subtype: string | null): string {
		return mapPlaidAccountType(type, subtype);
	}

	readonly #client: PlaidClientLike;
	readonly #dbFor: AdmissionDbFactory | undefined;
	readonly #logger: AdmissionLogger | undefined;
	#lastCorrections: CorrectionCounts = { modified: 0, removed: 0, cancelled: 0 };

	/**
	 * @param client Plaid SDK (structural subset).
	 * @param dbFor  tenant-bound service_role DB factory — REQUIRED for connect()/revoke();
	 *               fetch* paths do not use it (existing PR #1 callers pass only `client`).
	 * @param logger optional token-free diagnostic logger (SC3-C4).
	 */
	constructor(client: PlaidClientLike, dbFor?: AdmissionDbFactory, logger?: AdmissionLogger) {
		this.#client = client;
		this.#dbFor = dbFor;
		this.#logger = logger;
	}

	#requireDbFor(): AdmissionDbFactory {
		if (!this.#dbFor) {
			throw new Error(
				'PlaidAdapter credential admission (connect/revoke) requires a dbFor factory; ' +
					'construct with new PlaidAdapter(client, dbFor).'
			);
		}
		return this.#dbFor;
	}

	#log(message: string): void {
		this.#logger?.(message);
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

	// ── connect() — Vault credential admission (design §1.1 / §3 / §4 / §6). ─────────
	// Worker-owns-exchange (ratified one-way-door): the worker does the Plaid exchange +
	// vault.create_secret + INSERT linked_source under service_role. api/src (future) is a
	// thin relay handing only the short-lived public_token. Account-mapping (writing
	// pfin.account) is a SEPARATE slice — this returns account refs only.
	async connect(setup: unknown): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }> {
		const dbFor = this.#requireDbFor();
		const s = connectSetupSchema.parse(setup); // `.strict()` — mass-assignment prevention.
		assertUuid(s.ownerUserId, 'ownerUserId'); // SC3-C3: fail-closed BEFORE any admission.

		// (1) Provider exchange — the ONLY place the raw access_token is in process memory.
		let accessToken: string;
		let itemId: string;
		try {
			const { data } = await this.#client.itemPublicTokenExchange({ public_token: s.publicToken });
			const ex = exchangeSchema.parse(data);
			accessToken = ex.access_token;
			itemId = ex.item_id;
		} catch (err) {
			// Item-2: a recognized public_token-invalidity code at THIS (exchange) leg → a
			// client-correctable marker (→ worker-400). A malformed exchange RESPONSE (Zod parse
			// throw) or any other Plaid/transport failure has no invalidity code → generic 5xx
			// (guardrail #2, fail-safe). Both stay SCRUBBED (guardrail #3 / SC3-C4).
			if (isPublicTokenInvalidity(err)) {
				throw new PublicTokenInvalidError(plaidErrorCode(err) as string);
			}
			throw scrubbedPlaidError(err, 'item/public_token/exchange'); // SC3-C4.
		}

		// (2) Post-exchange work runs under a C6-4 recovery guard (Sec SELF-212): any failure
		//   AFTER a successful exchange attempts Plaid /item/remove so a live, un-revocable Item
		//   is never stranded (connect() discards the access_token when it throws, and the token
		//   lives ONLY in this scope → the recovery MUST be here, not in the HTTP wrapper). The
		//   caller contract is "never retry a burned public_token"; a legitimate same-Item retry
		//   lands on the (u) re-admission UPDATE via unique(provider, external_connection_id).
		try {
			return await this.#admitAfterExchange(s, dbFor, accessToken, itemId);
		} catch (err) {
			await this.#revokeExchangedItemBestEffort(accessToken, itemId);
			throw err;
		}
	}

	/**
	 * C6-4 recovery: best-effort Plaid /item/remove for an Item whose exchange SUCCEEDED but
	 * whose admission then failed. Swallows its own failure (never throws over the original
	 * admission error) and emits a TOKEN-FREE manual-revoke audit signal so a live Item is not
	 * silently stranded. C6-7 forward-hook: replace the log with a same-transaction audit row
	 * when audit infra lands (ADR-026 A2 deferral). NEVER logs the access_token (C6-5).
	 */
	async #revokeExchangedItemBestEffort(accessToken: string, itemId: string): Promise<void> {
		try {
			await this.#client.itemRemove({ access_token: accessToken });
			this.#log(`admission failed post-exchange; revoked orphaned plaid item item_id=${itemId} (C6-4).`);
		} catch (revokeErr) {
			const code = plaidErrorCode(revokeErr);
			this.#log(
				`MANUAL REVOKE REQUIRED (C6-4): plaid item_id=${itemId} is live post-exchange and ` +
					`/item/remove failed${code ? ` (${code})` : ''}; revoke it at the Plaid dashboard.`
			);
		}
	}

	/**
	 * The post-exchange admission body: account-refs fetch + the (u) ONE atomic service_role
	 * transaction (create_secret + INSERT/UPDATE linked_source). Extracted verbatim from
	 * connect() so connect() can wrap it in the C6-4 recovery guard; behavior is unchanged.
	 */
	async #admitAfterExchange(
		s: z.infer<typeof connectSetupSchema>,
		dbFor: AdmissionDbFactory,
		accessToken: string,
		itemId: string
	): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }> {
		// Account refs (no pfin.account write — separate slice / defers the D3 #6 fence).
		let accounts: ProviderAccountRef[];
		try {
			const { data } = await this.#client.accountsGet({ access_token: accessToken });
			accounts = data.accounts.map((a) => normalizeAccountRef(a));
		} catch (err) {
			throw scrubbedPlaidError(err, 'accounts/get'); // SC3-C4.
		}

		// (2) Admission — ONE service_role transaction (Decision 1 privileged-context-write).
		//   create_secret + INSERT are ATOMIC: a crash between them would orphan a never-
		//   referenced vault.secrets row (the retention trigger only fires on linked_source
		//   DELETE). The access_token is bound as a query PARAMETER (postgres.js sends $N,
		//   never interpolated into the query text) → a DB error cannot echo it (SC3-C4).
		const meta = JSON.stringify({ item_id: itemId });
		const label = `plaid:item:${itemId}`;
		const desc = `provider-sync linked_source credential (plaid item ${itemId})`;
		const db = dbFor(s.ownerUserId); // TenantBoundClient.forTenant re-validates the uuid.
		try {
			const sourceId = await db.withServiceRole(async (tx) => {
				// Re-admission dedup on (provider, external_connection_id) — the shipped
				// linked_source_provider_conn_uidx (015). For Plaid, external id = item_id.
				const existing = await tx<{ source_id: string; credential_secret_id: string | null; users_id: string }[]>`
					select source_id, credential_secret_id, users_id
					  from pfin.linked_source
					 where provider = 'plaid' and external_connection_id = ${itemId}`;
				const found = existing[0];
				if (found) {
					// SC3-C8: the matched row MUST belong to the admitting tenant. Under
					// service_role the dedup match is RLS-bypassed, so an item_id colliding with
					// ANOTHER tenant's source would otherwise let a re-admission rotate/UPDATE
					// that tenant's credential. Make the "item_id is globally unique so it's
					// safe" invariant EXPLICIT + fail-closed (parity with the revoke #1 guard).
					if (found.users_id !== s.ownerUserId) {
						throw new Error(
							'provider-sync admission: re-admission tenant mismatch — the existing ' +
								'source for this provider/connection belongs to a different tenant (fail-closed).'
						);
					}
					// Credential rotation on the SAME item (Plaid update-mode re-auth keeps
					// item_id). REUSE the same secret handle via vault.update_secret — swapping
					// to a new secret would orphan the old vault row (trigger fires on DELETE,
					// not UPDATE). UPDATE the existing row in place (linked_source is mutable).
					if (found.credential_secret_id) {
						await tx`select vault.update_secret(${found.credential_secret_id}::uuid, ${accessToken}, ${label}, ${desc})`;
					} else {
						// Was credential-less (manual/import) → mint + attach a secret in place.
						const created = await tx<{ secret_id: string }[]>`
							select vault.create_secret(${accessToken}, ${label}, ${desc}) as secret_id`;
						const secretId = created[0]?.secret_id;
						if (!secretId) throw new Error('provider-sync admission: vault.create_secret returned no id.');
						await tx`update pfin.linked_source set credential_secret_id = ${secretId} where source_id = ${found.source_id}`;
					}
					await tx`
						update pfin.linked_source
						   set connection_status = 'healthy',
						       provider_metadata = ${meta}::jsonb,
						       institution_id    = ${s.institutionId ?? null},
						       institution_name  = ${s.institutionName ?? null},
						       updated_at = now()
						 where source_id = ${found.source_id}`;
					return BigInt(found.source_id);
				}

				// New connection: atomic create_secret + INSERT (users_id bound in code —
				// auth.uid() is NULL under service_role, so the default won't stamp; §4).
				const created = await tx<{ secret_id: string }[]>`
					select vault.create_secret(${accessToken}, ${label}, ${desc}) as secret_id`;
				const secretId = created[0]?.secret_id;
				if (!secretId) throw new Error('provider-sync admission: vault.create_secret returned no id.');
				const inserted = await tx<{ source_id: string }[]>`
					insert into pfin.linked_source
						(provider, credential_secret_id, external_connection_id, provider_metadata,
						 connection_status, users_id, institution_id, institution_name)
					values
						('plaid', ${secretId}, ${itemId}, ${meta}::jsonb,
						 'healthy', ${s.ownerUserId}, ${s.institutionId ?? null}, ${s.institutionName ?? null})
					returning source_id`;
				const newId = inserted[0]?.source_id;
				if (!newId) throw new Error('provider-sync admission: INSERT linked_source returned no source_id.');
				return BigInt(newId);
			});
			// SC3-C4: token-free diagnostic; the return carries NO access_token.
			this.#log(`admitted plaid source source_id=${sourceId} (accounts=${accounts.length})`);
			return { sourceId, accounts };
		} finally {
			await db.end();
		}
	}

	// ── revoke() — provider revoke-then-delete (design §1.2 / §5; retention hard-gate). ──
	// Order is non-negotiable: read credential → Plaid /item/remove → THEN DELETE (fires
	// the vault-secret cleanup trigger). ABORT on revoke failure (SC3-C5) — never orphan a
	// live provider grant. ITEM_NOT_FOUND → proceed (idempotent / crash-safe). Tenant-scoped
	// (defense-in-depth): every statement filters users_id = ownerUserId.
	async revoke(ref: RevokeRef): Promise<void> {
		const dbFor = this.#requireDbFor();
		assertUuid(ref.ownerUserId, 'ownerUserId'); // fail-closed.
		const db = dbFor(ref.ownerUserId);
		try {
			// (1) Read credential via the service_role-only decrypt view (tenant-scoped).
			const sourceId = String(ref.sourceId); // postgres.js: bind bigint as text + ::bigint cast.
			const credential = await db.withServiceRole(async (tx) => {
				const rows = await tx<{ decrypted_credential: string }[]>`
					select decrypted_credential
					  from pfin.decrypted_source_credential
					 where source_id = ${sourceId}::bigint and users_id = ${ref.ownerUserId}`;
				return rows[0]?.decrypted_credential ?? null;
			});

			// (2) Provider revoke BEFORE delete. ABORT on failure (SC3-C5) → no DELETE runs
			//     → both the vault secret AND the row stay intact (retry-safe). A credential-
			//     less / already-gone source (no view row) skips straight to the idempotent
			//     tenant-scoped DELETE (0 rows if not owned → safe no-op).
			if (credential !== null) {
				try {
					await this.#client.itemRemove({ access_token: credential });
				} catch (err) {
					if (plaidErrorCode(err) !== 'ITEM_NOT_FOUND') {
						throw scrubbedPlaidError(err, 'item/remove'); // SC3-C4 + SC3-C5 abort.
					}
					// ITEM_NOT_FOUND → already revoked at provider → proceed (idempotent).
				}
			}

			// (3) Delete the row → fires fn_linked_source_cleanup_vault_secret (service_role
			//     holds DELETE on vault.secrets → secret cleaned).
			await db.withServiceRole(async (tx) => {
				await tx`delete from pfin.linked_source where source_id = ${sourceId}::bigint and users_id = ${ref.ownerUserId}`;
			});
			this.#log(`revoked plaid source source_id=${ref.sourceId}`);
		} finally {
			await db.end();
		}
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
