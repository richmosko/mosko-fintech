// asset-constants.test.ts — MINT_ASSET_TYPES / RESOLVABLE_ASSET_TYPES drift guards. Both are
// hand-listed (not filtered from ASSET_TYPES / pricingSourceForAssetType at runtime — deliberate,
// see each constant's own comment), so a future 016 CHECK change or resolvability ruling must
// update these lists in step — these tests are the watchers.

import { describe, it, expect } from 'vitest';
import { ASSET_TYPES, MINT_ASSET_TYPES, RESOLVABLE_ASSET_TYPES } from './asset-constants';

describe('MINT_ASSET_TYPES', () => {
	it('is exactly ASSET_TYPES minus currency', () => {
		expect(new Set(MINT_ASSET_TYPES)).toEqual(new Set(ASSET_TYPES.filter((t) => t !== 'currency')));
	});

	it('does not include currency', () => {
		expect(MINT_ASSET_TYPES).not.toContain('currency');
	});

	it('has no duplicate values', () => {
		expect(new Set(MINT_ASSET_TYPES).size).toBe(MINT_ASSET_TYPES.length);
	});
});

describe('RESOLVABLE_ASSET_TYPES (SELF-325 /asset/resolve boundary — Architect ruling 2026-08-21)', () => {
	it('is exactly the 9 feed-priceable types', () => {
		expect(new Set(RESOLVABLE_ASSET_TYPES)).toEqual(
			new Set(['equity', 'etf', 'fund', 'money_market', 'bond', 'future', 'option', 'crypto', 'metal'])
		);
	});

	it('is a subset of ASSET_TYPES', () => {
		for (const t of RESOLVABLE_ASSET_TYPES) expect(ASSET_TYPES).toContain(t);
	});

	it('excludes the 4 manual_valuation personal-asset types (permanently unpriceable as a global row)', () => {
		for (const t of ['real_estate', 'vehicle', 'collectible', 'private']) {
			expect(RESOLVABLE_ASSET_TYPES).not.toContain(t);
		}
	});

	it('excludes currency (088 MINT mode already rejects it; the two surfaces must not disagree)', () => {
		expect(RESOLVABLE_ASSET_TYPES).not.toContain('currency');
	});

	it('has no duplicate values', () => {
		expect(new Set(RESOLVABLE_ASSET_TYPES).size).toBe(RESOLVABLE_ASSET_TYPES.length);
	});
});
