-- =====================================================================
-- Per-Wave battery — pfin.account.tax_jurisdiction designation + the YTD-Paid
--   read primitive + the shared tax-authority predicate + the §2.1.5 leaf-set
--   exclusion (SELF-267; migration 102). Paired with the migration in the SAME
--   PR (verify-paired-artifacts discipline).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/102_tax_jurisdiction_ytd_paid.sql.
--   Objects: enum pfin.tax_jurisdiction_enum ('irs','ftb'); column
--   pfin.account.tax_jurisdiction (nullable, no default); partial unique index
--   account_tax_jurisdiction_uniq on (users_id, tax_jurisdiction) where
--   tax_jurisdiction is not null; pfin.fn_tax_authority_ledgers() — the ONE
--   shared predicate home; pfin.fn_ytd_paid_per_jurisdiction(p_as_of date,
--   p_jurisdiction pfin.tax_jurisdiction_enum) returns numeric (NULL when no
--   ledger designated, 0 for a designated empty ledger, NOT clamped, native
--   currency, no transaction_type filter); pfin.fn_nav_composition(date)
--   replaced (leaf set anti-joins the shared predicate; fn_compute_nav
--   untouched — R3's deliberate divergence). All three new/replaced functions
--   SECURITY INVOKER, STABLE, set search_path = ''.
--
--   Every AC below maps to docs/records/v14-preflight/rederived-acs.md
--   § SELF-267 and sitting-log R3 riders 0/0b/0c/1, read live at authoring.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per required leg ─────────────────────┐
-- │ L1  PARTIAL UNIQUE INDEX: per-user, not global; a clear-then-remark        │
-- │       sequence succeeds once the slot is free.                            │
-- │ L2  CROSS-TENANT: A's UPDATE against B's account id is a silent zero-row  │
-- │       no-op under RLS (not a WITH CHECK 42501 — there is no visible row   │
-- │       to violate a check against); fn_tax_authority_ledgers() is leak-    │
-- │       free even when both tenants hold the SAME jurisdiction value.       │
-- │ L3  R3 RIDER 0b — THE DEFAULT-STATE WALK, BOTH HALVES, ONE ACCOUNT, ONE   │
-- │       TRANSACTION: undesignated -> designated -> reverted, each state      │
-- │       observed on BOTH consumers (YTD-Paid and the §2.1.5 composition).    │
-- │ L4  NULL vs 0 (E11): no ledger designated -> NULL (shared with L3's        │
-- │       opening state); a designated ledger holding nothing -> 0.            │
-- │ L5  NOT CLAMPED: a net-negative YTD figure (refunds > payments) reports    │
-- │       the negative, not zero.                                              │
-- │ L6  BALANCE-AS-OF: a transaction dated after p_as_of is excluded; the SAME │
-- │       row is included once p_as_of moves past it (two-date discipline,    │
-- │       056's own E1a/E1b shape — see the header note on why NOT a dual-    │
-- │       column/created_at form).                                             │
-- │ L7  ENUM TYPING: an unrecognised jurisdiction is a TYPE ERROR at the cast  │
-- │       boundary (22P02), never a silent zero-row read.                     │
-- │ L8  ACL + POSTURE: prosecdef/provolatile/proconfig plus the anon/          │
-- │       authenticated EXECUTE pair, on all THREE new/replaced functions.    │
-- │ L9  CATALOG PINS: enum label set; column nullability/no-default; index    │
-- │       partial predicate; fn_create_manual_account's signature UNCHANGED.  │
-- │ L10 fn_compute_nav BYTE-UNCHANGED: md5(pg_get_functiondef) pinned against  │
-- │       the value measured on a clean pre-102 template clone (pfin_tmpl at  │
-- │       head=099, == origin/main 762f793's chain; 100/101 held by sibling   │
-- │       V1.4 branches, so 099 is the correct "before 102" anchor).          │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ RE-AIMED (SELF-268/105, Sec P-2): L3c and L3i asserted the RAW identity
--   nav == fn_compute_nav(as_of,true), which the §2.5.4 tax flip breaks in
--   general. It would stay green here ONLY BY FIXTURE ACCIDENT (no bracket
--   schedule seeded for A, so both tax scalars coalesce to 0 regardless of
--   L3's designation state) -- Sec's "leg that cannot fail" class. Both legs
--   are re-aimed to the FULL post-102/105 invariant, with the designated-
--   ledger term and both tax scalars computed independently rather than
--   assumed 0. Non-degenerate legs live in 105_nav_composition_tax_flip.sql.
--
-- ⚠ L6 DOES NOT USE A DUAL-COLUMN (transaction_date + created_at) AS-OF FORM.
--   fn_account_cash_as_of (056), which fn_ytd_paid_per_jurisdiction composes
--   on UNCHANGED, filters on transaction_date <= p_as_of ONLY — verified
--   directly against the live catalog body on this branch's scratch DB; it
--   carries no created_at predicate at all. The Lock 15 half-open
--   `transaction_date <= p_as_of AND created_at < (p_as_of + 1)` form belongs
--   to `093` fn_cashflow_items, a DIFFERENT reader over the SAME table with a
--   DIFFERENT as-of contract (it must distinguish a same-day reversal's
--   ordering; 056/102 do not). L6 below tests 056's ACTUAL single-column
--   contract, not the dual-column one.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY; no PII, no real account numbers
--   (SD-15), no prod data; rolled-back txn; no `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 35: L1 6 · L2 3 · L3 10 · L4 1 · L5 1 · L6 2 · L7 1 · L8 6 · L9 4 · L10 1.
select plan(35);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- L1 — PARTIAL UNIQUE INDEX: per-user, not global; clear-then-remark succeeds.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-idx-1', 'depository', 'household', 'taxable') returning account_id as a_idx1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-idx-2', 'depository', 'household', 'taxable') returning account_id as a_idx2 \gset

with upd as (
  update pfin.account set tax_jurisdiction = 'irs'
   where account_id = :a_idx1 returning tax_jurisdiction
)
select is(
  (select tax_jurisdiction::text from upd),
  'irs',
  '(L1a) A marks a_idx1 ''irs'' -> succeeds, value lands (not merely no-error)'
);

select throws_ok(
  format('update pfin.account set tax_jurisdiction = ''irs'' where account_id = %s', :a_idx2),
  '23505', null,
  '(L1b) A marks a_idx2 ''irs'' while a_idx1 already holds ''irs'' -> unique_violation (23505) on account_tax_jurisdiction_uniq'
);

with upd as (
  update pfin.account set tax_jurisdiction = 'ftb'
   where account_id = :a_idx2 returning tax_jurisdiction
)
select is(
  (select tax_jurisdiction::text from upd),
  'ftb',
  '(L1c) A marks a_idx2 ''ftb'' (different value from a_idx1''s ''irs'') -> succeeds'
);

-- (L1d) tenant B, CONCURRENTLY with A still holding 'irs' on a_idx1 -> proves the
-- index is PER-USER (users_id, tax_jurisdiction), not a global tax_jurisdiction uniq.
-- Role restored to postgres FIRST: schema _rls grants no USAGE to authenticated, so
-- calling _rls.set_tenant again while already authenticated (as A) is a permission
-- denial, not a tenant switch (PR #121 root-cause, restated in 087's own header).
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-idx', 'depository', 'household', 'taxable') returning account_id as b_idx \gset
with upd as (
  update pfin.account set tax_jurisdiction = 'irs'
   where account_id = :b_idx returning tax_jurisdiction
)
select is(
  (select tax_jurisdiction::text from upd),
  'irs',
  '(L1d) B marks b_idx ''irs'' while A''s a_idx1 ALSO holds ''irs'' -> succeeds: the index is scoped per (users_id, tax_jurisdiction), not global'
);

select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
with upd as (
  update pfin.account set tax_jurisdiction = null
   where account_id = :a_idx1 returning tax_jurisdiction
)
select is(
  (select tax_jurisdiction from upd),
  null::pfin.tax_jurisdiction_enum,
  '(L1e) A clears a_idx1 back to NULL -> succeeds, frees the ''irs'' slot for A'
);

with upd as (
  update pfin.account set tax_jurisdiction = 'irs'
   where account_id = :a_idx2 returning tax_jurisdiction
)
select is(
  (select tax_jurisdiction::text from upd),
  'irs',
  '(L1f) A re-marks a_idx2 ''irs'' now that a_idx1 is cleared -> succeeds (clear-then-remark, R3 rider 0c''s required sequence). Final state for the rest of this file: a_idx1=NULL, a_idx2=''irs'', b_idx=''irs'''
);

-- =====================================================================
-- L4b — NULL vs 0, second half: a_idx2 IS designated 'irs' but carries NO
--   checkpoint and NO transactions -> YTD Paid reads 0, not NULL (a real,
--   empty ledger vs. no ledger at all). Run here because a_idx2's zero-cash
--   state is a fixture accident of L1, not something re-seeded on purpose.
-- =====================================================================
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'irs'::pfin.tax_jurisdiction_enum)),
  0.0000::numeric,
  '(L4b) NULL-vs-0, designated-empty half: a_idx2 is designated ''irs'' with no checkpoint and no transactions -> YTD Paid reads 0.0000, NOT NULL. Paired with L3a''s undesignated-NULL half below (E11''s one-character-reversal design choice)'
);

-- =====================================================================
-- L2 — CROSS-TENANT: A's write against B's account id is a silent zero-row
--   no-op under RLS; fn_tax_authority_ledgers() leak-free.
-- =====================================================================
with upd as (
  update pfin.account set tax_jurisdiction = 'irs'
   where account_id = :b_idx returning account_id
)
select is(
  (select count(*)::int from upd),
  0,
  '(L2a) A targeting B''s account (b_idx) by id updates ZERO rows under RLS -- account_update''s USING clause hides the row entirely, so this is a silently empty UPDATE, not a WITH CHECK 42501 (there is no visible row to check a WITH CHECK predicate against)'
);
select set_config('role', 'postgres', true);
select is(
  (select tax_jurisdiction::text from pfin.account where account_id = :b_idx),
  'irs',
  '(L2a-verify) b_idx''s tax_jurisdiction is UNCHANGED by A''s no-op attempt -- confirms the empty UPDATE truly touched nothing, not merely that it reported 0 rows'
);

select _rls.set_tenant(:'ta'::uuid);
select results_eq(
  $$ select account_id from pfin.fn_tax_authority_ledgers() order by account_id $$,
  format('values (%s::bigint)', :a_idx2),
  '(L2b) fn_tax_authority_ledgers() as tenant A returns ONLY a_idx2 (A''s own ''irs'' designation) even though tenant B has independently designated b_idx ''irs'' -- cross-tenant leak-free under INVOKER + inherited pfin.account RLS, and non-vacuous because BOTH tenants hold the SAME jurisdiction value at once'
);

-- =====================================================================
-- L3 — R3 RIDER 0b: THE DEFAULT-STATE WALK. One account, three states,
--   both consumers observed at each state.
-- =====================================================================
-- Fixture seeding as postgres: account_balance_checkpoint / account_trans carry
-- no authenticated INSERT grant (writes go through controlled RPCs in the app,
-- e.g. fn_create_manual_account/fn_create_manual_trans; a battery seeds them
-- directly, as postgres, matching 056's own fixture convention).
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-walk', 'depository', 'household', 'taxable') returning account_id as a_walk \gset

-- Cash: checkpoint 1000 @ 01-31, +500 @ 02-15 (both <= as-of 02-28). X = 1500.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_walk, 1000.0000, 'USD', '2026-01-31', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
  values (:a_walk, '2026-02-15', 500.0000, 'walk-seed');

select _rls.set_tenant(:'ta'::uuid);
-- STATE 1 -- UNDESIGNATED (a_walk.tax_jurisdiction is NULL). Jurisdiction 'ftb'
-- deliberately -- A's 'irs' slot is already occupied by a_idx2 (L1), and using
-- the SAME jurisdiction here would make this leg indistinguishable from L4b.
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  null::numeric,
  '(L3a / L4a) STATE 1 (undesignated): no ''ftb'' ledger designated for A -> YTD Paid is NULL, not 0 -- the NULL-vs-0 undesignated half (E11), and simultaneously L3''s opening observation of the default state'
);
select ok(
  (select bool_or(acc->>'account_id' = :a_walk::text)
     from jsonb_array_elements(pfin.fn_nav_composition('2026-02-28'::date)->'groups') g,
          jsonb_array_elements(g->'accounts') acc),
  '(L3b) STATE 1: a_walk (undesignated) is PRESENT in fn_nav_composition''s leaf set -- not yet excluded'
);
-- RE-AIMED (SELF-268/105, Sec P-2): the RAW equality below would stay GREEN
--   against 105 ONLY BY FIXTURE ACCIDENT -- this file seeds no bracket
--   schedule for tenant A, so both tax scalars read {unavailable,
--   no_schedule_any_year} and coalesce to 0 regardless of what STATE a_walk
--   is in (Sec's "leg that cannot fail" class -- it would pass identically
--   whether or not 105 had landed). Re-aimed to the FULL post-102/105
--   invariant, with the designated-ledger term and both tax scalars computed
--   INDEPENDENTLY rather than assumed 0, so the formula itself is exercised.
select is(
  (select (pfin.fn_nav_composition('2026-02-28'::date)->>'nav')::numeric),
  (select pfin.fn_compute_nav('2026-02-28'::date, true))
    - coalesce((select sum(g.current_market_value)
                  from pfin.fn_tax_authority_ledgers() tal
                  join pfin.fn_account_unrealized_gl('2026-02-28'::date) g on g.account_id = tal.account_id), 0)
    - coalesce((pfin.fn_nav_composition('2026-02-28'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric, 0)
    - coalesce((pfin.fn_nav_composition('2026-02-28'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0),
  '(L3c) STATE 1: fn_nav_composition''s nav EQUALS fn_compute_nav(as_of,true) minus designated-ledger CMVs (a_idx2 is designated but carries a ZERO balance here -- L4b -- so this leg does NOT depend on that term being structurally zero, it is COMPUTED) minus the two coalesced tax scalars -- no divergence while a_walk is undesignated and no bracket schedule exists for A. Non-degenerate legs (real non-zero tax scalars, a real designated-ledger exclusion) live in 105_nav_composition_tax_flip.sql'
);
select pfin.fn_compute_nav('2026-02-28'::date, true) as nav_state1 \gset

-- STATE 2 -- DESIGNATED. Both consumers move together (rider 0b's whole point).
-- Still tenant A, uninterrupted -- same reasoning as above.
update pfin.account set tax_jurisdiction = 'ftb' where account_id = :a_walk;
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  1500.0000::numeric,
  '(L3d) STATE 2 (designated): YTD Paid = X = 1500.0000 (checkpoint 1000 + 500 after-anchor)'
);
select ok(
  not (select bool_or(acc->>'account_id' = :a_walk::text)
         from jsonb_array_elements(pfin.fn_nav_composition('2026-02-28'::date)->'groups') g,
              jsonb_array_elements(g->'accounts') acc),
  '(L3e) STATE 2: a_walk is now ABSENT from fn_nav_composition''s leaf set -- the §2.1.5 EXCLUSION (AC 2a)'
);
select is(
  (select pfin.fn_compute_nav('2026-02-28'::date, true) - (pfin.fn_nav_composition('2026-02-28'::date)->>'nav')::numeric),
  1500.0000::numeric,
  '(L3f) STATE 2: fn_compute_nav MINUS fn_nav_composition''s nav = exactly 1500.0000 (a_walk''s balance) -- the R3 divergence, MEASURED, not argued from the comment'
);
select is(
  (select pfin.fn_compute_nav('2026-02-28'::date, true)),
  :nav_state1::numeric,
  '(L3g) STATE 2: fn_compute_nav(as_of,true) is UNCHANGED from STATE 1 -- it keeps INCLUDING a_walk regardless of designation (fn_compute_nav itself is untouched by 102; only fn_nav_composition''s leaf set moved)'
);

-- STATE 3 -- REVERSION. Both figures return to their STATE 1 values.
update pfin.account set tax_jurisdiction = null where account_id = :a_walk;
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  null::numeric,
  '(L3h) STATE 3 (reverted to NULL): YTD Paid is NULL again -- the designation, not some cached state, drives the figure'
);
-- RE-AIMED (SELF-268/105, Sec P-2, same reasoning as L3c above).
select is(
  (select (pfin.fn_nav_composition('2026-02-28'::date)->>'nav')::numeric),
  (select pfin.fn_compute_nav('2026-02-28'::date, true))
    - coalesce((select sum(g.current_market_value)
                  from pfin.fn_tax_authority_ledgers() tal
                  join pfin.fn_account_unrealized_gl('2026-02-28'::date) g on g.account_id = tal.account_id), 0)
    - coalesce((pfin.fn_nav_composition('2026-02-28'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric, 0)
    - coalesce((pfin.fn_nav_composition('2026-02-28'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0),
  '(L3i) STATE 3: fn_nav_composition''s nav EQUALS fn_compute_nav again (RE-AIMED formula, same correction terms as L3c) -- the identity is RESTORED, not merely re-approximated'
);
select ok(
  (select bool_or(acc->>'account_id' = :a_walk::text)
     from jsonb_array_elements(pfin.fn_nav_composition('2026-02-28'::date)->'groups') g,
          jsonb_array_elements(g->'accounts') acc),
  '(L3j) STATE 3: a_walk is PRESENT again in the leaf set -- the exclusion is a live read of the designation, not a one-way latch'
);

-- =====================================================================
-- L5 — NOT CLAMPED: refunds exceeding payments report negative, not 0.
--   'ftb' is free again for A now that L3 reverted a_walk to NULL.
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-neg', 'depository', 'household', 'taxable') returning account_id as a_neg \gset
update pfin.account set tax_jurisdiction = 'ftb' where account_id = :a_neg;
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_neg, 500.0000, 'USD', '2026-01-31', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
  values (:a_neg, '2026-02-15', -800.0000, 'refund-heavy');
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  -300.0000::numeric,
  '(L5a) NOT CLAMPED: 500 checkpoint - 800 refund = -300.0000, reported as negative rather than floored at 0 -- deliberately asymmetric with the R9 zero-clamp on Unrealized Tax Liability (a different figure)'
);

-- =====================================================================
-- L6 — BALANCE-AS-OF: a future-dated row is excluded; the SAME row is
--   included once p_as_of moves past it (two-date discipline, 056's own
--   contract -- single-column transaction_date, see the file header).
-- =====================================================================
select set_config('role', 'postgres', true);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
  values (:a_neg, '2026-03-15', 10000.0000, 'after-as-of');
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  -300.0000::numeric,
  '(L6a) a transaction dated 2026-03-15 does NOT move the 2026-02-28 as-of figure -- still -300.0000, unchanged from L5a'
);
select is(
  (select pfin.fn_ytd_paid_per_jurisdiction('2026-03-15'::date, 'ftb'::pfin.tax_jurisdiction_enum)),
  9700.0000::numeric,
  '(L6b) the SAME row IS included once p_as_of moves to/past its date: -300 + 10000 = 9700.0000 -- proves L6a was a real as-of exclusion, not a row that never landed'
);

-- =====================================================================
-- L7 — ENUM TYPING: an unrecognised jurisdiction is a TYPE ERROR at the cast
--   boundary, never a silent zero-row read (Sec D-2(ii), the RT-25 shape).
-- =====================================================================
select throws_ok(
  $$ select pfin.fn_ytd_paid_per_jurisdiction('2026-02-28'::date, 'nonsense'::pfin.tax_jurisdiction_enum) $$,
  '22P02', null,
  '(L7a) an unrecognised jurisdiction value fails the enum CAST itself (22P02 invalid_text_representation) before the function is ever called -- with a text parameter this would instead be a silent zero-row read overstating Funds Due'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- L8 — ACL + POSTURE on all three new/replaced functions.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_tax_authority_ledgers'),
  array['false', 's', 'search_path=""'],
  '(L8a) fn_tax_authority_ledgers() POSTURE: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_tax_authority_ledgers()', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_tax_authority_ledgers()', 'execute'),
  '(L8b) fn_tax_authority_ledgers() EXECUTE revoked from PUBLIC (anon denied), granted to authenticated only'
);

select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_ytd_paid_per_jurisdiction'),
  array['false', 's', 'search_path=""'],
  '(L8c) fn_ytd_paid_per_jurisdiction(date,enum) POSTURE: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum)', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_ytd_paid_per_jurisdiction(date, pfin.tax_jurisdiction_enum)', 'execute'),
  '(L8d) fn_ytd_paid_per_jurisdiction(date,enum) EXECUTE revoked from PUBLIC (anon denied), granted to authenticated only'
);

select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  array['false', 's', 'search_path=""'],
  '(L8e) fn_nav_composition(date) POSTURE, RE-CONFIRMED POST-102: SECURITY INVOKER (prosecdef false), STABLE (provolatile s -- 079''s explicit re-declaration survives the CREATE OR REPLACE, R3 rider 7), search_path pinned empty'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_nav_composition(date)', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_nav_composition(date)', 'execute'),
  '(L8f) fn_nav_composition(date) EXECUTE revoked from PUBLIC (anon denied), granted to authenticated only -- unchanged by 102'
);

-- =====================================================================
-- L9 — CATALOG PINS.
-- =====================================================================
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder)
     from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'tax_jurisdiction_enum'),
  array['irs', 'ftb'],
  '(L9a) pfin.tax_jurisdiction_enum carries EXACTLY the two V1 labels, in order: irs, ftb'
);
select is(
  (select array[is_nullable::text, coalesce(column_default, '<none>')::text]
     from information_schema.columns
    where table_schema = 'pfin' and table_name = 'account' and column_name = 'tax_jurisdiction'),
  array['YES', '<none>']::text[],
  '(L9b) pfin.account.tax_jurisdiction is NULLABLE with NO DEFAULT -- an account is undesignated until an explicit UPDATE, never implicitly on creation'
);
select ok(
  (select indexdef from pg_indexes
    where schemaname = 'pfin' and indexname = 'account_tax_jurisdiction_uniq')
    ~ 'UNIQUE INDEX account_tax_jurisdiction_uniq ON pfin\.account USING btree \(users_id, tax_jurisdiction\) WHERE \(tax_jurisdiction IS NOT NULL\)',
  '(L9c) account_tax_jurisdiction_uniq is a PARTIAL unique index on (users_id, tax_jurisdiction) WHERE tax_jurisdiction IS NOT NULL -- the exact predicate L1 depends on'
);
select ok(
  (select true from pg_proc
    where oid = 'pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb)'::regprocedure),
  '(L9d) pfin.fn_create_manual_account''s 7-arg signature (087) is UNCHANGED by 102 -- the cast to this exact regprocedure still resolves; a signature change would make the cast itself raise "function does not exist" rather than fail this assertion cleanly (013''s own lesson on this function)'
);

-- =====================================================================
-- L10 — fn_compute_nav BYTE-UNCHANGED.
-- =====================================================================
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '9917963f130498c3614eb6d550f53f51',
  '(L10) fn_compute_nav(date,boolean) is BYTE-UNCHANGED by 102 -- md5 pinned against the value measured on a clean pre-102 clone (pfin_tmpl head=099, == origin/main 762f793''s migration chain; 100/101 are held by sibling V1.4 branches per 102''s own header). fn_compute_nav keeps its GROSS pre-tax definition PERMANENTLY (R3); only fn_nav_composition''s leaf set changes'
);

select * from finish();
rollback;
