-- =====================================================================
-- Per-Wave battery — SELF-311 / migration 041 (default-taxonomy provisioning).
--   pfin.taxonomy_default (global shared-read reference table) + the NEW scoped
--   authenticated INSERT policy/grant on pfin.user_taxonomy (Shape A — WITH CHECK
--   users_id = auth.uid() AND the 025 aal2 backstop clause).
--   (ADR-036 / SELF-311; V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — un-defers Lock 7
--    write-dormancy for INSERT only + the aal2 Shape-A Sec sign-off item.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/041_taxonomy_default_and_provisioning.sql
--   - pfin.taxonomy_default (id, domain CHECK, cat, sub_cat, tax_relevant, tax_character
--       CHECK, display_order, notes; UNIQUE(domain,cat,sub_cat); NO users_id / NO FK;
--       RLS using(true) SELECT for authenticated; anon zero; service_role none; 63 rows
--       = 36 asset + 27 cashflow, migration-seeded AT 041).
--   ⚠ AMENDED BY 077 AND 080 (ADR-057, two instances of the same pattern): 077 adds ONE
--     global row (asset/Cash/'Cash Balances'); 080 adds a SECOND (asset/Liabilities/
--     'Liability Balances') — the seeded set is 65 rows (38 asset + 27 cashflow) on the
--     001->080+ stack this battery actually runs against. Every count below is updated
--     for the 65-row world; HARDCODED, not derived, deliberately (see the note at each
--     assertion below). ⚠ THE WATCHER FIRED, OBSERVED BEFORE REPINNED: re-running this
--     battery's then-current 64-hardcoded assertions against the post-080 catalog
--     (before this fix landed) reproduced EXACTLY the 077 regression's shape — tests 2,
--     5-7 red, "have: 65 / want: 64" — proving the hardcode is a real, firing watcher and
--     not a decorative one. See the hand-off report for that run.
--   - pfin.user_taxonomy gains user_taxonomy_insert (authenticated, INSERT, WITH CHECK
--       (users_id = auth.uid()) AND (coalesce(user_settings.mfa_policy,'none') not in
--       ('totp','passkey') OR auth.jwt()->>'aal' = 'aal2')) + an INSERT grant. NO
--       UPDATE/DELETE policy or grant (Lock 7 mutate-dormancy preserved).
-- Prereqs exercised (on main / applied by the reset stack): 001 (pfin schema), 009
--   (pfin.user_taxonomy + user_taxonomy_select + unique(users_id,domain,cat,sub_cat)),
--   010 (user_taxonomy.notes), 024 (pfin.user_settings + mfa_policy), 025 (the aal2
--   backstop clause this INSERT policy mirrors), auth.users (the users_id anchor).
-- Reuses the harness idiom: \ir verbs, ALL-LOWERCASE \gset literals, MESSAGE-precise
--   throws_like (004 all-42501 discipline — RLS violation vs ACL denial disambiguated by
--   message, both are 42501), role restored to postgres between blocks (PR #121), aal
--   dimension via _rls.set_tenant_aal (025 precedent).
--
-- ┌─ WHY EACH REJECTION MATCHES A DISTINCT SIGNAL (no fence passes for another) ─────────┐
-- │  • cross-tenant users_id forge (WITH CHECK)    -> '%violates row-level security…%' 42501│
-- │  • totp user @ aal1 net-new (aal backstop)     -> '%violates row-level security…%' 42501│
-- │  • UPDATE/DELETE (no grant — mutate-dormancy)  -> '%permission denied%'            42501 │
-- │  • anon read taxonomy_default (no schema USAGE)-> insufficient_privilege           42501 │
-- │ authenticated HOLDS the INSERT grant, so the only INSERT-path 42501 is the RLS WITH    │
-- │ CHECK (matched on the RLS message, never a bare code); the mutate-path 42501 is the ACL │
-- │ denial (matched on 'permission denied') — a fence can never pass for another.          │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- INVERSION-PROVE (the battery has teeth — a real violation flips it RED):
--   (2a) — if the `users_id = auth.uid()` conjunct were dropped from user_taxonomy_insert
--          WITH CHECK, A forging a row owned by B would COMMIT → throws_like RED. This is
--          the security-teeth case asked for at hand-off.
--   (5b) — if the aal2 backstop conjunct were dropped (Shape B), a totp user at aal1 would
--          land a NET-NEW row → throws_like RED (proves the clause gates, Shape A).
--   (5d) — GROUND-TRUTH FINDING: the migration's AAL2 rationale claims an all-conflict
--          re-provision at aal1 by a totp user passes ("0 rows checked"). It does NOT —
--          Postgres evaluates WITH CHECK on the proposed row BEFORE conflict resolution, so it
--          RAISES. This test pins the REAL semantics (throws), not the migration's aspiration;
--          runtime safety comes from Backend's provisionDefaultTaxonomy existence-guard. Flagged
--          to Architect/Sec (the Shape-A sign-off rationale rests on this false premise).
--   (6a)/(6b) — if an UPDATE/DELETE grant leaked in, the mutate would not be ACL-denied → RED.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27). Decision-3 family
--   UNCHANGED (+0): taxonomy_default has NO users_id / NO reference column; user_taxonomy_insert
--   introduces no new reference column (users_id IS the tenant anchor, WITH CHECK is the C5
--   own-write shape, not a cross-tenant-FK validation). No SECURITY DEFINER/INVOKER authored;
--   DEFINER allowlist unchanged at 4 (authored 3). This battery proves the mechanisms, not a
--   ledger move.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c();
--   NO PII / NO real account numbers / NO prod data. user_settings: B = 'totp' (the aal-gated
--   user), C = 'none' (explicit fail-open), A = NO ROW (lazy/brand-new → coalesce fail-open).
--   taxonomy_default is migration-seeded (65 rows on the 001->080+ stack — see the AMENDED BY
--   077 AND 080 note above) — read, never re-seeded by this battery. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated; tenant
--   UUIDs resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant[_aal] is
--   called at role=postgres and each block restores role=postgres before the next.
--
-- ⟦WIRE-VALIDATE⟧ 041 (+ 009/010/024/025) on main → `supabase test db` (directory-mode pg_prove,
--   db-tests.yml) reaches this against the 001→041 reset stack. plan(16). RE-VALIDATED green
--   against the 001→079 stack (feature/cash-seed-and-kernel-gates) after the 077 count fix, and
--   again against the 001→081 stack (feature/self329-liability-cash-routing) after this 080
--   count fix — SECOND firing of the same watcher, see below.
--
-- ⚠ HARDCODE-VS-DYNAMIC (the 077 regression + fix, RE-CONFIRMED by 080's regression + fix —
--   stated as a rule for the NEXT seed delta, not just these two). The counts below are
--   RE-HARDCODED at 65, not switched to a `select count(*) from pfin.taxonomy_default`
--   self-comparison. A self-referential count is VACUOUS by construction (DESIGN.md §8 rule 5 —
--   a false assertion is worse than a vacuous one, and a dynamic total here is worse than false:
--   it is a tautology that can never go RED, since the value under test and the expected value
--   would be the SAME query). The whole point of (1b)/(3b)/(4a)/(4b) is to prove the FULL
--   committed default set actually round-trips through the WITH CHECK / RLS surfaces this
--   battery exercises — a number pinned against the MIGRATION-SEEDED TRUTH, not against the
--   table's own current state. ADR-057 (this branch) names "a change to taxonomy_default's
--   content" as a RECOGNIZED, RATIFIED event class — not an accident, and now demonstrated
--   TWICE (077, 080) — so a hardcoded count going RED on the next seed delta is the INTENDED
--   signal (a deliberate watcher whose owner is now named by this very comment), not a
--   maintenance tax to engineer away. Whoever lands the next seed delta re-counts and updates
--   these four sites + the header, the same way this fix did for 077 and again for 080.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(16);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users.
--  - user_settings: B = 'totp' (aal-gated), C = 'none' (explicit fail-open); A = NO ROW
--    (brand-new / lazy — the coalesce fail-open case).
--  - taxonomy_default is already populated (65 rows on this 001->080+ stack — 63 seeded at
--    041 + 077's 'Cash Balances' row + 080's 'Liability Balances' row) — the provisioning
--    source.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');
insert into pfin.user_settings (users_id, mfa_policy) values (:'tb', 'totp'), (:'tc', 'none');

-- =====================================================================
-- BLOCK 1 — owner provisions own rows PASS (+ fail-open: A has NO user_settings row).
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (1a) A (no user_settings row → coalesce→'none' → backstop TRUE at aal1) runs the canonical
--      provision statement → the whole default set lands. Owner-provisions-own PASS AND the
--      missing-settings fail-open path (deliverable 1 + 5).
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
     select auth.uid(), domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes
     from pfin.taxonomy_default
     on conflict (users_id, domain, cat, sub_cat) do nothing $$,
  '(1a) owner provisions own rows PASS (+ fail-open): A with NO user_settings row provisions the full default set at aal1 (users_id = auth.uid()) — WITH CHECK accepts every row (coalesce→''none'' fail-open)'
);

-- (1b) A now owns exactly 65 rows (the full committed default set copied through — 63 seeded
--      at 041 + 077's 'Cash Balances' row + 080's 'Liability Balances' row, this battery's
--      stack runs 001->080+; ⚠ HARDCODED, not derived — see the rule at the header).
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint,
  65::bigint,
  '(1b) owner provisioned all 65 default rows: A''s user_taxonomy count = 65 (every taxonomy_default row passed the INSERT WITH CHECK — 63 from 041 + 077''s Cash Balances row + 080''s Liability Balances row)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 — WITH CHECK fail-closed (the security teeth). Cross-tenant users_id forge.
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (2a) A (backstop fail-open, so the ONLY gate is the tenant predicate) inserts a row OWNED
--      BY B → user_taxonomy_insert WITH CHECK (users_id = auth.uid()) rejects. INVERSION:
--      drop that conjunct and the B-owned row COMMITS → this flips RED.
select throws_like(
  format($$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values (%L, 'asset', 'Cash', 'FDIC') $$, :'tb'),
  '%violates row-level security policy%',
  '(2a) WITH CHECK fail-closed: A inserting a row with users_id = B is RLS-rejected (users_id = auth.uid() fences the write to the owner) — a user cannot provision rows into another tenant''s taxonomy'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 — idempotent re-provision (ON CONFLICT DO NOTHING → no duplicates).
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (3a) A runs the SAME provision statement again → all 65 rows conflict → do nothing → no error.
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
     select auth.uid(), domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes
     from pfin.taxonomy_default
     on conflict (users_id, domain, cat, sub_cat) do nothing $$,
  '(3a) idempotent re-provision: A runs the provision statement a SECOND time → every row conflicts on unique(users_id,domain,cat,sub_cat) → DO NOTHING → no error'
);
select set_config('role', 'postgres', true);

-- (3b) A STILL owns exactly 65 rows — the second run inserted 0 (no duplicates).
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint,
  65::bigint,
  '(3b) idempotent re-provision: A''s count is STILL 65 after the second run — ON CONFLICT DO NOTHING double-seeds nothing'
);

-- =====================================================================
-- BLOCK 4 — taxonomy_default: global shared-read, no tenant scoping, both tenants identical.
-- =====================================================================
-- (4a) authenticated A reads the whole default set (using(true) global shared-read) = 65.
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');
select is(
  (select count(*) from pfin.taxonomy_default)::bigint,
  65::bigint,
  '(4a) taxonomy_default global shared-read: authenticated A SELECTs all 65 rows (using(true) — the provisioning source is readable to any authenticated user; 63 seeded at 041 + 077''s Cash Balances row + 080''s Liability Balances row)'
);
select set_config('role', 'postgres', true);

-- (4b) authenticated B (mfa_policy='totp') at aal1 reads the SAME 65 rows — taxonomy_default is
--      EXCLUDED from the aal2 backstop (using(true), no clause), so it is NOT aal-gated and is
--      identical across tenants (global reference data, not tenant-scoped).
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select is(
  (select count(*) from pfin.taxonomy_default)::bigint,
  65::bigint,
  '(4b) taxonomy_default readable identically across tenants + NOT aal-gated: B (totp) at aal1 reads the same 65 rows — global reference data, no tenant predicate, no step-up gate'
);
select set_config('role', 'postgres', true);

-- (4c) taxonomy_default carries NO users_id column — structurally it holds no tenant scoping /
--      no tenant rows (global reference data only).
select hasnt_column(
  'pfin', 'taxonomy_default', 'users_id',
  '(4c) taxonomy_default has NO users_id column: it is global, non-tenant reference data (no per-tenant rows, nothing to isolate) — the tenant surface is user_taxonomy, not this table'
);

-- (4d) anon holds no USAGE on schema pfin → even SELECT on taxonomy_default is denied at the ACL
--      layer, before RLS (the outer C2 fence; a global-read table is still not anon-reachable).
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.taxonomy_default',
  '42501', null,
  '(4d) anon zero-grant: anon holds no USAGE on schema pfin → SELECT on taxonomy_default is denied at the ACL layer (insufficient_privilege 42501), before RLS — global shared-read is authenticated-only'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 5 — aal2 Shape A behavior (fail-open population + the gated totp user + the load-
--   bearing all-conflict re-provision).
-- =====================================================================
-- (5a) fail-open, explicit 'none': C (mfa_policy='none') at aal1 provisions the full set → PASS
--      (distinct code path from A's missing-row: here the subselect RETURNS 'none').
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
     select auth.uid(), domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes
     from pfin.taxonomy_default
     on conflict (users_id, domain, cat, sub_cat) do nothing $$,
  '(5a) fail-open (explicit ''none''): C with mfa_policy=''none'' provisions at aal1 → PASS (coalesce returns ''none'' → not in (totp,passkey) → backstop TRUE; the non-null ''none'' path, distinct from A''s missing-row path)'
);
select set_config('role', 'postgres', true);

-- (5b) aal-gate BLOCK: B (mfa_policy='totp') at aal1 inserts a NET-NEW row (B has none) → the
--      backstop conjunct is FALSE (totp in (…), aal != 'aal2') → WITH CHECK rejects. The clause
--      has teeth on net-new writes. INVERSION: drop the conjunct (Shape B) and this COMMITS → RED.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select throws_like(
  $$ insert into pfin.user_taxonomy (domain, cat, sub_cat) values ('asset', 'Cash', 'FDIC') $$,
  '%violates row-level security policy%',
  '(5b) aal2 backstop BLOCK: a totp user at aal1 inserting a NET-NEW row is RLS-rejected (backstop conjunct false) — Shape A gates step-up-declared users at aal1 on net-new provisioning'
);
select set_config('role', 'postgres', true);

-- (5c) aal-gate LIFTED: the SAME totp user B at aal2 inserts the SAME row → COMMITS (aal='aal2'
--      → second disjunct TRUE). Proves 5b blocks on aal, not on B being write-incapable.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.user_taxonomy (domain, cat, sub_cat) values ('asset', 'Cash', 'FDIC') $$,
  '(5c) aal2 lifts the gate: the SAME totp user at aal2 inserts the SAME row → COMMITS (backstop satisfied by aal2) — 5b is an aal gate, not a blanket block'
);
select set_config('role', 'postgres', true);

-- (5d) GROUND-TRUTH (corrects a false premise in the 041 header): totp user B at aal1
--      re-provisions the now-existing row via ON CONFLICT DO NOTHING → STILL RAISES. Postgres
--      evaluates the INSERT WITH CHECK on the PROPOSED row BEFORE conflict resolution, so an
--      all-conflict re-provision is NOT "0 rows checked → passes" (the 041 AAL2 decision's
--      stated rationale). Empirically verified (psql probe): ON CONFLICT DO NOTHING does NOT
--      exempt the conflicting row from WITH CHECK. RUNTIME SAFETY comes from Backend's
--      provisionDefaultTaxonomy EXISTENCE-GUARD (skips the insert entirely when the caller
--      already has any row) + fail-soft — NOT from on-conflict semantics. Flagged to Architect/Sec
--      (the Shape-A sign-off rationale rests on this false premise; the DECISION may still stand,
--      but on corrected grounds — see the QA finding relayed at hand-off).
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select throws_like(
  $$ insert into pfin.user_taxonomy (domain, cat, sub_cat) values ('asset', 'Cash', 'FDIC')
     on conflict (users_id, domain, cat, sub_cat) do nothing $$,
  '%violates row-level security policy%',
  '(5d) ON CONFLICT DO NOTHING does NOT bypass the aal2 backstop: a totp user at aal1 re-inserting an EXISTING row STILL RAISES — Postgres evaluates INSERT WITH CHECK on the proposed row BEFORE conflict resolution (the migration''s "0 rows checked → passes" premise is FALSE). Runtime safety = Backend''s provisionDefaultTaxonomy existence-guard, not on-conflict semantics'
);
select set_config('role', 'postgres', true);

-- (5e) B owns exactly ONE row: 5b landed nothing (blocked), 5c landed one, 5d duplicated nothing.
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'tb')::bigint,
  1::bigint,
  '(5e) B owns exactly 1 row: the blocked (5b) net-new never landed, the aal2 (5c) insert landed once, the (5d) aal1 re-provision RAISED (added nothing) — the aal gate held on both the net-new and the on-conflict paths'
);

-- =====================================================================
-- BLOCK 6 — Lock 7 mutate-dormancy preserved: INSERT un-deferred, UPDATE/DELETE still denied.
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (6a) authenticated A holds NO UPDATE grant on user_taxonomy → UPDATE denied at the ACL layer
--      ('permission denied', 42501) before RLS — mutate-dormancy intact (only INSERT un-deferred).
select throws_like(
  $$ update pfin.user_taxonomy set sub_cat = 'HACK' where users_id = auth.uid() $$,
  '%permission denied%',
  '(6a) mutate-dormancy (UPDATE): authenticated holds no UPDATE grant on user_taxonomy → UPDATE is ACL-denied (permission denied, 42501) before RLS — 041 un-defers INSERT only, not UPDATE'
);

-- (6b) authenticated A holds NO DELETE grant → DELETE ACL-denied ('permission denied', 42501).
select throws_like(
  $$ delete from pfin.user_taxonomy where users_id = auth.uid() $$,
  '%permission denied%',
  '(6b) mutate-dormancy (DELETE): authenticated holds no DELETE grant on user_taxonomy → DELETE is ACL-denied (permission denied, 42501) — writes-that-remove stay default-denied (V2 CRUD-UI owns them)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
