// nonReAllocation.catGroupOrderEquality.server.test.ts — ADR-058 Decision 7's paired assertion:
// "the database's asset Cat set equals CAT_GROUP_ORDER exactly" — BOTH directions, and it
// fails LOUDLY (a failing test), never silently (a skip is the only permitted non-pass, and it is
// itself loud — see SKIP below).
//
// WHY THIS EXISTS. `CAT_GROUP_ORDER` (nonReAllocation.ts) is a hardcoded TS array duplicating the
// DB's canonical asset Cat vocabulary (`pfin.taxonomy_default`). Nothing today catches the
// two arrays drifting apart. If they do, the failure is SILENT and financial: `computeNonReAllocation`
// builds `groups` via `CAT_GROUP_ORDER.map((cat) => rowsByCat.get(cat) ?? [])` — a Cat present in
// the DB's asset set but ABSENT from CAT_GROUP_ORDER (e.g. exactly what an unmirrored rename
// produces) drops every one of its rows from the rendered table, while `total_non_re` still counts
// their value (SELF-239: the denominator sums every element='asset'-or-Unsorted 076 row, the same
// predicate this file now queries with). Percentages under-sum, silently, failing OPEN. This test
// is the PERMANENT watch against that whole class, not a one-off check of any one rename — worth
// more than any single instance per Decision 7's own framing.
//
// SCOPE NOTE — read before "fixing" a failure by editing the exclusion instead of investigating.
// SELF-239 (2026-08-20 ratified ACs) changed HOW this file derives the DB-side comparison set, not
// just what CAT_GROUP_ORDER contains. Pre-SELF-239 the DB set was the RAW six-Cat
// `taxonomy_default` read (Cash, Bonds, Marketable Securities, Alternatives, Liabilities, Real
// Estate) minus a named 'Real Estate' exclusion, compared against a FIVE-member CAT_GROUP_ORDER
// that still included Liabilities. SELF-239's assets-only ruling drops Liabilities from
// CAT_GROUP_ORDER (it is not §2.2.2 domain — Backend's nonReAllocation.ts header has the full
// rationale), and 085's `element` column now makes that exclusion EXPRESSIBLE AS A QUERY PREDICATE
// rather than a second named exclusion: the read below filters `element = 'asset'` at the DB
// (Cash, Bonds, Marketable Securities, Alternatives, Real Estate — FIVE, Liabilities excluded
// STRUCTURALLY by the predicate, not by a name in EXCLUDED_FROM_CAT_GROUP_ORDER), then Real Estate
// is still excluded BY NAME the same way it always was — element alone cannot distinguish Real
// Estate from any other asset-element Cat (085's own backfill maps Real Estate to 'asset', same as
// every non-Liabilities Cat). The comparison below is therefore DB-set(element='asset') MINUS
// 'Real Estate' vs `CAT_GROUP_ORDER` (now four), both directions. ✅ Original amended predicate
// (F/CTO, 2026-08-19, "DB asset-Cat set MINUS 'Real Estate' equals CAT_GROUP_ORDER... exclusion
// named and justified inside the assertion itself") is preserved for the Real Estate half; the
// Liabilities half moved from a named exclusion to a query predicate per SELF-239's 2026-08-20
// ratified ACs, which this file implements — a formal ADR-058 amendment entry for this second
// change is flagged to Architect/F/CTO at hand-off, not authored here. If a future ADR adds or
// removes an asset-domain Cat (Real Estate included), this file's `EXCLUDED_FROM_CAT_GROUP_ORDER`
// constant is where that decision is recorded — not a silent widening of the filter.
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
// or tenant column at all), so ANY authenticated JWT reads the canonical Cat set. Needs migration
// 041 (+ 082's rename + 085's `element` column) applied — no privileged seeding step.
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

/** Cats that exist in `taxonomy_default`'s element='asset' set but are DELIBERATELY excluded
 *  from `CAT_GROUP_ORDER` — see the SCOPE NOTE above (Real Estate half RATIFIED by F/CTO
 *  2026-08-19; THIS CONSTANT IS the ratified "named and justified" half, so do not inline it
 *  away). Liabilities is NOT in this set — it never reaches the element='asset' comparison set to
 *  begin with, so it cannot be "absent from CAT_GROUP_ORDER while present in the DB set" the way
 *  this constant's members can. Its exclusion is named separately, in
 *  STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE below — see that constant for why a SEPARATE named
 *  constant exists for a predicate-enforced exclusion rather than folding it in here.
 *  Any Cat in this set is EXPECTED to be absent from CAT_GROUP_ORDER; any Cat NOT in
 *  this set and NOT in CAT_GROUP_ORDER is the fail-open Decision 7 names. */
const EXCLUDED_FROM_CAT_GROUP_ORDER = new Set(['Real Estate']);

/** Cats excluded from the element='asset' comparison set by the QUERY PREDICATE itself
 *  (`.eq('element', 'asset')` below), not by `EXCLUDED_FROM_CAT_GROUP_ORDER`'s named-list
 *  mechanism. Named here anyway, in its OWN constant rather than folded into
 *  EXCLUDED_FROM_CAT_GROUP_ORDER, because the two exclusion mechanisms answer different failure
 *  modes and Decision 7's ratified predicate — "every excluded Cat named and justified inside the
 *  assertion" — is read here as a requirement on VISIBILITY, not on which mechanism does the
 *  excluding: a reader must be able to see, from this file's source, which Cat(s) never reach the
 *  comparison and why, without having to trust that the live predicate currently does what this
 *  comment claims. The dedicated structural-check test below is what makes that claim CHECKED
 *  rather than merely stated — it fails if a future migration ever makes a Cat OTHER than
 *  Liabilities element='liability', which a bare `.eq()` filter alone would silently absorb. */
const STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE = new Set(['Liabilities']);

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
		it('non-vacuous: the DB element=\'asset\' Cat set is non-empty (the equality below is a real comparison, not two empty sets agreeing)', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('element', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			expect((data ?? []).length).toBeGreaterThan(0);
		});

		it('(forward) every Cat in CAT_GROUP_ORDER exists in the DB element=\'asset\' Cat set', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('element', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			const dbCats = new Set((data ?? []).map((r) => (r as { cat: string }).cat));

			const missingFromDb = CAT_GROUP_ORDER.filter((cat) => !dbCats.has(cat));
			expect(
				missingFromDb,
				`CAT_GROUP_ORDER names a Cat the DB's element='asset' set does not have — a rename ` +
					`landed in code without the DB seed delta, or vice versa: ${JSON.stringify(missingFromDb)}`
			).toEqual([]);
		});

		it('(reverse) every DB element=\'asset\' Cat NOT in the excluded set exists in CAT_GROUP_ORDER — the fail-open direction', async () => {
			const client = await makeReaderClient();
			const { data, error } = await client
				.schema('pfin')
				.from('taxonomy_default')
				.select('cat')
				.eq('element', 'asset');
			if (error) throw new Error(`venue problem: taxonomy_default read failed: ${error.message}`);
			const dbCats = [...new Set((data ?? []).map((r) => (r as { cat: string }).cat))];
			const catGroupOrderSet = new Set<string>(CAT_GROUP_ORDER);

			const unwatched = dbCats.filter(
				(cat) => !catGroupOrderSet.has(cat) && !EXCLUDED_FROM_CAT_GROUP_ORDER.has(cat)
			);
			expect(
				unwatched,
				`the DB has an element='asset' Cat that CAT_GROUP_ORDER neither renders nor deliberately ` +
					`excludes — every row under this Cat is SILENTLY DROPPED from the §2.2.2 table while ` +
					`still counted in total_non_re (Decision 7's named fail-open): ${JSON.stringify(unwatched)}`
			).toEqual([]);
		});

		it('(SELF-239 structural check) the element=\'asset\' predicate excludes EXACTLY STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE — no more, no less', async () => {
			// Reads the RAW (unfiltered) Cat set and the element='asset'-FILTERED Cat set from the
			// SAME live catalog, then asserts their difference is EXACTLY the named constant — both
			// directions. This is what makes the predicate's exclusion CHECKED rather than merely
			// documented: a bare `dbCats.has('Liabilities') === false` check (the pre-strengthening
			// version of this test) would still pass if some OTHER Cat unexpectedly became
			// element='liability' too — that Cat would silently join Liabilities in being dropped
			// from the row set and the denominator, with nothing here to catch it. Comparing the
			// full raw-minus-filtered difference against the named set catches that case.
			const client = await makeReaderClient();
			const [{ data: rawData, error: rawError }, { data: assetData, error: assetError }] = await Promise.all([
				client.schema('pfin').from('taxonomy_default').select('cat'),
				client.schema('pfin').from('taxonomy_default').select('cat').eq('element', 'asset')
			]);
			if (rawError) throw new Error(`venue problem: taxonomy_default raw read failed: ${rawError.message}`);
			if (assetError) throw new Error(`venue problem: taxonomy_default element='asset' read failed: ${assetError.message}`);

			const rawCats = new Set((rawData ?? []).map((r) => (r as { cat: string }).cat));
			const assetCats = new Set((assetData ?? []).map((r) => (r as { cat: string }).cat));
			const excludedByPredicate = [...rawCats].filter((cat) => !assetCats.has(cat));

			expect(
				new Set(excludedByPredicate),
				`the element='asset' predicate excludes a different Cat set than ` +
					`STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE names — either a new liability-element ` +
					`Cat appeared (085's backfill/CHECK drifted) or a previously-liability Cat became ` +
					`asset-element (update the named constant to match, deliberately, if that's real): ` +
					`raw-minus-asset=${JSON.stringify(excludedByPredicate)}, ` +
					`named=${JSON.stringify([...STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE])}`
			).toEqual(STRUCTURALLY_EXCLUDED_BY_ELEMENT_PREDICATE);
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
