// per-account-loader.server.test.ts — SELF-254 load()-integration coverage for
// cash-flow/[account_id]/+page.server.ts. Mirrors cash-flow/cash-flow-loader.server.test.ts's own
// SELF-251 convention: import the real `load`, drive it with a minimal locals/params/url double,
// assert on the mock's call count/args rather than on network state.
//
// `loadCashflowPerAccountForRequest` (Backend-owned, cashflowPerAccount.ts) is mocked here — its
// own internal validation / RLS-scoping / normalize() behavior is proven by that file's own
// cashflowPerAccount.test.ts; this file's only honest claim is about +page.server.ts's WIRING:
// does it call the wrapper once, with the route param + a real maxAsOf, does the 400 split land
// on the right branch (account_id -> 404, as_of -> inline asOfError), and does the account-list
// read fail soft to `[]`.
//
// SELF-258 EXTENSION (staleness-ramp loader leg): `loadStaleness` is mocked the same way — its
// own internal RPC-normalize / fail-soft behavior is proven by staleness.test.ts /
// staleness.error-degrade.test.ts; this file's added coverage is again pure WIRING: exactly one
// call, the result threaded straight through to `data.staleness` on BOTH the happy path and the
// as_of-inline-error 400 branch, degrading to UNKNOWN_STALENESS (never EMPTY_STALENESS) on a
// throw, independent of the drilldown/account-list legs in both directions.

import { describe, it, expect, vi } from 'vitest';
import { isRedirect, isHttpError } from '@sveltejs/kit';

const loadCashflowPerAccountForRequestMock = vi.fn();
vi.mock('$lib/server/queries/cashflowPerAccount', () => ({
	loadCashflowPerAccountForRequest: loadCashflowPerAccountForRequestMock
}));

const loadStalenessMock = vi.fn();
vi.mock('$lib/server/queries/staleness', () => ({
	loadStaleness: loadStalenessMock
}));

const { load } = await import('./+page.server');
const { UNKNOWN_STALENESS } = await import('$lib/staleness/stale-constituent');

const SESSION_USER = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' };
const HAPPY_DRILLDOWN = {
	as_of: '2026-08-27',
	account_id: 42,
	sections: [],
	unclassified: { count_ytd: 0 }
};
const HAPPY_STALENESS = { is_stale: false, stale_items: [] };

function stubHappyStaleness() {
	loadStalenessMock.mockReset();
	loadStalenessMock.mockResolvedValue(HAPPY_STALENESS);
}

type AccountRow = { account_id: number; name: string; closed_at: string | null };

function makeSupabase(accountRows: AccountRow[] = [], accountReadError: { message: string } | null = null) {
	return {
		schema: () => ({
			from: () => ({
				select: () => ({
					order: async () => ({ data: accountReadError ? null : accountRows, error: accountReadError })
				})
			})
		})
	};
}

function makeEvent(opts: {
	accountId?: string;
	asOf?: string | null;
	user?: { id: string } | null;
	accounts?: AccountRow[];
	accountReadError?: { message: string } | null;
} = {}) {
	const {
		accountId = '42',
		asOf = null,
		user = SESSION_USER,
		accounts = [],
		accountReadError = null
	} = opts;
	const locals = {
		safeGetSession: async () => ({ session: user ? {} : null, user }),
		supabase: makeSupabase(accounts, accountReadError)
	};
	const search = asOf ? `?as_of=${asOf}` : '';
	const url = new URL(`http://localhost/cash-flow/${accountId}${search}`);
	return { locals, params: { account_id: accountId }, url } as unknown as Parameters<typeof load>[0];
}

describe('load() — SELF-254 unauthenticated redirect', () => {
	it('redirects to /login with a redirectTo, and attempts NO drilldown or staleness read', async () => {
		loadCashflowPerAccountForRequestMock.mockClear();
		loadStalenessMock.mockClear();
		let caught: unknown;
		try {
			await load(makeEvent({ user: null }));
		} catch (e) {
			caught = e;
		}
		expect(isRedirect(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(303);
		expect(loadCashflowPerAccountForRequestMock).not.toHaveBeenCalled();
		expect(loadStalenessMock).not.toHaveBeenCalled();
	});
});

describe('load() — SELF-254 one-source: exactly one drilldown read per load(), asOf resolved once', () => {
	it('calls loadCashflowPerAccountForRequest EXACTLY ONCE', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		await load(makeEvent());
		expect(loadCashflowPerAccountForRequestMock).toHaveBeenCalledTimes(1);
	});

	it('passes the route param as accountIdRaw, the URL as_of as asOfRaw, and a real YYYY-MM-DD maxAsOf', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		await load(makeEvent({ accountId: '42', asOf: '2026-06-01' }));
		const [, input] = loadCashflowPerAccountForRequestMock.mock.calls[0];
		expect(input.accountIdRaw).toBe('42');
		expect(input.asOfRaw).toBe('2026-06-01');
		expect(input.maxAsOf).toMatch(/^\d{4}-\d{2}-\d{2}$/);
	});

	it('passes asOfRaw as null when the URL carries no ?as_of=', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		await load(makeEvent({ asOf: null }));
		const [, input] = loadCashflowPerAccountForRequestMock.mock.calls[0];
		expect(input.asOfRaw).toBeNull();
	});

	it('threads the resolved drilldown straight through to data.drilldown, unmodified', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		const data = (await load(makeEvent())) as unknown as { drilldown: unknown };
		expect(data.drilldown).toBe(HAPPY_DRILLDOWN);
	});
});

describe('load() — SELF-254 AC4 item 3: the 400 split (account_id -> 404, as_of -> inline error)', () => {
	it('an account_id field error throws a 404 (not user-correctable — the picker never offers a bad id)', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({
			status: 400,
			fieldErrors: { account_id: ['Invalid account.'] }
		});
		stubHappyStaleness();
		let caught: unknown;
		try {
			await load(makeEvent());
		} catch (e) {
			caught = e;
		}
		expect(isHttpError(caught)).toBe(true);
		expect((caught as { status: number }).status).toBe(404);
	});

	it('an as_of-only field error degrades to a sane inline error state, never a thrown error', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({
			status: 400,
			fieldErrors: { as_of: ['Date cannot be in the future.'] }
		});
		stubHappyStaleness();
		const data = (await load(makeEvent())) as unknown as {
			drilldown: unknown;
			asOfError: string | null;
		};
		expect(data.drilldown).toBeNull();
		expect(data.asOfError).toBe('Date cannot be in the future.');
	});
});

describe('load() — SELF-254 AC3: the account-list read fails soft', () => {
	it('degrades to accounts: [] on a read error, without blocking the drilldown data', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		const data = (await load(
			makeEvent({ accountReadError: { message: 'network blip' } })
		)) as unknown as { accounts: unknown[]; drilldown: unknown };
		expect(data.accounts).toEqual([]);
		expect(data.drilldown).toBe(HAPPY_DRILLDOWN);
	});

	it('includes CLOSED accounts (AC3) — no filter applied to the read', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		stubHappyStaleness();
		const rows: AccountRow[] = [
			{ account_id: 1, name: 'Open Checking', closed_at: null },
			{ account_id: 2, name: 'Old Savings', closed_at: '2025-01-15T00:00:00Z' }
		];
		const data = (await load(makeEvent({ accounts: rows }))) as unknown as {
			accounts: AccountRow[];
		};
		expect(data.accounts).toHaveLength(2);
		expect(data.accounts.some((a) => a.closed_at !== null)).toBe(true);
	});
});

describe('load() — SELF-258 staleness ramp: one whole-tenant read, independent fail-soft, on BOTH the happy and as_of-error branches', () => {
	it('calls loadStaleness EXACTLY ONCE and threads the result straight through to data.staleness, unmodified', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		const data = (await load(makeEvent())) as unknown as { staleness: unknown };

		expect(loadStalenessMock).toHaveBeenCalledTimes(1);
		expect(data.staleness).toBe(HAPPY_STALENESS);
	});

	it('a real stale result (is_stale: true, non-empty stale_items) survives to data unmodified', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		const staleResult = {
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '7',
					institution_name: 'Test Bank',
					provider: 'plaid',
					connection_status: 'error',
					status_class: 'error'
				}
			]
		};
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(staleResult);
		const data = (await load(makeEvent())) as unknown as { staleness: unknown };

		expect(data.staleness).toBe(staleResult);
	});

	it('an unexpected throw from loadStaleness degrades data.staleness to UNKNOWN_STALENESS, WITHOUT touching data.drilldown', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({ status: 200, data: HAPPY_DRILLDOWN });
		loadStalenessMock.mockReset();
		loadStalenessMock.mockRejectedValueOnce(new Error('network blip'));
		const data = (await load(makeEvent())) as unknown as { staleness: unknown; drilldown: unknown };

		expect(data.staleness).toEqual(UNKNOWN_STALENESS);
		expect(data.drilldown).toBe(HAPPY_DRILLDOWN);
	});

	it('a staleness throw on the as_of-inline-error 400 branch still returns UNKNOWN_STALENESS, not a thrown error', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({
			status: 400,
			fieldErrors: { as_of: ['Date cannot be in the future.'] }
		});
		loadStalenessMock.mockReset();
		loadStalenessMock.mockRejectedValueOnce(new Error('network blip'));
		const data = (await load(makeEvent())) as unknown as {
			staleness: unknown;
			asOfError: string | null;
		};

		expect(data.staleness).toEqual(UNKNOWN_STALENESS);
		expect(data.asOfError).toBe('Date cannot be in the future.');
	});

	it('the SAME staleness value is returned on the as_of-inline-error 400 branch as on the happy path', async () => {
		loadCashflowPerAccountForRequestMock.mockReset();
		loadCashflowPerAccountForRequestMock.mockResolvedValueOnce({
			status: 400,
			fieldErrors: { as_of: ['Date cannot be in the future.'] }
		});
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(HAPPY_STALENESS);
		const data = (await load(makeEvent())) as unknown as { staleness: unknown };

		expect(data.staleness).toBe(HAPPY_STALENESS);
	});
});
