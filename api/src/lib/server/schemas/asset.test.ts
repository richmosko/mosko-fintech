// asset.test.ts — SELF-325 asset-resolve schema coverage (node env).
// Locks the Lock-14 security boundary at the input layer: `.strict()` (mass-assignment),
// symbol/cusip pattern+length (namespace-pollution boundary), the asset_type enum, and the
// at-least-one-identity refine.

import { describe, it, expect } from 'vitest';
import { assetResolveSchema, fieldErrors } from './asset';

describe('assetResolveSchema', () => {
	it('accepts a valid symbol + asset_type', () => {
		const r = assetResolveSchema.safeParse({ symbol: 'AAPL', cusip: '', asset_type: 'equity', name: 'Apple Inc' });
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.symbol).toBe('AAPL');
			expect(r.data.cusip).toBeNull();
			expect(r.data.name).toBe('Apple Inc');
		}
	});

	it('accepts a valid cusip with no symbol', () => {
		const r = assetResolveSchema.safeParse({ symbol: '', cusip: '037833100', asset_type: 'bond', name: '' });
		expect(r.success).toBe(true);
		if (r.success) {
			expect(r.data.symbol).toBeNull();
			expect(r.data.cusip).toBe('037833100');
			expect(r.data.name).toBeNull();
		}
	});

	it('rejects when both symbol and cusip are blank (no identity to resolve)', () => {
		const r = assetResolveSchema.safeParse({ symbol: '', cusip: '', asset_type: 'equity', name: '' });
		expect(r.success).toBe(false);
		if (!r.success) expect(fieldErrors(r.error)).toHaveProperty('symbol');
	});

	it('rejects a malformed symbol (namespace-pollution boundary — pattern)', () => {
		for (const bad of ['AAPL; DROP TABLE', 'A A', '<script>', '日本語']) {
			const r = assetResolveSchema.safeParse({ symbol: bad, cusip: null, asset_type: 'equity', name: null });
			expect(r.success).toBe(false);
		}
	});

	it('rejects a symbol over 20 characters', () => {
		const r = assetResolveSchema.safeParse({
			symbol: 'A'.repeat(21),
			cusip: null,
			asset_type: 'equity',
			name: null
		});
		expect(r.success).toBe(false);
	});

	it('rejects a cusip that is not exactly 9 alphanumeric characters', () => {
		for (const bad of ['TOOSHORT', '0378331000', '03783310-']) {
			const r = assetResolveSchema.safeParse({ symbol: null, cusip: bad, asset_type: 'equity', name: null });
			expect(r.success).toBe(false);
		}
	});

	it('rejects an asset_type outside 016\'s CHECK vocabulary', () => {
		const r = assetResolveSchema.safeParse({ symbol: 'AAPL', cusip: null, asset_type: 'nonsense', name: null });
		expect(r.success).toBe(false);
	});

	it('accepts every 016 asset_type value', () => {
		const types = [
			'equity',
			'etf',
			'fund',
			'money_market',
			'bond',
			'future',
			'option',
			'crypto',
			'real_estate',
			'vehicle',
			'metal',
			'collectible',
			'currency',
			'private'
		];
		for (const asset_type of types) {
			const r = assetResolveSchema.safeParse({ symbol: 'X', cusip: null, asset_type, name: null });
			expect(r.success).toBe(true);
		}
	});

	it('rejects a name over 200 characters', () => {
		const r = assetResolveSchema.safeParse({
			symbol: 'AAPL',
			cusip: null,
			asset_type: 'equity',
			name: 'x'.repeat(201)
		});
		expect(r.success).toBe(false);
	});

	it('rejects an extra field (Lock 14 mass-assignment fence, .strict)', () => {
		const r = assetResolveSchema.safeParse({
			symbol: 'AAPL',
			cusip: null,
			asset_type: 'equity',
			name: null,
			users_id: 'other-tenant'
		});
		expect(r.success).toBe(false);
	});

	it('rejects an extra field even when it looks like a currency override', () => {
		// Currency is deliberately NOT a form field (mirrors account.ts) — a stray `currency` key
		// must be rejected, never silently accepted/ignored.
		const r = assetResolveSchema.safeParse({
			symbol: 'AAPL',
			cusip: null,
			asset_type: 'equity',
			name: null,
			currency: 'EUR'
		});
		expect(r.success).toBe(false);
	});
});
