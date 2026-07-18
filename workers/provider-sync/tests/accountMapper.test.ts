// accountMapper.test.ts — the account-mapping slice (ADR-027 amendment).
//   1. buildAccountRows (PURE): field mapping + provisional defaults + the retirement nudge.
//   2. PlaidAdapter.mapAccountType: each Plaid type/subtype → 003 CHECK enum, incl. fallback.
//   3. landAccounts: INSERT under withTenant + the N1 re-run SELECT-merge completing the map.
// Mocked tx (postgres.js tagged-template shape) + mocked TenantBoundClient — no live Postgres.

import { describe, it, expect, vi } from 'vitest';
import { buildAccountRows, landAccounts, type AccountMapDefaults } from '../src/ingest/accountMapper.js';
import { PlaidAdapter } from '../src/adapters/PlaidAdapter.js';
import type { ProviderAccountRef } from '../src/adapters/ProviderAdapter.js';
import type { TenantBoundClient, Tx } from '../src/db/TenantBoundClient.js';

const VALID_UUID = '11111111-1111-4111-8111-111111111111';

const ref = (over: Partial<ProviderAccountRef>): ProviderAccountRef => ({
	providerAccountId: 'acct_1',
	name: 'Everyday Checking',
	type: 'depository',
	subtype: 'checking',
	currency: 'USD',
	...over
});

const defaults: AccountMapDefaults = { scope: 'personal', taxTreatment: 'taxable' };

// ── 1. buildAccountRows (PURE) ─────────────────────────────────────────────────
describe('buildAccountRows (pure — field map + defaults + retirement nudge)', () => {
	it('maps ref fields, applies provisional defaults, sets link cols, omits users_id', () => {
		const rows = buildAccountRows([ref({})], 42n, defaults, PlaidAdapter.mapAccountType);
		expect(rows[0]).toEqual({
			name: 'Everyday Checking',
			account_type: 'depository',
			scope: 'personal',
			tax_treatment: 'taxable',
			currency: 'USD',
			linked_source_id: 42,
			provider_account_id: 'acct_1'
		});
		// users_id is DELIBERATELY not built (DEFAULT auth.uid() stamps it — the un-forgeable tenant).
		expect(rows[0]).not.toHaveProperty('users_id');
	});

	it('nudges a retirement account to tax_deferred regardless of the batch default', () => {
		const rows = buildAccountRows(
			[ref({ providerAccountId: 'acct_ira', name: 'Rollover IRA', type: 'investment', subtype: 'ira' })],
			7n,
			{ scope: 'personal', taxTreatment: 'taxable' }, // batch default is taxable...
			PlaidAdapter.mapAccountType
		);
		expect(rows[0]?.account_type).toBe('retirement');
		expect(rows[0]?.tax_treatment).toBe('tax_deferred'); // ...but the retirement nudge overrides it.
	});

	it('leaves a non-retirement investment on the batch default', () => {
		const rows = buildAccountRows(
			[ref({ type: 'investment', subtype: 'brokerage' })],
			7n,
			{ scope: 'personal', taxTreatment: 'taxable' },
			PlaidAdapter.mapAccountType
		);
		expect(rows[0]?.account_type).toBe('investment');
		expect(rows[0]?.tax_treatment).toBe('taxable');
	});

	it('carries currency + provider id per ref', () => {
		const rows = buildAccountRows([ref({ providerAccountId: 'p_eur', currency: 'EUR' })], 1n, defaults, PlaidAdapter.mapAccountType);
		expect(rows[0]?.currency).toBe('EUR');
		expect(rows[0]?.provider_account_id).toBe('p_eur');
	});
});

// ── 2. PlaidAdapter.mapAccountType ─────────────────────────────────────────────
describe('PlaidAdapter.mapAccountType (Plaid type/subtype → 003 account_type CHECK)', () => {
	it('depository → depository', () => {
		expect(PlaidAdapter.mapAccountType('depository', 'checking')).toBe('depository');
		expect(PlaidAdapter.mapAccountType('depository', 'savings')).toBe('depository');
	});
	it('credit / loan → liability', () => {
		expect(PlaidAdapter.mapAccountType('credit', 'credit card')).toBe('liability');
		expect(PlaidAdapter.mapAccountType('loan', 'mortgage')).toBe('liability');
		expect(PlaidAdapter.mapAccountType('loan', 'student')).toBe('liability');
	});
	it('investment + non-retirement subtype → investment', () => {
		expect(PlaidAdapter.mapAccountType('investment', 'brokerage')).toBe('investment');
		expect(PlaidAdapter.mapAccountType('investment', '529')).toBe('investment');
		expect(PlaidAdapter.mapAccountType('investment', 'hsa')).toBe('investment');
	});
	it('investment + retirement subtype → retirement (allowlist)', () => {
		for (const s of ['401k', '403b', '457b', 'ira', 'roth', 'roth 401k', 'sep ira', 'simple ira', 'pension', 'retirement']) {
			expect(PlaidAdapter.mapAccountType('investment', s)).toBe('retirement');
		}
	});
	it('is case/whitespace-insensitive on type + subtype', () => {
		expect(PlaidAdapter.mapAccountType('  Investment ', ' IRA ')).toBe('retirement');
		expect(PlaidAdapter.mapAccountType('CREDIT', 'x')).toBe('liability');
	});
	it('investment + unrecognized subtype → investment (least-wrong bucket)', () => {
		expect(PlaidAdapter.mapAccountType('investment', 'something-weird')).toBe('investment');
		expect(PlaidAdapter.mapAccountType('investment', null)).toBe('investment');
	});
	it('unrecognized type → manual_other (fallback)', () => {
		expect(PlaidAdapter.mapAccountType('other', 'x')).toBe('manual_other');
		expect(PlaidAdapter.mapAccountType('', null)).toBe('manual_other');
		// No auto-assignment to crypto / real_estate — SELF-212 override only.
		expect(PlaidAdapter.mapAccountType('brokerage', 'x')).toBe('manual_other'); // legacy top-level type not mapped
	});
});

// ── 3. landAccounts (mocked tx) ────────────────────────────────────────────────
interface TxCall {
	text: string;
	params: unknown[];
}
interface Handler {
	match: RegExp;
	rows: (params: unknown[]) => unknown[];
}
/** A recording tagged-template tx mock (postgres.js call shape). First matching handler wins. */
function makeTx(handlers: Handler[]): { tx: Tx; calls: TxCall[] } {
	const calls: TxCall[] = [];
	const fn = (strings: TemplateStringsArray, ...params: unknown[]): Promise<unknown[]> => {
		const text = strings.join('?');
		calls.push({ text, params });
		for (const h of handlers) if (h.match.test(text)) return Promise.resolve(h.rows(params));
		return Promise.resolve([]);
	};
	return { tx: fn as unknown as Tx, calls };
}

/** A TenantBoundClient stand-in bound to VALID_UUID whose withTenant runs fn(tx) directly. */
function makeClient(tx: Tx, usersId: string = VALID_UUID): TenantBoundClient {
	return {
		usersId,
		withTenant: (<T>(fn: (t: Tx) => Promise<T>) => fn(tx)) as TenantBoundClient['withTenant'],
		withServiceRole: (() => {
			throw new Error('landAccounts must not use service_role (Q1)');
		}) as TenantBoundClient['withServiceRole'],
		end: (async () => {}) as TenantBoundClient['end']
	} as unknown as TenantBoundClient;
}

const refs: ProviderAccountRef[] = [
	ref({ providerAccountId: 'acct_chk', name: 'Checking', type: 'depository', subtype: 'checking' }),
	ref({ providerAccountId: 'acct_ira', name: 'IRA', type: 'investment', subtype: 'ira' })
];

describe('landAccounts', () => {
	it('inserts under withTenant with the 021 partial-index ON CONFLICT arbiter, returns the map', async () => {
		let nextId = 1000;
		const { tx, calls } = makeTx([
			// fresh INSERT ... RETURNING → one row per insert (the provider id is the last-ish param).
			{
				match: /insert into\s+pfin\.account/,
				rows: (params) => {
					const providerId = params.find((p) => p === 'acct_chk' || p === 'acct_ira');
					return [{ account_id: ++nextId, provider_account_id: providerId }];
				}
			},
			// N1 re-read (resolveAccountIds) → nothing extra here (all fresh).
			{ match: /select account_id, provider_account_id from pfin\.account/, rows: () => [] }
		]);
		const client = makeClient(tx);

		const map = await landAccounts(client, 42n, VALID_UUID, refs, defaults, PlaidAdapter.mapAccountType);

		expect(map.get('acct_chk')).toBe(1001);
		expect(map.get('acct_ira')).toBe(1002);
		expect(map.size).toBe(2);

		// The INSERT carries the partial-index ON CONFLICT arbiter WHERE clause (must match 021).
		const insert = calls.find((c) => /insert into\s+pfin\.account/.test(c.text));
		expect(insert?.text).toMatch(/on conflict \(linked_source_id, provider_account_id\) where linked_source_id is not null/i);
		expect(insert?.text).toMatch(/do nothing/i);
		// users_id is NEVER supplied by the writer (DEFAULT auth.uid() stamps it — Q1 un-forgeable).
		expect(insert?.text).not.toMatch(/users_id/i);
		expect(calls.every((c) => !c.params.includes(VALID_UUID))).toBe(true);
	});

	it('N1: a re-run where DO NOTHING skips an existing row still returns a COMPLETE map', async () => {
		// acct_chk already exists (INSERT returns [] — skipped by DO NOTHING); acct_ira is fresh.
		const { tx } = makeTx([
			{
				match: /insert into\s+pfin\.account/,
				rows: (params) => (params.includes('acct_ira') ? [{ account_id: 2002, provider_account_id: 'acct_ira' }] : [])
			},
			// resolveAccountIds re-reads ALL mapped rows for the source → completes acct_chk.
			{
				match: /select account_id, provider_account_id from pfin\.account/,
				rows: () => [
					{ account_id: 2001, provider_account_id: 'acct_chk' },
					{ account_id: 2002, provider_account_id: 'acct_ira' }
				]
			}
		]);
		const client = makeClient(tx);

		const map = await landAccounts(client, 42n, VALID_UUID, refs, defaults, PlaidAdapter.mapAccountType);

		// Complete whether freshly inserted (acct_ira) OR pre-existing/skipped (acct_chk).
		expect(map.get('acct_chk')).toBe(2001);
		expect(map.get('acct_ira')).toBe(2002);
		expect(map.size).toBe(2);
	});

	it('fail-closed: ownerUserId ≠ the tenant-bound client is rejected before any write', async () => {
		const { tx, calls } = makeTx([{ match: /.*/, rows: () => [] }]);
		const client = makeClient(tx, VALID_UUID);
		await expect(
			landAccounts(client, 42n, '22222222-2222-4222-8222-222222222222', refs, defaults, PlaidAdapter.mapAccountType)
		).rejects.toThrow(/does not match the tenant-bound client/i);
		expect(calls).toHaveLength(0); // no tx opened.
	});

	it('never touches service_role (Q1 — the write is authenticated/INVOKER only)', async () => {
		const withServiceRole = vi.fn();
		const { tx } = makeTx([
			{ match: /insert into\s+pfin\.account/, rows: () => [{ account_id: 1, provider_account_id: 'acct_chk' }] },
			{ match: /select account_id/, rows: () => [] }
		]);
		const client = {
			usersId: VALID_UUID,
			withTenant: (<T>(fn: (t: Tx) => Promise<T>) => fn(tx)) as TenantBoundClient['withTenant'],
			withServiceRole,
			end: async () => {}
		} as unknown as TenantBoundClient;
		await landAccounts(client, 1n, VALID_UUID, [refs[0]!], defaults, PlaidAdapter.mapAccountType);
		expect(withServiceRole).not.toHaveBeenCalled();
	});
});
