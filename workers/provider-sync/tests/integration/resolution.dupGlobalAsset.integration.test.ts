// resolution.dupGlobalAsset.integration.test.ts — QA SC-4: duplicate-global-asset data-quality
// edge, LIVE-DB (slice 3a; exercises resolution.ts cross-provider for the first time). Design
// ref: temp/provider-sync-scheduler-simplefin-design.md §6 (Sec SC-4) + §8 #6.
//
// ── THE EDGE (data-quality, Sec-flagged, NOT security-critical) ─────────────────────────
// resolution.ts resolves a security to a GLOBAL pfin.asset row (users_id NULL), cusip-first
// then symbol, auto-registering on a miss (ON CONFLICT against the 016 symbol / 020 cusip
// partial-unique indexes). A 2nd provider (SimpleFIN) that registers the SAME real security via
// a DIFFERENT identifier than a prior provider can mint a SECOND global row — because a
// symbol-keyed row and a cusip-keyed row for one security do not match each other. This test
// CHARACTERIZES that edge against the real indexes, PROVES dedup DOES work when identifiers
// align (the non-vacuous controls), asserts the edge is BOUNDED (a later both-identifier sync
// converges, does not compound), and asserts the SECURITY invariant is intact (every row is
// GLOBAL users_id NULL — the novel 017 #7 / 019 #11 global-OR-owned fence holds; the dup is a
// correctness/UX edge, not an isolation break).
//
// ── HERMETIC (rolled-back tx; distinctive ZZT_ namespace) ───────────────────────────────
// All resolves run inside ONE service_role transaction that is ROLLED BACK via a sentinel — no
// pfin.asset pollution. resolution's ON CONFLICT/uniqueness is enforced within-tx identically to
// cross-tx, so one rolled-back tx is a faithful AND clean model of a sync run. The ZZT_ symbol /
// ZZ99 cusip namespace guarantees clean misses against any pre-existing global rows.
//
// GATED behind RUN_DB_INTEGRATION=1 — a visible skip when the stack is absent, never a false pass.

import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import type { Sql } from 'postgres';
import { resolveSecurityId, type ResolvableAsset } from '../../src/ingest/resolution.js';
import type { Tx } from '../../src/db/TenantBoundClient.js';
import { rawSql, RUN_DB_INTEGRATION } from './_liveDb.js';

const d = RUN_DB_INTEGRATION ? describe : describe.skip;

// Two synthetic tenants for the isolation-posture probes (jwt sub only — no auth.users seed
// needed; auth.uid() resolves from the claim GUC regardless of an auth.users row).
const TENANT_A = 'c40a0000-0000-4000-8000-0000000000aa';
const TENANT_B = 'c40b0000-0000-4000-8000-0000000000bb';

const asset = (over: Partial<ResolvableAsset>): ResolvableAsset => ({
	symbol: null,
	cusip: null,
	assetType: 'equity',
	name: 'Test Security',
	currency: 'USD',
	...over
});

// Captured inside the rolled-back tx, asserted outside.
interface Captured {
	msgSymbolA: number | null;
	msgSymbolB: number | null; // same symbol twice → must dedup (same id)
	cusipCtrlA: number | null;
	cusipCtrlB: number | null; // same cusip twice → must dedup (same id)
	aaplBySymbol: number | null; // AAPL registered symbol-only
	aaplByCusip: number | null; // "same" AAPL registered cusip-only → THE EDGE (distinct id)
	aaplBoth: number | null; // later sync carrying BOTH → cusip-first convergence (== aaplByCusip)
	ownerRows: { asset_id: number; users_id: string | null }[]; // security invariant probe
}

let db: Sql;
let cap: Captured;

const SENTINEL = Symbol('rollback');

beforeAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	db = rawSql();
	try {
		await db.begin(async (tx) => {
			await tx.unsafe('set local role service_role');
			const t = tx as unknown as Tx;

			// CONTROL 1 — dedup by SYMBOL: two providers key by the SAME symbol 'ZZT_MSFT' (identical
			// casing — resolution matches symbol case-sensitively at the DB layer; the names differ to
			// show the 2nd provider still resolves onto the 1st provider's row).
			const msgSymbolA = await resolveSecurityId(t, asset({ symbol: 'ZZT_MSFT', name: 'Test Msft' }));
			const msgSymbolB = await resolveSecurityId(t, asset({ symbol: 'ZZT_MSFT', name: 'Test Msft (2nd provider)' }));

			// CONTROL 2 — dedup by CUSIP: two providers key by the SAME cusip 'ZZ9990002'.
			const cusipCtrlA = await resolveSecurityId(t, asset({ cusip: 'ZZ9990002', assetType: 'bond', name: 'Test Bond' }));
			const cusipCtrlB = await resolveSecurityId(t, asset({ cusip: 'ZZ9990002', assetType: 'bond', name: 'Test Bond (2nd provider)' }));

			// THE EDGE — same real security 'AAPL', registered symbol-only then cusip-only.
			const aaplBySymbol = await resolveSecurityId(t, asset({ symbol: 'ZZT_AAPL', name: 'Test Apple' }));
			const aaplByCusip = await resolveSecurityId(t, asset({ cusip: 'ZZ9990001', name: 'Test Apple' }));

			// BOUNDEDNESS — a later sync carrying BOTH identifiers resolves cusip-first to the
			// EXISTING cusip row (aaplByCusip), NOT a 3rd row.
			const aaplBoth = await resolveSecurityId(t, asset({ symbol: 'ZZT_AAPL', cusip: 'ZZ9990001', name: 'Test Apple' }));

			// SECURITY INVARIANT probe — every minted row must be GLOBAL (users_id NULL).
			// asset_id may arrive as a string (postgres.js renders bigint as text) — normalize +
			// cast the array param to bigint[] so `= any(...)` matches regardless.
			const ids = [msgSymbolA, cusipCtrlA, aaplBySymbol, aaplByCusip]
				.filter((x): x is number => x !== null)
				.map(String);
			const ownerRows = await t<{ asset_id: number; users_id: string | null }[]>`
				select asset_id, users_id from pfin.asset where asset_id = any(${ids}::bigint[])`;

			cap = { msgSymbolA, msgSymbolB, cusipCtrlA, cusipCtrlB, aaplBySymbol, aaplByCusip, aaplBoth, ownerRows };
			throw SENTINEL; // force ROLLBACK — hermetic, no pfin.asset pollution.
		});
	} catch (e) {
		if (e !== SENTINEL) throw e;
	}
});

afterAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	await db.end();
});

d('SC-4 — cross-provider global-asset resolution (live DB)', () => {
	it('CONTROL: same SYMBOL from two providers dedups to ONE global row', () => {
		expect(cap.msgSymbolA).not.toBeNull();
		expect(cap.msgSymbolB).toBe(cap.msgSymbolA); // symbol-match → same asset_id (no 2nd row)
	});

	it('CONTROL: same CUSIP from two providers dedups to ONE global row', () => {
		expect(cap.cusipCtrlA).not.toBeNull();
		expect(cap.cusipCtrlB).toBe(cap.cusipCtrlA); // cusip-match → same asset_id (no 2nd row)
	});

	it('THE EDGE: same security via symbol-only then cusip-only mints TWO distinct global rows (SC-4)', () => {
		expect(cap.aaplBySymbol).not.toBeNull();
		expect(cap.aaplByCusip).not.toBeNull();
		// The documented duplicate-global-asset data-quality edge: a symbol-keyed row and a
		// cusip-keyed row for the SAME real security do not match each other → 2 global rows.
		expect(cap.aaplByCusip).not.toBe(cap.aaplBySymbol);
	});

	it('BOUNDED: a later both-identifier sync converges cusip-first to the existing row (no 3rd row)', () => {
		// cusip-first resolution finds the cusip row → returns it, does NOT mint a 3rd row.
		expect(cap.aaplBoth).toBe(cap.aaplByCusip);
	});

	it('SECURITY INVARIANT: every auto-registered row is GLOBAL (users_id NULL) — the dup is data-quality, isolation intact', () => {
		expect(cap.ownerRows.length).toBeGreaterThanOrEqual(4);
		for (const row of cap.ownerRows) {
			expect(row.users_id).toBeNull(); // global-only; the 017 #7 / 019 #11 global-OR-owned fence holds
		}
	});
});

// ── SC-4 isolation posture (the "not an isolation breach" claims) ───────────────────────
// The dup is data-quality: the two claims best-homed in a live worker test are (a) global rows
// are SHARED-READ across tenants (016 using(true)) and (b) the register path is service_role-ONLY
// (authenticated cannot mint a global row). The THIRD claim — the novel #7/#11 global-OR-owned
// security_id fence REJECTS a mis-registered asset at reference time — is mechanically OWNED +
// PROVEN by the shipped pgTAP batteries `supabase/tests/rls/017_account_trans_investment_rls.sql`
// (its (a4) LOAD-BEARING leg: a cross-tenant security under service_role — the exact ingest path —
// STILL RAISES 'cross-tenant security rejected%') + `019_holdings_checkpoint_security_fence_rls.sql`
// (#11). Re-deriving that account_trans/holdings fixture here would duplicate those batteries; it is
// cited, not re-implemented (both are green under `supabase test db`).
d('SC-4 — isolation posture: shared-read + service_role-only register (live DB)', () => {
	async function globalAssetCountAs(tenant: string): Promise<number> {
		let n = 0;
		const SENT = Symbol('rb');
		try {
			await db.begin(async (tx) => {
				await tx.unsafe('set local role authenticated');
				await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: tenant, role: 'authenticated' })}, true)`;
				await tx`select set_config('request.jwt.claim.sub', ${tenant}, true)`;
				const r = await tx<{ n: string }[]>`select count(*)::text as n from pfin.asset where users_id is null`;
				n = Number(r[0]!.n);
				throw SENT; // read-only probe — roll back.
			});
		} catch (e) {
			if (e !== SENT) throw e;
		}
		return n;
	}

	it('global assets are SHARED-READ (using(true)) — both tenants see the SAME global set, no boundary crossed', async () => {
		const a = await globalAssetCountAs(TENANT_A);
		const b = await globalAssetCountAs(TENANT_B);
		expect(a).toBeGreaterThan(0); // ≥ the committed 016 global seed (e.g. the USD currency-asset)
		expect(b).toBe(a); // two distinct tenants read the IDENTICAL global set → shared-read, not tenant-scoped
	});

	it('register path is service_role-ONLY — an authenticated INSERT of a GLOBAL (users_id NULL) asset is REJECTED', async () => {
		let err: unknown;
		try {
			await db.begin(async (tx) => {
				await tx.unsafe('set local role authenticated');
				await tx`select set_config('request.jwt.claims', ${JSON.stringify({ sub: TENANT_A, role: 'authenticated' })}, true)`;
				await tx`select set_config('request.jwt.claim.sub', ${TENANT_A}, true)`;
				// 016 asset_insert WITH CHECK (users_id = auth.uid()) → a NULL (global) users_id fails
				// closed: a client cannot mint the shared/global rows resolution.ts registers.
				await tx`insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
					values (null, 'equity', 'market_feed', 'ZZT_DENY', 'client-forged global', 'USD')`;
			});
		} catch (e) {
			err = e;
		}
		expect(err).toBeDefined(); // the write is rejected (RLS WITH CHECK / policy) — no client-minted global row
		expect(String((err as Error).message)).toMatch(/policy|row-level|permission|violat|check/i);
	});
});
