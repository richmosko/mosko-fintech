// nonReAllocation.catGroupOrderEquality.server.test.ts — ADR-058 Decision 7's paired assertion:
// "the database's asset-domain Cat set equals CAT_GROUP_ORDER exactly" — BOTH directions, and it
// fails LOUDLY (a failing test), never silently (a skip is the only permitted non-pass, and it is
// itself loud — see SKIP below).
//
// WHY THIS EXISTS. `CAT_GROUP_ORDER` (nonReAllocation.ts) is a hardcoded TS array duplicating the
// DB's canonical asset-domain Cat vocabulary (`pfin.taxonomy_default`). Nothing today catches the
// two arrays drifting apart. If they do, the failure is SILENT and financial: `computeNonReAllocation`
// builds `groups` via `CAT_GROUP_ORDER.map((cat) => rowsByCat.get(cat) ?? [])` — a Cat present in
// the DB but ABSENT from CAT_GROUP_ORDER (e.g. exactly what an unmirrored rename produces) drops
// every one of its rows from the rendered table, while `total_non_re` — summed from the UNFILTERED
// 076 rows — still counts their value. Percentages under-sum, silently, failing OPEN. This test is
// the PERMANENT watch against that whole class, not a one-off check of this rename's instance —
// worth more than the rename itself per Decision 7's own framing.
//
// SCOPE NOTE — read before "fixing" a failure by editing the exclusion instead of investigating.
// `taxonomy_default`'s domain='asset' Cat set is SIX values as seeded by migration 041 + amended
// by 082: Cash, Bonds, Marketable Securities (post Decision-7 rename), Alternatives, Liabilities,
// Real Estate. `CAT_GROUP_ORDER` is FIVE — Real Estate is excluded BY DESIGN (nonReAllocation.ts's
// own header: 076 excludes it at p_include_real_estate=false, and computeNonReAllocation's
// taxonomy read filters it out independently). An equality against the RAW DB set would therefore
// fail permanently even on a fully-correct rename, which would make this watcher noise instead of
// signal the first time anyone ran it — so the comparison below is DB-set MINUS 'Real Estate' vs
// `CAT_GROUP_ORDER`, not the raw DB set. ✅ RATIFIED (F/CTO, 2026-08-19) — the amended predicate,
// transcribed rather than paraphrased: "DB asset-Cat set MINUS 'Real Estate' equals
// CAT_GROUP_ORDER, both directions, exclusion named and justified inside the assertion itself"
// (a visible EXCLUDED_FROM_CAT_GROUP_ORDER constant, never a silent filter). ADR-058 Decision 7's
// literal "equals exactly" was unsatisfiable as written; the decision to ship the assertion is
// UNCHANGED, only its stated predicate was loose. Records as ADR-058 Amendment 1, riding the split
// PR. If a future ADR adds or removes an
// asset-domain Cat (Real Estate included), this file's `EXCLUDED_FROM_CAT_GROUP_ORDER` constant is
// where that decision is recorded — not a silent widening of the filter.
//
// VENUE (read before running). QA_SELF238_POSTGREST_URL / QA_SELF238_JWT_SECRET name A VENUE — a
// throwaway Postgres+PostgREST pair with the full V1 migration chain applied — NOT a SELF-238-
// scoped fixture; this file reuses them because they're the established venue-naming convention in
// this codebase (nonReAllocation.tenant-isolation.server.test.ts stood the venue up first; that
// file's header has the full shape/gotchas, not re-duplicated here), not because this assertion is
// SELF-238-specific — it isn't; it's Decision-7/ADR-058-scoped.
//
// NO TENANT FIXTURE NEEDED, unlike the sibling file: `pfin.taxonomy_default` is GLOBAL
// SHARED-READ (041's own header — `using (true)` SELECT policy for `authenticated`, no `users_id`
// or tenant column at all), so ANY authenticated JWT reads the canonical Cat set. Needs only
// migration 041 (+ 082's rename) applied — no privileged seeding step.
//
// BOTH ENV VARS ABSENT -> the whole suite SKIPS (does not fail), mirroring the sibling file's
// convention, and logs loudly so a silent-always-skip in CI stays visible.

import { describe, it, expect } from 'vitest';
import { SignJWT } from 'jose';
import { createClient } from '@supabase/supabase-js';
import { CAT_GROUP_ORDER } from './nonReAllocation';

const POSTGREST_URL = process.env.QA_SELF238_POSTGREST_URL;
const JWT_SECRET = process.env.QA_SELF238_JWT_SECRET;
const VENUE_AVAILABLE = Boolean(POSTGREST_URL && JWT_SECRET);

/** Asset-domain Cats that exist in `taxonomy_default` but are DELIBERATELY excluded from
 *  `CAT_GROUP_ORDER` — see the SCOPE NOTE above (predicate RATIFIED by F/CTO 2026-08-19; THIS
 *  CONSTANT IS the ratified "named and justified" half, so do not inline it away).
 *  Any Cat in this set is EXPECTED to be absent from CAT_GROUP_ORDER; any Cat NOT in
 *  this set and NOT in CAT_GROUP_ORDER is the fail-open Decision 7 names. */
const EXCLUDED_FROM_CAT_GROUP_ORDER = new Set(['Real Estate']);

// Any fixed, syntactically-valid UUID works — taxonomy_default's RLS has no tenant clause to
// satisfy, so this identity is never checked against anything. Not a real/reserved tenant id.
const READER_ID = '00000000-0000-0000-0000-000000000e58';

async function makeReaderClient() {
	const secret = new TextEncoder().encode(JWT_SECRET!);
	const jwt = await new SignJWT({ sub: READER_ID, role: 'authenticated' })
		.setProtectedHeader({ alg: 'HS256' })
		.setIssuedAt()
		.setExpirationTime('10m')
		.sign(secret);
	return createClient(POSTGREST_URL!, 'unused-anon-key-bare-postgrest-does-not-check-it', {
		global: { headers: { Authorization: `Bearer ${jwt}` } }
	});
}

describe.skipIf(!VENUE_AVAILABLE)(
	'CAT_GROUP_ORDER vs pfin.taxonomy_default — ADR-058 Decision 7 paired equality assertion',
	() => {
		it('non-vacuous: the DB asset-domain Cat set is non-empty (the equality below is a real comparison, not two empty sets agreeing)', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('domain', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			expect((data ?? []).length).toBeGreaterThan(0);
		});

		it('(forward) every Cat in CAT_GROUP_ORDER exists in the DB asset-domain Cat set', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('domain', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			const dbCats = new Set((data ?? []).map((r) => (r as { cat: string }).cat));

			const missingFromDb = CAT_GROUP_ORDER.filter((cat) => !dbCats.has(cat));
			expect(
				missingFromDb,
				`CAT_GROUP_ORDER names a Cat the DB does not have — a rename landed in code without ` +
					`the DB seed delta, or vice versa: ${JSON.stringify(missingFromDb)}`
			).toEqual([]);
		});

		it('(reverse) every DB asset-domain Cat NOT in the excluded set exists in CAT_GROUP_ORDER — the fail-open direction', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('domain', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			const dbCats = [...new Set((data ?? []).map((r) => (r as { cat: string }).cat))];
			const catGroupOrderSet = new Set<string>(CAT_GROUP_ORDER);

			const unwatched = dbCats.filter(
				(cat) => !catGroupOrderSet.has(cat) && !EXCLUDED_FROM_CAT_GROUP_ORDER.has(cat)
			);
			expect(
				unwatched,
				`the DB has an asset-domain Cat that CAT_GROUP_ORDER neither renders nor deliberately ` +
					`excludes — every row under this Cat is SILENTLY DROPPED from the §2.2.2 table while ` +
					`still counted in total_non_re (Decision 7's named fail-open): ${JSON.stringify(unwatched)}`
			).toEqual([]);
		});
	}
);

if (!VENUE_AVAILABLE) {
	// eslint-disable-next-line no-console
	console.log(
		'[nonReAllocation.catGroupOrderEquality] SKIPPED — QA_SELF238_POSTGREST_URL / QA_SELF238_JWT_SECRET not set. ' +
			'This is expected in the default CI Vitest run (no PostgREST leg today); see the file header before adding one.'
	);
}
