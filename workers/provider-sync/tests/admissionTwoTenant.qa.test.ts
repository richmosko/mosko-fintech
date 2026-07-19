// admissionTwoTenant.qa.test.ts — QA INDEPENDENT verification battery (SELF-212 / SC3-C6).
//
// SCOPE (QA, not a duplicate of the engineers' unit tests): the WORKER half of the
// two-tenant cross-binding proof — the test that would catch a REAL cross-tenant credential
// violation. It drives the *real* admission HTTP server (real auth gate + real Zod `.strict()`
// + real routing, admissionServer.ts) over the *real* PlaidAdapter.connect() (real SC3-C8
// re-admission tenant guard + real (u) atomic admission body), backed by a FAITHFUL two-tenant
// in-memory `pfin.linked_source` that models service_role's RLS-BYPASSED visibility (a
// service_role SELECT sees EVERY tenant's rows — which is exactly why SC3-C8 must exist).
//
// The ONLY thing mocked is Postgres + the Plaid SDK. A live-DB variant belongs at the
// RUN_DB_INTEGRATION tier (see tests/integration/**); this in-memory model is deterministic,
// needs no running DB, and exercises the security-critical branch the engineers' fixtures do
// not reach (their C6-4 fixture's dedup SELECT always returns [] → the new-connection path;
// the SC3-C8 mismatch branch was previously UNCOVERED).
//
// Composition (documented for Sec joint-review): this file proves the worker, even under
// RLS-bypassing service_role, refuses a cross-tenant credential write. Its sibling —
// api/tests/admissionRelayTwoTenant.qa.test.ts — proves the api/src relay only ever puts a
// SESSION-derived tenant on the wire (never a browser-body tenant), for two tenants. Together
// they are the end-to-end two-tenant fence, each half tested at its right level.
//
// Grounding: docs/SECURITY §4.5 (two-tenant posture) · temp/self212-sec-c6-review.md
// (C6-3 / SC3-C8 / C6-5) · temp/self212-worker-endpoint-contract.md.

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { createAdmissionServer, type AdmissionServerDeps, type ExchangeInput } from '../src/http/admissionServer.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';
import { PlaidAdapter, type PlaidClientLike, type AdmissionDb } from '../src/adapters/PlaidAdapter.js';
import type { Tx } from '../src/db/TenantBoundClient.js';
import * as fx from './fixtures/plaid-payloads.js';

const SECRET = 'two-tenant-secret-0123456789abcdef0123456789abcdef';
const TENANT_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const TENANT_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
// A public_token → item_id map lets a test FORCE the same Plaid Item (external_connection_id)
// for two different tenants — the cross-tenant collision that arms SC3-C8.
const ITEM_SHARED = 'item_SHARED_COLLISION';
const ITEM_A_ONLY = 'item_A_ONLY';
const ITEM_B_ONLY = 'item_B_ONLY';
const ACCESS_A = 'access-sandbox-TENANT-A-SECRET-should-never-appear';
const ACCESS_B = 'access-sandbox-TENANT-B-SECRET-should-never-appear';

// ── A faithful in-memory pfin.linked_source under SERVICE_ROLE (RLS bypassed) ─────────────────
// Keyed by (provider, external_connection_id) — mirrors linked_source_provider_conn_uidx (015).
// A SELECT returns the row for ANY tenant (service_role sees all) — the precise condition that
// makes the SC3-C8 in-code tenant guard load-bearing rather than decorative.
interface SourceRow {
	source_id: string;
	credential_secret_id: string | null;
	users_id: string;
	access_token: string; // what create/update_secret stored (models the Vault secret content)
	institution_name: string | null;
	connection_status: string;
}

function makeTwoTenantStore() {
	const rows = new Map<string, SourceRow>(); // key = itemId (provider is always 'plaid' here)
	let sourceSeq = 0;
	let secretSeq = 0;

	// A postgres.js-style tagged-template runner over the in-memory store. Matches the exact
	// query shapes PlaidAdapter.#admitAfterExchange interpolates, in order.
	const tx = (async (strings: TemplateStringsArray, ...params: unknown[]): Promise<unknown[]> => {
		const text = strings.join(''); // join marker irrelevant; we match on substrings

		// (1) Dedup SELECT — service_role sees ALL tenants. params = [itemId]
		if (/select\s+source_id, credential_secret_id, users_id/.test(text)) {
			const itemId = String(params[0]);
			const row = rows.get(itemId);
			return row ? [{ source_id: row.source_id, credential_secret_id: row.credential_secret_id, users_id: row.users_id }] : [];
		}
		// (2) vault.create_secret(access_token, label, desc) → secret_id. params[0] = access_token
		if (/vault\.create_secret/.test(text)) {
			const accessToken = String(params[0]);
			const secretId = `sec-${++secretSeq}`;
			// Stash the token+secret on a scratch slot so the following INSERT/UPDATE can persist it.
			pendingSecret = { secretId, accessToken };
			return [{ secret_id: secretId }];
		}
		// (3) vault.update_secret(secret_id::uuid, access_token, label, desc). params[1] = access_token
		if (/vault\.update_secret/.test(text)) {
			const secretId = String(params[0]);
			const accessToken = String(params[1]);
			pendingSecret = { secretId, accessToken };
			return [];
		}
		// (4) INSERT linked_source ... values ('plaid', secretId, itemId, meta, 'healthy', ownerUserId, instId, instName)
		if (/insert into\s+pfin\.linked_source/.test(text)) {
			const [secretId, itemId, , ownerUserId, , institutionName] = params as [string, string, unknown, string, unknown, string | null];
			const sourceId = String(++sourceSeq);
			rows.set(String(itemId), {
				source_id: sourceId,
				credential_secret_id: String(secretId),
				users_id: String(ownerUserId),
				access_token: pendingSecret?.accessToken ?? '',
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
					row.access_token = pendingSecret?.accessToken ?? row.access_token;
				}
			}
			return [];
		}
		// (5b) UPDATE ... set connection_status=..., institution_name=$, ... where source_id=$
		if (/update\s+pfin\.linked_source/.test(text) && /connection_status/.test(text)) {
			// params order = [institutionId, institutionName, source_id] per the query.
			const sourceId = String(params[params.length - 1]);
			const institutionName = (params[1] as string | null) ?? null;
			for (const row of rows.values()) {
				if (row.source_id === sourceId) {
					row.connection_status = 'healthy';
					row.institution_name = institutionName;
					// A same-tenant rotation persisted the new token via pendingSecret above.
					if (pendingSecret) row.access_token = pendingSecret.accessToken;
				}
			}
			return [];
		}
		return [];
	}) as unknown as Tx;

	let pendingSecret: { secretId: string; accessToken: string } | null = null;

	const dbFor = (_usersId: string): AdmissionDb => ({
		// service_role: NO tenant scoping at the DB layer — the whole point of SC3-C8.
		withServiceRole: (<T>(fn: (t: Tx) => Promise<T>) => fn(tx)) as AdmissionDb['withServiceRole'],
		end: vi.fn(async () => {})
	});

	return { rows, dbFor };
}

// Plaid SDK mock: public_token → (item_id, access_token). Lets a test force a shared item_id.
function makePlaidClient(logSink?: (m: string) => void): PlaidClientLike {
	const tokenMap: Record<string, { item_id: string; access_token: string }> = {
		'public-A-shared': { item_id: ITEM_SHARED, access_token: ACCESS_A },
		'public-B-shared': { item_id: ITEM_SHARED, access_token: ACCESS_B },
		'public-A-only': { item_id: ITEM_A_ONLY, access_token: ACCESS_A },
		'public-B-only': { item_id: ITEM_B_ONLY, access_token: ACCESS_B }
	};
	return {
		linkTokenCreate: vi.fn(),
		itemPublicTokenExchange: vi.fn(async (req: { public_token: string }) => {
			const m = tokenMap[req.public_token];
			if (!m) throw new Error('unknown public_token in fixture');
			return { data: { access_token: m.access_token, item_id: m.item_id } };
		}),
		accountsGet: vi.fn(async () => ({ data: { accounts: [fx.acctDepository] } })),
		itemRemove: vi.fn(async () => ({ data: {} })),
		sandboxPublicTokenCreate: vi.fn(),
		transactionsSync: vi.fn(),
		investmentsHoldingsGet: vi.fn(),
		investmentsTransactionsGet: vi.fn()
	} as unknown as PlaidClientLike;
}

let live: Server | undefined;
afterEach(async () => {
	if (live) await new Promise<void>((r) => live!.close(() => r()));
	live = undefined;
});

// Boots the REAL admission server wired to the REAL PlaidAdapter over the two-tenant store.
async function startAdmission(opts: { logger?: (m: string) => void; store?: ReturnType<typeof makeTwoTenantStore> } = {}) {
	const store = opts.store ?? makeTwoTenantStore();
	const plaid = makePlaidClient(opts.logger);
	const adapter = new PlaidAdapter(plaid, store.dbFor, opts.logger);
	const deps: AdmissionServerDeps = {
		sharedSecret: SECRET,
		mintLinkToken: vi.fn(async () => ({ link_token: 'link-1', expiration: 'exp-1' })),
		admit: (input: ExchangeInput) =>
			adapter.connect({
				provider: 'plaid',
				publicToken: input.publicToken,
				ownerUserId: input.ownerUserId,
				institutionId: input.institutionId,
				institutionName: input.institutionName
			}),
		logger: opts.logger
	};
	live = createAdmissionServer(deps);
	await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
	const { port } = live!.address() as AddressInfo;
	return { url: `http://127.0.0.1:${port}`, store, plaid };
}

function exchange(url: string, body: unknown, secret = SECRET): Promise<Response> {
	return fetch(`${url}/admission/exchange`, {
		method: 'POST',
		headers: { 'content-type': 'application/json', [ADMISSION_SECRET_HEADER]: secret },
		body: JSON.stringify(body)
	});
}

describe('SELF-212 two-tenant credential-write boundary (QA — end-to-end worker admission)', () => {
	it('tenant A admits its own item → row bound to A; the stored credential is A’s', async () => {
		const { url, store } = await startAdmission();
		const res = await exchange(url, { public_token: 'public-A-only', ownerUserId: TENANT_A });
		expect(res.status).toBe(200);

		const row = store.rows.get(ITEM_A_ONLY);
		expect(row?.users_id).toBe(TENANT_A);
		expect(row?.access_token).toBe(ACCESS_A);
	});

	it('CORE: tenant B CANNOT rotate/overwrite tenant A’s existing credential (SC3-C8 fail-closed)', async () => {
		const store = makeTwoTenantStore();

		// (1) Tenant A admits the shared Item → linked_source row bound to A, holding A’s token.
		const a = await startAdmission({ store });
		expect((await exchange(a.url, { public_token: 'public-A-shared', ownerUserId: TENANT_A })).status).toBe(200);
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const before = { ...store.rows.get(ITEM_SHARED)! };
		expect(before.users_id).toBe(TENANT_A);
		expect(before.access_token).toBe(ACCESS_A);

		// (2) Tenant B presents a public_token that exchanges to the SAME item_id. Under
		//     service_role the dedup SELECT finds A’s row (RLS bypassed). SC3-C8 MUST fail closed.
		const b = await startAdmission({ store });
		const res = await exchange(b.url, { public_token: 'public-B-shared', ownerUserId: TENANT_B });

		// The admission is rejected — a generic 502 envelope (no internal detail leaks, C6-5).
		expect(res.status).toBe(502);
		expect(await res.json()).toEqual({ error: 'admission_failed' });

		// (3) THE violation this test exists to catch: A’s credential is UNTOUCHED — not rotated
		//     to B’s token, ownership not flipped, status unchanged. A cross-tenant credential
		//     takeover would have mutated one of these.
		const after = store.rows.get(ITEM_SHARED)!;
		expect(after.users_id).toBe(TENANT_A); // ownership NOT flipped to B
		expect(after.access_token).toBe(ACCESS_A); // B’s token did NOT overwrite A’s
		expect(after.credential_secret_id).toBe(before.credential_secret_id);
	});

	it('two tenants admitting DISTINCT items → two independent rows, no cross-contamination', async () => {
		const store = makeTwoTenantStore();
		const a = await startAdmission({ store });
		expect((await exchange(a.url, { public_token: 'public-A-only', ownerUserId: TENANT_A })).status).toBe(200);
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const b = await startAdmission({ store });
		expect((await exchange(b.url, { public_token: 'public-B-only', ownerUserId: TENANT_B })).status).toBe(200);

		expect(store.rows.get(ITEM_A_ONLY)?.users_id).toBe(TENANT_A);
		expect(store.rows.get(ITEM_A_ONLY)?.access_token).toBe(ACCESS_A);
		expect(store.rows.get(ITEM_B_ONLY)?.users_id).toBe(TENANT_B);
		expect(store.rows.get(ITEM_B_ONLY)?.access_token).toBe(ACCESS_B);
	});

	it('a body-injected extra tenant field is rejected at the worker boundary (.strict) — admit never runs', async () => {
		const store = makeTwoTenantStore();
		const { url } = await startAdmission({ store });
		// An attacker who reached the worker directly tries to smuggle a second tenant.
		const res = await exchange(url, {
			public_token: 'public-A-only',
			ownerUserId: TENANT_A,
			tenant_override: TENANT_B
		});
		expect(res.status).toBe(400);
		expect(await res.json()).toEqual({ error: 'invalid_request' });
		// No row was written — the admission body never executed.
		expect(store.rows.size).toBe(0);
	});

	it('the same tenant re-admitting its own item rotates in place (baseline for the SC3-C8 contrast)', async () => {
		const store = makeTwoTenantStore();
		const first = await startAdmission({ store });
		expect((await exchange(first.url, { public_token: 'public-A-only', ownerUserId: TENANT_A })).status).toBe(200);
		const firstSourceId = store.rows.get(ITEM_A_ONLY)?.source_id;
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		// Same tenant, same item → re-admission UPDATE in place (no duplicate row, same source_id).
		const second = await startAdmission({ store });
		expect((await exchange(second.url, { public_token: 'public-A-only', ownerUserId: TENANT_A })).status).toBe(200);
		expect(store.rows.size).toBe(1);
		expect(store.rows.get(ITEM_A_ONLY)?.source_id).toBe(firstSourceId);
		expect(store.rows.get(ITEM_A_ONLY)?.users_id).toBe(TENANT_A);
	});
});

// ── C6-5 log-scrub — WORKER tier, independent systematic sweep (success + both failure paths) ──
// Complements the engineers' path-specific redaction assertions: capture EVERY logger line AND
// the full response body across success, the SC3-C8 failure, and a Plaid-throw failure, then
// assert NONE of the credential sentinels ever appears.
describe('C6-5 log-scrub — worker tier (independent sweep)', () => {
	const SENTINELS = [ACCESS_A, ACCESS_B, SECRET, 'public-A-shared', 'public-B-shared'];

	it('no access_token / public_token / shared-secret in worker logs OR responses — success path', async () => {
		const logLines: string[] = [];
		const { url } = await startAdmission({ logger: (m) => logLines.push(m) });
		const res = await exchange(url, { public_token: 'public-A-only', ownerUserId: TENANT_A });
		const bodyText = await res.text();

		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('no credential sentinels in logs OR the generic envelope — SC3-C8 failure path', async () => {
		const store = makeTwoTenantStore();
		const logLines: string[] = [];
		const a = await startAdmission({ store, logger: (m) => logLines.push(m) });
		await exchange(a.url, { public_token: 'public-A-shared', ownerUserId: TENANT_A });
		await new Promise<void>((r) => live!.close(() => r()));
		live = undefined;

		const b = await startAdmission({ store, logger: (m) => logLines.push(m) });
		const res = await exchange(b.url, { public_token: 'public-B-shared', ownerUserId: TENANT_B });
		const bodyText = await res.text();

		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});

	it('no credential sentinels when the Plaid exchange itself throws a token-bearing error', async () => {
		// Force itemPublicTokenExchange to throw a message that embeds the token — the scrub must hold.
		const store = makeTwoTenantStore();
		const logLines: string[] = [];
		const plaid = makePlaidClient();
		(plaid.itemPublicTokenExchange as unknown as ReturnType<typeof vi.fn>).mockImplementation(async () => {
			throw new Error(`exchange blew up carrying ${ACCESS_A}`);
		});
		const adapter = new PlaidAdapter(plaid, store.dbFor, (m) => logLines.push(m));
		live = createAdmissionServer({
			sharedSecret: SECRET,
			mintLinkToken: vi.fn(async () => ({ link_token: 'x', expiration: 'y' })),
			admit: (input: ExchangeInput) =>
				adapter.connect({ provider: 'plaid', publicToken: input.publicToken, ownerUserId: input.ownerUserId }),
			logger: (m) => logLines.push(m)
		});
		await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
		const { port } = live!.address() as AddressInfo;
		const res = await exchange(`http://127.0.0.1:${port}`, { public_token: 'public-A-only', ownerUserId: TENANT_A });
		const bodyText = await res.text();

		expect(res.status).toBe(502);
		const haystack = logLines.join('\n') + '\n' + bodyText;
		for (const s of SENTINELS) expect(haystack).not.toContain(s);
	});
});
