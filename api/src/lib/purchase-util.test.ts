// purchase-util.test.ts — SELF-325 manual-purchase display/derivation helpers.

import { describe, it, expect } from 'vitest';
import {
	selectableAssetLabel,
	derivedPerUnitPrice,
	formatPrice,
	assetTypeLabel,
	type SelectableAssetOption
} from './purchase-util';

function asset(overrides: Partial<SelectableAssetOption>): SelectableAssetOption {
	return {
		asset_id: 1,
		asset_type: 'equity',
		symbol: null,
		cusip: null,
		name: null,
		currency: 'USD',
		is_global: true,
		...overrides
	};
}

describe('selectableAssetLabel', () => {
	it('symbol + name, global: "SYMBOL — Name" with no ownership suffix', () => {
		expect(selectableAssetLabel(asset({ symbol: 'AAPL', name: 'Apple Inc.', is_global: true }))).toBe(
			'AAPL — Apple Inc.'
		);
	});

	it('symbol + name, owned: same shape plus "(yours)"', () => {
		expect(
			selectableAssetLabel(asset({ symbol: 'AAPL', name: 'Apple Inc.', is_global: false }))
		).toBe('AAPL — Apple Inc. (yours)');
	});

	it('symbol only', () => {
		expect(selectableAssetLabel(asset({ symbol: 'VOO', is_global: true }))).toBe('VOO');
	});

	it('name only (no symbol) — falls through to name', () => {
		expect(selectableAssetLabel(asset({ name: 'My Rental Property', is_global: false }))).toBe(
			'My Rental Property (yours)'
		);
	});

	it('neither symbol nor name — falls through to cusip, then the id fallback', () => {
		expect(selectableAssetLabel(asset({ cusip: '037833100', is_global: true }))).toBe('037833100');
		expect(selectableAssetLabel(asset({ asset_id: 42, is_global: true }))).toBe('Asset #42');
	});

	it('a global row and the caller’s own same-named row are DISTINGUISHABLE (the reason the suffix exists)', () => {
		const global = asset({ asset_id: 1, symbol: 'ABC', is_global: true });
		const owned = asset({ asset_id: 2, symbol: 'ABC', is_global: false });
		expect(selectableAssetLabel(global)).not.toBe(selectableAssetLabel(owned));
	});
});

describe('derivedPerUnitPrice — mirrors 088’s round(cost_basis / quantity, 4)', () => {
	it('computes a simple per-unit price', () => {
		expect(derivedPerUnitPrice(10, 1000)).toBe(100);
	});

	it('rounds to 4 decimal places', () => {
		expect(derivedPerUnitPrice(3, 10)).toBe(3.3333);
	});

	it('088’s own worked example: quantity > 20000 x cost_basis rounds to 0.0000', () => {
		// cost_basis 10.00 over quantity 1,000,000 -> 0.00001, rounds to 0.0000.
		expect(derivedPerUnitPrice(1_000_000, 10)).toBe(0);
	});

	it('returns null (nothing to preview) when either input is not yet a usable positive number', () => {
		expect(derivedPerUnitPrice(0, 100)).toBeNull();
		expect(derivedPerUnitPrice(100, 0)).toBeNull();
		expect(derivedPerUnitPrice(-1, 100)).toBeNull();
		expect(derivedPerUnitPrice(NaN, 100)).toBeNull();
		expect(derivedPerUnitPrice(100, Infinity)).toBeNull();
	});
});

describe('formatPrice', () => {
	it('always shows exactly 4 decimal places, matching numeric(20,4)', () => {
		expect(formatPrice(100)).toBe('100.0000');
		expect(formatPrice(3.3333)).toBe('3.3333');
		expect(formatPrice(0)).toBe('0.0000');
	});
});

describe('assetTypeLabel', () => {
	it('labels a known asset_type', () => {
		expect(assetTypeLabel('real_estate')).toBe('Real estate');
		expect(assetTypeLabel('etf')).toBe('ETF');
	});

	it('falls back to the raw value for an unrecognized type (forward-compat, never throws)', () => {
		expect(assetTypeLabel('some_future_type')).toBe('some_future_type');
	});

	it('labels currency too (the map does not hide the value it refuses elsewhere)', () => {
		expect(assetTypeLabel('currency')).toBe('Currency');
	});
});
