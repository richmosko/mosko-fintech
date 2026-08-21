// nonReAllocation.tenant-isolation.server.test.ts — SELF-238 AC9 (QA gate), ratified text
// verbatim: "QA two-tenant assertion at this read path: tenant B's render contains zero of
// tenant A's values (INVOKER RLS composition; no service_role anywhere in the path)."
//
// ⚠ WHY THIS IS A DIFFERENT TEST CLASS FROM EVERY OTHER *.test.ts / *.io.test.ts IN THIS DIR.
//   nonReAllocation.io.test.ts (Backend's own I/O-wiring coverage) mocks the Supabase client —
//   every `vi.fn()` returns canned data regardless of any tenant scoping. That is the right tool
//   for proving the wiring reaches the right calls with the right shapes, and it is the WRONG
//   tool for AC9: a mock cannot fail closed, because it never enforces RLS in the first place —
//   "isolation" would be assumed away, not proven. `computeNonReAllocation` (the pure merge core)
//   is unit-tested elsewhere with synthetic single-tenant inputs, but it has NO tenant concept at
//   all — it just processes whatever rows you hand it, so it cannot answer a cross-tenant
//   question either. The property AC9 asks for — real RLS-scoped reads, composed through the
//   REAL `loadNonReAllocation`/`loadSubcatMarketValueAndTargets`, merged by the REAL TS code, with
//   TWO SEPARATE real tenant sessions — can only be exercised end-to-end against a live
//   Postgres+PostgREST backend with RLS actually enabled. This file does that. It is new
//   infrastructure for this codebase (see VENUE below) — flagged as a judgment call at hand-off,
//   not silently introduced as if it were the established pattern.
//
// WHAT THIS PROVES THAT A DB-LAYER (pgTAP) TEST CANNOT: `fn_subcat_market_value` (076),
// `pfin.planning_target` (074) and `pfin.user_taxonomy` (009) all already carry their OWN
// thorough two-tenant pgTAP isolation batteries (076/074/009's own I*/R2/1b legs) — that ground
// is NOT re-proven here, on purpose, to avoid duplicating an already-closed question. What is
// NEW here, and untouched by any of those three batteries, is the TS-side composition:
// `loadNonReAllocation` reads THREE independently-RLS'd sources through one per-request client
// and merges them with `computeNonReAllocation` — two Maps merged in one process, which is
// exactly where a leak would be invisible to RLS (team-lead's framing, and the reason this file
// exists). The collapsed "US - Sector Diversified" row is the sharpest case: it has no
// `sub_cat_id` at all and is entirely TS-computed (`usEquityTaxonomyRows.reduce(...)`) — a
// merge-layer bug there could leak a value with no underlying DB row to audit against. This file
// asserts it specifically (see the SHARPEST-CASE block below).
//
// "NO service_role ANYWHERE IN THE PATH" — two complementary proofs, neither alone sufficient:
//   (1) STRUCTURAL (by construction, not re-asserted per-test): this file's ONLY Supabase client
//       constructor is `makeClientFor(tenantUuid)` below, which mints an `authenticated`-role JWT
//       and nothing else — there is no service_role key anywhere in this file to leak. Combined
//       with `nonReAllocation.ts` / `subcatMarketValue.ts` themselves containing no reference to
//       the service-role key env var (confirmed by inspection while drafting this file —
//       surfaced to Backend/Sec at hand-off, not re-derived here every run).
//   (2) BEHAVIOURAL: every read below succeeds under an `authenticated`-role JWT alone — if the
//       module secretly needed service_role for any of its three reads, an anon/authenticated-only
//       venue (exactly what this harness provides — the throwaway PostgREST's DB connection
//       itself is unprivileged for RLS purposes; role-switching is per-JWT, never escalated) would
//        401/403 rather than return data.
//
// ⚠ VENUE (read before running). Targets a live Postgres+PostgREST pair via TWO env vars:
//   QA_SELF238_POSTGREST_URL — base URL of a PostgREST instance whose PGRST_DB_SCHEMAS includes
//     `pfin`, pointed at a DB with the FULL migration chain applied (needs 076/074/009 at least).
//     MUST be reachable WITHOUT the Supabase-gateway `/rest/v1` prefix supabase-js's high-level
//     `createClient()` hardcodes onto every request — if fronting bare PostgREST (not Kong), put
//     a `/rest/v1`-stripping reverse proxy in front of it (this is what the throwaway venue this
//     file was authored/verified against uses; see the hand-off report for the exact shape).
//   QA_SELF238_JWT_SECRET — the HS256 secret that PostgREST instance's PGRST_JWT_SECRET was
//     configured with, so this file can mint valid per-tenant JWTs (`jose`, already a
//     dependency).
//   BOTH ABSENT -> the whole suite SKIPS (does not fail) — this is a deliberate choice, not an
//   oversight: db-tests.yml (pgTAP CI) has no PostgREST leg today, and standing one up for CI is
//   a DevOps decision (CI workflow ownership), not something authored here. Skips loudly with a
//   console note so a silent-always-skip in CI is visible if anyone goes looking.
//
// REQUIRED FIXTURE (not seeded by this file — seeding requires privilege this file's client
// deliberately never holds, see the service_role proof above). Run once against the target venue
// before this suite, via a privileged (role=postgres) connection — SQL provided at hand-off, not
// duplicated here to avoid a second copy that can drift from what was actually run. Shape: TWO
// tenants (auth.users), each with distinct pfin.user_taxonomy / holdings / planning_target rows,
// at least one tenant (`TENANT_A_ID`) holding a Sub-Cat inside `US_EQUITY_SUB_CAT_SET` (see
// usEquitySubCats.ts) so the collapsed-row sharpest-case check below is non-vacuous.
//
// ⚠ SEED RISK, FLAGGED AT SELF-239 HAND-OFF (2026-08-20), NOT YET RE-VERIFIED AGAINST A LIVE
// VENUE — this venue has not been stood up in any session that also carries the SELF-239 rework,
// so the risk below is unconfirmed either way; check it the next time this fixture is actually
// seeded. The REQUIRED FIXTURE above and the "non-vacuous: both tenants have REAL nonzero Non-RE
// totals" test below were both written PRE-SELF-239, when `total_non_re` still summed every 076
// row unfiltered (Liabilities-cat holdings included). SELF-239 moved `total_non_re` onto the
// element='asset' predicate (nonReAllocation.ts's `assetSubCatIds`) — Liabilities-cat holdings no
// longer contribute to it at all. If either tenant's privileged seed SQL relied on
// Liabilities-cat holdings (e.g. `081`'s liability cash route) to make that tenant's total
// genuinely nonzero, the non-vacuous precondition test can now read as VACUOUS (total_non_re
// silently drops to 0, and the test's own `toBeGreaterThan(0)` assertion starts FAILING loudly —
// not a silent pass, but a surprising one to debug without this note) or, if the asset-side
// holdings alone still net positive, simply SMALLER than whoever wrote the seed expected.
// ACTION: when this venue is next stood up, re-run the seed SQL, confirm both tenants' totals are
// still genuinely positive from ASSET-element holdings alone, and adjust the seed (not this file)
// if not — the fixture's job is to be non-vacuous, and asset-element holdings are now the only
// thing that can make it so.

import { describe, it, expect, beforeAll } from 'vitest';
import { SignJWT } from 'jose';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { loadNonReAllocation, type NonReAllocation } from './nonReAllocation';
import { EMPTY_STALE_LINKED_SOURCE_IDS } from './navComposition';
import { unsafeAsOfForTest } from '$lib/server/time/asOf';

const POSTGREST_URL = process.env.QA_SELF238_POSTGREST_URL;
const JWT_SECRET = process.env.QA_SELF238_JWT_SECRET;
const VENUE_AVAILABLE = Boolean(POSTGREST_URL && JWT_SECRET);

// Fixed synthetic tenant UUIDs (raw literals, suffixed '238' — the pgTAP battery convention,
// reused here for the same reason: deterministic, diffable, obviously synthetic). MUST match
// whichever fixture SQL was run against the target venue.
const TENANT_A_ID = '00000000-0000-0000-0000-00000000a238';
const TENANT_B_ID = '00000000-0000-0000-0000-00000000b238';
const AS_OF = unsafeAsOfForTest('2026-08-10');

async function makeClientFor(tenantUuid: string): Promise<SupabaseClient> {
	// The ONLY JWT this file ever mints: role:'authenticated', nothing else. No service_role
	// anywhere in this constructor — see the header's structural proof.
	const secret = new TextEncoder().encode(JWT_SECRET!);
	const jwt = await new SignJWT({ sub: tenantUuid, role: 'authenticated' })
		.setProtectedHeader({ alg: 'HS256' })
		.setIssuedAt()
		.setExpirationTime('10m')
		.sign(secret);
	return createClient(POSTGREST_URL!, 'unused-anon-key-bare-postgrest-does-not-check-it', {
		global: { headers: { Authorization: `Bearer ${jwt}` } }
	});
}

/** Flatten every FINANCIAL VALUE a render exposes, for a blunt but genuinely comprehensive
 *  "contains none of" check — deliberately broader than spot-checking a couple of expected
 *  fields, so a leak in a field this test's author didn't think to name specifically still gets
 *  caught. Deliberately EXCLUDES `cat` / `sub_cat` label text and `kind`: those are shared
 *  TAXONOMY VOCABULARY, not tenant secrets — both tenants legitimately having a "Cash/CD" row or
 *  a "US - Sector Diversified" collapsed row is the CORRECT, expected outcome, not a leak, and
 *  checking for it as if it were one produces a false positive on every shared Sub-Cat name
 *  (measured while drafting this file: an early version flagged "Cash","CD" as "leaked" between
 *  two tenants who both simply hold a Cash/CD Sub-Cat — the fix is scoping to VALUES, not labels;
 *  `sub_cat_id` — the real tenant-scoped identity — is checked separately below). */
function allValues(render: NonReAllocation): number[] {
	const out: number[] = [render.total_non_re];
	const pushRow = (r: NonReAllocation['groups'][number]['rows'][number] | null) => {
		if (!r) return;
		out.push(r.dollar_alloc);
		// SELF-239: pct_alloc is `number | null` now (AC6 — null when TotalNonRE <= 0), not always
		// a number. Mechanical type-compat fix only, at SELF-239 hand-off — QA owns this file and
		// this fixture's total_non_re shape (which SELF-239 also changed: it now excludes any
		// liability-element row 076 returns); flagged for QA review, not otherwise touched here.
		if (r.pct_alloc !== null) out.push(r.pct_alloc);
		if (r.pct_target !== null) out.push(r.pct_target);
		if (r.dollar_target !== null) out.push(r.dollar_target);
		if (r.dollar_realloc !== null) out.push(r.dollar_realloc);
	};
	for (const g of render.groups) for (const r of g.rows) pushRow(r);
	pushRow(render.unsorted);
	return out;
}

describe.skipIf(!VENUE_AVAILABLE)(
	'loadNonReAllocation — AC9 two-tenant isolation (real RLS, real PostgREST, no service_role)',
	() => {
		let renderA: NonReAllocation;
		let renderB: NonReAllocation;

		beforeAll(async () => {
			const clientA = await makeClientFor(TENANT_A_ID);
			const clientB = await makeClientFor(TENANT_B_ID);
			const resultA = await loadNonReAllocation(clientA, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
			const resultB = await loadNonReAllocation(clientB, AS_OF, EMPTY_STALE_LINKED_SOURCE_IDS);
			if (!resultA.ok || !resultA.data) {
				throw new Error(
					`fixture/venue problem: tenant A's load failed (ok=${resultA.ok}) — check the required fixture SQL ran and QA_SELF238_POSTGREST_URL points at the right DB, before doubting this test`
				);
			}
			if (!resultB.ok || !resultB.data) {
				throw new Error(`fixture/venue problem: tenant B's load failed (ok=${resultB.ok})`);
			}
			renderA = resultA.data;
			renderB = resultB.data;
		});

		it('non-vacuous: both tenants have REAL nonzero Non-RE totals (the isolation check below is a boundary denial against real value, not an empty venue)', () => {
			expect(renderA.total_non_re).toBeGreaterThan(0);
			expect(renderB.total_non_re).toBeGreaterThan(0);
			expect(renderA.total_non_re).not.toBe(renderB.total_non_re);
		});

		it('(AC9) tenant B\'s render contains ZERO of tenant A\'s values', () => {
			const aValues = new Set(allValues(renderA));
			const bValues = allValues(renderB);
			const leaked = bValues.filter((v) => aValues.has(v));
			expect(leaked, `B's render exposed values that only exist in A's: ${JSON.stringify(leaked)}`).toEqual([]);
		});

		it('(AC9, reverse direction) tenant A\'s render contains ZERO of tenant B\'s values', () => {
			const bValues = new Set(allValues(renderB));
			const aValues = allValues(renderA);
			const leaked = aValues.filter((v) => bValues.has(v));
			expect(leaked, `A's render exposed values that only exist in B's: ${JSON.stringify(leaked)}`).toEqual([]);
		});

		it('A\'s own sub_cat_id values never appear anywhere in B\'s render (structural, not just value-level)', () => {
			const aSubCatIds = new Set(
				renderA.groups.flatMap((g) => g.rows.map((r) => r.sub_cat_id).filter((id): id is number => id !== null))
			);
			const bSubCatIds = renderB.groups.flatMap((g) =>
				g.rows.map((r) => r.sub_cat_id).filter((id): id is number => id !== null)
			);
			const leaked = bSubCatIds.filter((id) => aSubCatIds.has(id));
			expect(leaked).toEqual([]);
		});

		it('SHARPEST CASE — the TS-computed "US - Sector Diversified" row (no sub_cat_id, no DB row to audit against): B\'s collapsed row carries ZERO, not A\'s value, when B holds none of the twelve US-equity Sub-Cats', () => {
			const collapsedA = renderA.groups
				.find((g) => g.cat === 'Marketable Securities')
				?.rows.find((r) => r.kind === 'us_sector_diversified');
			const collapsedB = renderB.groups
				.find((g) => g.cat === 'Marketable Securities')
				?.rows.find((r) => r.kind === 'us_sector_diversified');
			expect(collapsedA, 'fixture problem: tenant A must hold a US-equity Sub-Cat for this leg to be non-vacuous').toBeDefined();
			expect(collapsedB).toBeDefined();
			// A's fixture is expected to hold real value here (else this leg is vacuous); B's must
			// be exactly zero — not merely "not equal to A's", which a coincidental collision could
			// pass — B genuinely holds none of the twelve, so its collapsed row IS zero by contract.
			expect(collapsedA!.dollar_alloc).toBeGreaterThan(0);
			expect(collapsedB!.dollar_alloc).toBe(0);
			expect(collapsedB!.pct_target).toBe(0);
			expect(collapsedB!.dollar_alloc).not.toBe(collapsedA!.dollar_alloc);
		});
	}
);

if (!VENUE_AVAILABLE) {
	// eslint-disable-next-line no-console
	console.log(
		'[nonReAllocation.tenant-isolation] SKIPPED — QA_SELF238_POSTGREST_URL / QA_SELF238_JWT_SECRET not set. ' +
			'This is expected in the default CI Vitest run (no PostgREST leg today); see the file header before adding one.'
	);
}
