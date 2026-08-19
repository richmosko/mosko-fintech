-- =====================================================================
-- Per-Wave battery — pfin.taxonomy_default + pfin.user_taxonomy asset-domain
--   Cat rename 'Equity' -> 'Marketable Securities'. ADR-058 Decision 7,
--   F/CTO-ratified 2026-08-18, first of the three GL-split PRs. A LABEL
--   CHANGE, NOT A RE-KEY: no id moves, no row is created or destroyed, no
--   column is added or dropped. No function, no policy, no grant, no
--   trigger — two UPDATE statements, structurally the 080 D1-adjacent
--   privileged-migration-write shape, applied to a rename instead of a
--   backfill.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/082_taxonomy_rename_marketable_securities.sql
--   (1) pfin.taxonomy_default: set cat='Marketable Securities' where
--       domain='asset' and cat='Equity'. Global template — already applied
--       for real against the seeded 65-row set by the time this file runs.
--   (2) pfin.user_taxonomy: same predicate, same assignment — the
--       ADR-057 REACH half for already-provisioned users. Applied for real
--       against ZERO rows at chain-apply time (no synthetic users exist
--       yet in a fresh migration-only DB), so its REACH property is
--       UNEXERCISED by the real apply and can only be proven here by
--       REPLAY (080's own precedent: "the ONLY way to exercise the
--       backfill against a non-empty user_taxonomy in a scratch DB where
--       [it] already ran once against zero users").
--   083 (the 009 comment-on-table supersession, same PR) ships NO battery:
--   comment-only, no DDL, no policy, no data change — same convention as
--   075 (no battery file exists for it either).
--
-- ┌─ WHAT THIS BATTERY PROVES ───────────────────────────────────────────┐
-- │ (a) SEEDED STATE — the real, already-migrated taxonomy_default: zero  │
-- │     asset-domain 'Equity' rows remain, exactly 15 asset-domain        │
-- │     'Marketable Securities' rows exist, and every row-count total is  │
-- │     unchanged (65 / 38 asset / 27 cashflow) — a rename creates and    │
-- │     destroys nothing.                                                 │
-- │ (b) REACH (replay) — an already-provisioned tenant's asset-domain     │
-- │     'Equity' row is renamed by statement 2's exact predicate, with    │
-- │     its `id` UNCHANGED (the "label change, not a re-key" claim,       │
-- │     proven rather than asserted).                                     │
-- │ (c) THE FENCE THAT MATTERS — the `domain = 'asset'` conjunct is a     │
-- │     REAL filter, not decorative: a same-tenant asset-domain row under │
-- │     a DIFFERENT Cat ('Bonds') is untouched, and — the hazard 082's    │
-- │     own header names as the worst-case failure — a same-tenant        │
-- │     CASHFLOW-domain row carrying the SAME literal 'Equity' (028's GL  │
-- │     accounting class) is untouched. INVERSION-PROVE: replaying the    │
-- │     statement WITHOUT the domain conjunct is REJECTED — not a silent  │
-- │     corruption, a CHECK-constraint abort (028's                       │
-- │     user_taxonomy_cashflow_class_chk, a SECOND independent fence —    │
-- │     see SECTION C) — proving (c)'s pass is a real fence and not a     │
-- │     vacuous one.                                                      │
-- │ (d) TWO-TENANT ISOLATION — under REAL RLS context (not a postgres-    │
-- │     role structural count), each tenant sees only its own renamed     │
-- │     row; cross-tenant reads fail closed in both directions.           │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- ⚠ QA DECISION (Architect's flagged item, ADR-058 Decision 7 package —
--   HISTORICAL, kept for record; `080_taxonomy_default_liability_balances_rls.sql:92`
--   was the citation at authoring time and its own N2-sweep patch has since
--   renamed that row to ''Marketable Securities'' too, same as this file's own
--   fixture literals): NOT touching that file. Every "does the legacy label
--   remain" leg below is scoped to (i) `pfin.taxonomy_default`, the seeded/global
--   table with no runtime writer, or (ii) THIS FILE'S OWN fixture tenants
--   (ta/tb), never to an unscoped `count(*) from pfin.user_taxonomy`. Two
--   independent reasons, either alone sufficient: (1) each battery file
--   runs in its own `begin…rollback` transaction (pg_prove: one file, one
--   connection), so another file's fixture row cannot be live when this file
--   runs regardless; (2) even if cross-file leakage were possible,
--   `pfin.user_taxonomy` is a tenant-WRITABLE table — a real user can
--   author a Cat value matching any string at all — so a global unscoped
--   "zero rows anywhere" assertion on it is inherently the wrong shape,
--   independent of transaction isolation. A per-leg edit to another file's
--   fixture would be a global edit to that file for a problem this scoping
--   avoids without one.
--
-- §10 / DECISION 3 (Path B — ADR-011 Decision 4 REFERENCED, not restated;
--   read live before drafting, no count/enumeration carried here, matching
--   082's own migration header). This battery introduces zero catalogued
--   §10 instances (no credential surface, no code-layer fence, no
--   network/config surface) and proves no NEW mechanism — it is the pgTAP
--   proof that a D1-ADJACENT privileged-context write (082's own §10 note:
--   meets (a)/(c), meets neither (b) nor (d), same class as 080) stays
--   scoped to the Cat value it renames and does not cross the domain
--   boundary. LEDGER STATUS: FLAT. Decision-3 family: family UNCHANGED
--   (+0) — no column created/altered/dropped, no id read or written by
--   082 itself; this battery's fixture rows carry no FK-shaped column
--   either (domain/cat/sub_cat are plain text, not references).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw
--   literals, suffixed '082' for this migration, mirroring 080's idiom).
--   No PII / no real account numbers / no prod data. All fixture rows
--   PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set
--   EXPLICITLY. Whole file in one rolled-back txn.
--
-- ⚠ HARDCODE-VS-DYNAMIC (041's rule, applied here without re-deriving it):
--   the seeded-state counts below (65 total / 38 asset / 27 cashflow / 15
--   Marketable Securities / 0 Equity) are HARDCODED against the
--   MIGRATION-SEEDED TRUTH (ADR-058 Decision 7's own re-measurement at
--   authoring), not derived via a self-referential `count(*)` comparison —
--   a dynamic total here would be a tautology that can never go RED
--   (DESIGN.md §8 rule 5). The next seed delta under `domain='asset'`
--   re-counts and updates these five sites + this header, the same way
--   077/080 did for 041's battery.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 convention): `_rls` grants no USAGE to
--   authenticated; tenant UUIDs resolve to psql literals via `\set`; every
--   `_rls.set_tenant` call happens at role=postgres and each block
--   restores role=postgres before the next.
--
-- ⚠ SAVEPOINT / PLAN-COUNTER HARNESS NOTE (DESIGN.md, `058`'s finding): a
--   MANUAL `rollback to savepoint` wrapping a PASSED pgTAP assertion
--   rewinds the plan counter while the emitted TAP numbering marches on.
--   Does not apply here: the INVERSION-PROVE leg uses `throws_like`, which
--   wraps its own probe in pgTAP's internal sub-transaction (041's bare
--   (2a)/(5b)/(5d) precedent, no manual savepoint) — the file uses no
--   manual `savepoint`/`rollback to savepoint` at all.
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified via pg_prove (TAP-aware —
--   never bare psql) against a postgres-owned scratch DB carrying the full
--   001->083 migration chain (non-destructive; `supabase db reset` never
--   invoked). RE-VERIFIED against 001->084 (ADR-058's split — S1-S5/R1-R6/
--   ISO1-3/INV1/CONFIRM all re-derived for the domain-column drop and the
--   cashflow-control-row retarget to posting_prototype; amended in place per
--   the batteries-are-freely-editable §7.16 precedent, not a fresh file).
--   plan(16): 5 seeded-state (S1-S5) + 6 reach/control (R1-R6) +
--   3 isolation (ISO1-ISO3) + 2 inversion (INV1 + CONFIRM) = 16. GREEN,
--   16/16, `pg_prove` exit 0 against BOTH the 001->083 and the 001->084 stack.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(16);

\set ta '00000000-0000-0000-0000-00000000a082'
\set tb '00000000-0000-0000-0000-00000000b082'

insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- SECTION A (S1-S5) — SEEDED STATE. The real taxonomy_default table, as
--   already migrated by the 001->083 chain. No replay needed here: the
--   rename already ran for real against this table's seeded rows.
-- =====================================================================

-- (S1) MECH POST-084: domain predicate dropped — taxonomy_default is asset-only.
select is(
  (select count(*) from pfin.taxonomy_default where cat = 'Equity')::bigint,
  0::bigint,
  '(S1) taxonomy_default: zero ''Equity'' rows remain after the rename'
);

-- (S2) MECH POST-084: domain predicate dropped.
select is(
  (select count(*) from pfin.taxonomy_default where cat = 'Marketable Securities')::bigint,
  15::bigint,
  '(S2) taxonomy_default: exactly 15 ''Marketable Securities'' rows (the renamed 041 set) exist'
);

-- (S3) RE-DERIVED POST-084: was "taxonomy_default total STILL 65" (pre-split, one
--      table). Post-split that total no longer lives in one table — RETARGET to
--      the split-total invariant: no row was lost crossing the split.
select is(
  (select (select count(*) from pfin.taxonomy_default) + (select count(*) from pfin.posting_prototype_default))::bigint,
  65::bigint,
  '(S3) SPLIT-TOTAL INVARIANT: taxonomy_default + posting_prototype_default together still total 65 — the split redistributes rows across two tables, it does not create or destroy any (was: "taxonomy_default total STILL 65", meaningless as a single-table claim post-084)'
);

-- (S4) MECH POST-084: the whole table is asset-domain by construction now.
select is(
  (select count(*) from pfin.taxonomy_default)::bigint,
  38::bigint,
  '(S4) taxonomy_default: total row count is 38 (asset-only post-split) — the rename reassigns `cat`, it does not change row cardinality'
);

-- (S5) RETARGET POST-084: table changes from taxonomy_default WHERE
--      domain='cashflow' to posting_prototype_default with no predicate — proves
--      the SAME coverage-identical claim via table identity instead of a WHERE.
select is(
  (select count(*) from pfin.posting_prototype_default)::bigint,
  27::bigint,
  '(S5) posting_prototype_default: total row count is 27, entirely untouched by the rename — table identity now keeps 028''s cashflow-class ''Equity'' out of scope (was: a domain=''cashflow'' filter on the same table the rename touched)'
);

-- =====================================================================
-- SECTION B (R1-R6) — REACH (replay). pfin.user_taxonomy is empty going
--   into this file (each battery file is its own connection/transaction;
--   every earlier file's fixtures were rolled back with it), so statement
--   2's REACH property was NEVER exercised for real by the migration chain
--   apply. REPLAY it here, verbatim, against synthetic already-provisioned
--   fixture rows — 080's own precedent for exercising a REACH statement
--   against non-empty state in a scratch DB.
-- =====================================================================

-- FIXTURE — two already-provisioned tenants, PRIVILEGED (role=postgres).
--   A carries THREE rows: the rename target, a same-domain DIFFERENT-Cat
--   control (proves the `cat='Equity'` conjunct, not "any asset row"), and
--   a cashflow-domain SAME-LITERAL control (proves the `domain='asset'`
--   conjunct — the GL-class-collision hazard 082's header names as the
--   worst-case failure of a blind sweep). B carries ONE row: the rename
--   target only, a second independent tenant proving reach is a property
--   of the WHERE clause, not an accident of A's specific setup.
insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'ta', 'Equity', 'REPLAY-Sector') returning id as a_eq_id \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'ta', 'Bonds', 'REPLAY-Control') returning id as a_bonds_id \gset
-- POST-084: the cashflow control now lives in pfin.posting_prototype (ADR-058
--   Decision 1's split), not pfin.user_taxonomy — see (R5)'s reworked mechanism below.
insert into pfin.posting_prototype (users_id, cat, sub_cat)
  values (:'ta', 'Equity', 'REPLAY-CF-Control') returning id as a_cf_id \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'tb', 'Equity', 'REPLAY-Sector-B') returning id as b_eq_id \gset

-- (R1) MECH POST-084: domain predicate dropped.
select is(
  (select count(*) from pfin.user_taxonomy
    where cat = 'Equity' and users_id in (:'ta', :'tb'))::bigint,
  2::bigint,
  '(R1) precondition: exactly 2 ''Equity'' fixture rows exist (A''s and B''s rename targets) before the replay'
);

-- REPLAY — 082's own statement 2, RE-DERIVED POST-084: the `domain` column is
--   gone from user_taxonomy by the time this battery executes (001..084 apply in
--   order; 084 drops it after 082's own historical DDL already ran). Table
--   identity now does what the domain conjunct used to — the cashflow control
--   (a_cf_id) simply isn't in this table to be reached, regardless of predicate.
update pfin.user_taxonomy
   set cat = 'Marketable Securities'
 where cat    = 'Equity';

-- (R2) A's rename target: renamed, id/domain/sub_cat UNCHANGED — "label
--      change, not a re-key," proven rather than asserted.
select ok(
  (select id = :a_eq_id and sub_cat = 'REPLAY-Sector' and cat = 'Marketable Securities'
     from pfin.user_taxonomy where id = :a_eq_id),
  '(R2) A''s rename-target row: cat -> ''Marketable Securities'', id/sub_cat UNCHANGED — a label change, not a re-key'
);

-- (R3) B's rename target: same shape, a SECOND independent tenant — reach
--      is a property of the WHERE clause, not an accident of A's setup.
select ok(
  (select id = :b_eq_id and sub_cat = 'REPLAY-Sector-B' and cat = 'Marketable Securities'
     from pfin.user_taxonomy where id = :b_eq_id),
  '(R3) B''s rename-target row: cat -> ''Marketable Securities'', id/sub_cat UNCHANGED — reach holds for a second, independent tenant'
);

-- (R4) CONTROL — DIFFERENT Cat ('Bonds'): UNTOUCHED. Proves `cat='Equity'` is a
--      real filter, not "any row."
select ok(
  (select id = :a_bonds_id and cat = 'Bonds' and sub_cat = 'REPLAY-Control'
     from pfin.user_taxonomy where id = :a_bonds_id),
  '(R4) CONTROL: A''s ''Bonds'' row is completely untouched — the `cat=''Equity''` conjunct is a real filter, not a blanket rename'
);

-- (R5) CONTROL, RETARGETED POST-084 — cashflow-domain, SAME literal 'Equity'
--      (028's GL accounting class): UNTOUCHED. Pre-084 this was proven by a
--      `domain='asset'` conjunct in a SHARED table; post-084 the proof mechanism
--      is TABLE IDENTITY — a_cf_id lives in pfin.posting_prototype, which the
--      REPLAY statement (scoped to pfin.user_taxonomy) cannot reach at all,
--      regardless of predicate. Same property (Decision 5 Finding (b)), stronger
--      mechanism — THE load-bearing proof from 082's own header: "two different
--      labels spelled identically."
select ok(
  (select cat = 'Equity' and sub_cat = 'REPLAY-CF-Control'
     from pfin.posting_prototype where id = :a_cf_id),
  '(R5) ⭐ CONTROL: A''s cashflow ''Equity'' row (028''s GL accounting class, the SAME literal string) is completely untouched — post-084 it lives in a DIFFERENT TABLE from the rename target, so table identity alone prevents the corruption (was: proven by a `domain=''asset''` conjunct in a shared table)'
);

-- (R6) MECH POST-084: domain predicate dropped.
select is(
  (select count(*) from pfin.user_taxonomy
    where cat = 'Equity' and users_id in (:'ta', :'tb'))::bigint,
  0::bigint,
  '(R6) no-leak total: zero ''Equity'' rows remain among the fixture tenants after the replay'
);

-- =====================================================================
-- ISOLATION (ISO1-ISO3) — two-tenant proof under REAL RLS context (SECURITY
--   §4.5), not merely a postgres-role structural count.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.user_taxonomy where cat = 'Marketable Securities'),
  1::bigint,
  '(ISO1) under RLS as tenant A: sees exactly its OWN renamed Marketable Securities row'
);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy where cat = 'Marketable Securities' and users_id = :'tb'
  ),
  '(ISO2) under RLS as tenant A: B''s renamed row is NOT visible — cross-tenant read fails closed'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select ok(
  not exists (
    select 1 from pfin.user_taxonomy where cat = 'Marketable Securities' and users_id = :'ta'
  ),
  '(ISO3) under RLS as tenant B (reverse direction): A''s renamed row is NOT visible'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- SECTION C — INVERSION-PROVE, RE-DERIVED POST-084 (the fence has teeth, not
--   just a pass). PRE-084 this replayed the rename statement without its
--   `domain='asset'` conjunct, against a SHARED table, to show 028's CHECK was
--   a real second fence. POST-084 that exact replay is no longer meaningful:
--   the REPLAY step above already dropped the domain conjunct (084 removed the
--   column, so there IS no conjunct to drop) and by this point in the file every
--   remaining 'Equity' row in user_taxonomy has ALREADY been renamed — a second
--   identical UPDATE would just silently touch 0 rows, not raise, which is a
--   WEAKER and DIFFERENT finding than this leg exists to prove.
--
--   RE-DESIGNED around the two-table world's analogous mistake: a migration
--   author reaches for the WRONG TABLE (posting_prototype, thinking "that's
--   where a cashflow-tagged 'Equity' row would live") and tries the same rename
--   there. `throws_like` wraps the probe in pgTAP's OWN internal sub-transaction
--   (041's precedent — no manual savepoint needed).
-- =====================================================================

-- (INV1) RE-DERIVED: the analogous mistake in a two-table world — running the
--        rename against posting_prototype instead of user_taxonomy — RAISES.
--        posting_prototype's own unconditional CHECK rejects 'Marketable
--        Securities' as a cat value (not a member of the accounting-class enum).
select throws_like(
  $$ update pfin.posting_prototype set cat = 'Marketable Securities' where cat = 'Equity' $$,
  '%violates check constraint%',
  '(INV1) INVERSION-PROVE, POST-084: the analogous mistake in a two-table world — running the rename against posting_prototype instead of user_taxonomy — is REJECTED by posting_prototype''s own unconditional CHECK (''Marketable Securities'' is not a member of the cat enum). Table identity alone already prevents reaching a_cf_id from a user_taxonomy-scoped statement (R5); this leg proves the CHECK is a genuine SECOND fence on the corrected table, not a redundant one now that table identity exists'
);

-- (CONFIRM) RETARGETED — LAST assertion in the file: the rejected statement
--   left A's cashflow control row (now in posting_prototype) untouched.
select is(
  (select cat from pfin.posting_prototype where id = :a_cf_id),
  'Equity',
  '(CONFIRM) after the rejected inversion probe, A''s cashflow control row still reads ''Equity'' — the failed attempt touched nothing'
);

select * from finish();
rollback;
