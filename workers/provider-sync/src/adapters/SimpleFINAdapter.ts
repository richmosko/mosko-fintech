// SimpleFINAdapter.ts — SimpleFIN (FALLBACK provider per ADR-027; banks/cards) → normalized
// DTOs + Vault credential admission. The 2nd ProviderAdapter impl (PlaidAdapter is the 1st).
//
// STRUCTURE mirrors PlaidAdapter: the NORMALIZERS are PURE functions (raw SimpleFIN payload
// → DTO) exported for unit testing WITHOUT the network or the DB. The fetch* methods are
// thin: they GET {access_url}/accounts and delegate to the normalizers. connect()/revoke()
// run the SAME inline service_role Vault admission as Plaid (vault.create_secret + INSERT
// linked_source), differing only in the provider "exchange" (SimpleFIN claim) + the lack of
// a provider-side revoke endpoint.
//
// ── SimpleFIN CREDENTIAL MODEL (SC-3; ratified §2-(a)) ─────────────────────────────────
//   setup-token → (base64-decode) → claim URL → POST → the ACCESS URL. The Access URL is a
//   long-lived REUSABLE READ credential that may embed basic-auth (https://user:pass@host/…).
//   It is an SD-03-class bearer credential (RT-02), handled IDENTICALLY to the Plaid
//   access_token: it lands ONLY in vault.secrets (ciphertext); linked_source holds the uuid
//   handle (withheld from `authenticated`); it is NEVER logged / returned / on a client-
//   readable column; it is bound as a query PARAMETER (postgres.js sends $N, never string-
//   interpolated) so a DB error cannot echo it, and every provider/HTTP error is SCRUBBED
//   (the whole error object is discarded — its message/url may carry the credential).
//
//   external_connection_id = the SHA-256 hex digest of the FULL normalized Access URL
//   (scheme + basic-auth userinfo + host + path; only query/hash dropped) — Sec SC-3 C4.
//   The digest MUST include the basic-auth: auth-stripped host+path is collision-prone (two
//   tenants behind the SAME SimpleFIN bridge would digest identically → the GLOBAL
//   unique(provider, external_connection_id) index rejects the 2nd admission + leaks a
//   cross-tenant signal). A full-URL digest is UNIQUE-per-credential + stable (re-admit-in-
//   place) + leak-safe (external_connection_id is RLS-scoped to the owner + anon-denied per
//   015, and SHA-256 is preimage-resistant over the high-entropy machine-generated secret —
//   C5). SimpleFIN has no stable provider connection id (Plaid's item_id analogue), so the
//   digest plays that role for the shipped dedup index (015): re-admitting the SAME cached
//   Access URL → same digest → the re-admission UPDATE path (mirrors Plaid item_id); a fresh
//   setup-token claim → a new Access URL (new random credential) → a new digest → a new
//   connection (the accepted duplicate edge, identical to Plaid's fresh-Link edge).
//
// ── SIGN CONVENTIONS (adapter-contract invariants; CONTRAST with Plaid) ────────────────
//   SimpleFIN natively signs values per the R-7 contract already, UNLIKE Plaid:
//     • balance : SimpleFIN returns a SIGNED decimal (negative for liabilities/owed —
//       credit cards, loans). This is ALREADY R-7 (liabilities negative) → PASS THROUGH,
//       NO negation (Plaid returns credit balances positive and the adapter must negate).
//     • amount  : SimpleFIN txn amount is SIGNED (negative = debit/outflow, positive =
//       credit/inflow). ALREADY R-7 (positive=inflow) → PASS THROUGH, NO ×−1 flip
//       (Plaid amount is INVERTED positive=out → Plaid adapter flips; SimpleFIN does NOT).
//
// ── EMPIRICAL SHAPE (temp/simplefin-test.mjs + temp/aggregator-strategy-memo.md) ───────
//   GET {access_url}/accounts?start-date&end-date&pending=1 (epoch seconds; ≤~90-day window)
//   → { accounts[], errors[], errlist[] }. Per account: { id, name, currency, balance,
//   available-balance, balance-date, transactions[], holdings[], org{name,domain} }.
//   NO account `type` field (SimpleFIN gives no type signal → refs carry type='unknown';
//   the account-mapping slice's fallback maps that to 'manual_other', corrected at SELF-212).
//   Txn fields: { id, posted, amount, description, payee, memo, transacted_at, mcc }.
//   Holding fields: { symbol|ticker, description, shares, market_value, cost_basis,
//   purchase_price }; blank symbols on sweeps → description-fallback (SELF-200 unvalued).
//   Holdings + balances are reliable; transactions are gappy for some institutions — per-
//   account failures surface in errlist[] (surfaced, NOT swallowed, for the sync-audit detail).

import { createHash } from 'node:crypto';
import { z } from 'zod';
import type { Tx } from '../db/TenantBoundClient.js';
import type { AdmissionDb, AdmissionDbFactory, AdmissionLogger } from './PlaidAdapter.js';
import type {
	BalanceDTO,
	DateRange,
	HoldingDTO,
	ProviderAccountRef,
	ProviderAdapter,
	RevokeRef,
	SourceRef,
	TransactionDTO
} from './ProviderAdapter.js';

// ── Defensive Zod shapes for the SimpleFIN fields we read (harden the normalize boundary —
//    external-API input discipline). Non-`.strict()`: the /accounts payload carries fields we
//    intentionally ignore; we validate ONLY the fields we consume + reject a malformed value
//    rather than coerce it. (The connect() SETUP shape IS `.strict()` — mass-assignment. §Lock14.)
const numLike = z.union([z.number(), z.string()]); // SimpleFIN sends decimals as strings.
const numLikeOrNull = numLike.nullable().optional();

export const simplefinOrgSchema = z
	.object({
		name: z.string().nullable().optional(),
		domain: z.string().nullable().optional()
	})
	.nullable()
	.optional();

export const simplefinHoldingSchema = z.object({
	id: z.string().nullable().optional(),
	symbol: z.string().nullable().optional(),
	ticker: z.string().nullable().optional(),
	cusip: z.string().nullable().optional(),
	isin: z.string().nullable().optional(),
	description: z.string().nullable().optional(),
	shares: numLikeOrNull,
	market_value: numLikeOrNull,
	cost_basis: numLikeOrNull,
	purchase_price: numLikeOrNull,
	currency: z.string().nullable().optional()
});

export const simplefinTxnSchema = z.object({
	id: z.string(),
	posted: numLikeOrNull,
	transacted_at: numLikeOrNull,
	amount: numLike,
	description: z.string().nullable().optional(),
	payee: z.string().nullable().optional(),
	memo: z.string().nullable().optional(),
	mcc: z.string().nullable().optional()
});

export const simplefinAccountSchema = z.object({
	id: z.string(),
	name: z.string().nullable().optional(),
	currency: z.string().nullable().optional(),
	balance: numLikeOrNull,
	'available-balance': numLikeOrNull,
	'balance-date': numLikeOrNull,
	org: simplefinOrgSchema,
	holdings: z.array(z.unknown()).nullable().optional(),
	transactions: z.array(z.unknown()).nullable().optional()
});

export const simplefinAccountsSetSchema = z.object({
	accounts: z.array(z.unknown()).default([]),
	errors: z.array(z.unknown()).default([]),
	errlist: z.array(z.unknown()).default([])
});

export type SimplefinAccount = z.infer<typeof simplefinAccountSchema>;

// ── Helpers ────────────────────────────────────────────────────────────────────

const blank = (s: string | null | undefined): boolean => s === null || s === undefined || s.trim() === '';

/** Coerce a SimpleFIN numeric (number | decimal-string) → number; null-safe. Returns null for
 *  a missing/blank/non-finite value (never NaN into a DTO — the downstream CHECKs reject NaN). */
export function toNum(v: number | string | null | undefined): number | null {
	if (v === null || v === undefined || (typeof v === 'string' && v.trim() === '')) return null;
	const n = typeof v === 'number' ? v : Number(v);
	return Number.isFinite(n) ? n : null;
}

/** Epoch-seconds → ISO date (yyyy-mm-dd), null-safe. */
export function epochToIsoDate(epoch: number | string | null | undefined): string | null {
	const n = toNum(epoch);
	if (n === null) return null;
	return new Date(n * 1000).toISOString().slice(0, 10);
}

/**
 * Split a URL that may embed basic-auth (https://user:pass@host/path) into { url, headers }
 * so fetch authenticates via the Authorization header (never a credential-in-URL that could
 * land in a log/referrer). Mirrors temp/simplefin-test.mjs splitAuth.
 */
export function splitAuth(rawUrl: string): { url: string; headers: Record<string, string> } {
	// F1/C3: Node's `new URL()` throws TypeError[ERR_INVALID_URL] whose `.input` is the FULL
	// offending URL (the raw credential). Catch + re-throw SCRUBBED so a malformed-but-https
	// Access URL (a hostile/buggy Bridge could return one) can never propagate an unscrubbed
	// error carrying the credential.
	let u: URL;
	try {
		u = new URL(rawUrl);
	} catch {
		throw scrubbedSimplefinError('access url parse');
	}
	const headers: Record<string, string> = {};
	if (u.username || u.password) {
		const creds = Buffer.from(`${decodeURIComponent(u.username)}:${decodeURIComponent(u.password)}`).toString('base64');
		headers['Authorization'] = `Basic ${creds}`;
		u.username = '';
		u.password = '';
	}
	return { url: u.toString(), headers };
}

/**
 * Normalize an Access URL for the external_connection_id digest — Sec SC-3 C4. KEEP the full
 * URL INCLUDING the basic-auth userinfo (it is part of the high-entropy machine-generated
 * credential; stripping it would collide two tenants behind the same bridge host+path). Only
 * the query/hash are dropped (the claim returns a base URL; /accounts query params are added
 * at fetch time, not part of the stored credential identity) + a trailing slash (stability).
 * Same full URL (cached re-use) → same digest → re-admission UPDATE; a fresh claim → a new
 * random credential → a different digest → a new connection.
 */
export function normalizeAccessUrlForDigest(accessUrl: string): string {
	// F1/C3: same as splitAuth — a malformed URL's TypeError.input is the raw credential; catch
	// + re-throw scrubbed so the digest path can never leak it either.
	let u: URL;
	try {
		u = new URL(accessUrl);
	} catch {
		throw scrubbedSimplefinError('access url parse');
	}
	u.search = '';
	u.hash = '';
	// Keep scheme + userinfo (basic-auth) + host + path; drop a trailing slash for stability.
	return u.toString().replace(/\/$/, '');
}

/** external_connection_id = SHA-256 hex of the FULL normalized Access URL (Sec SC-3 C4). One-
 *  way (preimage-resistant over the high-entropy secret — C5), so it is safe on the RLS-scoped
 *  external_connection_id column; the raw URL itself NEVER lands on a client-readable column (C1). */
export function accessUrlDigest(accessUrl: string): string {
	return createHash('sha256').update(normalizeAccessUrlForDigest(accessUrl)).digest('hex');
}

// ── PURE NORMALIZERS (exported for unit testing) ─────────────────────────────────

/**
 * Account ref (connect() mapping output). SimpleFIN gives NO account type/subtype signal,
 * so type='unknown' (the account-mapping fallback maps that to 'manual_other', corrected at
 * SELF-212); name falls back to the account id.
 */
export function normalizeAccountRef(rawAccount: unknown): ProviderAccountRef {
	const a = simplefinAccountSchema.parse(rawAccount);
	return {
		providerAccountId: a.id,
		name: a.name ?? a.id,
		type: 'unknown', // SimpleFIN carries no type field (empirical §probe) → refs are un-typed.
		subtype: null,
		currency: a.currency ?? 'USD'
	};
}

/**
 * Account balance → BalanceDTO. SimpleFIN `balance` is NATIVELY R-7 SIGNED (negative for
 * liabilities) → PASS THROUGH, no negation (contrast Plaid). balance-date → asOfDate
 * (fallback: syncDate). A missing/non-finite balance → 0 (a present-but-unparseable balance
 * is a data edge, not a crash).
 */
export function normalizeBalance(rawAccount: unknown, syncDate: string): BalanceDTO {
	const a = simplefinAccountSchema.parse(rawAccount);
	return {
		providerAccountId: a.id,
		balance: toNum(a.balance) ?? 0, // already R-7 signed — no flip.
		currency: a.currency ?? 'USD',
		asOfDate: epochToIsoDate(a['balance-date']) ?? syncDate
	};
}

/**
 * A holding row → HoldingDTO with the blank-symbol/cusip PRE-VALIDATION (backlog G-item /
 * SC-4 / SELF-200): a blank symbol AND blank cusip → symbol=null + cusip=null so the shipped
 * resolution.ts routes it through the description-fallback (security_id NULL / unvalued) rather
 * than minting a garbage security from an empty ticker. `description` carries the identity in
 * that case. assetType defaults to 'equity' (SimpleFIN gives no security-type signal — the
 * least-wrong market bucket; identical to the shipped Plaid/collectResolvableAssets default).
 */
export function normalizeHolding(rawHolding: unknown, account: SimplefinAccount, syncDate: string): HoldingDTO {
	const h = simplefinHoldingSchema.parse(rawHolding);
	const rawSymbol = h.symbol ?? h.ticker ?? null;
	const symbol = blank(rawSymbol) ? null : rawSymbol;
	const cusip = blank(h.cusip) ? null : (h.cusip ?? null);
	return {
		providerAccountId: account.id,
		symbol,
		cusip,
		isin: blank(h.isin) ? null : (h.isin ?? null),
		description: blank(h.description) ? null : (h.description ?? null),
		assetType: 'equity',
		quantity: toNum(h.shares) ?? 0,
		marketValue: toNum(h.market_value) ?? 0,
		costBasis: toNum(h.cost_basis),
		currency: h.currency ?? account.currency ?? 'USD',
		asOfDate: epochToIsoDate(account['balance-date']) ?? syncDate
	};
}

/**
 * A bank/card transaction → TransactionDTO. SimpleFIN `amount` is NATIVELY R-7 SIGNED
 * (negative=debit, positive=credit) → PASS THROUGH, no ×−1 (contrast Plaid's inverted amount).
 * SimpleFIN standard txns are pure cash → quantity 0, no security identity (017
 * qty_requires_security CHECK). posted (else transacted_at) → date. mcc → providerCategory
 * (display hint only, R-18). vendor ← payee; description ← description|memo fallback.
 */
export function normalizeTransaction(rawTxn: unknown, account: SimplefinAccount, syncDate: string): TransactionDTO {
	const t = simplefinTxnSchema.parse(rawTxn);
	return {
		providerAccountId: account.id,
		providerTxnId: t.id,
		cancelsTxnId: null, // SimpleFIN has no correction/cancel model.
		date: epochToIsoDate(t.posted ?? t.transacted_at) ?? syncDate,
		amount: toNum(t.amount) ?? 0, // already R-7 signed — no flip.
		quantity: 0, // pure cash (SimpleFIN standard txns carry no share quantity).
		symbol: null,
		cusip: null,
		price: null,
		costBasis: null,
		vendor: blank(t.payee) ? null : (t.payee ?? null),
		description: (blank(t.description) ? null : t.description) ?? (blank(t.memo) ? null : t.memo) ?? null,
		providerCategory: blank(t.mcc) ? null : (t.mcc ?? null),
		currency: account.currency ?? 'USD'
	};
}

/** Parse the /accounts set (accounts[] + errors[] + errlist[]); surface errlist for the
 *  sync-audit detail (per-account SimpleFIN failures — a gappy institution must be VISIBLE,
 *  not a silent zero). */
export function parseAccountsSet(raw: unknown): { accounts: SimplefinAccount[]; errors: unknown[]; errlist: unknown[] } {
	const set = simplefinAccountsSetSchema.parse(raw);
	const accounts = set.accounts.map((a) => simplefinAccountSchema.parse(a));
	return { accounts, errors: set.errors, errlist: set.errlist };
}

// ── HTTP seam (injectable for tests — no live SimpleFIN) ─────────────────────────

export interface FetchResponseLike {
	ok: boolean;
	status: number;
	text(): Promise<string>;
	json(): Promise<unknown>;
}
export type FetchLike = (
	url: string,
	init?: { method?: string; headers?: Record<string, string> }
) => Promise<FetchResponseLike>;

/** connect() setup shape — `.strict()` (SC mass-assignment prevention, Lock 14 mod #1). */
const connectSetupSchema = z
	.object({
		provider: z.literal('simplefin'),
		setupToken: z.string().min(1),
		ownerUserId: z.string().min(1),
		institutionName: z.string().optional()
	})
	.strict();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function assertUuid(value: string, label: string): void {
	if (!UUID_RE.test(value)) {
		throw new Error(`provider-sync admission: ${label} must be a well-formed uuid (fail-closed).`);
	}
}

/**
 * Build a SCRUBBED error for a failed SimpleFIN op. The raw error (fetch/URL error, or a
 * response body) may carry the Access URL / claim URL / basic-auth — discard the whole object
 * and keep ONLY a non-sensitive op label (+ HTTP status when we have it). Mirrors Plaid's
 * scrubbedPlaidError discipline (SC3-C4) extended to SimpleFIN.
 */
export function scrubbedSimplefinError(op: string, status?: number): Error {
	return new Error(`SimpleFIN ${op} failed${status !== undefined ? ` (HTTP ${status})` : ''}`);
}

// ── The adapter ──────────────────────────────────────────────────────────────────

export class SimpleFINAdapter implements ProviderAdapter {
	readonly provider = 'simplefin' as const;
	readonly #dbFor: AdmissionDbFactory | undefined;
	readonly #logger: AdmissionLogger | undefined;
	readonly #fetch: FetchLike;
	/** errlist[] from the most recent /accounts GET (gappy-institution per-account failures).
	 *  Surfaced (not swallowed) so the scheduler can land it in linked_source_sync_audit.detail
	 *  (design §8 Sec risk #3). These are NON-credential provider error entries from a 200 body;
	 *  credential-bearing failures throw a scrubbedSimplefinError instead and never reach here. */
	#lastErrlist: unknown[] = [];

	/**
	 * @param dbFor  tenant-bound service_role DB factory — REQUIRED for connect()/revoke();
	 *               fetch* paths do not use it. Same seam as PlaidAdapter (the factory, not this
	 *               file, constructs the raw client → the TBC-node fence stays satisfied).
	 * @param logger optional token-free diagnostic logger (never receives the Access URL).
	 * @param fetchLike injectable fetch (defaults to global fetch) — tests inject a mock.
	 */
	constructor(dbFor?: AdmissionDbFactory, logger?: AdmissionLogger, fetchLike?: FetchLike) {
		this.#dbFor = dbFor;
		this.#logger = logger;
		this.#fetch = fetchLike ?? (globalThis.fetch as unknown as FetchLike);
	}

	#requireDbFor(): AdmissionDbFactory {
		if (!this.#dbFor) {
			throw new Error(
				'SimpleFINAdapter credential admission (connect/revoke) requires a dbFor factory; ' +
					'construct with new SimpleFINAdapter(dbFor).'
			);
		}
		return this.#dbFor;
	}

	#log(message: string): void {
		this.#logger?.(message);
	}

	/** GET {access_url}/accounts[+qs] → the parsed /accounts set. Splits embedded basic-auth to
	 *  the Authorization header (never a credential-in-URL leak); scrubs every failure. */
	async #getAccounts(accessUrl: string, qs = ''): Promise<{ accounts: SimplefinAccount[]; errors: unknown[]; errlist: unknown[] }> {
		const { url, headers } = splitAuth(`${accessUrl.replace(/\/$/, '')}/accounts${qs}`);
		let resp: FetchResponseLike;
		try {
			resp = await this.#fetch(url, { headers });
		} catch {
			throw scrubbedSimplefinError('accounts'); // network/URL error may carry the credential.
		}
		if (!resp.ok) throw scrubbedSimplefinError('accounts', resp.status);
		let body: unknown;
		try {
			body = await resp.json();
		} catch {
			throw scrubbedSimplefinError('accounts (malformed body)', resp.status);
		}
		const set = parseAccountsSet(body);
		this.#lastErrlist = set.errlist; // capture gappy-institution signal for the sync audit
		return set;
	}

	/** errlist[] (gappy-institution per-account failures) from the most recent fetch* call —
	 *  for linked_source_sync_audit.detail (design §8 Sec risk #3; surfaced, never swallowed).
	 *  Empty until a fetch* has run. */
	getLastErrlist(): unknown[] {
		return [...this.#lastErrlist];
	}

	/** The ~89-day trailing window (SimpleFIN caps at ~90) + pending=1, epoch seconds. syncDate
	 *  anchors "now" (kept out of the DTO grain — a network-request concern). */
	#txnWindowQs(syncDate: string): string {
		const end = Math.floor(new Date(`${syncDate}T00:00:00Z`).getTime() / 1000);
		const start = end - 89 * 24 * 60 * 60;
		return `?start-date=${start}&end-date=${end}&pending=1`;
	}

	async fetchBalances(source: SourceRef): Promise<BalanceDTO[]> {
		const { accounts } = await this.#getAccounts(source.accessToken);
		return accounts.map((a) => normalizeBalance(a, source.syncDate));
	}

	async fetchHoldings(source: SourceRef): Promise<HoldingDTO[]> {
		const { accounts } = await this.#getAccounts(source.accessToken);
		const out: HoldingDTO[] = [];
		for (const a of accounts) {
			for (const h of a.holdings ?? []) out.push(normalizeHolding(h, a, source.syncDate));
		}
		return out;
	}

	async fetchTransactions(source: SourceRef, _range: DateRange): Promise<TransactionDTO[]> {
		// SimpleFIN filters transactions by the query window (not a cursor); use the full trailing
		// window + the shipped (source_provider, provider_txn_id) dedup (ratified Q3 full-window).
		const { accounts } = await this.#getAccounts(source.accessToken, this.#txnWindowQs(source.syncDate));
		const out: TransactionDTO[] = [];
		for (const a of accounts) {
			for (const t of a.transactions ?? []) out.push(normalizeTransaction(t, a, source.syncDate));
		}
		return out;
	}

	// ── connect() — SimpleFIN claim + Vault credential admission (§1.1; inherits ADR-027 (s)/(u)).
	async connect(setup: unknown): Promise<{ sourceId: bigint; accounts: ProviderAccountRef[] }> {
		const dbFor = this.#requireDbFor();
		const s = connectSetupSchema.parse(setup); // `.strict()` — mass-assignment prevention.
		assertUuid(s.ownerUserId, 'ownerUserId'); // fail-closed BEFORE any claim/admission.

		// (1) The SimpleFIN "exchange": base64-decode the setup token → claim URL → POST → Access URL.
		//     This is the ONLY place the raw Access URL is in process memory. One-time claim (403 if
		//     already claimed — the short-lived-single-use analogue of Plaid's public_token).
		let claimUrl: string;
		try {
			claimUrl = Buffer.from(s.setupToken, 'base64').toString('utf8').trim();
			// eslint-disable-next-line no-new
			new URL(claimUrl); // sanity: it must decode to a URL.
		} catch {
			throw new Error('SimpleFIN admission: setup token did not decode to a claim URL (fail-closed).');
		}
		let accessUrl: string;
		try {
			// C2: splitAuth BEFORE the request so any embedded basic-auth goes to a header, never a
			// credential-in-URL that a client could echo into a log. (Claim URLs normally carry no
			// userinfo; this is uniform defense-in-depth.)
			const { url: claimReqUrl, headers: claimHeaders } = splitAuth(claimUrl);
			const resp = await this.#fetch(claimReqUrl, { method: 'POST', headers: claimHeaders });
			if (!resp.ok) throw scrubbedSimplefinError('claim', resp.status); // 403 = already claimed.
			accessUrl = (await resp.text()).trim();
		} catch (err) {
			// C3: discard the raw error (it may echo the request URL/headers) — keep only a scrubbed
			// op label. Re-throw our own already-scrubbed SimpleFIN errors unchanged.
			throw err instanceof Error && err.message.startsWith('SimpleFIN') ? err : scrubbedSimplefinError('claim');
		}
		if (!accessUrl || !/^https?:\/\//i.test(accessUrl)) {
			throw new Error('SimpleFIN admission: claim did not return an Access URL (fail-closed).');
		}

		// Account refs (no pfin.account write — account-mapping is the shipped separate slice).
		const { accounts: rawAccounts } = await this.#getAccounts(accessUrl);
		const accounts = rawAccounts.map((a) => normalizeAccountRef(a));

		// external_connection_id = SHA-256 digest of the FULL normalized Access URL (SC-3 C4).
		const externalConnectionId = accessUrlDigest(accessUrl);
		// C1: provider_metadata is CLIENT-READABLE (015) → keep it strictly credential-free. The
		// Access URL / any auth-bearing fragment NEVER lands here (the digest already lives in the
		// dedicated external_connection_id column; nothing credential-derived belongs in metadata).
		const meta = '{}';
		// The vault.secrets label is NOT client-readable; a digest prefix keys it (no raw URL).
		const label = `simplefin:conn:${externalConnectionId.slice(0, 16)}`;
		const desc = 'provider-sync linked_source credential (simplefin access url)';

		// (2) Admission — ONE service_role transaction (Decision 1 privileged-context-write),
		//     mirroring Plaid connect(). The Access URL is bound as a query PARAMETER (never
		//     interpolated) → a DB error cannot echo it (SC3-C4).
		const db = dbFor(s.ownerUserId); // TenantBoundClient.forTenant re-validates the uuid.
		try {
			const sourceId = await db.withServiceRole(async (tx) => {
				// Re-admission dedup on (provider, external_connection_id) — the shipped
				// linked_source_provider_conn_uidx (015). For SimpleFIN, external id = the digest.
				const existing = await tx<{ source_id: string; credential_secret_id: string | null; users_id: string }[]>`
					select source_id, credential_secret_id, users_id
					  from pfin.linked_source
					 where provider = 'simplefin' and external_connection_id = ${externalConnectionId}`;
				const found = existing[0];
				if (found) {
					// SC3-C8 parity: the matched row MUST belong to the admitting tenant (under
					// service_role the dedup match is RLS-bypassed). Fail-closed on a cross-tenant
					// collision so a re-admission cannot rotate another tenant's credential.
					if (found.users_id !== s.ownerUserId) {
						throw new Error(
							'provider-sync admission: re-admission tenant mismatch — the existing source for ' +
								'this provider/connection belongs to a different tenant (fail-closed).'
						);
					}
					// Credential rotation on the SAME connection: REUSE the secret handle via
					// vault.update_secret (a new secret would orphan the old vault row — the cleanup
					// trigger fires on DELETE, not UPDATE). A credential-less row → mint + attach in place.
					if (found.credential_secret_id) {
						await tx`select vault.update_secret(${found.credential_secret_id}::uuid, ${accessUrl}, ${label}, ${desc})`;
					} else {
						const created = await tx<{ secret_id: string }[]>`
							select vault.create_secret(${accessUrl}, ${label}, ${desc}) as secret_id`;
						const secretId = created[0]?.secret_id;
						if (!secretId) throw new Error('provider-sync admission: vault.create_secret returned no id.');
						await tx`update pfin.linked_source set credential_secret_id = ${secretId} where source_id = ${found.source_id}`;
					}
					await tx`
						update pfin.linked_source
						   set connection_status = 'healthy',
						       provider_metadata = ${meta}::jsonb,
						       institution_name  = ${s.institutionName ?? null},
						       updated_at = now()
						 where source_id = ${found.source_id}`;
					return BigInt(found.source_id);
				}

				// New connection: atomic create_secret + INSERT (users_id bound in code — auth.uid()
				// is NULL under service_role, so the default won't stamp; Decision 1 (d) / §8).
				const created = await tx<{ secret_id: string }[]>`
					select vault.create_secret(${accessUrl}, ${label}, ${desc}) as secret_id`;
				const secretId = created[0]?.secret_id;
				if (!secretId) throw new Error('provider-sync admission: vault.create_secret returned no id.');
				const inserted = await tx<{ source_id: string }[]>`
					insert into pfin.linked_source
						(provider, credential_secret_id, external_connection_id, provider_metadata,
						 connection_status, users_id, institution_name)
					values
						('simplefin', ${secretId}, ${externalConnectionId}, ${meta}::jsonb,
						 'healthy', ${s.ownerUserId}, ${s.institutionName ?? null})
					returning source_id`;
				const newId = inserted[0]?.source_id;
				if (!newId) throw new Error('provider-sync admission: INSERT linked_source returned no source_id.');
				return BigInt(newId);
			});
			// Token-free diagnostic; the return carries NO Access URL.
			this.#log(`admitted simplefin source source_id=${sourceId} (accounts=${accounts.length})`);
			return { sourceId, accounts };
		} finally {
			await db.end();
		}
	}

	// ── revoke() — LOCAL-DELETE ONLY (§1.3). ─────────────────────────────────────────
	// SimpleFIN has NO provider-side revoke endpoint (no /item/remove analogue): revocation
	// at the Bridge is user-side (the user deletes the Access URL there). So revoke() destroys
	// ONLY the local credential — tenant-scoped DELETE linked_source (fires the shipped
	// fn_linked_source_cleanup_vault_secret → the Vault secret is deleted). No provider call to
	// make, so no decrypt-view read is needed and NO abort-on-revoke-failure hard-gate applies
	// (contrast Plaid, which must revoke at the provider BEFORE delete).
	//
	// DOCUMENTED RESIDUAL (Sec is ruling on it — §8 #3): the local credential is destroyed but
	// the grant STAYS LIVE at SimpleFIN until the user revokes it at the Bridge. This is a
	// documented product limitation surfaced to the user, NOT a code gap — there is no endpoint
	// to close the grant programmatically.
	async revoke(ref: RevokeRef): Promise<void> {
		const dbFor = this.#requireDbFor();
		assertUuid(ref.ownerUserId, 'ownerUserId'); // fail-closed.
		const db = dbFor(ref.ownerUserId);
		try {
			const sourceId = String(ref.sourceId); // postgres.js: bind bigint as text + ::bigint cast.
			await db.withServiceRole(async (tx) => {
				// Tenant-scoped: a wrong/foreign source_id deletes 0 rows (safe no-op), never another
				// tenant's source. Fires the Vault-secret cleanup trigger.
				await tx`delete from pfin.linked_source where source_id = ${sourceId}::bigint and users_id = ${ref.ownerUserId}`;
			});
			this.#log(`revoked simplefin source source_id=${ref.sourceId} (local-delete only; grant stays live at the Bridge)`);
		} finally {
			await db.end();
		}
	}
}

// Re-export the shared admission DB seam types for callers wiring SimpleFINAdapter.
export type { AdmissionDb, AdmissionDbFactory, AdmissionLogger } from './PlaidAdapter.js';
