-- =====================================================================
-- Per-Wave battery — pfin.taxonomy_default seed delta (asset/Cash/'Cash Balances')
--   + the pfin.user_taxonomy backfill for already-provisioned users (SELF-311 /
--   BACKLOG §7.20 item 1, the L1 cash-granularity ruling). No function, no
--   policy, no grant, no trigger — two INSERTs and one `comment on table`.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/077_taxonomy_default_cash_balances.sql
--   (1) pfin.taxonomy_default gains ONE global row: domain='asset', cat='Cash',
--       sub_cat='Cash Balances', tax_relevant=false, tax_character=null,
--       display_order=5. `on conflict (domain, cat, sub_cat) do nothing`.
--   (2) pfin.user_taxonomy gains that same row PER ALREADY-PROVISIONED USER —
--       the backfill's user set is `select distinct users_id from
--       pfin.user_taxonomy`, taken WITHOUT a domain filter. `on conflict
--       (users_id, domain, cat, sub_cat) do nothing`.
-- Prereqs exercised (on the 001->077 stack): 009 (pfin.user_taxonomy, its
--   unique (users_id, domain, cat, sub_cat) — the backfill's conflict target);
--   041 (pfin.taxonomy_default + its existence-guarded first-access
--   provisioning, the reason an already-provisioned user is NOT reached by
--   anything else).
--
-- ┌─ WHAT THIS BATTERY PROVES — the two properties 077's header names as    ┐
-- │ load-bearing, neither of which a totals-only or single-run battery      │
-- │ would catch: 077's own INSERTs are idempotent by construction (ON       │
-- │ CONFLICT DO NOTHING), so simply asserting "the row exists after 077     │
-- │ ran once" says nothing about a SECOND run, and the migration itself was │
-- │ already applied once (with zero users_id in the DB) by the time this    │
-- │ battery's txn opens — so re-invoking 077's own two statements is the    │
-- │ only way to exercise the backfill against a NON-EMPTY user_taxonomy.    │
-- │  (a) IDEMPOTENCY ON RE-RUN — re-running BOTH statements a second time   │
-- │      adds no second row, for the global seed row OR any user's backfill│
-- │      row.                                                               │
-- │  (b) ZERO-ROW-USER-UNREACHABLE — a user with NO pfin.user_taxonomy rows │
-- │      at all receives NOTHING. This is the LOAD-BEARING restriction      │
-- │      (077's header, ⚠ THE RESTRICTION IS LOAD-BEARING NOT A FILTER FOR  │
-- │      TIDINESS): reaching a zero-row user would satisfy 041's existence  │
-- │      guard and strand that user with ONE Sub-Cat forever.               │
-- │  (c) STORAGE-SCOPED BY CONSTRUCTION, POST-084 (was DOMAIN-AGNOSTIC REACH │
-- │      pre-split — RETARGET-WITH-NARROWING, queued for Sec confirm at the │
-- │      merge-gate joint-review; not yet ratified as a pure strengthening).│
-- │      ⚠ LOSING SIDE, named per the replacement-control rule: pre-084 the │
-- │      backfill's user set (`select distinct users_id from                │
-- │      pfin.user_taxonomy`) reached a user via EITHER domain, because the │
-- │      derivation carried no domain filter and the table held both. Post- │
-- │      084 `user_taxonomy` is asset-only BY CONSTRUCTION, so the SAME     │
-- │      derivation can only ever see storage-side users — a user whose ONLY│
-- │      prior row was cashflow-domain (now living in posting_prototype) is │
-- │      NO LONGER "already provisioned" by this check, and receives the    │
-- │      Cash Balances row a SECOND time on their next backfill pass rather │
-- │      than being correctly skipped. What is LOST: recognizing a user     │
-- │      provisioned via EITHER table. What replaces it: a narrower, still- │
-- │      correct claim scoped to the storage side only. Tenant C below now  │
-- │      demonstrates the NARROWING (Sec F10, BACKLOG §7.24 item 5,         │
-- │      independently re-derived from the battery side), not a reach.      │
-- │  (d) TENANT BINDING + NO CROSS-TENANT LANDING — every users_id written  │
-- │      is INHERITED from an existing row of the SAME table; the fixture   │
-- │      proves it lands on the RIGHT tenant and that no tenant sees        │
-- │      another's backfilled row, under real RLS context (not just a       │
-- │      postgres-role structural count).                                   │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (077 authors no function, no policy,
--   no grant, no trigger, no FK-shaped column — read ADR-011 Decision 4 live).
--   Decision-3 family UNCHANGED — the backfill writes user_taxonomy.users_id,
--   that table's own tenant anchor, copied from an existing row of the same
--   table; no second anchor exists to mismatch. This battery introduces no
--   catalogued instance; it is the pgTAP proof that a PRIVILEGED-CONTEXT WRITE
--   (077's own §10 note) stays scoped to the tenant it inherits from.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '77' for this migration). No PII / no real account numbers / no
--   prod data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with
--   users_id set EXPLICITLY. Whole file in one rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE: tenant UUIDs resolve to psql literals via \set;
--   every _rls.set_tenant is called at role=postgres and each block restores
--   role=postgres before the next (071's convention).
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->077 against a scratch DB (NON-destructive; `supabase db reset` never
--   invoked). RE-VERIFIED against 001->084 (ADR-058's split; tenant D added,
--   BF2/BF4/IDEM2/ISO2-3 re-derived per the STORAGE-SCOPING narrowing — see
--   the ⚠ LOSING SIDE box above). plan(14): 1 precondition (P1) + 2 reach/scoping (BF1-BF2) + 1 unreachable
--   (BF3) + 1 no-leak total (BF4) + 1 tenant-binding structural (BF5) + 1
--   contract-fields structural (BF6) + 3 isolation (ISO1-ISO3) + 4 idempotency
--   (IDEM1-IDEM4) = 14.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(14);

\set ta '00000000-0000-0000-0000-00000000a077'
\set tb '00000000-0000-0000-0000-00000000b077'
\set tc '00000000-0000-0000-0000-00000000c077'
\set td '00000000-0000-0000-0000-00000000d077'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td');

-- ---------------------------------------------------------------------
-- FIXTURE. Tenant A: "already-provisioned before 077" — some pre-existing
--   ASSET-domain user_taxonomy rows, none of them the Cash Balances row (077
--   already applied once against an EMPTY user_taxonomy when this scratch DB
--   was built, so no tenant here already carries it).
-- Tenant B: a brand-new, NEVER-provisioned user — ZERO user_taxonomy rows.
--   The reach-unreachable control (b).
-- Tenant C, POST-084: "already-provisioned" via a row that now lives in
--   pfin.posting_prototype ONLY (the cashflow half of the split) — the
--   STORAGE-SCOPING control (c), see the ⚠ LOSING SIDE box above. Pre-084
--   this proved domain-agnostic reach; post-084 it proves the opposite.
-- Tenant D, NEW at 084: a second storage-side ("asset") already-provisioned
--   user, added so ISO1-ISO3's cross-tenant isolation proof still has a real
--   second OWNER of a backfilled row to check against — C no longer receives
--   one, so asserting isolation against C's (now-absent) row would be
--   vacuous (DESIGN.md: "absence assertions are vacuous whenever the subject
--   never existed").
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'ta','Marketable Securities','US-06-Financials') returning id as a_eq \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'ta','Real Estate','Residential') returning id as a_re \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat) values
  (:'tc','Revenue','Dividend') returning id as c_cf \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat) values
  (:'td','Real Estate','Residential-D') returning id as d_re \gset
-- tenant B: deliberately NO rows.

-- =====================================================================
-- (P1) PRECONDITION — before any backfill re-run, NEITHER A nor C carries a
--   Cash Balances row yet (asserted separately from the result per DESIGN.md
--   rule 3 — the "after" assertions below would be vacuous if this were false).
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where cat='Cash' and sub_cat='Cash Balances'
      and users_id in (:'ta', :'td')),
  0::bigint,
  '(P1) precondition: neither A nor D carries a Cash Balances row before the backfill re-run'
);

-- =====================================================================
-- BACKFILL RE-RUN — 077's own two statements, RE-DERIVED at 084 (the `domain`
-- column and its predicate/conjunct are GONE from both tables by the time this
-- battery executes — 001..084 apply in order, and 084 drops it after 077's own
-- historical DDL already ran). This is the ONLY way to exercise the backfill
-- against a non-empty user_taxonomy in a scratch DB where 077 already ran once
-- against zero users.
-- =====================================================================
insert into pfin.taxonomy_default
  (cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('Cash', 'Cash Balances', false, null, 5,
   'Raw cash balance catch-all — one classification per user per currency. '
   'Asserts NO insurance regime and names no instrument: cash covered by a '
   'specific regime or held as a specific instrument belongs in FDIC / SPIC / '
   'T-Bill / CD instead.')
on conflict (cat, sub_cat) do nothing;

insert into pfin.user_taxonomy
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes
from pfin.taxonomy_default d
cross join (select distinct ut.users_id from pfin.user_taxonomy ut) provisioned
where d.cat = 'Cash' and d.sub_cat = 'Cash Balances'
on conflict (users_id, cat, sub_cat) do nothing;

-- =====================================================================
-- REACH (BF1) / STORAGE-SCOPING (BF2) — (a)/(c): A (asset-domain prior rows)
--   is reached; C (posting_prototype-only prior row) is NOT — see the ⚠
--   LOSING SIDE box above.
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'ta' and cat='Cash' and sub_cat='Cash Balances'),
  1::bigint,
  '(BF1) already-provisioned tenant A (asset-domain prior rows) receives exactly ONE Cash Balances row from the backfill re-run'
);
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'tc' and cat='Cash' and sub_cat='Cash Balances'),
  0::bigint,
  '(BF2) POST-084 STORAGE-SCOPING (was DOMAIN-AGNOSTIC REACH): tenant C, whose ONLY pre-existing row now lives in posting_prototype, is NOT reached — the backfill''s user-set derivation reads user_taxonomy only, which is asset-only by construction. C receives ZERO Cash Balances rows and will be re-offered one on every future backfill pass (Sec F10) — a narrowing this file records rather than hides'
);

-- =====================================================================
-- (BF3) UNREACHABLE (b) — the load-bearing restriction. Tenant B has ZERO
--   pre-existing rows and MUST have ZERO rows after the backfill too — not
--   one Cash Balances row and nothing else, which would satisfy 041's
--   existence guard and strand B with a single Sub-Cat forever.
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'tb'),
  0::bigint,
  '(BF3) ⭐ zero-row-user-unreachable: tenant B (no pre-existing user_taxonomy rows) receives NOTHING from the backfill — still ZERO rows total, not stranded with one Cash Balances row (041''s existence guard would otherwise skip B forever)'
);

-- =====================================================================
-- (BF4) NO-LEAK TOTAL (d), RE-DERIVED POST-084 — exactly TWO Cash Balances
--   rows exist cluster-wide after the re-run: A (BF1) and D (both asset-
--   domain already-provisioned before the backfill re-run fires) — NOT C,
--   which no longer qualifies (BF2), and NOT B (BF3, never provisioned).
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where cat='Cash' and sub_cat='Cash Balances'),
  2::bigint,
  '(BF4) no-leak total, POST-084: exactly 2 Cash Balances rows exist (A + D, both storage-side already-provisioned) after the backfill re-run — NOT C (see BF2), no stray row for B or any other users_id'
);

-- =====================================================================
-- (BF5) TENANT BINDING INHERITED CORRECTLY (d) — A''s Cash Balances row''s
--   users_id is A, not NULL and not another tenant.
-- =====================================================================
select is(
  (select users_id from pfin.user_taxonomy
    where cat='Cash' and sub_cat='Cash Balances' and users_id = :'ta'),
  :'ta'::uuid,
  '(BF5) tenant binding inherited correctly: A''s backfilled Cash Balances row carries users_id = A exactly'
);

-- =====================================================================
-- (BF6) CONTRACT FIELDS — the backfilled row''s non-key columns match
--   pfin.taxonomy_default''s seeded contract (values are SELECTed from the
--   default table, never hardcoded — this proves they actually copied).
-- =====================================================================
select ok(
  (select tax_relevant = false and tax_character is null and display_order = 5
     from pfin.user_taxonomy
    where users_id = :'ta' and cat='Cash' and sub_cat='Cash Balances'),
  '(BF6) A''s backfilled row carries the taxonomy_default contract: tax_relevant=false, tax_character IS NULL, display_order=5'
);

-- =====================================================================
-- ISOLATION (ISO1-ISO3), RE-TARGETED to tenant D (was C pre-084 — C no longer
--   receives a Cash Balances row at all post-split, per BF2, so asserting
--   cross-tenant "not exists" against C's row would be vacuous: DESIGN.md's
--   own rule, "absence assertions are vacuous whenever the subject never
--   existed." D is a genuine second OWNER instead.) Under REAL RLS context
--   (SECURITY §4.5), not merely a postgres-role structural count.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy
    where cat='Cash' and sub_cat='Cash Balances'),
  1::bigint,
  '(ISO1) under RLS as tenant A: sees exactly its OWN Cash Balances row'
);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy
     where cat='Cash' and sub_cat='Cash Balances' and users_id = :'td'
  ),
  '(ISO2) under RLS as tenant A: D''s Cash Balances row is NOT visible — cross-tenant read fails closed'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'td'::uuid);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy
     where cat='Cash' and sub_cat='Cash Balances' and users_id = :'ta'
  ),
  '(ISO3) under RLS as tenant D (reverse direction): A''s Cash Balances row is NOT visible'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- IDEMPOTENCY (IDEM1-IDEM4), RE-DERIVED POST-084 — re-run BOTH statements a
-- SECOND time (domain column/predicate gone, same as the first run above). No
-- second row for A, C STAYS at zero (not "stays at one" — POST-084 C never
-- had one to begin with, see BF2), none for the global seed row, and B stays
-- unreachable across repeated runs (not just a single one).
-- =====================================================================
insert into pfin.taxonomy_default
  (cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('Cash', 'Cash Balances', false, null, 5,
   'Raw cash balance catch-all — one classification per user per currency. '
   'Asserts NO insurance regime and names no instrument: cash covered by a '
   'specific regime or held as a specific instrument belongs in FDIC / SPIC / '
   'T-Bill / CD instead.')
on conflict (cat, sub_cat) do nothing;

insert into pfin.user_taxonomy
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes
from pfin.taxonomy_default d
cross join (select distinct ut.users_id from pfin.user_taxonomy ut) provisioned
where d.cat = 'Cash' and d.sub_cat = 'Cash Balances'
on conflict (users_id, cat, sub_cat) do nothing;

select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'ta' and cat='Cash' and sub_cat='Cash Balances'),
  1::bigint,
  '(IDEM1) idempotent on re-run: A''s Cash Balances row count stays exactly 1 after a second invocation'
);
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'tc' and cat='Cash' and sub_cat='Cash Balances'),
  0::bigint,
  '(IDEM2) POST-084: C STAYS at zero across a second invocation too — C never qualifies (BF2), not "stays at one" as it did pre-084'
);
select is(
  (select count(*) from pfin.taxonomy_default
    where cat='Cash' and sub_cat='Cash Balances'),
  1::bigint,
  '(IDEM3) idempotent on re-run: the GLOBAL taxonomy_default seed row stays exactly 1 (the `on conflict (cat, sub_cat)` target) after a second invocation'
);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'tb'),
  0::bigint,
  '(IDEM4) unreachability holds across repeated runs, not just one: B is STILL zero rows after the second invocation'
);

select * from finish();
rollback;
