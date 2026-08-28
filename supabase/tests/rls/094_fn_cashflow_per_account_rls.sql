-- =====================================================================
-- Per-Wave battery — SELF-253 §2.3.3.a Per-account cash-flow drill-down
--   backend (pfin.fn_cashflow_per_account(p_account_id bigint, p_as_of
--   date)). Composes on `093`'s pfin.fn_cashflow_items(p_as_of) — the six
--   reader rules are 093's exclusive territory (SELF-257 close-gate) and
--   are NOT re-proven here. This file's scope is 094's OWN shaping logic:
--   the three-section union partition, account scoping, the
--   non-disclosing empty-document identity across owned-empty/foreign/
--   nonexistent/Trade-only account states, structure, sign convention,
--   the two-sided em-dash rule, and — the one non-negotiable reader-rule
--   leg this file DOES carry — proving the created-ON-D inclusion THROUGH
--   THE COMPOSER (ADR-011 Decision 19's 2026-08-22 half-open-bound
--   amendment: "that leg is now required of the §2.3 verification
--   battery," and 093's own L15a/L15b prove it only through the reader;
--   composition could break it independently).
--
-- BINDS TO (the committed 094_fn_cashflow_per_account.sql, verbatim):
--   pfin.fn_cashflow_per_account(p_account_id bigint, p_as_of date)
--   RETURNS jsonb — { as_of, account_id, sections: [ {section_key, cats,
--   rows:[{cat,sub_cat,month,q1,q2,q3,q4,ytd}], total:{month,q1,q2,q3,
--   q4,ytd}} exactly 3, order income -> other_cash_flows -> expenses,
--   ALWAYS present even empty ], unclassified: {count_ytd} }. NO
--   `targets` key (AC7). SECURITY INVOKER, STABLE, set search_path=''.
--
-- Prereqs exercised (on the 001->094 stack): 003/006 (account RLS), 004
--   (account_trans immutable ledger), 012 (transaction_type), 016/017
--   (asset registry + security_id/quantity), 023 (account_trans_annotation),
--   033 (journal_id), 084 (posting_prototype + is_tax_payment NOT NULL/
--   no-DEFAULT from 091), 093 (the shared reader + its six rules).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants A/B (shared
--   `_rls` helper tenants) + one extra tenant-A account beyond 093's own
--   fixture, suffixed '94'. NO PII / NO real account numbers / NO
--   production data. All seeds PRIVILEGED (role=postgres; RLS+ACL
--   bypassed), users_id set EXPLICITLY. All in a rolled-back txn.
--
-- §10 / DECISION 3: read ADR-011 Decision 4 + Decision 3 LIVE at
--   reconciliation, not restated/counted here (Path B). This battery
--   ASSUMES 094 adds ZERO catalogued §10 instances and Decision-3 family
--   UNCHANGED (read-only INVOKER composition, no new column, no FK-shaped
--   parameter — the migration's own header states `p_account_id` is
--   FK-shaped-LOOKING but not a Decision 3 instance, since Decision 3
--   membership turns on a stored column, not a function parameter
--   evaluated inside one RLS-scoped read) — pending Architect's own
--   confirmation at joint review.
--
-- Sec gate: JOINT-REVIEW MANDATORY per the SELF-253 description (financial
--   calculation + a client-supplied date parameter on a multi-tenant read,
--   RT-25). This file is QA's half of that review's evidence; it does not
--   substitute for it.
--
-- plan(23):
--   CREATED-ON-D-1/2 (composer-level half-open inclusion/exclusion, the
--     non-negotiable leg) · EMPTY-3/4/5 (owned-empty == foreign ==
--     nonexistent == Trade-only, the non-disclosing identity) ·
--     UNION-1/2 (Transfer+Equity same section, raw-signed net) ·
--     TRADE-EXCL (Trade in no section despite co-existing activity) ·
--     TRADE-ONLY-3SEC (explicit 3-section check on the Trade-only account) ·
--     SCOPE-1/2 (two tenant-A accounts, each account's rows absent from
--     the other's document) · STRUCT-COUNT/ORDER/CATS/NOTARGETS/
--     UNCLASSIFIED-PRESENT · UNCLASSIFIED-SCOPED · EMDASH-NOTSTARTED/
--     STARTED-EMPTY · SIGN-EXPENSE/SIGN-INCOME · TOTAL-FOOTS-DOWN ·
--     TENANT-B-OWN-ACCESS (positive control: foreign-to-A but own-to-B
--     access is NOT blocked).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(23);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

\set d_asof '2026-10-15'
\set d2_asof '2026-02-15'

-- =====================================================================
-- FIXTURE (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-a1-94 (rich: income/expense/transfer/equity/trade/
--    unannotated/created-on-D pair), acct-a2-94 (owned-but-empty, zero
--    rows — the empty-identity referent and the em-dash D2 referent),
--    acct-a3-94 (Trade-classified activity ONLY), acct-a4-94 (its OWN
--    classified + unclassified activity — the account-scoping referent).
--  - B owns acct-b1-94, its own classified activity (the cross-tenant
--    referent AND the positive-access-control referent).
-- =====================================================================
insert into auth.users (id) values (:'ta'), (:'tb')
  on conflict (id) do nothing;

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a1-94', 'investment', 'household', 'taxable')
  returning account_id as accta1 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a2-94', 'depository', 'household', 'taxable')
  returning account_id as accta2 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a3-94', 'investment', 'household', 'taxable')
  returning account_id as accta3 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a4-94', 'depository', 'household', 'taxable')
  returning account_id as accta4 \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-b1-94', 'depository', 'household', 'taxable')
  returning account_id as acctb1 \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GSX94', 'Global Sec X (094 Trade control)')
  returning asset_id as g_asset \gset

-- posting_prototype (A). is_tax_payment NOT NULL no DEFAULT (091) -> false throughout.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Revenue', 'Salary94', false) returning id as a_salary \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Groceries94', false) returning id as a_groceries \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'CreatedOnD94', false) returning id as a_createdond \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'BankTransfer94', false) returning id as a_transfer \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Equity', 'Contribution94', false) returning id as a_equity \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Trade', 'BTO94', false) returning id as a_trade \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'UtilitiesAcct4_94', false) returning id as a_util4 \gset

-- posting_prototype (B) — the cross-tenant / positive-access-control referent.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'BExpense94', false) returning id as b_exp \gset

-- ---------------------------------------------------------------------
-- account_trans (acct-a1-94). D = 2026-10-15 — every 2026 quarter has
-- already started, matching 093's own fixture's quarter shape.
-- ---------------------------------------------------------------------
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta1, '2026-10-10', 5000, 'vSalary', '094 income row')
  returning trans_id as t_income \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_income, :a_salary);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta1, '2026-10-05', -120, 'vGroceries', '094 expense row (sign-convention leg)')
  returning trans_id as t_expense \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_expense, :a_groceries);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta1, '2026-10-06', -300, 'vBankTransfer', '094 non-journaled Transfer leg (union)')
  returning trans_id as t_transfer \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:t_transfer, :a_transfer);  -- journal_id NULL: non-journaled, passes S-1

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta1, '2026-10-07', 6000, 'vEquityContrib', '094 non-journaled Equity leg (union)')
  returning trans_id as t_equity \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:t_equity, :a_equity);  -- journal_id NULL: non-journaled, passes S-1

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta1, '2026-10-08', -800, 'vTrade', '094 Trade leg (must land in NO section)', :g_asset, 8)
  returning trans_id as t_trade \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_trade, :a_trade);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta1, '2026-10-09', -15, 'vUnannotated', '094 unclassified row (E3, no annotation at all)')
  returning trans_id as t_unannotated \gset

-- CREATED-ON-D pair — the non-negotiable composer-level leg (ADR-011
-- Decision 19's 2026-08-22 amendment). Both share the SAME Sub-Cat so a
-- single row-lookup isolates whether the excluded row silently leaked in.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta1, :'d_asof'::date, -111.11, 'vCreatedOk94', '094 created ON D, within half-open bound (MUST be included)', '2026-10-15 23:59:59+00')
  returning trans_id as t_created_ok \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_created_ok, :a_createdond);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta1, :'d_asof'::date, -222.22, 'vCreatedLate94', '094 created at D+1 00:00:00, excluded despite same transaction_date', '2026-10-16 00:00:00+00')
  returning trans_id as t_created_late \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_created_late, :a_createdond);

-- acct-a2-94: owned-but-empty. NO account_trans rows at all.

-- acct-a3-94: Trade-classified activity ONLY.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta3, '2026-10-08', -400, 'vTradeOnly', '094 Trade-only account (must show the ordinary empty document)', :g_asset, 4)
  returning trans_id as t_trade_only \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_trade_only, :a_trade);

-- acct-a4-94: its OWN classified + unclassified activity (account-scoping referent).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta4, '2026-10-11', -50, 'vUtilAcct4', '094 acct-a4-94 own classified row (must not leak into acct-a1-94)')
  returning trans_id as t_a4_expense \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_a4_expense, :a_util4);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta4, '2026-10-12', -9, 'vUnannotatedAcct4', '094 acct-a4-94 own unclassified row (unclassified-count scoping)')
  returning trans_id as t_a4_unannotated \gset

-- acct-b1-94 (tenant B): own classified activity — cross-tenant referent
-- AND the positive-access-control leg (B reading its own account works).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb1, '2026-10-13', -77, 'vB1', '094 tenant-B own row')
  returning trans_id as t_b1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_b1, :b_exp);

-- =====================================================================
-- ASSERTIONS — tenant A context (all but the final positive-access leg).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- CREATED-ON-D-1 — the row created ON D (within the half-open bound) IS
-- included: its Sub-Cat's YTD renders exactly its own negated amount.
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'CreatedOnD94'),
  111.11::numeric,
  '094 CREATED-ON-D-1: a row created ON D (created_at < D+1) is INCLUDED through the composer, rendering only its own amount'
);

-- CREATED-ON-D-2 — the sibling row created at EXACTLY D+1 00:00:00 is
-- excluded: the SAME Sub-Cat's total does not grow to reflect it. Proven
-- as the negation, not a separate absence check, so a regression that
-- silently included it flips the value tested above, not a second query.
select isnt(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'CreatedOnD94'),
  333.33::numeric,
  '094 CREATED-ON-D-2: a row created at D+1 00:00:00 is EXCLUDED through the composer — the shared Sub-Cat''s total does not grow to 333.33'
);

-- EMPTY identity captures.
select (pfin.fn_cashflow_per_account(:accta2, :'d_asof'::date) - 'account_id') as empty_doc \gset
select (pfin.fn_cashflow_per_account(:acctb1, :'d_asof'::date) - 'account_id') as foreign_doc \gset
select (pfin.fn_cashflow_per_account(999999999999, :'d_asof'::date) - 'account_id') as nonexistent_doc \gset
select (pfin.fn_cashflow_per_account(:accta3, :'d_asof'::date) - 'account_id') as tradeonly_doc \gset

-- EMPTY-3 — owned-but-empty and a FOREIGN account (owned by tenant B)
-- produce the IDENTICAL ordinary empty document.
select is(
  :'foreign_doc'::jsonb,
  :'empty_doc'::jsonb,
  '094 EMPTY-3: an owned-but-empty account and a foreign (tenant-B-owned) account produce the IDENTICAL empty document — non-disclosing by construction'
);

-- EMPTY-4 — owned-but-empty and a NONEXISTENT account_id produce the
-- IDENTICAL document too — the three states are indistinguishable.
select is(
  :'nonexistent_doc'::jsonb,
  :'empty_doc'::jsonb,
  '094 EMPTY-4: an owned-but-empty account and a NONEXISTENT account_id produce the IDENTICAL empty document'
);

-- EMPTY-5 — a Trade-classified-ONLY account (real activity, but the
-- reader's M2 predicate excludes every row from the item set) ALSO
-- produces the identical empty document, not a document with a Trade row.
select is(
  :'tradeonly_doc'::jsonb,
  :'empty_doc'::jsonb,
  '094 EMPTY-5: a Trade-classified-ONLY account produces the SAME empty document as owned-but-empty — Trade activity is invisible upstream, not merely unsectioned'
);

-- UNION-1 — Transfer AND Equity rows land in the SAME other_cash_flows
-- section (both Sub-Cats present in that one section's rows).
select bag_eq(
  format($$ select row ->> 'sub_cat'
              from jsonb_array_elements(pfin.fn_cashflow_per_account(%s, %L::date) -> 'sections') s,
                   jsonb_array_elements(s -> 'rows') row
             where s ->> 'section_key' = 'other_cash_flows' $$, :accta1, :'d_asof'),
  $$ values ('BankTransfer94'), ('Contribution94') $$,
  '094 UNION-1: Transfer and Equity rows land in the SAME other_cash_flows section'
);

-- UNION-2 — the section total is the RAW-SIGNED net of both (-300 + 6000
-- = 5700), never abs()''d and never per-class-split.
select is(
  (select (s -> 'total' ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s
    where s ->> 'section_key' = 'other_cash_flows'),
  5700::numeric,
  '094 UNION-2: other_cash_flows Total is the raw-signed net of the Transfer and Equity legs (-300 + 6000 = 5700)'
);

-- TRADE-EXCL — the Trade leg (co-existing with real income/expense/
-- transfer/equity activity on the SAME account) appears in NO section.
select is(
  (select count(*)
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'BTO94'),
  0::bigint,
  '094 TRADE-EXCL: a Trade-classified leg appears in NO section, even on an account with other real activity'
);

-- TRADE-ONLY-3SEC — explicit, not merely inferred via EMPTY-5''s equality:
-- the Trade-only account still emits exactly 3 sections.
select is(
  (select jsonb_array_length(pfin.fn_cashflow_per_account(:accta3, :'d_asof'::date) -> 'sections')),
  3,
  '094 TRADE-ONLY-3SEC: a Trade-classified-ONLY account still emits exactly 3 sections (present even empty)'
);

-- SCOPE-1 — acct-a4-94''s own classified row never appears in
-- acct-a1-94''s document.
select is(
  (select count(*)
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'UtilitiesAcct4_94'),
  0::bigint,
  '094 SCOPE-1: acct-a4-94''s own Sub-Cat row never appears in acct-a1-94''s document'
);

-- SCOPE-2 — the reverse: acct-a1-94''s rows never appear in acct-a4-94''s document.
select is(
  (select count(*)
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta4, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' in ('Salary94', 'Groceries94', 'BankTransfer94', 'Contribution94', 'CreatedOnD94')),
  0::bigint,
  '094 SCOPE-2: acct-a1-94''s Sub-Cat rows never appear in acct-a4-94''s document'
);

-- STRUCT-COUNT — exactly 3 sections.
select is(
  (select jsonb_array_length(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections')),
  3,
  '094 STRUCT-COUNT: exactly 3 sections'
);

-- STRUCT-ORDER — section_key values in the PRD''s ruled order.
select is(
  (select jsonb_agg(s ->> 'section_key' order by ord)
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') with ordinality as t(s, ord)),
  '["income", "other_cash_flows", "expenses"]'::jsonb,
  '094 STRUCT-ORDER: section_key order is income -> other_cash_flows -> expenses'
);

-- STRUCT-CATS — the `cats` watcher array is exactly {Revenue} / {Equity,
-- Transfer} (alphabetical) / {Expense}.
select is(
  (select jsonb_agg(s -> 'cats' order by ord)
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') with ordinality as t(s, ord)),
  '[["Revenue"], ["Equity", "Transfer"], ["Expense"]]'::jsonb,
  '094 STRUCT-CATS: cats arrays are exactly {Revenue} / {Equity,Transfer} / {Expense}, the mechanical partition watcher'
);

-- STRUCT-NOTARGETS — NO `targets` key anywhere on the document (AC7).
select ok(
  not (pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) ? 'targets'),
  '094 STRUCT-NOTARGETS: the document carries no targets key — a single-account scope has none to synthesise'
);

-- STRUCT-UNCLASSIFIED-PRESENT — unclassified.count_ytd exists (not NULL).
select ok(
  (pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'unclassified' -> 'count_ytd') is not null,
  '094 STRUCT-UNCLASSIFIED-PRESENT: unclassified.count_ytd is present'
);

-- UNCLASSIFIED-SCOPED — acct-a1-94''s count reflects ONLY its own
-- unannotated row (1), not inflated by acct-a4-94''s own unclassified row.
select is(
  (pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'unclassified' ->> 'count_ytd')::bigint,
  1::bigint,
  '094 UNCLASSIFIED-SCOPED: acct-a1-94''s unclassified.count_ytd counts only ITS OWN unannotated row, not acct-a4-94''s'
);

-- EMDASH-NOTSTARTED / EMDASH-STARTED-EMPTY — using acct-a2-94 (owned-but-
-- empty) at D2 = 2026-02-15: Q1 has started (from Jan 1) with zero rows
-- -> 0; Q2 has NOT started -> JSON null. Never collapsed.
select is(
  (select (s -> 'total' -> 'q1')
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta2, :'d2_asof'::date) -> 'sections') s
    where s ->> 'section_key' = 'income'),
  '0'::jsonb,
  '094 EMDASH-STARTED-EMPTY: a started quarter (Q1, D2 in Feb) with no rows renders a real 0, not null'
);
select is(
  (select (s -> 'total' -> 'q2')
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta2, :'d2_asof'::date) -> 'sections') s
    where s ->> 'section_key' = 'income'),
  'null'::jsonb,
  '094 EMDASH-NOTSTARTED: a quarter that has not yet started relative to D2 (Q2) renders JSON null, never 0'
);

-- SIGN-EXPENSE — Expense negation: -120 stored renders +120.
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Groceries94'),
  120::numeric,
  '094 SIGN-EXPENSE: a -120 stored Expense leg renders +120 (outflow-positive convention)'
);

-- SIGN-INCOME — Income is already inflow-positive, no negation.
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Salary94'),
  5000::numeric,
  '094 SIGN-INCOME: a +5000 stored Revenue leg renders +5000 unchanged'
);

-- TOTAL-FOOTS-DOWN — the Expense section''s Total sums its Sub-Cat rows'
-- real signed values, independently recomputed from the shared reader
-- (never a hand-tracked literal): Groceries94 (-120) + CreatedOnD94's
-- INCLUDED leg only (-111.11), negated.
select is(
  (select (s -> 'total' ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:accta1, :'d_asof'::date) -> 'sections') s
    where s ->> 'section_key' = 'expenses'),
  (select -1 * sum(amount_net) from pfin.fn_cashflow_items(:'d_asof'::date)
    where account_id = :accta1 and cat = 'Expense' and sub_cat_id is not null and in_ytd),
  '094 TOTAL-FOOTS-DOWN: the Expenses Total sums its Sub-Cat rows'' real signed values (independently recomputed from the shared reader, account-scoped), never abs()''d'
);

-- =====================================================================
-- TENANT-B-OWN-ACCESS — positive control: acct-b1-94 is FOREIGN to
-- tenant A (proven empty above via EMPTY-3) but is NOT blocked for its
-- own owner. Guards against "RLS blocks everything" masquerading as
-- "RLS blocks cross-tenant access."
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);

select ok(
  (select jsonb_array_length(sec -> 'rows') > 0
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:acctb1, :'d_asof'::date) -> 'sections') sec
    where sec ->> 'section_key' = 'expenses'),
  '094 TENANT-B-OWN-ACCESS: tenant B reading its OWN account is NOT blocked — the foreign-account emptiness above is RLS-selective, not RLS-total'
);

select * from finish();
rollback;
