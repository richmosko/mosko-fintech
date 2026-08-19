-- =====================================================================
-- Per-Wave battery — pfin.user_asset_category: the per-user asset→taxonomy
--   allocation junction + BOTH Decision-3 fences (matched-tenant #8 + the NOVEL
--   global-OR-matched-tenant #9, Pattern 2 site 2) + RLS isolation + unique + grants
--   (ADR-027 R-19 / SELF-282 — C6 EXPOSURE-GATING per ADR-023; V1-SHIP-BLOCK;
--    JOINT-REVIEW-MANDATORY — two Decision-3 fence patterns in one table)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/022_user_asset_category.sql
--   - pfin.user_asset_category (id, users_id NOT NULL DEFAULT auth.uid() -> auth.users
--       ON DELETE CASCADE, asset_id NOT NULL -> pfin.asset ON DELETE RESTRICT,
--       sub_cat_id NOT NULL -> pfin.user_taxonomy ON DELETE RESTRICT, created/updated_at,
--       unique(users_id, asset_id)). RLS direct-owner (users_id = auth.uid()); full
--       authenticated CRUD; anon zero-grant; service_role UNGRANTED (no V1 writer).
--   - pfin.fn_user_asset_category_matched_sub_cat()  (Decision-3 CANONICAL #8; 012
--       Pattern 1; SECURITY INVOKER; BEFORE INSERT OR UPDATE WHEN (new.sub_cat_id IS NOT
--       NULL); NULL-safe fail-closed NOT EXISTS -> raise 'cross-tenant Sub-Cat rejected%';
--       referenced user_taxonomy row must share new.users_id).
--   - pfin.fn_user_asset_category_asset()  (Decision-3 CANONICAL #9; the NOVEL global-OR-
--       matched-tenant fence, Pattern 2 site 2; SECURITY INVOKER; BEFORE INSERT OR UPDATE
--       WHEN (new.asset_id IS NOT NULL); NULL-safe fail-closed; asset valid IFF GLOBAL
--       (asset.users_id IS NULL) OR OWNED by this row's tenant (asset.users_id =
--       new.users_id, resolved DIRECTLY via new.users_id — NO account JOIN, contrast 017).
--   - trigger user_asset_category_set_updated_at (reuses the 001 DEFINER allowlist entry #1).
-- Prereqs exercised (already on main / applied by Backend on the reset stack): 001 (pfin
--   schema + fn_refresh_updated_at), 009 (pfin.user_taxonomy — the sub_cat_id FK target),
--   016 (pfin.asset hybrid registry — the asset_id FK target + its global-OR-owned RLS the
--   novel fence mirrors), auth.users (the users_id anchor).
-- Reuses the SELF-187/189/190/196/012/015/016/017 idiom: \ir verbs, ALL-LOWERCASE \gset
--   literals (005 case-fold lesson), MESSAGE-precise throws_like (004 all-42501 false-green
--   lesson), role restored to postgres between blocks (PR #121 _rls-USAGE root-cause).
--
-- ┌─ TRIGGER FIRING ORDER (load-bearing for fence isolation — verified, not assumed) ────┐
-- │ Postgres fires same-event BEFORE-ROW triggers in trigger-NAME ALPHABETICAL order:     │
-- │   user_asset_category_asset (#9)  <  user_asset_category_matched_sub_cat (#8)          │
-- │ so #9 (asset) fires FIRST. Therefore to surface #8's message the asset must PASS #9    │
-- │ (use a GLOBAL or tenant-OWNED asset); to surface #9's message the asset must FAIL #9   │
-- │ (it raises first regardless of sub_cat). Every isolation case below is built on this.  │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THE CROSS-TENANT ASSERTIONS HAVE TEETH (the (3b)/(3c) necessary-but-INSUFFICIENT, │
-- │  (6a)/(6b) LOAD-BEARING split — the 017 (a3)-vs-(a4) lesson applied to BOTH fences) ──┐│
-- │ Both fences are SECURITY INVOKER. Under authenticated B, the #8 read composes with     ││
-- │ user_taxonomy RLS (A's Sub-Cat is RLS-INVISIBLE to B) and the #9 read composes with    ││
-- │ 016 asset RLS (A's per-user asset is RLS-INVISIBLE to B) — so (3b)/(3c) could PASS even ││
-- │ if the explicit users_id predicates were removed and RLS carried the whole load. That  ││
-- │ is belt-and-suspenders, NECESSARY but not sufficient to prove the TRIGGER.             ││
-- │ (6a)/(6b) isolate the trigger: under service_role (RLS BYPASSED — B's Sub-Cat AND B's  ││
-- │ asset ARE visible to the subqueries), the SAME cross-tenant writes STILL RAISE, so the ││
-- │ explicit `= new.users_id` / `(IS NULL OR = new.users_id)` predicate — NOT RLS — is the ││
-- │ gate. (6c) is the non-vacuous control: a matched row under service_role COMMITS.       ││
-- │ NOTE — unlike 017 (whose fence is load-bearing under a REAL provider-sync service_role  ││
-- │ writer), user_asset_category has NO service_role writer in V1 (POSTURE: service_role    ││
-- │ UNGRANTED). BLOCK 6 is a TEST-ONLY trigger-isolation device: the grants are held OPEN   ││
-- │ in-test (rolled back with the txn) purely so RLS-bypass exposes the referenced rows and ││
-- │ the explicit predicate is the sole remaining gate. It asserts teeth, not a prod path.  ││
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY EACH REJECTION MATCHES A DISTINCT SIGNAL (no fence/constraint passes for another) ┐
-- │  • cross-tenant sub_cat (fence #8)  -> raise 'cross-tenant Sub-Cat rejected%'           │
-- │  • cross-tenant asset  (fence #9)   -> raise 'cross-tenant asset rejected%'             │
-- │  • duplicate (users_id, asset_id)   -> unique_violation 23505                           │
-- │  • ON DELETE RESTRICT (both FKs)    -> foreign_key_violation 23503                      │
-- │  • anon (no schema USAGE)           -> insufficient_privilege 42501 (ACL, before RLS)   │
-- │ Fence raises are MESSAGE-precise (not a bare 42501, not a 23503 FK violation, not a     │
-- │ silent pass) so a fence can never pass for another (the 004 all-42501 discipline).      │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ RLS WITH CHECK is SHADOWED by the BEFORE fence (honest note on (5a)) ────────────────┐
-- │ sub_cat_id is NOT NULL, so the #8 fence fires on EVERY write. A cross-tenant ownership  │
-- │ forge (B inserting users_id = A) has new.users_id = A but a Sub-Cat NOT owned by A, so  │
-- │ the #8 BEFORE trigger raises BEFORE the uac_insert RLS WITH CHECK (users_id=auth.uid()) │
-- │ is ever evaluated (Postgres runs BEFORE triggers, then the WITH CHECK). Both would      │
-- │ block; the fence intercepts first. (5a) asserts the forge FAILS CLOSED via the fence    │
-- │ message; the RLS USING isolation ((2b)/(4a)/(4b)) proves the SELECT/UPDATE/DELETE       │
-- │ owner-scoping independently. Together: a row owned by A can neither be read, forged,    │
-- │ modified, nor deleted by B.                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1a) -> LOAD-BEARING POSITIVE: RED if the #9 global disjunct (asset.users_id IS NULL)
--          were dropped — categorizing a GLOBAL asset (VOO) is the whole point of R-19 / the
--          novel predicate; a fence that rejected globals would break the feature.
--   (1b) -> RED if the #9 owned disjunct or the #8 matched-tenant PASS over-blocked own data.
--   (1c) -> RED if the fences did not cover UPDATE (BEFORE INSERT OR UPDATE) — a legit
--          re-categorization to another OWN Sub-Cat must succeed (mutable junction).
--   (2a) -> RED if RLS were over-restrictive (owner cannot read own rows).
--   (2b) -> RED if the SELECT policy leaked — B must see 0 of A's rows.
--   (3a) -> NON-VACUOUS control: RED if the fences blanket-blocked authenticated B (proves
--          (3b)-(3e) are cross-tenant-MISMATCH-driven); also proves the global disjunct is
--          TENANT-AGNOSTIC (any tenant may categorize a global asset).
--   (3b) -> #8 cross-tenant INSERT: RED if fn_user_asset_category_matched_sub_cat (or its
--          users_id predicate) were removed -> B tags an asset with A's Sub-Cat and it COMMITS.
--   (3c) -> #9 cross-tenant INSERT: RED if fn_user_asset_category_asset (or its predicate)
--          were removed -> B references A's per-user asset and it COMMITS.
--   (3d)/(3e) -> RED if the fences did not cover UPDATE -> a re-categorization could pivot to
--          another tenant's Sub-Cat / asset.
--   (4a)/(4b) -> RED if the UPDATE/DELETE USING policy leaked -> B could modify/delete A's row.
--   (5a) -> RED if the ownership forge (B inserting users_id = A) were admitted (fence +
--          WITH CHECK both broken).
--   (6a)/(6b) -> LOAD-BEARING: RED if either fence relied on RLS instead of its explicit
--          users_id predicate -> under RLS-bypass the cross-tenant write would COMMIT. The
--          SOLE assertions that isolate the TRIGGERs from RLS.
--   (6c) -> NON-VACUOUS service_role control: a matched row under service_role COMMITS (the
--          fences are owner-mismatch-driven, not a blanket service_role block).
--   (7)  -> RED if unique(users_id, asset_id) were dropped -> a second categorization of the
--          same (user, asset) would double-insert.
--   (8a) -> RED if anon were granted any reach -> a global-registry table becoming anon-
--          readable is an exposure regression.
--   (8b) -> RED if the DELETE grant/policy were missing -> owner cannot delete own row
--          (authenticated full-CRUD contract broken).
--   (9a)/(9b) -> RED if ON DELETE RESTRICT were relaxed on sub_cat_id / asset_id -> a
--          referenced user_taxonomy / pfin.asset row could be deleted out from under a
--          categorization (orphan).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 022 introduces ZERO
--   catalogued §10 instances — authenticated-tier RLS/FK/trigger DDL + two INVOKER fences;
--   adds no service_role grant, so no RT-26 code-layer surface). Decision-3 family: this
--   migration REALIZES CANONICAL instances #8 (user_asset_category.sub_cat_id -> user_taxonomy,
--   matched-tenant) + #9 (user_asset_category.asset_id -> pfin.asset, the novel global-OR-
--   matched-tenant fence, Pattern 2 site 2 of 2) per the ADR-027 atomic amendment (g) — no
--   new ADR. This battery is the pgTAP proof of BOTH mechanisms (each verified separately),
--   confirming each fence catches a REAL cross-tenant violation. Canonical realized 7 -> 9.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b();
--   NO PII / NO real account numbers / NO prod data. BOTH tenants are populated with their
--   OWN user_taxonomy rows + OWN per-user assets so every matched-tenant PASS and every
--   cross-tenant FAIL has a real referent (non-vacuous). GLOBAL assets are seeded users_id
--   NULL (auth.uid() is NULL under postgres — an omitted/explicit-NULL users_id lands GLOBAL);
--   per-user assets set users_id EXPLICITLY (else they'd land global). All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so
--   NO `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and
--   each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 022's firmed contract; the authoritative run is against the
--   001->022 reset stack. Roles `authenticated` / `service_role` / `anon` name-checked in the
--   blocks; BLOCK 6 service_role SELECT/INSERT grants are held OPEN in-test (rolled back) so the
--   TRIGGER — not a missing ACL — is isolated as the sole gate (a missing grant would 42501
--   'permission denied', a false-RED). Local stack sits at 021 — `supabase test db` cannot
--   reach 022 until Backend applies it; RED-until-022-applied is expected. CI (pg_prove
--   directory-mode, db-tests.yml, after Backend's clean-apply) is the green gate. plan(22).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(22);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Two tenants in auth.users.
--  - user_taxonomy: A owns TWO asset Sub-Cats (a_sub, a_sub2 — a_sub2 is the reassignment
--    target for 1c); B owns ONE (b_sub).
--  - pfin.asset: three GLOBAL assets (users_id NULL — the global-disjunct targets; symbol
--    omitted so the 016 partial-unique(symbol) where users_id is null does not bind); two
--    A-OWNED assets (a_asset, a_asset2 — users_id set EXPLICITLY); one B-OWNED (b_asset —
--    the cross-tenant target the #9 fence must reject).
--  - service_role ACLs held OPEN in-test (rolled back) so the BLOCK 6 fence TRIGGERS — not a
--    missing grant — are the sole gate (022 itself adds NO service_role grant; this is a
--    test-only trigger-isolation device — see the LOAD-BEARING box above).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'ta', 'Brokerage', 'US Equity')
  returning id as a_sub \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'ta', 'Real Estate', 'Primary Home')
  returning id as a_sub2 \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat)
  values (:'tb', 'Brokerage', 'US Equity')
  returning id as b_sub \gset

insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (null, 'equity', 'market_feed', 'Global Sec 1') returning asset_id as g_glob1 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (null, 'equity', 'market_feed', 'Global Sec 2') returning asset_id as g_glob2 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (null, 'equity', 'market_feed', 'Global Sec 3') returning asset_id as g_glob3 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A owned asset 1') returning asset_id as a_asset \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'ta', 'collectible', 'manual_valuation', 'A owned asset 2') returning asset_id as a_asset2 \gset
insert into pfin.asset (users_id, asset_type, pricing_source, name)
  values (:'tb', 'collectible', 'manual_valuation', 'B owned asset') returning asset_id as b_asset \gset

-- Hold the ACLs the BLOCK 6 fence subqueries + inserts need OPEN to service_role (test
-- setup, rolled back). SELECT on user_taxonomy + asset = the fences' read paths; INSERT on
-- user_asset_category = the write path. 022 itself grants service_role NOTHING (POSTURE).
grant usage on schema pfin to service_role;
grant select on pfin.user_taxonomy to service_role;
grant select on pfin.asset to service_role;
grant insert on pfin.user_asset_category to service_role;

-- =====================================================================
-- BLOCK 1 (authenticated A) — matched-tenant PASSes: GLOBAL asset (the whole point),
--   OWNED asset, and a re-categorization UPDATE. users_id lands via DEFAULT auth.uid() = A.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1a) #9 GLOBAL disjunct PASS: A categorizes a GLOBAL asset (users_id NULL) with A's own
--      Sub-Cat -> BOTH fences accept. This is the R-19 raison d'etre (a global asset like VOO
--      is categorizable per-user via the junction).
select lives_ok(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :g_glob1, :a_sub),
  '(1a) #9 GLOBAL disjunct PASS: authenticated A categorizes a GLOBAL asset (asset.users_id IS NULL) with its OWN Sub-Cat -> accepted (the novel global-OR-owned predicate; the whole point of R-19 — a global asset is categorizable per-user)'
);

-- (1b) #9 OWNED disjunct + #8 matched PASS: A categorizes its OWN asset with its OWN Sub-Cat.
select lives_ok(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :a_asset, :a_sub),
  '(1b) #9 OWNED disjunct + #8 matched PASS: authenticated A categorizes its OWN asset (asset.users_id = A) with its OWN Sub-Cat -> accepted (non-vacuous positive)'
);

-- fixture: a third A row on a distinct GLOBAL asset, captured for the UPDATE (1c) + the RLS
-- UPDATE/DELETE isolation probes (4a)/(4b).
insert into pfin.user_asset_category (asset_id, sub_cat_id)
  values (:g_glob2, :a_sub) returning id as uac_upd \gset

-- (1c) matched-tenant re-categorization UPDATE PASS: A moves the row to ANOTHER of its OWN
--      Sub-Cats -> the BEFORE UPDATE fences accept (mutable junction; covers UPDATE not just INSERT).
select lives_ok(
  format($$ update pfin.user_asset_category set sub_cat_id = %s where id = %s $$, :a_sub2, :uac_upd),
  '(1c) matched-tenant re-categorization UPDATE: A reassigns its row to another of ITS OWN Sub-Cats -> both fences ACCEPT (BEFORE INSERT OR UPDATE covers the mutable re-categorization path)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (postgres — _rls verbs) — RLS SELECT isolation, two-tenant.
--   A now owns exactly 3 rows (g_glob1, a_asset, g_glob2).
-- =====================================================================
-- (2a) owner-reads-own: A sees exactly its 3 rows (guards an over-restrictive policy).
select _rls.expect_owner_can_read('pfin.user_asset_category'::regclass, :'ta'::uuid, 3::bigint);

-- (2b) cross-tenant read fails closed: B sees 0 of A's rows (SELECT USING owner-scoping).
select _rls.expect_cross_tenant_read_empty('pfin.user_asset_category'::regclass, :'ta'::uuid, :'tb'::uuid);

-- =====================================================================
-- BLOCK 3 (authenticated B) — the LOAD-BEARING cross-tenant fences (belt-and-suspenders leg,
--   #9 fires first per the firing-order box) + a non-vacuous control + UPDATE coverage.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);

-- (3a) NON-VACUOUS control: B categorizes a GLOBAL asset with its OWN Sub-Cat -> accepted.
--      Proves the (3b)-(3e) raises are cross-tenant-MISMATCH-driven (not a blanket B block)
--      AND that the global disjunct is TENANT-AGNOSTIC (any tenant may tag a global asset).
select lives_ok(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :g_glob1, :b_sub),
  '(3a) control: B categorizes a GLOBAL asset with its OWN Sub-Cat -> ACCEPTED (proves the cross-tenant raises below are mismatch-driven, and the #9 global disjunct is tenant-agnostic)'
);

-- fixture: B's own row (own asset + own Sub-Cat), captured for the cross-tenant UPDATEs (3d)/(3e).
insert into pfin.user_asset_category (asset_id, sub_cat_id)
  values (:b_asset, :b_sub) returning id as uac_b \gset

-- (3b) #8 cross-tenant INSERT: B tags a GLOBAL asset (asset PASSES #9) with A's Sub-Cat.
--      #8 reads user_taxonomy(id=A's sub_cat, users_id=B) -> NOT EXISTS (A's row is users_id=A
--      AND RLS-invisible to B) -> RAISE. Necessary but not sufficient (RLS also hides it);
--      (6a) isolates the trigger.
select throws_like(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :g_glob2, :a_sub),
  'cross-tenant Sub-Cat rejected%',
  '(3b) #8 cross-tenant INSERT: B categorizes a global asset with A''s Sub-Cat -> fn_user_asset_category_matched_sub_cat RAISES (NOT EXISTS matched-tenant row; the chain-attack Decision-3 #8 fences — a real violation, not a silent pass)'
);

-- (3c) #9 cross-tenant INSERT: B references A's per-user asset (asset FAILS #9, fires first)
--      with B's own Sub-Cat. -> RAISE 'cross-tenant asset rejected'.
select throws_like(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :a_asset, :b_sub),
  'cross-tenant asset rejected%',
  '(3c) #9 cross-tenant INSERT: B references A''s per-user asset -> fn_user_asset_category_asset RAISES (asset neither global nor B-owned; the novel Pattern-2 fence catches a real cross-tenant asset reference)'
);

-- (3d) #8 cross-tenant UPDATE: B re-points its own row's Sub-Cat to A's -> BEFORE UPDATE #8
--      RAISES (asset unchanged b_asset PASSES #9). Confirms #8 covers UPDATE/reassignment.
select throws_like(
  format($$ update pfin.user_asset_category set sub_cat_id = %s where id = %s $$, :a_sub, :uac_b),
  'cross-tenant Sub-Cat rejected%',
  '(3d) #8 cross-tenant UPDATE: B reassigns its own row to A''s Sub-Cat -> #8 RAISES (matched-tenant fence covers UPDATE — a re-categorization cannot pivot to another tenant''s Sub-Cat)'
);

-- (3e) #9 cross-tenant UPDATE: B re-points its own row's asset to A's -> BEFORE UPDATE #9
--      RAISES (asset FAILS #9, fires first). Confirms #9 covers UPDATE.
select throws_like(
  format($$ update pfin.user_asset_category set asset_id = %s where id = %s $$, :a_asset, :uac_b),
  'cross-tenant asset rejected%',
  '(3e) #9 cross-tenant UPDATE: B re-points its own row to A''s per-user asset -> #9 RAISES (novel fence covers UPDATE — a re-categorization cannot pivot to another tenant''s asset)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 4 (authenticated B -> postgres asserts) — RLS UPDATE/DELETE isolation (USING).
--   B's write statements target A's row (uac_upd); RLS USING filters it out -> 0 rows
--   affected (silently, no fence — no matching row). The assertions prove A's row survives
--   UNCHANGED, isolating the UPDATE/DELETE USING owner-scoping.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
update pfin.user_asset_category set sub_cat_id = :b_sub where id = :uac_upd;  -- 0 rows (RLS hides A's row)
delete from pfin.user_asset_category where id = :uac_upd;                     -- 0 rows (RLS hides A's row)
select set_config('role', 'postgres', true);

-- (4a) cross-tenant UPDATE blocked: A's row still carries a_sub2 (from 1c) — B's UPDATE
--      touched 0 rows (UPDATE USING owner-scoping).
select is(
  (select sub_cat_id from pfin.user_asset_category where id = :uac_upd),
  :a_sub2::bigint,
  '(4a) cross-tenant UPDATE blocked: after B''s UPDATE targeting A''s row, the row is UNCHANGED (still a_sub2) — the UPDATE USING policy scoped B to its own rows (0 rows affected)'
);

-- (4b) cross-tenant DELETE blocked: A's row still present — B's DELETE touched 0 rows.
select is(
  (select count(*) from pfin.user_asset_category where id = :uac_upd)::bigint,
  1::bigint,
  '(4b) cross-tenant DELETE blocked: after B''s DELETE targeting A''s row, the row still EXISTS — the DELETE USING policy scoped B to its own rows (0 rows affected)'
);

-- =====================================================================
-- BLOCK 5 (authenticated B) — ownership forge (WITH CHECK, shadowed by the #8 BEFORE fence).
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
-- (5a) B forges a row OWNED BY A (users_id = A) on a GLOBAL asset (PASSES #9) with B's own
--      Sub-Cat. new.users_id = A, so #8 needs A to own the Sub-Cat -> NOT EXISTS -> RAISE
--      (before the uac_insert RLS WITH CHECK is evaluated). The row owned by A never lands.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (%L, %s, %s) $$, :'ta', :g_glob3, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(5a) ownership forge fails closed: B inserts users_id = A (forging a row owned by A) -> the #8 BEFORE fence RAISES before the uac_insert RLS WITH CHECK is even reached (both would block; belt-and-suspenders) — B cannot create a row owned by A'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 6 (service_role — RLS BYPASSED) — THE LOAD-BEARING LEG: prove the EXPLICIT users_id
--   predicates (not RLS) are the gate. B's Sub-Cat + B's asset are VISIBLE to the subqueries
--   under RLS-bypass; only the trigger predicate rejects. users_id set EXPLICITLY (= A) since
--   auth.uid() is NULL under service_role. Test-only isolation (022 grants service_role none).
-- =====================================================================
select set_config('role', 'service_role', true);

-- (6a) LOAD-BEARING #8: users_id = A, an A-OWNED asset (PASSES #9), B's Sub-Cat. Under
--      RLS-bypass B's Sub-Cat IS visible, but the explicit `= new.users_id (A)` predicate
--      mismatches -> RAISE. Proves #8's predicate, not user_taxonomy RLS, is the gate.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (%L, %s, %s) $$, :'ta', :a_asset2, :b_sub),
  'cross-tenant Sub-Cat rejected%',
  '(6a) LOAD-BEARING #8 under service_role: RLS BYPASSED (B''s Sub-Cat IS visible), yet the cross-tenant Sub-Cat STILL RAISES — the explicit users_id predicate (NOT user_taxonomy RLS) is the sole gate'
);

-- (6b) LOAD-BEARING #9: users_id = A, B's per-user asset (FAILS #9, fires first), A's Sub-Cat.
--      Under RLS-bypass B's asset IS visible, but neither global nor A-owned -> RAISE.
--      Proves #9's predicate, not 016 asset RLS, is the gate.
select throws_like(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (%L, %s, %s) $$, :'ta', :b_asset, :a_sub),
  'cross-tenant asset rejected%',
  '(6b) LOAD-BEARING #9 under service_role: RLS BYPASSED (B''s asset IS visible), yet referencing B''s per-user asset STILL RAISES — the explicit global-OR-owned predicate (NOT 016 asset RLS) is the sole gate'
);

-- (6c) non-vacuous service_role control: users_id = A, an A-OWNED asset (PASSES #9), A's
--      Sub-Cat (PASSES #8) -> COMMITS. The fences are owner-mismatch-driven, not a blanket block.
select lives_ok(
  format($$ insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values (%L, %s, %s) $$, :'ta', :a_asset2, :a_sub),
  '(6c) control: a matched (A-owned asset + A''s Sub-Cat, users_id=A) row under service_role COMMITS -> the fences do not blanket-block; they are owner-mismatch-driven (non-vacuous service_role control)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 7 (authenticated A) — unique(users_id, asset_id): one categorization per (user, asset).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (7) A re-categorizes an asset it has ALREADY categorized ((A, a_asset) from 1b) -> both
--     fences PASS (own asset + own Sub-Cat), then the unique index RAISES 23505.
select throws_ok(
  format($$ insert into pfin.user_asset_category (asset_id, sub_cat_id) values (%s, %s) $$, :a_asset, :a_sub2),
  '23505', null,
  '(7) unique(users_id, asset_id): a SECOND categorization of the same (user, asset) is REJECTED (unique_violation 23505) — one allocation class per user per asset; the fences pass first, so the unique index is the sole gate'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 8 (grants) — anon zero-grant + authenticated DELETE (full-CRUD contract).
-- =====================================================================
-- (8a) anon has NO USAGE on schema pfin -> even SELECT is denied at the ACL layer (42501),
--      before RLS is consulted.
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.user_asset_category',
  '42501', null,
  '(8a) anon zero-grant: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (insufficient_privilege 42501), before RLS — the table is not anon-reachable'
);
select set_config('role', 'postgres', true);

-- (8b) authenticated DELETE positive (completes the CRUD contract): A deletes its OWN row
--      (RLS scopes to A — B's row on the same global asset is untouched).
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ delete from pfin.user_asset_category where asset_id = %s $$, :g_glob1),
  '(8b) authenticated DELETE: A deletes its OWN row (RLS DELETE USING scopes to A; B''s row on the same global asset is untouched) -> owner full-CRUD delete works'
);
select set_config('role', 'postgres', true);

-- (8b/verify) A's g_glob1 row is gone; B's g_glob1 row (3a) survives.
select is(
  (select count(*) from pfin.user_asset_category where users_id = :'ta' and asset_id = :g_glob1)::bigint,
  0::bigint,
  '(8b/verify) after A''s owner-DELETE, A''s row on that global asset is GONE (0) — the delete really applied and stayed owner-scoped'
);

-- =====================================================================
-- BLOCK 9 (postgres) — ON DELETE RESTRICT on BOTH FKs (fail-loud referential integrity).
--   A's (a_asset, a_sub) row (1b) is still present -> both a_sub and a_asset are referenced.
-- =====================================================================
-- (9a) sub_cat_id ON DELETE RESTRICT: deleting a user_taxonomy row still referenced is blocked.
select throws_ok(
  format($$ delete from pfin.user_taxonomy where id = %s $$, :a_sub),
  '23503', null,
  '(9a) sub_cat_id ON DELETE RESTRICT: deleting a user_taxonomy row still referenced by a categorization is RESTRICTED (foreign_key_violation 23503) — no orphaned Sub-Cat reference'
);

-- (9b) asset_id ON DELETE RESTRICT: deleting a pfin.asset row still referenced is blocked.
select throws_ok(
  format($$ delete from pfin.asset where asset_id = %s $$, :a_asset),
  '23503', null,
  '(9b) asset_id ON DELETE RESTRICT: deleting a pfin.asset row still referenced by a categorization is RESTRICTED (foreign_key_violation 23503) — no orphaned asset reference'
);

select * from finish();
rollback;
