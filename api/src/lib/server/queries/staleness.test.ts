// staleness.test.ts — unit coverage for the SELF-208 §2.4.4.c D1 staleness read (`046`).
// Pure-TS server test (node env per vitest.config). Mocks the supabase-js chain:
//   .schema('pfin').rpc('fn_aggregation_has_stale_constituent') → { data, error }
//
// Proves: the happy path (set-returning RPC → array[0], jsonb stale_items normalized to the
// StaleConstituentItem contract including the SELF-199 bigint→string coercion), and — the point
// of this file, added as part of the SELF-229 REWORK — that a read failure degrades to
// UNKNOWN_STALENESS, NEVER EMPTY_STALENESS. This module previously had NO dedicated test file;
// it is the one that most needed it, since it is the framework's own root: every consumer
// (headline badge, and once threaded, the §2.1.2/.3/.4 surfaces, plus §2.1.5 composition's join)
// inherits whatever this function returns on failure.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadStaleness } from './staleness';
import { EMPTY_STALENESS, UNKNOWN_STALENESS } from '$lib/staleness/stale-constituent';

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

describe('loadStaleness', () => {
	it('happy path: is_stale=true + stale_items normalized (bigint→string, status_class default)', async () => {
		const { client, rpc, schema } = makeSupabase({
			data: [
				{
					is_stale: true,
					stale_items: [
						{
							linked_source_id: 42, // arrives as a JSON number from the jsonb projection
							institution_name: 'Chase',
							provider: 'plaid',
							connection_status: 'login_required',
							status_class: null
						}
					]
				}
			]
		});
		const result = await loadStaleness(client);

		expect(result).toEqual({
			is_stale: true,
			stale_items: [
				{
					linked_source_id: '42', // SELF-199 convention: coerced to string
					institution_name: 'Chase',
					provider: 'plaid',
					connection_status: 'login_required',
					status_class: null
				}
			]
		});
		expect(schema).toHaveBeenCalledWith('pfin');
		expect(rpc).toHaveBeenCalledWith('fn_aggregation_has_stale_constituent');
	});

	it('happy path, all-healthy: is_stale=false + stale_items=[] (a KNOWN empty, not EMPTY_STALENESS by coincidence)', async () => {
		const { client } = makeSupabase({ data: [{ is_stale: false, stale_items: [] }] });
		const result = await loadStaleness(client);
		expect(result).toEqual(EMPTY_STALENESS);
	});

	// ── SELF-229 REWORK: the discriminating legs (team-lead catch, mirrors SELF-220 Sec round 2)
	describe('failure degrades to UNKNOWN_STALENESS — never EMPTY_STALENESS', () => {
		it('RPC error → UNKNOWN_STALENESS', async () => {
			const { client } = makeSupabase({ error: { message: 'permission denied' } });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			// The negative assertion is the point of this test.
			expect(result.is_stale).not.toBe(false);
			expect(result).not.toEqual(EMPTY_STALENESS);
		});

		it('no aggregate row returned (malformed response) → UNKNOWN_STALENESS', async () => {
			const { client } = makeSupabase({ data: [] });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			expect(result.is_stale).not.toBe(false);
		});

		it('null payload (unexpected) → UNKNOWN_STALENESS', async () => {
			const { client } = makeSupabase({ data: null });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			expect(result.is_stale).not.toBe(false);
		});

		// ── Sec F1 (AMBER, 2026-08-14): the malformed-row guard. NOT reachable from the real `046`
		// RPC today (Sec verified the CTE keeps is_stale/stale_items consistent by construction) —
		// this is a contract-drift trap, exercised here by feeding the mock a row the real fn
		// cannot actually produce.
		it('Sec F1 — {is_stale: true, stale_items: null} (inconsistent pair) → UNKNOWN_STALENESS, not a coerced is_stale=true', async () => {
			const { client } = makeSupabase({ data: [{ is_stale: true, stale_items: null }] });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			expect(result.is_stale).toBeNull();
			// The failure this guards: Array.isArray(null) ? ... : [] alone would have paired a
			// truthy is_stale with an empty list instead of refusing the whole malformed row.
			expect(result.stale_items).toEqual([]);
		});

		it('Sec F1 — is_stale is a non-boolean (e.g. a string) → UNKNOWN_STALENESS, never coerced via Boolean()', async () => {
			const { client } = makeSupabase({ data: [{ is_stale: 'true', stale_items: [] }] });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			// The failure this guards: Boolean('true') === true, which would have silently
			// asserted staleness from a value that was never actually a boolean.
			expect(result.is_stale).not.toBe(true);
		});

		it('Sec F1 — is_stale is null (absent-like) → UNKNOWN_STALENESS, never silently coerced to false', async () => {
			const { client } = makeSupabase({ data: [{ is_stale: null, stale_items: [] }] });
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			// The failure this guards: Boolean(null) === false, which is EMPTY_STALENESS's exact
			// value — the original REWORK defect reintroduced through this one field.
			expect(result.is_stale).not.toBe(false);
		});

		// Sec R1 (GREEN round, non-blocking): the shape guard above proves is_stale IS a boolean and
		// stale_items IS an array — but a well-TYPED pair can still be internally INCONSISTENT.
		// {is_stale: false, stale_items: [...]} passes F1's shape check cleanly (a real boolean, a
		// real array) yet contradicts `046`'s own contract that is_stale means "stale_items is
		// non-empty." This is the diagonal cell F1's shape guard structurally cannot see.
		it('Sec R1 — {is_stale: false, stale_items: [oneItem]} (well-typed but inconsistent pair) → UNKNOWN_STALENESS', async () => {
			const { client } = makeSupabase({
				data: [
					{
						is_stale: false,
						stale_items: [
							{
								linked_source_id: 1,
								institution_name: 'Chase',
								provider: 'plaid',
								connection_status: 'login_required',
								status_class: null
							}
						]
					}
				]
			});
			const result = await loadStaleness(client);

			expect(result).toEqual(UNKNOWN_STALENESS);
			// The failure this guards: a naive shape-only guard would have passed this row through
			// as EMPTY_STALENESS-shaped (is_stale: false) while silently dropping a real stale item.
			expect(result.is_stale).not.toBe(false);
			expect(result.stale_items).toEqual([]);
		});
	});
});
