-- ============================================================================
-- Migration: pfin.fn_cashflow_per_account — the PRD §2.3.3 per-account
--            cash-flow drill-down.
-- Phase 6 Build Loop (SELF-253; PRD §2.3.3). The SECOND surface to compose on
-- the ONE extracted §2.3 reader, and the first to PARTITION the posting
-- vocabulary into more sections than there are classes.
--
-- Numbering: next free number at authoring time; the live tail was 093. Depends
-- on 093 (pfin.fn_cashflow_items — THE reader this function composes on, and the
-- sole home of the six reader rules) · 003 (pfin.account.account_id, the bigint
-- this function's first parameter is) · 084 (the posting_prototype the reader
-- resolves cat/sub_cat through) · 091 (the Equity/Contribution +
-- Equity/Distribution seed rows, without which this function's middle section
-- would have no reachable Equity content at all).
--
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
-- SECURITY DEFINER. This function reads exactly one relation: the SECURITY
-- INVOKER reader pfin.fn_cashflow_items, under the caller's own session. Tenant
-- isolation is INHERITED, never asserted here — the reader's own composition
-- gates pfin.account_trans / account_trans_annotation / account_trans_split on
-- pfin.account_users.rd_access under auth.uid(). This function takes NO tenant
-- parameter, so there is no tenant argument to forge. ⚠ SECURITY DEFINER here
-- would be a defect, not a convenience: it would sever the account filter below
-- from the RLS that makes it safe, and turn p_account_id from a filter into an
-- unfenced tenant selector. The SECURITY DEFINER allowlist (ADR-011 Decision 9,
-- read live before drafting) is UNCHANGED by this migration.
--
-- LEDGERS. §10 catalogued-instance ledger UNCHANGED — ADR-011 Decision 4 read
-- verbatim and live before drafting, 2026-08-28; three axes clean (no
-- catalogued instance added, removed, reordered or renumbered; no layer
-- re-attributed; no surface becomes "four-layer"). Path B — Decision 4 is
-- linked, not restated, and no count is carried here. ⚠ The §10 CATALOGUED set
-- and the CI-FENCED set are different sets and are not reconciled here.
-- ADR-011 Decision 3 cross-tenant FK-bypass family UNCHANGED — this migration
-- creates, alters and drops no column, so no FK-shaped reference joins the
-- family and no matched-tenant validation is owed. ⚠ p_account_id is
-- FK-SHAPED-LOOKING and is NOT an instance: Decision 3 membership turns on a
-- stored column that outlives its write, not on a function parameter evaluated
-- inside one RLS-scoped read. Recorded because the resemblance invites the
-- opposite reading.
--
-- SEC JOINT-REVIEW — MANDATORY, on two independent triggers (SELF-253 Sec gate).
--   (i)  financial calculation on the §2.3 money path.
--   (ii) a CLIENT-SUPPLIED DATE parameter on a multi-tenant read — RT-25,
--        Lock 15's parameter-bypass adversarial-input surface. ⚠ PRD §2.3.3 is
--        the ONE V1 story carrying a user-facing as-of toggle (ADR-011 Decision
--        19 Amendment Edit 2), so this function is where that toggle lands.
--        The range validation ([floor, D], no future dates) is APP-LAYER and is
--        NOT re-implemented here — see the CONTRACT note on p_as_of.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--
--   pfin.fn_cashflow_per_account(p_account_id bigint, p_as_of date) -> jsonb
--
--   SHAPING ONLY. It composes on pfin.fn_cashflow_items(p_as_of) and restates
--   NONE of the six reader rules. ⚠ A reader rule appearing in this function IS
--   the drift defect the shared-reader extraction exists to prevent — that is
--   the standing requirement on anyone editing this body. In particular the
--   as-of semantics are the reader's rule 6 (dual-column, half-open) and this
--   function contains NO date predicate of its own; the arithmetic on p_as_of
--   below derives quarter STARTS for the em-dash rule, which is a property of
--   the parameter and not of any item.
--
--   SIGNATURE.
--     p_account_id bigint — pfin.account.account_id (003). NOT uuid.
--     p_as_of      date   — threaded by the app. NO DEFAULT: ADR-044's
--                           zero-round-trip in-function CURRENT_DATE variant is
--                           ruled out, and a default would let a caller omit the
--                           parameter the whole Lock 15 validation battery
--                           exists to check.
--   p_users_id, p_scope and p_year are absent by ruling, not by omission:
--   tenancy rides RLS, pfin.scope is not a type and does not exist, and the year
--   is year(p_as_of) — two parameters that can contradict about one fact
--   generate defects.
--
--   RETURNS one jsonb document: as_of · account_id · sections · unclassified.
--   ⚠ NO `targets` key (SELF-253 AC7): targets are §2.3.2 AGGREGATE concepts and
--   do not attach to a single-account scope. Its absence is the contract, not an
--   oversight, and a consumer must not synthesise one.
--
-- ----------------------------------------------------------------------------
-- THE THREE SECTIONS, AND WHY THE DISCRIMINATOR IS A SECTION KEY RATHER THAN A
-- `cat` VALUE — the one structural difference from 093, stated so it is not
-- read as drift.
--
-- 093 emits RAW `cat` values as its section discriminator and lets the app map
-- them to product copy, because there its sections are 1:1 with classes
-- (Revenue, Expense). §2.3.3's middle section is NOT 1:1: D-2 (B) rules its
-- content as the Transfer ∪ Equity UNION, so there is no `cat` value that names
-- it. The union has to be formed WHERE THE PER-SECTION TOTAL IS COMPUTED — a
-- section's Total foot row and its sign multiplier are properties of the
-- SECTION, and computing them app-side would move a money figure out of the one
-- place §2.3 derives money.
--
-- So this function emits `section_key` — the app-side GROUPING IDENTITY already
-- declared as `CashflowSectionKey` in the shared section-map module
-- api/src/lib/server/queries/cashflowSections.ts ('income' | 'other_cash_flows'
-- | 'expenses'). ⚠ The section LABELS ("Income", "Other Cash Flows",
-- "Expenses") appear NOWHERE in this file and must not: that copy layer is
-- CASHFLOW_SECTION_LABELS and stays app-side, exactly as SELF-250 AC5 requires.
-- The vocabulary therefore still has ONE home and this file opens no second one
-- — it mirrors the module's KEY vocabulary, not its COPY.
--
-- ⚠ "Other Cash Flows" is a section NAME, not a Cat. `OtherCF` is not a
-- posting-vocabulary value, has no successor value, and no row anywhere carries
-- it.
--
-- ⚠ `Trade` appears in NO section — excluded by the D-2 ruling across every
-- §2.3 surface, not merely unmapped by omission. A `Trade`-classified item read
-- by this function joins no section and is silently absent from the sums; that
-- is the ruled behaviour. (It is also mostly unreachable upstream: the reader's
-- rule 1 excludes security-bearing rows.)
--
-- THE EMITTED `cats` ARRAY IS A WATCHER, not decoration. Each section carries
-- the class set it partitioned on. That makes this function's partition
-- MECHANICALLY COMPARABLE to CASHFLOW_CLASS_TO_SECTION's inverse in the shared
-- module — a QA leg can assert the two agree. Two homes for one mapping is the
-- shape that drifts; a home plus a watcher over it is not.
--
-- ----------------------------------------------------------------------------
-- SIGN CONVENTION — two sections inherit 093's multiplier and ONE DOES NOT.
--
--   income           sign = +1  Revenue is already inflow-positive (as 093).
--   expenses         sign = -1  Expense is outflow-NEGATIVE in account_trans,
--                               negated ONCE at the section so the ordinary
--                               case renders outflow-positive (as 093).
--   other_cash_flows sign = +1  NOT a normalization — the RAW SIGNED amount.
--
-- ⚠ The +1 on other_cash_flows is a DELIBERATE CHOICE and is the one place this
-- function had a decision to make rather than a precedent to follow. Income and
-- Expenses each have a normal balance to normalize TOWARD; Transfer ∪ Equity has
-- none — a transfer is inbound or outbound with equal legitimacy, and
-- Equity/Contribution and Equity/Distribution point in opposite directions
-- WITHIN THE SAME SECTION (both seeded at 091). Any multiplier other than +1
-- would declare one direction "normal" and render the other one negative, which
-- is a claim about the user's intent that no ruling makes. +1 leaves each row
-- with the sign the ledger actually recorded: money into this account positive,
-- money out negative. The alternative considered and rejected was per-row
-- abs() — rejected for the same reason 093 rejects it, and harder here, since a
-- section with no normal balance would lose ALL of its information under abs().
--
-- ⚠ NEVER abs() per row, in any section. Reachable states, stated the way
-- ADR-061 Decision 3 and 093 do:
--   Revenue,  net inflow        -> POSITIVE  (the ordinary case)
--   Revenue,  net contra        -> NEGATIVE  (refunds/chargebacks exceed receipts)
--   Expense,  net outflow       -> POSITIVE  (the ordinary case)
--   Expense,  net refund        -> NEGATIVE  (returns exceed spending in window)
--   Transfer/Equity, inbound    -> POSITIVE
--   Transfer/Equity, outbound   -> NEGATIVE  (an ORDINARY case here, not an edge)
--   any bucket, exactly zero    -> 0         (a real answer; e.g. fully reversed)
--   quarter not yet started     -> NULL      (renders em-dash, never $0)
-- A consumer that cannot render a negative figure hides exactly what this
-- surface exists to show, and on the middle section it would hide HALF of it.
--
-- ----------------------------------------------------------------------------
-- ACCOUNT SCOPING, AND WHY THERE IS NO OWNERSHIP CHECK.
--
-- The filter is `account_id = p_account_id` applied to the reader's OUTPUT. The
-- reader has already resolved tenancy: its rows exist only for accounts the
-- caller can read. A foreign or nonexistent p_account_id therefore matches zero
-- reader rows and this function returns its ORDINARY EMPTY DOCUMENT — three
-- sections, empty row lists, zero totals.
--
-- ⚠ That is the REQUIRED behaviour and an explicit ownership check would BREAK
-- it. A `raise` on "no such account" would answer an existence question the
-- caller is not entitled to ask, and would make a foreign account_id
-- distinguishable from an owned-but-empty one. The three states — owned and
-- empty · owned by someone else · never existed — are INDISTINGUISHABLE to the
-- caller BY CONSTRUCTION, not by care. Sec verifies this at SELF-257.
--
-- ⚠ A NULL p_account_id or a NULL p_as_of likewise yields that same empty
-- document rather than an error: every comparison is NULL and the reader itself
-- fails closed on a NULL as-of. Neither is a supported call — the app validates
-- both before invocation (AC5) — and neither leaks.
--
-- ----------------------------------------------------------------------------
-- ⚠ INHERITED RESIDUAL, restated so a reader of THIS file does not conclude the
-- case is handled: the reader cannot see a reversal of a SPLIT PARENT, because
-- rule 3's netting term attaches at the transaction grain and a split parent
-- emits no item to net against. What holds the line is the write-path refusal of
-- reversing a split parent. This function inherits that residual whole; it
-- neither checks nor promises it. See 093's header for the full statement.
--
-- ⚠ SECTION-2 COPY, owed at the UI (SELF-254 / AC8) and named here because this
-- is the function that creates the section: classifying a transfer does NOT by
-- itself make it cancel out — a journal-less `Transfer` resolves to Suspense in
-- the GL. Copy on this section must not promise an offset. This function emits
-- no copy and cannot enforce that; recording the obligation is what it can do.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_cashflow_per_account(
  p_account_id bigint,
  p_as_of      date
)
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

  -- The em-dash rule, two-sided (V1.3 pre-flight sitting item 5a; 093's Part B
  -- states it identically and for the same reason): a quarter that has NOT
  -- STARTED relative to D renders as an em-dash and must arrive as NULL; a
  -- quarter that HAS started with no rows in it renders $0 and must arrive as 0.
  -- The two must never be collapsed by a coalesce. "Has the quarter started" is
  -- not a property of any item, so it cannot come from the reader's flags — it
  -- is arithmetic on THIS function's own parameter, and is therefore not a
  -- restatement of reader rule 5.
  started as (
    select
      (b.q1_start <= b.d) as q1,
      (b.q2_start <= b.d) as q2,
      (b.q3_start <= b.d) as q3,
      (b.q4_start <= b.d) as q4
    from bounds b
  ),

  -- The three §2.3.3 sections, in the PRD's ruled order: Income -> Other Cash
  -- Flows -> Expenses. `section_key` values are the shared module's
  -- CashflowSectionKey; no product label appears here. See the SIGN CONVENTION
  -- block above for why other_cash_flows carries +1 rather than a normalization.
  sections(section_key, sign, ord) as (
    values
      ('income'::text,            1::numeric, 1),
      ('other_cash_flows'::text,  1::numeric, 2),
      ('expenses'::text,         -1::numeric, 3)
  ),

  -- The class sets, one ROW PER (section, cat) rather than an array literal, so
  -- the middle section's union is expressed as data the join consumes directly
  -- and the emitted `cats` array is derived from the same rows that do the
  -- partitioning — one source, not a declaration plus a copy of it.
  -- `Trade` has NO row here: excluded from every §2.3 surface by D-2, the same
  -- way it has no entry in CASHFLOW_CLASS_TO_SECTION.
  section_cats(section_key, cat) as (
    values
      ('income'::text,           'Revenue'::text),
      ('other_cash_flows'::text, 'Transfer'::text),
      ('other_cash_flows'::text, 'Equity'::text),
      ('expenses'::text,         'Expense'::text)
  ),

  -- THE ONLY READ. The account filter is applied to the reader's output, not
  -- pushed into a predicate of our own — the reader owns every predicate over
  -- pfin.account_trans, including the as-of pair.
  items as (
    select i.*
    from pfin.fn_cashflow_items(p_as_of) i
    where i.account_id = p_account_id
  ),

  -- Sub-Cat rows: group (cat, sub_cat), sum amount_net per period flag.
  -- `cat` is carried through — unlike 093, where the section IS the cat, here
  -- the middle section spans two classes and (cat, sub_cat) is what makes a row
  -- identifiable. The UI still renders flat with no Cat-group headers (PRD
  -- §2.3.3); `cat` is the row's key, not a rendering instruction.
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
    -- in_ytd is the UNION of every period this surface renders (month and each
    -- quarter are subsets of it by rule 5's construction), so this conjunct
    -- changes no displayed figure. What it removes is a Sub-Cat whose only items
    -- fall OUTSIDE the rendered year — the reader emits those for the §2.3.4
    -- five-year window — which would otherwise appear as a row of zeros in every
    -- column. A zero in a period is a real answer; a Sub-Cat with no activity in
    -- the year at all is not one of this surface's rows.
    where i.sub_cat_id is not null
      and i.in_ytd
    group by i.cat, i.sub_cat
  ),

  -- ⚠ The multiplier is applied per SECTION, never abs() per row. See the SIGN
  -- CONVENTION block above for the reachable states, including the two that are
  -- ORDINARY rather than exotic on other_cash_flows.
  sub_cat_rows as (
    select
      s.ord,
      s.section_key,
      r.cat,
      r.sub_cat,
      (s.sign * coalesce(r.m,   0))                                      as v_month,
      case when st.q1 then (s.sign * coalesce(r.q1,  0)) else null end   as v_q1,
      case when st.q2 then (s.sign * coalesce(r.q2,  0)) else null end   as v_q2,
      case when st.q3 then (s.sign * coalesce(r.q3,  0)) else null end   as v_q3,
      case when st.q4 then (s.sign * coalesce(r.q4,  0)) else null end   as v_q4,
      (s.sign * coalesce(r.ytd, 0))                                      as v_ytd
    from sections s
    join section_cats sc on sc.section_key = s.section_key
    join sub_cat_raw  r  on r.cat = sc.cat
    cross join started st
  ),

  -- The per-section Total foot row sums each period column INDEPENDENTLY — down
  -- the column, never across the row, because the period columns overlap. On
  -- other_cash_flows the total is a NET of inbound and outbound flows, which is
  -- the honest reading of a section with no normal balance.
  section_totals as (
    select
      s.ord,
      s.section_key,
      coalesce(sum(sr.v_month), 0)                                  as t_month,
      case when st.q1 then coalesce(sum(sr.v_q1),  0) else null end as t_q1,
      case when st.q2 then coalesce(sum(sr.v_q2),  0) else null end as t_q2,
      case when st.q3 then coalesce(sum(sr.v_q3),  0) else null end as t_q3,
      case when st.q4 then coalesce(sum(sr.v_q4),  0) else null end as t_q4,
      coalesce(sum(sr.v_ytd), 0)                                    as t_ytd
    from sections s
    cross join started st
    left join sub_cat_rows sr on sr.section_key = s.section_key
    group by s.ord, s.section_key, st.q1, st.q2, st.q3, st.q4
  ),

  -- The emitted class set per section, aggregated from the SAME rows the
  -- partition joins on.
  section_cat_list as (
    select
      sc.section_key,
      jsonb_agg(sc.cat order by sc.cat) as cats
    from section_cats sc
    group by sc.section_key
  ),

  -- The unclassified count, from the SAME query as the sums and scoped to the
  -- SAME account — that identity is why the reader emits unclassified items
  -- rather than filtering them out. Scoped to the rendered year (in_ytd),
  -- matching what this surface renders. A consumer that re-derives this from a
  -- second query forfeits the only property the shared reader exists to deliver.
  unclassified as (
    select count(*)::bigint as count_ytd
    from items i
    where i.sub_cat_id is null
      and i.in_ytd
  )

  select jsonb_build_object(
    'as_of',      to_jsonb(p_as_of),
    'account_id', to_jsonb(p_account_id),
    'sections', (
      select coalesce(jsonb_agg(sec order by sec_ord), '[]'::jsonb)
      from (
        select
          t.ord as sec_ord,
          jsonb_build_object(
            'section_key', t.section_key,
            'cats',        scl.cats,
            'rows', coalesce((
              select jsonb_agg(
                       jsonb_build_object(
                         'cat',     sr.cat,
                         'sub_cat', sr.sub_cat,
                         'month',   sr.v_month,
                         'q1',      sr.v_q1,
                         'q2',      sr.v_q2,
                         'q3',      sr.v_q3,
                         'q4',      sr.v_q4,
                         'ytd',     sr.v_ytd
                       ) order by sr.sub_cat, sr.cat
                     )
              from sub_cat_rows sr
              where sr.section_key = t.section_key
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
        join section_cat_list scl on scl.section_key = t.section_key
      ) z
    ),
    'unclassified', (
      select jsonb_build_object('count_ytd', u.count_ytd) from unclassified u
    )
  )
$$;

revoke execute on function pfin.fn_cashflow_per_account(bigint, date) from public;
grant  execute on function pfin.fn_cashflow_per_account(bigint, date) to authenticated;

comment on function pfin.fn_cashflow_per_account(bigint, date) is
  'PRD §2.3.3 per-account cash-flow drill-down (SELF-253). Composes on '
  'pfin.fn_cashflow_items(p_as_of) and adds SHAPING ONLY — it restates NONE of '
  'the six reader rules, and a reader rule appearing here IS the drift defect '
  'the shared reader exists to prevent. In particular the as-of semantics are '
  'the reader''s rule 6 (dual-column, HALF-OPEN: transaction_date <= p_as_of AND '
  'created_at < (p_as_of + 1), per ADR-011 Decision 19 as amended 2026-08-22) '
  'and this function carries NO date predicate of its own; its arithmetic on '
  'p_as_of derives quarter STARTS only. SECURITY INVOKER + STABLE + set '
  'search_path = ''''; p_account_id is pfin.account.account_id (bigint, NOT '
  'uuid); p_as_of has NO DEFAULT because the app threads it and the Lock 15 '
  'range validation ([floor, today], no future dates) is APP-LAYER and is not '
  're-implemented here. NO tenant, scope or year parameter — isolation is '
  'INHERITED through the reader under the caller''s own session, and the year is '
  'year(p_as_of). ⚠ SECURITY DEFINER would be a DEFECT here, not a convenience: '
  'it would sever the account filter from the RLS that makes it safe and turn '
  'p_account_id into an unfenced tenant selector. Returns one jsonb document: '
  'as_of, account_id, sections, unclassified. sections is ALWAYS exactly three '
  'entries in the PRD''s ruled order — section_key ''income'' then '
  '''other_cash_flows'' then ''expenses'' — present even when empty. section_key '
  'is the app-side GROUPING IDENTITY (CashflowSectionKey in the shared '
  'section-map module api/src/lib/server/queries/cashflowSections.ts); the '
  'product LABELS live in that module''s CASHFLOW_SECTION_LABELS and appear '
  'nowhere in this function. Each section also carries `cats`, the class set it '
  'partitioned on: ''income'' <- {Revenue}, ''other_cash_flows'' <- {Transfer, '
  'Equity}, ''expenses'' <- {Expense}. That array is a WATCHER — it makes this '
  'partition mechanically comparable to the shared module''s inverse mapping, so '
  'the two homes cannot drift unobserved. ⚠ "Other Cash Flows" is a SECTION '
  'NAME, not a Cat: OtherCF is not a posting-vocabulary value and no row carries '
  'it; the section''s content is the Transfer union Equity union. ⚠ Trade '
  'belongs to NO section and is excluded from every §2.3 surface by ruling, not '
  'by omission. ⚠ SIGN: each section applies ONE multiplier to the whole section '
  '— NEVER abs() per row. Revenue as-is and Expense negated, both so the '
  'ordinary case renders positive; other_cash_flows carries a +1 that is NOT a '
  'normalization but the RAW SIGNED amount, because Transfer union Equity has no '
  'normal balance — an inbound transfer and an outbound one are equally '
  'ordinary, and Contribution and Distribution point opposite ways inside that '
  'one section. A genuinely negative bucket KEEPS ITS REAL SIGN in every '
  'section, and a consumer unable to render a negative figure hides half of '
  'other_cash_flows. ⚠ The period columns OVERLAP (month is inside its quarter, '
  'which is inside YTD), so every total sums DOWN one column and never across. ⚠ '
  'A quarter that has NOT STARTED relative to p_as_of arrives as JSON null '
  '(render an em-dash); a quarter that HAS started with no rows arrives as 0 (a '
  'real answer). These two MUST NOT be collapsed. Rows carry `cat` as well as '
  '`sub_cat` because the middle section spans two classes and (cat, sub_cat) is '
  'what identifies a row; the view still renders Sub-Cats FLAT with no Cat-group '
  'headers. ⚠ There is NO targets key, and its absence is the contract: targets '
  'are §2.3.2 aggregate concepts that do not attach to a single-account scope, '
  'and a consumer must not synthesise one. unclassified.count_ytd counts items '
  'with NULL sub_cat_id for THIS account in the rendered year, FROM THE SAME '
  'QUERY as the sums — the count and the totals cannot drift because there is '
  'only one query. ⚠ ACCOUNT SCOPING IS NON-DISCLOSING BY CONSTRUCTION: the '
  'filter runs over the reader''s already-RLS-scoped output, so an account owned '
  'by someone else, an account that never existed, and an owned account with no '
  'activity ALL return the same ordinary empty document — three sections, empty '
  'row lists, zero totals. An explicit ownership check would BREAK that by '
  'answering an existence question the caller may not ask, and must not be '
  'added. A NULL p_account_id or NULL p_as_of returns that same empty document '
  'rather than raising; neither is a supported call and neither leaks. ⚠ '
  'INHERITED RESIDUAL: a reversal of a SPLIT PARENT is invisible to the reader '
  'and therefore to this function — the netting term attaches at the transaction '
  'grain and a split parent emits no item to net against; what holds the line is '
  'the write-path refusal of reversing a split parent, which this function '
  'neither checks nor promises. Reads only: no write path, no new FK-shaped '
  'column, no SECURITY DEFINER entry, no service_role grant. ADR-011 Decision 3 '
  'family and the §10 catalogued-instance ledger are both unchanged by this '
  'migration — read Decision 3, Decision 4 and Decision 9 live, never from a '
  'copy.';
