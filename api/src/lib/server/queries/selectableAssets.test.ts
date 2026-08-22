// selectableAssets.test.ts — SELF-325 selectable-assets (own + global) reader.
// Mocks the supabase chain (schema→from→select→[eq]→[or]→order→order→limit / →maybeSingle) as a
// thenable builder, mirroring the sibling query-module tests but supporting the extra
// eq/or/limit hops this module's search + filter options need.

import { describe, it, expect, vi } from 'vitest';
import { loadSelectableAssets, loadSelectableAssetById } from './selectableAssets';
import type { SupabaseClient } from '@supabase/supabase-js';

/** A chainable mock query builder: every hop returns itself and records its call; awaiting it
 *  resolves to `result` (mirrors PostgREST's real builder, which is PromiseLike). */
function makeBuilder(result: { data?: unknown; error?: unknown }) {
	const calls: { method: string; args: unknown[] }[] = [];
	const builder: Record<string, unknown> = {};
	for (const method of ['eq', 'or', 'order', 'limit']) {
		builder[method] = vi.fn((...args: unknown[]) => {
			calls.push({ method, args });
			return builder;
		});
	}
	builder.maybeSingle = vi.fn(async () => result);
	// PromiseLike — `await query` resolves to `result` without an explicit terminal call
	// (loadSelectableAssets awaits the chain directly after .limit()).
	(builder as { then: PromiseLike<unknown>['then'] }).then = (onFulfilled, onRejected) =>
		Promise.resolve(result).then(onFulfilled, onRejected);
	return { builder, calls };
}

function makeSupabase(result: { data?: unknown; error?: unknown }) {
	const { builder, calls } = makeBuilder(result);
	const select = vi.fn(() => builder);
	const from = vi.fn(() => ({ select }));
	const schema = vi.fn(() => ({ from }));
	return { supabase: { schema } as unknown as SupabaseClient, schema, from, select, builder, calls };
}

const ROW_GLOBAL = {
	asset_id: 1,
	users_id: null,
	asset_type: 'equity',
	pricing_source: 'market_feed',
	symbol: 'AAPL',
	cusip: null,
	name: 'Apple Inc',
	currency: 'USD'
};
const ROW_OWN = {
	asset_id: 2,
	users_id: '11111111-1111-4111-8111-111111111111',
	asset_type: 'real_estate',
	pricing_source: 'manual_valuation',
	symbol: null,
	cusip: null,
	name: 'Rental House',
	currency: 'USD'
};

describe('loadSelectableAssets', () => {
	it('reads pfin.asset and maps users_id → is_global', async () => {
		const { supabase, schema, from } = makeSupabase({ data: [ROW_GLOBAL, ROW_OWN], error: null });
		const { assets, error } = await loadSelectableAssets(supabase);

		expect(schema).toHaveBeenCalledWith('pfin');
		expect(from).toHaveBeenCalledWith('asset');
		expect(error).toBe(false);
		expect(assets).toEqual([
			{
				asset_id: 1,
				asset_type: 'equity',
				pricing_source: 'market_feed',
				symbol: 'AAPL',
				cusip: null,
				name: 'Apple Inc',
				currency: 'USD',
				is_global: true
			},
			{
				asset_id: 2,
				asset_type: 'real_estate',
				pricing_source: 'manual_valuation',
				symbol: null,
				cusip: null,
				name: 'Rental House',
				currency: 'USD',
				is_global: false
			}
		]);
	});

	it('applies the assetType filter via .eq', async () => {
		const { supabase, builder } = makeSupabase({ data: [], error: null });
		await loadSelectableAssets(supabase, { assetType: 'equity' });
		expect(builder.eq).toHaveBeenCalledWith('asset_type', 'equity');
	});

	it('applies a search as an or-ilike over symbol/name, stripping structurally-significant chars', async () => {
		const { supabase, builder } = makeSupabase({ data: [], error: null });
		await loadSelectableAssets(supabase, { search: 'AAPL,)(evil' });
		expect(builder.or).toHaveBeenCalledWith('symbol.ilike.%AAPLevil%,name.ilike.%AAPLevil%');
	});

	it('omits the or-filter when search is blank/whitespace', async () => {
		const { supabase, builder } = makeSupabase({ data: [], error: null });
		await loadSelectableAssets(supabase, { search: '   ' });
		expect(builder.or).not.toHaveBeenCalled();
	});

	it('defaults the limit to 50; a caller-supplied limit overrides it', async () => {
		const { supabase, builder } = makeSupabase({ data: [], error: null });
		await loadSelectableAssets(supabase);
		expect(builder.limit).toHaveBeenCalledWith(50);

		await loadSelectableAssets(supabase, { limit: 10 });
		expect(builder.limit).toHaveBeenCalledWith(10);
	});

	it('fail-soft: read error → { assets: [], error: true }', async () => {
		const { supabase } = makeSupabase({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		expect(await loadSelectableAssets(supabase)).toEqual({ assets: [], error: true });
		spy.mockRestore();
	});

	it('empty result → { assets: [], error: false } (true-empty, not a failure)', async () => {
		const { supabase } = makeSupabase({ data: [], error: null });
		expect(await loadSelectableAssets(supabase)).toEqual({ assets: [], error: false });
	});
});

describe('loadSelectableAssetById', () => {
	it('returns the mapped asset when RLS admits it', async () => {
		const { supabase, builder } = makeSupabase({ data: ROW_GLOBAL, error: null });
		const asset = await loadSelectableAssetById(supabase, 1);
		expect(builder.eq).toHaveBeenCalledWith('asset_id', 1);
		expect(asset).toEqual({
			asset_id: 1,
			asset_type: 'equity',
			pricing_source: 'market_feed',
			symbol: 'AAPL',
			cusip: null,
			name: 'Apple Inc',
			currency: 'USD',
			is_global: true
		});
	});

	it('returns null for a cross-tenant / nonexistent asset_id (no existence leak)', async () => {
		const { supabase } = makeSupabase({ data: null, error: null });
		expect(await loadSelectableAssetById(supabase, 999)).toBeNull();
	});

	it('returns null on a read error (same shape as not-found)', async () => {
		const { supabase } = makeSupabase({ data: null, error: { message: 'boom' } });
		const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
		expect(await loadSelectableAssetById(supabase, 1)).toBeNull();
		spy.mockRestore();
	});
});
