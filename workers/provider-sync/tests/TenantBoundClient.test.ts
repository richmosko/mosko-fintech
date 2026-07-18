// TenantBoundClient.test.ts — the enumeration-only client (slice 3b): withTenant is disabled
// fail-closed (no tenant bound), withServiceRole remains available. No live DB (postgres.js
// connects lazily; we never issue a query, and we end() the idle connection).

import { describe, it, expect } from 'vitest';
import { TenantBoundClient } from '../src/db/TenantBoundClient.js';
import type { WorkerConfig } from '../src/config/env.js';

const CONFIG: WorkerConfig = {
	db: { host: '127.0.0.1', port: 5432, database: 'd', user: 'u', password: 'p' },
	plaid: { clientId: 'c', secret: 's', env: 'sandbox' },
	simplefinToken: undefined,
	discordWebhookUrl: undefined
};

describe('TenantBoundClient.forEnumeration (enumeration-only, no tenant bound)', () => {
	it('has a null usersId', async () => {
		const c = TenantBoundClient.forEnumeration(CONFIG);
		try {
			expect(c.usersId).toBeNull();
		} finally {
			await c.end();
		}
	});

	it('withTenant() is disabled fail-closed (no RLS context to bind)', async () => {
		const c = TenantBoundClient.forEnumeration(CONFIG);
		try {
			await expect(c.withTenant(async () => 1)).rejects.toThrow(/enumeration-only/);
		} finally {
			await c.end();
		}
	});

	it('forTenant() rejects a non-uuid (fail-closed)', () => {
		expect(() => TenantBoundClient.forTenant(CONFIG, 'not-a-uuid')).toThrow(/real users_id/);
	});
});
