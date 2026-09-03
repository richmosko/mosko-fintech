-- =====================================================================
-- Per-Wave battery — pfin.fn_cashflow_contributors(p_as_of date) — the §2.3
--   per-Sub-Cat CONTRIBUTOR MAP (SELF-258 AC4/AC5). Composes on 093's shared
--   reader (pfin.fn_cashflow_items). Returns DISTINCT (cat, sub_cat,
--   sub_cat_id, account_id, account_name). CARRIES NO MONEY, NO FRESHNESS
--   VERDICT (086 SHAPE 3 ruling, unchanged — see the migration's own header).
--   Read-only. NO new base table, NO write path, NO new DEFINER, NO new
--   FK-shaped column. Paired with the migration in the SAME PR.
-- =====================================================================
-- BINDS TO: supabase/migrations/099_fn_cashflow_contributors.sql (committed,
--   feature/self-258 9b74517) — pfin.fn_cashflow_contributors(p_as_of date)
--   RETURNS TABLE (cat text, sub_cat text, sub_cat_id bigint, account_id
--   bigint, account_name text) SECURITY INVOKER · STABLE · set search_path=''.
--   NO tenant parameter, NO default on p_as_of. LEFT JOIN to pfin.account
--   (load-bearing, not defensive — see the migration's own LEFT JOIN block).
--
-- Prereqs exercised (on the 001->099 stack): 003 (account + account_users,
--   incl. the rd_access-only dormant grant shape), 006 (account_trans_select
--   rd_access-JOIN), 024/025 (user_settings.mfa_policy + the aal2 backstop
--   clause fn_cashflow_items inherits through account_trans), 084 (posting_
--   prototype + the #10/#13 matched-tenant fences), 093 (the shared reader +
--   the sibling rollup this file parity-checks against), 094 (the sibling
--   per-account drill-down this file also parity-checks against, AS
--   CURRENTLY COMMITTED — verified against pg_get_functiondef, not assumed
--   from the file text).
--
-- §10 / DECISION 3: read ADR-011 Decision 4 + Decision 3 LIVE at merge time,
--   not restated/counted here (Path B). This battery assumes, per the
--   migration's own §10 3-AXIS CROSS-CHECK and DECISION 3 EVALUATION
--   paragraphs: ZERO catalogued §10 instances added (read-only, no write
--   path, no credential surface), Decision-3 family UNCHANGED (no column of
--   any kind created/altered/dropped), SECURITY DEFINER allowlist UNCHANGED
--   (INVOKER posture). ⚠ RE-VERIFY both paragraphs against the committed
--   file and ADR-011 read live before sign-off — this note records what was
--   read, not a standing count.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (_rls.tenant_a
--   / _rls.tenant_b() for A/B; raw literals suffixed '99' for D/E/F,
--   provisional). NO PII / NO real account numbers / NO production data. All
--   seeds PRIVILEGED (role=postgres; RLS+ACL bypassed) with users_id set
--   EXPLICITLY. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated. Every _rls.set_tenant/set_tenant_aal call is preceded by
--   an explicit role=postgres restore (the leaked-role gotcha — a second
--   call while already 'authenticated' fails closed on "permission denied
--   for schema _rls" instead of switching tenants).
--
-- ⚠ FIXTURE-CLOCK TRAP (Architect's own arc note): the DB container's wall
--   clock can cross UTC midnight vs the repo-local calendar date. p_as_of
--   (D = 2026-11-15) and every seeded transaction_date are ARGUMENTS, not the
--   wall clock, and reader rule 6's created_at < (D+1) bound is satisfied by
--   the DEFAULT now() at insert time regardless — this file does not force
--   the clock and carries no created_at literal, so the trap does not apply
--   to it, recorded here so a future reader does not need to re-derive that.
--
-- Sec joint-review: MANDATORY per the migration's own JOINT-REVIEW-MANDATORY
--   block (inherited multi-tenant fence + account-identity disclosure +
--   fail-OPEN staleness-pipeline consumer). This file is QA's half of that
--   review's evidence; it does not substitute for it.
--
-- plan(37) BREAKDOWN — 1 Sec FLAG-2 (F2, col_not_null) + 2 crux X1
--   (staleness-predicate single-source pin, text + pg_depend) + 5 crux X2
--   (parity P1/P2 both directions via EXCEPT + P3 iff) + 1 crux X3
--   (non-vacuity companion) + 5 crux X4 (posture triple + 3 ACL legs + anon
--   42501) + 5 two-tenant isolation (I1-I5) + 2 aal2 gate (both legs) + 2
--   NULL/predates-data arg semantics + 7 grain (split x2, net-zero, out-year,
--   two-sub-cats, two-accounts, manual-account) + 2 superset corroboration
--   (SUP-RAW/ROLLUP — SUP-PERACCT dropped, see the SUP fixture comment: no
--   fixture can reach a Trade-classified un-journaled item, the only cat
--   truly excluded from BOTH consumers) + 3 dormant-branch (name-NULL,
--   third-taxonomy-state, non-degenerate count) + 2 corrupt-the-control (CC0
--   defense-in-depth, CC1 load-bearing leak) = 37.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(37);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-0000000000d9'
\set te '00000000-0000-0000-0000-0000000000e9'
\set tf '00000000-0000-0000-0000-0000000000f9'

\set d_asof '2026-11-15'

insert into auth.users (id) values (:'ta'), (:'tb'), (:'td'), (:'te'), (:'tf');
insert into pfin.user_settings (users_id, mfa_policy) values (:'td', 'totp');

-- =====================================================================
-- FIXTURE — TENANT A. a_acc1 carries: two classified Sub-Cats (Groceries99,
--   Dining99 — GR-TWOSUBCAT), a net-zero fully-reversed item (NetZero99), an
--   out-of-year item (OutYear99), a split parent/2-children pair (Split1_99/
--   Split2_99), an unclassified item (P3/classified+unclassified requirement),
--   and a Trade-classified item with NO security_id (SUP — passes the
--   reader's S-1 predicate but excluded from every §2.3 section by cat, not
--   by the reader). a_acc2 duplicates the Groceries99 classification under a
--   DIFFERENT account (GR-TWOACCT). Neither account is ever given a
--   linked_source_id (GR-MANUAL: contributes exactly like a connected one,
--   because this function reads linked_source_id nowhere at all).
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'Groceries99', false) returning id as a_groceries \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'Dining99', false) returning id as a_dining \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'NetZero99', false) returning id as a_netzero \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'OutYear99', false) returning id as a_outyear \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'Split1_99', false) returning id as a_split1 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'Split2_99', false) returning id as a_split2 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Equity', 'EquityLabel99', false) returning id as a_equity \gset

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-acc1-99', 'depository', 'household', 'taxable') returning account_id as a_acc1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-acc2-99', 'depository', 'household', 'taxable') returning account_id as a_acc2 \gset

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-03-01', -50, 'vGroceries1', '099 GR-TWOSUBCAT/GR-TWOACCT a_acc1 groceries leg')
  returning trans_id as t_a1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_a1, :a_groceries);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc2, '2026-03-05', -30, 'vGroceries2', '099 GR-TWOACCT a_acc2 groceries leg (SAME Sub-Cat, DIFFERENT account)')
  returning trans_id as t_a2 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_a2, :a_groceries);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-04-01', -20, 'vDining1', '099 GR-TWOSUBCAT a_acc1 dining leg (SAME account, DIFFERENT Sub-Cat)')
  returning trans_id as t_a3 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_a3, :a_dining);

-- P3 / classified-and-unclassified requirement: NO annotation row at all.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-04-10', -15, 'vUnclassified1', '099 P3 unclassified item, no annotation')
  returning trans_id as t_a4 \gset

-- GR-NETZERO: a fully-reversed item nets to 0 but must STILL contribute
-- (group existence, not value — the migration's own CONTRACT closing note).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-05-10', -40, 'vNetZeroOrig', '099 GR-NETZERO original')
  returning trans_id as o1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:o1, :a_netzero);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id) values
  (:a_acc1, '2026-05-11', 40, 'vNetZeroRev', '099 GR-NETZERO reversal', true, :o1)
  returning trans_id as r1 \gset

-- GR-OUTYEAR: dated OUTSIDE D's rendered year (2025 vs D's 2026) — the reader
-- still emits it (093 rule 5), but in_ytd is false, so it must contribute
-- NOTHING here — the leg that reds if a future edit drops the in_ytd conjunct.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2025-06-01', -999, 'vOutYear', '099 GR-OUTYEAR item outside D''s rendered year')
  returning trans_id as t_outyear \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_outyear, :a_outyear);

-- GR-SPLIT: parent excluded, 2 children emitted under THEIR OWN Sub-Cats but
-- the PARENT's account_id (093 rule 2 emission) — one account, two Sub-Cats.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-06-15', -90, 'vSplitParent', '099 GR-SPLIT parent (never itself a contributor)')
  returning trans_id as t_split_parent \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values
  (:t_split_parent, :a_split1, -60);
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount) values
  (:t_split_parent, :a_split2, -30);

-- SUP: an Equity-classified, non-journaled, non-security item — the 093
-- RU-EQ precedent verbatim (passes the reader's S-1 predicate) — IS present
-- in this function's raw output (deliberate SUPERSET over the rollup's
-- Revenue/Expense-only vocabulary), while absent from the ROLLUP's sections.
-- ⚠ NOT usable to demonstrate the superset against fn_cashflow_per_account
-- too: Equity IS one of per_account's own section_cats (other_cash_flows),
-- and 'Trade' — the one cat truly excluded from BOTH consumers — cannot
-- reach this reader's output un-journaled without a security_id (the
-- Trade-consistency trigger requires security_id present <=> cat='Trade',
-- and a security_id present is EXCLUDED by the reader's own R2), so no
-- fixture can reach that state. Recorded rather than silently narrowed.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:a_acc1, '2026-07-01', 500, 'vEquityCat', '099 SUP Equity-classified non-journaled non-security item')
  returning trans_id as t_equity_cat \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_equity_cat, :a_equity);

-- =====================================================================
-- FIXTURE — TENANT B. Isolation control: one account, one classified item,
--   non-vacuous.
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'tb', 'Expense', 'BStuff99', false) returning id as b_exp \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb', 'b-acc-99', 'depository', 'household', 'taxable') returning account_id as b_acc \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:b_acc, '2026-03-01', -25, 'vB', '099 tenant-B own classified item')
  returning trans_id as t_b1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_b1, :b_exp);

-- =====================================================================
-- FIXTURE — TENANT D. aal2 backstop: mfa_policy='totp' (set above), one
--   classified item.
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'td', 'Expense', 'DStuff99', false) returning id as d_exp \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'td', 'd-acc-99', 'depository', 'household', 'taxable') returning account_id as d_acc \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:d_acc, '2026-03-01', -10, 'vD', '099 tenant-D aal2-gated item')
  returning trans_id as t_d1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_d1, :d_exp);

-- =====================================================================
-- FIXTURE — DORMANT-BRANCH PAIR (E owns, F is a NON-OWNER granted rd_access
--   DIRECTLY — the V1-dormant shape; revives with the first V2 sharing write
--   path). E annotates its OWN item with its OWN posting_prototype row (the
--   084 matched-tenant fence is satisfied — owner annotates with owner's
--   vocabulary). F never owns e_acc and is never given a posting_prototype
--   row resolving to e_exp's id.
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'te', 'Expense', 'EOwned99', false) returning id as e_exp \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'te', 'e-acc-99', 'depository', 'household', 'taxable') returning account_id as e_acc \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description) values
  (:e_acc, '2026-03-01', -70, 'vE', '099 dormant-branch: E''s own item, E''s own classification')
  returning trans_id as t_e1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_e1, :e_exp);

-- F: PRIVILEGED direct grant, rd-only, NOT the owner (006's Tenant-C shape).
insert into pfin.account_users (account_id, users_id, rd_access, wr_access) values
  (:e_acc, :'tf', true, false);

-- =====================================================================
-- SEC FLAG 2 — the CONTRACT's "account_name IS NULL means exactly one
--   thing" rests on this unwatched invariant (085/091/058 col_not_null idiom).
-- =====================================================================
select col_not_null(
  'pfin', 'account', 'name',
  '(F2) SEC FLAG 2: pfin.account.name is NOT NULL — the load-bearing premise behind ''account_name IS NULL means unresolvable, never a real NULL name'''
);

-- =====================================================================
-- CRUX X1 — STALENESS-PREDICATE SINGLE-SOURCE PIN.
-- =====================================================================
select ok(
  pg_get_functiondef('pfin.fn_cashflow_contributors(date)'::regprocedure) !~* 'connection_status'
  and pg_get_functiondef('pfin.fn_cashflow_contributors(date)'::regprocedure) !~* 'linked_source'
  and pg_get_functiondef('pfin.fn_cashflow_contributors(date)'::regprocedure) !~* 'has_stale',
  '(X1a) the function body contains NEITHER ''connection_status'' NOR ''linked_source'' NOR ''has_stale'' — no future author has "helpfully" inlined the staleness rule'
);
select ok(
  not exists (
    select 1 from pg_depend d
    where d.classid = 'pg_proc'::regclass
      and d.objid = 'pfin.fn_cashflow_contributors(date)'::regprocedure
      and (
        (d.refclassid = 'pg_proc'::regclass and d.refobjid = 'pfin.fn_aggregation_has_stale_constituent()'::regprocedure)
        or (d.refclassid = 'pg_class'::regclass and d.refobjid = 'pfin.linked_source_connection_state'::regclass)
      )
  ),
  '(X1b) pg_depend shows NO reference from fn_cashflow_contributors to fn_aggregation_has_stale_constituent (046) or linked_source_connection_state (043) — the catalog-level proof, not merely a text-absence proof'
);

-- =====================================================================
-- CRUX X2 — PARITY, BOTH DIRECTIONS, VIA EXCEPT (never NOT IN — sub_cat is
--   text and the unclassified key is NULL; EXCEPT is NULL-safe for row
--   comparison, NOT IN is NULL-blind — the 086 N1/N2 instrument proof applies
--   unchanged here and is not re-derived).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (P1) forward: contributor (cat,sub_cat) set (restricted to the consumer's
-- own cat vocabulary) has nothing the rollup's rendered Sub-Cat rows lack.
select is(
  (select count(*) from (
    select cat, sub_cat from pfin.fn_cashflow_contributors(:'d_asof'::date)
     where sub_cat_id is not null and cat in ('Revenue','Expense')
    except
    select (s ->> 'cat'), (row ->> 'sub_cat')
      from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
           jsonb_array_elements(s -> 'rows') row
  ) d),
  0::bigint,
  '(X2-P1F) ⭐ PARITY forward (rollup, P1): contributor (cat,sub_cat) set EXCEPT rollup Sub-Cat row set = EMPTY'
);
-- (P1) reverse.
select is(
  (select count(*) from (
    select (s ->> 'cat'), (row ->> 'sub_cat')
      from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
           jsonb_array_elements(s -> 'rows') row
    except
    select cat, sub_cat from pfin.fn_cashflow_contributors(:'d_asof'::date)
     where sub_cat_id is not null and cat in ('Revenue','Expense')
  ) d),
  0::bigint,
  '(X2-P1R) ⭐ PARITY reverse (rollup, P1): rollup Sub-Cat row set EXCEPT contributor (cat,sub_cat) set = EMPTY'
);

-- (P2) forward, per-account (a_acc1): same discipline, scoped to one account.
select is(
  (select count(*) from (
    select cat, sub_cat from pfin.fn_cashflow_contributors(:'d_asof'::date)
     where account_id = :a_acc1 and sub_cat_id is not null and cat in ('Revenue','Transfer','Equity','Expense')
    except
    select (row ->> 'cat'), (row ->> 'sub_cat')
      from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_acc1, :'d_asof'::date) -> 'sections') s,
           jsonb_array_elements(s -> 'rows') row
  ) d),
  0::bigint,
  '(X2-P2F) ⭐ PARITY forward (per-account, P2): a_acc1''s contributor (cat,sub_cat) set EXCEPT fn_cashflow_per_account''s Sub-Cat row set = EMPTY'
);
-- (P2) reverse.
select is(
  (select count(*) from (
    select (row ->> 'cat'), (row ->> 'sub_cat')
      from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_acc1, :'d_asof'::date) -> 'sections') s,
           jsonb_array_elements(s -> 'rows') row
    except
    select cat, sub_cat from pfin.fn_cashflow_contributors(:'d_asof'::date)
     where account_id = :a_acc1 and sub_cat_id is not null and cat in ('Revenue','Transfer','Equity','Expense')
  ) d),
  0::bigint,
  '(X2-P2R) ⭐ PARITY reverse (per-account, P2): fn_cashflow_per_account''s Sub-Cat row set EXCEPT a_acc1''s contributor (cat,sub_cat) set = EMPTY'
);

-- (P3) the unclassified-existence iff, both directions in one boolean identity.
select is(
  (select exists(select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :a_acc1 and sub_cat_id is null)),
  (select ((pfin.fn_cashflow_per_account(:a_acc1, :'d_asof'::date) -> 'unclassified' ->> 'count_ytd')::int > 0)),
  '(X2-P3) P3 iff: an UNCLASSIFIED contributor row exists for a_acc1 <==> fn_cashflow_per_account(a_acc1,d)->unclassified->count_ytd > 0'
);

-- =====================================================================
-- CRUX X3 — NON-VACUITY OF THE ITEM LIST. Two empty relations would pass
--   every EXCEPT leg above trivially; this is the companion that rules it out.
-- =====================================================================
select ok(
  (select count(*) from pfin.fn_cashflow_contributors(:'d_asof'::date)) > 0
  and (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s, jsonb_array_elements(s -> 'rows') row) > 0
  and (select count(*) from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_acc1, :'d_asof'::date) -> 'sections') s, jsonb_array_elements(s -> 'rows') row) > 0,
  '(X3-NV) non-vacuous companion: the contributor map, the rollup''s sections, AND a_acc1''s per-account sections all carry REAL non-empty row sets — (X2)''s EMPTY EXCEPT results are not two empty sets agreeing trivially'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- CRUX X4 — POSTURE TRIPLE (067/098 three-element catalog form) + ACL.
-- =====================================================================
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_cashflow_contributors'),
  array['false','s','search_path=""'],
  '(X4-POST) POSTURE, read DECLARATIVELY from the catalog: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty'
);
select ok(
  has_function_privilege('authenticated', 'pfin.fn_cashflow_contributors(date)', 'execute'),
  '(X4-ACL1) authenticated HOLDS EXECUTE'
);
select ok(
  not has_function_privilege('public', 'pfin.fn_cashflow_contributors(date)', 'execute'),
  '(X4-ACL2) LOAD-BEARING: PUBLIC does NOT — create function grants EXECUTE to PUBLIC by default, so the revoke is load-bearing and silent on removal'
);
select ok(
  not has_function_privilege('service_role', 'pfin.fn_cashflow_contributors(date)', 'execute'),
  '(X4-ACL3) service_role does NOT hold EXECUTE — an account-identity disclosure surface has no service_role-side consumer'
);
select set_config('role', 'anon', true);
select throws_ok(
  $$ select * from pfin.fn_cashflow_contributors('2026-11-15'::date) $$,
  '42501', null,
  '(X4-ACLANON) anon zero-grant: EXECUTE is revoked from public and not granted to anon — fails closed at the pfin schema-USAGE fence before the body runs'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- TWO-TENANT ISOLATION (I1-I5).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :a_acc1),
  '(TT-I1) A''s own account (a_acc1) IS present in A''s contributor set — non-vacuous'
);
select ok(
  not exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :b_acc),
  '(TT-I2) cross-tenant read fails closed: A''s call never returns B''s account_id (b_acc)'
);
select ok(
  not exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_name = 'b-acc-99'),
  '(TT-I3) cross-tenant read fails closed on the NAME column too: A''s call never returns B''s account_name (''b-acc-99'') — the column 086 did not have'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select ok(
  not exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :a_acc1 or account_id = :a_acc2 or account_name in ('a-acc1-99','a-acc2-99')),
  '(TT-I4) cross-tenant read fails closed (reverse): B''s call never returns EITHER of A''s account_ids or account_names'
);
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :b_acc),
  '(TT-I5) non-vacuous companion (reverse): B''s own account (b_acc) IS present in B''s contributor set'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- AAL2 GATE, BOTH LEGS (098's own pattern — both legs required, or (AAL-A)
--   could pass vacuously against a policy that blinds every caller).
-- =====================================================================
select is(
  _rls.count_as(:'td'::uuid, 'aal1',
    $$ select count(*) from pfin.fn_cashflow_contributors('2026-11-15'::date) $$
  ), 0::bigint,
  '(TT-AAL-A) an aal1 session for the totp-declared tenant D gets the EMPTY SET, even though D genuinely has a classified item — the aal2 backstop, inherited via account_trans, fails this read closed'
);
select is(
  _rls.count_as(:'td'::uuid, 'aal2',
    $$ select count(*) from pfin.fn_cashflow_contributors('2026-11-15'::date) $$
  ), 1::bigint,
  '(TT-AAL-B) ⭐ the POSITIVE leg that makes (TT-AAL-A) a test: the SAME tenant at aal2 sees their REAL 1 contributor row'
);

-- =====================================================================
-- NULL-ARG / PREDATES-DATA SEMANTICS.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.fn_cashflow_contributors(null::date)),
  0::bigint,
  '(TT-NULL) p_as_of NULL returns the EMPTY SET (the ordinary empty answer of a set-returning function, not an error)'
);
select is(
  (select count(*) from pfin.fn_cashflow_contributors('2020-01-01'::date)),
  0::bigint,
  '(TT-PREDATE) p_as_of predating every seeded transaction returns the EMPTY SET'
);

-- =====================================================================
-- GRAIN LEGS.
-- =====================================================================
-- (GR-SPLIT-A/B) split children each contribute under THEIR OWN Sub-Cat but
-- the PARENT's account_id.
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where sub_cat_id = :a_split1 and account_id = :a_acc1),
  '(GR-SPLIT-A) split child 1 contributes under its OWN Sub-Cat (a_split1) but the SPLIT PARENT''s account_id (a_acc1)'
);
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where sub_cat_id = :a_split2 and account_id = :a_acc1),
  '(GR-SPLIT-B) split child 2 contributes under its OWN Sub-Cat (a_split2) but the SAME parent account_id (a_acc1) — one account, several Sub-Cats'
);
-- (GR-NETZERO) fully-reversed item nets to 0 and STILL contributes.
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where sub_cat_id = :a_netzero and account_id = :a_acc1),
  '(GR-NETZERO) a fully-reversed item nets to 0 inside its own Sub-Cat but STILL contributes — group existence, not value'
);
-- (GR-OUTYEAR) an item outside the rendered year contributes NOTHING.
select ok(
  not exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where sub_cat_id = :a_outyear),
  '(GR-OUTYEAR) an item dated outside D''s rendered year contributes NOTHING — the leg that reds if a future edit drops the in_ytd conjunct'
);
-- (GR-TWOSUBCAT) one account feeding TWO distinct Sub-Cats yields TWO tuples.
select ok(
  (select array_agg(sub_cat_id) from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :a_acc1)
    @> array[:a_groceries, :a_dining]::bigint[],
  '(GR-TWOSUBCAT) a_acc1 contributes to BOTH Groceries99 (a_groceries) AND Dining99 (a_dining) — two tuples, one account'
);
-- (GR-TWOACCT) one Sub-Cat fed by TWO accounts yields TWO tuples.
select is(
  (select array_agg(account_id order by account_id) from pfin.fn_cashflow_contributors(:'d_asof'::date) where sub_cat_id = :a_groceries),
  array[least(:a_acc1,:a_acc2), greatest(:a_acc1,:a_acc2)]::bigint[],
  '(GR-TWOACCT) Groceries99 (a_groceries) is fed by EXACTLY {a_acc1, a_acc2} — two tuples, one Sub-Cat, the case that makes the §2.3.2 per-row indicator informative'
);
-- (GR-MANUAL) a manually-managed account (linked_source_id IS NULL) contributes exactly like a connected one — this function reads linked_source_id nowhere at all.
select ok(
  (select linked_source_id from pfin.account where account_id = :a_acc1) is null
  and exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :a_acc1),
  '(GR-MANUAL) a_acc1 has linked_source_id IS NULL (never linked) and STILL contributes normally — "no linked source" is not a special case here'
);

-- =====================================================================
-- SUPERSET CORROBORATION — the Equity-classified item (t_equity_cat) passes
--   the reader's S-1 predicate, appears in this function's RAW output
--   (deliberate superset over the ROLLUP's Revenue/Expense-only section
--   vocabulary), and has NO row in the rollup's sections. See the fixture
--   comment above for why this cannot ALSO be demonstrated against
--   fn_cashflow_per_account (Equity is one of ITS section_cats).
-- =====================================================================
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where cat = 'Equity' and sub_cat = 'EquityLabel99' and account_id = :a_acc1),
  '(SUP-RAW) the Equity-classified item IS present in the raw contributor output — this function is a deliberate SUPERSET of the rollup''s Revenue/Expense-only section vocabulary'
);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'EquityLabel99'),
  0::bigint,
  '(SUP-ROLLUP) the SAME Equity item is ABSENT from both rollup sections (Revenue/Expense only, AC5) — the contributor map disclosed it anyway'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- DORMANT-BRANCH PAIR — F is a NON-OWNER granted rd_access directly on E's
--   account (V1-dormant; revives with the first V2 sharing write path).
-- =====================================================================
select _rls.set_tenant(:'tf'::uuid);
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :e_acc and account_name is null),
  '(DB-NAME) LEFT-vs-INNER discriminator: F (rd_access, non-owner) reads a contributor row for e_acc with account_name IS NULL — present, not dropped, because the join to pfin.account is LEFT'
);
select results_eq(
  format($$ select sub_cat_id, cat, sub_cat from pfin.fn_cashflow_contributors(%L::date) where account_id = %s $$, :'d_asof', :e_acc),
  format($$ values (%s::bigint, null::text, null::text) $$, :e_exp),
  '(DB-TAXO) the THIRD taxonomy state, positively observed: sub_cat_id (e_exp) is NOT NULL while cat AND sub_cat are BOTH NULL — F sees E''s posting_prototype id copied from the annotation but cannot resolve E''s per-user RLS-scoped posting_prototype row'
);
select is(
  (select count(*) from pfin.fn_cashflow_contributors(:'d_asof'::date)),
  1::bigint,
  '(DB-COUNT) non-degenerate: F''s ENTIRE contributor set is exactly this 1 row — F owns nothing else and holds no other rd_access grant'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- CORRUPT-THE-CONTROL — the inherited-fence claim, MEASURED (086/093's own
--   discipline, carried here because this function's isolation is ENTIRELY
--   inherited from account_trans_select; account_select's LEFT JOIN gates
--   only account_name resolution for a row already in the set, never row
--   membership itself).
-- =====================================================================
savepoint sp_cc0;
-- (CC0) DEFENSE IN DEPTH: account_select ALONE corrupted open — A's
--   contributor account_id set is UNCHANGED; b_acc still does not appear,
--   because account_trans_select (not account_select) is what gates row
--   membership here.
alter policy account_select on pfin.account using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  not exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :b_acc),
  '(CC0) DEFENSE IN DEPTH, measured: with account_select ALONE broken OPEN, A''s contributor set still does NOT include b_acc — row membership here is gated by account_trans_select, not account_select'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_cc0;

savepoint sp_cc1;
-- (CC1) ⭐ LOAD-BEARING: account_trans_select ALSO corrupted open — NOW
--   b_acc leaks into A's contributor set, confirming isolation here really is
--   ENTIRELY inherited, with account_trans_select as the one relation whose
--   RLS actually does the work.
alter policy account_trans_select on pfin.account_trans using (true);
select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from pfin.fn_cashflow_contributors(:'d_asof'::date) where account_id = :b_acc),
  '(CC1) ⭐ CORRUPT-THE-CONTROL, load-bearing: with account_trans_select ALSO broken OPEN, b_acc NOW appears in A''s contributor set — proving the tenant fence is entirely INHERITED from account_trans_select, exactly as the migration''s own JOINT-REVIEW-MANDATORY ground (1) states'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_cc1;

select * from finish();
rollback;
