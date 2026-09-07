// load.server.test.ts — the SELF-266 §2.5.3 quarterly loader watcher. Proves: (a) the
// unauthenticated redirect to /login with a redirectTo pointing back at this page; (b) liability
// is loadTaxLiability's return VERBATIM (loadTaxLiability itself is mocked — taxLiability.test.ts
// owns its own contract); (c) AC 8(ii)'s noTaxAuthorityDesignated flag reads BOTH ways off
// pfin.fn_tax_authority_ledgers()'s result — true on an empty result (nothing designated for
// either jurisdiction), false the moment at least one ledger is designated for EITHER authority;
// (d) a fn_tax_authority_ledgers() read failure throws rather than guessing the flag either way;
// (e) E39's priorYearQ4 wiring — loadPriorYearQ4 (also mocked; its own contract is
// taxLiability.test.ts's job) is called ONLY when `liability.prior_year_q4_window.open` is true,
// and its resolved value passes through as `priorYearQ4` verbatim; `null` when the window is shut;
// (f) SELF-361 / P9 — `staleness` is `loadStaleness()`'s return threaded straight through,
// fail-SOFT to UNKNOWN_STALENESS on an unexpected throw, unlike this file's two fail-loud reads.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

const loadTaxLiabilityMock = vi.fn();
const loadPriorYearQ4Mock = vi.fn();
vi.mock('$lib/server/queries/taxLiability', () => ({
	loadTaxLiability: loadTaxLiabilityMock,
	loadPriorYearQ4: loadPriorYearQ4Mock
}));

const loadStalenessMock = vi.fn();
vi.mock('$lib/server/queries/staleness', () => ({
	loadStaleness: loadStalenessMock
}));

const { UNKNOWN_STALENESS } = await import('$lib/staleness/stale-constituent');
const { load } = await import('./+page.server');

const HAPPY_STALENESS = { is_stale: false, stale_items: [] };

beforeEach(() => {
	loadStalenessMock.mockReset();
	loadStalenessMock.mockResolvedValue(HAPPY_STALENESS);
});

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const LIABILITY_STUB = {
	as_of: '2026-09-04',
	tax_year: 2026,
	jurisdictions: {},
	prior_year_q4_window: { open: false, tax_year: 2025, due_date: '2026-01-15' }
};

const LIABILITY_STUB_WINDOW_OPEN = {
	...LIABILITY_STUB,
	prior_year_q4_window: { open: true, tax_year: 2025, due_date: '2026-01-15' }
};

function makeSupabase(opts: { ledgers?: unknown[]; ledgersError?: { message: string } | null }) {
	const rpc = vi.fn(async (fn: string) => {
		if (fn !== 'fn_tax_authority_ledgers') throw new Error(`unexpected rpc: ${fn}`);
		return { data: opts.ledgers, error: opts.ledgersError ?? null };
	});
	const schema = vi.fn(() => ({ rpc }));
	return { client: { schema } as unknown as SupabaseClient, rpc, schema };
}

function makeEvent(supabase: SupabaseClient, user: { id: string } | null = { id: SESSION_UID }) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return {
		locals,
		params: {},
		url: new URL('http://localhost/taxes/quarterly')
	} as unknown as Parameters<typeof load>[0];
}

describe('load() — SELF-266 auth', () => {
	it('redirects unauthenticated callers to /login with redirectTo pointing back at this page', async () => {
		const { client } = makeSupabase({ ledgers: [] });
		await expect(load(makeEvent(client, null))).rejects.toMatchObject({
			status: 303,
			location: '/login?redirectTo=%2Ftaxes%2Fquarterly'
		});
	});

	it('never calls loadTaxLiability or fn_tax_authority_ledgers when unauthenticated', async () => {
		loadTaxLiabilityMock.mockClear();
		const { client, rpc } = makeSupabase({ ledgers: [] });
		await expect(load(makeEvent(client, null))).rejects.toBeTruthy();
		expect(loadTaxLiabilityMock).not.toHaveBeenCalled();
		expect(rpc).not.toHaveBeenCalled();
	});
});

describe('load() — SELF-266 payload passthrough', () => {
	it("forwards loadTaxLiability's return VERBATIM as `liability` — no reshaping", async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ liability: LIABILITY_STUB });
	});

	it('calls loadTaxLiability exactly once per load()', async () => {
		loadTaxLiabilityMock.mockClear();
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		await load(makeEvent(client));
		expect(loadTaxLiabilityMock).toHaveBeenCalledTimes(1);
	});
});

describe('load() — SELF-266 AC 8(ii) noTaxAuthorityDesignated, both directions', () => {
	it('is true when fn_tax_authority_ledgers() returns EMPTY — nothing designated for either authority', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ noTaxAuthorityDesignated: true });
	});

	it('is false the moment at least one ledger is designated (irs only — ftb still undesignated)', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgers: [{ account_id: 7, tax_jurisdiction: 'irs' }] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ noTaxAuthorityDesignated: false });
	});

	it('is false when BOTH authorities are designated', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({
			ledgers: [
				{ account_id: 7, tax_jurisdiction: 'irs' },
				{ account_id: 8, tax_jurisdiction: 'ftb' }
			]
		});
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ noTaxAuthorityDesignated: false });
	});
});

describe('load() — SELF-266 fail-loud fn_tax_authority_ledgers read', () => {
	it('throws when fn_tax_authority_ledgers() errors, rather than guessing the empty-state flag', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgersError: { message: 'timeout' } });
		await expect(load(makeEvent(client))).rejects.toThrow(/fn_tax_authority_ledgers read failed/);
	});
});

const PRIOR_YEAR_Q4_STUB = {
	tax_year: 2025,
	due_date: '2026-01-15',
	as_of: '2025-12-31',
	federal: { q4_installment: 100, annual_liability: 400, funds_due_envelope: { status: 'computed', amount: 100 } },
	california: { q4_installment: 50, annual_liability: 200, funds_due_envelope: { status: 'computed', amount: 50 } }
};

describe('load() — SELF-266 / E39 priorYearQ4 wiring', () => {
	it('does NOT call loadPriorYearQ4 when prior_year_q4_window.open is false — priorYearQ4 is null', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		loadPriorYearQ4Mock.mockClear();
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(loadPriorYearQ4Mock).not.toHaveBeenCalled();
		expect(result).toMatchObject({ priorYearQ4: null });
	});

	it('calls loadPriorYearQ4 EXACTLY once, with the current payload\'s own prior_year_q4_window, when open is true', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB_WINDOW_OPEN);
		loadPriorYearQ4Mock.mockClear();
		loadPriorYearQ4Mock.mockResolvedValueOnce(PRIOR_YEAR_Q4_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		await load(makeEvent(client));
		expect(loadPriorYearQ4Mock).toHaveBeenCalledTimes(1);
		expect(loadPriorYearQ4Mock).toHaveBeenCalledWith(
			client,
			LIABILITY_STUB_WINDOW_OPEN.prior_year_q4_window
		);
	});

	it('forwards loadPriorYearQ4\'s resolved value as `priorYearQ4` VERBATIM when open is true', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB_WINDOW_OPEN);
		loadPriorYearQ4Mock.mockClear();
		loadPriorYearQ4Mock.mockResolvedValueOnce(PRIOR_YEAR_Q4_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ priorYearQ4: PRIOR_YEAR_Q4_STUB });
	});

	it('propagates a loadPriorYearQ4 failure rather than degrading to null', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB_WINDOW_OPEN);
		loadPriorYearQ4Mock.mockClear();
		loadPriorYearQ4Mock.mockRejectedValueOnce(new Error('second call failed'));
		const { client } = makeSupabase({ ledgers: [] });
		await expect(load(makeEvent(client))).rejects.toThrow(/second call failed/);
	});
});

describe('load() — SELF-361 / P9 staleness wiring', () => {
	it('calls loadStaleness EXACTLY ONCE and threads the result straight through to data.staleness, unmodified', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(loadStalenessMock).toHaveBeenCalledTimes(1);
		expect(result).toMatchObject({ staleness: HAPPY_STALENESS });
	});

	it('a confirmed-stale result passes through verbatim', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const staleResult = {
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '42',
					institution_name: 'Test Bank',
					provider: 'plaid',
					connection_status: 'login_required',
					status_class: null
				}
			]
		};
		loadStalenessMock.mockReset();
		loadStalenessMock.mockResolvedValueOnce(staleResult);
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ staleness: staleResult });
	});

	it('an unexpected throw from loadStaleness degrades data.staleness to UNKNOWN_STALENESS, WITHOUT touching data.noTaxAuthorityDesignated', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		loadStalenessMock.mockReset();
		loadStalenessMock.mockRejectedValueOnce(new Error('network blip'));
		const { client } = makeSupabase({ ledgers: [] });
		const result = await load(makeEvent(client));
		expect(result).toMatchObject({ staleness: UNKNOWN_STALENESS, noTaxAuthorityDesignated: true });
	});

	it('a staleness throw does not prevent the fail-loud fn_tax_authority_ledgers error from still throwing', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		loadStalenessMock.mockReset();
		loadStalenessMock.mockRejectedValueOnce(new Error('network blip'));
		const { client } = makeSupabase({ ledgersError: { message: 'timeout' } });
		await expect(load(makeEvent(client))).rejects.toThrow(/fn_tax_authority_ledgers read failed/);
	});
});
