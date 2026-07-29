// reauth.test.ts — SELF-207 §2.4.4.b ProviderAdapter.reauthStart/reauthComplete.
// Mocked Plaid SDK + mocked DB (NO live Plaid, NO live Postgres). Covers: Plaid update-mode
// start (access_token resolved + no-rotation), Plaid complete (healthy transition, rotated:false,
// fail-closed on cross-tenant), SimpleFIN start (recollect signal), SimpleFIN complete (② held).

import { describe, it, expect, vi } from 'vitest';
import { PlaidAdapter, type PlaidClientLike, type AdmissionDb } from '../src/adapters/PlaidAdapter.js';
import { SimpleFINAdapter, accessUrlDigest, type FetchLike } from '../src/adapters/SimpleFINAdapter.js';
import * as fx from './fixtures/simplefin-payloads.js';

/** fetch mock: POST <claim URL> → Access URL (text); GET .../accounts → the accounts set. */
function admissionFetch(accessUrl = fx.ACCESS_URL, accountsSet: unknown = fx.accountsSetClean): FetchLike {
	return async (_url, init) => {
		if (init?.method === 'POST') return { ok: true, status: 200, text: async () => accessUrl, json: async () => ({}) };
		return { ok: true, status: 200, text: async () => JSON.stringify(accountsSet), json: async () => accountsSet };
	};
}

const VALID_UUID = '11111111-1111-4111-8111-111111111111';
const TOKEN = 'access-sandbox-SUPERSECRET-abc123';

// ── Recording tagged-template tx mock (postgres.js call shape). ──────────────────
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
function plaidClient(overrides: Partial<Record<keyof PlaidClientLike, unknown>> = {}): PlaidClientLike {
	return {
		linkTokenCreate: vi.fn(async () => ({ data: { link_token: 'link-upd-1', expiration: '2026-07-29T10:00:00Z' } })),
		itemPublicTokenExchange: vi.fn(),
		accountsGet: vi.fn(),
		itemRemove: vi.fn(),
		sandboxPublicTokenCreate: vi.fn(),
		transactionsSync: vi.fn(),
		investmentsHoldingsGet: vi.fn(),
		investmentsTransactionsGet: vi.fn(),
		...overrides
	} as unknown as PlaidClientLike;
}

describe('PlaidAdapter.reauthStart (update mode)', () => {
	it('resolves the existing access_token + mints an update-mode link_token (access_token, NO products)', async () => {
		const { tx } = makeTx([{ match: /decrypted_source_credential/, rows: () => [{ decrypted_credential: TOKEN }] }]);
		const { db, endSpy } = makeDb(tx);
		const dbFor = vi.fn(() => db);
		const client = plaidClient();
		const adapter = new PlaidAdapter(client, dbFor);

		const handoff = await adapter.reauthStart({ linkedSourceId: 42n, ownerUserId: VALID_UUID });

		expect(handoff).toEqual({ kind: 'link_update', linkToken: 'link-upd-1' });
		expect(dbFor).toHaveBeenCalledWith(VALID_UUID);
		const req = (client.linkTokenCreate as ReturnType<typeof vi.fn>).mock.calls[0][0] as Record<string, unknown>;
		expect(req.access_token).toBe(TOKEN); // update mode references the existing Item
		expect('products' in req).toBe(false); // OMITTED in update mode (Plaid rule)
		expect(endSpy).toHaveBeenCalled();
	});

	it('fail-closed: no credential for source/tenant → throws, no link_token minted', async () => {
		const { tx } = makeTx([{ match: /decrypted_source_credential/, rows: () => [] }]);
		const { db } = makeDb(tx);
		const client = plaidClient();
		const adapter = new PlaidAdapter(client, vi.fn(() => db));
		await expect(adapter.reauthStart({ linkedSourceId: 99n, ownerUserId: VALID_UUID })).rejects.toThrow(/no credential/);
		expect(client.linkTokenCreate).not.toHaveBeenCalled();
	});

	it('rejects a malformed ownerUserId before any read (fail-closed)', async () => {
		const { tx } = makeTx([]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(plaidClient(), vi.fn(() => db));
		await expect(adapter.reauthStart({ linkedSourceId: 1n, ownerUserId: 'not-a-uuid' })).rejects.toThrow(/uuid/);
	});
});

describe('PlaidAdapter.reauthComplete (no rotation)', () => {
	it('writes the healthy transition (UPDATE + state_history) and returns rotated:false', async () => {
		const { tx, calls } = makeTx([
			{ match: /update pfin\.linked_source/, rows: () => [{ source_id: '42' }] },
			{ match: /insert into pfin\.linked_source_state_history/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(plaidClient(), vi.fn(() => db));

		const result = await adapter.reauthComplete({ linkedSourceId: 42n, ownerUserId: VALID_UUID }, { kind: 'link_update_success' });

		expect(result).toEqual({ connectionStatus: 'healthy', rotated: false });
		const upd = calls.find((c) => /update pfin\.linked_source/.test(c.text));
		expect(upd?.params).toContain(VALID_UUID); // tenant-bound in code
		expect(calls.some((c) => /insert into pfin\.linked_source_state_history/.test(c.text))).toBe(true);
	});

	it('fail-closed: cross-tenant/nonexistent source (UPDATE hits 0 rows) → throws, NO state_history insert', async () => {
		const { tx, calls } = makeTx([
			{ match: /update pfin\.linked_source/, rows: () => [] } // 0 rows
		]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(plaidClient(), vi.fn(() => db));
		await expect(
			adapter.reauthComplete({ linkedSourceId: 7n, ownerUserId: VALID_UUID }, { kind: 'link_update_success' })
		).rejects.toThrow(/not found for tenant/);
		expect(calls.some((c) => /insert into pfin\.linked_source_state_history/.test(c.text))).toBe(false);
	});

	it('rejects a non-update input kind', async () => {
		const { tx } = makeTx([]);
		const { db } = makeDb(tx);
		const adapter = new PlaidAdapter(plaidClient(), vi.fn(() => db));
		await expect(
			adapter.reauthComplete({ linkedSourceId: 1n, ownerUserId: VALID_UUID }, { kind: 'setup_token', setupToken: 'x' })
		).rejects.toThrow(/link_update_success/);
	});
});

describe('SimpleFINAdapter reauth', () => {
	it('reauthStart signals the client to re-collect a credential (no server token)', async () => {
		const adapter = new SimpleFINAdapter(vi.fn(() => makeDb(makeTx([]).tx).db));
		await expect(adapter.reauthStart({ linkedSourceId: 5n, ownerUserId: VALID_UUID })).resolves.toEqual({
			kind: 'recollect_credential'
		});
	});

	it('reauthComplete claims + rotates IN-PLACE by source_id (same handle), flips healthy, rotated:true', async () => {
		const { tx, calls } = makeTx([
			{ match: /select\s+credential_secret_id/, rows: () => [{ credential_secret_id: 'sec-existing' }] },
			{ match: /vault\.update_secret/, rows: () => [] },
			{ match: /update pfin\.linked_source/, rows: () => [{ source_id: '77' }] },
			{ match: /insert into pfin\.linked_source_state_history/, rows: () => [] }
		]);
		const { db } = makeDb(tx);
		const adapter = new SimpleFINAdapter(vi.fn(() => db), undefined, admissionFetch());

		const result = await adapter.reauthComplete(
			{ linkedSourceId: 77n, ownerUserId: VALID_UUID },
			{ kind: 'setup_token', setupToken: fx.SETUP_TOKEN }
		);

		expect(result).toEqual({ connectionStatus: 'healthy', rotated: true });
		// In-place rotation on the EXISTING handle (NOT create_secret / NOT a new source row).
		expect(calls.some((c) => /vault\.update_secret/.test(c.text))).toBe(true);
		expect(calls.some((c) => /vault\.create_secret/.test(c.text))).toBe(false);
		expect(calls.some((c) => /insert into pfin\.linked_source\b/.test(c.text))).toBe(false); // no new source row → 021 preserved
		// external_connection_id UPDATE-ed to the fresh digest + tenant-bound + healthy audit row.
		const upd = calls.find((c) => /update pfin\.linked_source/.test(c.text));
		expect(upd?.params).toContain(VALID_UUID);
		expect(upd?.params).toContain(accessUrlDigest(fx.ACCESS_URL));
		expect(calls.some((c) => /insert into pfin\.linked_source_state_history/.test(c.text))).toBe(true);
	});

	it('fail-closed: source not owned by tenant (SELECT 0 rows) → throws, no rotation', async () => {
		const { tx, calls } = makeTx([{ match: /select\s+credential_secret_id/, rows: () => [] }]);
		const { db } = makeDb(tx);
		const adapter = new SimpleFINAdapter(vi.fn(() => db), undefined, admissionFetch());
		await expect(
			adapter.reauthComplete({ linkedSourceId: 7n, ownerUserId: VALID_UUID }, { kind: 'setup_token', setupToken: fx.SETUP_TOKEN })
		).rejects.toThrow(/not found for tenant/);
		expect(calls.some((c) => /vault\.update_secret/.test(c.text))).toBe(false);
	});

	it('rejects a non-setup_token input kind', async () => {
		const adapter = new SimpleFINAdapter(vi.fn(() => makeDb(makeTx([]).tx).db));
		await expect(
			adapter.reauthComplete({ linkedSourceId: 5n, ownerUserId: VALID_UUID }, { kind: 'link_update_success' })
		).rejects.toThrow(/expected setup_token/);
	});
});
