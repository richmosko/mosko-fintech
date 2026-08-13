// nav-boundary.test.ts — unit coverage for the §2.1.2 cron/imported boundary
// read (SELF-220). Pure-TS server test (node env per vitest.config). Mocks
// the supabase-js chain:
//   .schema('pfin').rpc('fn_first_cron_checkpoint') → { data, error }
//
// Proves: all FOUR of 069's states pass through unchanged (including the
// REAL empty-store row, which must NOT collapse into the failure `null`),
// and the fail-soft degrade-to-`null` on an RPC error, a non-array payload,
// and a wrong-row-count payload (069's own contract is exactly one row,
// always — anything else is a transport surprise, not a legitimate state).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadNavBoundary } from './nav-boundary';

type MockOpts = {
	data?: unknown;
	error?: { message: string } | null;
};

/** Minimal supabase-js stub: the single .schema('pfin').rpc(...) chain the helper touches. */
function makeSupabase(opts: MockOpts) {
	const rpc = vi.fn(async () => ({ data: opts.data ?? null, error: opts.error ?? null }));
	const schema = vi.fn(() => ({ rpc }));
	const client = { schema } as unknown as SupabaseClient;
	return { client, rpc, schema };
}

describe('loadNavBoundary', () => {
	it('state (a) no rows at all: the REAL (NULL, false, false) row passes through — NOT null', async () => {
		const { client, rpc, schema } = makeSupabase({
			data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false }]
		});
		const boundary = await loadNavBoundary(client);

		expect(boundary).toEqual({
			first_cron_checkpoint: null,
			has_cron_rows: false,
			has_imported_rows: false
		});
		expect(boundary).not.toBeNull();
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_first_cron_checkpoint');
	});

	it('state (b) imported only: (NULL, false, true) passes through', async () => {
		const { client } = makeSupabase({
			data: [{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: true }]
		});
		const boundary = await loadNavBoundary(client);
		expect(boundary).toEqual({
			first_cron_checkpoint: null,
			has_cron_rows: false,
			has_imported_rows: true
		});
	});

	it('state (c) cron only: (date, true, false) passes through', async () => {
		const { client } = makeSupabase({
			data: [{ first_cron_checkpoint: '2026-08-01', has_cron_rows: true, has_imported_rows: false }]
		});
		const boundary = await loadNavBoundary(client);
		expect(boundary).toEqual({
			first_cron_checkpoint: '2026-08-01',
			has_cron_rows: true,
			has_imported_rows: false
		});
	});

	it('state (d) mixed: (date, true, true) passes through', async () => {
		const { client } = makeSupabase({
			data: [{ first_cron_checkpoint: '2026-08-01', has_cron_rows: true, has_imported_rows: true }]
		});
		const boundary = await loadNavBoundary(client);
		expect(boundary).toEqual({
			first_cron_checkpoint: '2026-08-01',
			has_cron_rows: true,
			has_imported_rows: true
		});
	});

	it('RPC error → null (NOT the empty-store row) — fail-soft, but distinguishably "read failed"', async () => {
		const { client } = makeSupabase({ error: { message: 'permission denied' } });
		const boundary = await loadNavBoundary(client);
		expect(boundary).toBeNull();
	});

	it('zero-row payload (violates "exactly one row, always") → null, not guessed', async () => {
		const { client } = makeSupabase({ data: [] });
		const boundary = await loadNavBoundary(client);
		expect(boundary).toBeNull();
	});

	it('multi-row payload (transport surprise) → null, not the first row silently', async () => {
		const { client } = makeSupabase({
			data: [
				{ first_cron_checkpoint: null, has_cron_rows: false, has_imported_rows: false },
				{ first_cron_checkpoint: '2026-08-01', has_cron_rows: true, has_imported_rows: false }
			]
		});
		const boundary = await loadNavBoundary(client);
		expect(boundary).toBeNull();
	});

	it('non-array payload (unexpected) → null', async () => {
		const { client } = makeSupabase({ data: { unexpected: 'shape' } });
		const boundary = await loadNavBoundary(client);
		expect(boundary).toBeNull();
	});

	it('null payload (unexpected) → null', async () => {
		const { client } = makeSupabase({ data: null });
		const boundary = await loadNavBoundary(client);
		expect(boundary).toBeNull();
	});
});
