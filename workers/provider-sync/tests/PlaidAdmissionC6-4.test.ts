// PlaidAdmissionC6-4.test.ts — C6-4 (Sec SELF-212): post-exchange admission failure must
// attempt Plaid /item/remove so a live, un-revocable Item is never stranded; a burned token is
// never retried inside connect(); the ORIGINAL admission error surfaces (not the revoke error);
// a revoke-that-also-fails emits a token-free MANUAL-REVOKE signal. Mocked Plaid + DB (no live).

import { describe, it, expect, vi } from 'vitest';
import { PlaidAdapter, type PlaidClientLike, type AdmissionDb } from '../src/adapters/PlaidAdapter.js';
import * as fx from './fixtures/plaid-payloads.js';

const UUID = '11111111-1111-4111-8111-111111111111';
const TOKEN = 'access-sandbox-SUPERSECRET-abc123';

function makeTx(fail: boolean): (s: TemplateStringsArray, ...p: unknown[]) => Promise<unknown[]> {
	return (strings: TemplateStringsArray) => {
		const text = strings.join('?');
		// Dedup SELECT → not found (new connection path).
		if (/source_id, credential_secret_id/.test(text)) return Promise.resolve([]);
		if (/vault\.create_secret/.test(text)) {
			if (fail) return Promise.reject(new Error('vault.create_secret exploded'));
			return Promise.resolve([{ secret_id: 'sec-1' }]);
		}
		if (/insert into\s+pfin\.linked_source/.test(text)) return Promise.resolve([{ source_id: '42' }]);
		return Promise.resolve([]);
	};
}

function makeDb(fail: boolean): AdmissionDb {
	const tx = makeTx(fail);
	return {
		withServiceRole: (<T>(fn: (t: unknown) => Promise<T>) => fn(tx)) as AdmissionDb['withServiceRole'],
		end: vi.fn(async () => {})
	};
}

function client(overrides: Partial<Record<keyof PlaidClientLike, unknown>> = {}): PlaidClientLike {
	return {
		linkTokenCreate: vi.fn(),
		itemPublicTokenExchange: vi.fn(async () => ({ data: { access_token: TOKEN, item_id: 'item_ABC' } })),
		accountsGet: vi.fn(async () => ({ data: { accounts: [fx.acctDepository] } })),
		itemRemove: vi.fn(async () => ({ data: {} })),
		sandboxPublicTokenCreate: vi.fn(),
		transactionsSync: vi.fn(),
		investmentsHoldingsGet: vi.fn(),
		investmentsTransactionsGet: vi.fn(),
		...overrides
	} as unknown as PlaidClientLike;
}

describe('C6-4 — post-exchange admission failure attempts /item/remove', () => {
	it('exchange succeeds, admission txn fails → /item/remove(token) called; original error re-thrown', async () => {
		const c = client();
		const adapter = new PlaidAdapter(c, () => makeDb(true));

		await expect(
			adapter.connect({ provider: 'plaid', publicToken: 'public-1', ownerUserId: UUID })
		).rejects.toThrow(/vault\.create_secret exploded/);

		expect(c.itemRemove).toHaveBeenCalledWith({ access_token: TOKEN });
	});

	it('does NOT call /item/remove when the exchange itself fails (nothing to revoke)', async () => {
		const c = client({
			itemPublicTokenExchange: vi.fn(async () => {
				throw new Error('exchange failed');
			})
		});
		const adapter = new PlaidAdapter(c, () => makeDb(false));

		await expect(adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: UUID })).rejects.toThrow();
		expect(c.itemRemove).not.toHaveBeenCalled();
	});

	it('when /item/remove ALSO fails → still rejects with the ORIGINAL error + logs a token-free MANUAL-REVOKE signal', async () => {
		const c = client({
			itemRemove: vi.fn(async () => {
				throw new Error('item/remove failed too');
			})
		});
		const logSpy = vi.fn();
		const adapter = new PlaidAdapter(c, () => makeDb(true), logSpy);

		let caught: unknown;
		await adapter.connect({ provider: 'plaid', publicToken: 'p', ownerUserId: UUID }).catch((e) => (caught = e));
		// The admission error surfaces, NOT the revoke error.
		expect((caught as Error).message).toMatch(/vault\.create_secret exploded/);

		const manual = logSpy.mock.calls.find((call) => /MANUAL REVOKE REQUIRED/.test(String(call[0])));
		expect(manual).toBeTruthy();
		// C6-5: the manual-revoke signal (and every log line) is token-free.
		for (const call of logSpy.mock.calls) expect(JSON.stringify(call)).not.toContain(TOKEN);
	});
});
