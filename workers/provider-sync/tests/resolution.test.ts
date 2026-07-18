// resolution.test.ts — pure resolution helpers + the auto-register logic against a
// fake tx (no DB). The fake tx records the SQL fragments it is called with so we can
// assert the cusip-first order + the ON CONFLICT arbiter selection.

import { describe, it, expect, vi } from 'vitest';
import { assetKey, pricingSourceForAssetType, resolveSecurityId, type ResolvableAsset } from '../src/ingest/resolution.js';
import type { Tx } from '../src/db/TenantBoundClient.js';

describe('assetKey (cusip-first, normalized)', () => {
	it('prefers cusip', () => {
		expect(assetKey({ symbol: 'VOO', cusip: '922908363' })).toBe('cusip:922908363');
	});
	it('falls back to symbol', () => {
		expect(assetKey({ symbol: 'voo', cusip: null })).toBe('symbol:VOO'); // upper-cased
	});
	it('is null for blank/blank', () => {
		expect(assetKey({ symbol: null, cusip: '  ' })).toBeNull();
	});
});

describe('pricingSourceForAssetType', () => {
	it('routes market instruments to market_feed', () => {
		expect(pricingSourceForAssetType('equity')).toBe('market_feed');
		expect(pricingSourceForAssetType('bond')).toBe('market_feed');
	});
	it('routes currency/metal/physical to their feeds', () => {
		expect(pricingSourceForAssetType('currency')).toBe('fx_feed');
		expect(pricingSourceForAssetType('metal')).toBe('spot_feed');
		expect(pricingSourceForAssetType('real_estate')).toBe('manual_valuation');
	});
});

// A minimal fake postgres.js tagged-template that returns a scripted sequence of results
// and captures the composed query text (strings joined by '?') for assertions.
function fakeTx(results: unknown[][]): { tx: Tx; queries: string[] } {
	const queries: string[] = [];
	let call = 0;
	const tagged = (strings: TemplateStringsArray, ..._vals: unknown[]) => {
		queries.push(strings.join('?').replace(/\s+/g, ' ').trim());
		const r = results[call] ?? [];
		call += 1;
		return Promise.resolve(r);
	};
	return { tx: tagged as unknown as Tx, queries };
}

describe('resolveSecurityId', () => {
	it('returns null for a blank/blank sweep (no query)', async () => {
		const { tx, queries } = fakeTx([]);
		const a: ResolvableAsset = { symbol: null, cusip: null, assetType: 'equity', name: 'x', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBeNull();
		expect(queries).toHaveLength(0);
	});

	it('resolves by cusip FIRST (does not fall through to symbol)', async () => {
		// First query (cusip select) hits → returns asset_id 42, no further queries.
		const { tx, queries } = fakeTx([[{ asset_id: 42 }]]);
		const a: ResolvableAsset = { symbol: 'CILH4422711', cusip: '912797KL5', assetType: 'bond', name: 'T-Bill', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(42);
		expect(queries).toHaveLength(1);
		expect(queries[0]).toContain('cusip =');
	});

	it('falls back to symbol match when cusip misses', async () => {
		// cusip select miss ([]) → symbol select hit ([{asset_id:7}]).
		const { tx, queries } = fakeTx([[], [{ asset_id: 7 }]]);
		const a: ResolvableAsset = { symbol: 'VOO', cusip: '922908363', assetType: 'etf', name: 'VOO', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(7);
		expect(queries[1]).toContain('symbol =');
	});

	it('auto-registers a GLOBAL row (symbol arbiter) on full miss, then returns the new id', async () => {
		// cusip is null → NO cusip select. query0 = symbol select (miss); query1 = INSERT (hit).
		const { tx, queries } = fakeTx([[], [{ asset_id: 100 }]]);
		const a: ResolvableAsset = { symbol: 'NEWCO', cusip: null, assetType: 'equity', name: 'NewCo', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(100);
		expect(queries[0]).toContain('symbol =');
		expect(queries[1]).toContain('insert into pfin.asset');
		expect(queries[1]).toContain('on conflict (symbol) where users_id is null do nothing');
	});

	it('uses the cusip arbiter when the security has no symbol', async () => {
		// cusip miss (symbol absent, so no symbol select), INSERT via cusip arbiter → id 55.
		const { tx, queries } = fakeTx([[], [{ asset_id: 55 }]]);
		const a: ResolvableAsset = { symbol: null, cusip: '912797KL5', assetType: 'bond', name: 'T-Bill', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(55);
		// query 0 = cusip select (miss); query 1 = insert via cusip arbiter.
		expect(queries[1]).toContain('on conflict (cusip) where users_id is null and cusip is not null');
	});

	it('re-selects after ON CONFLICT DO NOTHING (concurrent insert)', async () => {
		// cusip miss, symbol miss, INSERT DO NOTHING (returns []), re-select cusip → 88.
		const { tx } = fakeTx([[], [], [], [{ asset_id: 88 }]]);
		const a: ResolvableAsset = { symbol: 'RACE', cusip: 'ABC123', assetType: 'equity', name: 'Race', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(88);
	});
});
