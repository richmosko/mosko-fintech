// PlaidAdapterAdmission.test.ts — connect()/revoke() credential-admission slice.
// Mocked Plaid SDK + mocked DB (fixture-style; NO live Plaid, NO live Postgres).
// Covers: happy-path admission, re-admission-UPDATE-same-handle, SC3-C3 uuid-reject,
// SC3-C4 no-access_token-leak, SC3-C5 revoke-abort + ITEM_NOT_FOUND-proceeds.

import { describe, it, expect, vi } from 'vitest';
import { PlaidAdapter, PublicTokenInvalidError, type PlaidClientLike, type AdmissionDb } from '../src/adapters/PlaidAdapter.js';
import * as fx from './fixtures/plaid-payloads.js';

const VALID_UUID = '11111111-1111-4111-8111-111111111111';
const TOKEN = 'access-sandbox-SUPERSECRET-abc123'; // stand-in long-lived access_token.
const PLAID_SECRET = 'plaid-client-SECRET-xyz';

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
		for (const h of handlers) {
			if (h.match.test(text)) return Promise.resolve(h.rows ? h.rows(params) : []);
		}
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

function baseClient(overrides: Partial<Record<keyof PlaidClientLike, unknown>> = {}): PlaidClientLike {
	return {
		itemPublicTokenExchange: vi.fn(async () => ({ data: { access_token: TOKEN, item_id: 'item_ABC' } })),
		accountsGet: vi.fn(async () => ({ data: { accounts: [fx.acctDepository, fx.acctCredit] } })),
		itemRemove: vi.fn(async () => ({ data: {} })),
		sandboxPublicTokenCreate: vi.fn(),
		transactionsSync: vi.fn(),
		investmentsHoldingsGet: vi.fn(),
		investmentsTransactionsGet: vi.fn(),
		...overrides
	} as unknown as PlaidClientLike;
}

// A Plaid SDK/axios-style error whose config.data leaks the access_token + secret.
function leakyPlaidError(errorCode: string | undefined): Error {
	return Object.assign(new Error('Request failed with status code 400'), {
		response: errorCode ? { data: { error_code: errorCode, error_message: 'x' } } : undefined,
		config: { data: JSON.stringify({ access_token: TOKEN, secret: PLAID_SECRET }) }
	});
}

describe('connect() — happy-path admission (new connection)', () => {
	it('exchanges, atomically create_secret + INSERTs, returns sourceId + refs (no pfin.account write)', async () => {
		const { tx, calls } = makeTx([
			{ match: /source_id, credential_secret_id/, rows: () => [] }, // not found → new
			{ match: /vault\.create_secret/, rows: () => [{ secret_id: 'sec-new-1' }] },
			{ match: /insert into\s+pfin\.linked_source/, rows: () => [{ source_id: '42' }] }
		]);
		const { db } = makeDb(tx);
		const dbFor = vi.fn(() => db);
		const client = baseClient();
		const adapter = new PlaidAdapter(client, dbFor);

		const result = await adapter.connect({
			provider: 'plaid',
			publicToken: 'public-sandbox-1',
			ownerUserId: VALID_UUID,
			institutionName: 'Test Bank'
		});

		expect(result.sourceId).toBe(42n);
		expect(result.accounts).toHaveLength(2);
		expect(dbFor).toHaveBeenCalledWith(VALID_UUID); // tenant bound in code (§4).
		// create_secret received the token; INSERT bound users_id = ownerUserId.
		const createCall = calls.find((c) => /vault\.create_secret/.test(c.text));
		expect(createCall?.params).toContain(TOKEN);
		const insertCall = calls.find((c) => /insert into\s+pfin\.linked_source/.test(c.text));
		expect(insertCall?.params).toContain(VALID_UUID);
		// No pfin.account write in this slice.
		expect(calls.some((c) => /insert into\s+pfin\.account/.test(c.text))).toBe(false);
	});
});

describe('connect() — re-admission (existing item) UPDATEs the SAME secret handle', () => {
	it('calls vault.update_secret on the existing handle and does NOT mint a new secret', async () => {
		const { tx, calls } = makeTx([
			{
				match: /source_id, credential_secret_id/,
				rows: () => [{ source_id: '7', credential_secret_id: 'existing-sec', users_id: VALID_UUID }]
			},
			{ match: /vault\.update_secret/, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(baseClient(), vi.fn(() => db));

		const result = await adapter.connect({ provider: 'plaid', publicToken: 'public-sandbox-2', ownerUserId: VALID_UUID });

		expect(result.sourceId).toBe(7n);
		// SAME handle reused (no orphaned vault row): update_secret fired with existing id + token.
		const upd = calls.find((c) => /vault\.update_secret/.test(c.text));
		expect(upd?.params).toContain('existing-sec');
		expect(upd?.params).toContain(TOKEN);
		// NO new secret minted on the re-admission path.
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(false);
	});

	it('G1 (QA): re-admitting a credential-LESS existing row mints + attaches a secret in place', async () => {
		const { tx, calls } = makeTx([
			{
				match: /source_id, credential_secret_id/,
				rows: () => [{ source_id: '7', credential_secret_id: null, users_id: VALID_UUID }]
			},
			{ match: /vault\.create_secret/, rows: () => [{ secret_id: 'sec-attached' }] },
			{ match: /update pfin\.linked_source set credential_secret_id/, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(baseClient(), vi.fn(() => db));

		const result = await adapter.connect({ provider: 'plaid', publicToken: 'public-sandbox-3', ownerUserId: VALID_UUID });

		expect(result.sourceId).toBe(7n);
		// A credential-less (manual/import) row → mint a NEW secret + attach it in place.
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(true);
		const attach = calls.find((c) => /update pfin\.linked_source set credential_secret_id/.test(c.text));
		expect(attach?.params).toContain('sec-attached');
		// NOT the update_secret path (no existing handle to rotate).
		expect(calls.some((c) => /vault\.update_secret/.test(c.text))).toBe(false);
	});

	it('SC3-C8: a matched row owned by ANOTHER tenant is rejected fail-closed (no write)', async () => {
		const OTHER_UUID = '22222222-2222-4222-8222-222222222222';
		const { tx, calls } = makeTx([
			{
				match: /source_id, credential_secret_id/,
				rows: () => [{ source_id: '7', credential_secret_id: 'other-tenant-sec', users_id: OTHER_UUID }]
			},
			{ match: /vault\./, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(baseClient(), vi.fn(() => db));

		await expect(
			adapter.connect({ provider: 'plaid', publicToken: 'public-sandbox-x', ownerUserId: VALID_UUID })
		).rejects.toThrow(/tenant mismatch/i);

		// Fail-closed: NO credential rotation, NO secret mint, NO row UPDATE touched the
		// other tenant's source.
		expect(calls.some((c) => /vault\.update_secret/.test(c.text))).toBe(false);
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(false);
		expect(calls.some((c) => /update pfin\.linked_source/.test(c.text))).toBe(false);
	});
});

describe('connect() — SC3-C3 tenant-binding fail-closed', () => {
	it('rejects a non-uuid ownerUserId BEFORE any exchange or DB touch', async () => {
		const client = baseClient();
		const dbFor = vi.fn();
		const adapter = new PlaidAdapter(client, dbFor as never);

		await expect(
			adapter.connect({ provider: 'plaid', publicToken: 'public-sandbox-x', ownerUserId: 'not-a-uuid' })
		).rejects.toThrow(/uuid/i);

		expect(client.itemPublicTokenExchange).not.toHaveBeenCalled();
		expect(dbFor).not.toHaveBeenCalled();
	});

	it('rejects an unknown/extra field via `.strict()` (mass-assignment prevention)', async () => {
		const adapter = new PlaidAdapter(baseClient(), vi.fn() as never);
		await expect(
			adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: VALID_UUID, isAdmin: true } as never)
		).rejects.toThrow();
	});
});

describe('connect() — SC3-C4 the access_token never leaks', () => {
	it('is absent from the returned object AND from every logger call (only in vault.create_secret params)', async () => {
		const { tx, calls } = makeTx([
			{ match: /source_id, credential_secret_id/, rows: () => [] },
			{ match: /vault\.create_secret/, rows: () => [{ secret_id: 'sec-new-1' }] },
			{ match: /insert into\s+pfin\.linked_source/, rows: () => [{ source_id: '99' }] }
		]);
		const { db } = makeDb(tx);
		const logSpy = vi.fn();
		const adapter = new PlaidAdapter(baseClient(), vi.fn(() => db), logSpy);

		const result = await adapter.connect({ provider: 'plaid', publicToken: 'public-sandbox-1', ownerUserId: VALID_UUID });

		const bigintSafe = (_k: string, v: unknown) => (typeof v === 'bigint' ? v.toString() : v);
		expect(JSON.stringify(result, bigintSafe)).not.toContain(TOKEN);
		for (const call of logSpy.mock.calls) {
			expect(JSON.stringify(call)).not.toContain(TOKEN);
		}
		expect(logSpy).toHaveBeenCalled(); // it DID log (a token-free line) — the assertion is meaningful.
		// The token reached ONLY vault.create_secret (Vault), nowhere else.
		expect(calls.find((c) => /vault\.create_secret/.test(c.text))?.params).toContain(TOKEN);
	});

	it('scrubs a failed exchange error (no access_token / no client secret in the message)', async () => {
		// Use a NON-invalidity code so this exercises the generic scrubbedPlaidError path (an
		// INVALID_PUBLIC_TOKEN is reclassified to the Item-2 marker, covered separately below).
		const client = baseClient({
			itemPublicTokenExchange: vi.fn(async () => {
				throw leakyPlaidError('INTERNAL_SERVER_ERROR');
			})
		});
		const adapter = new PlaidAdapter(client, vi.fn(() => makeDb(makeTx([]).tx).db));

		let caught: unknown;
		await adapter
			.connect({ provider: 'plaid', publicToken: 'public-sandbox-bad', ownerUserId: VALID_UUID })
			.catch((e) => (caught = e));
		const msg = (caught as Error).message;
		expect(msg).toContain('INTERNAL_SERVER_ERROR'); // the non-sensitive code survives.
		expect(msg).not.toContain(TOKEN);
		expect(msg).not.toContain(PLAID_SECRET);
	});
});

describe('Item-2 — public_token invalidity classified ONLY at the exchange leg', () => {
	it('a recognized invalidity code (INVALID_PUBLIC_TOKEN) at exchange → PublicTokenInvalidError (client-correctable)', async () => {
		const client = baseClient({
			itemPublicTokenExchange: vi.fn(async () => {
				throw leakyPlaidError('INVALID_PUBLIC_TOKEN');
			})
		});
		const adapter = new PlaidAdapter(client, vi.fn(() => makeDb(makeTx([]).tx).db));

		let caught: unknown;
		await adapter
			.connect({ provider: 'plaid', publicToken: 'public-burned', ownerUserId: VALID_UUID })
			.catch((e) => (caught = e));
		expect(caught).toBeInstanceOf(PublicTokenInvalidError);
		// SCRUBBED (guardrail #3): no token / no client secret in the marker's message.
		expect((caught as Error).message).not.toContain(TOKEN);
		expect((caught as Error).message).not.toContain(PLAID_SECRET);
	});

	it('a NON-invalidity exchange error_code (INTERNAL_SERVER_ERROR) stays a generic (5xx) error', async () => {
		const client = baseClient({
			itemPublicTokenExchange: vi.fn(async () => {
				throw leakyPlaidError('INTERNAL_SERVER_ERROR');
			})
		});
		const adapter = new PlaidAdapter(client, vi.fn(() => makeDb(makeTx([]).tx).db));

		let caught: unknown;
		await adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: VALID_UUID }).catch((e) => (caught = e));
		expect(caught).toBeInstanceOf(Error);
		expect(caught).not.toBeInstanceOf(PublicTokenInvalidError); // → 5xx, not client-correctable.
	});

	it('a POST-exchange DB/vault failure is NEVER a PublicTokenInvalidError (server failure stays 5xx)', async () => {
		// Exchange SUCCEEDS; the dedup SELECT throws → a server-side failure, not token invalidity.
		const tx = ((strings: TemplateStringsArray) => {
			if (/source_id, credential_secret_id/.test(strings.join('?'))) return Promise.reject(new Error('db exploded'));
			return Promise.resolve([]);
		}) as unknown;
		const db: AdmissionDb = {
			withServiceRole: (<T>(fn: (t: unknown) => Promise<T>) => fn(tx)) as AdmissionDb['withServiceRole'],
			end: vi.fn(async () => {})
		};
		const adapter = new PlaidAdapter(baseClient(), vi.fn(() => db));

		let caught: unknown;
		await adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: VALID_UUID }).catch((e) => (caught = e));
		expect(caught).toBeInstanceOf(Error);
		expect(caught).not.toBeInstanceOf(PublicTokenInvalidError);
	});
});

describe('revoke() — SC3-C5 provider-revoke-then-delete + abort semantics', () => {
	function revokeHarness(itemRemove: () => Promise<{ data: unknown }>, credRows: unknown[]) {
		const { tx, calls } = makeTx([
			{ match: /decrypted_source_credential/, rows: () => credRows },
			{ match: /delete from pfin\.linked_source/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const client = baseClient({ itemRemove: vi.fn(itemRemove) });
		const adapter = new PlaidAdapter(client, vi.fn(() => db));
		return { adapter, calls, client };
	}

	it('ABORTS on a provider-revoke failure — no DELETE, leaves both intact, scrubbed error', async () => {
		const { adapter, calls } = revokeHarness(
			async () => {
				throw leakyPlaidError('INSTITUTION_ERROR');
			},
			[{ decrypted_credential: TOKEN }]
		);

		let caught: unknown;
		await adapter.revoke({ sourceId: 7n, ownerUserId: VALID_UUID }).catch((e) => (caught = e));
		expect(caught).toBeInstanceOf(Error);
		const msg = (caught as Error).message;
		expect(msg).toContain('INSTITUTION_ERROR');
		expect(msg).not.toContain(TOKEN); // SC3-C4 on the revoke path (err.config.data leak).
		expect(msg).not.toContain(PLAID_SECRET);
		// SC3-C5: the DELETE never ran → the row + vault secret stay intact (retry-safe).
		expect(calls.some((c) => /delete from pfin\.linked_source/.test(c.text))).toBe(false);
		// G2 (QA): even on the abort path the credential read must be tenant-scoped.
		const readCall = calls.find((c) => /decrypted_source_credential/.test(c.text));
		expect(readCall?.params).toContain(VALID_UUID);
	});

	it('ITEM_NOT_FOUND → proceeds to DELETE (idempotent / crash-safe)', async () => {
		const { adapter, calls } = revokeHarness(
			async () => {
				throw leakyPlaidError('ITEM_NOT_FOUND');
			},
			[{ decrypted_credential: TOKEN }]
		);

		await expect(adapter.revoke({ sourceId: 7n, ownerUserId: VALID_UUID })).resolves.toBeUndefined();
		expect(calls.some((c) => /delete from pfin\.linked_source/.test(c.text))).toBe(true);
	});

	it('happy path: provider revoke succeeds → row deleted', async () => {
		const { adapter, calls, client } = revokeHarness(async () => ({ data: {} }), [{ decrypted_credential: TOKEN }]);
		await adapter.revoke({ sourceId: 7n, ownerUserId: VALID_UUID });
		expect(client.itemRemove).toHaveBeenCalledWith({ access_token: TOKEN });
		expect(calls.some((c) => /delete from pfin\.linked_source/.test(c.text))).toBe(true);
		// G2 (QA): the tenant-scoping (#1 DiD refinement) is LOAD-BEARING — assert BOTH the
		// decrypt-view read AND the delete carry users_id=ownerUserId. Without this, dropping
		// the `and users_id = ${ownerUserId}` filter would pass every other revoke test silently.
		const readCall = calls.find((c) => /decrypted_source_credential/.test(c.text));
		const deleteCall = calls.find((c) => /delete from pfin\.linked_source/.test(c.text));
		expect(readCall?.params).toContain(VALID_UUID);
		expect(deleteCall?.params).toContain(VALID_UUID);
	});

	it('rejects a non-uuid ownerUserId fail-closed (before any DB touch)', async () => {
		const dbFor = vi.fn();
		const adapter = new PlaidAdapter(baseClient(), dbFor as never);
		await expect(adapter.revoke({ sourceId: 7n, ownerUserId: 'nope' })).rejects.toThrow(/uuid/i);
		expect(dbFor).not.toHaveBeenCalled();
	});
});

describe('connect()/revoke() require a dbFor factory', () => {
	it('throws a clear error when constructed without dbFor', async () => {
		const adapter = new PlaidAdapter(baseClient());
		await expect(
			adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: VALID_UUID })
		).rejects.toThrow(/dbFor/);
	});
});
