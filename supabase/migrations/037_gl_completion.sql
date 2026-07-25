-- ============================================================================
-- Migration: M4-GL-write COMPLETION — closes the Double-Entry GL project core.
--   Four co-landing components (all SECURITY INVOKER; single logical lock-set):
--     (1) pfin.fn_gl_entries create-or-replace — SELL realized-gain / position-basis
--         removal reading the now-writable pfin.lot_match (FIFO/specific-lot; Option A:
--         ONE realized-gain line to equity, tax character derived in the tax layer);
--         book-neutral corp_actions are already no-ops; wash_sale + substantive
--         corp_action stay Suspense-parked (deferred — see follow-ups).
--     (2) pfin.fn_journal_close_balance — at-close enforcement trigger on pfin.journal.
--         First an ALL-group_types future-dated-leg reject (N1; one "no closing a period
--         with future-dated entries" rule — keeps every snapshot faithful), then the
--         Option-B group_type conservation law (transfer=Σamount=0; transfer_in_kind=
--         per-security Σqty=0; compound=NO Suspense residual — the literal total-Σ is
--         vacuous [self-balancing contras]; F/CTO-ratified 2026-07-25) + writes the snapshot.
--     (3) pfin.journal ALTER — close_book_value + closed_at columns (write-once at
--         close; nulled on reopen).
--     (4) pfin.fn_account_trans_annotation_freeze_closed — membership-freeze guard on
--         the 023 overlay (rejects attach/detach/edit of a CLOSED journal's legs).
--     (F1) journal_insert WITH CHECK gains `status = 'open'` (Sec F1 gate-now, ratified
--         2026-07-25) — re-created append-only-correctly, 025 aal2 backstop reproduced.
--   Linear SELF-301. F/CTO-ratified 2026-07-25 (A / B / A+guard / defer + F1 gate-now).
--   Design memo temp/m4-gl-write-design.md §037.
--
-- Numbering: 037 follows 036 (lot_match write-enablement). Depends on 035 (the
--   fn_gl_entries this replaces), 032 (pfin.lot_match — now writable per 036; the sell
--   reads its current-batch matches), 033 (pfin.journal + status/reopen + the 023
--   journal_id overlay the freeze guards), 034 (basis_adjust), 023 (the annotation
--   overlay), 017/004 (account_trans facts), 019 (fn_compute_nav — reused by the memo).
--
-- POSTURE RATIONALE — ALL SECURITY INVOKER; NO new SECURITY DEFINER (allowlist UNCHANGED
--   at 4 = 3 authored + 1 reserved). fn_gl_entries stays an INVOKER read (composes under
--   the caller's RLS). BOTH new triggers are INVOKER: the Σ=0-close trigger reads the
--   group's legs + writes close_book_value/closed_at ON THE ROW THE CALLER IS UPDATING
--   (their own journal, under their own RLS) — no elevated privilege; the membership-freeze
--   guard reads pfin.journal.status and raises — touches nothing it could not already read.
--   set search_path = '' on every function. No function joins the DEFINER allowlist.
--
-- ----------------------------------------------------------------------------
-- COMPONENT 1 — SELL realized-gain (Option A; ratified). The sale completes what 035
--   parks in Suspense, BALANCED-BY-CONSTRUCTION (three legs sum to exactly 0 for any
--   matched-book value — the trial balance can never be unbalanced by this logic):
--     Dr Cash (proceeds; already 035 P1) · Cr Position (matched lots' CURRENT CARRIED
--     BOOK value) · Realized-Gain = proceeds − that book → Equity (ONE line).
--   MATCHED SET: the current re-match batch (max(match_seq) per sell_trans_id, 032),
--     FIFO/specific-lot (F/CTO-locked). MATCHED BOOK = the matched lots' FIFO/specific-lot
--     ACQUISITION basis (Σ quantity_matched × buy.cost_basis/buy.quantity) PLUS the sold
--     shares' pro-rata share of the security's position-level basis_adjust deltas
--     (Σ basis_adjust.cost_basis × matched_qty / total-bought-qty) — this is exactly the
--     "current carried book" (acquisition net of the depreciation/RoC that 035 already
--     posted to the position), so the position zeros on full liquidation and the gain is
--     proceeds − effective book. PARK-IF-UNMATCHED: a sell with NO lot_match rows keeps
--     035's Suspense counter (the graceful-degradation floor).
--   TAX CHARACTER NOT POSTED (Option A): ST/LT holding-period + depreciation-recapture
--     (recapture = min(gain, accumulated_depreciation)) are DERIVED in the tax layer
--     (fn_compute_tax_liability) from the lot_match (which lots / dates) + basis_adjust
--     history — the book trial balance posts only the total realized gain to equity. No
--     information is lost (lot_match + basis_adjust retain everything).
--   V1 CONVENTION NOTE (basis_adjust × lot-matched-security intersection): position-level
--     basis_adjust deltas are allocated to the sold shares PRO-RATA by share count (deltas
--     are position-level; lots are lot-level — pro-rata is the honest V1 allocation).
--     Exact for securities with no basis_adjust (acquisition == current book) and for
--     single-lot positions; strict per-lot delta attribution is a future refinement.
--     Regardless, the three sell legs remain balanced-by-construction.
--   corp_action / wash_sale — NO code change, already correct in 035:
--     - BOOK-NEUTRAL corp_actions (split / ticker-change: amount=0 AND cost_basis=0) emit
--       ZERO book legs already (035 P1/P2 skip, P9 nets 0) — the quantity change flows to
--       fn_holdings_as_of / NAV, book unaffected. Completed by construction.
--     - SUBSTANTIVE corp_action (spin-off / cash-in-lieu: amount<>0 or cost_basis<>0) and
--       basis_adjust wash_sale P&L stay SUSPENSE-PARKED (035 P9 / P7) — DEFERRED (below).
--
-- ----------------------------------------------------------------------------
-- COMPONENT 4 SCOPE NOTE (deliberate strengthening, flagged for Sec/F-CTO): the ratified
--   ask was a membership-freeze on journal_id attach/detach. The guard as authored uses
--   the simpler, stricter predicate "block any 023 write where OLD.journal_id or
--   NEW.journal_id is a CLOSED journal" — which freezes BOTH membership (journal_id) AND
--   classification (sub_cat_id / metadata) of a closed journal's legs. This is a superset
--   of the ask and is the faithful choice: a re-derived close Σ depends on the legs'
--   classification too, so freezing only journal_id would still let a sub_cat edit perturb
--   the snapshot. Stricter = more fail-closed = safe. Reopen (status→'open') unfreezes.
--
-- ----------------------------------------------------------------------------
-- DEFERRED (post-037 follow-ups — team-lead files at PR time; each its own later migration):
--   (D1) basis_adjust wash_sale P&L — the disallowed loss adds to the replacement lot's
--        basis (lot-level, intricate); stays Suspense-parked (035 P7) until specified.
--   (D2) SUBSTANTIVE corp_action (spin-off basis allocation / cash-in-lieu) — its own
--        economic spec; stays Suspense-parked (035 P9) until specified.
--   037 completes the SELL realized-gain + book-neutral corp_actions and CLOSES the
--   M4-GL / Double-Entry GL project CORE. The two deferred classes are Suspense-safe
--   (they surface as reconciliation to-dos, never silently drop, never unbalance).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Decision 4 read verbatim before drafting.) 037 introduces
--   ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: an INVOKER read revision + two INVOKER triggers + two numeric/
--         timestamp columns on pfin.journal — all authenticated-tier, no service_role grant,
--         no credential, no admission/network-exposure/config surface. RT-22 (PDF-worker
--         container), RT-26 (SUPABASE_SERVICE_ROLE_KEY source grep fence), RT-27 (admission
--         inbound fence) untouched. Nothing becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated. 037 is not the anchor.
--   DE-CONFLATION GUARD: the freeze guard reads pfin.journal.status — it is a snapshot-
--   fidelity mechanism, NOT a §10 catalogued instance and NOT a Decision-3 instance.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY DEFINER
--   allowlist = unchanged (4: 3 authored — fn_refresh_updated_at @001, fn_grant_creator_
--   access @003, fn_reclass_history_insert @031 — + 1 reserved; both new triggers INVOKER,
--   no new DEFINER) · Decision-3 family = unchanged (NO new FK-shaped column — the freeze
--   guard READS the existing 023.journal_id FK's target status; the close snapshot is two
--   plain columns on pfin.journal, no FK; the F1 journal_insert predicate is a status
--   literal — no new FK, no new function). Zero ledger movement — the whole GL project
--   closes flat.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_gl_entries(p_as_of date) — signature UNCHANGED (12-col RETURNS TABLE as 035);
--     body revised: a matched SELL now emits Cr Position(current carried book) + a single
--     Realized-Gain equity line instead of parking proceeds in Suspense; unmatched sells
--     still park (035 floor). Balanced-by-construction; INVOKER; set search_path=''.
--   pfin.fn_journal_close_balance() — BEFORE UPDATE trigger on pfin.journal; INVOKER.
--     On open→closed: enforces the group_type conservation law (transfer→Σamount=0;
--     transfer_in_kind→per-security Σquantity=0; compound→fn_gl_entries book Σ=0), RAISEs
--     on imbalance, and writes close_book_value (gross debit book at close) + closed_at.
--     On closed→open (reopen): nulls close_book_value + closed_at. Never re-values a
--     standing snapshot (write-once at close).
--   pfin.fn_account_trans_annotation_freeze_closed() — BEFORE INSERT/UPDATE/DELETE trigger
--     on pfin.account_trans_annotation; INVOKER. Rejects any write where OLD.journal_id or
--     NEW.journal_id is a CLOSED journal (freezes membership + classification of a closed
--     group's legs); reopen to modify. NULL-safe (no journal_id → no-op).
--   Security-load-bearing edges: all INVOKER (cross-tenant caller sees no rows / cannot
--     touch another tenant's journal); sell legs balanced-by-construction; the close check
--     + freeze fail loud; snapshot write-once. No DEFINER; no new §10 / Decision-3 surface.
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- COMPONENT 3 — close-snapshot columns on pfin.journal (additive; write-once at close).
-- ----------------------------------------------------------------------------
alter table pfin.journal
  add column if not exists close_book_value numeric,
  add column if not exists closed_at timestamptz;

comment on column pfin.journal.close_book_value is
  'Book-value snapshot of the group at close (gross debit-side book from fn_gl_entries), '
  'write-once by fn_journal_close_balance on open→closed, NULLed on reopen (037 / SELF-301; '
  '033 Decision 7 M2 cond 7 — snapshotted deterministically at close, never re-valued). '
  'Faithful because the 037 membership-freeze guard holds the group''s legs + classification '
  'stable while closed, so a re-derived Σ matches this stored witness.';
comment on column pfin.journal.closed_at is
  'Timestamp the group was closed (set with close_book_value; NULLed on reopen). 037/SELF-301.';

-- ----------------------------------------------------------------------------
-- COMPONENT F1 (Sec joint-review; F/CTO-ratified gate-now 2026-07-25) — close the
--   insert-with-status='closed' hole. Journals are BORN open; closing is ONLY via the
--   gated open→closed UPDATE (which runs fn_journal_close_balance's conservation check +
--   writes closed_at). An INSERT that sets status='closed' would bypass that gate and
--   violate the CONTRACT invariant (closed ⟹ conservation-checked + closed_at written).
--   Fix: add `status = 'open'` to the journal_insert WITH CHECK. Re-created here
--   append-only-correctly (033's file untouched — the 034/017 precedent); the 025 aal2
--   backstop clause is REPRODUCED VERBATIM (dropping it would be an aal1 read/write
--   regression). Ledger-flat: a status literal predicate — no new FK, no new function.
-- ----------------------------------------------------------------------------
drop policy if exists journal_insert on pfin.journal;
create policy journal_insert on pfin.journal
  for insert to authenticated
  with check (
    users_id = auth.uid()
    and status = 'open'
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy journal_insert on pfin.journal is
  'Direct-owner INSERT WITH CHECK (users_id = auth.uid()) AND status = ''open'' (F1 gate, '
  '037 / SELF-301: journals are born open; closing is ONLY via the gated open->closed UPDATE '
  '+ the journal_close_balance conservation check — an insert-with-status=''closed'' is '
  'rejected here, closing the CONTRACT invariant closed => conservation-checked + closed_at '
  'written) AND the 025 aal2 backstop. Supersedes the 033 journal_insert policy (append-only '
  're-create; 033 file untouched).';

-- ----------------------------------------------------------------------------
-- COMPONENT 1 — pfin.fn_gl_entries create-or-replace (035 body + the SELL completion).
-- Signature unchanged. Balanced-by-construction. INVOKER; set search_path=''.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_gl_entries(p_as_of date)
returns table (
  users_id        uuid,
  as_of           date,
  source_trans_id bigint,
  split_id        bigint,
  journal_id      bigint,
  account_id      bigint,
  entry_account   text,
  security_id     bigint,
  entry_class     text,
  side            text,
  currency        text,
  amount_book     numeric
)
language sql
security invoker
set search_path = ''
as $$
  with txn as (
    select
      t.trans_id, t.account_id, t.amount, t.security_id, t.quantity, t.cost_basis,
      t.transaction_type, t.transaction_date,
      a.users_id     as users_id,
      a.currency     as currency,
      a.name         as account_name,
      ann.journal_id as journal_id,
      (ann.metadata ->> 'reason') as reason,
      ut.cat         as flow_class,
      (select count(*) from pfin.account_trans_split s where s.account_trans_id = t.trans_id) as split_count
    from pfin.account_trans t
    join pfin.account a on a.account_id = t.account_id
    left join pfin.account_trans_annotation ann on ann.trans_id = t.trans_id
    left join pfin.user_taxonomy ut on ut.id = ann.sub_cat_id
    where t.transaction_date <= p_as_of
  ),

  -- SELL completion (Component 1): the current re-match batch per sell, its matched
  -- acquisition basis (FIFO/specific-lot), and the pro-rata basis_adjust term → the
  -- matched lots' CURRENT CARRIED BOOK value. Only sells WITH lot_match rows appear here;
  -- unmatched sells fall through to the Suspense floor (P8).
  sell_curr_batch as (
    select lm.sell_trans_id, lm.buy_trans_id, lm.quantity_matched
    from pfin.lot_match lm
    where lm.match_seq = (
      select max(lm2.match_seq) from pfin.lot_match lm2 where lm2.sell_trans_id = lm.sell_trans_id
    )
  ),
  sell_agg as (
    select
      t.trans_id as sell_trans_id, t.users_id, t.account_id, t.account_name, t.security_id,
      t.journal_id, t.currency, t.amount, t.transaction_date,
      coalesce(sum(scb.quantity_matched * (coalesce(b.cost_basis, 0) / nullif(b.quantity, 0))), 0) as matched_acq,
      coalesce(sum(scb.quantity_matched), 0) as matched_qty
    from txn t
    join sell_curr_batch scb on scb.sell_trans_id = t.trans_id
    join pfin.account_trans b on b.trans_id = scb.buy_trans_id
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity < 0
    group by t.trans_id, t.users_id, t.account_id, t.account_name, t.security_id,
             t.journal_id, t.currency, t.amount, t.transaction_date
  ),
  sell_book as (
    select
      sa.users_id, sa.sell_trans_id, sa.account_id, sa.account_name, sa.security_id,
      sa.journal_id, sa.currency, sa.amount,
      sa.matched_acq
      + coalesce(
          (select coalesce(sum(ba.cost_basis), 0)
             from pfin.account_trans ba
            where ba.account_id = sa.account_id and ba.security_id = sa.security_id
              and ba.transaction_type = 'basis_adjust'
              and ba.transaction_date <= sa.transaction_date)
          * (sa.matched_qty / nullif(
              (select sum(bq.quantity)
                 from pfin.account_trans bq
                where bq.account_id = sa.account_id and bq.security_id = sa.security_id
                  and bq.quantity > 0 and bq.transaction_date <= sa.transaction_date), 0)),
          0) as matched_book
    from sell_agg sa
  ),

  -- REAL LEGS: P1 cash + P2 position adds + the SELL position removal (Component 1).
  real_leg as (
    -- P1: cash leg — every cash-bearing row (incl. the sell's proceeds).
    select
      t.users_id, t.trans_id as source_trans_id, null::bigint as split_id, t.journal_id,
      t.account_id, t.account_name as entry_account, null::bigint as security_id,
      'asset_liability'::text as entry_class, t.currency, t.amount as amount_book
    from txn t
    where t.amount <> 0
    union all
    -- P2: position book add — BUY / acct_setup position / basis_adjust delta. Standard
    --     non-buys (sell / zero-qty) excluded (the sell removes position via sell_book).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      t.account_id, t.account_name, t.security_id,
      'trade_position'::text, t.currency, t.cost_basis
    from txn t
    where t.security_id is not null
      and t.cost_basis is not null and t.cost_basis <> 0
      and not (t.transaction_type = 'standard' and t.quantity <= 0)
    union all
    -- SELL position removal (Component 1): remove the matched lots at current carried book.
    select
      sb.users_id, sb.sell_trans_id, null::bigint, sb.journal_id,
      sb.account_id, sb.account_name, sb.security_id,
      'trade_position'::text, sb.currency, (- sb.matched_book)
    from sell_book sb
  ),

  contra as (
    -- P3: standard cash-flow contra (non-split), by the 023 overlay cat.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint as account_id,
      case
        when t.flow_class = 'Revenue'  then 'Revenue'
        when t.flow_class = 'Expense'  then 'Expense'
        when t.flow_class = 'Equity'   then 'Equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end as entry_account,
      null::bigint,
      case
        when t.flow_class = 'Revenue'  then 'revenue'
        when t.flow_class = 'Expense'  then 'expense'
        when t.flow_class = 'Equity'   then 'equity'
        when t.flow_class = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end as entry_class,
      t.currency, (- t.amount) as amount_book
    from txn t
    where t.transaction_type = 'standard' and t.security_id is null
      and t.split_count = 0 and t.amount <> 0

    union all
    -- P4: split-child contras — one per 029 child, by the CHILD's cat.
    select
      t.users_id, t.trans_id, s.id, t.journal_id, null::bigint,
      case
        when ut.cat = 'Revenue'  then 'Revenue'
        when ut.cat = 'Expense'  then 'Expense'
        when ut.cat = 'Equity'   then 'Equity'
        when ut.cat = 'Transfer' and t.journal_id is not null then 'Journal Clearing'
        else 'Suspense'
      end,
      null::bigint,
      case
        when ut.cat = 'Revenue'  then 'revenue'
        when ut.cat = 'Expense'  then 'expense'
        when ut.cat = 'Equity'   then 'equity'
        when ut.cat = 'Transfer' and t.journal_id is not null then 'journal_clearing'
        else 'suspense'
      end,
      t.currency, (- s.amount)
    from txn t
    join pfin.account_trans_split s on s.account_trans_id = t.trans_id
    left join pfin.user_taxonomy ut on ut.id = s.sub_cat_id
    where t.split_count > 0

    union all
    -- P5: acct_setup contra → Opening-Balance-Equity (offsets cash + opening position).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Opening Balance Equity', null::bigint, 'opening_equity',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'acct_setup'

    union all
    -- P6: basis_adjust depreciation contra → Dr Depreciation-Expense.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Depreciation Expense', null::bigint, 'depreciation_expense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust' and t.reason = 'depreciation'
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P7: basis_adjust wash_sale / unknown-reason contra → Suspense (DEFERRED D1, 037).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.cost_basis)
    from txn t
    where t.transaction_type = 'basis_adjust'
      and (t.reason is null or t.reason not in ('depreciation', 'return_of_capital'))
      and t.cost_basis is not null and t.cost_basis <> 0

    union all
    -- P8: UNMATCHED standard security non-buy (sell w/o lot_match, or zero-qty) → Suspense
    --     (the park-if-unmatched floor). Matched sells are completed via sell_book, so they
    --     are excluded here by the NOT EXISTS.
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, (- t.amount)
    from txn t
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity <= 0
      and not exists (select 1 from pfin.lot_match lm where lm.sell_trans_id = t.trans_id)

    union all
    -- SELL realized-gain (Component 1): the single equity line = proceeds − matched book.
    -- (matched_book − amount): a GAIN (proceeds > book) is negative → credit to equity.
    select
      sb.users_id, sb.sell_trans_id, null::bigint, sb.journal_id,
      null::bigint, 'Realized Gain/(Loss)', null::bigint, 'realized_gain',
      sb.currency, (sb.matched_book - sb.amount)
    from sell_book sb

    union all
    -- P9: corp_action counter → Suspense (book-neutral nets 0 & drops; SUBSTANTIVE deferred D2).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency,
      - ( coalesce(t.amount, 0)
          + coalesce(case when t.security_id is not null then t.cost_basis else 0 end, 0) )
    from txn t
    where t.transaction_type = 'corp_action'

    union all
    -- P10: standard BUY residual plug → Suspense (0 for a clean buy).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'standard' and t.security_id is not null and t.quantity > 0

    union all
    -- P11: return_of_capital residual plug → Suspense (0 when cash-in = basis-out).
    select
      t.users_id, t.trans_id, null::bigint, t.journal_id,
      null::bigint, 'Suspense', null::bigint, 'suspense',
      t.currency, - ( coalesce(t.amount, 0) + coalesce(t.cost_basis, 0) )
    from txn t
    where t.transaction_type = 'basis_adjust' and t.reason = 'return_of_capital'
  ),

  postings as (
    select * from real_leg
    union all
    select * from contra
  ),

  book_nav as (
    select coalesce(sum(
      rl.amount_book
      * case when rl.currency = 'USD' then 1.0
             else coalesce((
               select fx.price from pfin.eod_price fx
               join pfin.asset ca on ca.asset_id = fx.asset_id
               where ca.users_id is null and ca.asset_type = 'currency'
                 and ca.symbol = rl.currency and fx.source = 'fx_feed'
                 and fx.price_date <= p_as_of
               order by fx.price_date desc limit 1), 1.0) end
    ), 0) as v
    from real_leg rl
  ),

  memo as (
    select
      auth.uid() as users_id,
      null::bigint as source_trans_id, null::bigint as split_id, null::bigint as journal_id,
      null::bigint as account_id,
      'Market Value Adjustment'::text as entry_account, null::bigint as security_id,
      'unrealized_gains'::text as entry_class, 'USD'::text as currency,
      (pfin.fn_compute_nav(p_as_of) - (select v from book_nav)) as amount_book
    union all
    select
      auth.uid(),
      null::bigint, null::bigint, null::bigint,
      null::bigint, 'Unrealized Gains (Equity)', null::bigint,
      'unrealized_gains', 'USD',
      - (pfin.fn_compute_nav(p_as_of) - (select v from book_nav))
  ),

  all_rows as (
    select * from postings
    union all
    select * from memo
  )

  select
    ar.users_id,
    p_as_of as as_of,
    ar.source_trans_id,
    ar.split_id,
    ar.journal_id,
    ar.account_id,
    ar.entry_account,
    ar.security_id,
    ar.entry_class,
    case when ar.amount_book >= 0 then 'dr' else 'cr' end as side,
    ar.currency,
    ar.amount_book
  from all_rows ar
  where ar.amount_book <> 0
  order by ar.source_trans_id nulls last, ar.entry_class;
$$;

revoke execute on function pfin.fn_gl_entries(date) from public;
grant execute on function pfin.fn_gl_entries(date) to authenticated;

comment on function pfin.fn_gl_entries(date) is
  'SECURITY INVOKER book-value GL / trial-balance read helper (M4-GL; ADR-031 Decision 5 / '
  'Lock 11). 037 completes the SELL: a matched sell (lot_match current batch, FIFO/specific-'
  'lot) posts Dr Cash / Cr Position(current carried book = FIFO acquisition + pro-rata '
  'basis_adjust) / one Realized-Gain line to equity (proceeds − book) — balanced-by-'
  'construction; ST/LT + recapture character is DERIVED in the tax layer, not posted (Option '
  'A). Unmatched sells park in Suspense (035 floor). Book-neutral corp_actions are no-ops; '
  'substantive corp_action + basis_adjust wash_sale stay Suspense-parked (deferred). Signature '
  'unchanged from 035; SUM(amount_book)=0 by construction; INVOKER (cross-tenant → no rows); '
  'set search_path=''''. §10 3, DEFINER 4, Decision-3 unchanged.';

-- ----------------------------------------------------------------------------
-- COMPONENT 2 — Σ=0-at-close enforcement trigger (Option B; group_type-branched) +
-- snapshot writer. BEFORE UPDATE on pfin.journal. INVOKER. Handles both transitions.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_journal_close_balance()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_residual    numeric;
  v_bad_security bigint;
begin
  -- REOPEN (closed→open): unfreeze; null the write-once snapshot (re-close re-snapshots).
  if old.status = 'closed' and new.status = 'open' then
    new.close_book_value := null;
    new.closed_at := null;
    return new;
  end if;

  -- CLOSE (open→closed): reject future-dated legs (ALL group_types), enforce the group_type
  --   conservation law, then snapshot.
  if old.status = 'open' and new.status = 'closed' then
    -- Future-dated guard (ALL group_types; 037 N1, F/CTO-ratified hoist 2026-07-25): every
    --   close snapshot (and the compound check) is computed via fn_gl_entries(current_date),
    --   which excludes a leg dated after today — so no group may close with a future-dated
    --   leg. One consistent "no closing a period with future-dated entries" rule; keeps
    --   close_book_value faithful for transfer / transfer_in_kind / compound alike.
    if exists (
      select 1
      from pfin.account_trans at
      join pfin.account_trans_annotation ann on ann.trans_id = at.trans_id
      where ann.journal_id = new.journal_id and at.transaction_date > current_date
    ) then
      raise exception
        'journal % cannot close: it has a future-dated leg (transaction_date > today) — close only once all legs are dated-through (037 N1; keeps close_book_value faithful).',
        new.journal_id;
    end if;

    if new.group_type = 'transfer' then
      -- cash conservation: Σ(amount) over the group's legs = 0.
      select coalesce(sum(at.amount), 0) into v_residual
      from pfin.account_trans at
      join pfin.account_trans_annotation ann on ann.trans_id = at.trans_id
      where ann.journal_id = new.journal_id;
      if v_residual <> 0 then
        raise exception
          'journal % cannot close: transfer legs do not net to zero (Sum(amount)=%). Park the residual in Suspense or correct the group (033 conservation law; ADR-031 Decision 4).',
          new.journal_id, v_residual;
      end if;

    elsif new.group_type = 'transfer_in_kind' then
      -- per-security quantity conservation: no security has a nonzero net quantity.
      select at.security_id into v_bad_security
      from pfin.account_trans at
      join pfin.account_trans_annotation ann on ann.trans_id = at.trans_id
      where ann.journal_id = new.journal_id and at.security_id is not null
      group by at.security_id
      having coalesce(sum(at.quantity), 0) <> 0
      limit 1;
      if v_bad_security is not null then
        raise exception
          'journal % cannot close: in-kind transfer does not conserve quantity for security % (Sum(quantity)<>0) (033 conservation law).',
          new.journal_id, v_bad_security;
      end if;

    else
      -- compound close law (037 F/CTO-ratified) = "all legs dated-through [the all-group_types
      --   guard above] + NO Suspense residual [here]", superseding the literal total-Sigma
      --   (VACUOUS — every leg's imputed contra self-balances within its own journal_id, so
      --   Sum(amount_book) over the group is always 0 and never catches an imbalance).
      -- NO Suspense residual — the meaningful "group fully resolved" gate (COMPOUND-ONLY;
      --   transfer / transfer_in_kind use their raw-leg conservation sums above). An
      --   unclassified / unmatched-sell / unarrived-transfer-counter leg surfaces as a
      --   Suspense posting; a compound group may only close once none remain.
      if exists (
        select 1 from pfin.fn_gl_entries(current_date) g
        where g.journal_id = new.journal_id and g.entry_class = 'suspense'
      ) then
        raise exception
          'journal % cannot close: the compound group has an unresolved (Suspense) leg — classify/match every leg first (037; ADR-031 Decision 5 book-value imputation; 033 M4-GL CONTRACT).',
          new.journal_id;
      end if;
    end if;

    -- Write-once snapshot: gross debit-side book value of the group at close.
    select coalesce(sum(g.amount_book) filter (where g.amount_book > 0), 0)
      into new.close_book_value
    from pfin.fn_gl_entries(current_date) g
    where g.journal_id = new.journal_id;
    new.closed_at := now();
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_journal_close_balance() from public;

comment on function pfin.fn_journal_close_balance() is
  'BEFORE UPDATE Sigma=0-at-close enforcement + snapshot writer on pfin.journal (037 / '
  'SELF-301; ADR-031 Decision 4/5/7; 033 M4-GL CONTRACT). SECURITY INVOKER (reads the '
  'group''s legs + writes the snapshot on the caller''s own journal row, under the caller''s '
  'RLS — no elevated privilege; not a DEFINER allowlist entry). On open->closed: first '
  'rejects any future-dated leg (ALL group_types — one "no closing a period with future-'
  'dated entries" rule, keeps every snapshot faithful; N1), then the group_type conservation '
  'law (transfer=Sum(amount)=0; transfer_in_kind=per-security Sum(quantity)=0; compound=NO '
  'Suspense residual [the literal total-Sigma is vacuous — self-balancing contras]), RAISE '
  'on failure, then writes close_book_value (gross debit book) + closed_at. On closed->open '
  '(reopen): nulls both (never re-values a standing snapshot). set search_path=''''.';

drop trigger if exists journal_close_balance on pfin.journal;
create trigger journal_close_balance
  before update on pfin.journal
  for each row execute function pfin.fn_journal_close_balance();

-- ----------------------------------------------------------------------------
-- COMPONENT 4 — membership-freeze-on-close guard on the 023 overlay. BEFORE INSERT OR
-- UPDATE OR DELETE. INVOKER. Rejects any write touching a CLOSED journal's legs (old or
-- new journal_id closed) → freezes membership + classification while closed; reopen to edit.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_annotation_freeze_closed()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_status text;
begin
  -- Attaching/writing a leg whose NEW target journal is closed → reject.
  if tg_op in ('INSERT', 'UPDATE') and new.journal_id is not null then
    select status into v_status from pfin.journal where journal_id = new.journal_id;
    if v_status = 'closed' then
      raise exception
        'cannot attach/modify an annotation for CLOSED journal % — reopen it first (037 membership-freeze; 033 C-i reopen).',
        new.journal_id;
    end if;
  end if;

  -- Detaching/deleting/editing a leg whose OLD target journal is closed → reject
  -- (freezes both membership and classification of a closed group's legs).
  if tg_op in ('UPDATE', 'DELETE') and old.journal_id is not null then
    select status into v_status from pfin.journal where journal_id = old.journal_id;
    if v_status = 'closed' then
      raise exception
        'cannot detach/modify an annotation of CLOSED journal % — reopen it first (037 membership-freeze; 033 C-i reopen).',
        old.journal_id;
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_freeze_closed() from public;

comment on function pfin.fn_account_trans_annotation_freeze_closed() is
  'BEFORE INSERT/UPDATE/DELETE membership-freeze guard on pfin.account_trans_annotation '
  '(037 / SELF-301; keeps close_book_value faithful). SECURITY INVOKER (reads '
  'pfin.journal.status, raises; not a DEFINER allowlist entry). Rejects any write where '
  'OLD.journal_id or NEW.journal_id is a CLOSED journal — freezes BOTH membership '
  '(journal_id) and classification (sub_cat_id/metadata) of a closed group''s legs so a '
  're-derived close Sigma matches the stored snapshot; reopen (status->open, which nulls '
  'the snapshot) to modify. NULL-safe (no journal_id → no-op). Reads the existing 023 '
  'journal_id FK''s target status — NOT a new Decision-3 FK. set search_path=''''.';

drop trigger if exists account_trans_annotation_freeze_closed on pfin.account_trans_annotation;
create trigger account_trans_annotation_freeze_closed
  before insert or update or delete on pfin.account_trans_annotation
  for each row execute function pfin.fn_account_trans_annotation_freeze_closed();
