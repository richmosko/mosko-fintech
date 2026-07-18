// resolutionCaseNormalize.test.ts — Flag-2 V1-now case-normalize (slice 3b): symbol + cusip
// canonicalize to .trim().toUpperCase() at BOTH the resolve SELECTs AND the auto-register
// INSERT stored value, so cross-provider case variants (Plaid `voo` vs SimpleFIN `VOO`) dedup
// to ONE global pfin.asset row. Fake tx captures bound VALUES (no DB).

import { describe, it, expect } from 'vitest';
import { resolveSecurityId, type ResolvableAsset } from '../src/ingest/resolution.js';
import type { Tx } from '../src/db/TenantBoundClient.js';

/** Fake tagged-template tx capturing the bound values per call + scripting result rows. */
function fakeTx(results: unknown[][]): { tx: Tx; values: unknown[][] } {
	const values: unknown[][] = [];
	let call = 0;
	const tagged = (_strings: TemplateStringsArray, ...vals: unknown[]) => {
		values.push(vals);
		const r = results[call] ?? [];
		call += 1;
		return Promise.resolve(r);
	};
	return { tx: tagged as unknown as Tx, values };
}

describe('resolveSecurityId — case-normalize (voo/VOO → one global row)', () => {
	it('uppercases a lowercase symbol in BOTH the resolve SELECT and the INSERT stored value', async () => {
		// symbol-only: (1) symbol SELECT miss → (2) INSERT returns asset_id.
		const { tx, values } = fakeTx([[], [{ asset_id: 7 }]]);
		const a: ResolvableAsset = { symbol: 'voo', cusip: null, assetType: 'etf', name: 'Vanguard 500', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(7);

		// (1) symbol SELECT value uppercased.
		expect(values[0]).toEqual(['VOO']);
		// (2) INSERT: [assetType, pricingSource, symbol, cusip, name, currency] → stored symbol uppercased.
		expect(values[1]).toContain('VOO');
	});

	it('uppercases a lowercase cusip in the cusip SELECT and the INSERT stored value', async () => {
		// cusip present: (1) cusip SELECT miss → (2) symbol SELECT miss → (3) INSERT.
		const { tx, values } = fakeTx([[], [], [{ asset_id: 9 }]]);
		const a: ResolvableAsset = { symbol: 'voo', cusip: 'abc123', assetType: 'bond', name: 'B', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(9);

		expect(values[0]).toEqual(['ABC123']); // cusip SELECT uppercased
		expect(values[1]).toEqual(['VOO']); // symbol SELECT uppercased
		expect(values[2]).toContain('VOO'); // INSERT symbol uppercased
		expect(values[2]).toContain('ABC123'); // INSERT cusip uppercased
	});

	it('trims + uppercases (whitespace-padded mixed-case)', async () => {
		const { tx, values } = fakeTx([[{ asset_id: 3 }]]);
		const a: ResolvableAsset = { symbol: '  Aapl ', cusip: null, assetType: 'equity', name: 'Apple', currency: 'USD' };
		expect(await resolveSecurityId(tx, a)).toBe(3);
		expect(values[0]).toEqual(['AAPL']);
	});
});
