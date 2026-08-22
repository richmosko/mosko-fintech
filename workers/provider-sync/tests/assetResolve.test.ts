// assetResolve.test.ts — SELF-325 productionAssetResolveDeps wiring. Asserts the THIN-WRAPPER
// property structurally: the module calls the EXISTING resolveSecurityId (never a re-implemented
// copy of the key order — the repo's named drift surface at 078), opens a withServiceRole()
// transaction on a tenant-bound client, and always closes the client (even on failure).

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { WorkerConfig } from '../src/config/env.js';

// ⚠ THE REAL WIRE-FORMAT BUG THIS SUITE MISSED (QA freeze-break, fixed here): resolveSecurityId
// is typed `Promise<number | null>`, but postgres.js returns the underlying bigint `asset_id`
// column as a STRING at runtime (TenantBoundClient sets no bigint type override) — the TS type
// was never a runtime guarantee. The mock below used to return a `number` (501), matching the
// aspirational type instead of the real shape, so this suite was GREEN while the actual wire
// format broke every /asset/resolve call downstream. Mocking the REAL runtime shape (a string)
// is the fix to the test, not just to the source — see the dedicated wire-format tests below.
const resolveSecurityIdMock = vi.fn(async () => '501');

vi.mock('../src/ingest/resolution.js', () => ({
	resolveSecurityId: (...args: unknown[]) => resolveSecurityIdMock(...args)
}));

const withServiceRoleMock = vi.fn(async (fn: (tx: unknown) => unknown) => fn('TX_SENTINEL'));
const endMock = vi.fn(async () => undefined);
const forTenantMock = vi.fn(() => ({ withServiceRole: withServiceRoleMock, end: endMock }));

vi.mock('../src/db/TenantBoundClient.js', () => ({
	TenantBoundClient: { forTenant: (...args: unknown[]) => forTenantMock(...args) }
}));

const CONFIG = {} as WorkerConfig;
const UUID = '11111111-1111-4111-8111-111111111111';

afterEach(() => {
	vi.clearAllMocks();
});

describe('productionAssetResolveDeps — thin-wrapper delegation (no re-implemented key order)', () => {
	it('binds a tenant client to ownerUserId, runs under withServiceRole, and delegates to resolveSecurityId', async () => {
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const deps = productionAssetResolveDeps(CONFIG);

		const result = await deps.resolve({
			ownerUserId: UUID,
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: 'Apple Inc',
			currency: 'USD'
		});

		expect(forTenantMock).toHaveBeenCalledWith(CONFIG, UUID);
		expect(withServiceRoleMock).toHaveBeenCalledTimes(1);
		expect(resolveSecurityIdMock).toHaveBeenCalledWith('TX_SENTINEL', {
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: 'Apple Inc',
			currency: 'USD'
		});
		expect(result).toEqual({ assetId: '501' });
		expect(endMock).toHaveBeenCalledTimes(1);
	});

	it('WIRE-FORMAT WATCHER (QA freeze-break fix): result.assetId is a STRING with typeof === "string", not a number — the exact class of bug a same-typed mock cannot catch', async () => {
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const deps = productionAssetResolveDeps(CONFIG);
		const result = await deps.resolve({
			ownerUserId: UUID,
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: null,
			currency: 'USD'
		});
		expect(typeof result.assetId).toBe('string');
	});

	it('coerces to a string even if resolveSecurityId ever returned an actual JS number (defensive — the fix must not depend on postgres.js staying misconfigured the same way forever)', async () => {
		resolveSecurityIdMock.mockResolvedValueOnce(501 as unknown as string);
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const deps = productionAssetResolveDeps(CONFIG);
		const result = await deps.resolve({
			ownerUserId: UUID,
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: null,
			currency: 'USD'
		});
		expect(result).toEqual({ assetId: '501' });
		expect(typeof result.assetId).toBe('string');
	});

	it('closes the client even when resolveSecurityId throws', async () => {
		resolveSecurityIdMock.mockRejectedValueOnce(new Error('boom'));
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const deps = productionAssetResolveDeps(CONFIG);

		await expect(
			deps.resolve({
				ownerUserId: UUID,
				symbol: 'AAPL',
				cusip: null,
				assetType: 'equity',
				name: null,
				currency: 'USD'
			})
		).rejects.toThrow('boom');
		expect(endMock).toHaveBeenCalledTimes(1);
	});

	it('passes null assetId through unchanged (SELF-200 unvalued parity, defensive)', async () => {
		resolveSecurityIdMock.mockResolvedValueOnce(null);
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const deps = productionAssetResolveDeps(CONFIG);

		const result = await deps.resolve({
			ownerUserId: UUID,
			symbol: null,
			cusip: null,
			assetType: 'equity',
			name: null,
			currency: 'USD'
		});
		expect(result).toEqual({ assetId: null });
	});
});
