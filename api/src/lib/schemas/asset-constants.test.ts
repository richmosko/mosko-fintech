// asset-constants.test.ts — MINT_ASSET_TYPES drift guard. It is hand-listed (not filtered from
// ASSET_TYPES at runtime, to stay a plain literal tuple for z.enum), so a future 016 CHECK change
// must update both lists in step — this test is the watcher.

import { describe, it, expect } from 'vitest';
import { ASSET_TYPES, MINT_ASSET_TYPES } from './asset-constants';

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
