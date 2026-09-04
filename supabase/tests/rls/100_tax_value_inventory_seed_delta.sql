-- =====================================================================
-- Per-Wave battery — pfin.posting_prototype{,_default} + pfin.user_taxonomy /
--   pfin.taxonomy_default: the V1.4 tax-value inventory SEED DELTA (SELF-263).
--   Value corrections on both pairs (guarded UPDATEs), the Revenue /
--   Dividend - Qualified row add + its per-user backfill, and the four
--   `comment on column ... .tax_relevant` pins. No function, policy, grant or
--   trigger is authored — this battery proves DATA/comment correctness and
--   the backfill's reach discipline, not a new RLS mechanism.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/100_tax_value_inventory_seed_delta.sql
--   (committed a94d50d, blob md5 47acfcb1c3d5d629d4e07c47682d7a81 — re-hash
--   before trusting this line). Every UPDATE/INSERT statement copied or
--   re-derived below is checked against that committed blob directly, not
--   reconstructed from memory of the AC text alone. a94d50d is a text-only
--   fix (Sec F-1/F-2/F-4-subnote: header attribution + a CLASS-SCOPE column
--   comment addition on posting_prototype_default.tax_relevant) over 4ee2a10
--   — no statement/guard/value/grant/policy/trigger/function changed; D1-D5
--   below (added for Sec A-1) were authored and inversion-proved against
--   this same committed blob.
--
-- ┌─ WHAT THIS BATTERY PROVES ───────────────────────────────────────────────┐
-- │ (BF) BACKFILL REACH (AC 8 i) — a tenant already-provisioned BEFORE 100    │
-- │     (synthetic OLD-state rows matching 100's own UPDATE guards) holds,    │
-- │     after REPLAYING 100's own statements (2)/(4)/(6) verbatim against     │
-- │     that fixture — the only way to exercise a migration-time backfill on  │
-- │     a scratch DB where 100 already ran once against zero synthetic users  │
-- │     (077/080/091 precedent) — every corrected value AC 8 i names.         │
-- │ (FS) FRESH-SIGNUP ROW COUNT (AC 8 ii) — a tenant provisioned AFTER 100    │
-- │     (full column-listed copy from BOTH default tables, 091's FS pattern)  │
-- │     receives 30 posting_prototype rows and 38 user_taxonomy rows, by ROW  │
-- │     COUNT — the provisioning branch is fail-soft, so an error-absence     │
-- │     assertion would be vacuous.                                          │
-- │ (IDEM) IDEMPOTENCY — every one of 100's six UPDATE/INSERT statements,     │
-- │     RE-APPLIED a second time (the three default-table statements against  │
-- │     the REAL already-migrated defaults; the three backfill statements     │
-- │     against this file's own already-corrected fixture tenants), affects   │
-- │     ZERO rows. The guard IS the idempotence mechanism (100's own header). │
-- │ (COM) THE FOUR COMMENT PINS (AC 6) — `col_description` on each table's    │
-- │     tax_relevant column contains "not marked" and does NOT contain the    │
-- │     negated reading "found not tax-relevant".                            │
-- │ (ISO) CROSS-TENANT — the backfill reaches every already-provisioned       │
-- │     tenant INDEPENDENTLY (a second fixture tenant's row is corrected on   │
-- │     its own identity, not merged with the first's), and ordinary RLS      │
-- │     read/write isolation holds unchanged on both tables post-100.        │
-- │ (VOC) NO NEW VOCABULARY (AC 7) — pfin.tax_character still carries exactly │
-- │     5 codes; pfin.tax_character_enum does not exist.                     │
-- │ (D) REAL DEFAULT-TABLE POST-STATE (Sec A-1, SELF-263 joint-review AMBER   │
-- │     condition) — pfin.posting_prototype_default / pfin.taxonomy_default   │
-- │     read DIRECTLY, no fixture, no replay: BF2/BF4/BF5/BF6/BF7/BF8         │
-- │     re-aimed at the real tables every future signup inherits. BF1-8       │
-- │     watch this battery's own fixture+replay; IDEM1-3 watch the real       │
-- │     tables but only via zero-rows-affected, which a never-matching guard  │
-- │     also satisfies. D1-D5 are the watcher the migration's header          │
-- │     promises and IDEM cannot provide.                                    │
-- └────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (read ADR-011 Decision 4 live before
--   trusting this line — this battery carries no tally). Decision-3 family
--   UNCHANGED (+0) — 100 introduces no reference column and no id is minted
--   or crossed; this battery's own fixture rows carry no cross-tenant FK
--   either (100's own header, re-verified rather than merely cited).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — three migration-local fixture
--   tenants (tPre/tOther/tFresh, suffixed '100'), NOT the shared
--   _rls.tenant_a()/_b() (091/082 precedent for a migration-local BF fixture
--   that must NOT collide with another battery file's fixture identities —
--   each file is its own transaction/connection, so collision is impossible
--   regardless, but distinct literals keep a diff legible). NO PII / NO real
--   account numbers / NO prod data. All in a rolled-back txn.
--
-- ⚠ HARDCODE-VS-DYNAMIC (041's rule, applied here without re-deriving it):
--   30 / 38 / 25 / 24 / 1 / 5 below are HARDCODED against the migration-seeded
--   TRUTH (100's own CONTRACT block, re-measured at authoring), never a
--   self-referential `count(*)` comparison — DESIGN.md §8 rule 5.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 convention, PR #555 gotcha):
--   `_rls.expect_cross_tenant_write_blocked` does NOT self-restore role — the
--   restore sits immediately after it, not after the next leg (084/091
--   precedent). `_rls._visible_owner_rows` (and therefore
--   `expect_cross_tenant_read_empty`) DOES self-restore.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(34);  -- BF-PRE1 + BF1-8 (9) + D1-5 (5) + FS1-2 (2) + IDEM1-6 (6) + COM1-4 (4) + ISO-PRE + ISO1-5 (6) + VOC1-2 (2)

\set tPre   '00000000-0000-0000-0000-00000000a100'
\set tOther '00000000-0000-0000-0000-00000000b100'
\set tFresh '00000000-0000-0000-0000-00000000c100'

insert into auth.users (id) values (:'tPre'), (:'tOther'), (:'tFresh');

-- =====================================================================
-- BLOCK BF — backfill reach (AC 8 i). Fixture: tPre and tOther both hold
--   OLD-state (pre-100) rows on both tables of both pairs. tPre carries the
--   FULL set (all three cash-flow rows + all 25 relevant asset Sub-Cats + a
--   Real Estate control); tOther carries a MINIMAL set (Contribution + one
--   asset row + a Real Estate control) — just enough to prove the backfill
--   reaches a SECOND, independent tenant without re-deriving the whole 25-row
--   asset fixture twice (that independence is what BLOCK ISO's (ISO-PRE)
--   leg checks).
-- =====================================================================

-- Cash-flow pair, OLD-state, tPre: exactly the three rows 100 corrects.
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, notes, is_tax_payment)
values
  (:'tPre', 'Equity', 'Contribution', true, null,
   'potentially deductible; resolve per account type at the V1.4 tax inventory', false),
  (:'tPre', 'Revenue', 'Dividend', true, 'qualified_dividend',
   'pre-100 placeholder dividend note (100''s own guard on this row is tax_character only)', false),
  (:'tPre', 'Revenue', 'Bond Premium', true, 'ordinary',
   'Mark-to-Market Gain for Tax Purposes', false);

-- Cash-flow pair, OLD-state, tOther: Contribution only (BLOCK ISO's fixture).
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, notes, is_tax_payment)
values
  (:'tOther', 'Equity', 'Contribution', true, null,
   'potentially deductible; resolve per account type at the V1.4 tax inventory', false);

-- Asset pair, OLD-state, tPre: all 25 Sub-Cats 100's statement (4) corrects,
--   false/NULL — the 041-seeded baseline every one of these rows held before
--   100 ran. Column-listed (matches 009/085's actual columns: no `domain`,
--   post-084; `element` NOT NULL, post-085).
insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, element)
select :'tPre', v.cat, v.sub_cat, false, null, 'asset'
  from (values
    ('Cash',                  'T-Bill'),
    ('Bonds',                 'IGL'),
    ('Bonds',                 'IGI'),
    ('Bonds',                 'HYI'),
    ('Bonds',                 'INTL'),
    ('Marketable Securities', 'UNKNOWN'),
    ('Marketable Securities', 'US-01-Basic_Materials'),
    ('Marketable Securities', 'US-02-Telecom'),
    ('Marketable Securities', 'US-03-Consumer_Discretionary'),
    ('Marketable Securities', 'US-04-Consumer_Staples'),
    ('Marketable Securities', 'US-05-Energy'),
    ('Marketable Securities', 'US-06-Financials'),
    ('Marketable Securities', 'US-07-Health_Care'),
    ('Marketable Securities', 'US-08-Industrials'),
    ('Marketable Securities', 'US-09-Information_Technology'),
    ('Marketable Securities', 'US-10-Utilities'),
    ('Marketable Securities', 'US-Index-Non_Sector'),
    ('Marketable Securities', 'US-Growth-Non_Sector'),
    ('Marketable Securities', 'ExUS-Developed_Market'),
    ('Marketable Securities', 'ExUS-Emerging_Market'),
    ('Alternatives',          'REIT'),
    ('Alternatives',          'Crypto-Fx'),
    ('Alternatives',          'Commodities-Other'),
    ('Alternatives',          'Volatility-Hedges'),
    ('Alternatives',          'Volatility-60/40')
  ) as v(cat, sub_cat);

-- Real Estate control, tPre: stays false/NULL — absent from statement (4)'s
--   VALUES list, so untouched by 100 (BF8 watches this).
insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, element)
values (:'tPre', 'Real Estate', 'Residential', false, null, 'asset');

-- Asset pair, OLD-state, tOther: Cash/T-Bill (a relevant row) + Real Estate
--   control (an irrelevant one) — minimal, same shape as tPre's, for ISO.
insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, element)
values
  (:'tOther', 'Cash', 'T-Bill', false, null, 'asset'),
  (:'tOther', 'Real Estate', 'Residential', false, null, 'asset');

-- (BF-PRE1) precondition: the fixture genuinely represents PRE-100 state —
--   tPre's Contribution row matches 100's OLD guard exactly, before replay.
select ok(
  (select tax_relevant is true
      and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory'
     from pfin.posting_prototype
    where users_id = :'tPre' and cat = 'Equity' and sub_cat = 'Contribution'),
  '(BF-PRE1) precondition: tPre''s fixture Contribution row matches 100''s OLD guard exactly before the replay — the fixture is genuinely pre-100 state, not already-corrected data'
);

-- REPLAY — 100's own statement (2), copied verbatim, checked against the
--   committed blob directly. GLOBAL (no tenant filter, by 100's own design —
--   see the migration header's REACH DECISION) — reaches BOTH tPre and
--   tOther in one apply.
update pfin.posting_prototype
   set tax_relevant = false,
       notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
 where cat = 'Equity'
   and sub_cat = 'Contribution'
   and tax_relevant is true
   and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory';

update pfin.posting_prototype
   set tax_character = 'ordinary',
       notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
 where cat = 'Revenue'
   and sub_cat = 'Dividend'
   and tax_character = 'qualified_dividend';

update pfin.posting_prototype
   set notes = 'Bond premium amortization / market-discount accretion — an ordinary-interest adjustment (1099-INT / OID), never a capital item.'
 where cat = 'Revenue'
   and sub_cat = 'Bond Premium'
   and notes = 'Mark-to-Market Gain for Tax Purposes';

-- REPLAY — 100's own statement (4), copied verbatim. GLOBAL, reaches both.
update pfin.user_taxonomy u
   set tax_relevant = true,
       tax_character = v.tax_character
  from (values
    ('Cash',                  'T-Bill',                       'short_term_only'),
    ('Bonds',                 'IGL',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'IGI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'HYI',                          'long_term_capital_gain_eligible'),
    ('Bonds',                 'INTL',                         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'UNKNOWN',                      'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-01-Basic_Materials',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-02-Telecom',                'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-03-Consumer_Discretionary', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-04-Consumer_Staples',       'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-05-Energy',                 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-06-Financials',             'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-07-Health_Care',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-08-Industrials',            'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-09-Information_Technology', 'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-10-Utilities',              'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Index-Non_Sector',          'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'US-Growth-Non_Sector',         'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Developed_Market',        'long_term_capital_gain_eligible'),
    ('Marketable Securities', 'ExUS-Emerging_Market',         'long_term_capital_gain_eligible'),
    ('Alternatives',          'REIT',                         'long_term_capital_gain_eligible'),
    ('Alternatives',          'Crypto-Fx',                    'long_term_capital_gain_eligible'),
    ('Alternatives',          'Commodities-Other',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-Hedges',            'long_term_capital_gain_eligible'),
    ('Alternatives',          'Volatility-60/40',             'long_term_capital_gain_eligible')
  ) as v (cat, sub_cat, tax_character)
 where u.cat = v.cat
   and u.sub_cat = v.sub_cat
   and u.tax_relevant is false
   and u.tax_character is null;

-- REPLAY — 100's own statement (6), copied verbatim. Reads the row VALUES
--   from posting_prototype_default (already corrected for real by 100's
--   apply), cross-joins every DISTINCT users_id currently in
--   posting_prototype — which at this point is exactly {tPre, tOther}.
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes,
   is_tax_payment)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes,
  d.is_tax_payment
from pfin.posting_prototype_default d
cross join (select distinct pp.users_id from pfin.posting_prototype pp) provisioned
where d.cat = 'Revenue'
  and d.sub_cat = 'Dividend - Qualified'
on conflict (users_id, cat, sub_cat) do nothing;

-- (BF1) Contribution: tax_relevant=false, tax_character NULL, notes carries
--   the corrected description, and NO trace of the old ADR-062 D4 rider.
select ok(
  (select tax_relevant = false
      and tax_character is null
      and notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
      and notes not like '%resolve per account type at the V1.4 tax inventory%'
     from pfin.posting_prototype
    where users_id = :'tPre' and cat = 'Equity' and sub_cat = 'Contribution'),
  '(BF1) tPre Contribution POST-100: tax_relevant=false, tax_character IS NULL, notes carries the corrected description, and NO trace of the old ADR-062 Decision 4 rider string'
);

-- (BF2) Dividend: the fail-closed ORDINARY bucket.
select ok(
  (select tax_relevant = true and tax_character = 'ordinary'
     from pfin.posting_prototype
    where users_id = :'tPre' and cat = 'Revenue' and sub_cat = 'Dividend'),
  '(BF2) tPre Dividend POST-100: tax_relevant=true, tax_character=ordinary (the fail-closed generic bucket, E4 D-ii)'
);

-- (BF3) the NEW Dividend - Qualified row, backfilled.
select ok(
  (select tax_relevant = true and tax_character = 'qualified_dividend' and display_order = 65
     from pfin.posting_prototype
    where users_id = :'tPre' and cat = 'Revenue' and sub_cat = 'Dividend - Qualified'),
  '(BF3) tPre receives the NEW Dividend - Qualified row via the backfill: tax_relevant=true, tax_character=qualified_dividend, display_order=65 (E4 D-ii option C prime)'
);

-- (BF4) Bond Premium: value CONFIRMED, notes corrected off the
--   mark-to-market wording (100's own header names the misattribution).
select ok(
  (select tax_relevant = true and tax_character = 'ordinary'
      and notes not like '%Mark-to-Market%'
     from pfin.posting_prototype
    where users_id = :'tPre' and cat = 'Revenue' and sub_cat = 'Bond Premium'),
  '(BF4) tPre Bond Premium POST-100: value CONFIRMED (tax_relevant=true, tax_character=ordinary), notes corrected off the mark-to-market wording that names a different (§1256) concept'
);

-- (BF5) asset side: exactly 25 tax_relevant=true rows.
select is(
  (select count(*)::bigint from pfin.user_taxonomy where users_id = :'tPre' and tax_relevant = true),
  25::bigint,
  '(BF5) tPre asset side POST-100: exactly 25 tax_relevant=true rows'
);

-- (BF6) exactly 24 long_term_capital_gain_eligible.
select is(
  (select count(*)::bigint from pfin.user_taxonomy
    where users_id = :'tPre' and tax_character = 'long_term_capital_gain_eligible'),
  24::bigint,
  '(BF6) tPre asset side POST-100: exactly 24 long_term_capital_gain_eligible rows'
);

-- (BF7) exactly 1 short_term_only, and it is Cash / T-Bill (not merely a count).
select is(
  (select array_agg(cat || '/' || sub_cat) from pfin.user_taxonomy
    where users_id = :'tPre' and tax_character = 'short_term_only'),
  array['Cash/T-Bill'],
  '(BF7) tPre asset side POST-100: exactly 1 short_term_only row and it is Cash / T-Bill (discount gain is legally interest, never long-term)'
);

-- (BF8) Real Estate stays tax_relevant=false — absent from 100's VALUES list,
--   untouched (the disposition is UNMODELLED, not tax-free — 100's own header).
select is(
  (select count(*)::bigint from pfin.user_taxonomy
    where users_id = :'tPre' and cat = 'Real Estate' and tax_relevant = true),
  0::bigint,
  '(BF8) tPre Real Estate rows remain tax_relevant=false POST-100 — absent from the corrected VALUES list, untouched by design'
);

-- =====================================================================
-- BLOCK D — REAL DEFAULT-TABLE POST-STATE (Sec A-1, SELF-263 joint-review
--   AMBER blocking condition). pfin.posting_prototype_default and
--   pfin.taxonomy_default are the provisioning source EVERY FUTURE SIGNUP
--   inherits (api/src/lib/server/queries/taxonomy.ts:37,
--   DEFAULT_PROVISION_COLUMNS already carries tax_relevant/tax_character).
--   BF1-BF8 above observe this battery's OWN fixture, corrected by this
--   battery's OWN replayed copies of statements (2)/(4)/(6) — they cannot
--   catch a miss on the real default tables. IDEM1/IDEM2/IDEM3 below DO hit
--   the real default tables but assert zero-rows-affected only, which a
--   guard that never matched anything satisfies exactly as well as a guard
--   that corrected everything — vacuous on cost (c), "A MISS IS SILENT",
--   the migration header's own named failure mode. These five legs read
--   the real default tables DIRECTLY, no fixture, no replay: BF2/BF4/BF5/
--   BF6/BF7/BF8 re-aimed at the tables that matter. Inversion-proved
--   against statement (3) (D3/D4/D5 red, BF5-BF8 stay green) and
--   statement (1) (D1 red, BF2 green) — see the commit hand-off.
-- =====================================================================

-- (D1) REAL pfin.posting_prototype_default Revenue/Dividend: the fail-closed
--   ORDINARY bucket, and notes carries the corrected wording — statement
--   (1) landed on the real default table, not only this battery's fixture.
select ok(
  (select tax_character = 'ordinary'
      and notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
     from pfin.posting_prototype_default
    where cat = 'Revenue' and sub_cat = 'Dividend'),
  '(D1) REAL pfin.posting_prototype_default Revenue/Dividend: tax_character=ordinary (E4 D-ii fail-closed bucket) and notes carries the corrected wording — statement (1) on the real default table'
);

-- (D2) REAL pfin.posting_prototype_default Revenue/Bond Premium: value
--   CONFIRMED ordinary, notes off the mark-to-market wording — statement
--   (1) landed on the real default table.
select ok(
  (select tax_character = 'ordinary'
      and notes not like '%Mark-to-Market%'
     from pfin.posting_prototype_default
    where cat = 'Revenue' and sub_cat = 'Bond Premium'),
  '(D2) REAL pfin.posting_prototype_default Revenue/Bond Premium: tax_character CONFIRMED ordinary and notes corrected off the mark-to-market wording — statement (1) on the real default table'
);

-- (D3) REAL pfin.taxonomy_default: exactly 25 tax_relevant=true rows — BF5
--   re-aimed at the real default table.
select is(
  (select count(*)::bigint from pfin.taxonomy_default where tax_relevant = true),
  25::bigint,
  '(D3) REAL pfin.taxonomy_default: exactly 25 tax_relevant=true rows — statement (3) on the real default table, not only this battery''s fixture'
);

-- (D4) REAL pfin.taxonomy_default: exactly 24 long_term_capital_gain_eligible
--   rows, AND exactly 1 short_term_only row which IS Cash/T-Bill (identity,
--   not merely a count — BF6/BF7 re-aimed at the real default table).
select ok(
  (select count(*) from pfin.taxonomy_default where tax_character = 'long_term_capital_gain_eligible') = 24
  and (select array_agg(cat || '/' || sub_cat) from pfin.taxonomy_default where tax_character = 'short_term_only') = array['Cash/T-Bill'],
  '(D4) REAL pfin.taxonomy_default: exactly 24 long_term_capital_gain_eligible rows, and exactly 1 short_term_only row which IS Cash/T-Bill (discount gain is legally interest, never long-term) — statement (3) on the real default table'
);

-- (D5) REAL pfin.taxonomy_default: Real Estate rows remain tax_relevant=false
--   — absent from statement (3)'s VALUES list, untouched — BF8's control,
--   re-aimed at the real default table.
select is(
  (select count(*)::bigint from pfin.taxonomy_default where cat = 'Real Estate' and tax_relevant = true),
  0::bigint,
  '(D5) REAL pfin.taxonomy_default: Real Estate rows remain tax_relevant=false POST-100 — absent from statement (3)''s corrected VALUES list, untouched by design'
);

-- =====================================================================
-- BLOCK FS — fresh-signup provisioning, DB layer ONLY (AC 8 ii). Does NOT
--   exercise api/src/lib/server/queries/taxonomy.ts — pgTAP runs SQL, not
--   TypeScript (091's FS-block scope note, applies verbatim). Full
--   column-listed copy from BOTH default tables, mirroring 041/091's
--   provisioning-statement shape exactly.
-- =====================================================================

insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
select :'tFresh', cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment
  from pfin.posting_prototype_default
on conflict (users_id, cat, sub_cat) do nothing;

insert into pfin.user_taxonomy
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
select :'tFresh', cat, sub_cat, tax_relevant, tax_character, display_order, notes, element
  from pfin.taxonomy_default
on conflict (users_id, cat, sub_cat) do nothing;

-- (FS1) fresh signup receives 30 posting_prototype rows, asserted by ROW
--   COUNT (not error-absence — the provisioning branch is fail-soft):
--   30 = 29 at 091 + the Dividend - Qualified row landed by 100.
select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'tFresh'),
  30::bigint,
  '(FS1) fresh signup receives 30 posting_prototype rows, by ROW COUNT (AC 8 ii): 30 = 29 at 091 + Dividend - Qualified'
);

-- (FS2) fresh signup receives 38 user_taxonomy rows — unchanged by 100
--   (the asset side gains no row, only value corrections).
select is(
  (select count(*)::bigint from pfin.user_taxonomy where users_id = :'tFresh'),
  38::bigint,
  '(FS2) fresh signup receives 38 user_taxonomy rows, by ROW COUNT (AC 8 ii): unchanged by 100 — no asset-side row is added'
);

-- =====================================================================
-- BLOCK IDEM — idempotency (100's header, "WHY EVERY STATEMENT IS GUARDED").
--   Every one of 100's six UPDATE/INSERT statements, re-applied a second
--   time here, affects ZERO rows: the three default-table statements
--   against the REAL already-migrated defaults (100 already ran once at
--   chain-apply time), the three backfill statements against this file's
--   own already-corrected BLOCK BF / BLOCK FS fixture tenants.
-- =====================================================================

-- ⚠ MECHANICAL NOTE: each leg's data-modifying WITH is issued as its OWN
--   TOP-LEVEL statement, captured via `\gset`, and the pgTAP `is()` call runs
--   as a SEPARATE following statement — Postgres rejects "WITH clause
--   containing a data-modifying statement" when nested inside a scalar
--   subquery argument (confirmed by pg_prove: exactly that error, on the
--   first-drafted nested form, before this fix — never verify a battery
--   locally with bare psql, this is why).

-- (IDEM1) statement (1) — the three posting_prototype_default UPDATEs.
with u1 as (
  update pfin.posting_prototype_default
     set tax_relevant = false,
         notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
   where cat = 'Equity' and sub_cat = 'Contribution'
     and tax_relevant is true
     and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory'
  returning 1
),
u2 as (
  update pfin.posting_prototype_default
     set tax_character = 'ordinary',
         notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
   where cat = 'Revenue' and sub_cat = 'Dividend' and tax_character = 'qualified_dividend'
  returning 1
),
u3 as (
  update pfin.posting_prototype_default
     set notes = 'Bond premium amortization / market-discount accretion — an ordinary-interest adjustment (1099-INT / OID), never a capital item.'
   where cat = 'Revenue' and sub_cat = 'Bond Premium' and notes = 'Mark-to-Market Gain for Tax Purposes'
  returning 1
)
select ((select count(*) from u1) + (select count(*) from u2) + (select count(*) from u3))::bigint as idem1_affected
\gset

select is(
  :idem1_affected::bigint,
  0::bigint,
  '(IDEM1) re-applying 100''s three posting_prototype_default UPDATEs (statement 1) a second time affects ZERO rows total — already corrected by the real apply'
);

-- (IDEM2) statement (3) — the 25-row taxonomy_default asset UPDATE.
with u as (
  update pfin.taxonomy_default d
     set tax_relevant = true, tax_character = v.tax_character
    from (values
      ('Cash','T-Bill','short_term_only'),
      ('Bonds','IGL','long_term_capital_gain_eligible'),
      ('Bonds','IGI','long_term_capital_gain_eligible'),
      ('Bonds','HYI','long_term_capital_gain_eligible'),
      ('Bonds','INTL','long_term_capital_gain_eligible'),
      ('Marketable Securities','UNKNOWN','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-01-Basic_Materials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-02-Telecom','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-03-Consumer_Discretionary','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-04-Consumer_Staples','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-05-Energy','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-06-Financials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-07-Health_Care','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-08-Industrials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-09-Information_Technology','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-10-Utilities','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-Index-Non_Sector','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-Growth-Non_Sector','long_term_capital_gain_eligible'),
      ('Marketable Securities','ExUS-Developed_Market','long_term_capital_gain_eligible'),
      ('Marketable Securities','ExUS-Emerging_Market','long_term_capital_gain_eligible'),
      ('Alternatives','REIT','long_term_capital_gain_eligible'),
      ('Alternatives','Crypto-Fx','long_term_capital_gain_eligible'),
      ('Alternatives','Commodities-Other','long_term_capital_gain_eligible'),
      ('Alternatives','Volatility-Hedges','long_term_capital_gain_eligible'),
      ('Alternatives','Volatility-60/40','long_term_capital_gain_eligible')
    ) as v(cat, sub_cat, tax_character)
   where d.cat = v.cat and d.sub_cat = v.sub_cat and d.tax_relevant is false and d.tax_character is null
  returning 1
)
select count(*)::bigint as idem2_affected from u
\gset

select is(
  :idem2_affected::bigint,
  0::bigint,
  '(IDEM2) re-applying 100''s taxonomy_default 25-row asset UPDATE (statement 3) a second time affects ZERO rows — already corrected by the real apply'
);

-- (IDEM3) statement (5) — the Dividend - Qualified default-row INSERT.
with u as (
  insert into pfin.posting_prototype_default
    (cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
  values
    ('Revenue', 'Dividend - Qualified', true, 'qualified_dividend', 65,
     'Qualified dividend from a Stock or ETF — the payer and holding-period tests are met, so it is taxed at long-term capital-gain rates Federally (California taxes it as ordinary income).',
     false)
  on conflict (cat, sub_cat) do nothing
  returning 1
)
select count(*)::bigint as idem3_affected from u
\gset

select is(
  :idem3_affected::bigint,
  0::bigint,
  '(IDEM3) re-applying 100''s Dividend - Qualified INSERT (statement 5) a second time inserts ZERO new rows — on conflict do nothing, already present'
);

-- (IDEM4) statement (2) — the three posting_prototype backfill UPDATEs,
--   global: re-run against tPre + tOther (already corrected by BLOCK BF)
--   AND tFresh (already correct from BLOCK FS's copy).
with u1 as (
  update pfin.posting_prototype
     set tax_relevant = false,
         notes = 'Owner capital contribution — value moved into the portfolio from the owner. Not income; retirement-contribution deductibility is per account and is not modelled in V1.'
   where cat = 'Equity' and sub_cat = 'Contribution'
     and tax_relevant is true
     and notes = 'potentially deductible; resolve per account type at the V1.4 tax inventory'
  returning 1
),
u2 as (
  update pfin.posting_prototype
     set tax_character = 'ordinary',
         notes = 'Dividend from a Stock or ETF — ORDINARY (non-qualified): REIT, bond-fund and money-market distributions. A dividend that meets the qualified payer and holding-period tests belongs in Dividend - Qualified.'
   where cat = 'Revenue' and sub_cat = 'Dividend' and tax_character = 'qualified_dividend'
  returning 1
),
u3 as (
  update pfin.posting_prototype
     set notes = 'Bond premium amortization / market-discount accretion — an ordinary-interest adjustment (1099-INT / OID), never a capital item.'
   where cat = 'Revenue' and sub_cat = 'Bond Premium' and notes = 'Mark-to-Market Gain for Tax Purposes'
  returning 1
)
select ((select count(*) from u1) + (select count(*) from u2) + (select count(*) from u3))::bigint as idem4_affected
\gset

select is(
  :idem4_affected::bigint,
  0::bigint,
  '(IDEM4) re-applying 100''s three posting_prototype backfill UPDATEs (statement 2) a second time affects ZERO rows total across ALL provisioned tenants (tPre, tOther, tFresh)'
);

-- (IDEM5) statement (4) — the 25-row user_taxonomy backfill UPDATE, global.
with u as (
  update pfin.user_taxonomy uu
     set tax_relevant = true, tax_character = v.tax_character
    from (values
      ('Cash','T-Bill','short_term_only'),
      ('Bonds','IGL','long_term_capital_gain_eligible'),
      ('Bonds','IGI','long_term_capital_gain_eligible'),
      ('Bonds','HYI','long_term_capital_gain_eligible'),
      ('Bonds','INTL','long_term_capital_gain_eligible'),
      ('Marketable Securities','UNKNOWN','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-01-Basic_Materials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-02-Telecom','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-03-Consumer_Discretionary','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-04-Consumer_Staples','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-05-Energy','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-06-Financials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-07-Health_Care','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-08-Industrials','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-09-Information_Technology','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-10-Utilities','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-Index-Non_Sector','long_term_capital_gain_eligible'),
      ('Marketable Securities','US-Growth-Non_Sector','long_term_capital_gain_eligible'),
      ('Marketable Securities','ExUS-Developed_Market','long_term_capital_gain_eligible'),
      ('Marketable Securities','ExUS-Emerging_Market','long_term_capital_gain_eligible'),
      ('Alternatives','REIT','long_term_capital_gain_eligible'),
      ('Alternatives','Crypto-Fx','long_term_capital_gain_eligible'),
      ('Alternatives','Commodities-Other','long_term_capital_gain_eligible'),
      ('Alternatives','Volatility-Hedges','long_term_capital_gain_eligible'),
      ('Alternatives','Volatility-60/40','long_term_capital_gain_eligible')
    ) as v(cat, sub_cat, tax_character)
   where uu.cat = v.cat and uu.sub_cat = v.sub_cat and uu.tax_relevant is false and uu.tax_character is null
  returning 1
)
select count(*)::bigint as idem5_affected from u
\gset

select is(
  :idem5_affected::bigint,
  0::bigint,
  '(IDEM5) re-applying 100''s user_taxonomy 25-row asset backfill UPDATE (statement 4) a second time affects ZERO rows total across ALL provisioned tenants'
);

-- (IDEM6) statement (6) — the per-user Dividend - Qualified backfill INSERT.
with u as (
  insert into pfin.posting_prototype
    (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
  select provisioned.users_id, d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes, d.is_tax_payment
    from pfin.posting_prototype_default d
    cross join (select distinct pp.users_id from pfin.posting_prototype pp) provisioned
   where d.cat = 'Revenue' and d.sub_cat = 'Dividend - Qualified'
  on conflict (users_id, cat, sub_cat) do nothing
  returning 1
)
select count(*)::bigint as idem6_affected from u
\gset

select is(
  :idem6_affected::bigint,
  0::bigint,
  '(IDEM6) re-applying 100''s per-user Dividend - Qualified backfill INSERT (statement 6) a second time inserts ZERO new rows across ALL provisioned tenants (tPre, tOther, tFresh) — already landed by BLOCK BF / BLOCK FS'
);

-- =====================================================================
-- BLOCK COM — the four `comment on column ... .tax_relevant` pins (AC 6).
--   Each contains "not marked" and does NOT contain the negated reading
--   "found not tax-relevant" the comment text exists specifically to rule
--   out (100's header: "a consumer MUST NOT infer from a false that the
--   question was asked").
-- =====================================================================

select ok(
  (select col_description('pfin.user_taxonomy'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.user_taxonomy'::regclass and attname = 'tax_relevant'))
   ilike '%not marked%'
   and col_description('pfin.user_taxonomy'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.user_taxonomy'::regclass and attname = 'tax_relevant'))
   not ilike '%found not tax-relevant%'),
  '(COM1) pfin.user_taxonomy.tax_relevant column comment contains "not marked" and does NOT carry the negated reading "found not tax-relevant"'
);

select ok(
  (select col_description('pfin.taxonomy_default'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.taxonomy_default'::regclass and attname = 'tax_relevant'))
   ilike '%not marked%'
   and col_description('pfin.taxonomy_default'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.taxonomy_default'::regclass and attname = 'tax_relevant'))
   not ilike '%found not tax-relevant%'),
  '(COM2) pfin.taxonomy_default.tax_relevant column comment contains "not marked" and does NOT carry the negated reading "found not tax-relevant"'
);

select ok(
  (select col_description('pfin.posting_prototype'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.posting_prototype'::regclass and attname = 'tax_relevant'))
   ilike '%not marked%'
   and col_description('pfin.posting_prototype'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.posting_prototype'::regclass and attname = 'tax_relevant'))
   not ilike '%found not tax-relevant%'),
  '(COM3) pfin.posting_prototype.tax_relevant column comment contains "not marked" and does NOT carry the negated reading "found not tax-relevant"'
);

select ok(
  (select col_description('pfin.posting_prototype_default'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.posting_prototype_default'::regclass and attname = 'tax_relevant'))
   ilike '%not marked%'
   and col_description('pfin.posting_prototype_default'::regclass,
     (select attnum from pg_attribute where attrelid = 'pfin.posting_prototype_default'::regclass and attname = 'tax_relevant'))
   not ilike '%found not tax-relevant%'),
  '(COM4) pfin.posting_prototype_default.tax_relevant column comment contains "not marked" and does NOT carry the negated reading "found not tax-relevant"'
);

-- =====================================================================
-- BLOCK ISO — cross-tenant. The backfill reaches every already-provisioned
--   tenant INDEPENDENTLY, and ordinary two-tenant RLS isolation (SECURITY
--   §4.5) holds unchanged on both tables post-100.
-- =====================================================================

-- (ISO-PRE) tOther's Contribution row was ALSO corrected by the same GLOBAL
--   backfill (100 carries no tenant filter — see the migration header's
--   REACH DECISION), independently of tPre's: own users_id, not merged.
select ok(
  (select tax_relevant = false and users_id = :'tOther'::uuid
     from pfin.posting_prototype
    where users_id = :'tOther' and cat = 'Equity' and sub_cat = 'Contribution'),
  '(ISO-PRE) tOther''s Contribution row was ALSO corrected by the same global backfill, independently of tPre''s — own users_id, not merged'
);

-- (ISO1) under RLS as tPre: sees exactly its own 4 posting_prototype rows
--   (Contribution, Dividend, Bond Premium, Dividend - Qualified) — not
--   tOther's single Contribution row.
select _rls.set_tenant(:'tPre'::uuid);
select is(
  (select count(*)::bigint from pfin.posting_prototype),
  4::bigint,
  '(ISO1) under RLS as tPre: sees exactly its own 4 posting_prototype rows — not tOther''s'
);
select set_config('role', 'postgres', true);

-- (ISO2) cross-tenant read fails closed: tOther cannot see tPre's rows.
select _rls.expect_cross_tenant_read_empty(
  'pfin.posting_prototype'::regclass, :'tPre'::uuid, :'tOther'::uuid
);  -- (ISO2)

-- (ISO3) cross-tenant write fails closed: tOther cannot forge a
--   users_id=tPre posting_prototype row. ⚠ leaves the session as the
--   INTRUDER tenant (helper does not self-restore) — restore immediately
--   below, per 084/091's own documented gotcha.
select _rls.expect_cross_tenant_write_blocked(
  :'tOther'::uuid,
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values (%L, 'Equity', 'Contribution', false) $$, :'tPre'),
  '(ISO3) cross-tenant write fails closed: tOther cannot forge a users_id=tPre posting_prototype row'
);
select set_config('role', 'postgres', true);

-- (ISO4) under RLS as tPre: sees exactly its own 26 user_taxonomy rows (25
--   tax-relevant asset rows + the Real Estate control) — not tOther's.
select _rls.set_tenant(:'tPre'::uuid);
select is(
  (select count(*)::bigint from pfin.user_taxonomy),
  26::bigint,
  '(ISO4) under RLS as tPre: sees exactly its own 26 user_taxonomy rows — not tOther''s'
);
select set_config('role', 'postgres', true);

-- (ISO5) cross-tenant read fails closed on the asset side too.
select _rls.expect_cross_tenant_read_empty(
  'pfin.user_taxonomy'::regclass, :'tPre'::uuid, :'tOther'::uuid
);  -- (ISO5)

-- =====================================================================
-- BLOCK VOC — no new vocabulary (AC 7).
-- =====================================================================

select is(
  (select count(*)::bigint from pfin.tax_character),
  5::bigint,
  '(VOC1) pfin.tax_character still carries exactly 5 codes — 100 writes VALUES into it, never adds a row'
);

select is(
  to_regtype('pfin.tax_character_enum'),
  null::regtype,
  '(VOC2) pfin.tax_character_enum does NOT exist — a sixth value is a seed migration on 011''s registry table, never a CHECK/enum edit'
);

select * from finish();
rollback;
