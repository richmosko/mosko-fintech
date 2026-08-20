-- =====================================================================
-- Per-Wave battery — SELF-311 / migration 041 (default-taxonomy provisioning),
--   RE-DERIVED AT 084 (ADR-058 Decision 1's split — pfin.taxonomy_default +
--   pfin.user_taxonomy split symmetrically with pfin.posting_prototype_default +
--   pfin.posting_prototype; `domain` dropped from both source/target pairs).
--   pfin.taxonomy_default (global shared-read reference table, asset-only post-
--   split) + the NEW scoped authenticated INSERT policy/grant on
--   pfin.user_taxonomy (Shape A — WITH CHECK users_id = auth.uid() AND the 025
--   aal2 backstop clause) + the SAME posture mirrored on posting_prototype /
--   posting_prototype_default.
--   (ADR-036 / SELF-311; V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY — un-defers Lock 7
--    write-dormancy for INSERT only + the aal2 Shape-A Sec sign-off item.)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/041_taxonomy_default_and_provisioning.sql
--   + supabase/migrations/084_gl_split_posting_prototype.sql (the split this file
--   is re-derived against).
--   - pfin.taxonomy_default POST-084: `domain` DROPPED, asset-only by construction.
--     38 rows on the 001->084 stack (36 seeded at 041 + 077's 'Cash Balances' +
--     080's 'Liability Balances', all asset-domain pre-split).
--   - pfin.posting_prototype_default: NEW at 084, the cashflow half of the split.
--     27 rows on the 001->084 stack. Global shared-read (using(true)), SELECT to
--     authenticated only, NO users_id. tax_character DOES carry an FK to the
--     ADR-024 global pfin.tax_character(code) registry (a strengthening over
--     taxonomy_default's inline CHECK) — Decision-3-NEUTRAL not because there is
--     no FK, but because the referenced table has no tenant dimension: every
--     tenant legitimately references every row, so there is no cross-tenant
--     boundary for the FK to cross. 025 aal2 EXCLUSION (i) (same posture as
--     taxonomy_default).
--   - pfin.user_taxonomy gains user_taxonomy_insert (authenticated, INSERT, WITH CHECK
--       (users_id = auth.uid()) AND (coalesce(user_settings.mfa_policy,'none') not in
--       ('totp','passkey') OR auth.jwt()->>'aal' = 'aal2')) + an INSERT grant. NO
--       UPDATE/DELETE policy or grant (Lock 7 mutate-dormancy preserved). `domain`
--       DROPPED at 084; unique becomes (users_id, cat, sub_cat).
--   - pfin.posting_prototype carries the SAME aal2-claused INSERT policy VERBATIM
--       (Shape A, ADR-058 Decision 1) + select/insert grants only.
-- Prereqs exercised (on main / applied by the reset stack): 001 (pfin schema), 009
--   (pfin.user_taxonomy + user_taxonomy_select), 010 (user_taxonomy.notes), 024
--   (pfin.user_settings + mfa_policy), 025 (the aal2 backstop clause this INSERT
--   policy mirrors), auth.users (the users_id anchor), 084 (the split itself).
-- Reuses the harness idiom: \ir verbs, ALL-LOWERCASE \gset literals, MESSAGE-precise
--   throws_like (004 all-42501 discipline — RLS violation vs ACL denial disambiguated by
--   message, both are 42501), role restored to postgres between blocks (PR #121), aal
--   dimension via _rls.set_tenant_aal (025 precedent).
--
-- ⚠ RE-SCOPED AT 084 (item 5/6, per Architect's correction): `provisionDefaultTaxonomy`
--   is app-side TypeScript with NO RPC wrapper — pgTAP cannot invoke it. Sec F3
--   condition 3's fresh-user fixture (existing user_taxonomy rows + zero
--   posting_prototype rows still provisions prototypes) is satisfied at the VITEST
--   layer (Backend's taxonomy.test.ts), not here. What THIS file still owns: the
--   provisioning SOURCE precondition (DEFAULT1-3, below — both default tables
--   non-empty and disjoint on (cat, sub_cat), an invariant the app's two-upsert code
--   assumes but never checks, and which a mocked vitest test cannot see) + the RAW
--   SQL SHAPE of each of the two provisioning statements, tested in isolation
--   (BLOCK 1/3, now split into a storage half and a prototype half) — proving each
--   statement's own RLS / WITH CHECK / idempotency holds, not simulating the app's
--   existence-guard branching logic (that is pure TypeScript control flow).
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
--   UNCHANGED (+0): taxonomy_default/posting_prototype_default have NO users_id. Correction
--   (FLAG-1): "NO reference column" is FALSE as a bare sentence against the DDL —
--   posting_prototype_default.tax_character IS an FK to the ADR-024 global pfin.tax_character(code)
--   registry (a strengthening over taxonomy_default's inline CHECK). It stays OFF the Decision-3
--   ledger not because there is no FK, but because the referenced table carries no tenant
--   dimension of any kind — every tenant legitimately references every row, so the FK crosses no
--   isolation boundary. user_taxonomy_insert/posting_prototype_insert introduce no new reference
--   column (users_id IS the tenant anchor, WITH CHECK is the C5 own-write shape, not a cross-
--   tenant-FK validation). No SECURITY DEFINER/INVOKER authored; DEFINER allowlist unchanged. This
--   battery proves the mechanisms, not a ledger move. Sec has signed the not-a-D3-member
--   disposition; only the clause's wording was wrong, not the ruling.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c();
--   NO PII / NO real account numbers / NO prod data. user_settings: B = 'totp' (the aal-gated
--   user), C = 'none' (explicit fail-open), A = NO ROW (lazy/brand-new → coalesce fail-open).
--   taxonomy_default / posting_prototype_default are migration-seeded (38 / 27 rows on the
--   001->084 stack) — read, never re-seeded by this battery. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated; tenant
--   UUIDs resolve to psql LITERALS via \gset at role=postgres; every _rls.set_tenant[_aal] is
--   called at role=postgres and each block restores role=postgres before the next.
--
-- ⟦WIRE-VALIDATE⟧ 041 (+ 009/010/024/025) on main → `supabase test db` (directory-mode pg_prove,
--   db-tests.yml) reaches this against the 001→041 reset stack. RE-VALIDATED against 001->084
--   (ADR-058's split — counts re-measured live, not carried forward from any prior stack's
--   figure, same discipline the 077/080 hardcode rule already required). RE-VALIDATED again
--   against 001->085 (`element` — every insert re-targeted, one leg added: (1b-element)). plan(26).
--
-- ⚠ HARDCODE-VS-DYNAMIC (the 077/080 regression + fix rule, applied again at 084's split — a
--   NEW seed delta by this rule's own definition). The counts below are HARDCODED at 38 / 27,
--   not switched to a `select count(*)` self-comparison. A self-referential count is VACUOUS by
--   construction (DESIGN.md §8 rule 5 — a false assertion is worse than a vacuous one, and a
--   dynamic total here is worse than false: it is a tautology that can never go RED, since the
--   value under test and the expected value would be the SAME query). Whoever lands the next
--   seed delta re-counts and updates these sites + the header, the same discipline 077/080 set.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(26);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users.
--  - user_settings: B = 'totp' (aal-gated), C = 'none' (explicit fail-open); A = NO ROW
--    (brand-new / lazy — the coalesce fail-open case).
--  - taxonomy_default / posting_prototype_default are already populated (38 / 27 rows
--    on this 001->084+ stack) — the provisioning sources.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');
insert into pfin.user_settings (users_id, mfa_policy) values (:'tb', 'totp'), (:'tc', 'none');

-- =====================================================================
-- BLOCK DEFAULT — the provisioning SOURCE precondition (new at 084, item 5/6's
--   pgTAP-ownable half — see the header note).
-- =====================================================================

-- (DEFAULT1) taxonomy_default is non-empty post-split.
select is(
  (select count(*) from pfin.taxonomy_default)::bigint, 38::bigint,
  '(DEFAULT1) taxonomy_default: 38 rows post-split (asset-only provisioning source)'
);
-- (DEFAULT2) posting_prototype_default is non-empty post-split.
select is(
  (select count(*) from pfin.posting_prototype_default)::bigint, 27::bigint,
  '(DEFAULT2) posting_prototype_default: 27 rows post-split (cashflow-only provisioning source)'
);
-- (DEFAULT3) the two provisioning sources are DISJOINT on (cat, sub_cat) — the
--   precondition the app's two-upsert provisioning code assumes but never checks,
--   and which Backend's mocked vitest test cannot see (it mocks the DB, not the
--   seed data). A collision here would mean a user's storage row and prototype row
--   could carry the SAME (cat, sub_cat) label — confusing but not itself a security
--   defect — asserted here because only a real-data DB test can prove it.
select is(
  (select count(*) from pfin.taxonomy_default td
     join pfin.posting_prototype_default ppd
       on td.cat = ppd.cat and td.sub_cat = ppd.sub_cat)::bigint,
  0::bigint,
  '(DEFAULT3) taxonomy_default and posting_prototype_default share NO (cat, sub_cat) pair — the provisioning sources are disjoint by content, not merely by table'
);

-- =====================================================================
-- BLOCK 1 — owner provisions own rows PASS (+ fail-open: A has NO user_settings row).
--   SPLIT into a storage half and a prototype half (084 — the app issues two
--   separate upserts; this proves each raw statement's own RLS/WITH CHECK holds).
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (1a-storage) A (no user_settings row → coalesce→'none' → backstop TRUE at aal1) runs
--      the storage-half provision statement → the whole asset default set lands.
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes, element
     from pfin.taxonomy_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(1a-storage) owner provisions own storage rows PASS (+ fail-open): A with NO user_settings row provisions the full asset default set at aal1 (users_id = auth.uid()) — WITH CHECK accepts every row (coalesce→''none'' fail-open)'
);
-- (1a-proto) A runs the prototype-half provision statement → the whole cashflow
--      default set lands, mirroring (1a-storage) on the second table.
select lives_ok(
  $$ insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes
     from pfin.posting_prototype_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(1a-proto) owner provisions own prototype rows PASS: same tenant, second table, mirrors (1a-storage)'
);

-- (1b-storage) A now owns exactly 38 user_taxonomy rows (the full committed asset
--      default set copied through; ⚠ HARDCODED, not derived — see the header rule).
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint,
  38::bigint,
  '(1b-storage) owner provisioned all 38 asset default rows: A''s user_taxonomy count = 38'
);
-- (1b-element) NEW at 085 — the provisioning fixture extension (ADR-058 Decision 3 / Sec F4
--      condition 2, provisioning half): A's 38 freshly-provisioned rows carry ZERO NULL
--      `element` values. This is the pgTAP-ownable half of "a fresh user ends up with rows
--      carrying no NULL element" (Architect's ask) — it is what catches Backend's
--      `taxonomy.ts` column-list split adding `element` to the SHARED constant instead of the
--      storage-only one: if that regressed, this statement's own `select ... select ... from
--      taxonomy_default` column-listed copy (BLOCK 1 above, already re-targeted this PR) would
--      either have failed outright (element omitted -> not-null violation, (1a-storage) itself
--      would already be RED) or, if `taxonomy_default.element` were ever nullable, landed NULLs
--      here silently — this leg is the one that would catch the silent case.
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta' and element is null)::bigint,
  0::bigint,
  '(1b-element) provisioning fixture extension: A''s 38 freshly-provisioned user_taxonomy rows carry ZERO NULL element values — the column-listed copy from taxonomy_default (BLOCK 1) propagates element correctly, not silently'
);
-- (1b-proto) A now owns exactly 27 posting_prototype rows.
select is(
  (select count(*) from pfin.posting_prototype where users_id = :'ta')::bigint,
  27::bigint,
  '(1b-proto) owner provisioned all 27 cashflow default rows: A''s posting_prototype count = 27'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 — WITH CHECK fail-closed (the security teeth). Cross-tenant users_id forge.
--   user_taxonomy only — posting_prototype's identical WITH CHECK teeth are already
--   proven in 084_posting_prototype_rls.sql (W1/W2); not duplicated here.
--
-- ⚠ 085's `element` ADDED TO EVERY INSERT BELOW, INCLUDING THE REJECTION LEGS — this is
--   why, stated precisely rather than left implicit. Empirically probed (throwaway
--   scratch DB, a synthetic table mirroring this one's shape, NOT assumed from source
--   recall): **RLS `WITH CHECK` evaluates BEFORE the column's `NOT NULL` constraint.**
--   A mismatched-tenant/backstop-failing insert raises the RLS violation even when
--   `element` is omitted — the NOT NULL check is never reached, because RLS rejects the
--   proposed row first. This means (2a) and BLOCK 5's (5b)/(5d) below would have kept
--   passing, for the SAME reason as before 085, even with `element` left out. `element`
--   is added to them anyway — defensively, not because the mechanism requires it — so
--   none of these legs' correctness depends on an unstated assumption about constraint-
--   evaluation order. The one leg where the ordering DOES matter is (5c): the SAME insert
--   shape, but RLS PASSES there (aal2 lifts the gate) — so NOT NULL is the next gate
--   reached, and (5c) would genuinely break without `element`. That contrast is why this
--   probe was worth running rather than assuming: a NOT NULL-then-CHECK error text does
--   not match `%violates row-level security policy%`, so a wrong assumption here would
--   have either broken (5c) silently or made (2a)/(5b)/(5d) look like they needed
--   `element` for a reason they don't.
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (2a) A (backstop fail-open, so the ONLY gate is the tenant predicate) inserts a row OWNED
--      BY B → user_taxonomy_insert WITH CHECK (users_id = auth.uid()) rejects. INVERSION:
--      drop that conjunct and the B-owned row COMMITS → this flips RED.
select throws_like(
  format($$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values (%L, 'Cash', 'FDIC', 'asset') $$, :'tb'),
  '%violates row-level security policy%',
  '(2a) WITH CHECK fail-closed: A inserting a row with users_id = B is RLS-rejected (users_id = auth.uid() fences the write to the owner) — a user cannot provision rows into another tenant''s taxonomy'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 — idempotent re-provision (ON CONFLICT DO NOTHING → no duplicates), SPLIT
--   the same way as BLOCK 1.
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (3a-storage) A runs the SAME storage-half statement again → all 38 rows conflict.
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes, element
     from pfin.taxonomy_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(3a-storage) idempotent re-provision: A runs the storage-half statement a SECOND time → every row conflicts on unique(users_id,cat,sub_cat) → DO NOTHING → no error'
);
-- (3a-proto) A runs the SAME prototype-half statement again.
select lives_ok(
  $$ insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes
     from pfin.posting_prototype_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(3a-proto) idempotent re-provision: A runs the prototype-half statement a SECOND time → no error'
);
select set_config('role', 'postgres', true);

-- (3b-storage) A STILL owns exactly 38 user_taxonomy rows — the second run inserted 0.
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta')::bigint,
  38::bigint,
  '(3b-storage) idempotent re-provision: A''s user_taxonomy count is STILL 38 after the second run'
);
-- (3b-proto) A STILL owns exactly 27 posting_prototype rows.
select is(
  (select count(*) from pfin.posting_prototype where users_id = :'ta')::bigint,
  27::bigint,
  '(3b-proto) idempotent re-provision: A''s posting_prototype count is STILL 27 after the second run'
);

-- =====================================================================
-- BLOCK 4 — taxonomy_default / posting_prototype_default: global shared-read, no
--   tenant scoping, both tenants identical, on BOTH provisioning-source tables.
-- =====================================================================
-- (4a) authenticated A reads the whole asset default set (using(true)) = 38.
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');
select is(
  (select count(*) from pfin.taxonomy_default)::bigint,
  38::bigint,
  '(4a) taxonomy_default global shared-read: authenticated A SELECTs all 38 rows (using(true) — the provisioning source is readable to any authenticated user)'
);
select set_config('role', 'postgres', true);

-- (4a-proto) authenticated A reads the whole cashflow default set = 27.
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');
select is(
  (select count(*) from pfin.posting_prototype_default)::bigint,
  27::bigint,
  '(4a-proto) posting_prototype_default global shared-read: authenticated A SELECTs all 27 rows (using(true), same posture as taxonomy_default)'
);
select set_config('role', 'postgres', true);

-- (4b) authenticated B (mfa_policy='totp') at aal1 reads the SAME 38 rows — taxonomy_default is
--      EXCLUDED from the aal2 backstop (using(true), no clause), so it is NOT aal-gated and is
--      identical across tenants (global reference data, not tenant-scoped).
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select is(
  (select count(*) from pfin.taxonomy_default)::bigint,
  38::bigint,
  '(4b) taxonomy_default readable identically across tenants + NOT aal-gated: B (totp) at aal1 reads the same 38 rows — global reference data, no tenant predicate, no step-up gate'
);
select set_config('role', 'postgres', true);

-- (4b-proto) same proof, posting_prototype_default: B (totp) at aal1 reads the same 27 rows.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select is(
  (select count(*) from pfin.posting_prototype_default)::bigint,
  27::bigint,
  '(4b-proto) posting_prototype_default readable identically across tenants + NOT aal-gated: B (totp) at aal1 reads the same 27 rows'
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
--   bearing all-conflict re-provision). user_taxonomy only — posting_prototype carries the
--   identical clause VERBATIM (Decision 1); its structural presence is proven in
--   084_posting_prototype_rls.sql (S3), not behaviorally duplicated here.
-- =====================================================================
-- (5a) fail-open, explicit 'none': C (mfa_policy='none') at aal1 provisions the full set → PASS
--      (distinct code path from A's missing-row: here the subselect RETURNS 'none').
select _rls.set_tenant_aal(:'tc'::uuid, 'aal1');
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes, element
     from pfin.taxonomy_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(5a) fail-open (explicit ''none''): C with mfa_policy=''none'' provisions at aal1 → PASS (coalesce returns ''none'' → not in (totp,passkey) → backstop TRUE; the non-null ''none'' path, distinct from A''s missing-row path)'
);
select set_config('role', 'postgres', true);

-- (5b) aal-gate BLOCK: B (mfa_policy='totp') at aal1 inserts a NET-NEW row (B has none) → the
--      backstop conjunct is FALSE (totp in (…), aal != 'aal2') → WITH CHECK rejects. The clause
--      has teeth on net-new writes. INVERSION: drop the conjunct (Shape B) and this COMMITS → RED.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal1');
select throws_like(
  $$ insert into pfin.user_taxonomy (cat, sub_cat, element) values ('Cash', 'FDIC', 'asset') $$,
  '%violates row-level security policy%',
  '(5b) aal2 backstop BLOCK: a totp user at aal1 inserting a NET-NEW row is RLS-rejected (backstop conjunct false) — Shape A gates step-up-declared users at aal1 on net-new provisioning'
);
select set_config('role', 'postgres', true);

-- (5c) aal-gate LIFTED: the SAME totp user B at aal2 inserts the SAME row → COMMITS (aal='aal2'
--      → second disjunct TRUE). Proves 5b blocks on aal, not on B being write-incapable.
select _rls.set_tenant_aal(:'tb'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.user_taxonomy (cat, sub_cat, element) values ('Cash', 'FDIC', 'asset') $$,
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
  $$ insert into pfin.user_taxonomy (cat, sub_cat, element) values ('Cash', 'FDIC', 'asset')
     on conflict (users_id, cat, sub_cat) do nothing $$,
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
--   user_taxonomy only — posting_prototype's identical {select,insert}-only grant shape is
--   already proven structurally in 084_posting_prototype_rls.sql (S4).
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
