// assetResolveWireFormat.test.ts — SELF-325 round 10 boundary-crossing watcher (Sec-mandated).
//
// WHY THIS FILE EXISTS: the freeze-break bug (QA-found) shipped with BOTH sides green —
// assetResolve.test.ts mocks resolveSecurityId to return a plain JS `number` literal (hiding
// postgres.js's real bigint-as-string behavior), and admissionClient.test.ts mocks the worker's
// HTTP response with a hand-written `{ assetId: 501 }` fixture (hiding whatever the real
// JSON.stringify of the real response object actually produces). Neither leg's mock could ever
// disagree with itself, so neither could catch the bug. Sec's explicit requirement (SELF-325
// round 10 joint review): "a test that crosses the REAL serialization boundary ... a value from
// the actual driver, JSON.stringify'd, parsed by the actual app schema. A test asserting a
// hand-written {assetId: 123} fixture reproduces the exact blindness that shipped."
//
// WHAT THIS TEST ACTUALLY EXERCISES, UNMOCKED, END TO END:
//   1. The REAL resolveSecurityId (../src/ingest/resolution.js) — not stubbed.
//   2. The REAL productionAssetResolveDeps Number() coercion (../src/http/assetResolve.js).
//   3. The REAL createAdmissionServer HTTP route + JSON.stringify wire serialization
//      (../src/http/admissionServer.js), driven over an actual loopback HTTP connection —
//      not an in-process function call, so nothing skips JSON.stringify/JSON.parse.
// ONLY the Postgres transaction (`tx`) is faked — and it is faked to return `asset_id` as a
// STRING ('1683'), because that is what postgres.js actually hands back for a bigint column
// (016: pfin.asset.asset_id is bigint) at runtime, regardless of resolveSecurityId's
// `Promise<{asset_id: number}[]>` annotation. This reproduces the EXACT shape that broke
// production — resolveSecurityId's TS type was always aspirational, never a runtime guarantee.
//
// ASSERTION STRENGTH: this checks the RAW response TEXT for an unquoted number
// (`"assetId":1683`) and explicitly asserts the quoted-string form (`"assetId":"1683"` — the
// shape that shipped broken) is ABSENT. A raw-byte check is strictly stronger than a schema
// check: any Zod number schema treats `1683` and `"1683"` differently by construction, so a
// byte-level assertion cannot be satisfied by coincidence the way a loosely-typed schema check
// could. A second assertion below also parses the response through a schema shaped exactly like
// admissionClient.ts's `workerResolveResponseSchema` (duplicated here, not imported — the app and
// worker are separate packages with no cross-package dependency; see that module for the
// authoritative copy) to prove the wire format is what the REAL app-side strict `z.number()`
// schema — no coercion — accepts.

import { describe, it, expect, vi, afterEach } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { z } from 'zod';
import { createAdmissionServer, type AdmissionServerDeps } from '../src/http/admissionServer.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';
import type { WorkerConfig } from '../src/config/env.js';

// NOTE: productionAssetResolveDeps is deliberately NOT statically imported here — each test
// below calls `vi.doMock('../src/db/TenantBoundClient.js', ...)` THEN dynamically
// `await import('../src/http/assetResolve.js')`, so the module graph picks up the per-test fake
// tx. A static top-level import would resolve (and cache) against the UNMOCKED TenantBoundClient
// before any test runs, defeating the per-test fake.

const SECRET = 'test-shared-secret-0123456789abcdef0123456789abcdef';
const UUID = '11111111-1111-4111-8111-111111111111';
const CONFIG = {} as WorkerConfig;

// Mirrors admissionClient.ts's workerResolveResponseSchema EXACTLY (strict, no coercion) — the
// real app-side contract this wire format must satisfy. Kept in sync by hand; if that schema
// changes, this copy must change with it (same discipline as any cross-package contract test).
const appSideResolveResponseSchema = z.object({
	assetId: z.number().int().positive().nullable()
});

let live: Server | undefined;
afterEach(async () => {
	if (live) await new Promise<void>((r) => live!.close(() => r()));
	live = undefined;
	vi.restoreAllMocks();
});

/**
 * A fake postgres.js tagged-template `tx` — the ONLY faked collaborator. Returns `asset_id` as a
 * STRING, exactly like the real driver does for a bigint column (016). resolveSecurityId itself
 * (../src/ingest/resolution.js) runs FOR REAL against this fake, unmodified.
 */
function makeFakeTx(assetIdAsString: string) {
	return vi.fn(async () => [{ asset_id: assetIdAsString }]);
}

describe('SELF-325 round 10 — real serialization boundary (worker driver → HTTP wire)', () => {
	it('a bigint asset_id returned as a STRING by the (faked) driver reaches the wire as an UNQUOTED JSON number, never a quoted string', async () => {
		vi.resetModules(); // force a fresh module graph so this test's doMock isn't shadowed by a
		// previous test's cached import of assetResolve.js (each test fakes a different tx).
		const fakeTx = makeFakeTx('1683');
		vi.doMock('../src/db/TenantBoundClient.js', () => ({
			TenantBoundClient: {
				forTenant: () => ({
					withServiceRole: async (fn: (tx: unknown) => unknown) => fn(fakeTx),
					end: async () => undefined
				})
			}
		}));
		const { productionAssetResolveDeps: freshDeps } = await import('../src/http/assetResolve.js');
		const resolveDeps = freshDeps(CONFIG);

		const deps: AdmissionServerDeps = {
			sharedSecret: SECRET,
			mintLinkToken: vi.fn(),
			admit: vi.fn(),
			admitSimplefin: vi.fn(),
			reauthStart: vi.fn(),
			reauthComplete: vi.fn(),
			fetchWebhookVerificationKey: vi.fn(),
			syncSource: vi.fn(),
			manualSync: vi.fn(),
			resolveAsset: resolveDeps.resolve
		} as unknown as AdmissionServerDeps;

		live = createAdmissionServer(deps);
		await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
		const { port } = live!.address() as AddressInfo;
		const url = `http://127.0.0.1:${port}`;

		const res = await fetch(`${url}/asset/resolve`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', [ADMISSION_SECRET_HEADER]: SECRET },
			body: JSON.stringify({
				ownerUserId: UUID,
				symbol: 'AAPL',
				cusip: null,
				assetType: 'equity',
				name: null,
				currency: 'USD'
			})
		});
		expect(res.status).toBe(200);

		const rawText = await res.text();
		// THE ASSERTION THAT WOULD HAVE CAUGHT THE FREEZE-BREAK BUG: a bare, unquoted number.
		expect(rawText).toContain('"assetId":1683');
		// THE ASSERTION THAT PROVES THE OLD (BROKEN) SHAPE IS GONE: never a quoted digit string.
		expect(rawText).not.toMatch(/"assetId":"1683"/);

		// Independently, the REAL app-side contract (a strict z.number(), no coercion) accepts it.
		const parsed = appSideResolveResponseSchema.safeParse(JSON.parse(rawText));
		expect(parsed.success).toBe(true);
		if (parsed.success) expect(parsed.data.assetId).toBe(1683);
	});

	it('inversion control: a driver that returns asset_id as a NUMBER (not a string) still round-trips correctly — the fix does not depend on the input already being wrong', async () => {
		vi.resetModules();
		const fakeTx = vi.fn(async () => [{ asset_id: 9001 }]);
		vi.doMock('../src/db/TenantBoundClient.js', () => ({
			TenantBoundClient: {
				forTenant: () => ({
					withServiceRole: async (fn: (tx: unknown) => unknown) => fn(fakeTx),
					end: async () => undefined
				})
			}
		}));
		const { productionAssetResolveDeps: freshDeps } = await import('../src/http/assetResolve.js');
		const resolveDeps = freshDeps(CONFIG);

		const deps: AdmissionServerDeps = {
			sharedSecret: SECRET,
			mintLinkToken: vi.fn(),
			admit: vi.fn(),
			admitSimplefin: vi.fn(),
			reauthStart: vi.fn(),
			reauthComplete: vi.fn(),
			fetchWebhookVerificationKey: vi.fn(),
			syncSource: vi.fn(),
			manualSync: vi.fn(),
			resolveAsset: resolveDeps.resolve
		} as unknown as AdmissionServerDeps;

		live = createAdmissionServer(deps);
		await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
		const { port } = live!.address() as AddressInfo;
		const url = `http://127.0.0.1:${port}`;

		const res = await fetch(`${url}/asset/resolve`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', [ADMISSION_SECRET_HEADER]: SECRET },
			body: JSON.stringify({
				ownerUserId: UUID,
				symbol: 'VOO',
				cusip: null,
				assetType: 'etf',
				name: null,
				currency: 'USD'
			})
		});
		const rawText = await res.text();
		expect(rawText).toContain('"assetId":9001');
	});
});
