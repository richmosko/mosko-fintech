-- =====================================================================
-- Per-Wave battery — pfin.account provider-linked mapping dedup + #6 fence exercise
--   (provider-sync account-mapping slice / 021 — ADR-027 amendment; C6 EXPOSURE-GATING
--    per ADR-023 / SECURITY §4.5; V1-SHIP-BLOCK; sec-joint-review-mandatory)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/021_account_linked_source_dedup.sql
--   - partial UNIQUE index pfin.account_linked_source_provider_uidx
--       ON pfin.account (linked_source_id, provider_account_id)
--       WHERE linked_source_id IS NOT NULL
--     (structural idempotency for the account-mapping re-run — one canonical pfin.account
--      row per (linked_source, provider account); the ON CONFLICT arbiter for landAccounts;
--      manual/unlinked rows [linked_source_id NULL] EXEMPT by the partial predicate).
--   This migration adds NO function / NO RLS / NO new Decision-3 instance — it EXERCISES the
--   Decision-3 CANONICAL instance #6 fence authored at 015 (see below), and adds one index.
-- Prereqs exercised (already on main):
--   003 — pfin.account RLS/GRANT (users_id = auth.uid()) + fn_grant_creator_access AFTER
--         INSERT creator-grant trigger (fires ONE pfin.account_users row per account INSERT —
--         the load-bearing referent for the trigger-no-refire assertion (7)).
--   015 STEP 7/8 — account.linked_source_id + account.provider_account_id columns +
--         fn_account_matched_linked_source (SECURITY INVOKER; BEFORE INSERT OR UPDATE ON
--         pfin.account WHEN (new.linked_source_id IS NOT NULL); NULL-safe fail-closed
--         NOT EXISTS -> raise 'cross-tenant linked_source rejected%'; Decision-3 instance #6).
--   pfin.linked_source (015) — the FK target + tenant anchor; provider='snaptrade' rows here
--         (account-mapping provider), credential_secret_id NULL (credential-less -> no Vault
--         secret, nothing real enters CI); external_connection_id distinct per (provider, id) uidx.
-- Reuses the SELF-187/189/190/196/231/012/015 idiom: \ir verbs, ALL-LOWERCASE \gset literals
--   (005 case-fold lesson), SQLSTATE-precise throws_ok + message-precise throws_like (004
--   all-42501 false-green lesson), role restored to postgres between blocks (PR #121 _rls-USAGE
--   root-cause). The account-mapping write runs INVOKER/withTenant (ratified Q1) -> every mapping
--   assertion runs under authenticated A so the index + #6 fence are proven to COMPOSE with RLS,
--   not just fire as raw constraints under a privileged session.
--
-- ┌─ WHY THE DEDUP + TRIGGER-NO-REFIRE ASSERTIONS HAVE TEETH (load-bearing (5)/(6)/(7)/(8)) ─┐
-- │ landAccounts is idempotent by CONSTRUCTION: it INSERTs each provider account              │
-- │   ON CONFLICT (linked_source_id, provider_account_id) WHERE linked_source_id IS NOT NULL   │
-- │   DO NOTHING. A re-run (connect+map on the same source again) MUST NOT:                    │
-- │   (a) mint a 2nd pfin.account row  -> (6) asserts the (source,provider_account) count      │
-- │       stays exactly 1 after the DO-NOTHING re-map;                                         │
-- │   (b) mint a 2nd account_users creator-grant row -> (7) asserts account_users count is     │
-- │       UNCHANGED. This is the subtle one: the fn_grant_creator_access AFTER INSERT trigger  │
-- │       must NOT fire on a DO-NOTHING skip (no row inserted -> no AFTER INSERT). (3) captures │
-- │       the baseline = 1 (the trigger DOES fire on the REAL insert — non-vacuous contrast).  │
-- │ (8) proves the INDEX ITSELF is the structural invariant (bare duplicate INSERT without     │
-- │   ON CONFLICT -> 23505 unique_violation), independent of the app's ON CONFLICT clause —    │
-- │   so a code path that forgot the arbiter still cannot duplicate a mapping.                 │
-- │ (4) is the non-vacuous specificity control: the SAME source with a DIFFERENT               │
-- │   provider_account_id coexists -> the dedup keys on the (source, provider account) PAIR,   │
-- │   not on the source (the index is not over-broad; one source legitimately holds many       │
-- │   provider accounts).                                                                      │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THE #6 FENCE ASSERTION HAS TEETH (load-bearing (9)) ─────────────────────────────────┐
-- │ fn_account_matched_linked_source is SECURITY INVOKER. Under authenticated A mapping its    │
-- │ OWN account (users_id = A via the 003 WITH CHECK) to B's source, the trigger reads:        │
-- │ EXISTS linked_source WHERE source_id = <B's> AND users_id = A. TWO independent reasons this │
-- │ is empty: (i) B's source is users_id = B (matched-tenant predicate excludes it); (ii)      │
-- │ linked_source RLS scopes the INVOKER read to auth.uid() = A, so B's row is RLS-INVISIBLE.   │
-- │ NOT EXISTS -> RAISE. We assert the RAISE MESSAGE ('cross-tenant linked_source rejected%') — │
-- │ NOT a bare 42501, NOT a 23503 FK violation, NOT a silent pass. The (1)/(2) matched positive │
-- │ is the non-vacuous control proving the raise is MISMATCH-driven, not a blanket A block.     │
-- │ (015's battery exercised B->A's source; 021 exercises A->B's source through the mapping     │
-- │ write path — the complementary direction, proving the fence composes with THIS slice.)     │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   (1)  -> non-vacuous positive: A maps its OWN account to its OWN source -> ACCEPTED. RED if the
--           #6 fence or the dedup index over-broadly blocked a legitimate first mapping.
--   (2)  -> RED if the mapped row were stamped with the wrong tenant (users_id must DEFAULT to A =
--           auth.uid(); the whole idempotency + isolation argument rests on un-forgeable users_id).
--   (3)  -> baseline: RED if the creator-grant trigger did NOT fire on the real insert (proves it
--           DOES mint exactly one account_users row per account — the referent (7) contrasts against).
--   (4)  -> non-vacuous specificity: RED if the index keyed on linked_source_id alone (a 2nd
--           provider account on the same source would be wrongly rejected — the dedup is per-PAIR).
--   (5)  -> RED if the ON CONFLICT arbiter did not match the partial index (the landAccounts re-run
--           would raise instead of no-op — a re-map would crash the mapping worker).
--   (6)  -> LOAD-BEARING: RED if the unique index were dropped/mis-keyed -> the DO-NOTHING re-map
--           would mint a 2nd pfin.account row (duplicate mapping — the exact thing 021 fences).
--   (7)  -> LOAD-BEARING (the subtle one): RED if the AFTER INSERT creator-grant trigger fired on a
--           DO-NOTHING skip -> a 2nd account_users grant row per re-map (grant-row inflation).
--   (8)  -> RED if the unique index were absent -> a bare duplicate INSERT (no ON CONFLICT) would
--           COMMIT a second row; the index is the structural invariant, not just the app clause.
--   (9)  -> LOAD-BEARING: RED if fn_account_matched_linked_source (or its trigger) were removed, or
--           the users_id predicate dropped -> A's cross-tenant mapping to B's source would COMMIT
--           (the exact chain-attack Decision-3 instance #6 fences, exercised via the mapping path).
--   (10) -> non-vacuous positive: a 2nd manual/unlinked account (linked_source_id NULL) inserts.
--   (11) -> RED if the index predicate were NOT partial (WHERE linked_source_id IS NOT NULL) -> two
--           unlinked rows [(NULL, NULL)] would collide; manual accounts (SELF-201) must coexist.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 2 (RT-22 + RT-26; 021 is index-only — no
--   infra-credential/service_role-key surface; authenticated-tier INVOKER write path per the 021
--   header §10 3-axis, Path B). Decision-3 family UNCHANGED at 8 (021 adds NO FK-shaped column;
--   provider_account_id is TEXT, linked_source_id already carries canonical instance #6). THIS
--   battery is the pgTAP proof that (a) the 021 dedup invariant holds AND (b) the #6 fence catches
--   a REAL cross-tenant mapping violation (per the 021 header QA TEST-PAIRING; Sec joint-review).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b(); NO PII /
--   NO real account numbers / NO real credentials (SD-03) / NO prod data. linked_source rows carry
--   provider='snaptrade' with credential_secret_id NULL (credential-less) — no Vault secret created.
--   linked_source rows are seeded PRIVILEGED (role=postgres — the credential store has no
--   authenticated write path, Decision 1); pfin.account rows are created via the APP PATH under
--   authenticated (users_id DEFAULT auth.uid()) exactly as the account-mapping write runs. All in a
--   rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. Tenant UUIDs + row ids are resolved to psql LITERALS via
--   \gset at role=postgres; every _rls.set_tenant is called at role=postgres and each block restores
--   role=postgres before the next. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 021's firmed contract; the authoritative run is against the
--   001->021 reset stack. Roles `authenticated` name-checked in the blocks. RED-until-021-applied is
--   expected on any pre-021 stack (the unique index absent -> (6)/(8) would not hold).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(11);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — the sole linked_source write path). Two tenants in
-- auth.users; A owns ONE source, B owns ONE source. provider='snaptrade' (account-mapping
-- provider) + credential_secret_id NULL (credential-less -> no Vault secret); external_connection_id
-- distinct to satisfy the (provider, external id) unique index. users_id set explicitly (auth.uid()
-- is NULL under postgres).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'ta', 'snaptrade', 'conn-a-1', 'Synthetic Brokerage A')
  returning source_id as a_src1 \gset
insert into pfin.linked_source (users_id, provider, external_connection_id, institution_name)
  values (:'tb', 'snaptrade', 'conn-b-1', 'Synthetic Brokerage B')
  returning source_id as b_src1 \gset

-- =====================================================================
-- BLOCK 1 (authenticated A) — owner positive mapping + tenant stamping + per-pair specificity +
--   dedup idempotency (DO NOTHING no-op) + trigger-no-refire + bare-duplicate index teeth.
--   Accounts are created via the APP PATH (users_id DEFAULT auth.uid() = A); the 003 DEFINER
--   creator-grant trigger fires once per real INSERT.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (1) owner positive path: A maps a fresh account to its OWN source (with provider_account_id)
--     -> fn_account_matched_linked_source ACCEPTS + the dedup index admits the first mapping.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
              values ('A mapped acct 1', 'investment', 'household', 'taxable', %s, 'ext-a-1') $$, :a_src1),
  '(1) owner positive: A maps its OWN account to its OWN linked_source (provider_account_id ext-a-1) -> ACCEPTED (the #6 fence + the dedup index admit a legitimate first mapping, non-vacuous positive)'
);

-- capture the canonical mapped account_id (authenticated A; RLS-visible) for the count assertions.
select account_id as acct_a1 from pfin.account
  where linked_source_id = :a_src1 and provider_account_id = 'ext-a-1' \gset

-- (2) correct tenant stamping: the mapped row carries users_id = A (un-forgeable, DEFAULT auth.uid()).
select is(
  (select users_id from pfin.account where account_id = :acct_a1),
  :'ta'::uuid,
  '(2) correct tenant stamping: the mapped account is stamped users_id = A (DEFAULT auth.uid(); the isolation + idempotency argument rests on an un-forgeable tenant anchor)'
);

-- (3) baseline creator-grant: the 003 AFTER INSERT trigger minted EXACTLY ONE account_users row
--     for the mapped account (the referent (7) contrasts against — proves the trigger DOES fire).
select is(
  (select count(*) from pfin.account_users where account_id = :acct_a1)::bigint,
  1::bigint,
  '(3) baseline creator-grant: fn_grant_creator_access minted exactly ONE account_users row on the real mapping INSERT (non-vacuous referent for the trigger-no-refire assertion)'
);

-- (4) per-pair specificity control: the SAME source with a DIFFERENT provider_account_id coexists
--     -> the dedup keys on the (linked_source_id, provider_account_id) PAIR, not on the source.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
              values ('A mapped acct 2', 'investment', 'household', 'taxable', %s, 'ext-a-2') $$, :a_src1),
  '(4) per-pair specificity: A maps a SECOND provider account (ext-a-2) on the SAME source -> ACCEPTED (dedup keys on the (source, provider_account) PAIR — one source legitimately holds many provider accounts; the index is not over-broad)'
);

-- (5) dedup idempotency: a re-map of the SAME (a_src1, ext-a-1) via the landAccounts ON CONFLICT
--     arbiter is a no-op (no error) — the partial-index arbiter matches, DO NOTHING skips.
select lives_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
              values ('A re-map dup', 'investment', 'household', 'taxable', %s, 'ext-a-1')
              on conflict (linked_source_id, provider_account_id) where linked_source_id is not null
              do nothing $$, :a_src1),
  '(5) dedup idempotency: a re-run re-map of the SAME (source, provider_account) via ON CONFLICT ... DO NOTHING (the landAccounts arbiter) is a NO-OP (no error — the arbiter matches the partial unique index)'
);

-- (6) LOAD-BEARING: after the DO-NOTHING re-map, the (source, provider_account) still resolves to
--     EXACTLY ONE pfin.account row (no duplicate mapping row was minted).
select is(
  (select count(*) from pfin.account where linked_source_id = :a_src1 and provider_account_id = 'ext-a-1')::bigint,
  1::bigint,
  '(6) LOAD-BEARING no-duplicate-row: after the DO-NOTHING re-map, (a_src1, ext-a-1) still resolves to exactly 1 pfin.account row (the unique index prevented a 2nd mapping row)'
);

-- (7) LOAD-BEARING (the subtle one): the AFTER INSERT creator-grant trigger did NOT fire on the
--     DO-NOTHING skip -> account_users count for the mapped account is UNCHANGED (still 1).
select is(
  (select count(*) from pfin.account_users where account_id = :acct_a1)::bigint,
  1::bigint,
  '(7) LOAD-BEARING trigger-no-refire: after the DO-NOTHING re-map, account_users for the mapped account is UNCHANGED at 1 (no row inserted -> the AFTER INSERT creator-grant trigger did not fire -> no grant-row inflation)'
);

-- (8) index teeth: a bare duplicate INSERT (NO ON CONFLICT) of the SAME (a_src1, ext-a-1) violates
--     the partial unique index -> 23505 unique_violation (the structural invariant, independent of
--     the app's ON CONFLICT clause — a code path that forgot the arbiter still cannot duplicate).
select throws_ok(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
              values ('A bare dup', 'investment', 'household', 'taxable', %s, 'ext-a-1') $$, :a_src1),
  '23505', null,
  '(8) index teeth: a bare duplicate INSERT (no ON CONFLICT) of (a_src1, ext-a-1) raises unique_violation (23505) — account_linked_source_provider_uidx is the structural invariant, not just the app ON CONFLICT clause'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 2 (authenticated A) — THE #6 FENCE, exercised via the mapping write path. A maps its OWN
--   account (users_id = A) to B's source -> fn_account_matched_linked_source RAISES. The
--   complementary direction to 015's B->A case; proves the fence composes with THIS slice + RLS.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (9) LOAD-BEARING cross-tenant mapping fails closed: A maps its own account to B's source_id. The
--     BEFORE INSERT fence reads linked_source(source_id=B's, users_id=A) -> NOT EXISTS (B's row is
--     users_id=B AND RLS-invisible to A) -> RAISE. Assert the RAISE (not a silent pass, not a bare
--     42501, not a 23503 FK violation).
select throws_like(
  format($$ insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id, provider_account_id)
              values ('A steals B source', 'investment', 'household', 'taxable', %s, 'ext-b-1') $$, :b_src1),
  'cross-tenant linked_source rejected%',
  '(9) LOAD-BEARING cross-tenant mapping: A maps its own account to B''s linked_source_id -> fn_account_matched_linked_source RAISES (NOT EXISTS matched-tenant row; the exact chain-attack Decision-3 instance #6 fences, exercised via the account-mapping write path — a real violation, not a silent pass)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK 3 (authenticated A) — partial-index EXEMPTION for manual/unlinked accounts (SELF-201).
--   Two accounts with linked_source_id NULL are OUTSIDE the partial index (WHERE linked_source_id
--   IS NOT NULL) -> they coexist even with identical (NULL, NULL) key. A user holds many manual
--   accounts; the dedup must NOT fence them.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- fixture: a first manual/unlinked account (linked_source_id NULL, provider_account_id NULL).
insert into pfin.account (name, account_type, scope, tax_treatment)
  values ('A manual acct 1', 'depository', 'household', 'taxable');

-- (10) EXEMPTION positive: a SECOND unlinked account [identical (NULL, NULL) key] inserts cleanly.
select lives_ok(
  $$ insert into pfin.account (name, account_type, scope, tax_treatment)
       values ('A manual acct 2', 'depository', 'household', 'taxable') $$,
  '(10) partial-index EXEMPTION: a 2nd manual/unlinked account (linked_source_id NULL) inserts cleanly -> the partial predicate (WHERE linked_source_id IS NOT NULL) exempts unlinked rows (non-vacuous positive)'
);

-- (11) both unlinked accounts coexist: A sees exactly 2 unlinked accounts (the partial index does
--      NOT fence NULL-linked rows — two (NULL, NULL) keys are not a collision).
select is(
  (select count(*) from pfin.account where linked_source_id is null)::bigint,
  2::bigint,
  '(11) EXEMPTION coexistence: A holds exactly 2 unlinked accounts (linked_source_id NULL) -> the partial index does not fence unlinked rows (manual accounts SELF-201 coexist; the dedup binds only provider-linked rows)'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
