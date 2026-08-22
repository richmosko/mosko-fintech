// assetResolveWireFormat.test.ts — the SELF-325 /asset/resolve wire-format contract, end to end.
//
// WHY THIS FILE EXISTS (QA freeze-break, team-lead's requirement): the bug that shipped was
// "both sides green against mocks of each other" — admissionServer.test.ts mocked `resolveAsset`
// to return `{ assetId: 501 }` (a JS number), and the app's admissionClient.test.ts mocked the
// worker's JSON response the same way. Neither mock was wrong about the TYPE resolveSecurityId
// was DECLARED to return; both were wrong about what postgres.js ACTUALLY returns for a bigint
// column (a string), and no test exercised the real boundary where that mismatch lives.
//
// This file closes that gap by testing the REAL PIPELINE with only the DB TRANSPORT faked (the
// one seam that genuinely cannot run in a unit test without a live Postgres): the real
// resolveSecurityId (workers/provider-sync/src/ingest/resolution.ts, UNMOCKED), the real
// productionAssetResolveDeps, and the real HTTP server from createAdmissionServer, driven by a
// fake tx that returns `asset_id` as a STRING — matching postgres.js's actual runtime behavior,
// not the aspirational `number` type on resolveSecurityId's signature. It reads the RAW response
// TEXT (not `res.json()`, which parses either shape silently) to prove the bytes on the wire are
// string-typed, and it parses those exact bytes through the APP-SIDE schema
// (api/src/lib/server/asset/admissionClient.ts's workerResolveResponseSchema) to prove the two
// packages actually agree about what's on the wire — a genuine cross-package contract check, not
// two independently-plausible mocks.

import { describe, it, expect, afterEach, vi } from 'vitest';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { z } from 'zod';
import type { Tx } from '../src/db/TenantBoundClient.js';
import type { WorkerConfig } from '../src/config/env.js';
import { ADMISSION_SECRET_HEADER } from '../src/http/sharedSecret.js';

const SECRET = 'test-shared-secret-0123456789abcdef0123456789abcdef';
const UUID = '11111111-1111-4111-8111-111111111111';

// The SAME schema api/src/lib/server/asset/admissionClient.ts validates the worker's response
// against — duplicated here (not imported: that module lives in the api/ package, a different
// npm workspace this worker package does not depend on) so this test proves what THAT schema
// requires, not what THIS package's own types claim. If the two ever diverge, update both
// sides deliberately — see that file's `workerResolveResponseSchema`.
const appSideResponseSchema = z.object({ assetId: z.string().regex(/^\d+$/).nullable() });

/** A fake postgres.js tagged-template tx: returns `asset_id` as a STRING on the symbol-resolve
 *  SELECT, mirroring postgres.js's real behavior for a bigint column (no `bigint` type override
 *  configured anywhere in this worker — see assetResolve.ts's AssetResolveResult comment). */
function fakeTxReturningStringBigint(assetId: string): Tx {
	let call = 0;
	const tagged = (_strings: TemplateStringsArray, ..._vals: unknown[]) => {
		call += 1;
		// Query 1 (cusip present) or the fallback symbol query — either way, the resolve hit
		// returns a row shaped exactly like a real driver result: asset_id as a decimal STRING.
		return Promise.resolve(call === 1 ? [{ asset_id: assetId }] : []);
	};
	return tagged as unknown as Tx;
}

// Fake ONLY the DB transport (TenantBoundClient) — resolveSecurityId itself is NOT mocked.
const withServiceRoleImpl = vi.fn(async (fn: (tx: Tx) => unknown) => fn(fakeTxReturningStringBigint('1683')));
const endMock = vi.fn(async () => undefined);
vi.mock('../src/db/TenantBoundClient.js', () => ({
	TenantBoundClient: {
		forTenant: () => ({ withServiceRole: withServiceRoleImpl, end: endMock })
	}
}));

let live: Server | undefined;
afterEach(async () => {
	if (live) await new Promise<void>((r) => live!.close(() => r()));
	live = undefined;
	vi.clearAllMocks();
});

describe('POST /asset/resolve — real pipeline, only DB transport faked', () => {
	it('the raw wire bytes are a quoted decimal string ("assetId":"1683"), not a bare number', async () => {
		const { productionAssetResolveDeps } = await import('../src/http/assetResolve.js');
		const { createAdmissionServer } = await import('../src/http/admissionServer.js');

		const resolveDeps = productionAssetResolveDeps({} as WorkerConfig);
		live = createAdmissionServer({
			sharedSecret: SECRET,
			mintLinkToken: vi.fn(),
			admit: vi.fn(),
			admitSimplefin: vi.fn(),
			reauthStart: vi.fn(),
			reauthComplete: vi.fn(),
			fetchWebhookVerificationKey: vi.fn(),
			syncSource: vi.fn(),
			manualSync: vi.fn(),
			resolveAsset: (input) => resolveDeps.resolve(input)
		});
		await new Promise<void>((r) => live!.listen(0, '127.0.0.1', () => r()));
		const { port } = live!.address() as AddressInfo;

		const res = await fetch(`http://127.0.0.1:${port}/asset/resolve`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', [ADMISSION_SECRET_HEADER]: SECRET },
			body: JSON.stringify({
				ownerUserId: UUID,
				symbol: 'AAPL',
				cusip: null,
				assetType: 'equity',
				name: 'Apple Inc',
				currency: 'USD'
			})
		});
		expect(res.status).toBe(200);

		const rawText = await res.text();
		// THE ASSERTION THAT WOULD HAVE CAUGHT THE SHIPPED BUG: a bare-number wire format
		// (`"assetId":1683`) would fail this and pass a `res.json()`-then-`toEqual` check just
		// fine, because JSON.parse doesn't distinguish "was quoted" once it hands you a value.
		expect(rawText).toContain('"assetId":"1683"');
		expect(rawText).not.toMatch(/"assetId":1683\b/);

		// CROSS-PACKAGE CONTRACT: the exact bytes the worker produced parse against the SAME
		// schema api/src/lib/server/asset/admissionClient.ts validates them with.
		const parsed = appSideResponseSchema.safeParse(JSON.parse(rawText));
		expect(parsed.success).toBe(true);
		if (parsed.success) expect(parsed.data.assetId).toBe('1683');
	});
});
