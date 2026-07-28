// taxonomy.test.ts — unit coverage for provisionDefaultTaxonomy (SELF-311 / migration 041).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain per table:
//   user_taxonomy: .select('id').limit(1).maybeSingle() → guard read; .upsert(rows, opts) → write
//   taxonomy_default: .select(cols) (awaited) → the 63-row global default set read
//
// Proves: the existence guard SKIPS the default-read + upsert when a row already exists; on an
// empty guard it reads taxonomy_default and UPSERTs the mapped rows with a SESSION-derived
// users_id + ON CONFLICT DO NOTHING; and it is FAIL-SOFT (logs, never throws) on every error path.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { provisionDefaultTaxonomy } from './taxonomy';

const USER_ID = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

const DEFAULTS = [
	{ domain: 'asset', cat: 'Equities', sub_cat: 'US Large Cap', tax_relevant: false, tax_character: null, display_order: 1, notes: null },
	{ domain: 'cashflow', cat: 'Income', sub_cat: 'Salary', tax_relevant: true, tax_character: 'ordinary', display_order: 2, notes: 'W-2' }
];

/**
 * Table-dispatching supabase stub. `from(table)` returns the right sub-chain:
 *   user_taxonomy → { select: guard chain, upsert }
 *   taxonomy_default → { select: awaited default read }
 */
function makeSupabase(opts: {
	existing?: unknown;
	existingErr?: { message: string } | null;
	defaults?: unknown;
	defaultsErr?: { message: string } | null;
	upsertErr?: { message: string } | null;
}) {
	const maybeSingle = vi.fn(async () => ({ data: opts.existing ?? null, error: opts.existingErr ?? null }));
	const limit = vi.fn(() => ({ maybeSingle }));
	const selectGuard = vi.fn(() => ({ limit }));
	const upsert = vi.fn(async (_rows: unknown, _opts: unknown) => ({ error: opts.upsertErr ?? null }));
	const selectDefaults = vi.fn(async () => ({ data: opts.defaults ?? null, error: opts.defaultsErr ?? null }));

	const from = vi.fn((table: string) => {
		if (table === 'user_taxonomy') return { select: selectGuard, upsert };
		if (table === 'taxonomy_default') return { select: selectDefaults };
		return {};
	});
	const schema = vi.fn(() => ({ from }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, maybeSingle, limit, selectGuard, upsert, selectDefaults, from, schema };
}

describe('provisionDefaultTaxonomy', () => {
	it('SKIPS the default read + upsert when the caller already has taxonomy (guard hit)', async () => {
		const { client, selectDefaults, upsert, from } = makeSupabase({ existing: { id: 42 } });
		await provisionDefaultTaxonomy(client, USER_ID);

		expect(from).toHaveBeenCalledWith('user_taxonomy');
		expect(from).not.toHaveBeenCalledWith('taxonomy_default');
		expect(selectDefaults).not.toHaveBeenCalled();
		expect(upsert).not.toHaveBeenCalled();
	});

	it('provisions on an empty guard: reads taxonomy_default + UPSERTs mapped rows with session users_id + DO NOTHING', async () => {
		const { client, upsert, from } = makeSupabase({ existing: null, defaults: DEFAULTS });
		await provisionDefaultTaxonomy(client, USER_ID);

		expect(from).toHaveBeenCalledWith('taxonomy_default');
		expect(upsert).toHaveBeenCalledTimes(1);
		const [rows, opts] = upsert.mock.calls[0];
		// Every row carries the SESSION users_id (never a client value) + the exact default fields.
		expect(rows).toEqual([
			{ users_id: USER_ID, ...DEFAULTS[0] },
			{ users_id: USER_ID, ...DEFAULTS[1] }
		]);
		expect(opts).toEqual({ onConflict: 'users_id,domain,cat,sub_cat', ignoreDuplicates: true });
	});

	it('does not upsert when the default set is empty', async () => {
		const { client, upsert } = makeSupabase({ existing: null, defaults: [] });
		await provisionDefaultTaxonomy(client, USER_ID);
		expect(upsert).not.toHaveBeenCalled();
	});

	it('is fail-soft on a guard read error (logs, no default read, no upsert)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client, selectDefaults, upsert } = makeSupabase({ existingErr: { message: 'rls denied' } });
		await expect(provisionDefaultTaxonomy(client, USER_ID)).resolves.toBeUndefined();
		expect(selectDefaults).not.toHaveBeenCalled();
		expect(upsert).not.toHaveBeenCalled();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('is fail-soft on a default read error (logs, no upsert)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client, upsert } = makeSupabase({ existing: null, defaultsErr: { message: 'boom' } });
		await expect(provisionDefaultTaxonomy(client, USER_ID)).resolves.toBeUndefined();
		expect(upsert).not.toHaveBeenCalled();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	// Sec positive-verification (SELF-311): the RLS WITH-CHECK RAISE on the upsert itself must be
	// caught → logged → graceful empty degrade, NOT a hard 500 on every nav. Scenario: a pre-041
	// mfa_policy='totp' user at aal1 with NO taxonomy yet → the guard does NOT skip → the 041 INSERT
	// policy's aal2 backstop rejects with 42501 (returned by supabase-js as { error }, not thrown).
	// Asserts the upsert WAS reached (so the try/catch scope genuinely covers the provision write)
	// and the raise is swallowed fail-soft. Self-heals via the layout call after step-up.
	it('is fail-soft on an RLS WITH-CHECK raise from the upsert (aal2-at-aal1 42501) — logs, reaches upsert, never throws', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { client, upsert } = makeSupabase({
			existing: null,
			defaults: DEFAULTS,
			upsertErr: { message: 'new row violates row-level security policy for table "user_taxonomy" (42501)' }
		});
		await expect(provisionDefaultTaxonomy(client, USER_ID)).resolves.toBeUndefined();
		expect(upsert).toHaveBeenCalledTimes(1); // we genuinely hit the upsert; its error was caught
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('is fail-soft when the chain itself throws (never blocks the load)', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const client = {
			schema: () => {
				throw new Error('transport down');
			}
		} as unknown as SupabaseClient;
		await expect(provisionDefaultTaxonomy(client, USER_ID)).resolves.toBeUndefined();
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});
});
