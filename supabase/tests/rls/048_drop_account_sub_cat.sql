-- =====================================================================
-- Per-Wave battery — DROP of the account-level asset Sub-Category surface
--   (SELF-319 / 048 — Decision-3 CANONICAL instance #5 DROPPED; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/048_drop_account_sub_cat.sql
--   Migration 048 physically REMOVES the account-level asset Sub-Cat feature (dead
--   schema after v1.132 — no surface read or wrote account.sub_cat_id):
--     (1) trigger  pfin.account.account_matched_sub_cat            (was 012)
--     (2) function pfin.fn_account_matched_sub_cat()               (was 012) — the
--         Decision-3 CANONICAL instance #5 matched-tenant fence.
--     (3) column   pfin.account.sub_cat_id -> pfin.user_taxonomy(id) (was 012)
--     (4) param    p_sub_cat_id on pfin.fn_create_manual_account   (was 013): a
--         SIGNATURE change (7-arg -> 6-arg) — DROP FUNCTION + recreate (INVOKER, 6-arg).
--
-- WHAT THIS BATTERY PROVES: that the drop ACTUALLY HAPPENED, and — the de-conflation
--   guard — that it did NOT over-reach into the TRANSACTION-level sub_cat surface (a
--   DIFFERENT, LIVE feature). This is the inverse of a normal RLS battery: the invariant
--   is now the ABSENCE of the fence, because the column it guarded is gone. The former
--   fn_account_matched_sub_cat cross-tenant coverage (old 012 assertions (1a)/(1b)/(1c)/
--   (2a)/(2b)/(2c)/(3)/(6) and old 013 (3a)/(3b)/(5)) is RETIRED with the surface it
--   guarded; this file replaces it.
--
-- NON-VACUITY (this whole file goes RED on any pre-048 stack — that is the point):
--   (1)-(3) hasnt_* -> RED if 048 had NOT run (column/trigger/function still present).
--   (4)     has_function 6-arg -> RED if 048 had NOT run (only the 7-arg overload existed).
--   (5)     hasnt_function 7-arg -> RED if 048 had NOT run (the 7-arg overload still existed).
--   (6)/(7) function_privs_is on the 6-arg -> RED if the recreated grant were wrong
--           (EXECUTE not granted to authenticated, or leaked to anon).
--   (8)     positive create -> RED if the 6-arg create path did not work under a real tenant.
--   (9)-(12) de-conflation spot-asserts -> RED if 048 had ALSO dropped the transaction-level
--           sub_cat surface (account_trans_annotation #10 + account_trans_split #13 + their
--           matched-tenant fences) — a real over-reach failure mode this migration guards against.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27 per ADR-011 Decision 4;
--   this drop touches NO catalogued instance — authenticated-tier RLS/FK/column DROP; the
--   create path uses NO service_role, so the RT-26 code-layer key allowlist is untouched).
--   Decision-3 family: instance #5 transitions to the THIRD status class — DROPPED
--   (built-then-removed), distinct from DDL-realized and DDL-deferred; the label #5 is STABLE
--   and NEVER reused (ADR-011 D3 "Enumeration DROP resolution (SELF-319 / 048)"). COUNT MOVE:
--   15 labeled / 13 DDL-realized -> 15 labeled / 12 DDL-realized. #6-#15 unchanged; #10 + #13
--   (the transaction-level sub_cat fences) remain REALIZED — asserted present at (9)-(12).
--   Precedent-setting ledger event -> F/CTO-RATIFY + Sec-JOINT-REVIEW mandatory (per 048 header).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenant from _rls.tenant_a();
--   NO PII / NO real account numbers / NO prod data. Catalog assertions ((1)-(7), (9)-(12))
--   are role-independent (pg_catalog / information_schema shape); (8) exercises the 6-arg
--   create under a synthetic authenticated tenant. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call runs under authenticated. The tenant UUID is resolved to a psql literal via
--   \gset at role=postgres; the single _rls.set_tenant (for (8)) is called at role=postgres and
--   the block restores role=postgres after. \gset var names are ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 048's firmed contract; the authoritative run is against the
--   001->048 reset stack. Verified locally 2026-08-01 against the already-migrated local DB
--   (048 applied: sub_cat_id / trigger / fn absent, fn_create_manual_account is 6-arg).
--   RED-until-048-applied is EXPECTED on any pre-048 stack — the drop assertions invert.
--
-- RECONCILED AT 087 (SELF-325) — fn_create_manual_account DROP + CREATE AGAIN,
--   this time 6-arg -> 7-arg (adds p_positions jsonb default '[]'::jsonb).
--   GROUP B (4)/(6)/(7) named the 6-arg signature by an EXACT regprocedure/
--   argument-type list; (4) uses has_function (SOFT — a catalog lookup, not a
--   cast, so it just goes RED rather than erroring the file); (6)/(7) use
--   has_function_privilege's regprocedure CAST (HARD — errors the whole file
--   with "function ... does not exist" once the 6-arg signature is gone from
--   pg_proc, MEASURED against 087's live catalog). Re-targeted to the 7-arg
--   signature below; substance UNCHANGED (still proving the recreated RPC's
--   grant is correct + anon-denied). (5) is LEFT ALONE — it asserts a
--   DIFFERENT, older 7-arg overload (...,bigint, the pre-048 p_sub_cat_id
--   signature) does not exist, which stays true (087's 7th arg is jsonb, not
--   bigint) and re-targeting it would assert the wrong thing. (8)'s 6-
--   positional-arg CALL is unaffected (087's 7th param defaults). The NEW
--   p_positions properties are proved by SELF-325's own battery,
--   supabase/tests/rls/087_manual_account_value_binding_rls.sql.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(12);

-- =====================================================================
-- GROUP A — the DROP actually happened (catalog assertions; role-independent).
-- =====================================================================

-- (1) the column is GONE.
select hasnt_column(
  'pfin', 'account', 'sub_cat_id',
  '(1) DROP: pfin.account.sub_cat_id column does NOT exist (Decision-3 #5 column removed at 048)'
);

-- (2) the trigger binding is GONE.
select hasnt_trigger(
  'pfin', 'account', 'account_matched_sub_cat',
  '(2) DROP: trigger account_matched_sub_cat on pfin.account does NOT exist (the matched-tenant BEFORE INSERT/UPDATE binding removed at 048)'
);

-- (3) the matched-tenant fence function is GONE (no-arg signature).
select hasnt_function(
  'pfin', 'fn_account_matched_sub_cat', '{}'::text[],
  '(3) DROP: function pfin.fn_account_matched_sub_cat() does NOT exist (the Decision-3 #5 fence fn removed at 048)'
);

-- =====================================================================
-- GROUP B — fn_create_manual_account is now the 6-arg signature (7-arg overload gone).
-- =====================================================================

-- (4) the 7-arg signature EXISTS (RECONCILED AT 087 — the recreated INVOKER
--     write-composition RPC, now with p_positions jsonb).
select has_function(
  'pfin', 'fn_create_manual_account',
  ARRAY['text','text','text','text','numeric','date','jsonb'],
  '(4) SIGNATURE: pfin.fn_create_manual_account(text,text,text,text,numeric,date,jsonb) EXISTS — the 7-arg INVOKER RPC (p_sub_cat_id param dropped at 048; p_positions jsonb added at 087)'
);

-- (5) the 7-arg overload is GONE (the DROP FUNCTION removed the p_sub_cat_id signature).
select hasnt_function(
  'pfin', 'fn_create_manual_account',
  ARRAY['text','text','text','text','numeric','date','bigint'],
  '(5) SIGNATURE: the 7-arg pfin.fn_create_manual_account(...,bigint) overload does NOT exist — the p_sub_cat_id signature was DROPped at 048 (no lingering overload)'
);

-- (6) EXECUTE granted to authenticated on the 6-arg (the create path is authenticated-tier).
--     has_function_privilege is the proven idiom (see 013 (6a)) — role-independent catalog probe.
select ok(
  has_function_privilege(
    'authenticated',
    'pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb)',
    'EXECUTE'),
  '(6) GRANT: authenticated holds EXECUTE on the 7-arg fn_create_manual_account (the recreated grant is correct — the write RPC is authenticated-callable)'
);

-- (7) anon holds NO privilege on the 6-arg (EXECUTE revoked from PUBLIC, granted authenticated only).
select ok(
  not has_function_privilege(
    'anon',
    'pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb)',
    'EXECUTE'),
  '(7) GRANT: anon holds NO EXECUTE on the 7-arg fn_create_manual_account (revoked from PUBLIC — the write RPC is not anon-callable)'
);

-- (8) the 6-arg create path WORKS under a real tenant: returns an account_id (NOT NULL).
--     Fixture: one synthetic tenant; the 003 creator-grant trigger + 006 wr_access-JOIN make
--     the two-statement INVOKER body succeed under the caller's RLS.
insert into auth.users (id) values (_rls.tenant_a());
select _rls.tenant_a() as ta \gset
select _rls.set_tenant(:'ta'::uuid);
select isnt(
  pfin.fn_create_manual_account('A create via 6-arg', 'depository', 'household', 'taxable', 1000, '2026-04-01'),
  null::bigint,
  '(8) 6-arg create path: fn_create_manual_account returns a non-NULL account_id under a real authenticated tenant (the recreated 6-arg body atomically creates account + acct_setup row and works)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- GROUP C — DE-CONFLATION GUARD: the TRANSACTION-level sub_cat surface is a DIFFERENT, LIVE
--   feature (Decision-3 #10 + #13) and must be UNTOUCHED by 048. RED if the drop over-reached.
-- =====================================================================

-- (9) account_trans_annotation.sub_cat_id (#10) still EXISTS.
select has_column(
  'pfin', 'account_trans_annotation', 'sub_cat_id',
  '(9) DE-CONFLATION: pfin.account_trans_annotation.sub_cat_id (transaction-level cashflow class, Decision-3 #10) STILL EXISTS — 048 did NOT touch the transaction-level surface'
);

-- (10) the #10 matched-tenant fence fn still EXISTS.
select has_function(
  'pfin', 'fn_account_trans_annotation_matched_sub_cat', '{}'::text[],
  '(10) DE-CONFLATION: pfin.fn_account_trans_annotation_matched_sub_cat() (the #10 matched-tenant fence) STILL EXISTS — the transaction-level fence is intact'
);

-- (11) account_trans_split.sub_cat_id (#13) still EXISTS.
select has_column(
  'pfin', 'account_trans_split', 'sub_cat_id',
  '(11) DE-CONFLATION: pfin.account_trans_split.sub_cat_id (split-line cashflow class, Decision-3 #13) STILL EXISTS — 048 did NOT touch the split surface'
);

-- (12) the #13 matched-tenant fence fn still EXISTS.
select has_function(
  'pfin', 'fn_account_trans_split_matched_sub_cat', '{}'::text[],
  '(12) DE-CONFLATION: pfin.fn_account_trans_split_matched_sub_cat() (the #13 matched-tenant fence) STILL EXISTS — the split fence is intact'
);

select * from finish();
rollback;
