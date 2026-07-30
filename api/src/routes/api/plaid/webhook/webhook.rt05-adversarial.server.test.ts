// webhook.rt05-adversarial.server.test.ts — SELF-206 QA-authored RT-05 adversarial battery for the
// Plaid webhook handler's signature-verify layer. V1-SHIP-BLOCK · Sec joint-review-mandatory.
//
// This is the QA companion to Backend's webhookVerify.test.ts (unit-level) + webhook.server.test.ts
// (orchestration). It asserts the FULL handler contract at the HTTP boundary: every adversarial
// Plaid-Verification token → 401 with NO RPC calls and NO worker sync (no writes anywhere). Each
// case would go RED if the corresponding fence were removed (e.g. drop the ES256 alg-pin → the
// alg-confusion cases would 200; drop the body-hash check → the tamper case would 200).
//
// Battery (RT-05, per the SELF-206 mandate):
//   • header-strip (missing Plaid-Verification)                 → 401, no writes
//   • JWT signed by a non-Plaid key (kid resolves, sig wrong)   → 401, no writes
//   • alg-confusion: alg:none / RS256 / HS256 downgrade         → 401, no writes
//   • body-tamper with the signature retained                   → 401, no writes
//   • replay-stale (iat older than the ~5min freshness window)  → 401, no writes
//   • unknown/ROTATED kid → a FRESH credentialed fetch verifies → 200 (positive control)
//
// Harness: real jose ES256 keypair; the credentialed JWK fetch is mocked to return the test PUBLIC
// key (keyed by kid); supabase-admin is mocked so we can assert ZERO rpc() calls on every reject.

import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT, type JWK } from 'jose';

const h = vi.hoisted(() => ({
	jwk: null as JWK | null,
	admin: null as unknown,
	fetchCalls: [] as string[],
	triggerSourceSync: vi.fn(async () => ({ ok: true }))
}));

vi.mock('$lib/server/plaid/admissionClient', () => ({
	// The credentialed fetch returns the ONE test public key regardless of kid (mirrors Plaid's
	// /webhook_verification_key/get for a rotated kid). We record the kid it was asked for.
	fetchWebhookVerificationKey: async (kid: string) => {
		h.fetchCalls.push(kid);
		if (!h.jwk) throw new Error('no test key');
		return h.jwk;
	},
	triggerSourceSync: h.triggerSourceSync
}));

vi.mock('$lib/server/supabase-admin', () => ({
	supabaseAdmin: () => h.admin
}));

const { POST } = await import('./+server');

type RpcResult = { data: unknown; error: unknown };

/** Mock admin recording every .schema('pfin').rpc(fn, params) call. Default resolve = a resolved,
 *  non-sync ITEM event so the positive control reaches a clean 200. */
function makeAdmin(): {
	schema: () => { rpc: (fn: string, params: unknown) => Promise<RpcResult> };
	rpcCalls: { fn: string }[];
} {
	const rpcCalls: { fn: string }[] = [];
	const rpc = (fn: string): Promise<RpcResult> => {
		rpcCalls.push({ fn });
		if (fn === 'fn_plaid_webhook_resolve') {
			return Promise.resolve({
				data: [
					{
						resolved: true,
						already_processed: false,
						should_trigger_sync: false,
						source_id: 501,
						users_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
					}
				],
				error: null
			});
		}
		return Promise.resolve({ data: [{ committed: true, was_fresh: true }], error: null });
	};
	return { schema: () => ({ rpc }), rpcCalls };
}

const KID = 'kid-1';
const sha256hex = (s: string): string => createHash('sha256').update(s, 'utf8').digest('hex');

let esPrivate: CryptoKey; // the legit Plaid ES256 private key (test keypair)
let attackerPrivate: CryptoKey; // a DIFFERENT ES256 private key (non-Plaid signer)
let rsaPrivate: CryptoKey; // an RS256 private key (alg-confusion)

beforeAll(async () => {
	const { publicKey, privateKey } = await generateKeyPair('ES256', { extractable: true });
	esPrivate = privateKey;
	const pub = await exportJWK(publicKey);
	h.jwk = { ...pub, kid: KID, alg: 'ES256', use: 'sig' };

	attackerPrivate = (await generateKeyPair('ES256', { extractable: true })).privateKey;
	rsaPrivate = (await generateKeyPair('RS256', { extractable: true })).privateKey;
});

beforeEach(() => {
	h.triggerSourceSync.mockClear();
	h.fetchCalls.length = 0;
});

const nowSec = (): number => Math.floor(Date.now() / 1000);

/** Build a request with an explicit Plaid-Verification header value (or omit it entirely). */
function makeRequest(body: string, header: string | null): Request {
	const headers: Record<string, string> = { 'content-type': 'application/json' };
	if (header !== null) headers['plaid-verification'] = header;
	return new Request('http://localhost/api/plaid/webhook', { method: 'POST', headers, body });
}

const STATE_BODY = JSON.stringify({
	webhook_type: 'ITEM',
	webhook_code: 'ERROR',
	item_id: 'itm_1',
	error: { error_code: 'ITEM_LOGIN_REQUIRED' }
});

/** Assert: rejected with 401 AND no RPC calls AND no worker sync (NO writes anywhere). */
async function expectRejectedNoWrites(header: string | null, body = STATE_BODY): Promise<void> {
	const admin = makeAdmin();
	h.admin = admin;
	const res = await POST({ request: makeRequest(body, header) } as unknown as Parameters<typeof POST>[0]);
	expect(res.status).toBe(401);
	expect(admin.rpcCalls).toHaveLength(0); // no resolve, no commit
	expect(h.triggerSourceSync).not.toHaveBeenCalled(); // no external sync
}

describe('RT-05 adversarial — header-strip', () => {
	it('missing Plaid-Verification header → 401, no writes', async () => {
		await expectRejectedNoWrites(null);
	});
	it('empty Plaid-Verification header → 401, no writes', async () => {
		await expectRejectedNoWrites('');
	});
});

describe('RT-05 adversarial — non-Plaid signer', () => {
	it('valid ES256 JWT signed by a DIFFERENT (attacker) key, legit kid → 401, no writes', async () => {
		const jwt = await new SignJWT({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'ES256', kid: KID })
			.sign(attackerPrivate);
		await expectRejectedNoWrites(jwt);
	});
});

describe('RT-05 adversarial — alg-confusion', () => {
	it('alg:none (unsigned token) → 401, no writes', async () => {
		const seg = (o: object): string => Buffer.from(JSON.stringify(o)).toString('base64url');
		const noneToken = `${seg({ alg: 'none', kid: KID })}.${seg({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })}.`;
		await expectRejectedNoWrites(noneToken);
	});

	it('RS256-signed JWT (asymmetric downgrade) → 401, no writes', async () => {
		const jwt = await new SignJWT({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'RS256', kid: KID })
			.sign(rsaPrivate);
		await expectRejectedNoWrites(jwt);
	});

	it('HS256-signed JWT (symmetric downgrade using the public bytes as an HMAC key) → 401, no writes', async () => {
		const jwt = await new SignJWT({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'HS256', kid: KID })
			.sign(new TextEncoder().encode('attacker-shared-secret-0123456789'));
		await expectRejectedNoWrites(jwt);
	});
});

describe('RT-05 adversarial — body tamper with the signature retained', () => {
	it('a JWT signed over body X, delivered with tampered body Y → 401 (body-hash mismatch), no writes', async () => {
		// Sign over the AUTHENTIC body, then deliver a DIFFERENT body with the same (valid) JWT.
		const jwt = await new SignJWT({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'ES256', kid: KID })
			.sign(esPrivate);
		const tampered = JSON.stringify({ webhook_type: 'ITEM', webhook_code: 'ERROR', item_id: 'itm_EVIL' });
		await expectRejectedNoWrites(jwt, tampered);
	});
});

describe('RT-05 adversarial — replay-stale iat', () => {
	it('a validly-signed JWT with iat older than the ~5min freshness window → 401, no writes', async () => {
		const staleIat = nowSec() - 100_000; // ~27h old — well past the 300s window.
		const jwt = await new SignJWT({ iat: staleIat, request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'ES256', kid: KID })
			.sign(esPrivate);
		await expectRejectedNoWrites(jwt);
	});
});

describe('RT-05 — unknown/rotated kid triggers a fresh credentialed fetch then verifies (positive control)', () => {
	it('a valid ES256 JWT with a NEVER-SEEN kid → the handler fetches that kid fresh and verifies → 200', async () => {
		const admin = makeAdmin();
		h.admin = admin;
		const rotatedKid = 'kid-ROTATED-2';
		const jwt = await new SignJWT({ iat: nowSec(), request_body_sha256: sha256hex(STATE_BODY) })
			.setProtectedHeader({ alg: 'ES256', kid: rotatedKid })
			.sign(esPrivate);
		const res = await POST({ request: makeRequest(STATE_BODY, jwt) } as unknown as Parameters<typeof POST>[0]);
		// Positive control: a correctly-signed webhook is NOT 401 — it passes verification and proceeds.
		expect(res.status).toBe(200);
		expect(h.fetchCalls).toContain(rotatedKid); // the rotated kid triggered a fresh credentialed fetch
		expect(admin.rpcCalls.map((c) => c.fn)).toContain('fn_plaid_webhook_resolve'); // reached the RPC layer
	});
});
