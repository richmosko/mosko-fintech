// transactions.priced.test.ts — SELF-325 P-b account-detail read-side signal:
// loadHeldSecurities' `priced` field (via the internal loadPricedFlags helper).
//
// F/CTO catch criterion (verbatim, per Architect): "after this PR, a user who records a purchase
// that cannot be priced must be able to see that fact on the account, at any later time — not
// only in the confirmation they saw once." This file is the watcher for that criterion at the
// query layer (load.server.test.ts carries the pass-through watcher at the page-load layer).
//
// ⚠ SCOPE NARROWED (Sec C3 → Sec F1, SELF-325 round 10): `loadPricedFlags` used to compute the
// `priced` predicate itself (a TypeScript reimplementation of 088's inline SQL) — THIS file used
// to be where that computation was watched (zero-price rows, same-date ties, max-price_date
// picking). That computation now lives ENTIRELY in `pfin.fn_asset_priced_flags` (089); the app
// layer just marshals whatever boolean the RPC returns into a Map. The predicate-correctness
// tests that used to live here (zero-valued rows, same-date ties, max-date picking) now belong to
// 089's own pgTAP battery (QA-owned) — re-deriving them here as app-side "does 0 count as
// unpriced" tests would be testing a DB behavior through a mock that always agrees with itself,
// which is exactly the mock-vs-mock blindness class this arc's freeze-break bug came from.
// What THIS file still owns: does the app correlate RPC rows back to the right asset_id, forward
// them faithfully, re-evaluate live rather than cache, and — Sec F1's app-layer catch criterion —
// never fetch raw price history again (the row-cap exposure is now closed BY CONSTRUCTION, not by
// a bound; a structural test below proves the vulnerable fetch shape cannot silently return).

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadHeldSecurities, type HeldSecurity } from './transactions';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const ACCOUNT_ID = 10;
const AS_OF = unsafeAsOfForTest('2026-08-15');

type PricedRow = { asset_id: number; priced: boolean };

/** A minimal supabase stub covering the two RPCs + one table select loadHeldSecurities makes:
 *  fn_holdings_as_of, the pfin.asset label select, and fn_asset_priced_flags (089). Records every
 *  `.rpc()` call (fn name + args) and every `.from()` table name so tests can assert on the SHAPE
 *  of what was asked for, not just the values that came back. */
function makeSupabase(opts: {
	holdings?: Array<{ account_id: number; asset_id: number; quantity: number }>;
	assets?: Array<{ asset_id: number; symbol: string | null; name: string | null }>;
	pricedRows?: PricedRow[];
	pricedError?: { message: string } | null;
}) {
	const rpcCalls: Array<{ fn: string; args: unknown }> = [];
	const rpc = vi.fn(async (fn: string, args: unknown) => {
		rpcCalls.push({ fn, args });
		if (fn === 'fn_holdings_as_of') return { data: opts.holdings ?? [], error: null };
		if (fn === 'fn_asset_priced_flags') return { data: opts.pricedRows ?? [], error: opts.pricedError ?? null };
		throw new Error(`unexpected rpc: ${fn}`);
	});

	const assetSelect = vi.fn(() => ({
		in: vi.fn(async () => ({ data: opts.assets ?? [], error: null }))
	}));

	const fromCalls: string[] = [];
	const from = vi.fn((table: string) => {
		fromCalls.push(table);
		if (table === 'asset') return { select: assetSelect };
		// ⚠ Deliberately NO 'eod_price' branch — see the structural F1 test below. A call here
		// throws loudly rather than quietly answering, so a regression back to a raw eod_price
		// fetch fails FAST, not by a coincidentally-still-passing assertion.
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ from, rpc }));
	return { supabase: { schema } as unknown as SupabaseClient, rpcCalls, fromCalls };
}

function findBySecurityId(rows: HeldSecurity[], id: number): HeldSecurity | undefined {
	return rows.find((r) => r.security_id === id);
}

describe('loadHeldSecurities — priced field (SELF-325 P-b / F1, delegated to 089)', () => {
	it('089 reports priced:false for a held asset → priced:false', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [{ asset_id: 501, priced: false }]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('089 reports priced:true for a held asset → priced:true', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [{ asset_id: 501, priced: true }]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(true);
	});

	it('an asset_id absent from 089\'s result defaults to priced:false (089\'s own contract says this should not happen — a row exists for every id passed — but the app-layer default stays fail-closed regardless)', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [] // 089 returned nothing for asset 501 — should not happen, but don't crash or default true.
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('THE CLEARING CASE — a previously-unpriced asset that later gains a price reads priced:true (the signal is re-evaluated live, never a frozen snapshot of what a purchase confirmation once said)', async () => {
		// Two calls, same asset, same account — the only thing that changed between them is what
		// 089 now reports. This is the "turn OFF, not just on" property the catch criterion
		// requires ("at any later time"): a marker that can only ever turn on is a bug that
		// outlives the condition it reports. loadHeldSecurities has no memory between calls — this
		// test exists to make that property explicit and watched.
		const holdings = [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }];
		const assets = [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }];

		const { supabase: beforeSupabase } = makeSupabase({ holdings, assets, pricedRows: [{ asset_id: 501, priced: false }] });
		const before = await loadHeldSecurities(beforeSupabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(before, 501)?.priced).toBe(false);

		const { supabase: afterSupabase } = makeSupabase({ holdings, assets, pricedRows: [{ asset_id: 501, priced: true }] });
		const after = await loadHeldSecurities(afterSupabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(after, 501)?.priced).toBe(true);
	});

	it('multiple held assets get independent priced flags, correctly correlated by asset_id (not by array position)', async () => {
		const { supabase } = makeSupabase({
			holdings: [
				{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 },
				{ account_id: ACCOUNT_ID, asset_id: 502, quantity: 5 }
			],
			assets: [
				{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' },
				{ asset_id: 502, symbol: null, name: 'Rental House' }
			],
			// Deliberately returned in the OPPOSITE order from the holdings/assets arrays above, and
			// with 502 (not 501) priced — a positional (rather than asset_id-keyed) correlation bug
			// would silently swap these.
			pricedRows: [
				{ asset_id: 502, priced: true },
				{ asset_id: 501, priced: false }
			]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
		expect(findBySecurityId(rows, 502)?.priced).toBe(true);
	});

	it('SELF-325 F1 (app-layer analog) — a very large asset_id correlates correctly, in either RPC row order; nothing here is ordering- or magnitude-sensitive the way the pre-089 truncation was', async () => {
		// The pre-089 bug truncated the HIGHEST asset_id first (the raw query ordered asset_id
		// ascending and PostgREST's row cap cut off whatever came last). 089 returns one row per
		// input id with no row-count relationship to price history, so there is no analogous
		// truncation risk left — but a correlation bug (mis-keying a high/unusual asset_id) would
		// still be a real, different way to reproduce the same user-visible symptom. This pins that
		// down at the app layer, independent of 089's own pgTAP coverage for the real >1000-row cap.
		const HIGH_ASSET_ID = 999_999_999;
		const { supabase: rpcOrderA } = makeSupabase({
			holdings: [
				{ account_id: ACCOUNT_ID, asset_id: 1, quantity: 1 },
				{ account_id: ACCOUNT_ID, asset_id: HIGH_ASSET_ID, quantity: 1 }
			],
			assets: [
				{ asset_id: 1, symbol: 'A', name: null },
				{ asset_id: HIGH_ASSET_ID, symbol: 'Z', name: null }
			],
			pricedRows: [
				{ asset_id: 1, priced: false },
				{ asset_id: HIGH_ASSET_ID, priced: true }
			]
		});
		const rowsA = await loadHeldSecurities(rpcOrderA, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rowsA, HIGH_ASSET_ID)?.priced).toBe(true);
		expect(findBySecurityId(rowsA, 1)?.priced).toBe(false);

		// Same fixture, RPC rows in the OPPOSITE order — 089's contract makes no ordering guarantee.
		const { supabase: rpcOrderB } = makeSupabase({
			holdings: [
				{ account_id: ACCOUNT_ID, asset_id: 1, quantity: 1 },
				{ account_id: ACCOUNT_ID, asset_id: HIGH_ASSET_ID, quantity: 1 }
			],
			assets: [
				{ asset_id: 1, symbol: 'A', name: null },
				{ asset_id: HIGH_ASSET_ID, symbol: 'Z', name: null }
			],
			pricedRows: [
				{ asset_id: HIGH_ASSET_ID, priced: true },
				{ asset_id: 1, priced: false }
			]
		});
		const rowsB = await loadHeldSecurities(rpcOrderB, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rowsB, HIGH_ASSET_ID)?.priced).toBe(true);
		expect(findBySecurityId(rowsB, 1)?.priced).toBe(false);
	});

	it('fail-CLOSED on an RPC error: defaults every asset to priced:false, never throws, never defaults true', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [],
			pricedError: { message: 'connection reset' }
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('calls fn_asset_priced_flags with the SAME as_of as the holdings read — never calls the clock twice', async () => {
		const { supabase, rpcCalls } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [{ asset_id: 501, priced: true }]
		});
		await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		const call = rpcCalls.find((c) => c.fn === 'fn_asset_priced_flags');
		expect((call?.args as { p_as_of: unknown })?.p_as_of).toBe(AS_OF);
	});

	it('scopes fn_asset_priced_flags to the held asset_ids only, in exactly ONE round trip', async () => {
		const { supabase, rpcCalls } = makeSupabase({
			holdings: [
				{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 },
				{ account_id: ACCOUNT_ID, asset_id: 502, quantity: 5 }
			],
			assets: [
				{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' },
				{ asset_id: 502, symbol: null, name: 'Rental House' }
			],
			pricedRows: [
				{ asset_id: 501, priced: true },
				{ asset_id: 502, priced: false }
			]
		});
		await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		const pricedCalls = rpcCalls.filter((c) => c.fn === 'fn_asset_priced_flags');
		expect(pricedCalls).toHaveLength(1);
		expect((pricedCalls[0]?.args as { p_asset_ids: unknown })?.p_asset_ids).toEqual([501, 502]);
	});

	it('SELF-325 Sec F1, STRUCTURAL — loadHeldSecurities NEVER selects from eod_price directly; the row-cap exposure is closed by construction, not by a bound that could be silently removed', async () => {
		// This is the regression test for F1 that actually cannot be defeated by "the fixture wasn't
		// big enough": the pre-089 bug existed because this code path fetched raw eod_price rows at
		// all. As long as `.from('eod_price')` is never called here, no fixture size — 10 rows or
		// 10 million — can reproduce PostgREST's row-cap truncation, because the query that could
		// exceed it no longer exists. The makeSupabase stub's `from()` throws on any table other
		// than 'asset' specifically so a reintroduced eod_price fetch fails LOUD, immediately, on
		// every test in this file — not just on one dedicated to noticing it.
		const { supabase, fromCalls } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			pricedRows: [{ asset_id: 501, priced: true }]
		});
		await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(fromCalls).not.toContain('eod_price');
		expect(fromCalls).toEqual(['asset']);
	});
});
