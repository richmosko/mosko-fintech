// SimpleFINAdapter.test.ts — normalization invariants + credential digest/splitAuth + fetch*
// delegation. Pure normalizers + injected fetch; no live SimpleFIN, no DB. (connect/revoke
// admission lives in SimpleFINAdapterAdmission.test.ts.)

import { describe, it, expect } from 'vitest';
import {
	SimpleFINAdapter,
	accessUrlDigest,
	epochToIsoDate,
	normalizeAccessUrlForDigest,
	normalizeAccountRef,
	normalizeBalance,
	normalizeHolding,
	normalizeTransaction,
	parseAccountsSet,
	splitAuth,
	toNum,
	type FetchLike,
	type FetchResponseLike
} from '../src/adapters/SimpleFINAdapter.js';
import { simplefinAccountSchema } from '../src/adapters/SimpleFINAdapter.js';
import * as fx from './fixtures/simplefin-payloads.js';

const acct = (raw: unknown) => simplefinAccountSchema.parse(raw);

describe('toNum / epochToIsoDate (SimpleFIN decimal-string + epoch coercion)', () => {
	it('coerces decimal strings + numbers; null-safe; rejects non-finite', () => {
		expect(toNum('3200.55')).toBe(3200.55);
		expect(toNum(-52.1)).toBe(-52.1);
		expect(toNum(null)).toBeNull();
		expect(toNum('')).toBeNull();
		expect(toNum('not-a-number')).toBeNull();
	});
	it('epoch seconds → ISO date', () => {
		expect(epochToIsoDate(1751500800)).toBe('2025-07-03');
		expect(epochToIsoDate(null)).toBeNull();
	});
});

describe('splitAuth (embedded basic-auth → Authorization header, never a credential-in-URL)', () => {
	it('lifts user:pass@ into a Basic header and strips it from the URL', () => {
		const { url, headers } = splitAuth(fx.ACCESS_URL);
		expect(url).not.toContain('user:pass@');
		expect(url).toContain('bridge.example.test/simplefin/access/token-xyz');
		expect(headers['Authorization']).toBe(`Basic ${Buffer.from('user:pass').toString('base64')}`);
	});
	it('leaves an auth-less URL unchanged (no header)', () => {
		const { url, headers } = splitAuth('https://bridge.example.test/simplefin/access/tok');
		expect(url).toContain('bridge.example.test');
		expect(headers['Authorization']).toBeUndefined();
	});
});

describe('F1 — malformed-URL parse leak vector (new URL() TypeError.input carries the credential)', () => {
	// A malformed-but-https Access URL: the space in the host makes `new URL()` throw
	// TypeError[ERR_INVALID_URL] whose `.input` = this whole string (incl. the credential).
	const BAD = 'https://SECRETUSER:SECRETPASS@exa mple.test/simplefin';
	it('splitAuth throws a SCRUBBED error — no credential in the message, NOT the raw TypeError', () => {
		let caught: unknown;
		try {
			splitAuth(BAD);
		} catch (e) {
			caught = e;
		}
		expect((caught as Error).message).toMatch(/SimpleFIN .*failed/);
		expect((caught as Error).message).not.toContain('SECRET');
		// The raw TypeError carries `.input` = the credential; our scrubbed Error must NOT.
		expect((caught as { input?: unknown }).input).toBeUndefined();
		expect(JSON.stringify(caught)).not.toContain('SECRET');
	});
	it('accessUrlDigest (normalizeAccessUrlForDigest) throws a SCRUBBED error — no credential leak', () => {
		let caught: unknown;
		try {
			accessUrlDigest(BAD);
		} catch (e) {
			caught = e;
		}
		expect((caught as Error).message).toMatch(/SimpleFIN .*failed/);
		expect((caught as Error).message).not.toContain('SECRET');
		expect((caught as { input?: unknown }).input).toBeUndefined();
	});
});

describe('external_connection_id digest (Sec SC-3 C4 — SHA-256 of the FULL normalized Access URL)', () => {
	it('KEEPS userinfo (basic-auth) + host + path; drops query/hash + trailing slash', () => {
		// C4: the basic-auth is part of the credential and MUST be in the digest input (not stripped).
		expect(normalizeAccessUrlForDigest(fx.ACCESS_URL)).toBe('https://user:pass@bridge.example.test/simplefin/access/token-xyz');
		expect(normalizeAccessUrlForDigest('https://u:p@h.test/a/b/?q=1#frag')).toBe('https://u:p@h.test/a/b');
	});
	it('is a 64-char hex digest, STABLE for the same URL (re-use → UPDATE path)', () => {
		const d = accessUrlDigest(fx.ACCESS_URL);
		expect(d).toMatch(/^[0-9a-f]{64}$/);
		expect(accessUrlDigest(fx.ACCESS_URL)).toBe(d); // deterministic
	});
	it('C4: INCLUDES the basic-auth — the REAL SimpleFIN shared-bridge-path form, diff creds → DIFFERENT digest', () => {
		// The load-bearing SC-3 C4 property, pinned to the REAL SimpleFIN URL shape: the bridge
		// PATH is SHARED across connections (…@bridge.simplefin.org/simplefin) and the per-
		// connection uniqueness lives ONLY in the basic-auth userinfo. An auth-stripped digest
		// would collide two connections on the GLOBAL (provider, external_connection_id) index →
		// a NEW connection mis-treated as a re-admission UPDATE (same-tenant credential/mapping
		// corruption) + a cross-tenant reject/timing leak. Full-URL digest = unique-per-credential.
		const connA = 'https://userA:secretTokenAAA@bridge.simplefin.org/simplefin';
		const connB = 'https://userB:secretTokenBBB@bridge.simplefin.org/simplefin'; // SAME host+path
		expect(accessUrlDigest(connA)).not.toBe(accessUrlDigest(connB));
		// And still: the SAME credential (cached re-use) → the SAME digest (re-admission UPDATE works).
		expect(accessUrlDigest(connA)).toBe(accessUrlDigest(connA));
	});
	it('a different per-claim path token → a DIFFERENT digest (fresh claim → new connection)', () => {
		expect(accessUrlDigest('https://u:p@bridge.test/access/tok-1')).not.toBe(accessUrlDigest('https://u:p@bridge.test/access/tok-2'));
	});
	it('the digest never contains the raw credential (one-way; safe on the RLS-scoped column)', () => {
		const d = accessUrlDigest(fx.ACCESS_URL);
		expect(d).not.toContain('user');
		expect(d).not.toContain('pass');
		expect(d).not.toContain('token-xyz');
	});
});

describe('normalizeAccountRef (SimpleFIN gives NO type → unknown; account-mapping → manual_other)', () => {
	it('maps id/name/currency; type=unknown, subtype=null', () => {
		expect(normalizeAccountRef(fx.acctChecking)).toEqual({
			providerAccountId: 'sfin_acct_chk',
			name: 'Everyday Checking',
			type: 'unknown',
			subtype: null,
			currency: 'USD'
		});
	});
	it('falls back name → id when name is absent', () => {
		expect(normalizeAccountRef({ id: 'sfin_x', currency: 'USD' }).name).toBe('sfin_x');
	});
});

describe('normalizeBalance (§ SimpleFIN balance is NATIVELY R-7 signed — no negation)', () => {
	it('passes a positive depository balance through', () => {
		const b = normalizeBalance(fx.acctChecking, '2026-07-18');
		expect(b.balance).toBe(3200.55);
		expect(b.currency).toBe('USD');
		expect(b.asOfDate).toBe('2025-07-03'); // from balance-date epoch
	});
	it('KEEPS a liability balance negative (no negation, unlike Plaid)', () => {
		// The load-bearing contrast with Plaid: SimpleFIN already signs the credit-card balance
		// negative, so the adapter must NOT flip it. A Math.abs()/negation regression flips this.
		expect(normalizeBalance(fx.acctCard, '2026-07-18').balance).toBe(-875.4);
	});
	it('falls back asOfDate → syncDate when balance-date is missing', () => {
		expect(normalizeBalance({ id: 'x', balance: '1', currency: 'USD' }, '2026-07-18').asOfDate).toBe('2026-07-18');
	});
});

describe('normalizeTransaction (§ SimpleFIN amount is NATIVELY R-7 signed — no ×−1 flip)', () => {
	it('passes a debit through as negative (no flip, contrast Plaid)', () => {
		const t = normalizeTransaction(fx.acctChecking.transactions[0], acct(fx.acctChecking), '2026-07-18');
		expect(t.amount).toBe(-52.1); // NOT +52.1 — a flip regression (Plaid-style) breaks this
		expect(t.quantity).toBe(0); // pure cash
		expect(t.providerTxnId).toBe('sfin_txn_debit');
		expect(t.vendor).toBe('Coffee Shop'); // payee
		expect(t.description).toBe('COFFEE SHOP #42');
		expect(t.providerCategory).toBe('5814'); // mcc (display hint only)
		expect(t.date).toBe('2025-07-02');
		expect(t.cancelsTxnId).toBeNull();
	});
	it('passes a credit through as positive; description falls back to memo', () => {
		const t = normalizeTransaction(
			{ id: 'x', posted: 1751328000, amount: '99.00', description: null, memo: 'ACH memo', payee: null, mcc: null },
			acct(fx.acctChecking),
			'2026-07-18'
		);
		expect(t.amount).toBe(99.0);
		expect(t.description).toBe('ACH memo'); // memo fallback
	});
});

describe('normalizeHolding (blank-symbol/cusip pre-validation → description-fallback, SELF-200)', () => {
	it('maps a real ticker holding with cost basis', () => {
		const h = normalizeHolding(fx.acctInvestment.holdings[0], acct(fx.acctInvestment), '2026-07-18');
		expect(h.symbol).toBe('VOO');
		expect(h.quantity).toBe(10);
		expect(h.marketValue).toBe(4500);
		expect(h.costBasis).toBe(4000);
		expect(h.assetType).toBe('equity'); // SimpleFIN gives no security-type → least-wrong bucket
		expect(h.asOfDate).toBe('2025-07-03');
	});
	it('routes a BLANK symbol + blank cusip to null/null (unvalued; description carries identity)', () => {
		const h = normalizeHolding(fx.acctInvestment.holdings[1], acct(fx.acctInvestment), '2026-07-18');
		expect(h.symbol).toBeNull(); // '   ' → null (not a garbage ticker)
		expect(h.cusip).toBeNull();
		expect(h.description).toBe('FIDELITY GOVERNMENT MONEY MARKET'); // the fallback identity
		expect(h.costBasis).toBeNull();
	});
});

describe('parseAccountsSet (surfaces errlist — a gappy institution must be VISIBLE)', () => {
	it('parses accounts + surfaces per-account errlist (not swallowed)', () => {
		const set = parseAccountsSet(fx.accountsSetWithErrlist);
		expect(set.accounts).toHaveLength(1);
		expect(set.errlist).toHaveLength(1);
	});
});

// ── fetch* delegate to the normalizers (injected fetch, no network) ──────────────
function jsonResponse(body: unknown): FetchResponseLike {
	return { ok: true, status: 200, text: async () => JSON.stringify(body), json: async () => body };
}
const source = { sourceId: 1n, accessToken: fx.ACCESS_URL, syncDate: '2026-07-18' };

describe('SimpleFINAdapter fetch* (injected fetch, delegate to normalizers)', () => {
	it('fetchBalances returns one BalanceDTO per account, credential lifted to a header', async () => {
		let seenUrl = '';
		let seenAuth: string | undefined;
		const fetchLike: FetchLike = async (url, init) => {
			seenUrl = url;
			seenAuth = init?.headers?.['Authorization'];
			return jsonResponse(fx.accountsSetClean);
		};
		const adapter = new SimpleFINAdapter(undefined, undefined, fetchLike);
		const b = await adapter.fetchBalances(source);
		expect(b).toHaveLength(3);
		expect(b.find((x) => x.providerAccountId === 'sfin_acct_card')?.balance).toBe(-875.4);
		// The Access URL's basic-auth was lifted to the Authorization header, never left in the URL.
		expect(seenUrl).not.toContain('user:pass@');
		expect(seenAuth).toBe(`Basic ${Buffer.from('user:pass').toString('base64')}`);
	});

	it('fetchHoldings flattens per-account holdings (2 positions on the one investment acct)', async () => {
		const adapter = new SimpleFINAdapter(undefined, undefined, async () => jsonResponse(fx.accountsSetClean));
		const h = await adapter.fetchHoldings(source);
		expect(h).toHaveLength(2);
		const symbols = h.map((x) => x.symbol);
		expect(symbols).toContain('VOO');
		expect(symbols).toContain(null); // the blank-symbol sweep → unvalued
	});

	it('fetchTransactions flattens cash txns + requests the trailing window', async () => {
		let qs = '';
		const adapter = new SimpleFINAdapter(undefined, undefined, async (url) => {
			qs = url;
			return jsonResponse(fx.accountsSetClean);
		});
		const t = await adapter.fetchTransactions(source, { start: '2026-04-01', end: '2026-07-18' });
		expect(t).toHaveLength(2); // both on the checking account
		expect(qs).toMatch(/start-date=\d+&end-date=\d+&pending=1/);
	});

	it('throws a SCRUBBED error on a non-ok /accounts (no credential/status leak beyond HTTP code)', async () => {
		const adapter = new SimpleFINAdapter(undefined, undefined, async () => ({
			ok: false,
			status: 403,
			text: async () => 'forbidden',
			json: async () => ({})
		}));
		await expect(adapter.fetchBalances(source)).rejects.toThrow(/SimpleFIN accounts failed \(HTTP 403\)/);
	});
});
