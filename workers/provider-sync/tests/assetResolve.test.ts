// assetResolve.test.ts — SELF-325 productionAssetResolveDeps wiring. Asserts the THIN-WRAPPER
// property structurally: the module calls the EXISTING resolveSecurityId (never a re-implemented
// copy of the key order — the addendum's named drift surface), opens a withServiceRole()
// transaction on a tenant-bound client, and always closes the client (even on failure).

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { WorkerConfig } from '../src/config/env.js';

const resolveSecurityIdMock = vi.fn(async () => 501);

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
		expect(result).toEqual({ assetId: 501 });
		expect(endMock).toHaveBeenCalledTimes(1);
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
