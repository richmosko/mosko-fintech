// admissionServer.test.ts — SELF-212 Option C inbound admission endpoint.
// Drives the real node:http server on an ephemeral port with injected (mocked) mintLinkToken +
// admit collaborators — NO Plaid client, NO Postgres. Covers auth (C6-6), both legs, Zod
// `.strict()` validation, error envelope + redaction (C6-5), bigint serialization, routing.

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createAdmissionServer, type AdmissionServerDeps } from '../src/http/admissionServer.js';
import { PublicTokenInvalidError } from '../src/adapters/PlaidAdapter.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';
import type { ProviderAccountRef } from '../src/adapters/ProviderAdapter.js';

const SECRET = 'test-shared-secret-0123456789abcdef0123456789abcdef';
const UUID = '11111111-1111-4111-8111-111111111111';
const TOKEN = 'access-sandbox-SUPERSECRET-should-never-appear';

const ACCT: ProviderAccountRef = {
	providerAccountId: 'acct_1',
	name: 'Checking',
	type: 'depository',
	subtype: 'checking',
	currency: 'USD'
};

let live: Server | undefined;

afterEach(async () => {
	if (live) await new Promise<void>((r) => live!.close(() => r()));
	live = undefined;
});

async function start(deps: Partial<AdmissionServerDeps> = {}): Promise<string> {
	const full: AdmissionServerDeps = {
		sharedSecret: SECRET,
		mintLinkToken: vi.fn(async () => ({ link_token: 'link-sandbox-1', expiration: '2026-07-19T12:00:00Z' })),
		admit: vi.fn(async () => ({ sourceId: 42n, accounts: [ACCT] })),
		logger: vi.fn(),
		...deps
	};
	live = createAdmissionServer(full);
	await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
	const { port } = live!.address() as AddressInfo;
	return `http://127.0.0.1:${port}`;
}

function post(url: string, body: unknown, headers: Record<string, string> = {}): Promise<Response> {
	return fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
}

const authed = { [ADMISSION_SECRET_HEADER]: SECRET };

describe('N-1 — explicit hung-request timeouts', () => {
	it('sets bounded headersTimeout (5s) and requestTimeout (15s), with requestTimeout > headersTimeout', async () => {
		await start();
		expect(live!.headersTimeout).toBe(5_000);
		expect(live!.requestTimeout).toBe(15_000);
		expect(live!.requestTimeout).toBeGreaterThan(live!.headersTimeout);
	});
});

describe('healthz — unauthenticated liveness', () => {
	it('GET /healthz returns 200 { status: ok } with no auth', async () => {
		const url = await start();
		const res = await fetch(`${url}/healthz`);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ status: 'ok' });
	});
});

describe('C6-6 auth gate — both legs behind the shared secret', () => {
	it('401 when the secret header is absent', async () => {
		const mintLinkToken = vi.fn();
		const url = await start({ mintLinkToken });
		const res = await post(`${url}/admission/link-token`, { ownerUserId: UUID });
		expect(res.status).toBe(401);
		expect(await res.json()).toEqual({ error: 'unauthorized' });
		expect(mintLinkToken).not.toHaveBeenCalled();
	});

	it('401 on a wrong secret — collaborator never invoked', async () => {
		const admit = vi.fn();
		const url = await start({ admit });
		const res = await post(`${url}/admission/exchange`, { public_token: 'p', ownerUserId: UUID }, { [ADMISSION_SECRET_HEADER]: 'wrong' });
		expect(res.status).toBe(401);
		expect(admit).not.toHaveBeenCalled();
	});
});

describe('leg-1 — link_token mint', () => {
	it('happy path returns { link_token, expiration }; ownerUserId forwarded', async () => {
		const mintLinkToken = vi.fn(async () => ({ link_token: 'link-1', expiration: 'exp-1' }));
		const url = await start({ mintLinkToken });
		const res = await post(`${url}/admission/link-token`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ link_token: 'link-1', expiration: 'exp-1' });
		expect(mintLinkToken).toHaveBeenCalledWith(UUID);
	});

	it('400 on a bad uuid (Zod .strict boundary)', async () => {
		const mintLinkToken = vi.fn();
		const url = await start({ mintLinkToken });
		const res = await post(`${url}/admission/link-token`, { ownerUserId: 'not-a-uuid' }, authed);
		expect(res.status).toBe(400);
		expect(mintLinkToken).not.toHaveBeenCalled();
	});

	it('400 on an extra field (mass-assignment prevention)', async () => {
		const url = await start();
		const res = await post(`${url}/admission/link-token`, { ownerUserId: UUID, isAdmin: true }, authed);
		expect(res.status).toBe(400);
	});

	it('502 + generic envelope when the mint throws (no internal detail leaks)', async () => {
		const mintLinkToken = vi.fn(async () => {
			throw new Error('Plaid link/token/create failed (RATE_LIMIT)');
		});
		const url = await start({ mintLinkToken });
		const res = await post(`${url}/admission/link-token`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'link_token_failed' });
	});
});

describe('leg-2 — public_token exchange/admit', () => {
	it('happy path returns { sourceId (string), accounts } and forwards the input', async () => {
		const admit = vi.fn(async () => ({ sourceId: 42n, accounts: [ACCT] }));
		const url = await start({ admit });
		const res = await post(
			`${url}/admission/exchange`,
			{ public_token: 'public-sandbox-1', ownerUserId: UUID, institutionName: 'Test Bank' },
			authed
		);
		expect(res.status).toBe(200);
		const body = await res.json();
		expect(body.sourceId).toBe('42'); // bigint serialized as string
		expect(body.accounts).toEqual([
			{ account_id: 'acct_1', name: 'Checking', type: 'depository', subtype: 'checking', currency: 'USD' }
		]);
		expect(admit).toHaveBeenCalledWith({
			publicToken: 'public-sandbox-1',
			ownerUserId: UUID,
			institutionName: 'Test Bank'
		});
	});

	it('400 on missing public_token; admit not called', async () => {
		const admit = vi.fn();
		const url = await start({ admit });
		const res = await post(`${url}/admission/exchange`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(400);
		expect(admit).not.toHaveBeenCalled();
	});

	it('C6-3: an extra ownerUserId-adjacent field is rejected (.strict)', async () => {
		const admit = vi.fn();
		const url = await start({ admit });
		const res = await post(
			`${url}/admission/exchange`,
			{ public_token: 'p', ownerUserId: UUID, tenant_override: 'other' },
			authed
		);
		expect(res.status).toBe(400);
		expect(admit).not.toHaveBeenCalled();
	});

	it('Item-2: a PublicTokenInvalidError → worker-400 public_token_invalid (client-correctable)', async () => {
		const admit = vi.fn(async () => {
			throw new PublicTokenInvalidError('INVALID_PUBLIC_TOKEN');
		});
		const url = await start({ admit });
		const res = await post(`${url}/admission/exchange`, { public_token: 'burned', ownerUserId: UUID }, authed);
		expect(res.status).toBe(400);
		const text = await res.text();
		expect(text).toBe(JSON.stringify({ error: 'public_token_invalid' })); // one uniform code, no Plaid detail
	});

	it('C6-5: a failed admission returns a generic 502 with NO token fragment', async () => {
		const admit = vi.fn(async () => {
			// Even if the adapter somehow surfaced a token-bearing message, the envelope is generic.
			throw new Error(`admission blew up with ${TOKEN}`);
		});
		const url = await start({ admit });
		const res = await post(`${url}/admission/exchange`, { public_token: 'p', ownerUserId: UUID }, authed);
		expect(res.status).toBe(502);
		const text = await res.text();
		expect(text).toBe(JSON.stringify({ error: 'admission_failed' }));
		expect(text).not.toContain(TOKEN);
	});
});

describe('routing', () => {
	it('404 on an unknown authed route', async () => {
		const url = await start();
		const res = await post(`${url}/admission/nope`, {}, authed);
		expect(res.status).toBe(404);
	});

	it('405 on a wrong method for a known route', async () => {
		const url = await start();
		const res = await fetch(`${url}/admission/exchange`, { headers: authed });
		expect(res.status).toBe(405);
	});
});
