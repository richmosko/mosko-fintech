// load.server.test.ts — the SELF-264 §2.5.1 decomposition loader watcher. Proves: (a) the
// unauthenticated redirect to /login with a redirectTo pointing back at this page; (b) liability
// is loadTaxLiability's return VERBATIM (loadTaxLiability itself is mocked — its own contract is
// taxLiability.test.ts's job, this file only proves the wiring); (c) pfin.tax_character rows pass
// through ordered by display_order, with the AC 11 seed-delta migration name attached; (d) a
// tax_character read failure throws rather than rendering an incomplete vocabulary.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';

const loadTaxLiabilityMock = vi.fn();
const INVENTORY_SEED_DELTA_MIGRATION = '100_tax_value_inventory_seed_delta.sql';
vi.mock('$lib/server/queries/taxLiability', () => ({
	loadTaxLiability: loadTaxLiabilityMock,
	INVENTORY_SEED_DELTA_MIGRATION
}));

const { load } = await import('./+page.server');

const SESSION_UID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

const LIABILITY_STUB = { as_of: '2026-09-04', tax_year: 2026, decomposition: {}, jurisdictions: {} };

const TAX_CHARACTER_ROWS = [
	{ code: 'ordinary', label: 'Ordinary income', display_order: 10 },
	{ code: 'qualified_dividend', label: 'Qualified dividend', display_order: 20 }
];

function makeSupabase(opts: { taxCharacters?: unknown[]; taxCharacterError?: { message: string } | null }) {
	const order = vi.fn(async () => ({
		data: opts.taxCharacters ?? [],
		error: opts.taxCharacterError ?? null
	}));
	const select = vi.fn(() => ({ order }));
	const from = vi.fn((table: string) => {
		if (table === 'tax_character') return { select };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ from }));
	return { client: { schema } as unknown as SupabaseClient, order, select, from };
}

function makeEvent(supabase: SupabaseClient, user: { id: string } | null = { id: SESSION_UID }) {
	const locals = { safeGetSession: async () => ({ session: user ? {} : null, user }), supabase };
	return {
		locals,
		params: {},
		url: new URL('http://localhost/taxes/decomposition')
	} as unknown as Parameters<typeof load>[0];
}

/** load()'s inferred return type unions in `void` (the redirect() early-throw path), which TS
 *  can't rule out statically even though every test here supplies an authed session. Narrow to
 *  the fields this file actually asserts on, mirroring accounts/[account_id]/load.server.test.ts's
 *  own loadData() helper. */
type LoadResult = {
	liability: unknown;
	taxCharacters: Array<{ code: string; label: string; display_order: number | null }>;
	inventorySeedDeltaMigration: string;
};
async function loadData(event: Parameters<typeof load>[0]): Promise<LoadResult> {
	return (await load(event)) as unknown as LoadResult;
}

describe('load() — SELF-264 auth', () => {
	it('redirects unauthenticated callers to /login with redirectTo pointing back at this page', async () => {
		const { client } = makeSupabase({ taxCharacters: [] });
		await expect(load(makeEvent(client, null))).rejects.toMatchObject({
			status: 303,
			location: '/login?redirectTo=%2Ftaxes%2Fdecomposition'
		});
	});

	it('never calls loadTaxLiability or reads tax_character when unauthenticated', async () => {
		loadTaxLiabilityMock.mockClear();
		const { client, from } = makeSupabase({ taxCharacters: [] });
		await expect(load(makeEvent(client, null))).rejects.toBeTruthy();
		expect(loadTaxLiabilityMock).not.toHaveBeenCalled();
		expect(from).not.toHaveBeenCalled();
	});
});

describe('load() — SELF-264 payload passthrough', () => {
	it('forwards loadTaxLiability\'s return VERBATIM as `liability` — no reshaping', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ taxCharacters: TAX_CHARACTER_ROWS });
		const result = await loadData(makeEvent(client));
		expect(result).toMatchObject({ liability: LIABILITY_STUB });
	});

	it('calls loadTaxLiability exactly once per load()', async () => {
		loadTaxLiabilityMock.mockClear();
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ taxCharacters: TAX_CHARACTER_ROWS });
		await load(makeEvent(client));
		expect(loadTaxLiabilityMock).toHaveBeenCalledTimes(1);
	});

	it('forwards the tax_character rows ordered by display_order, and the AC 11 seed-delta migration name', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client, order } = makeSupabase({ taxCharacters: TAX_CHARACTER_ROWS });
		const result = await loadData(makeEvent(client));
		expect(result).toMatchObject({
			taxCharacters: TAX_CHARACTER_ROWS,
			inventorySeedDeltaMigration: '100_tax_value_inventory_seed_delta.sql'
		});
		expect(result.inventorySeedDeltaMigration).toBe(INVENTORY_SEED_DELTA_MIGRATION);
		expect(order).toHaveBeenCalledWith('display_order', { ascending: true });
	});

	it('degrades an absent tax_character result (data null, no error) to an empty array rather than throwing', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ taxCharacters: undefined });
		const result = await loadData(makeEvent(client));
		expect(result).toMatchObject({ taxCharacters: [] });
	});
});

describe('load() — SELF-264 fail-loud tax_character read', () => {
	it('throws when pfin.tax_character read errors, rather than rendering an incomplete vocabulary', async () => {
		loadTaxLiabilityMock.mockResolvedValueOnce(LIABILITY_STUB);
		const { client } = makeSupabase({ taxCharacterError: { message: 'timeout' } });
		await expect(load(makeEvent(client))).rejects.toThrow(/tax_character read failed/);
	});
});
