// SimpleFINAdapterAdmission.test.ts — connect()/revoke() credential-admission slice (SC-3).
// Mocked fetch (claim + /accounts) + mocked DB (fixture-style; NO live SimpleFIN, NO live
// Postgres). Covers: happy-path admission (claim → atomic create_secret + INSERT), re-admission
// UPDATE-same-handle, tenant-mismatch fail-closed, uuid fail-closed, `.strict()` mass-assignment,
// the Access-URL-never-leaks property, and local-delete-only revoke (no provider call).

import { describe, it, expect, vi } from 'vitest';
import { SimpleFINAdapter, SetupTokenInvalidError, accessUrlDigest, type AdmissionDb, type FetchLike } from '../src/adapters/SimpleFINAdapter.js';
import * as fx from './fixtures/simplefin-payloads.js';

const VALID_UUID = '11111111-1111-4111-8111-111111111111';
const ACCESS_URL = fx.ACCESS_URL; // the live bearer credential — must NEVER leak.

// ── A recording tagged-template tx mock (postgres.js call shape). ────────────────
interface TxCall {
	text: string;
	params: unknown[];
}
interface Handler {
	match: RegExp;
	rows?: (params: unknown[]) => unknown[];
}
function makeTx(handlers: Handler[]): { tx: unknown; calls: TxCall[] } {
	const calls: TxCall[] = [];
	const tx = (strings: TemplateStringsArray, ...params: unknown[]): Promise<unknown[]> => {
		const text = strings.join('?');
		calls.push({ text, params });
		for (const h of handlers) if (h.match.test(text)) return Promise.resolve(h.rows ? h.rows(params) : []);
		return Promise.resolve([]);
	};
	return { tx, calls };
}

function makeDb(tx: unknown): { db: AdmissionDb; endSpy: ReturnType<typeof vi.fn> } {
	const endSpy = vi.fn(async () => {});
	const db: AdmissionDb = {
		withServiceRole: (<T>(fn: (t: unknown) => Promise<T>) => fn(tx)) as AdmissionDb['withServiceRole'],
		end: endSpy
	};
	return { db, endSpy };
}

/** A fetch mock: POST <claim URL> → the Access URL (text); GET .../accounts → the accounts set. */
function admissionFetch(accessUrl = ACCESS_URL, accountsSet: unknown = fx.accountsSetClean): FetchLike {
	return async (url, init) => {
		if (init?.method === 'POST') {
			return { ok: true, status: 200, text: async () => accessUrl, json: async () => ({}) };
		}
		return { ok: true, status: 200, text: async () => JSON.stringify(accountsSet), json: async () => accountsSet };
	};
}

describe('connect() — happy-path admission (new connection)', () => {
	it('claims, atomically create_secret + INSERTs (users_id + digest bound), returns refs (no pfin.account write)', async () => {
		const { tx, calls } = makeTx([
			{ match: /source_id, credential_secret_id/, rows: () => [] }, // not found → new
			{ match: /vault\.create_secret/, rows: () => [{ secret_id: 'sec-new-1' }] },
			{ match: /insert into\s+pfin\.linked_source/, rows: () => [{ source_id: '55' }] }
		]);
		const { db } = makeDb(tx);
		const dbFor = vi.fn(() => db);
		const adapter = new SimpleFINAdapter(dbFor, undefined, admissionFetch());

		const result = await adapter.connect({
			provider: 'simplefin',
			setupToken: fx.SETUP_TOKEN,
			ownerUserId: VALID_UUID,
			institutionName: 'Capital One'
		});

		expect(result.sourceId).toBe(55n);
		expect(result.accounts).toHaveLength(3); // checking + card + investment
		expect(dbFor).toHaveBeenCalledWith(VALID_UUID); // tenant bound in code (§8).
		// create_secret received the ACCESS URL (the credential lands ONLY in Vault).
		const createCall = calls.find((c) => /vault\.create_secret/.test(c.text));
		expect(createCall?.params).toContain(ACCESS_URL);
		// INSERT bound users_id = ownerUserId AND external_connection_id = the digest.
		const insertCall = calls.find((c) => /insert into\s+pfin\.linked_source/.test(c.text));
		expect(insertCall?.params).toContain(VALID_UUID);
		expect(insertCall?.params).toContain(accessUrlDigest(ACCESS_URL));
		// No pfin.account write in this slice (account-mapping is separate).
		expect(calls.some((c) => /insert into\s+pfin\.account/.test(c.text))).toBe(false);
	});
});

describe('connect() — re-admission (same digest) UPDATEs the SAME secret handle', () => {
	it('calls vault.update_secret on the existing handle, does NOT mint a new secret', async () => {
		const { tx, calls } = makeTx([
			{
				match: /source_id, credential_secret_id/,
				rows: () => [{ source_id: '9', credential_secret_id: 'existing-sec', users_id: VALID_UUID }]
			},
			{ match: /vault\.update_secret/, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new SimpleFINAdapter(vi.fn(() => db), undefined, admissionFetch());

		const result = await adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID });

		expect(result.sourceId).toBe(9n);
		const upd = calls.find((c) => /vault\.update_secret/.test(c.text));
		expect(upd?.params).toContain('existing-sec');
		expect(upd?.params).toContain(ACCESS_URL); // rotated to the new Access URL on the same handle
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(false); // no new secret minted
	});

	it('SC3-C8 parity: a matched row owned by ANOTHER tenant is rejected fail-closed (no write)', async () => {
		const OTHER = '22222222-2222-4222-8222-222222222222';
		const { tx, calls } = makeTx([
			{
				match: /source_id, credential_secret_id/,
				rows: () => [{ source_id: '9', credential_secret_id: 'other-sec', users_id: OTHER }]
			},
			{ match: /vault\./, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new SimpleFINAdapter(vi.fn(() => db), undefined, admissionFetch());

		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID })
		).rejects.toThrow(/tenant mismatch/i);
		expect(calls.some((c) => /vault\.update_secret/.test(c.text))).toBe(false);
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(false);
		expect(calls.some((c) => /update pfin\.linked_source/.test(c.text))).toBe(false);
	});
});

describe('connect() — fail-closed input hardening', () => {
	it('rejects a non-uuid ownerUserId BEFORE any claim or DB touch', async () => {
		const dbFor = vi.fn();
		let fetched = false;
		const adapter = new SimpleFINAdapter(dbFor as never, undefined, async () => {
			fetched = true;
			return { ok: true, status: 200, text: async () => ACCESS_URL, json: async () => ({}) };
		});
		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: 'not-a-uuid' })
		).rejects.toThrow(/uuid/i);
		expect(fetched).toBe(false);
		expect(dbFor).not.toHaveBeenCalled();
	});

	it('rejects an unknown/extra field via `.strict()` (mass-assignment prevention)', async () => {
		const adapter = new SimpleFINAdapter(vi.fn() as never, undefined, admissionFetch());
		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID, isAdmin: true } as never)
		).rejects.toThrow();
	});

	it('rejects a setup token that does not decode to a URL (fail-closed)', async () => {
		const adapter = new SimpleFINAdapter(vi.fn() as never, undefined, admissionFetch());
		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: 'not-base64-url!!', ownerUserId: VALID_UUID })
		).rejects.toThrow(/claim url/i);
	});

	it('scrubs a claim failure (403 already-claimed) — no credential in the message', async () => {
		const adapter = new SimpleFINAdapter(vi.fn(() => makeDb(makeTx([]).tx).db), undefined, async (_url, init) => {
			if (init?.method === 'POST') return { ok: false, status: 403, text: async () => ACCESS_URL, json: async () => ({}) };
			return { ok: true, status: 200, text: async () => '{}', json: async () => ({}) };
		});
		let caught: unknown;
		await adapter
			.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID })
			.catch((e) => (caught = e));
		const msg = (caught as Error).message;
		expect(msg).toMatch(/SimpleFIN claim failed \(HTTP 403\)/);
		expect(msg).not.toContain(ACCESS_URL);
	});
});

describe('connect() — SetupTokenInvalidError discrimination (client-correctable 400 vs generic 5xx)', () => {
	it('a 403 (already-claimed) claim → SetupTokenInvalidError (client-correctable); message scrubbed', async () => {
		const adapter = new SimpleFINAdapter(vi.fn(() => makeDb(makeTx([]).tx).db), undefined, async (_url, init) => {
			if (init?.method === 'POST') return { ok: false, status: 403, text: async () => ACCESS_URL, json: async () => ({}) };
			return { ok: true, status: 200, text: async () => '{}', json: async () => ({}) };
		});
		const caught = await adapter
			.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID })
			.catch((e) => e);
		expect(caught).toBeInstanceOf(SetupTokenInvalidError);
		expect((caught as Error).message).not.toContain(ACCESS_URL);
	});

	it('a malformed (non-decodable) setup token → SetupTokenInvalidError (client-correctable)', async () => {
		const adapter = new SimpleFINAdapter(vi.fn() as never, undefined, admissionFetch());
		const caught = await adapter
			.connect({ provider: 'simplefin', setupToken: 'not-base64-url!!', ownerUserId: VALID_UUID })
			.catch((e) => e);
		expect(caught).toBeInstanceOf(SetupTokenInvalidError);
	});

	it('a 500 (Bridge server error) claim → NOT SetupTokenInvalidError (stays generic → 5xx, fail-safe)', async () => {
		const adapter = new SimpleFINAdapter(vi.fn(() => makeDb(makeTx([]).tx).db), undefined, async (_url, init) => {
			if (init?.method === 'POST') return { ok: false, status: 500, text: async () => ACCESS_URL, json: async () => ({}) };
			return { ok: true, status: 200, text: async () => '{}', json: async () => ({}) };
		});
		const caught = await adapter
			.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID })
			.catch((e) => e);
		expect(caught).toBeInstanceOf(Error);
		expect(caught).not.toBeInstanceOf(SetupTokenInvalidError);
		expect((caught as Error).message).not.toContain(ACCESS_URL);
	});
});

describe('connect() — SC-3 the Access URL never leaks', () => {
	it('is absent from the returned object AND every logger call (only in vault.create_secret params)', async () => {
		const { tx, calls } = makeTx([
			{ match: /source_id, credential_secret_id/, rows: () => [] },
			{ match: /vault\.create_secret/, rows: () => [{ secret_id: 'sec-new-1' }] },
			{ match: /insert into\s+pfin\.linked_source/, rows: () => [{ source_id: '77' }] }
		]);
		const { db } = makeDb(tx);
		const logSpy = vi.fn();
		const adapter = new SimpleFINAdapter(vi.fn(() => db), logSpy, admissionFetch());

		const result = await adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID });

		const bigintSafe = (_k: string, v: unknown) => (typeof v === 'bigint' ? v.toString() : v);
		expect(JSON.stringify(result, bigintSafe)).not.toContain(ACCESS_URL);
		for (const call of logSpy.mock.calls) expect(JSON.stringify(call)).not.toContain(ACCESS_URL);
		expect(logSpy).toHaveBeenCalled(); // it DID log a token-free line.
		// The Access URL + its basic-auth reached ONLY vault.create_secret (Vault), nowhere else.
		const nonVaultCalls = calls.filter((c) => !/vault\./.test(c.text));
		for (const c of nonVaultCalls) {
			expect(JSON.stringify(c.params)).not.toContain(ACCESS_URL);
			expect(JSON.stringify(c.params)).not.toContain('user:pass'); // C3: no basic-auth fragment either
		}
		// C1: provider_metadata (client-readable per 015) is credential-free — the INSERT binds '{}',
		// never the Access URL / a digest / an auth fragment.
		const insertCall = calls.find((c) => /insert into\s+pfin\.linked_source/.test(c.text));
		expect(insertCall?.params).toContain('{}');
		expect(JSON.stringify(insertCall?.params)).not.toContain('user');
		expect(JSON.stringify(insertCall?.params)).not.toContain('token-xyz');
	});
});

describe('revoke() — LOCAL-DELETE ONLY (no provider revoke endpoint)', () => {
	it('deletes the tenant-scoped row (fires the Vault cleanup trigger) with NO provider call', async () => {
		const { tx, calls } = makeTx([{ match: /delete from pfin\.linked_source/, rows: () => [] }]);
		const { db } = makeDb(tx);
		let posted = false;
		// A fetch that records ANY call — revoke must make NONE (no provider revoke endpoint).
		const adapter = new SimpleFINAdapter(vi.fn(() => db), undefined, async () => {
			posted = true;
			return { ok: true, status: 200, text: async () => '', json: async () => ({}) };
		});

		await expect(adapter.revoke({ sourceId: 9n, ownerUserId: VALID_UUID })).resolves.toBeUndefined();
		expect(posted).toBe(false); // NO provider HTTP call (contrast Plaid's item/remove)
		const del = calls.find((c) => /delete from pfin\.linked_source/.test(c.text));
		expect(del?.params).toContain(VALID_UUID); // tenant-scoped delete
		// No decrypt-view read needed (no provider credential to send).
		expect(calls.some((c) => /decrypted_source_credential/.test(c.text))).toBe(false);
	});

	it('rejects a non-uuid ownerUserId fail-closed (before any DB touch)', async () => {
		const dbFor = vi.fn();
		const adapter = new SimpleFINAdapter(dbFor as never, undefined, admissionFetch());
		await expect(adapter.revoke({ sourceId: 9n, ownerUserId: 'nope' })).rejects.toThrow(/uuid/i);
		expect(dbFor).not.toHaveBeenCalled();
	});
});

describe('connect()/revoke() require a dbFor factory', () => {
	it('throws a clear error when constructed without dbFor', async () => {
		const adapter = new SimpleFINAdapter();
		await expect(
			adapter.connect({ provider: 'simplefin', setupToken: fx.SETUP_TOKEN, ownerUserId: VALID_UUID })
		).rejects.toThrow(/dbFor/);
	});
});
