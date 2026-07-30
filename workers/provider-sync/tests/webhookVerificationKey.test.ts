// webhookVerificationKey.test.ts — SELF-206 Option-1 credentialed JWK fetch (worker side).
// The credentialed Plaid call is mocked (no live Plaid); asserts we forward ONLY the public JWK
// material (no created_at/expired_at) and pass the kid through as key_id.

import { describe, it, expect, vi } from 'vitest';
import { fetchWebhookVerificationKey, type WebhookKeyClient } from '../src/http/webhookVerificationKey.js';

describe('fetchWebhookVerificationKey', () => {
	it('calls webhookVerificationKeyGet with { key_id } and returns ONLY the public JWK subset', async () => {
		const webhookVerificationKeyGet = vi.fn(async () => ({
			data: {
				key: {
					kty: 'EC',
					crv: 'P-256',
					x: 'X',
					y: 'Y',
					kid: 'kid-42',
					alg: 'ES256',
					use: 'sig',
					// Extra fields the real Plaid response carries — must NOT be forwarded.
					created_at: 1_700_000_000,
					expired_at: null
				}
			}
		}));
		const client = { webhookVerificationKeyGet } as unknown as WebhookKeyClient;

		const jwk = await fetchWebhookVerificationKey(client, 'kid-42');

		expect(webhookVerificationKeyGet).toHaveBeenCalledWith({ key_id: 'kid-42' });
		expect(jwk).toEqual({ kty: 'EC', crv: 'P-256', x: 'X', y: 'Y', kid: 'kid-42', alg: 'ES256', use: 'sig' });
		// Defense-in-depth: no non-public / metadata fields leaked into the forwarded object.
		expect(Object.keys(jwk).sort()).toEqual(['alg', 'crv', 'kid', 'kty', 'use', 'x', 'y']);
	});

	it('propagates a Plaid/transport failure (caller fails the webhook CLOSED)', async () => {
		const client = {
			webhookVerificationKeyGet: vi.fn(async () => {
				throw new Error('RATE_LIMIT');
			})
		} as unknown as WebhookKeyClient;
		await expect(fetchWebhookVerificationKey(client, 'kid-1')).rejects.toThrow();
	});
});
