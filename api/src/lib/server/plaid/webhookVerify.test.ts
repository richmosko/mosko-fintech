// webhookVerify.test.ts — SELF-206 RT-05 verification unit tests. Uses REAL jose ES256 signing so
// the happy path exercises actual crypto; negative cases prove each Sec mod fails CLOSED.

import { describe, it, expect, vi } from 'vitest';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT, type JWK } from 'jose';
import {
	JwkCache,
	verifyPlaidWebhook,
	deriveProviderEventId,
	type FetchJwk
} from './webhookVerify';

const KID = 'kid-test-1';
const NOW_MS = 1_760_000_000_000; // fixed clock for deterministic iat checks.

async function makeKeypair(): Promise<{ jwk: JWK; sign: (payload: Record<string, unknown>, header?: Record<string, unknown>) => Promise<string> }> {
	const { publicKey, privateKey } = await generateKeyPair('ES256', { extractable: true });
	const pub = await exportJWK(publicKey);
	const jwk: JWK = { ...pub, kid: KID, alg: 'ES256', use: 'sig' };
	const sign = async (payload: Record<string, unknown>, header: Record<string, unknown> = {}) =>
		new SignJWT(payload).setProtectedHeader({ alg: 'ES256', kid: KID, ...header }).sign(privateKey);
	return { jwk, sign };
}

function sha256hex(s: string): string {
	return createHash('sha256').update(s, 'utf8').digest('hex');
}

/** A verified webhook body + its correctly-signed Plaid-Verification JWT. */
async function signedWebhook(
	body: string,
	over: { iat?: number } = {}
): Promise<{ jwt: string; cache: JwkCache; fetch: ReturnType<typeof vi.fn> }> {
	const { jwk, sign } = await makeKeypair();
	const iat = over.iat ?? Math.floor(NOW_MS / 1000);
	const jwt = await sign({ iat, request_body_sha256: sha256hex(body) });
	const fetch = vi.fn<FetchJwk>(async () => jwk);
	return { jwt, cache: new JwkCache(fetch), fetch };
}

describe('verifyPlaidWebhook — happy path', () => {
	it('verifies a correctly-signed webhook and returns the trusted claims', async () => {
		const body = JSON.stringify({ webhook_type: 'ITEM', webhook_code: 'ERROR', item_id: 'itm_1' });
		const { jwt, cache, fetch } = await signedWebhook(body);
		const res = await verifyPlaidWebhook(body, jwt, { cache, now: NOW_MS });
		expect(res.ok).toBe(true);
		if (res.ok) {
			expect(res.claims.kid).toBe(KID);
			expect(res.claims.requestBodySha256).toBe(sha256hex(body));
		}
		expect(fetch).toHaveBeenCalledWith(KID); // key came from the credentialed fetch, keyed by kid.
	});
});

describe('verifyPlaidWebhook — fail-closed modes', () => {
	it('missing Plaid-Verification header → missing_verification_header', async () => {
		const { cache } = await signedWebhook('{}');
		const res = await verifyPlaidWebhook('{}', null, { cache, now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'missing_verification_header' });
	});

	it('M1: a non-ES256 alg (HS256) is rejected at the pre-check → bad_alg (no key fetch)', async () => {
		const body = '{}';
		// A token whose header alg is HS256 (symmetric) — must be rejected before any key work.
		const hsJwt = await new SignJWT({ iat: Math.floor(NOW_MS / 1000), request_body_sha256: sha256hex(body) })
			.setProtectedHeader({ alg: 'HS256', kid: KID })
			.sign(new TextEncoder().encode('attacker-hmac-key-attacker-hmac-key'));
		const fetch = vi.fn<FetchJwk>();
		const res = await verifyPlaidWebhook(body, hsJwt, { cache: new JwkCache(fetch), now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'bad_alg' });
		expect(fetch).not.toHaveBeenCalled();
	});

	it('M2: a tampered body (hash mismatch) is rejected → body_hash_mismatch', async () => {
		const body = JSON.stringify({ webhook_type: 'ITEM', item_id: 'itm_1' });
		const { jwt, cache } = await signedWebhook(body);
		const tampered = JSON.stringify({ webhook_type: 'ITEM', item_id: 'itm_EVIL' });
		const res = await verifyPlaidWebhook(tampered, jwt, { cache, now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'body_hash_mismatch' });
	});

	it('M3: a stale iat (older than the freshness window) is rejected → stale_iat', async () => {
		const body = '{}';
		const staleIat = Math.floor(NOW_MS / 1000) - 10_000; // ~2.7h old
		const { jwt, cache } = await signedWebhook(body, { iat: staleIat });
		const res = await verifyPlaidWebhook(body, jwt, { cache, now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'stale_iat' });
	});

	it('a signature from a DIFFERENT key (kid resolves to the wrong JWK) → bad_signature', async () => {
		const body = '{}';
		const { jwt } = await signedWebhook(body); // signed by keypair A
		const other = await makeKeypair(); // unrelated keypair B
		const cache = new JwkCache(async () => other.jwk); // fetch returns B's public key
		const res = await verifyPlaidWebhook(body, jwt, { cache, now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'bad_signature' });
	});

	it('an unfetchable key (worker/Plaid unreachable) → key_unavailable (fail closed)', async () => {
		const body = '{}';
		const { jwt } = await signedWebhook(body);
		const cache = new JwkCache(async () => {
			throw new Error('worker unreachable');
		});
		const res = await verifyPlaidWebhook(body, jwt, { cache, now: NOW_MS });
		expect(res).toEqual({ ok: false, reason: 'key_unavailable' });
	});
});

describe('deriveProviderEventId', () => {
	it('is stable per signed delivery (exact replay → same id) and varies with iat', () => {
		const base = { kid: KID, requestBodySha256: 'abc123' };
		const a = deriveProviderEventId({ ...base, iat: 1000 });
		const b = deriveProviderEventId({ ...base, iat: 1000 });
		const c = deriveProviderEventId({ ...base, iat: 1001 });
		expect(a).toBe(b); // replay dedups
		expect(a).not.toBe(c); // distinct delivery processes
		expect(a).toBe('plaid:1000:abc123');
	});
});

describe('JwkCache — M7 hygiene', () => {
	it('caches by kid within TTL, refetches after expiry', async () => {
		const { jwk } = await makeKeypair();
		const fetch = vi.fn<FetchJwk>(async () => jwk);
		const cache = new JwkCache(fetch, 1000, 8);
		await cache.get(KID, 0);
		await cache.get(KID, 500); // within TTL → cached
		expect(fetch).toHaveBeenCalledTimes(1);
		await cache.get(KID, 2000); // past TTL → refetch
		expect(fetch).toHaveBeenCalledTimes(2);
	});

	it('is bounded (FIFO-evicts beyond max)', async () => {
		const { jwk } = await makeKeypair();
		const fetch = vi.fn<FetchJwk>(async (kid) => ({ ...jwk, kid }));
		const cache = new JwkCache(fetch, 10_000, 2);
		await cache.get('k1', 0);
		await cache.get('k2', 0);
		await cache.get('k3', 0); // evicts k1
		await cache.get('k1', 0); // k1 was evicted → refetch (4th call)
		expect(fetch).toHaveBeenCalledTimes(4);
	});
});
