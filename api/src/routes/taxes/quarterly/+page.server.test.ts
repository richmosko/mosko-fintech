// +page.server.test.ts — the SELF-266 §2.5.3 quarterly loader watcher. Proves: (a) the
// unauthenticated redirect to /login with a redirectTo pointing back at this page; (b) liability
// is loadTaxLiability's return VERBATIM (loadTaxLiability itself is mocked — taxLiability.test.ts
// owns its own contract); (c) AC 8(ii)'s noTaxAuthorityDesignated flag reads BOTH ways off
// pfin.fn_tax_authority_ledgers()'s result — true on an empty result (nothing designated for
// either jurisdiction), false the moment at least one ledger is designated for EITHER authority;
// (d) a fn_tax_authority_ledgers() read failure throws rather than guessing the flag either way.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

const loadTaxLiabilityMock = vi.fn();
vi.mock('$lib/server/queries/taxLiability', () => ({
	loadTaxLiability: loadTaxLiabilityMock
}));

const { load } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const LIABILITY_STUB = { as_of: '2026-09-04', tax_year: 2026, jurisdictions: {}, prior_year_q4_window: {} };

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
