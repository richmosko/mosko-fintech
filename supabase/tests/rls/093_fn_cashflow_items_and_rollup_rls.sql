-- =====================================================================
-- Per-Wave battery — SELF-250 §2.3.2.a Cross-account rollup backend + the
--   shared §2.3 reader (provisionally pfin.fn_cashflow_items(p_as_of date))
--   and pfin.fn_cashflow_cross_account_rollup(p_as_of date). Also proves the
--   8a-promoted partial-unique index on account_trans.replaces_trans_id
--   (second reversal of the same original REFUSED).
-- =====================================================================
-- ⟦FINALIZED against architect-250's committed blob⟧ QA is RESPONDER on this
--   pair; architect-250 is HOLDER. Bind-target sha 16538b67515def2d3f7cf84
--   220ee2e75dae09064 (feature/self-250-cashflow-rollup), file
--   supabase/migrations/093_cashflow_reader_and_rollup.sql, blob md5
--   10d679374f4c78947e1a4ba052917fbb (self-computed via `git show
--   <sha>:<path> | md5`, not taken from a report). First drafted against the
--   re-derived ACs (Linear SELF-250, tree-verified at 0491830) + the V1.3
--   pre-flight sitting items 8a/9a; reconciled here against the actual
--   committed function bodies — three real mismatches were caught at
--   reconciliation and are fixed in place (not left as TODOs):
--     (1) rollup section rows carry `sub_cat` (the NAME), never
--         `sub_cat_id` — RU2/RU-EQ originally matched on a key that does
--         not exist in the shipped shape.
--     (2) RU3 (the Total-row sum-down leg) originally hardcoded -380 from
--         only the two RU2 sign-convention fixture rows (OfficeSupplies +
--         Utilities) — WRONG, because the Expense section''s Total sums
--         EVERY Expense Sub-Cat this fixture seeds (Groceries, Split1/2,
--         the netted Dining/Office pair too), not just those two. Fixed to
--         an INDEPENDENT recomputation straight from pfin.fn_cashflow_items
--         rather than a hand-tracked literal, which is also more robust to
--         future fixture additions in this file.
--     (3) the same reasoning applied pre-emptively to RU6 (the
--         unclassified.count_ytd banner identity, AC8) — added at
--         reconciliation, also independently recomputed rather than
--         hand-counted, since this fixture''s incidental unclassified-item
--         count (E3a + the L15a created-on-D row) is easy to miscount by
--         inspection.
--   NOT YET RUN under pg_prove (scratch-DB run pending — see the hand-off
--   report); this header will be corrected with the actual pg_prove summary
--   once that run completes. Never trust a bare `psql` run of this file —
--   pgTAP's plan-count enforcement only works through a TAP-aware consumer.
--
-- BINDS TO (the committed 093_cashflow_reader_and_rollup.sql, verbatim):
--   - pfin.fn_cashflow_items(p_as_of date) RETURNS TABLE(
--       item_kind text, item_id bigint, trans_id bigint, account_id bigint,
--       transaction_date date, sub_cat_id bigint, cat text, sub_cat text,
--       amount_net numeric(20,4), in_month boolean, in_q1 boolean,
--       in_q2 boolean, in_q3 boolean, in_q4 boolean, in_ytd boolean)
--     SECURITY INVOKER, STABLE, set search_path=''. No tenant parameter —
--     isolation inherited from RLS on account/account_trans/
--     account_trans_annotation/account_trans_split/posting_prototype.
--   - pfin.fn_cashflow_cross_account_rollup(p_as_of date) RETURNS jsonb —
--     { "as_of", "sections": [ {"cat","rows":[{"sub_cat","month","q1",
--       "q2","q3","q4","ytd"}, ...], "total":{"month","q1","q2","q3","q4",
--       "ytd"}}, ... exactly 2, Revenue then Expense, ALWAYS present even
--       empty ], "targets": {"income_target_annual",
--       "expense_target_monthly"}, "unclassified": {"count_ytd"} }.
--     A quarter not yet started relative to p_as_of renders JSON null
--     (em-dash), never 0 — irrelevant to this file's D=2026-10-15 fixture,
--     where every 2026 quarter has started.
--   - pfin.account_trans_reversal_unique_idx — unique index on
--     pfin.account_trans(replaces_trans_id) WHERE is_reverse (verbatim
--     predicate, no `and replaces_trans_id is not null` conjunct — NULLs
--     are distinct in a unique index already). Discovered DYNAMICALLY below
--     rather than hardcoded, since the discovery logic is correct either
--     way and costs nothing.
--
-- Prereqs exercised (on the 001->092 stack): 003/006 (account + rd/wr_access
--   JOIN RLS), 004 (account_trans immutable ledger + the matched-account
--   fence on replaces_trans_id), 012 (transaction_type), 016/017 (asset
--   registry + security_id/quantity), 023 (account_trans_annotation +
--   #10 matched_sub_cat), 029 (account_trans_split + Σ=parent deferred
--   constraint), 030 (transaction_type vocab + Trade constraints), 033
--   (pfin.journal + journal_id + #12 matched_journal), 084 (posting_prototype
--   — the FK re-target both 023/029's sub_cat_id now point at; the
--   is_tax_payment NOT NULL/no-DEFAULT column from 091), 090
--   (pfin.cashflow_target — the targets source).
--
-- THE SIX RULES, per-leg map (SELF-250 description, "housed here and
--   nowhere else"):
--   (1) S-1 predicate            -> R1/R2/R3a/R5 (5 legs incl. R4's is_reverse
--                                    exclusion, per-rule below)
--   (2) split XOR                -> R3a/R3b/R3c
--   (3) E1 netting               -> N1/R4/N3/N4
--   (4) E3 LEFT JOIN             -> E3a
--   (5) S-3 period grammar       -> S3a/S3b/S3c
--   (6) Lock 15 dual-column half-open as-of -> L15a/L15b/L15c
--
-- ┌─ WHY THE INDEX INVERSION USES SAVEPOINT ROLLBACK, NOT DDL RECONSTRUCTION ─┐
-- │ The dispatch's "drop the index on scratch -> the duplicate lands ->       │
-- │ restore" is honoured here by SAVEPOINT / ROLLBACK TO SAVEPOINT rather     │
-- │ than capturing pg_get_indexdef() and re-issuing it: a savepoint rollback  │
-- │ restores the EXACT prior index definition byte-for-byte (no risk of a     │
-- │ hand-reconstructed CREATE INDEX drifting from what was actually dropped), │
-- │ and it composes cleanly with pgTAP's own throws_ok/lives_ok internal      │
-- │ exception handling (both nest fine inside an outer named savepoint).      │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ RU-EQ — WHY EQUITY, NOT TRANSFER OR TRADE, IS THE SECTION-EXCLUSION      ┐
-- │ DISCRIMINATOR: Transfer legs in this fixture are already excluded from    │
-- │ the READER's item set via the journal_id predicate (R5) and Trade legs    │
-- │ via the security_id predicate (R2) — neither would ever reach the         │
-- │ rollup's section-filter step, so testing them there would be VACUOUS      │
-- │ (an already-excluded-upstream row proves nothing about a downstream       │
-- │ filter). A non-journaled, non-security Equity-classified item DOES pass   │
-- │ the reader's S-1 predicate and DOES appear in fn_cashflow_items — so its  │
-- │ absence from BOTH rollup sections is the one leg that actually exercises  │
-- │ AC5's "Transfer, Trade and Equity are excluded from THIS surface."        │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: read ADR-011 Decision 4 + Decision 3 LIVE at
--   reconciliation, not restated/counted here (Path B). This battery ASSUMES
--   the reader + rollup add ZERO catalogued §10 instances (read-only INVOKER,
--   no service_role, no credential surface) and Decision-3 family UNCHANGED
--   (no new table, no new FK-shaped column authored by a pure read
--   composition) — pending Architect's actual migration text. The reversal-
--   dedup partial-unique index is NOT a Decision-3 instance (it constrains
--   uniqueness, not tenant-matching) and NOT a §10 instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants suffixed '93'
--   for this migration (provisional). NO PII / NO real account numbers / NO
--   production data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed),
--   users_id set EXPLICITLY. All in a rolled-back txn.
--
-- Sec gate: JOINT-REVIEW MANDATORY per the SELF-250 description (the reader
--   is THE money-path for §2.3). This file is QA's half of that review's
--   evidence; it does not substitute for it.
--
-- plan(31) — see the per-rule map above; RU6 (the unclassified-banner
--   identity, AC8) was added at reconciliation against the committed blob.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(31);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

\set d_asof '2026-10-15'

-- =====================================================================
-- FIXTURE (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - A owns acct-a (investment; carries cash + one Trade leg).
--  - B owns acct-b (depository; its own classified history — the cross-
--    tenant referent).
--  - C owns NO account/txns at all — it exists only to carry the explicit
--    both-columns-NULL cashflow_target row for RU5 (row-absent vs all-NULL
--    row equivalence).
-- =====================================================================
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-a93', 'investment', 'household', 'taxable')
  returning account_id as accta \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'acct-b93', 'depository', 'household', 'taxable')
  returning account_id as acctb \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GSX93', 'Global Sec X (093 Trade control)')
  returning asset_id as g_asset \gset

-- posting_prototype (A). is_tax_payment NOT NULL no DEFAULT (091) -> false throughout.
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Groceries93', false) returning id as a_groceries \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Dining93', false) returning id as a_dining \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Office93', false) returning id as a_office \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Utilities93', false) returning id as a_utilities \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'OfficeSupplies93', false) returning id as a_officesupplies \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Split1_93', false) returning id as a_split1 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Expense', 'Split2_93', false) returning id as a_split2 \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Transfer', 'Transfer93', false) returning id as a_transfer \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Trade', 'BTO93', false) returning id as a_trade \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'ta', 'Equity', 'OwnerContribution93', false) returning id as a_equity \gset

-- journal (A) — the journaled-exclusion referent (R5).
insert into pfin.journal (users_id, group_type, status, description)
  values (:'ta', 'transfer', 'open', '093 R5 journaled-leg fixture')
  returning journal_id as j_a \gset

-- ---------------------------------------------------------------------
-- account_trans rows (A). Dates chosen so p_as_of = 2026-10-15 (D):
--   Q1=2026-02-01, Q2=2026-05-01, Q3(month-boundary)=2026-09-30,
--   Q4/month=2026-10-10.
-- ---------------------------------------------------------------------

-- R1 — M1: transaction_type <> 'standard' excluded regardless of annotation.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:accta, '2026-01-01', 1000, 'vAcctSetup', '093 R1 acct_setup excluded', 'acct_setup')
  returning trans_id as t_acctsetup \gset

-- R2 — M2: security_id IS NOT NULL excluded (Trade leg; quantity>0 per 017 CHECK).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, security_id, quantity)
  values (:accta, '2026-01-02', -500, 'vTrade', '093 R2 security-row excluded', :g_asset, 5)
  returning trans_id as t_trade \gset

-- R3 — split XOR: parent excluded, 2 children emitted with their OWN Sub-Cats.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-06-15', -90, 'vSplitParent', '093 R3 split parent (never emitted)')
  returning trans_id as t_split_parent \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split_parent, :a_split1, -60) returning id as split_child1 \gset
insert into pfin.account_trans_split (account_trans_id, sub_cat_id, amount)
  values (:t_split_parent, :a_split2, -30) returning id as split_child2 \gset

-- R5 — journaled leg excluded regardless of classification.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-06-20', -200, 'vTransfer', '093 R5 journaled leg excluded')
  returning trans_id as t_transfer \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id, journal_id)
  values (:t_transfer, :a_transfer, :j_a);

-- E3a — a standard cash row with NO annotation row at all: must appear with
-- NULL cat (the inner-join trap this rule exists to catch).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-06-25', -15, 'vUnannotated', '093 E3a unannotated row')
  returning trans_id as t_unannotated \gset

-- N1/N3/R4 — E1 netting: a fully-reversed original nets to 0 inside its own
-- Sub-Cat, invariant under later reclassification. The reversal row (r1)
-- itself must never appear as an item (R4).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-10', -40, 'vOrig', '093 N1/N3 reversal-netting original')
  returning trans_id as o1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:o1, :a_dining);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id)
  values (:accta, '2026-05-11', 40, 'vRev', '093 N1 reversal of o1', true, :o1)
  returning trans_id as r1 \gset

-- N4 — partial reversal nets partially (only ONE of two same-Sub-Cat rows
-- reversed; the group nets to the survivor's amount, not 0 and not the sum).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-07-01', -30, 'vPartial1', '093 N4 partial-reversal original')
  returning trans_id as p1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:p1, :a_utilities);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id)
  values (:accta, '2026-07-02', 30, 'vPartialRev', '093 N4 reversal of p1', true, :p1)
  returning trans_id as rp1 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-07-05', -20, 'vPartial2', '093 N4 unreversed sibling')
  returning trans_id as p2 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
  values (:p2, :a_utilities);

-- S3a/S3b/S3c — S-3 period grammar. 4 Groceries rows spanning all 4 quarters
-- of 2026, truncated at D=2026-10-15 (Q4 itself only partially elapsed).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-02-01', -100, 'vQ1', '093 S3 Q1 row')
  returning trans_id as t_q1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_q1, :a_groceries);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-05-01', -50, 'vQ2', '093 S3 Q2 row')
  returning trans_id as t_q2 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_q2, :a_groceries);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-09-30', -70, 'vQ3', '093 S3 Q3 row (month-lower-bound control: one day before D''s month starts)')
  returning trans_id as t_q3 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_q3, :a_groceries);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-10-10', -40, 'vQ4', '093 S3 Q4/month row')
  returning trans_id as t_q4 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_q4, :a_groceries);

-- L15a/L15b/L15c — Lock 15 dual-column half-open as-of: transaction_date<=D
-- AND created_at < D+1. created_at is settable on INSERT (no wall-clock dep).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, :'d_asof'::date, -5, 'vCreatedOk', '093 L15a created within D', '2026-10-15 23:59:59+00')
  returning trans_id as t_created_ok \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, :'d_asof'::date, -6, 'vCreatedLate', '093 L15b created exactly at D+1 (excluded)', '2026-10-16 00:00:00+00')
  returning trans_id as t_created_late \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at)
  values (:accta, '2026-10-16', -7, 'vFuture', '093 L15c transaction_date > D (excluded)', '2026-10-16 00:00:00+00')
  returning trans_id as t_future \gset

-- RU2/RU3 — sign convention: a refund-heavy Expense Sub-Cat nets to a REAL
-- CREDIT (raw sum positive), which the "outflow-positive" display convention
-- must render NEGATIVE, never abs()'d positive.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-08-01', -100, 'vOfficeCharge', '093 RU2 office-supplies charge')
  returning trans_id as t_office_charge \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_office_charge, :a_officesupplies);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-08-15', 500, 'vOfficeRefund', '093 RU2 office-supplies refund (dominates -> net credit)')
  returning trans_id as t_office_refund \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_office_refund, :a_officesupplies);

-- RU-EQ — a non-journaled, non-security Equity-classified item: passes the
-- reader's S-1 predicate (so it DOES appear in fn_cashflow_items) and must
-- still be excluded from BOTH rollup sections (Revenue/Expense only, AC5).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-03-01', 5000, 'vEquity', '093 RU-EQ owner contribution')
  returning trans_id as t_equity \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_equity, :a_equity);

-- Tenant B's own classified history (the cross-tenant referent, X1/X2).
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment)
  values (:'tb', 'Expense', 'BExpense93', false) returning id as b_exp \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:acctb, '2026-06-01', -25, 'vB', '093 X1/X2 tenant-B own row')
  returning trans_id as b1 \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:b1, :b_exp);

-- cashflow_target (090): A partial-set (income only), C explicit both-NULL
-- row, B row-absent (no INSERT at all) — the RU5 row-absent/all-NULL pair.
insert into pfin.cashflow_target (users_id, income_target_annual, expense_target_monthly)
  values (:'ta', 60000, null);
insert into pfin.cashflow_target (users_id, income_target_annual, expense_target_monthly)
  values (:'tc', null, null);

-- =====================================================================
-- READER ASSERTIONS — all as tenant A unless noted. fn_cashflow_items is
-- SECURITY INVOKER / STABLE, no tenant parameter (RLS-inherited isolation).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- R1 — M1 acct_setup excluded.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_acctsetup),
  0::bigint,
  '093 R1: transaction_type <> ''standard'' (acct_setup) never appears as an item'
);

-- R2 — M2 security-row excluded.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_trade),
  0::bigint,
  '093 R2: a row with security_id IS NOT NULL never appears as an item'
);

-- R3a — split parent excluded (item_kind='transaction' never fires for it).
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date)
    where trans_id = :t_split_parent and item_kind = 'transaction'),
  0::bigint,
  '093 R3a: split XOR — the parent is never emitted once split_count > 0'
);

-- R3b — split children emitted, exactly 2.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date)
    where trans_id = :t_split_parent and item_kind = 'split_child'),
  2::bigint,
  '093 R3b: split XOR — exactly the 2 children are emitted, never the parent too'
);

-- R3c — each split child carries its OWN Sub-Cat (granularity, not the parent's).
select bag_eq(
  format($$ select sub_cat_id from pfin.fn_cashflow_items(%L::date)
             where trans_id = %s and item_kind = 'split_child' $$, :'d_asof', :t_split_parent),
  format($$ values (%s::bigint), (%s::bigint) $$, :a_split1, :a_split2),
  '093 R3c: split children resolve to their OWN distinct Sub-Cats, not the parent''s'
);

-- R5 — journaled leg excluded regardless of classification.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_transfer),
  0::bigint,
  '093 R5: a leg attached to a journal never appears as an item'
);

-- N1 — a fully-reversed original nets to 0 inside its own Sub-Cat.
select is(
  (select amount_net from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :o1),
  0::numeric,
  '093 N1: E1 netting — a fully-reversed original nets to 0'
);

-- R4 — is_reverse rows (r1, rp1) never appear as items themselves.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id in (:r1, :rp1)),
  0::bigint,
  '093 R4: is_reverse rows are never emitted as items — only their amount is netted into the original'
);

-- N3 — the net invariant survives reclassifying the original AFTER reversal.
update pfin.account_trans_annotation set sub_cat_id = :a_office where trans_id = :o1;
select results_eq(
  format($$ select sub_cat_id, amount_net from pfin.fn_cashflow_items(%L::date) where trans_id = %s $$, :'d_asof', :o1),
  format($$ values (%s::bigint, 0::numeric) $$, :a_office),
  '093 N3: amount_net stays 0 under the NEW Sub-Cat after the original is reclassified post-reversal'
);

-- N4 — partial reversal nets partially: the group is the unreversed survivor's
-- amount only, never 0 and never the raw sum of both rows.
select is(
  (select sum(amount_net) from pfin.fn_cashflow_items(:'d_asof'::date) where sub_cat_id = :a_utilities),
  -20::numeric,
  '093 N4: a partially-reversed Sub-Cat group nets to the unreversed survivor''s amount, not 0 and not the raw sum'
);

-- E3a — the un-annotated row: LEFT JOIN means it appears with a NULL cat, not
-- silently dropped by an inner join.
select results_eq(
  format($$ select sub_cat_id, cat, amount_net from pfin.fn_cashflow_items(%L::date) where trans_id = %s $$, :'d_asof', :t_unannotated),
  $$ values (null::bigint, null::text, -15::numeric) $$,
  '093 E3a: a standard cash row with NO annotation row appears with NULL sub_cat_id/cat (the inner-join trap this rule catches)'
);

-- L15a — a row created WITHIN D (created_at < D+1) is included.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_created_ok),
  1::bigint,
  '093 L15a: half-open as-of — created_at strictly before D+1 is included'
);

-- L15b — a row created EXACTLY at D+1 00:00:00 is excluded, despite transaction_date<=D.
-- ⚠ TIMEZONE-SENSITIVE BOUNDARY: this literal assumes D+1 casts to midnight UTC
-- inside the reader. If Architect's implementation casts against the session/
-- server local timezone instead, this boundary literal needs adjusting at
-- finalize — re-verify against the committed function body, not this comment.
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_created_late),
  0::bigint,
  '093 L15b: half-open as-of boundary — created_at = D+1 00:00:00 is excluded (the defective Lock 15 verbatim predicate, per D-9, is NOT what this reader implements)'
);

-- L15c — transaction_date > D excluded (the other half of the dual-column filter).
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :t_future),
  0::bigint,
  '093 L15c: transaction_date > D is excluded regardless of created_at'
);

-- S3a — the Q4/month row: in_month, in_q4 and in_ytd all true.
select results_eq(
  format($$ select in_month, in_q4, in_ytd from pfin.fn_cashflow_items(%L::date) where trans_id = %s $$, :'d_asof', :t_q4),
  $$ values (true, true, true) $$,
  '093 S3a: a row inside D''s partial month is in_month/in_q4/in_ytd'
);

-- S3b — the Q3 row (2026-09-30, one day before D''s month starts): NOT in_month,
-- but in_q3 and in_ytd — proves Month is a PARTIAL month (truncated at its own
-- start), not "whichever quarter/year D falls in".
select results_eq(
  format($$ select in_month, in_q3, in_ytd from pfin.fn_cashflow_items(%L::date) where trans_id = %s $$, :'d_asof', :t_q3),
  $$ values (false, true, true) $$,
  '093 S3b: Month is truncated at its own start — a row one day earlier is in_q3/in_ytd but NOT in_month'
);

-- S3c — ΣQ1..Q4 = YTD partition identity over the 4-quarter Groceries fixture.
select is(
  (select sum(amount_net) filter (where in_q1 or in_q2 or in_q3 or in_q4)
     from pfin.fn_cashflow_items(:'d_asof'::date) where sub_cat_id = :a_groceries),
  (select sum(amount_net) filter (where in_ytd)
     from pfin.fn_cashflow_items(:'d_asof'::date) where sub_cat_id = :a_groceries),
  '093 S3c: the truncated quarters partition YTD exactly (ΣQ1..Q4 = YTD)'
);

-- X2 — owner reads a non-vacuous set of its own items (guards an
-- over-restrictive read, not just an over-permissive one).
select ok(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date)) >= 10,
  '093 X2: tenant A reads a non-vacuous set of its own items'
);

-- X1 — cross-tenant read fails closed: B sees NONE of A's items.
-- ⚠ role-restore FIRST: _rls.set_tenant sets role='authenticated' for the rest
-- of the transaction (set_config is_local=true, but no intervening COMMIT
-- happens); the _rls schema itself grants NO USAGE to authenticated, so a
-- SECOND _rls.set_tenant call while already 'authenticated' fails closed with
-- "permission denied for schema _rls" rather than switching tenants (the
-- leaked-role gotcha — every subsequent _rls.set_tenant call in this file
-- must be preceded by an explicit restore to postgres).
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where trans_id = :o1),
  0::bigint,
  '093 X1: cross-tenant read fails closed — B sees zero of A''s items (RLS-inherited, no tenant parameter to spoof)'
);

-- RU5 setup — capture B's (row-absent) and C's (explicit both-NULL row)
-- targets output for an exact equality comparison below.
select (pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'targets') as targets_b \gset
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select (pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'targets') as targets_c \gset

-- restore privileged role before the DDL-touching index section.
select set_config('role', 'postgres', true);

-- =====================================================================
-- PARTIAL-UNIQUE REVERSAL-DEDUP INDEX (8a promotion) — discovered
-- DYNAMICALLY by shape, never hardcoded by name (Architect's naming is
-- unknown at draft time).
-- =====================================================================
select indexname, indexdef
  from pg_indexes
 where schemaname = 'pfin' and tablename = 'account_trans'
   and indexdef ilike 'create unique index%'
   and indexdef ilike '%replaces_trans_id%'
   and indexdef ilike '%where%'
 order by indexname
 limit 1 \gset

select ok(
  :'indexname' is not null,
  '093 IDX1: a partial-unique index on pfin.account_trans covering replaces_trans_id exists (8a promotion)'
);

-- IDX2 — baseline: a SECOND reversal pointing at the same original (o1, which
-- already has r1) is refused.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id)
             values (%s, %L, %s, %L, %L, true, %s) $$,
    :accta, '2026-05-12'::date, 40, 'vDup', '093 IDX2 duplicate reversal attempt', :o1),
  '23505',
  null,
  '093 IDX2: a second reversal pointing at the same original is REFUSED by the DB (unique_violation)'
);

-- IDX3 — inversion: with the index dropped, the identical duplicate LANDS.
-- ⚠ psql does NOT interpolate `:'var'` inside a `do $$ ... $$` body (dollar-
-- quoted text is opaque to psql's colon-substitution, the same reason a `::`
-- cast or an array slice survives unmolested) — measured directly, reproduced
-- in isolation. Building the DROP as a plain SQL fragment via format() OUTSIDE
-- any dollar-quoting, captured with \gset, then executed as a bare (unquoted)
-- psql-variable statement sidesteps it entirely.
select format('drop index pfin.%I', :'indexname') as dropsql \gset

savepoint idx_inversion;

:dropsql;

select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id)
             values (%s, %L, %s, %L, %L, true, %s) $$,
    :accta, '2026-05-13'::date, 41, 'vDup2', '093 IDX3 inversion: duplicate reversal after index drop', :o1),
  '093 IDX3: with the reversal-dedup index dropped, the duplicate LANDS — proves the index (not some other fence) was the blocking mechanism'
);

-- IDX4 — restore via ROLLBACK TO SAVEPOINT (byte-identical restore of both the
-- index AND the pre-leak data state) and reconfirm the refusal.
rollback to savepoint idx_inversion;

select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, is_reverse, replaces_trans_id)
             values (%s, %L, %s, %L, %L, true, %s) $$,
    :accta, '2026-05-14'::date, 42, 'vDup3', '093 IDX4 restore check: duplicate reversal after ROLLBACK TO SAVEPOINT', :o1),
  '23505',
  null,
  '093 IDX4: after ROLLBACK TO SAVEPOINT restores the index, the duplicate reversal is REFUSED again'
);

-- =====================================================================
-- ROLLUP ASSERTIONS — pfin.fn_cashflow_cross_account_rollup. ⚠ ASSUMED
-- jsonb shape throughout (see the BINDS TO note at the top of this file);
-- re-verify every path against Architect's committed function.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- RU1a — exactly 2 sections.
select is(
  (select jsonb_array_length(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections')),
  2,
  '093 RU1a: the rollup has exactly 2 sections'
);

-- RU1b — the section labels are exactly {Revenue, Expense} (never Transfer/Trade/Equity).
select is(
  (select array_agg(s ->> 'cat' order by s ->> 'cat')
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s),
  array['Expense', 'Revenue'],
  '093 RU1b: section labels are exactly {Expense, Revenue} — Transfer/Trade/Equity never appear as a section'
);

-- RU2 — sign convention: the refund-heavy OfficeSupplies Sub-Cat (raw sum
-- +400, a real net CREDIT) displays as -400 under Expense''s outflow-positive
-- convention, never abs()''d to +400. Rows carry `sub_cat` (the NAME), not
-- sub_cat_id — matched against Architect's committed jsonb shape.
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where s ->> 'cat' = 'Expense' and row ->> 'sub_cat' = 'OfficeSupplies93'),
  -400::numeric,
  '093 RU2: a refund-heavy Expense Sub-Cat renders its REAL negative sign — never abs()''d positive'
);

-- RU3 — the Expense section''s Total row sums EVERY Expense Sub-Cat row DOWN
-- the ytd column (never abs()'d per row first). Compared against an
-- INDEPENDENT recomputation straight from the shared reader (never a
-- hand-tracked literal) — the fixture carries several OTHER Expense Sub-Cats
-- (Groceries, Split1/2, the netted Dining/Office pair) besides the two RU2
-- sign-convention rows, so the Total is the sum of ALL of them, not just
-- OfficeSupplies + Utilities.
select is(
  (select (s -> 'total' ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s
    where s ->> 'cat' = 'Expense'),
  (select -1 * sum(amount_net) from pfin.fn_cashflow_items(:'d_asof'::date)
    where cat = 'Expense' and sub_cat_id is not null and in_ytd),
  '093 RU3: the Expense Total sums its Sub-Cat rows'' real signed values (independently recomputed from the shared reader), never their absolute values'
);

-- RU-EQ — the Equity-classified, non-journaled, non-security item never
-- surfaces in either section (AC5 — Transfer/Trade/Equity excluded from
-- THIS surface). Matched by `sub_cat` name (rows carry no sub_cat_id key).
select is(
  (select count(*)
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'OwnerContribution93'),
  0::bigint,
  '093 RU-EQ: an Equity-classified item (which DOES pass the reader''s S-1 predicate) is excluded from both rollup sections'
);

-- RU6 — the unclassified.count_ytd banner comes from the SAME query as the
-- sums (AC8): independently recomputed from the shared reader, never
-- hand-tracked, since this fixture''s exact unclassified-item count is
-- incidental to several other legs.
select is(
  (select (pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'unclassified' ->> 'count_ytd')::bigint),
  (select count(*) from pfin.fn_cashflow_items(:'d_asof'::date) where sub_cat_id is null and in_ytd),
  '093 RU6: unclassified.count_ytd matches an independent recount of the reader''s own NULL-sub_cat_id in_ytd items (the sum/banner drift-proof identity)'
);

-- RU4 — targets: a partial-set tenant (income set, expense left unset) reads
-- income_target_annual verbatim and expense_target_monthly as NULL, never 0.
select results_eq(
  format($$ select (pfin.fn_cashflow_cross_account_rollup(%L::date) -> 'targets' ->> 'income_target_annual')::numeric,
                    (pfin.fn_cashflow_cross_account_rollup(%L::date) -> 'targets' ->> 'expense_target_monthly')::numeric $$,
    :'d_asof', :'d_asof'),
  $$ values (60000::numeric, null::numeric) $$,
  '093 RU4: a partial-set cashflow_target row reads its set column verbatim and its unset column as NULL'
);

-- RU5 — row-absent (B) and an explicit both-columns-NULL row (C) produce
-- IDENTICAL targets output (SELF-246 AC7/AC8 equivalence, encoded at 19a as
-- SELF-250 AC6).
select is(
  :'targets_b'::jsonb,
  :'targets_c'::jsonb,
  '093 RU5: a row-absent tenant (B) and an explicit both-NULL row (C) produce IDENTICAL targets output'
);

select * from finish();
rollback;
