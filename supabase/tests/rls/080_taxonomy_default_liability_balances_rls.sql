-- =====================================================================
-- Per-Wave battery — pfin.taxonomy_default seed delta (asset/Liabilities/
--   'Liability Balances') + the pfin.user_taxonomy backfill for already-
--   provisioned users (SELF-329, ADR-057 2nd instance — account-type-aware
--   cash routing, F/CTO-ratified 2026-08-17). No function, no policy, no
--   grant, no trigger — two INSERTs, structurally the 077 shape reused
--   verbatim for the second ADR-057 instance.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/080_taxonomy_default_liability_balances.sql
--   (1) pfin.taxonomy_default gains ONE global row: domain='asset',
--       cat='Liabilities', sub_cat='Liability Balances', tax_relevant=false,
--       tax_character=null, display_order=285. `on conflict (domain, cat,
--       sub_cat) do nothing`.
--   (2) pfin.user_taxonomy gains that same row PER ALREADY-PROVISIONED USER —
--       the backfill's user set is `select distinct users_id from
--       pfin.user_taxonomy`, taken WITHOUT a domain filter. `on conflict
--       (users_id, domain, cat, sub_cat) do nothing`.
-- Prereqs exercised (on the 001->080 stack): 009 (pfin.user_taxonomy, its
--   unique (users_id, domain, cat, sub_cat) — the backfill's conflict
--   target); 041 (pfin.taxonomy_default + its existence-guarded first-access
--   provisioning); 077 (the FIRST ADR-057 instance — this battery is its
--   structural twin, adapted, not re-derived from scratch).
--
-- ┌─ WHAT THIS BATTERY PROVES — identical shape to 077's, restated for THIS ┐
-- │ table's specific reach/idempotency/unreachability properties, per       │
-- │ ADR-057 applied rather than re-derived:                                 │
-- │  (a) IDEMPOTENCY ON RE-RUN — re-running BOTH statements a second time   │
-- │      adds no second row, for the global seed row OR any user's backfill│
-- │      row.                                                               │
-- │  (b) ZERO-ROW-USER-UNREACHABLE — a user with NO pfin.user_taxonomy rows │
-- │      at all receives NOTHING. LOAD-BEARING (080's header): reaching a   │
-- │      zero-row user would satisfy 041's existence guard and strand that  │
-- │      user with ONE Sub-Cat forever.                                     │
-- │  (c) DOMAIN-AGNOSTIC REACH — the user set carries no `domain=...`       │
-- │      filter. A user whose ONLY pre-existing row is CASHFLOW-domain is   │
-- │      still "already provisioned" and IS reached.                        │
-- │  (d) TENANT BINDING + NO CROSS-TENANT LANDING — every users_id written  │
-- │      is INHERITED from an existing row of the SAME table; proven under  │
-- │      real RLS context, not just a postgres-role structural count.       │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (080 authors no function, no policy,
--   no grant, no trigger, no FK-shaped column — read ADR-011 Decision 4 live).
--   Decision-3 family UNCHANGED — the backfill writes user_taxonomy.users_id,
--   that table's own tenant anchor, copied from an existing row of the same
--   table. This battery introduces no catalogued instance; it is the pgTAP
--   proof that a PRIVILEGED-CONTEXT WRITE (080's own §10 note: D1-adjacent,
--   meets (a)/(c), meets neither (b) nor (d)) stays scoped to the tenant it
--   inherits from.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '80' for this migration). No PII / no real account numbers / no
--   prod data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with
--   users_id set EXPLICITLY. Whole file in one rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE: tenant UUIDs resolve to psql literals via \set;
--   every _rls.set_tenant is called at role=postgres and each block restores
--   role=postgres before the next (071's convention).
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->080 against a postgres-owned scratch DB (NON-destructive; zero
--   cluster-level grants; `supabase db reset` never invoked). plan(14): 1
--   precondition (P1) + 2 reach (BF1-BF2) + 1 unreachable (BF3) + 1 no-leak
--   total (BF4) + 1 tenant-binding structural (BF5) + 1 contract-fields
--   structural (BF6) + 3 isolation (ISO1-ISO3) + 4 idempotency
--   (IDEM1-IDEM4) = 14 — same count as 077, same shape.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(14);

\set ta '00000000-0000-0000-0000-00000000a080'
\set tb '00000000-0000-0000-0000-00000000b080'
\set tc '00000000-0000-0000-0000-00000000c080'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- ---------------------------------------------------------------------
-- FIXTURE. Tenant A: "already-provisioned before 080" — pre-existing
--   ASSET-domain user_taxonomy rows, none of them the Liability Balances
--   row (080 already applied once against an EMPTY user_taxonomy when this
--   scratch DB was built, so no tenant here already carries it).
-- Tenant B: a brand-new, NEVER-provisioned user — ZERO user_taxonomy rows.
--   The reach-unreachable control (b).
-- Tenant C: "already-provisioned" via a CASHFLOW-domain row ONLY — the
--   domain-agnostic-reach control (c).
-- ---------------------------------------------------------------------
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values
  (:'ta','asset','Equity','US-06-Financials') returning id as a_eq \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values
  (:'ta','asset','Cash','CD') returning id as a_cd \gset
insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values
  (:'tc','cashflow','Revenue','Dividend') returning id as c_cf \gset
-- tenant B: deliberately NO rows.

-- =====================================================================
-- (P1) PRECONDITION — before any backfill re-run, NEITHER A nor C carries a
--   Liability Balances row yet.
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'
      and users_id in (:'ta', :'tc')),
  0::bigint,
  '(P1) precondition: neither A nor C carries a Liability Balances row before the backfill re-run'
);

-- =====================================================================
-- BACKFILL RE-RUN — 080's own two statements, verbatim, re-invoked. This is
-- the ONLY way to exercise the backfill against a non-empty user_taxonomy in
-- a scratch DB where 080 already ran once against zero users.
-- =====================================================================
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('asset', 'Liabilities', 'Liability Balances', false, null, 285,
   'Raw balance of a liability-type account — the catch-all for account-level '
   'debt. Asserts NO instrument: where the instrument IS known, the balance '
   'belongs in Credit-Balance (revolving credit), Loan-Balance (a loan) or '
   'EstTax-Pending (taxes due) instead. Naturally signed, so a balance owed is '
   'negative and an overpayment is positive.')
on conflict (domain, cat, sub_cat) do nothing;

insert into pfin.user_taxonomy
  (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select
  provisioned.users_id,
  d.domain, d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes
from pfin.taxonomy_default d
cross join (select distinct ut.users_id from pfin.user_taxonomy ut) provisioned
where d.domain = 'asset' and d.cat = 'Liabilities' and d.sub_cat = 'Liability Balances'
on conflict (users_id, domain, cat, sub_cat) do nothing;

-- =====================================================================
-- REACH (BF1-BF2) — (a)/(c): already-provisioned users, ONE via an asset-
--   domain row (A), ONE via a CASHFLOW-domain-only row (C, the domain-
--   agnostic-reach control).
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'ta' and domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(BF1) already-provisioned tenant A (asset-domain prior rows) receives exactly ONE Liability Balances row from the backfill re-run'
);
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'tc' and domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(BF2) DOMAIN-AGNOSTIC REACH: tenant C, whose ONLY pre-existing row is CASHFLOW-domain, is still "already provisioned" and receives exactly ONE Liability Balances row'
);

-- =====================================================================
-- (BF3) UNREACHABLE (b) — the load-bearing restriction. Tenant B has ZERO
--   pre-existing rows and MUST have ZERO rows after the backfill too.
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'tb'),
  0::bigint,
  '(BF3) ⭐ zero-row-user-unreachable: tenant B (no pre-existing user_taxonomy rows) receives NOTHING from the backfill — still ZERO rows total, not stranded with one Liability Balances row (041''s existence guard would otherwise skip B forever)'
);

-- =====================================================================
-- (BF4) NO-LEAK TOTAL (d) — exactly TWO Liability Balances rows exist
--   cluster-wide after the re-run (A + C), scoped at role=postgres,
--   structural.
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy
    where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  2::bigint,
  '(BF4) no-leak total: exactly 2 Liability Balances rows exist (A + C) after the backfill re-run — no stray row for B or any other users_id'
);

-- =====================================================================
-- (BF5) TENANT BINDING INHERITED CORRECTLY (d) — A''s Liability Balances
--   row''s users_id is A, not NULL and not another tenant.
-- =====================================================================
select is(
  (select users_id from pfin.user_taxonomy
    where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances' and users_id = :'ta'),
  :'ta'::uuid,
  '(BF5) tenant binding inherited correctly: A''s backfilled Liability Balances row carries users_id = A exactly'
);

-- =====================================================================
-- (BF6) CONTRACT FIELDS — the backfilled row''s non-key columns match
--   pfin.taxonomy_default''s seeded contract, including display_order=285
--   (deliberately BELOW the existing Liabilities floor of 290/300/310, the
--   077 idiom — "first among Liabilities without renumbering a single
--   existing row").
-- =====================================================================
select ok(
  (select tax_relevant = false and tax_character is null and display_order = 285
     from pfin.user_taxonomy
    where users_id = :'ta' and domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  '(BF6) A''s backfilled row carries the taxonomy_default contract: tax_relevant=false, tax_character IS NULL, display_order=285'
);

-- =====================================================================
-- ISOLATION (ISO1-ISO3) — the two-tenant cross-tenant proof, under REAL RLS
--   context (SECURITY §4.5), not merely a postgres-role structural count.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy
    where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(ISO1) under RLS as tenant A: sees exactly its OWN Liability Balances row'
);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy
     where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances' and users_id = :'tc'
  ),
  '(ISO2) under RLS as tenant A: C''s Liability Balances row is NOT visible — cross-tenant read fails closed'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tc'::uuid);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy
     where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances' and users_id = :'ta'
  ),
  '(ISO3) under RLS as tenant C (reverse direction): A''s Liability Balances row is NOT visible'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- IDEMPOTENCY (IDEM1-IDEM4) — re-run BOTH statements a SECOND time. No
-- second row for A, none for C, none for the global seed row, and B stays
-- unreachable across repeated runs (not just a single one).
-- =====================================================================
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('asset', 'Liabilities', 'Liability Balances', false, null, 285,
   'Raw balance of a liability-type account — the catch-all for account-level '
   'debt. Asserts NO instrument: where the instrument IS known, the balance '
   'belongs in Credit-Balance (revolving credit), Loan-Balance (a loan) or '
   'EstTax-Pending (taxes due) instead. Naturally signed, so a balance owed is '
   'negative and an overpayment is positive.')
on conflict (domain, cat, sub_cat) do nothing;

insert into pfin.user_taxonomy
  (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
select
  provisioned.users_id,
  d.domain, d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes
from pfin.taxonomy_default d
cross join (select distinct ut.users_id from pfin.user_taxonomy ut) provisioned
where d.domain = 'asset' and d.cat = 'Liabilities' and d.sub_cat = 'Liability Balances'
on conflict (users_id, domain, cat, sub_cat) do nothing;

select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'ta' and domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(IDEM1) idempotent on re-run: A''s Liability Balances row count stays exactly 1 after a second invocation'
);
select is(
  (select count(*) from pfin.user_taxonomy
    where users_id = :'tc' and domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(IDEM2) idempotent on re-run: C''s Liability Balances row count stays exactly 1 after a second invocation'
);
select is(
  (select count(*) from pfin.taxonomy_default
    where domain='asset' and cat='Liabilities' and sub_cat='Liability Balances'),
  1::bigint,
  '(IDEM3) idempotent on re-run: the GLOBAL taxonomy_default seed row stays exactly 1 (the `on conflict (domain, cat, sub_cat)` target) after a second invocation'
);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'tb'),
  0::bigint,
  '(IDEM4) unreachability holds across repeated runs, not just one: B is STILL zero rows after the second invocation'
);

select * from finish();
rollback;
