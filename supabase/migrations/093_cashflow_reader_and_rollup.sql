-- ============================================================================
-- Migration: pfin.fn_cashflow_items + pfin.fn_cashflow_cross_account_rollup
--            + the account_trans reversal-uniqueness index.
-- Phase 6 Build Loop (SELF-250; PRD §2.3.2). V1.3's foundation piece: the ONE
-- extracted §2.3 reader ruled at the V1.3 pre-flight sitting item 9 (D-1 (iii),
-- the hybrid), plus the first surface that composes on it, plus the invariant
-- that ruling created (sitting item 8a).
--
-- Numbering: next free number at authoring time; the live tail was 092. Depends
-- on 004 (account_trans + created_at) · 017 (ingest; the un-annotated majority)
-- · 023 (account_trans_annotation) · 029 (account_trans_split) · 033
-- (journal_id on the annotation) · 035/037 (the GL reader whose rules these
-- mirror and which this migration does NOT touch) · 084 (the posting_prototype
-- re-target both sub_cat_id FKs now point at) · 090 (cashflow_target).
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
-- SECURITY DEFINER. Both functions are read-only compositions over relations
-- that already carry per-tenant RLS. Tenant isolation is INHERITED, never
-- asserted here: pfin.account_trans / account_trans_annotation /
-- account_trans_split gate on pfin.account_users.rd_access under auth.uid();
-- pfin.posting_prototype and pfin.cashflow_target gate on users_id = auth.uid().
-- A cross-tenant caller sees zero rows and fails closed. Neither function takes
-- a tenant parameter, so there is no tenant argument to forge. The SECURITY
-- DEFINER allowlist (ADR-011 Decision 9) is UNCHANGED by this migration.
--
-- LEDGERS. §10 catalogued-instance ledger UNCHANGED — ADR-011 Decision 4 read
-- verbatim and live before drafting, 2026-08-26; three axes clean (no
-- catalogued instance added, removed, reordered or renumbered; no layer
-- re-attributed; no surface becomes "four-layer"). Path B — Decision 4 is
-- linked, not restated, and no count is carried here. ⚠ The §10 CATALOGUED set
-- and the CI-FENCED set are different sets and are not reconciled here.
-- ADR-011 Decision 3 cross-tenant FK-bypass family UNCHANGED — this migration
-- creates, alters and drops no column, so no FK-shaped reference joins the
-- family and no matched-tenant validation is owed.
--
-- SEC JOINT-REVIEW — MANDATORY, on two independent triggers.
--   (i)  fn_cashflow_items is THE money path for every PRD §2.3 surface
--        (financial calculation + multi-tenant read composition).
--   (ii) the index in Part C changes a pfin.account_trans WRITE surface. It
--        makes a previously-accepted INSERT fail. ADR-064 Decision 5 states the
--        trigger is the surface, not the layer, and not the author's assessment
--        of risk — so this is routed as D5-reviewable rather than as "an index".
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--
--   pfin.fn_cashflow_items(p_as_of date)
--     -> TABLE(item_kind, item_id, trans_id, account_id, transaction_date,
--              sub_cat_id, cat, sub_cat, amount_net,
--              in_month, in_q1, in_q2, in_q3, in_q4, in_ytd)
--
--   Item-grain rows over the classifiable() set — classified AND unclassified
--   alike. Mechanically-excluded rows never appear; unclassified items appear
--   with NULL sub_cat_id and NULL cat.
--
--   ⚠ THE ROW SET IS THE UNION OF WHAT §2.3 SUMS AND WHAT THE S-2 BANNER
--   COUNTS, deliberately. Each surface derives both figures from ONE query:
--   sum where sub_cat_id is not null; count where sub_cat_id is null. Two
--   counts of "how much is missing" cannot drift if there is only one query.
--   A consumer that re-derives either figure from a second query forfeits the
--   only property this extraction exists to deliver.
--
--   pfin.fn_cashflow_cross_account_rollup(p_as_of date) -> jsonb
--
--   SHAPING ONLY. It composes on fn_cashflow_items and restates NONE of the six
--   reader rules. ⚠ A reader rule appearing in this function too IS the drift
--   defect the extraction exists to prevent — that is the standing requirement
--   on anyone editing either body.
--
-- ----------------------------------------------------------------------------
-- NAME DECISION (the provisional handle is fixed HERE, per the SELF-250 AC).
-- `pfin.fn_cashflow_items` was coined as a working handle at the sitting and
-- explicitly NOT ratified. It is ADOPTED, on three grounds: it names the DOMAIN
-- (cashflow — the same word as pfin.cashflow_target and the §2.3 section
-- vocabulary), it names the GRAIN (items — the S-5 "whole-item" word, which the
-- item_kind column then discriminates), and fn_<domain>_<plural-noun> is the
-- shape of pfin.fn_gl_entries, the repo's OTHER reader over pfin.account_trans.
-- The two names being parallel is informative, not coincidental.
-- Rejected: fn_cashflow_classifiable_items — accurate but it reads as excluding
-- unclassified items, which is exactly backwards, and a predicate belongs in
-- the comment rather than in the name.
--
-- ----------------------------------------------------------------------------
-- ⚠ NAMED RESIDUAL — the reader CANNOT see a reversal of a SPLIT PARENT, and
-- its only fence is app-layer. Rule 2 emits the children; rule 1 excludes the
-- reversal row itself; rule 3's netting term attaches at the TRANSACTION grain,
-- so a split parent's reversal has no emitted item to net against and vanishes
-- from §2.3 entirely. Apportioning it pro-rata across the children was
-- considered and rejected at the sitting (it invents an apportionment the user
-- never authored), and emitting the parent as a netting item re-introduces the
-- double-count rule 2 prevents. What holds the line today is the write-path
-- refusal of reversing a split parent. This function does not check it and does
-- not promise it. Recorded so a reader does not conclude the case is handled.
-- ============================================================================

create schema if not exists pfin;

-- ============================================================================
-- PART A — the shared §2.3 reader.
-- ============================================================================

create or replace function pfin.fn_cashflow_items(p_as_of date)
returns table (
  item_kind        text,
  item_id          bigint,
  trans_id         bigint,
  account_id       bigint,
  transaction_date date,
  sub_cat_id       bigint,
  cat              text,
  sub_cat          text,
  amount_net       numeric(20,4),
  in_month         boolean,
  in_q1            boolean,
  in_q2            boolean,
  in_q3            boolean,
  in_q4            boolean,
  in_ytd           boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select
      p_as_of                                           as d,
      date_trunc('month', p_as_of)::date                as month_start,
      make_date(extract(year from p_as_of)::int,  1,  1) as year_start,
      make_date(extract(year from p_as_of)::int,  3, 31) as q1_end,
      make_date(extract(year from p_as_of)::int,  4,  1) as q2_start,
      make_date(extract(year from p_as_of)::int,  6, 30) as q2_end,
      make_date(extract(year from p_as_of)::int,  7,  1) as q3_start,
      make_date(extract(year from p_as_of)::int,  9, 30) as q3_end,
      make_date(extract(year from p_as_of)::int, 10,  1) as q4_start,
      make_date(extract(year from p_as_of)::int, 12, 31) as q4_end
  ),

  -- RULE 6 — Lock 15 dual-column as-of, HALF-OPEN upper bound. ADR-011
  -- Decision 19 as amended 2026-08-22 states the filter verbatim as:
  --   `transaction_date <= $1 AND created_at < ($1 + 1)`
  -- created_at is timestamptz and $1 is a date, so a `created_at <= $1` form
  -- promotes the date to midnight in the session TimeZone and excludes every
  -- row created ON the as-of date. The half-open bound is also sargable, which
  -- a created_at::date cast would not be. Applied HERE, once, on the base scan.
  --
  -- RULE 4 — E3: LEFT JOIN to the annotation. An inner join silently drops
  -- every row with no annotation at all, which per 017 is most of an ingested
  -- book (all ingested txns land Unsorted).
  txn as (
    select
      t.trans_id,
      t.account_id,
      t.transaction_date,
      t.amount,
      t.is_reverse,
      t.transaction_type,
      t.security_id,
      (a.trans_id is not null) as has_annotation,
      a.sub_cat_id             as ann_sub_cat_id,
      a.journal_id             as ann_journal_id,
      -- split_count is DERIVED by count and NEVER stored (the house precedent;
      -- a stored counter is a second source of truth for a fact the child rows
      -- already carry).
      (select count(*)
         from pfin.account_trans_split s
        where s.account_trans_id = t.trans_id) as split_count
    from pfin.account_trans t
    left join pfin.account_trans_annotation a on a.trans_id = t.trans_id
    cross join bounds b
    where t.transaction_date <= b.d
      and t.created_at < (b.d + 1)
  ),

  -- RULE 3 — E1 netting (sitting item 8, ruling (a)). amount_net = amount +
  -- Σ(amount of rows where replaces_trans_id = this trans_id and is_reverse).
  -- A fully-reversed original nets to 0 and stays INSIDE its own Sub-Cat,
  -- invariant under later reclassification.
  -- ⚠ Rule 6 is applied to the netting rows TOO, and that is load-bearing:
  -- a reversal back-dates its transaction_date from the original, so
  -- created_at is the ONLY column that distinguishes "reversed by the as-of
  -- date" from "reversed afterwards". Without it, an edit made after D would
  -- silently restate the history read at D.
  netting as (
    select
      r.replaces_trans_id as orig_trans_id,
      sum(r.amount)       as reversal_sum
    from pfin.account_trans r
    cross join bounds b
    where r.is_reverse
      and r.replaces_trans_id is not null
      and r.transaction_date <= b.d
      and r.created_at < (b.d + 1)
    group by r.replaces_trans_id
  ),

  -- RULE 1 — the S-1 predicate (sitting item 3a), at the TRANSACTION grain.
  -- Stated in the ruled two-branch form rather than collapsed to
  -- `ann_journal_id is null`: under the LEFT JOIN the two branches are
  -- equivalent, and writing the collapsed form would hide which of the two
  -- conditions a future edit is changing.
  -- ⚠ is_reverse = false is part of the predicate: reversal rows NEVER appear
  -- as items (E1(a) — they are excluded from the queue and netted structurally
  -- by rule 3 instead).
  classifiable_txn as (
    select t.*
    from txn t
    where t.transaction_type = 'standard'
      and t.security_id is null
      and t.split_count = 0
      and t.is_reverse = false
      and (t.has_annotation = false or t.ann_journal_id is null)
  ),

  -- RULE 2 — split XOR, parent half. Same predicate MINUS the split_count
  -- clause, because split_count > 0 is what selects this branch. These parents
  -- are NEVER emitted; only their children are.
  split_parent as (
    select t.*
    from txn t
    where t.transaction_type = 'standard'
      and t.security_id is null
      and t.split_count > 0
      and t.is_reverse = false
      and (t.has_annotation = false or t.ann_journal_id is null)
  ),

  -- RULE 2 — the emission. split_count > 0 -> the children; else the parent.
  -- Never both: the two branches are disjoint on split_count by construction,
  -- not by a filter that could be edited apart.
  items as (
    select
      'transaction'::text                                   as item_kind,
      c.trans_id                                            as item_id,
      c.trans_id,
      c.account_id,
      c.transaction_date,
      c.ann_sub_cat_id                                      as sub_cat_id,
      (c.amount + coalesce(n.reversal_sum, 0))::numeric(20,4) as amount_net
    from classifiable_txn c
    left join netting n on n.orig_trans_id = c.trans_id

    union all

    select
      'split_child'::text,
      s.id,
      sp.trans_id,
      sp.account_id,
      sp.transaction_date,
      s.sub_cat_id,
      s.amount::numeric(20,4)
    from split_parent sp
    join pfin.account_trans_split s on s.account_trans_id = sp.trans_id
  )

  -- RULE 5 — the S-3 period grammar, computed ONCE, here. Every window is
  -- inclusive and truncated at D: Month = date_trunc('month', D) -> D (a
  -- PARTIAL month, not the whole calendar month); Qk = start(k) ->
  -- least(end(k), D); YTD = Jan 1 of year(D) -> D. The truncated quarters
  -- partition YTD exactly, so ΣQ1..Q4 = YTD. The columns are NOT disjoint
  -- (Month ⊆ its quarter ⊆ YTD), so a Total sums DOWN a column and never
  -- across.
  --
  -- ⚠ The posting_prototype join is LEFT, and for the same reason rule 4 is:
  -- an inner join would drop every UNCLASSIFIED item and silently zero the
  -- S-2 banner on every surface. Unclassified items are the point of the
  -- row set, not an edge case.
  select
    i.item_kind,
    i.item_id,
    i.trans_id,
    i.account_id,
    i.transaction_date,
    i.sub_cat_id,
    pp.cat,
    pp.sub_cat,
    i.amount_net,
    (i.transaction_date >= b.month_start and i.transaction_date <= b.d)                as in_month,
    (i.transaction_date >= b.year_start  and i.transaction_date <= least(b.q1_end, b.d)) as in_q1,
    (i.transaction_date >= b.q2_start    and i.transaction_date <= least(b.q2_end, b.d)) as in_q2,
    (i.transaction_date >= b.q3_start    and i.transaction_date <= least(b.q3_end, b.d)) as in_q3,
    (i.transaction_date >= b.q4_start    and i.transaction_date <= least(b.q4_end, b.d)) as in_q4,
    (i.transaction_date >= b.year_start  and i.transaction_date <= b.d)                 as in_ytd
  from items i
  cross join bounds b
  left join pfin.posting_prototype pp on pp.id = i.sub_cat_id
$$;

revoke execute on function pfin.fn_cashflow_items(date) from public;
grant  execute on function pfin.fn_cashflow_items(date) to authenticated;

comment on function pfin.fn_cashflow_items(date) is
  'THE shared PRD §2.3 cash-flow reader (SELF-250; ruled at the V1.3 pre-flight '
  'sitting as D-1 (iii)). Emits ITEM-GRAIN rows — one per item in the '
  'classifiable set, CLASSIFIED AND UNCLASSIFIED ALIKE — over pfin.account_trans '
  'as of p_as_of. item_kind names the grain in the data: ''transaction'' for an '
  'unsplit transaction, ''split_child'' for one pfin.account_trans_split row. '
  'SECURITY INVOKER + STABLE + set search_path = ''''; NO tenant and NO scope '
  'parameter — isolation is INHERITED from the RLS on every relation read, under '
  'the caller''s own session, and a cross-tenant caller gets zero rows. A NULL '
  'p_as_of returns zero rows (every comparison is NULL): it fails closed. '
  'STANDING REQUIREMENT: the six reader rules — the S-1 classifiability '
  'predicate, the split XOR, the E1 reversal netting, the E3 LEFT JOIN to the '
  'annotation, the S-3 period grammar, and the Lock 15 dual-column as-of filter '
  '— are housed in THIS function and MUST NOT be restated in any consumer; a '
  'consumer that restates one has re-created the drift this extraction exists to '
  'prevent. ⚠ THE ROW SET IS THE UNION OF WHAT §2.3 SUMS AND WHAT THE '
  'unclassified-items banner COUNTS: sum where sub_cat_id IS NOT NULL, count '
  'where sub_cat_id IS NULL, from ONE query. sub_cat_id IS NULL is the '
  'UNCLASSIFIED key and cat/sub_cat are NULL with it — match it by IS NULL, '
  'never by equality, and never inner-join it away. amount_net is SIGNED and NET '
  'OF REVERSALS: it is the item amount plus the sum of the amounts of the '
  'is_reverse rows pointing at that transaction, so a fully-reversed original '
  'nets to 0 INSIDE its own Sub-Cat and stays there after any later '
  'reclassification. ⚠ The netting term attaches at the TRANSACTION grain only; '
  'a reversal of a SPLIT PARENT has no emitted item to net against and is '
  'invisible here — what prevents that state is the write-path refusal of '
  'reversing a split parent, which this function neither checks nor promises. ⚠ '
  'is_reverse rows are NEVER emitted as items. ⚠ The as-of filter is DUAL-COLUMN '
  'and its upper bound is HALF-OPEN (ADR-011 Decision 19 as amended 2026-08-22): '
  'transaction_date <= p_as_of AND created_at < (p_as_of + 1). The half-open '
  'form is required because created_at is timestamptz and p_as_of is a date, so '
  'a <= comparison promotes the date to midnight and drops every row created ON '
  'the as-of day; it is applied to the reversal rows too, so a correction made '
  'after p_as_of does not restate the history read at p_as_of. The period flags '
  'are NOT disjoint (Month is inside its quarter, which is inside YTD), so a '
  'total sums DOWN one flag''s column and NEVER across flags; the truncated '
  'quarters partition YTD exactly. Rows dated before Jan 1 of year(p_as_of) ARE '
  'emitted, with every flag false — the 5-year §2.3.4 window consumes them. '
  'Reads only: no write path, no new FK-shaped column, no SECURITY DEFINER '
  'entry, no service_role grant. pfin.fn_gl_entries is a SEPARATE reader over '
  'the same ledger and is deliberately untouched; the two agree only because the '
  'same rules were written into both, and on reversals they disagree ON PURPOSE '
  '(this function nets the pair inside the original''s Sub-Cat; the GL posts the '
  'reversal''s contra to Suspense) — see the BACKLOG close-out booking.';

-- ============================================================================
-- PART B — the §2.3.2 cross-account rollup. SHAPING ONLY.
-- ============================================================================

create or replace function pfin.fn_cashflow_cross_account_rollup(p_as_of date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with bounds as (
    select
      p_as_of                                            as d,
      make_date(extract(year from p_as_of)::int,  1, 1)  as q1_start,
      make_date(extract(year from p_as_of)::int,  4, 1)  as q2_start,
      make_date(extract(year from p_as_of)::int,  7, 1)  as q3_start,
      make_date(extract(year from p_as_of)::int, 10, 1)  as q4_start
  ),

  -- The em-dash rule, two-sided (sitting item 5a): a quarter that has NOT
  -- STARTED relative to D renders as an em-dash and must arrive as NULL; a
  -- quarter that HAS started with no rows in it renders $0 and must arrive as
  -- 0, never collapsed together by a coalesce. "Has the quarter started" is not
  -- a property of any item, so it cannot come from the reader's flags — it is
  -- derived here from p_as_of alone. That is arithmetic on this function's own
  -- parameter, NOT a restatement of reader rule 5. The QA ΣQ1..Q4 = YTD leg is
  -- the watcher that catches these two ever disagreeing.
  started as (
    select
      (b.q1_start <= b.d) as q1,
      (b.q2_start <= b.d) as q2,
      (b.q3_start <= b.d) as q3,
      (b.q4_start <= b.d) as q4
    from bounds b
  ),

  -- The section list is EXACTLY these two, and they are `cat` VALUES from the
  -- ratified 5-class posting vocabulary — not product labels. Transfer, Trade
  -- and Equity are excluded from THIS surface. Rendering "Income"/"Expenses" is
  -- an APP-side mapping over these values and is deliberately absent here.
  -- `sign` is the section's normalization multiplier: Revenue is already
  -- inflow-positive in pfin.account_trans, Expense is outflow-NEGATIVE, so the
  -- Expense section is negated ONCE, at the section, to render outflow-positive.
  sections(cat, sign, ord) as (
    values ('Revenue'::text, 1::numeric, 1), ('Expense'::text, -1::numeric, 2)
  ),

  items as (
    select * from pfin.fn_cashflow_items(p_as_of)
  ),

  -- Sub-Cat rows: group (cat, sub_cat), sum amount_net per period flag.
  sub_cat_raw as (
    select
      i.cat,
      i.sub_cat,
      sum(i.amount_net) filter (where i.in_month) as m,
      sum(i.amount_net) filter (where i.in_q1)    as q1,
      sum(i.amount_net) filter (where i.in_q2)    as q2,
      sum(i.amount_net) filter (where i.in_q3)    as q3,
      sum(i.amount_net) filter (where i.in_q4)    as q4,
      sum(i.amount_net) filter (where i.in_ytd)   as ytd
    from items i
    -- in_ytd is the UNION of every period flag this surface renders (month and
    -- each quarter are subsets of it by rule 5's construction), so this
    -- conjunct changes no displayed figure. What it removes is a Sub-Cat whose
    -- only items fall OUTSIDE the rendered year — the reader emits those for
    -- the §2.3.4 five-year window — which would otherwise appear here as a row
    -- of zeros in every column. A zero in a period is a real answer; a Sub-Cat
    -- with no activity in the year at all is not one of this surface's rows.
    where i.sub_cat_id is not null
      and i.in_ytd
    group by i.cat, i.sub_cat
  ),

  -- ⚠ SIGN CONVENTION — the multiplier is applied per SECTION, never abs() per
  -- row. abs() would silently flip a genuinely negative bucket to positive; a
  -- refund-heavy Expense Sub-Cat and a contra-revenue month are both reachable,
  -- and both must render with their real sign. Reachable states, stated the way
  -- ADR-061 Decision 3 does:
  --   Revenue, net inflow      -> POSITIVE   (the ordinary case)
  --   Revenue, net contra      -> NEGATIVE   (refunds/chargebacks exceed receipts)
  --   Expense, net outflow     -> POSITIVE   (the ordinary case)
  --   Expense, net refund      -> NEGATIVE   (returns exceed spending in the window)
  --   any bucket, exactly zero -> 0          (a real answer; e.g. fully reversed)
  --   quarter not yet started  -> NULL       (renders em-dash, never $0)
  -- A consumer that cannot render a negative figure hides exactly the case this
  -- function exists to surface.
  sub_cat_rows as (
    select
      s.ord,
      s.cat,
      r.sub_cat,
      (s.sign * coalesce(r.m,   0))                                      as v_month,
      case when st.q1 then (s.sign * coalesce(r.q1,  0)) else null end   as v_q1,
      case when st.q2 then (s.sign * coalesce(r.q2,  0)) else null end   as v_q2,
      case when st.q3 then (s.sign * coalesce(r.q3,  0)) else null end   as v_q3,
      case when st.q4 then (s.sign * coalesce(r.q4,  0)) else null end   as v_q4,
      (s.sign * coalesce(r.ytd, 0))                                      as v_ytd
    from sections s
    join sub_cat_raw r on r.cat = s.cat
    cross join started st
  ),

  -- The per-section Total sums each period column INDEPENDENTLY — down the
  -- column, never across the row, because the period columns overlap.
  section_totals as (
    select
      s.ord,
      s.cat,
      coalesce(sum(sr.v_month), 0)                                  as t_month,
      case when st.q1 then coalesce(sum(sr.v_q1),  0) else null end as t_q1,
      case when st.q2 then coalesce(sum(sr.v_q2),  0) else null end as t_q2,
      case when st.q3 then coalesce(sum(sr.v_q3),  0) else null end as t_q3,
      case when st.q4 then coalesce(sum(sr.v_q4),  0) else null end as t_q4,
      coalesce(sum(sr.v_ytd), 0)                                    as t_ytd
    from sections s
    cross join started st
    left join sub_cat_rows sr on sr.cat = s.cat
    group by s.ord, s.cat, st.q1, st.q2, st.q3, st.q4
  ),

  -- ⚠ TARGETS — row-absent and all-columns-NULL are IDENTICAL to the caller,
  -- BY CONSTRUCTION rather than by care. Both are reachable (never-opened-the-
  -- editor vs set-then-cleared) under the always-NULL-never-DELETE ruling, and
  -- they arrive from the driver as different result shapes — zero rows vs one
  -- row of NULLs. A scalar subquery over zero rows yields NULL, so both states
  -- produce the SAME two-key object with both values null. There is no shape a
  -- caller could branch on, which is the point: a handler anticipating only one
  -- cannot diverge. pfin.cashflow_target is UNIQUE (users_id) and RLS-scoped to
  -- auth.uid(), so at most one row is ever visible.
  targets as (
    select
      (select ct.income_target_annual   from pfin.cashflow_target ct) as income_target_annual,
      (select ct.expense_target_monthly from pfin.cashflow_target ct) as expense_target_monthly
  ),

  -- The unclassified count, from the SAME query as the sums — that identity is
  -- why the reader emits unclassified items rather than filtering them out.
  -- Scoped to the rendered year (in_ytd), matching what this surface renders.
  unclassified as (
    select count(*)::bigint as count_ytd
    from items i
    where i.sub_cat_id is null and i.in_ytd
  )

  select jsonb_build_object(
    'as_of', to_jsonb(p_as_of),
    'sections', (
      select coalesce(jsonb_agg(sec order by sec_ord), '[]'::jsonb)
      from (
        select
          t.ord as sec_ord,
          jsonb_build_object(
            'cat', t.cat,
            'rows', coalesce((
              select jsonb_agg(
                       jsonb_build_object(
                         'sub_cat', sr.sub_cat,
                         'month',   sr.v_month,
                         'q1',      sr.v_q1,
                         'q2',      sr.v_q2,
                         'q3',      sr.v_q3,
                         'q4',      sr.v_q4,
                         'ytd',     sr.v_ytd
                       ) order by sr.sub_cat
                     )
              from sub_cat_rows sr
              where sr.cat = t.cat
            ), '[]'::jsonb),
            'total', jsonb_build_object(
              'month', t.t_month,
              'q1',    t.t_q1,
              'q2',    t.t_q2,
              'q3',    t.t_q3,
              'q4',    t.t_q4,
              'ytd',   t.t_ytd
            )
          ) as sec
        from section_totals t
      ) z
    ),
    'targets', (
      select jsonb_build_object(
        'income_target_annual',   tg.income_target_annual,
        'expense_target_monthly', tg.expense_target_monthly
      )
      from targets tg
    ),
    'unclassified', (
      select jsonb_build_object('count_ytd', u.count_ytd) from unclassified u
    )
  )
$$;

revoke execute on function pfin.fn_cashflow_cross_account_rollup(date) from public;
grant  execute on function pfin.fn_cashflow_cross_account_rollup(date) to authenticated;

comment on function pfin.fn_cashflow_cross_account_rollup(date) is
  'PRD §2.3.2 cross-account multi-period cash-flow rollup (SELF-250). Composes '
  'on pfin.fn_cashflow_items(p_as_of) and adds SHAPING ONLY — it restates NONE '
  'of the six reader rules, and a reader rule appearing here IS the drift defect '
  'the shared reader exists to prevent. SECURITY INVOKER + STABLE + set '
  'search_path = ''''; NO tenant and NO scope parameter (isolation is inherited '
  'through the reader); the year is derived from p_as_of and is NOT a separate '
  'parameter, because two parameters that can contradict about the same fact '
  'generate defects. Returns one jsonb document: as_of, sections, targets, '
  'unclassified. sections is ALWAYS exactly two entries, cat = ''Revenue'' then '
  '''Expense'', present even when empty; these are `cat` VALUES from the '
  'ratified 5-class posting vocabulary, NOT product labels — mapping them to '
  'user-facing captions is an APP-side concern and is deliberately not done '
  'here. Transfer, Trade and Equity are excluded from this surface. Each section '
  'carries per-(cat, sub_cat) rows and a total. ⚠ SIGN: each section is '
  'normalized by ONE multiplier applied to the whole section (Revenue as-is, '
  'Expense negated) so both render inflow/outflow-positive in the ordinary case '
  '— NEVER abs() per row. A genuinely negative bucket KEEPS ITS REAL SIGN: a '
  'refund-heavy Expense Sub-Cat and a contra-revenue period are both reachable '
  'and both arrive negative, and a consumer unable to render a negative figure '
  'hides exactly the case this function surfaces. ⚠ The period columns OVERLAP '
  '(month is inside its quarter, which is inside YTD), so every total sums DOWN '
  'one column and never across. ⚠ A quarter that has NOT STARTED relative to '
  'p_as_of arrives as JSON null (render an em-dash); a quarter that HAS started '
  'with no rows arrives as 0 (a real answer). These two MUST NOT be collapsed. ⚠ '
  'targets: row-absent and all-columns-NULL are INDISTINGUISHABLE by '
  'construction — both are reachable states of "no targets set" under the '
  'always-NULL-never-DELETE ruling, and both produce the same two-key object '
  'with null values, so there is no result shape for a caller to branch on. '
  'unclassified.count_ytd counts items with NULL sub_cat_id in the rendered '
  'year, FROM THE SAME QUERY as the sums — the banner and the totals cannot '
  'drift because there is only one query. There is no skip_flag and no '
  'reconciled_flag: neither column exists and both were ruled unbuildable on the '
  'immutable ledger (ADR-032); a section''s exclusions are expressed by its '
  'class set. Reads only: no write path, no new FK-shaped column, no SECURITY '
  'DEFINER entry, no service_role grant.';

-- ============================================================================
-- PART C — the reversal-uniqueness index.
--
-- Ruled at the V1.3 pre-flight sitting item 8a: PROMOTED from a code comment to
-- a migration, in the same wave as the §2.3 readers. Under E1(a)'s structural
-- netting, two is_reverse rows pointing at one original DOUBLE-NET the §2.3
-- figure — so what was edit hygiene at api/src/lib/server/queries/transactions.ts
-- (the double-edit guard, which that file's own comment describes as
-- "not a hard DB constraint — TOCTOU-narrow, single-user; a partial-unique
-- index on replaces_trans_id would harden it") is now a MONEY INVARIANT.
-- Double-reversal becomes a database refusal.
--
-- ⚠ THIS IS A pfin.account_trans WRITE-SURFACE CHANGE. It causes a
-- previously-accepted INSERT to fail. ADR-064 Decision 5 makes any such change
-- Sec-joint-review-mandatory, on the surface rather than on the layer, and the
-- fact that the vehicle is an index does not move it out of that class.
--
-- PRE-FLIGHT MEASUREMENT (required before adding a uniqueness constraint to a
-- populated table). Live local stack, container supabase_db_mosko-fintech,
-- database postgres, read-only SELECT as postgres, 2026-08-26:
--   select count(*) from (
--     select replaces_trans_id from pfin.account_trans
--      where is_reverse and replaces_trans_id is not null
--      group by 1 having count(*) > 1) t;          -> 0   (zero violating groups)
--   is_reverse rows = 6, of which 0 carry a NULL replaces_trans_id;
--   pfin.account_trans total rows = 28.
-- Zero violations, so the index is admissible on existing data.
--
-- The predicate is `where is_reverse` verbatim per the ruling. An is_reverse row
-- with a NULL replaces_trans_id is included in the index and cannot conflict,
-- because a unique index treats NULLs as distinct; adding
-- `and replaces_trans_id is not null` would build a smaller index with
-- identical semantics and is deliberately not done, so that the shipped shape
-- matches the ruled shape byte for byte.
--
-- ⚠ WHAT THIS DOES NOT COVER, so nobody reads it as the whole answer: it fences
-- a SECOND reversal of one original. It does not fence reversing a leg of an
-- already-closed balanced journal, and it does not fence reversing a split
-- parent — both remain app-layer refusals. This index is necessary for the E1
-- netting invariant and is not sufficient for it.
-- ============================================================================

create unique index if not exists account_trans_reversal_unique_idx
  on pfin.account_trans (replaces_trans_id)
  where is_reverse;

comment on index pfin.account_trans_reversal_unique_idx is
  'At most ONE is_reverse row may point at any given original transaction '
  '(SELF-250; ruled at the V1.3 pre-flight sitting item 8a). This is a MONEY '
  'invariant, not edit hygiene: PRD §2.3 nets a reversal structurally into its '
  'original''s Sub-Cat through replaces_trans_id, so a second reversal of one '
  'original would double-net that Sub-Cat''s total. It hardens the app-layer '
  'double-edit guard in api/src/lib/server/queries/transactions.ts, which is '
  'TOCTOU-narrow, into a database refusal. NULLs are distinct in a unique index, '
  'so an is_reverse row carrying no replaces_trans_id is unconstrained here. ⚠ '
  'NECESSARY, NOT SUFFICIENT: reversing a split parent and reversing a leg of an '
  'already-closed balanced journal are separate hazards fenced only at the app '
  'layer.';
