// simplefinAdmissionTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (OQ-2 / SC3-C6).
//
// SCOPE (QA, not a duplicate of the engineer's unit tests): the WORKER half of the leg-S
// two-tenant cross-binding proof — the test that would catch a REAL cross-tenant SimpleFIN
// credential violation. It drives the *real* admission HTTP server (real C6-6 auth gate + real
// Zod `.strict()` + real routing, admissionServer.ts) over the *real* SimpleFINAdapter.connect()
// (real SC3-C8 re-admission tenant guard + real atomic service_role admission), backed by a
// FAITHFUL two-tenant in-memory `pfin.linked_source` that models service_role's RLS-BYPASSED
// visibility (a service_role SELECT sees EVERY tenant's rows — exactly why SC3-C8 must exist).
//
// SimpleFIN's connection identity is the SHA-256 digest of the claimed Access URL (not Plaid's
// item_id). To ARM the SC3-C8 collision we contrive two setup tokens whose claims resolve to the
// SAME Access URL → the SAME digest → the SAME linked_source row (the analogue of Plaid's shared
// item_id). A real fresh claim yields a new random Access URL; the collision is a deliberate test
// fixture, identical in spirit to the Plaid ITEM_SHARED contrivance.
//
// The ONLY things mocked are Postgres + the SimpleFIN Bridge HTTP (claim POST + /accounts GET).
// A live-DB variant belongs at the RUN_DB_INTEGRATION tier; this in-memory model is deterministic,
// needs no running DB, and exercises the security-critical branch the engineer's fixtures do not
// reach (their fixture's dedup SELECT returns [] → the new-connection path; the SC3-C8 mismatch
// branch was previously UNCOVERED at the leg-S surface).
//
// Composition (documented for Sec joint-review): this proves the worker, even under RLS-bypassing
// service_role, refuses a cross-tenant SimpleFIN credential write. Its sibling —
// api/tests/simplefinConnectTwoTenant.qa.test.ts — proves the api/src relay only ever puts a
// SESSION-derived tenant on the wire. Together = the end-to-end two-tenant leg-S fence. Mirrors
// the Plaid pair (admissionTwoTenant + admissionRelayTwoTenant).
//
// Grounding: docs/SECURITY §4.5 · temp/oq2-connect-seam-design.md (§7 C6 mapping / §4 scrub) ·
// workers/…/adapters/SimpleFINAdapter.ts (connect() SC3-C8 guard + scrubbed errors).

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createAdmissionServer, type AdmissionServerDeps, type SimplefinClaimInput } from '../src/http/admissionServer.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';
import { SimpleFINAdapter, accessUrlDigest, type AdmissionDb, type FetchLike } from '../src/adapters/SimpleFINAdapter.js';
import type { Tx } from '../src/db/TenantBoundClient.js';
import * as fx from './fixtures/simplefin-payloads.js';

const SECRET = 'sfin-two-tenant-secret-0123456789abcdef0123456789abcdef';
const TENANT_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

// ── Claim URLs (decoded from the setup tokens) → the Access URL each claim RETURNS. ────────────
// a-shared and b-shared resolve to the SAME Access URL → the SAME digest → the cross-tenant
// collision that arms SC3-C8. a-only / b-only are distinct.
const CLAIM_A_SHARED = 'https://bridge.test/simplefin/claim/a-shared';
const CLAIM_B_SHARED = 'https://bridge.test/simplefin/claim/b-shared';
const CLAIM_A_ONLY = 'https://bridge.test/simplefin/claim/a-only';
const CLAIM_B_ONLY = 'https://bridge.test/simplefin/claim/b-only';

const b64 = (s: string): string => Buffer.from(s, 'utf8').toString('base64');
const SETUP_A_SHARED = b64(CLAIM_A_SHARED);
const SETUP_B_SHARED = b64(CLAIM_B_SHARED);
const SETUP_A_ONLY = b64(CLAIM_A_ONLY);
const SETUP_B_ONLY = b64(CLAIM_B_ONLY);

// Access URLs = the long-lived REUSABLE READ credentials — embed basic-auth (splitAuth must lift
// it to a header). These are the secrets that must NEVER leak (scrub sentinels).
const ACCESS_SHARED = 'https://uShared:pShared@sf.test/access/SHARED-SECRET-should-never-appear';
const ACCESS_A = 'https://uA:pA@sf.test/access/TENANT-A-SECRET-should-never-appear';
const ACCESS_B = 'https://uB:pB@sf.test/access/TENANT-B-SECRET-should-never-appear';

const CLAIM_TO_ACCESS: Record<string, string> = {
	[CLAIM_A_SHARED]: ACCESS_SHARED,
	[CLAIM_B_SHARED]: ACCESS_SHARED, // SAME Access URL → SAME digest → SC3-C8 collision
	[CLAIM_A_ONLY]: ACCESS_A,
	[CLAIM_B_ONLY]: ACCESS_B
};

const DIGEST_SHARED = accessUrlDigest(ACCESS_SHARED);
const DIGEST_A = accessUrlDigest(ACCESS_A);
const DIGEST_B = accessUrlDigest(ACCESS_B);

// ── A faithful in-memory pfin.linked_source under SERVICE_ROLE (RLS bypassed). ─────────────────
// Keyed by external_connection_id (the digest) — mirrors linked_source_provider_conn_uidx (015).
// A SELECT returns the row for ANY tenant (service_role sees all) — the precise condition that
// makes the SC3-C8 in-code tenant guard load-bearing rather than decorative.
interface SourceRow {
	source_id: string;
	credential_secret_id: string | null;
	users_id: string;
	access_url: string; // what create/update_secret stored (models the Vault secret content)
	institution_name: string | null;
	connection_status: string;
}

function makeTwoTenantStore() {
	const rows = new Map<string, SourceRow>(); // key = digest (provider is always 'simplefin' here)
	let sourceSeq = 0;
	let secretSeq = 0;
	let pendingSecret: { secretId: string; accessUrl: string } | null = null;

	const tx = (async (strings: TemplateStringsArray, ...params: unknown[]): Promise<unknown[]> => {
		const text = strings.join(''); // match on substrings

		// (1) Dedup SELECT — service_role sees ALL tenants. params = [digest]
		if (/select\s+source_id, credential_secret_id, users_id/.test(text)) {
			const digest = String(params[0]);
			const row = rows.get(digest);
			return row ? [{ source_id: row.source_id, credential_secret_id: row.credential_secret_id, users_id: row.users_id }] : [];
		}
		// (2) vault.create_secret(access_url, label, desc) → secret_id. params[0] = access_url
		if (/vault\.create_secret/.test(text)) {
			const accessUrl = String(params[0]);
			const secretId = `sec-${++secretSeq}`;
			pendingSecret = { secretId, accessUrl };
			return [{ secret_id: secretId }];
		}
		// (3) vault.update_secret(secret_id::uuid, access_url, label, desc). params[1] = access_url
		if (/vault\.update_secret/.test(text)) {
			const secretId = String(params[0]);
			const accessUrl = String(params[1]);
			pendingSecret = { secretId, accessUrl };
			return [];
		}
		// (4) INSERT linked_source ... values ('simplefin', secretId, digest, meta, 'healthy', ownerUserId, instName)
		if (/insert into\s+pfin\.linked_source/.test(text)) {
			const [secretId, digest, , ownerUserId, institutionName] = params as [string, string, unknown, string, string | null];
			const sourceId = String(++sourceSeq);
			rows.set(String(digest), {
				source_id: sourceId,
				credential_secret_id: String(secretId),
				users_id: String(ownerUserId),
				access_url: pendingSecret?.accessUrl ?? '',
				institution_name: institutionName ?? null,
				connection_status: 'healthy'
			});
			return [{ source_id: sourceId }];
		}
		// (5a) UPDATE ... set credential_secret_id = $ where source_id = $ (credential-less attach)
		if (/update pfin\.linked_source set credential_secret_id/.test(text)) {
			const [secretId, sourceId] = params as [string, string];
			for (const row of rows.values()) {
				if (row.source_id === String(sourceId)) {
					row.credential_secret_id = String(secretId);
					row.access_url = pendingSecret?.accessUrl ?? row.access_url;
				}
			}
			return [];
		}
		// (5b) UPDATE ... set connection_status=..., institution_name=$, ... where source_id=$
		if (/update\s+pfin\.linked_source/.test(text) && /connection_status/.test(text)) {
			// params order = [meta, institutionName, source_id] per the query.
			const sourceId = String(params[params.length - 1]);
			const institutionName = (params[1] as string | null) ?? null;
			for (const row of rows.values()) {
				if (row.source_id === sourceId) {
					row.connection_status = 'healthy';
					row.institution_name = institutionName;
					if (pendingSecret) row.access_url = pendingSecret.accessUrl; // same-tenant rotation persisted
				}
			}
			return [];
		}
		return [];
	}) as unknown as Tx;

	const dbFor = (_usersId: string): AdmissionDb => ({
		// service_role: NO tenant scoping at the DB layer — the whole point of SC3-C8.
		withServiceRole: (<T>(fn: (t: Tx) => Promise<T>) => fn(tx)) as AdmissionDb['withServiceRole'],
		end: vi.fn(async () => {})
	});

	return { rows, dbFor };
}

// ── SimpleFIN Bridge fetch mock: POST <claim URL> → Access URL (text); GET .../accounts → set. ──
// `claimStatus` forces a non-200 claim response to exercise the SetupTokenInvalidError (4xx) vs
// generic-5xx (fail-safe) discrimination. Records every call for "no HTTP happened" assertions.
function makeBridgeFetch(opts: { claimStatus?: number; calls?: { url: string; method: string }[] } = {}): FetchLike {
	return async (url, init) => {
		opts.calls?.push({ url, method: init?.method ?? 'GET' });
		if (init?.method === 'POST') {
			const status = opts.claimStatus ?? 200;
			// The claim URL has no basic-auth, so splitAuth left it intact → look up the Access URL.
			const access = CLAIM_TO_ACCESS[url] ?? ACCESS_A;
			// On a forced non-200, the body carries the Access URL to prove the scrub discards it.
			return { ok: status === 200, status, text: async () => access, json: async () => ({}) };
		}
		// GET .../accounts (basic-auth lifted to a header by splitAuth → url is auth-stripped).
		return { ok: true, status: 200, text: async () => JSON.stringify(fx.accountsSetClean), json: async () => fx.accountsSetClean };
	};
}

let live: Server | undefined;
afterEach(async () => {
	if (live) await new Promise<void>((r) => live!.close(() => r()));
	live = undefined;
});

// Boots the REAL admission server wired to the REAL SimpleFINAdapter over the two-tenant store.
async function startAdmission(
	opts: { logger?: (m: string) => void; store?: ReturnType<typeof makeTwoTenantStore>; fetchLike?: FetchLike } = {}
) {
	const store = opts.store ?? makeTwoTenantStore();
	const adapter = new SimpleFINAdapter(store.dbFor, opts.logger, opts.fetchLike ?? makeBridgeFetch());
	const deps: AdmissionServerDeps = {
		sharedSecret: SECRET,
		mintLinkToken: vi.fn(async () => ({ link_token: 'link-1', expiration: 'exp-1' })),
		admit: vi.fn(async () => ({ sourceId: 0n, accounts: [] })), // Plaid leg unused here
		admitSimplefin: (input: SimplefinClaimInput) =>
			adapter.connect({
				provider: 'simplefin',
				setupToken: input.setupToken,
				ownerUserId: input.ownerUserId,
				institutionName: input.institutionName
			}),
		logger: opts.logger
	};
	live = createAdmissionServer(deps);
	await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
	const { port } = live!.address() as AddressInfo;
	return { url: `http://127.0.0.1:${port}`, store };
}

function claim(url: string, body: unknown, secret = SECRET): Promise<Response> {
	return fetch(`${url}/admission/simplefin/claim`, {
		method: 'POST',
		headers: { 'content-type': 'application/json', [ADMISSION_SECRET_HEADER]: secret },
		body: JSON.stringify(body)
	});
}

describe('OQ-2 leg-S two-tenant credential-write boundary (QA — end-to-end worker admission)', () => {
	it('tenant A admits its own connection → row bound to A; the stored credential is A’s Access URL', async () => {
		const { url, store } = await startAdmission();
		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A });
		expect(res.status).toBe(200);

		const row = store.rows.get(DIGEST_A);
		expect(row?.users_id).toBe(TENANT_A);
		expect(row?.access_url).toBe(ACCESS_A);
	});

	it('CORE: tenant B CANNOT rotate/overwrite tenant A’s existing credential on a digest collision (SC3-C8 fail-closed)', async () => {
		const store = makeTwoTenantStore();

		// (1) Tenant A admits the shared connection → row bound to A, holding A’s (shared) Access URL.
		const a = await startAdmission({ store });
		expect((await claim(a.url, { setup_token: SETUP_A_SHARED, ownerUserId: TENANT_A })).status).toBe(200);
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const before = { ...store.rows.get(DIGEST_SHARED)! };
		expect(before.users_id).toBe(TENANT_A);
		expect(before.access_url).toBe(ACCESS_SHARED);

		// (2) Tenant B presents a setup token whose claim resolves to the SAME Access URL (same
		//     digest). Under service_role the dedup SELECT finds A’s row (RLS bypassed). SC3-C8 fires.
		const b = await startAdmission({ store });
		const res = await claim(b.url, { setup_token: SETUP_B_SHARED, ownerUserId: TENANT_B });

		// Rejected — a generic 502 envelope (no internal detail leaks, C6-5); a server-side mismatch
		// is NOT a client-correctable setup_token_invalid (fail-safe: it stays 5xx, not 400).
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'admission_failed' });

		// (3) THE violation this test exists to catch: A’s credential is UNTOUCHED — not rotated to
		//     B’s token, ownership not flipped, secret handle unchanged.
		const after = store.rows.get(DIGEST_SHARED)!;
		expect(after.users_id).toBe(TENANT_A); // ownership NOT flipped to B
		expect(after.access_url).toBe(ACCESS_SHARED); // credential NOT overwritten
		expect(after.credential_secret_id).toBe(before.credential_secret_id);
		expect(store.rows.size).toBe(1); // no second row minted for B
	});

	it('two tenants admitting DISTINCT connections → two independent rows, no cross-contamination', async () => {
		const store = makeTwoTenantStore();
		const a = await startAdmission({ store });
		expect((await claim(a.url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A })).status).toBe(200);
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const b = await startAdmission({ store });
		expect((await claim(b.url, { setup_token: SETUP_B_ONLY, ownerUserId: TENANT_B })).status).toBe(200);

		expect(store.rows.get(DIGEST_A)?.users_id).toBe(TENANT_A);
		expect(store.rows.get(DIGEST_A)?.access_url).toBe(ACCESS_A);
		expect(store.rows.get(DIGEST_B)?.users_id).toBe(TENANT_B);
		expect(store.rows.get(DIGEST_B)?.access_url).toBe(ACCESS_B);
	});

	it('the same tenant re-admitting its own connection rotates in place (baseline for the SC3-C8 contrast)', async () => {
		const store = makeTwoTenantStore();
		const first = await startAdmission({ store });
		expect((await claim(first.url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A })).status).toBe(200);
		const firstSourceId = store.rows.get(DIGEST_A)?.source_id;
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		// Same tenant, same Access URL → re-admission UPDATE in place (no duplicate row, same source_id).
		const second = await startAdmission({ store });
		expect((await claim(second.url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A })).status).toBe(200);
		expect(store.rows.size).toBe(1);
		expect(store.rows.get(DIGEST_A)?.source_id).toBe(firstSourceId);
		expect(store.rows.get(DIGEST_A)?.users_id).toBe(TENANT_A);
	});
});

describe('OQ-2 leg-S — C6-2/C6-6 auth gate + .strict body-injection (worker boundary, fail-closed)', () => {
	it('a WRONG shared secret → 401; connect() never runs (no claim HTTP, no row)', async () => {
		const store = makeTwoTenantStore();
		const calls: { url: string; method: string }[] = [];
		const { url } = await startAdmission({ store, fetchLike: makeBridgeFetch({ calls }) });

		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A }, 'wrong-secret');
		expect(res.status).toBe(401);
		expect(await res.json()).toEqual({ error: 'unauthorized' });
		expect(calls).toHaveLength(0); // no Bridge claim attempted — gated before any admission
		expect(store.rows.size).toBe(0);
	});

	it('a body-injected extra tenant field is rejected at the worker boundary (.strict) — admit never runs', async () => {
		const store = makeTwoTenantStore();
		const calls: { url: string; method: string }[] = [];
		const { url } = await startAdmission({ store, fetchLike: makeBridgeFetch({ calls }) });

		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A, tenant_override: TENANT_B });
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: 'invalid_request' });
		expect(calls).toHaveLength(0); // no claim executed
		expect(store.rows.size).toBe(0);
	});
});

describe('OQ-2 leg-S — client-correctable discrimination end-to-end (403 → 400 vs 5xx → 502)', () => {
	it('a 403 (burned/already-claimed setup token) → worker 400 setup_token_invalid (client-correctable)', async () => {
		const { url } = await startAdmission({ fetchLike: makeBridgeFetch({ claimStatus: 403 }) });
		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A });
		expect(res.status).toBe(400);
		const text = await res.text();
		expect(text).toBe(JSON.stringify({ error: 'setup_token_invalid' }));
		// The 403 body carried the Access URL — it must NOT surface in the envelope.
		expect(text).not.toContain('SHARED-SECRET');
		expect(text).not.toContain('access/');
	});

	it('a 500 (Bridge server error) → worker 502 admission_failed (fail-safe, NOT dressed as client-correctable)', async () => {
		const { url } = await startAdmission({ fetchLike: makeBridgeFetch({ claimStatus: 500 }) });
		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A });
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'admission_failed' });
	});

	it('a setup token that does not base64-decode to a URL → worker 400 setup_token_invalid', async () => {
		const { url } = await startAdmission();
		const res = await claim(url, { setup_token: 'not-base64-url!!', ownerUserId: TENANT_A });
		expect(res.status).toBe(400);
		expect(await res.text()).toBe(JSON.stringify({ error: 'setup_token_invalid' }));
	});
});

// ── C6-5 log-scrub — WORKER tier, independent systematic sweep (success + failure paths) ────────
// Capture EVERY logger line AND the full response body across success, the SC3-C8 collision, and a
// claim-throw whose body carries the Access URL, then assert NONE of the credential sentinels
// (Access URLs, basic-auth fragments, the shared secret, decoded claim URLs) ever appears.
describe('C6-5 log-scrub — worker leg-S tier (independent sweep)', () => {
	const SENTINELS = [ACCESS_SHARED, ACCESS_A, ACCESS_B, SECRET, 'uShared:pShared', 'uA:pA', 'SHARED-SECRET', 'TENANT-A-SECRET'];

	it('no Access URL / basic-auth / shared-secret in worker logs OR the response — success path', async () => {
		const logLines: string[] = [];
		const { url } = await startAdmission({ logger: (m) => logLines.push(m) });
		const res = await claim(url, { setup_token: SETUP_A_ONLY, ownerUserId: TENANT_A });
		const bodyText = await res.text();

		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('no credential sentinels in logs OR the generic envelope — SC3-C8 collision failure path', async () => {
		const store = makeTwoTenantStore();
		const logLines: string[] = [];
		const a = await startAdmission({ store, logger: (m) => logLines.push(m) });
		await claim(a.url, { setup_token: SETUP_A_SHARED, ownerUserId: TENANT_A });
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const b = await startAdmission({ store, logger: (m) => logLines.push(m) });
		const res = await claim(b.url, { setup_token: SETUP_B_SHARED, ownerUserId: TENANT_B });
		const bodyText = await res.text();

		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('no credential sentinels when the claim returns a 403 whose body carries the Access URL', async () => {
		const logLines: string[] = [];
		const { url } = await startAdmission({ logger: (m) => logLines.push(m), fetchLike: makeBridgeFetch({ claimStatus: 403 }) });
		const res = await claim(url, { setup_token: SETUP_A_SHARED, ownerUserId: TENANT_A });
		const bodyText = await res.text();

		expect(res.status).toBe(400); // client-correctable
		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});
});
