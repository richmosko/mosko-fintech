// webhook.server.test.ts — SELF-206 handler integration tests (Route Z-INVOKER two-phase).
// Real jose ES256 JWTs; mocked supabase-js `.schema('pfin').rpc(...)` (fn_plaid_webhook_resolve /
// fn_plaid_webhook_commit); mocked worker legs. Proves: 401 fail-closed (no RPC calls); the
// resolve→(sync)→commit orchestration; C-X1 (sync-unconfirmed → 5xx, no commit); ack-drop on
// unknown Item; confirmed-duplicate short-circuit; ITEM event skips sync and commits.

import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import { createHash } from 'node:crypto';
import { generateKeyPair, exportJWK, SignJWT, type JWK } from 'jose';

const h = vi.hoisted(() => ({
	jwk: null as JWK | null,
	admin: null as unknown,
	triggerSourceSync: vi.fn(async () => ({ ok: true }))
}));

vi.mock('$lib/server/plaid/admissionClient', () => ({
	fetchWebhookVerificationKey: async () => {
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

/** Mock admin whose `.schema('pfin').rpc(fn, params)` returns configured per-fn results and records calls. */
function makeAdmin(cfg: { resolve?: RpcResult; commit?: RpcResult }): {
	schema: () => { rpc: (fn: string, params: unknown) => Promise<RpcResult> };
	rpcCalls: { fn: string; params: Record<string, unknown> }[];
} {
	const rpcCalls: { fn: string; params: Record<string, unknown> }[] = [];
	const rpc = (fn: string, params: unknown): Promise<RpcResult> => {
		rpcCalls.push({ fn, params: params as Record<string, unknown> });
		if (fn === 'fn_plaid_webhook_resolve') {
			return Promise.resolve(cfg.resolve ?? { data: [DEFAULT_RESOLVE], error: null });
		}
		if (fn === 'fn_plaid_webhook_commit') {
			return Promise.resolve(cfg.commit ?? { data: [{ committed: true, was_fresh: true }], error: null });
		}
		return Promise.resolve({ data: null, error: null });
	};
	return { schema: () => ({ rpc }), rpcCalls };
}

const SOURCE_ID = 501;
const USERS_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
interface ResolveRow {
	resolved: boolean;
	already_processed: boolean;
	should_trigger_sync: boolean;
	source_id: number | null;
	users_id: string | null;
}
const DEFAULT_RESOLVE: ResolveRow = {
	resolved: true,
	already_processed: false,
	should_trigger_sync: false,
	source_id: SOURCE_ID,
	users_id: USERS_ID
};
const resolveRow = (over: Partial<typeof DEFAULT_RESOLVE>): RpcResult => ({
	data: [{ ...DEFAULT_RESOLVE, ...over }],
	error: null
});

const NOW = Date.now();
let signJwt: (payload: Record<string, unknown>) => Promise<string>;

beforeAll(async () => {
	const { publicKey, privateKey } = await generateKeyPair('ES256', { extractable: true });
	const pub = await exportJWK(publicKey);
	h.jwk = { ...pub, kid: 'kid-1', alg: 'ES256', use: 'sig' };
	signJwt = (payload) =>
		new SignJWT(payload).setProtectedHeader({ alg: 'ES256', kid: 'kid-1' }).sign(privateKey);
});

beforeEach(() => h.triggerSourceSync.mockClear());

const sha256hex = (s: string): string => createHash('sha256').update(s, 'utf8').digest('hex');

async function call(body: object, opts: { header?: string } = {}): Promise<Response> {
	const raw = JSON.stringify(body);
	const jwt = await signJwt({ iat: Math.floor(NOW / 1000), request_body_sha256: sha256hex(raw) });
	const request = new Request('http://localhost/api/plaid/webhook', {
		method: 'POST',
		headers: { 'content-type': 'application/json', 'plaid-verification': opts.header ?? jwt },
		body: raw
	});
	return POST({ request } as unknown as Parameters<typeof POST>[0]);
}

const rpcNames = (admin: { rpcCalls: { fn: string }[] }): string[] => admin.rpcCalls.map((c) => c.fn);

describe('POST /api/plaid/webhook — AC1 signature verification', () => {
	it('invalid signature → 401 and NO RPC calls / no sync', async () => {
		const admin = makeAdmin({});
		h.admin = admin;
		const res = await call({ webhook_type: 'ITEM', webhook_code: 'ERROR', item_id: 'itm_1' }, { header: 'not.a.jwt' });
		expect(res.status).toBe(401);
		expect(admin.rpcCalls).toHaveLength(0);
		expect(h.triggerSourceSync).not.toHaveBeenCalled();
	});
});

describe('POST /api/plaid/webhook — AC5 transactions (resolve → sync → commit)', () => {
	it('fresh transactions event → resolve, triggerSourceSync(users_id, source_id), commit; 200', async () => {
		const admin = makeAdmin({ resolve: resolveRow({ should_trigger_sync: true }) });
		h.admin = admin;
		const res = await call({ webhook_type: 'TRANSACTIONS', webhook_code: 'SYNC_UPDATES_AVAILABLE', item_id: 'itm_1', environment: 'production' });
		expect(res.status).toBe(200);
		expect(h.triggerSourceSync).toHaveBeenCalledWith(USERS_ID, String(SOURCE_ID));
		expect(rpcNames(admin)).toEqual(['fn_plaid_webhook_resolve', 'fn_plaid_webhook_commit']);
		// The commit p_event carries provider_event_id + sync_outcome + is_transactions_event.
		const commit = admin.rpcCalls.find((c) => c.fn === 'fn_plaid_webhook_commit');
		const pEvent = commit?.params.p_event as Record<string, unknown>;
		expect(pEvent.item_id).toBe('itm_1');
		// Per-path idempotency (045): TRANSACTIONS events carry a NULL provider_event_id (deduped by
		// the cursor; a content-hash id would false-collide on same-second identical bodies).
		expect(pEvent.provider_event_id).toBeNull();
		expect(pEvent.sync_outcome).toEqual({ ok: true });
		expect(pEvent.is_transactions_event).toBe(true);
	});

	it('C-X1: sync did NOT confirm → 5xx and commit is NEVER called (gate not claimed)', async () => {
		h.triggerSourceSync.mockResolvedValueOnce({ ok: false });
		const admin = makeAdmin({ resolve: resolveRow({ should_trigger_sync: true }) });
		h.admin = admin;
		const res = await call({ webhook_type: 'TRANSACTIONS', webhook_code: 'SYNC_UPDATES_AVAILABLE', item_id: 'itm_1' });
		expect(res.status).toBeGreaterThanOrEqual(500);
		expect(rpcNames(admin)).toEqual(['fn_plaid_webhook_resolve']); // resolve only; NO commit
	});
});

describe('POST /api/plaid/webhook — AC4 ITEM event (no sync, commit state+gate)', () => {
	it('resolved non-transactions ITEM → NO sync, commit with normalized status_class; 200', async () => {
		const admin = makeAdmin({ resolve: resolveRow({ should_trigger_sync: false }) });
		h.admin = admin;
		const res = await call({
			webhook_type: 'ITEM',
			webhook_code: 'ERROR',
			item_id: 'itm_1',
			error: { error_code: 'ITEM_LOGIN_REQUIRED' }
		});
		expect(res.status).toBe(200);
		expect(h.triggerSourceSync).not.toHaveBeenCalled();
		expect(rpcNames(admin)).toEqual(['fn_plaid_webhook_resolve', 'fn_plaid_webhook_commit']);
		const commit = admin.rpcCalls.find((c) => c.fn === 'fn_plaid_webhook_commit');
		const pEvent = commit?.params.p_event as Record<string, unknown>;
		expect(pEvent.status_class).toBe('login_required');
		expect(pEvent.provider_error_code).toBe('ITEM_LOGIN_REQUIRED');
		// Per-path idempotency (045): STATE events carry a NON-NULL per-delivery id (exact-replay
		// suppression via RPC-1 already_processed; RPC-2 RAISEs on NULL for a STATE event).
		expect(typeof pEvent.provider_event_id).toBe('string');
		expect(pEvent.is_transactions_event).toBe(false);
	});
});

describe('POST /api/plaid/webhook — idempotency + unknown Item', () => {
	it('unknown/foreign Item (resolved=false) → 200 ack-drop, no sync, no commit, MOD-2 forensic WARN', async () => {
		const admin = makeAdmin({ resolve: resolveRow({ resolved: false, source_id: null, users_id: null }) });
		h.admin = admin;
		const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
		const res = await call({ webhook_type: 'TRANSACTIONS', webhook_code: 'SYNC_UPDATES_AVAILABLE', item_id: 'itm_UNKNOWN' });
		expect(res.status).toBe(200);
		expect(h.triggerSourceSync).not.toHaveBeenCalled();
		expect(rpcNames(admin)).toEqual(['fn_plaid_webhook_resolve']); // no commit
		// MOD 2 (Sec): the ack-drop of a valid-signature unknown-Item webhook MUST be detectable
		// (possible orphaned live Plaid Item). The breadcrumb carries the opaque item_id (M8-safe).
		expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('ack-drop'));
		expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('itm_UNKNOWN'));
		warnSpy.mockRestore();
	});

	it('already_processed (confirmed duplicate) → 200, no sync, no commit', async () => {
		const admin = makeAdmin({ resolve: resolveRow({ already_processed: true, should_trigger_sync: false }) });
		h.admin = admin;
		const res = await call({ webhook_type: 'TRANSACTIONS', webhook_code: 'SYNC_UPDATES_AVAILABLE', item_id: 'itm_1' });
		expect(res.status).toBe(200);
		expect(h.triggerSourceSync).not.toHaveBeenCalled();
		expect(rpcNames(admin)).toEqual(['fn_plaid_webhook_resolve']);
	});

	it('commit RPC error → 500', async () => {
		const admin = makeAdmin({
			resolve: resolveRow({ should_trigger_sync: false }),
			commit: { data: null, error: { message: 'boom' } }
		});
		h.admin = admin;
		const res = await call({ webhook_type: 'ITEM', webhook_code: 'ERROR', item_id: 'itm_1', error: { error_code: 'ITEM_LOGIN_REQUIRED' } });
		expect(res.status).toBe(500);
	});
});
