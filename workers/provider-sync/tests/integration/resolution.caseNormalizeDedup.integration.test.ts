// resolution.caseNormalizeDedup.integration.test.ts — QA SC-4 case-normalize CLOSURE, LIVE-DB
// (slice 3b). Sibling to resolution.dupGlobalAsset.integration.test.ts (3a), which
// CHARACTERIZED the cross-provider duplicate-global-asset edge as OPEN. Design ref:
// temp/provider-sync-scheduler-design.md (Flag-2 case-normalize) + resolution.ts §Flag-2.
//
// ── THE VECTOR THIS CLOSES ──────────────────────────────────────────────────────────────
// The 3a SC-4 test proved that a symbol-keyed row and a cusip-keyed row for the same security
// do not match (a real, bounded edge). It ALSO left a NARROWER dup vector explicitly open: the
// SAME identifier surfaced by two providers in DIFFERENT CASE — Plaid `voo` vs SimpleFIN `VOO`
// (or a cusip case-variant) — would key two DISTINCT global rows, because the DB match was
// case-sensitive. The Flag-2 fix canonicalizes symbol + cusip to `.trim().toUpperCase()` at
// BOTH the resolve SELECTs AND the auto-register INSERT stored value (resolution.ts). This test
// PROVES, against the REAL 016 (symbol) / 020 (cusip) partial-unique indexes, that case variants
// now converge to ONE global pfin.asset row storing the canonical (uppercase) value — closing
// the vector the 3a test characterized. The resolutionCaseNormalize.test.ts unit test proves the
// bound VALUES are uppercased; THIS test proves the end-to-end DEDUP against the live indexes.
//
// ── HERMETIC (rolled-back tx; distinctive ZZN_ namespace) ───────────────────────────────
// All resolves run inside ONE service_role transaction ROLLED BACK via a sentinel — no
// pfin.asset pollution. resolution's ON CONFLICT / partial-unique is enforced within-tx
// identically to cross-tx, so one rolled-back tx faithfully models a sync run. The ZZN_ symbol /
// ZZN cusip namespace guarantees clean misses against any pre-existing global rows.
//
// GATED behind RUN_DB_INTEGRATION=1 — a visible skip when the stack is absent, never a false pass.

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Sql } from 'postgres';
import { resolveSecurityId, type ResolvableAsset } from '../../src/ingest/resolution.js';
import type { Tx } from '../../src/db/TenantBoundClient.js';
import { rawSql, RUN_DB_INTEGRATION } from './_liveDb.js';

const d = RUN_DB_INTEGRATION ? describe : describe.skip;

const asset = (over: Partial<ResolvableAsset>): ResolvableAsset => ({
	symbol: null,
	cusip: null,
	assetType: 'etf',
	name: 'Case-Normalize Test',
	currency: 'USD',
	...over
});

interface Captured {
	vooLower: number | null; // symbol registered via lowercase 'zzn_voo'
	vooUpper: number | null; // same symbol via 'ZZN_VOO' → MUST equal vooLower (converge)
	vooMixed: number | null; // ' ZzN_Voo ' (padded mixed case) → MUST equal vooLower
	symbolRows: { asset_id: number; symbol: string | null }[]; // exactly ONE row; canonical uppercase
	cusipLower: number | null; // cusip registered via lowercase 'zzn99aa1'
	cusipUpper: number | null; // 'ZZN99AA1' → MUST equal cusipLower (converge)
	cusipRows: { asset_id: number; cusip: string | null }[]; // exactly ONE row; canonical uppercase
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

			// SYMBOL case-dedup — lowercase, then uppercase, then padded-mixed. All three must
			// resolve/register to ONE global row (the Flag-2 fix uppercases at resolve + register).
			const vooLower = await resolveSecurityId(t, asset({ symbol: 'zzn_voo', name: 'Vanguard (plaid)' }));
			const vooUpper = await resolveSecurityId(t, asset({ symbol: 'ZZN_VOO', name: 'Vanguard (simplefin)' }));
			const vooMixed = await resolveSecurityId(t, asset({ symbol: '  ZzN_Voo  ', name: 'Vanguard (padded)' }));

			// The stored value is CANONICAL uppercase, and there is exactly ONE global row for it
			// (no lowercase sibling). Probe by exact uppercase match — a lowercase row would NOT
			// match, so length 1 + symbol='ZZN_VOO' proves both "one row" and "uppercase stored".
			const symbolRows = await t<{ asset_id: number; symbol: string | null }[]>`
				select asset_id, symbol from pfin.asset where users_id is null and symbol = 'ZZN_VOO'`;

			// CUSIP case-dedup — cusip-only asset (symbol null); lowercase then uppercase converge.
			const cusipLower = await resolveSecurityId(t, asset({ cusip: 'zzn99aa1', assetType: 'bond', name: 'Bond (plaid)' }));
			const cusipUpper = await resolveSecurityId(t, asset({ cusip: 'ZZN99AA1', assetType: 'bond', name: 'Bond (simplefin)' }));
			const cusipRows = await t<{ asset_id: number; cusip: string | null }[]>`
				select asset_id, cusip from pfin.asset where users_id is null and cusip = 'ZZN99AA1'`;

			cap = { vooLower, vooUpper, vooMixed, symbolRows, cusipLower, cusipUpper, cusipRows };
			throw SENTINEL; // ROLLBACK — hermetic, no pfin.asset pollution.
		});
	} catch (e) {
		if (e !== SENTINEL) throw e;
	}
});

afterAll(async () => {
	if (!RUN_DB_INTEGRATION) return;
	await db.end();
});

d('SC-4 closure — cross-provider case-variant dedup (live DB)', () => {
	it('SYMBOL: lowercase, uppercase, and padded-mixed all converge to ONE global asset_id', () => {
		expect(cap.vooLower).not.toBeNull();
		expect(cap.vooUpper).toBe(cap.vooLower); // voo === VOO → same row (vector closed)
		expect(cap.vooMixed).toBe(cap.vooLower); // '  ZzN_Voo  ' trims+uppercases → same row
	});

	it('SYMBOL: exactly ONE global row exists, storing the canonical UPPERCASE symbol', () => {
		expect(cap.symbolRows).toHaveLength(1); // no lowercase sibling was minted
		expect(cap.symbolRows[0]!.symbol).toBe('ZZN_VOO'); // canonical stored value
		expect(cap.symbolRows[0]!.asset_id).toBe(cap.vooLower); // the row the resolves returned
	});

	it('CUSIP: lowercase and uppercase variants converge to ONE global asset_id', () => {
		expect(cap.cusipLower).not.toBeNull();
		expect(cap.cusipUpper).toBe(cap.cusipLower); // zzn99aa1 === ZZN99AA1 → same row
	});

	it('CUSIP: exactly ONE global row exists, storing the canonical UPPERCASE cusip', () => {
		expect(cap.cusipRows).toHaveLength(1);
		expect(cap.cusipRows[0]!.cusip).toBe('ZZN99AA1');
		expect(cap.cusipRows[0]!.asset_id).toBe(cap.cusipLower);
	});
});
