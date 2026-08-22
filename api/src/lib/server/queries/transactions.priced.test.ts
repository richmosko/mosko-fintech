// transactions.priced.test.ts — SELF-325 P-b account-detail read-side signal:
// loadHeldSecurities' `priced` field (via the internal loadPricedFlags helper).
//
// F/CTO catch criterion (verbatim, per Architect): "after this PR, a user who records a purchase
// that cannot be priced must be able to see that fact on the account, at any later time — not
// only in the confirmation they saw once." This file is the watcher for that criterion at the
// query layer (load.server.test.ts carries the pass-through watcher at the page-load layer).
//
// THE LEG THAT MATTERS (Architect, verbatim): a held asset with a ZERO-VALUED eod_price row at
// the max price_date must still be `priced: false` — a bare presence check passes there and is
// exactly the F3-b spelling the original 087/088 watchers were built to catch. Inversion-tested
// below: striking `Number(row.price) > 0` down to a bare presence check reds that leg specifically.

import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadHeldSecurities, type HeldSecurity } from './transactions';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const ACCOUNT_ID = 10;
const AS_OF = unsafeAsOfForTest('2026-08-15');

type EodPriceRow = { asset_id: number; price_date: string; price: number | string };

/** A minimal supabase stub covering the three reads loadHeldSecurities makes: the
 *  fn_holdings_as_of RPC, the pfin.asset label select, and the pfin.eod_price priced-flag select.
 *  Each `eod_price` chain hop (.in/.lte/.order/.order) returns itself; awaiting resolves to the
 *  configured price rows (mirrors the thenable-builder shape used across this test suite). */
function makeSupabase(opts: {
	holdings?: Array<{ account_id: number; asset_id: number; quantity: number }>;
	assets?: Array<{ asset_id: number; symbol: string | null; name: string | null }>;
	priceRows?: EodPriceRow[];
	priceError?: { message: string } | null;
}) {
	const rpc = vi.fn(async () => ({ data: opts.holdings ?? [], error: null }));

	const assetSelect = vi.fn(() => ({
		in: vi.fn(async () => ({ data: opts.assets ?? [], error: null }))
	}));

	const eodPriceCalls: { in: unknown[]; lte: unknown[] } = { in: [], lte: [] };
	function eodPriceBuilder() {
		const b: Record<string, unknown> = {};
		b.in = vi.fn((...args: unknown[]) => {
			eodPriceCalls.in.push(args);
			return b;
		});
		b.lte = vi.fn((...args: unknown[]) => {
			eodPriceCalls.lte.push(args);
			return b;
		});
		b.order = vi.fn(() => b);
		(b as { then: PromiseLike<unknown>['then'] }).then = (onF, onR) =>
			Promise.resolve({ data: opts.priceRows ?? [], error: opts.priceError ?? null }).then(onF, onR);
		return b;
	}

	const from = vi.fn((table: string) => {
		if (table === 'asset') return { select: assetSelect };
		if (table === 'eod_price') return { select: () => eodPriceBuilder() };
		throw new Error(`unexpected table: ${table}`);
	});
	const schema = vi.fn(() => ({ from, rpc }));
	return { supabase: { schema } as unknown as SupabaseClient, eodPriceCalls };
}

function findBySecurityId(rows: HeldSecurity[], id: number): HeldSecurity | undefined {
	return rows.find((r) => r.security_id === id);
}

describe('loadHeldSecurities — priced field (SELF-325 P-b)', () => {
	it('a held asset with NO eod_price row → priced: false', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: []
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('THE LEG THAT MATTERS — a held asset with a ZERO-VALUED row at the max price_date → priced: false (F3-b: presence alone would pass)', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 0 }]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('a negative price at the max date → priced: false (the fence is > 0, not >= 0)', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: -5 }]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('a held asset with a normal positive price at the max date → priced: true', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 150.25 }]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(true);
	});

	it('THE CLEARING CASE — a previously-unpriced asset that later gains a price reads priced:true (the signal is re-evaluated live, never a frozen snapshot of what a purchase confirmation once said)', async () => {
		// Two calls, same asset, same account — the only thing that changed between them is what
		// eod_price now contains. This is the "turn OFF, not just on" property the catch criterion
		// requires ("at any later time"): a marker that can only ever turn on is a bug that
		// outlives the condition it reports. loadHeldSecurities has no memory between calls — this
		// test exists to make that property explicit and watched, not to exercise new code the
		// "normal positive price" case above doesn't already run.
		const holdings = [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }];
		const assets = [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }];

		const { supabase: beforeSupabase } = makeSupabase({ holdings, assets, priceRows: [] });
		const before = await loadHeldSecurities(beforeSupabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(before, 501)?.priced).toBe(false);

		const { supabase: afterSupabase } = makeSupabase({
			holdings,
			assets,
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 150.25 }]
		});
		const after = await loadHeldSecurities(afterSupabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(after, 501)?.priced).toBe(true);
	});

	it('picks the MAXIMUM price_date row when multiple exist, ignoring an older positive price if the newest is zero', async () => {
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			// Ordered desc by price_date (as the real query requests) — first row is the max date.
			priceRows: [
				{ asset_id: 501, price_date: '2026-08-15', price: 0 },
				{ asset_id: 501, price_date: '2026-08-01', price: 150.0 }
			]
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
	});

	it('SELF-325 Sec C3 — a SAME-DATE tie (one positive, one zero row at the identical max price_date) reads priced:true deterministically, in EITHER row order — bool_or, not first-row', async () => {
		// This is the exact case the pre-fix "first row per asset wins" logic could not answer
		// deterministically: with no tiebreak among rows sharing the max price_date, the result
		// depended on planner-decided row order. 088's own predicate (bool_or(price > 0) over ALL
		// rows at the max date) always answers TRUE here — this test pins the TS read-side to
		// that same answer, in both possible arrival orders, so neither order can silently regress
		// back to "whichever row happened to be first."
		const holdings = [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }];
		const assets = [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }];

		const { supabase: zeroFirst } = makeSupabase({
			holdings,
			assets,
			priceRows: [
				{ asset_id: 501, price_date: '2026-08-15', price: 0 },
				{ asset_id: 501, price_date: '2026-08-15', price: 150.25 }
			]
		});
		const rowsZeroFirst = await loadHeldSecurities(zeroFirst, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rowsZeroFirst, 501)?.priced).toBe(true);

		const { supabase: positiveFirst } = makeSupabase({
			holdings,
			assets,
			priceRows: [
				{ asset_id: 501, price_date: '2026-08-15', price: 150.25 },
				{ asset_id: 501, price_date: '2026-08-15', price: 0 }
			]
		});
		const rowsPositiveFirst = await loadHeldSecurities(positiveFirst, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rowsPositiveFirst, 501)?.priced).toBe(true);
	});

	it('multiple held assets get independent priced flags', async () => {
		const { supabase } = makeSupabase({
			holdings: [
				{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 },
				{ account_id: ACCOUNT_ID, asset_id: 502, quantity: 5 }
			],
			assets: [
				{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' },
				{ asset_id: 502, symbol: null, name: 'Rental House' }
			],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 150 }]
			// asset 502 has no price rows at all.
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(true);
		expect(findBySecurityId(rows, 502)?.priced).toBe(false);
	});

	it('fail-CLOSED on a read error: defaults every asset to priced:false, never throws, never defaults true', async () => {
		const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
		const { supabase } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [],
			priceError: { message: 'connection reset' }
		});
		const rows = await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(findBySecurityId(rows, 501)?.priced).toBe(false);
		expect(errSpy).toHaveBeenCalled();
		errSpy.mockRestore();
	});

	it('uses the SAME as_of as the holdings read — never calls the clock twice', async () => {
		const { supabase, eodPriceCalls } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 150 }]
		});
		await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(eodPriceCalls.lte).toContainEqual(['price_date', AS_OF]);
	});

	it('scopes the priced query to the held asset_ids only', async () => {
		const { supabase, eodPriceCalls } = makeSupabase({
			holdings: [{ account_id: ACCOUNT_ID, asset_id: 501, quantity: 10 }],
			assets: [{ asset_id: 501, symbol: 'AAPL', name: 'Apple Inc' }],
			priceRows: [{ asset_id: 501, price_date: '2026-08-15', price: 150 }]
		});
		await loadHeldSecurities(supabase, ACCOUNT_ID, AS_OF);
		expect(eodPriceCalls.in).toContainEqual(['asset_id', [501]]);
	});
});
