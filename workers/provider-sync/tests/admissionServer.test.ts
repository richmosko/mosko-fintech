// admissionServer.test.ts — SELF-212 Option C inbound admission endpoint.
// Drives the real node:http server on an ephemeral port with injected (mocked) mintLinkToken +
// admit collaborators — NO Plaid client, NO Postgres. Covers auth (C6-6), both legs, Zod
// `.strict()` validation, error envelope + redaction (C6-5), bigint serialization, routing.

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createAdmissionServer, type AdmissionServerDeps } from '../src/http/admissionServer.js';
import { PublicTokenInvalidError } from '../src/adapters/PlaidAdapter.js';
import { SetupTokenInvalidError } from '../src/adapters/SimpleFINAdapter.js';
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
		admitSimplefin: vi.fn(async () => ({ sourceId: 77n, accounts: [ACCT] })),
		reauthStart: vi.fn(async () => ({ kind: 'link_update', linkToken: 'link-upd-1' })),
		reauthComplete: vi.fn(async () => ({ connectionStatus: 'healthy', rotated: false })),
		fetchWebhookVerificationKey: vi.fn(async () => ({
			kty: 'EC',
			crv: 'P-256',
			x: 'x-coord',
			y: 'y-coord',
			kid: 'kid-1',
			alg: 'ES256',
			use: 'sig'
		})),
		syncSource: vi.fn(async () => ({ sourceId: '42', inserted: 3, skipped: 1, unresolvedAccounts: 0 })),
		manualSync: vi.fn(async () => ({ sources: [{ source_id: '42', disposition: 'triggered' as const }] })),
		resolveAsset: vi.fn(async () => ({ assetId: 501 })),
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

describe('leg-S — SimpleFIN setup-token claim/admit', () => {
	const SETUP_TOKEN = btoa('https://setup-should-never-appear'); // base64-ish; never echoed

	it('happy path returns { sourceId (string), accounts } and forwards the input', async () => {
		const admitSimplefin = vi.fn(async () => ({ sourceId: 77n, accounts: [ACCT] }));
		const url = await start({ admitSimplefin });
		const res = await post(
			`${url}/admission/simplefin/claim`,
			{ setup_token: SETUP_TOKEN, ownerUserId: UUID, institutionName: 'Test Bank' },
			authed
		);
		expect(res.status).toBe(200);
		const body = await res.json();
		expect(body.sourceId).toBe('77'); // bigint serialized as string
		expect(body.accounts).toEqual([
			{ account_id: 'acct_1', name: 'Checking', type: 'depository', subtype: 'checking', currency: 'USD' }
		]);
		expect(admitSimplefin).toHaveBeenCalledWith({
			setupToken: SETUP_TOKEN,
			ownerUserId: UUID,
			institutionName: 'Test Bank'
		});
	});

	it('C6-6: 401 when the secret header is absent — admitSimplefin never invoked', async () => {
		const admitSimplefin = vi.fn();
		const url = await start({ admitSimplefin });
		const res = await post(`${url}/admission/simplefin/claim`, { setup_token: SETUP_TOKEN, ownerUserId: UUID });
		expect(res.status).toBe(401);
		expect(admitSimplefin).not.toHaveBeenCalled();
	});

	it('400 on missing setup_token; admitSimplefin not called', async () => {
		const admitSimplefin = vi.fn();
		const url = await start({ admitSimplefin });
		const res = await post(`${url}/admission/simplefin/claim`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(400);
		expect(admitSimplefin).not.toHaveBeenCalled();
	});

	it('400 on a bad uuid ownerUserId (Zod .strict boundary)', async () => {
		const admitSimplefin = vi.fn();
		const url = await start({ admitSimplefin });
		const res = await post(`${url}/admission/simplefin/claim`, { setup_token: SETUP_TOKEN, ownerUserId: 'not-a-uuid' }, authed);
		expect(res.status).toBe(400);
		expect(admitSimplefin).not.toHaveBeenCalled();
	});

	it('C6-3: an extra tenant-adjacent field is rejected (.strict)', async () => {
		const admitSimplefin = vi.fn();
		const url = await start({ admitSimplefin });
		const res = await post(
			`${url}/admission/simplefin/claim`,
			{ setup_token: SETUP_TOKEN, ownerUserId: UUID, tenant_override: 'other' },
			authed
		);
		expect(res.status).toBe(400);
		expect(admitSimplefin).not.toHaveBeenCalled();
	});

	it('a SetupTokenInvalidError → worker-400 setup_token_invalid (client-correctable)', async () => {
		const admitSimplefin = vi.fn(async () => {
			throw new SetupTokenInvalidError('SimpleFIN claim failed (HTTP 403)');
		});
		const url = await start({ admitSimplefin });
		const res = await post(`${url}/admission/simplefin/claim`, { setup_token: 'burned', ownerUserId: UUID }, authed);
		expect(res.status).toBe(400);
		const text = await res.text();
		expect(text).toBe(JSON.stringify({ error: 'setup_token_invalid' })); // one uniform code, no detail
	});

	it('C6-5: any other failure returns a generic 502 with NO token fragment', async () => {
		const admitSimplefin = vi.fn(async () => {
			// Even if the adapter somehow surfaced a token-bearing message, the envelope is generic.
			throw new Error(`admission blew up with ${TOKEN}`);
		});
		const url = await start({ admitSimplefin });
		const res = await post(`${url}/admission/simplefin/claim`, { setup_token: SETUP_TOKEN, ownerUserId: UUID }, authed);
		expect(res.status).toBe(502);
		const text = await res.text();
		expect(text).toBe(JSON.stringify({ error: 'admission_failed' }));
		expect(text).not.toContain(TOKEN);
		expect(text).not.toContain(SETUP_TOKEN);
	});

	it('405 on a wrong method for the claim route', async () => {
		const url = await start();
		const res = await fetch(`${url}/admission/simplefin/claim`, { headers: authed });
		expect(res.status).toBe(405);
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

describe('reauth legs (SELF-207)', () => {
	it('POST /admission/reauth/start dispatches + returns the ReauthHandoff', async () => {
		const reauthStart = vi.fn(async () => ({ kind: 'link_update' as const, linkToken: 'lt-1' }));
		const url = await start({ reauthStart });
		const res = await post(`${url}/admission/reauth/start`, { provider: 'plaid', linked_source_id: '42', ownerUserId: UUID }, authed);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ kind: 'link_update', linkToken: 'lt-1' });
		expect(reauthStart).toHaveBeenCalledWith({ provider: 'plaid', linkedSourceId: 42n, ownerUserId: UUID });
	});

	it('POST /admission/reauth/start requires the shared secret', async () => {
		const url = await start();
		const res = await post(`${url}/admission/reauth/start`, { provider: 'plaid', linked_source_id: '42', ownerUserId: UUID });
		expect(res.status).toBe(401);
	});

	it('POST /admission/reauth/start rejects a bad body (.strict / bad linked_source_id)', async () => {
		const url = await start();
		const r1 = await post(`${url}/admission/reauth/start`, { provider: 'plaid', linked_source_id: 'abc', ownerUserId: UUID }, authed);
		expect(r1.status).toBe(400);
		const r2 = await post(`${url}/admission/reauth/start`, { provider: 'plaid', linked_source_id: '42', ownerUserId: UUID, extra: 1 }, authed);
		expect(r2.status).toBe(400);
	});

	it('POST /admission/reauth/complete (Plaid) maps link_update_success + returns the result', async () => {
		const reauthComplete = vi.fn(async () => ({ connectionStatus: 'healthy' as const, rotated: false }));
		const url = await start({ reauthComplete });
		const res = await post(
			`${url}/admission/reauth/complete`,
			{ provider: 'plaid', linked_source_id: '42', ownerUserId: UUID, input: { kind: 'link_update_success' } },
			authed
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ connectionStatus: 'healthy', rotated: false });
		expect(reauthComplete).toHaveBeenCalledWith({
			provider: 'plaid',
			linkedSourceId: 42n,
			ownerUserId: UUID,
			input: { kind: 'link_update_success' }
		});
	});

	it('POST /admission/reauth/complete (SimpleFIN) maps setup_token → setupToken (camel)', async () => {
		const reauthComplete = vi.fn(async () => ({ connectionStatus: 'healthy' as const, rotated: true }));
		const url = await start({ reauthComplete });
		const res = await post(
			`${url}/admission/reauth/complete`,
			{ provider: 'simplefin', linked_source_id: '77', ownerUserId: UUID, input: { kind: 'setup_token', setup_token: 'tok-abc' } },
			authed
		);
		expect(res.status).toBe(200);
		expect(reauthComplete).toHaveBeenCalledWith({
			provider: 'simplefin',
			linkedSourceId: 77n,
			ownerUserId: UUID,
			input: { kind: 'setup_token', setupToken: 'tok-abc' }
		});
	});

	it('POST /admission/reauth/complete rejects an unknown input kind (.strict discriminated union)', async () => {
		const url = await start();
		const res = await post(
			`${url}/admission/reauth/complete`,
			{ provider: 'plaid', linked_source_id: '42', ownerUserId: UUID, input: { kind: 'nope' } },
			authed
		);
		expect(res.status).toBe(400);
	});

	it('reauth-complete failure → 502 reauth_failed (e.g. the SimpleFIN ②-held throw)', async () => {
		const reauthComplete = vi.fn(async () => {
			throw new Error('held');
		});
		const url = await start({ reauthComplete });
		const res = await post(
			`${url}/admission/reauth/complete`,
			{ provider: 'simplefin', linked_source_id: '77', ownerUserId: UUID, input: { kind: 'setup_token', setup_token: 't' } },
			authed
		);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'reauth_failed' });
	});
});

// ── SELF-206 — webhook-verification-key + sync trigger (new routes, same server/gate) ──────
describe('SELF-206 webhook-verification-key — credentialed JWK fetch (Option 1)', () => {
	it('401 without the shared secret (route on the SAME RT-27 gate)', async () => {
		const fetchWebhookVerificationKey = vi.fn();
		const url = await start({ fetchWebhookVerificationKey });
		const res = await post(`${url}/admission/webhook-verification-key`, { kid: 'kid-1' });
		expect(res.status).toBe(401);
		expect(fetchWebhookVerificationKey).not.toHaveBeenCalled();
	});

	it('happy path returns { key } (public JWK); kid forwarded', async () => {
		const fetchWebhookVerificationKey = vi.fn(async () => ({
			kty: 'EC',
			crv: 'P-256',
			x: 'X',
			y: 'Y',
			kid: 'kid-9',
			alg: 'ES256',
			use: 'sig'
		}));
		const url = await start({ fetchWebhookVerificationKey });
		const res = await post(`${url}/admission/webhook-verification-key`, { kid: 'kid-9' }, authed);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({
			key: { kty: 'EC', crv: 'P-256', x: 'X', y: 'Y', kid: 'kid-9', alg: 'ES256', use: 'sig' }
		});
		expect(fetchWebhookVerificationKey).toHaveBeenCalledWith('kid-9');
	});

	it('400 on an empty kid / extra field (Zod .strict boundary)', async () => {
		const fetchWebhookVerificationKey = vi.fn();
		const url = await start({ fetchWebhookVerificationKey });
		expect((await post(`${url}/admission/webhook-verification-key`, { kid: '' }, authed)).status).toBe(400);
		expect(
			(await post(`${url}/admission/webhook-verification-key`, { kid: 'k', extra: 1 }, authed)).status
		).toBe(400);
		expect(fetchWebhookVerificationKey).not.toHaveBeenCalled();
	});

	it('502 generic envelope when the fetch throws (no internal detail leaks)', async () => {
		const fetchWebhookVerificationKey = vi.fn(async () => {
			throw new Error('Plaid /webhook_verification_key/get failed (RATE_LIMIT)');
		});
		const url = await start({ fetchWebhookVerificationKey });
		const res = await post(`${url}/admission/webhook-verification-key`, { kid: 'kid-1' }, authed);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'verification_key_failed' });
	});
});

describe('SELF-206 sync — on-demand incremental sync trigger (AC5)', () => {
	it('401 without the shared secret', async () => {
		const syncSource = vi.fn();
		const url = await start({ syncSource });
		const res = await post(`${url}/admission/sync`, { ownerUserId: UUID, linked_source_id: '42' });
		expect(res.status).toBe(401);
		expect(syncSource).not.toHaveBeenCalled();
	});

	it('happy path returns { ok, ...counts }; input forwarded (bigint parsed)', async () => {
		const syncSource = vi.fn(async () => ({ sourceId: '42', inserted: 5, skipped: 2, unresolvedAccounts: 1 }));
		const url = await start({ syncSource });
		const res = await post(`${url}/admission/sync`, { ownerUserId: UUID, linked_source_id: '42' }, authed);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ ok: true, sourceId: '42', inserted: 5, skipped: 2, unresolvedAccounts: 1 });
		expect(syncSource).toHaveBeenCalledWith({ ownerUserId: UUID, linkedSourceId: 42n });
	});

	it('400 on a non-digit linked_source_id / extra field (Zod .strict boundary)', async () => {
		const syncSource = vi.fn();
		const url = await start({ syncSource });
		expect(
			(await post(`${url}/admission/sync`, { ownerUserId: UUID, linked_source_id: 'abc' }, authed)).status
		).toBe(400);
		expect(
			(await post(`${url}/admission/sync`, { ownerUserId: UUID, linked_source_id: '42', extra: 1 }, authed)).status
		).toBe(400);
		expect(syncSource).not.toHaveBeenCalled();
	});

	it('502 generic envelope when the sync throws (no credential/detail leaks)', async () => {
		const syncSource = vi.fn(async () => {
			throw new Error('no credential resolved for source_id=42');
		});
		const url = await start({ syncSource });
		const res = await post(`${url}/admission/sync`, { ownerUserId: UUID, linked_source_id: '42' }, authed);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'sync_failed' });
	});
});

describe('SELF-317 manual-sync — user-initiated "Sync now" (A2 return-fast 202)', () => {
	it('401 without the shared secret — manualSync never invoked', async () => {
		const manualSync = vi.fn();
		const url = await start({ manualSync });
		const res = await post(`${url}/admission/manual-sync`, { ownerUserId: UUID });
		expect(res.status).toBe(401);
		expect(manualSync).not.toHaveBeenCalled();
	});

	it('sync-all (source_id absent) → 202 { accepted, sources }; ownerUserId forwarded, no sourceId', async () => {
		const manualSync = vi.fn(async () => ({
			sources: [
				{ source_id: '42', disposition: 'triggered' as const },
				{ source_id: '77', disposition: 'debounced' as const }
			]
		}));
		const url = await start({ manualSync });
		const res = await post(`${url}/admission/manual-sync`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(202);
		expect(await res.json()).toEqual({
			accepted: true,
			sources: [
				{ source_id: '42', disposition: 'triggered' },
				{ source_id: '77', disposition: 'debounced' }
			]
		});
		expect(manualSync).toHaveBeenCalledWith({ ownerUserId: UUID });
	});

	it('per-source (source_id present) → 202; sourceId forwarded verbatim', async () => {
		const manualSync = vi.fn(async () => ({ sources: [{ source_id: '42', disposition: 'triggered' as const }] }));
		const url = await start({ manualSync });
		const res = await post(`${url}/admission/manual-sync`, { ownerUserId: UUID, source_id: '42' }, authed);
		expect(res.status).toBe(202);
		expect(manualSync).toHaveBeenCalledWith({ ownerUserId: UUID, sourceId: '42' });
	});

	it('400 on a bad uuid / non-digit source_id / extra field (Zod .strict boundary)', async () => {
		const manualSync = vi.fn();
		const url = await start({ manualSync });
		expect((await post(`${url}/admission/manual-sync`, { ownerUserId: 'nope' }, authed)).status).toBe(400);
		expect(
			(await post(`${url}/admission/manual-sync`, { ownerUserId: UUID, source_id: 'abc' }, authed)).status
		).toBe(400);
		expect(
			(await post(`${url}/admission/manual-sync`, { ownerUserId: UUID, extra: 1 }, authed)).status
		).toBe(400);
		expect(manualSync).not.toHaveBeenCalled();
	});

	it('502 generic envelope when phase-1 throws (no detail leaks)', async () => {
		const manualSync = vi.fn(async () => {
			throw new Error('enumeration failed for tenant');
		});
		const url = await start({ manualSync });
		const res = await post(`${url}/admission/manual-sync`, { ownerUserId: UUID }, authed);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'manual_sync_failed' });
	});
});

describe('SELF-325 asset-resolve — resolve-or-mint a global asset (Case 3)', () => {
	it('happy path (symbol) returns { assetId } and forwards the input verbatim', async () => {
		const resolveAsset = vi.fn(async () => ({ assetId: 501 }));
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: 'AAPL', cusip: null, assetType: 'equity', name: 'Apple Inc', currency: 'USD' },
			authed
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ assetId: 501 });
		expect(resolveAsset).toHaveBeenCalledWith({
			ownerUserId: UUID,
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: 'Apple Inc',
			currency: 'USD'
		});
	});

	it('happy path (cusip, no symbol) resolves too', async () => {
		const resolveAsset = vi.fn(async () => ({ assetId: 502 }));
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: null, cusip: '037833100', assetType: 'bond', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(200);
		expect(await res.json()).toEqual({ assetId: 502 });
	});

	it('401 without the shared secret — resolveAsset never invoked', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(`${url}/asset/resolve`, {
			ownerUserId: UUID,
			symbol: 'AAPL',
			cusip: null,
			assetType: 'equity',
			name: null,
			currency: 'USD'
		});
		expect(res.status).toBe(401);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 when both symbol and cusip are absent — no identity to resolve', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: null, cusip: null, assetType: 'equity', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on a malformed symbol (namespace-pollution boundary — pattern/length)', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: 'AAPL; DROP TABLE', cusip: null, assetType: 'equity', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on a cusip that is not exactly 9 characters', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: null, cusip: 'TOOSHORT', assetType: 'equity', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on an asset_type outside 016\'s CHECK vocabulary', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: 'AAPL', cusip: null, assetType: 'nonsense', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it("400 on a personal-asset type (real_estate/vehicle/collectible/private) — excluded 2026-08-21: would mint a permanently-unpriceable global row", async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		for (const assetType of ['real_estate', 'vehicle', 'collectible', 'private']) {
			const res = await post(
				`${url}/asset/resolve`,
				{ ownerUserId: UUID, symbol: 'X', cusip: null, assetType, name: null, currency: 'USD' },
				authed
			);
			expect(res.status).toBe(400);
		}
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on currency (088 MINT mode already rejects it; the two surfaces must not disagree)', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: 'USD', cusip: null, assetType: 'currency', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on a bad uuid ownerUserId', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: 'not-a-uuid', symbol: 'AAPL', cusip: null, assetType: 'equity', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('400 on an extra field (Lock 14 mass-assignment fence, .strict)', async () => {
		const resolveAsset = vi.fn();
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{
				ownerUserId: UUID,
				symbol: 'AAPL',
				cusip: null,
				assetType: 'equity',
				name: null,
				currency: 'USD',
				users_id: 'other-tenant'
			},
			authed
		);
		expect(res.status).toBe(400);
		expect(resolveAsset).not.toHaveBeenCalled();
	});

	it('C6-5: any resolve failure returns a generic 502 with no detail leak', async () => {
		const resolveAsset = vi.fn(async () => {
			throw new Error('db blew up unexpectedly');
		});
		const url = await start({ resolveAsset });
		const res = await post(
			`${url}/asset/resolve`,
			{ ownerUserId: UUID, symbol: 'AAPL', cusip: null, assetType: 'equity', name: null, currency: 'USD' },
			authed
		);
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'asset_resolve_failed' });
	});

	it('405 on a wrong method for the resolve route', async () => {
		const url = await start();
		const res = await fetch(`${url}/asset/resolve`, { headers: authed });
		expect(res.status).toBe(405);
	});
});
