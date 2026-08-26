-- ============================================================================
-- Migration: pfin.fn_account_trans_annotation_journaled_cat_fence (+ its trigger)
--   and pfin.fn_suggest_subcat_for_vendor — the SELF-248 §2.3.1.a classify
--   backend's two DB-layer pieces: the AC10 journaled-leg classification fence
--   and the AC7 recurring-vendor inference primitive.
-- Phase 6 Build Loop. SELF-248 AC7 / AC8 / AC10. Realizes the Sec (C'/C''/C''')
--   ruling recorded at the V1.3 pre-flight sitting item 15 (F/CTO-confirmed),
--   with Sec's binding conditions (1) (2) (4) (5) discharged in this file —
--   (3) is QA's paired pgTAP battery, (6) is the endpoint + frontend, (7) is
--   this PR's joint review.
-- Closes no SD/RT. Extends no lock. Adds no table, column, policy or grant on a
--   table; authors two functions and one trigger.
--
-- ----------------------------------------------------------------------------
-- Numbering: 092 follows 091 (posting_prototype.is_tax_payment); taken at
--   authoring time against the live listing, not reserved.
--   Order-dependent — must run AFTER:
--     004 pfin.account_trans (trans_id, vendor)
--     006 account_trans rd_access-JOIN RLS (the isolation this file's reader
--         composes with) + pfin.account_users
--     023 pfin.account_trans_annotation (the fenced table; sub_cat_id, updated_at)
--     033 account_trans_annotation.journal_id (the fence's second operand)
--     084 pfin.posting_prototype (the class the fence resolves) + the sub_cat_id
--         FK re-target + the ordered CASE this fence is derived from
--   Independent of 085–091. No later migration depends on 092 landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER for BOTH functions (default per ADR-011
--   Lock 11); NOT SECURITY DEFINER. The SECURITY DEFINER allowlist is UNCHANGED
--   by this file — read it live at ADR-011 Decision 9; this file states no count.
--
--   fn_account_trans_annotation_journaled_cat_fence: a BEFORE trigger fence needs
--     no elevated privilege. It reads exactly one relation — pfin.posting_prototype
--     — and the row it must resolve is one the writer already referenced on the
--     same write, so INVOKER's RLS-filtered read is the correct visibility and an
--     unresolvable row is a fail-closed raise (Sec condition (1)). This mirrors
--     fn_account_trans_annotation_trade_constraints (084), which resolves the same
--     relation the same way on the same table.
--   fn_suggest_subcat_for_vendor: a read helper whose entire isolation story is
--     the caller's own RLS context (Lock 11 read-composition; the 076 / 049 / 051
--     convention). DEFINER would make it a confused deputy over every tenant's
--     annotation history — the one posture that must not be chosen here.
--
--   Both carry `set search_path = ''`. Neither is granted to anon. No RLS policy
--   is added or altered, so no ADR-029 / 025 aal2 step-up obligation is triggered
--   — that obligation attaches to a NEW sensitive tenant-owned TABLE, and no
--   table is created here.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
--   the catalogued numbered list. Decision 4 was read VERBATIM before drafting.)
--   This migration introduces ZERO catalogued §10 instances.
--   (i)   Instance-numbering: untouched — no instance is added, reordered or
--         renumbered by this file.
--   (ii)  Layer-attribution: untouched. No infrastructure-credential-presence
--         surface, no code-layer service-role-key allowlist surface, and no
--         network-exposure/config surface is involved. This is authenticated-tier
--         trigger + read-helper DDL only, with no service_role grant and no
--         admission channel. No surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 092 is not
--         the canonical §10 anchor.
--   DE-CONFLATION GUARD: the AC10 fence below is a financial-correctness
--   (ADR-011 Decision 2) mechanism, NOT a §10 catalogued instance and NOT a
--   Decision-3 instance — the same separation 012 / 017 / 022 / 023 drew.
--
-- ----------------------------------------------------------------------------
-- ADR-011 DECISION 3 (cross-tenant FK-bypass family) — NO MOVE. This file adds
--   NO column of any kind, therefore no FK-shaped column, therefore no family
--   member. Read Decision 3's body live for the family's shape; this file states
--   no count. Both columns the fence reads (sub_cat_id, journal_id) are ALREADY
--   fenced members, by fn_account_trans_annotation_matched_sub_cat (023) and
--   fn_account_trans_annotation_matched_journal (033) respectively; this fence
--   composes with them and replaces neither.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--
--   pfin.fn_account_trans_annotation_journaled_cat_fence() RETURNS trigger
--     BEFORE INSERT OR UPDATE ON pfin.account_trans_annotation FOR EACH ROW
--     WHEN (new.sub_cat_id IS NOT NULL AND new.journal_id IS NOT NULL)
--     Enforces:  journal_id IS NOT NULL  =>  resolved posting_prototype.cat
--                NOT IN ('Revenue', 'Expense', 'Equity')
--     Security-load-bearing edges: unresolvable prototype => raise (never a
--       silent skip); the WHEN clause is a STATE predicate on NEW only, so both
--       reachability orders are closed; detach (new.journal_id NULL) is
--       WHEN-skipped and therefore never blocked.
--
--   pfin.fn_suggest_subcat_for_vendor(p_vendor text) RETURNS bigint
--     STABLE, SECURITY INVOKER, no tenant parameter.
--     Returns the sub_cat_id of the most recently EDITED annotation on a prior
--       transaction whose vendor matches p_vendor case-insensitively after
--       trimming; NULL when there is no such history (AC8).
--     Security-load-bearing edges: the account_users conjunct is what makes the
--       vendor-string join fail CLOSED (see its own note below); a blank or NULL
--       p_vendor returns NULL rather than matching blank vendors.
--
-- ----------------------------------------------------------------------------
-- WHY THE INVARIANT IS "NOT IN (Revenue, Expense, Equity)" AND NOT "= Transfer".
--
--   084's P3 contra branch (084:865-882) resolves a standard cash-flow leg's
--   contra account through an ORDERED CASE: Revenue -> Expense -> Equity ->
--   (Transfer AND journal_id IS NOT NULL) -> else Suspense. A journaled leg
--   reaches 'Journal Clearing' ONLY by falling through the first three arms.
--   The refused set is therefore exactly that fall-through set — DERIVED from the
--   defect, not chosen — which is what lets this fence explain itself to a reader
--   who has 084 in front of them.
--
--   ⚠ "Refuse a non-Transfer cat when journaled" is the naive formulation and it
--   is WRONG: a transfer_in_kind journal's legs are security rows, and 084:1233's
--   biconditional (security_id present <=> cat = 'Trade') FORCES them to
--   cat = 'Trade'. That formulation would refuse every in-kind transfer.
--   'Trade' and 'Transfer' both pass here, deliberately.
--
-- ----------------------------------------------------------------------------
-- WHY THE WHEN CLAUSE IS A STATE PREDICATE ON NEW AND NEVER A TRANSITION GUARD.
--
--   A transition-scoped WHEN (new.sub_cat_id IS DISTINCT FROM old.sub_cat_id) is
--   doubly wrong here. It CANNOT be written at all on an INSERT OR UPDATE trigger
--   (OLD is not available in the WHEN of an INSERT), and even on UPDATE alone it
--   leaves one of the two reachability orders open:
--     attach-then-classify -> sub_cat_id changes -> fires  -> refused
--     classify-then-attach -> only journal_id changes -> DOES NOT FIRE -> the
--                             defect state is reached
--   The state predicate closes both, because it asks what the row WILL BE rather
--   than what changed. It also means an unrelated edit (a note change) on an
--   already-valid row fires and passes, which is correct and cheap: the fence is
--   an invariant on the row, not a gate on an operation.
--
-- ----------------------------------------------------------------------------
-- WHY M1 AND M4 STAY APP-LAYER, AND WHY THAT IS NOT AN OMISSION (Sec cond. (5)).
--
--   The S-1 classifiability predicate has four mechanical rules. Only M3 is
--   fenced here, and the reason is measured, not stylistic — it is 084's P3
--   WHERE clause at 084:885-886:
--       where t.transaction_type = 'standard' and t.security_id is null
--         and t.split_count = 0 and t.amount <> 0
--   M1 (transaction_type <> 'standard') and M4 (split_count > 0) are excluded by
--   that WHERE, so a prototype classification on such a row is NEVER READ by the
--   GL: writing one is inert, and a DB fence over it would refuse a write that
--   costs nothing. M2 (security_id IS NOT NULL) is already fenced, by 084's
--   biconditional. M3 alone is BOTH admitted by the WHERE and mis-resolved by the
--   CASE — the leg posts as spending, silently, with a real dollar figure.
--   ⚠ So: this fence is NOT an incomplete implementation of classifiable(). Do
--   not "complete" it by adding M1/M4 legs, and do not delete it as arbitrary.
--   The app-layer guard (SELF-248 AC4) still refuses all four rules in full; this
--   fence exists because M3, and only M3, is a money defect if the app is bypassed.
--
--   ⚠ KNOWN RESIDUAL, stated so it is not mistaken for coverage: 084's P4
--   split-child branch (084:889-911) resolves each CHILD's cat through the same
--   ordered CASE while taking journal_id from the PARENT (t.journal_id), so the
--   identical defect exists at the split-child grain — and this trigger cannot
--   see it, because the child's category lives on pfin.account_trans_split, not
--   on this table. A split parent's own annotation typically carries a NULL
--   sub_cat_id (M4 refuses classifying it), so this trigger's WHEN does not even
--   fire on that row. Fencing the child grain is a separate surface and a
--   separate Sec call; it is deliberately NOT attempted here.
--
-- ----------------------------------------------------------------------------
-- FIRING ORDER, stated so it is not mistaken for a dependency. Postgres fires
--   BEFORE row triggers in NAME order, so this fence runs after
--   ..._freeze_closed and before ..._matched_journal / ..._matched_sub_cat /
--   ..._trade_constraints. That ORDER IS NOT LOAD-BEARING: every one of those
--   fences is fail-closed, so any order refuses the same set of writes. What the
--   order decides is only WHICH refusal message surfaces first — a write carrying
--   a cross-tenant sub_cat_id together with a journal_id will report this fence's
--   "cannot resolve class" rather than the #10 matched-tenant message. Both are
--   refusals. Do not rename any trigger to "fix" this believing correctness rides
--   on it, and do not build anything that assumes the order.
--
-- ----------------------------------------------------------------------------
-- EXISTING-VIOLATION MEASUREMENT (Sec binding condition (4)) — recorded here
--   because the count is the precondition for landing the fence at all, and a
--   PR body is not where a future reader looks.
--   Measured 2026-08-25 against the local Supabase stack (the only database
--   holding rows in this greenfield project; migrations 001-089 applied there):
--     rows with journal_id IS NOT NULL and resolved cat IN
--       ('Revenue','Expense','Equity')                                     = 0
--     annotations with journal_id IS NOT NULL (any classification)         = 0
--     annotations with journal_id IS NOT NULL and an UNRESOLVABLE prototype = 0
--     annotation rows total                                                = 6
--   Zero violations, so the fence lands without a data remediation.
--   The query, recorded here rather than in the PR body because a PR body is not
--   where a future reader looks and a re-measurement must be reproducible:
--     select count(*)
--       from pfin.account_trans_annotation ann
--       join pfin.posting_prototype pp on pp.id = ann.sub_cat_id
--      where ann.journal_id is not null
--        and pp.cat in ('Revenue', 'Expense', 'Equity');
--   ⚠ Read with its companion figures above, which are what make the 0 ROBUST: the
--   violating set is a SUBSET of `journal_id is not null`, and that count is also 0
--   over a 6-row table — so the primary number does not depend on the join half of
--   this query being written correctly. Re-measure both together, never the first
--   alone.
--
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- (1) AC10 — the journaled-leg classification fence.
-- ----------------------------------------------------------------------------

create or replace function pfin.fn_account_trans_annotation_journaled_cat_fence()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_cat   text;
begin
  -- The trigger WHEN clause guarantees BOTH new.sub_cat_id IS NOT NULL and
  -- new.journal_id IS NOT NULL, so this body never runs on an unclassified leg
  -- (NULL cat -> Suspense downstream, which is correct) nor on a detach.

  -- Resolve the CLASS (the posting vocabulary, 084). posting_prototype.cat is
  -- NOT NULL, so v_cat is non-null whenever v_found is true. A cross-tenant
  -- sub_cat_id is separately rejected by the #10 matched-tenant fence firing on
  -- the same write; under INVOKER this read sees only the caller's own rows.
  select true, pp.cat
    into v_found, v_cat
    from pfin.posting_prototype pp
   where pp.id = new.sub_cat_id;

  -- NULL-SAFE FAIL-CLOSED (Sec binding condition (1)): a missing or
  -- not-currently-visible prototype row raises. Never a silent skip — a skip
  -- here would let exactly the write this fence exists to refuse through, on the
  -- one input the fence cannot evaluate.
  if v_found is null then
    raise exception
      'journaled-leg classification fence: cannot resolve class (sub_cat_id %) for trans_id % attached to journal % — not found or not visible under current AAL; fail-closed (SELF-248 AC10)',
      new.sub_cat_id, new.trans_id, new.journal_id;
  end if;

  -- THE INVARIANT. The refused set is 084's P3 ordered-CASE fall-through set
  -- (084:869-872): a leg reaching those arms posts to Revenue / Expense / Equity
  -- instead of Journal Clearing, which double-counts a transfer as income or
  -- spending. 'Transfer' and 'Trade' pass — see the header note on why the naive
  -- "must be Transfer" formulation would refuse every in-kind transfer.
  if v_cat in ('Revenue', 'Expense', 'Equity') then
    raise exception
      'journaled-leg classification rejected: trans_id % is attached to journal % and so cannot carry a % classification (sub_cat_id %) — a journaled leg must post to Journal Clearing, and this class would post it as income or spending instead. Reclassify the leg (Transfer or Trade), or detach it from the journal first (SELF-248 AC10 / ADR-058 084 P3)',
      new.trans_id, new.journal_id, v_cat, new.sub_cat_id;
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_journaled_cat_fence() from public;

comment on function pfin.fn_account_trans_annotation_journaled_cat_fence() is
  'BEFORE INSERT OR UPDATE financial-correctness fence on '
  'pfin.account_trans_annotation (ADR-011 Decision 2 surface; SELF-248 AC10; Sec '
  'ruling C''/C''''/C'''''' as confirmed at the V1.3 pre-flight sitting item 15). '
  'INVARIANT: journal_id IS NOT NULL implies the resolved posting_prototype.cat is '
  'NOT IN (''Revenue'', ''Expense'', ''Equity''). That refused set is DERIVED, not '
  'chosen: it is exactly the fall-through set of the ordered CASE in fn_gl_entries'' '
  'P3 contra branch (084), where a journaled leg reaches ''Journal Clearing'' only '
  'by falling past those three arms — so a journaled leg carrying one of them posts '
  'as income or spending and double-counts a transfer, silently, with a real dollar '
  'figure. ⚠ NOT the naive "must be Transfer": a transfer_in_kind journal''s legs '
  'are security rows forced to cat=''Trade'' by the 084 biconditional (security_id '
  'present <=> cat=''Trade''), so that formulation would refuse every in-kind '
  'transfer. ''Trade'' and ''Transfer'' both pass. SCOPING: the trigger WHEN is a '
  'STATE predicate on NEW (new.sub_cat_id IS NOT NULL AND new.journal_id IS NOT '
  'NULL) and references no OLD — a transition-scoped WHEN cannot be written on an '
  'INSERT OR UPDATE trigger at all, and would leave classify-then-attach open '
  '(that order changes only journal_id, so it would never fire). Both reachability '
  'orders are closed. Detach is WHEN-skipped and never blocked. NULL-safe '
  'fail-closed: an unresolvable or not-currently-visible prototype raises, never a '
  'silent skip. SECURITY INVOKER + set search_path='''' — no DEFINER; the '
  'ADR-011 Decision 9 allowlist is unmoved by this function (read it live). ⚠ WHY '
  'THIS FENCES ONLY M3 OF THE FOUR classifiable() RULES, so that a later reader '
  'neither completes it nor deletes it as arbitrary: M1 (transaction_type <> '
  '''standard'') and M4 (split_count > 0) are EXCLUDED BY THE P3 WHERE CLAUSE in '
  '084, so a classification on such a row is never read by the GL and writing one '
  'is inert; M2 (security_id IS NOT NULL) is already fenced by the 084 '
  'biconditional. M3 alone is both admitted by that WHERE and mis-resolved by the '
  'CASE. The app-layer guard (SELF-248 AC4) still refuses all four rules in full; '
  'this fence exists because M3, and only M3, is a money defect when the app is '
  'bypassed — and pfin.account_trans_annotation carries a table-level authenticated '
  'UPDATE grant (023) on a Data-API-exposed schema, so paths other than that '
  'endpoint reach this column. ⚠ KNOWN RESIDUAL, not coverage: 084''s P4 '
  'split-child branch runs the same ordered CASE over each CHILD''s cat while '
  'taking journal_id from the PARENT, so the identical defect exists at the '
  'split-child grain and is OUT OF REACH of this trigger — the child''s category '
  'lives on pfin.account_trans_split, not on this table. Fencing that grain is a '
  'separate surface and a separate Sec call. UX consequence, stated because it is '
  'user-visible: attaching a journal to an already-Revenue/Expense/Equity-classified '
  'leg now FAILS, and the remedy is reclassify-then-attach.';

drop trigger if exists account_trans_annotation_journaled_cat_fence
  on pfin.account_trans_annotation;

create trigger account_trans_annotation_journaled_cat_fence
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.sub_cat_id is not null and new.journal_id is not null)
  execute function pfin.fn_account_trans_annotation_journaled_cat_fence();

-- ----------------------------------------------------------------------------
-- (2) AC7 / AC8 — the recurring-vendor inference primitive.
--
-- WHY THE account_users CONJUNCT IS HERE even though pfin.account_trans already
--   carries an rd_access-JOIN SELECT policy (006) that says the same thing.
--   It is about the FAILURE DIRECTION of this particular join, not about a
--   preference for explicit over inherited fences.
--   The join key is p_vendor — a SHARED-VOCABULARY STRING. 'AMAZON' is not
--   tenant-scoped: the same literal exists in every tenant's ledger. If the RLS
--   on pfin.account_trans ever regressed, a surrogate-id join would return
--   nothing (fail closed), but THIS join would start matching other tenants'
--   transactions and returning their prototype ids — fail OPEN, and silently,
--   because a plausible id is indistinguishable from a correct one at the call
--   site. The conjunct is deliberately redundant with account_trans_select TODAY;
--   what it buys is that the redundancy is what keeps the failure closed.
--   It adds NO tenant parameter (AC7): auth.uid() is the caller's own session.
-- ----------------------------------------------------------------------------

create or replace function pfin.fn_suggest_subcat_for_vendor(p_vendor text)
returns bigint
language sql
security invoker
stable
set search_path = ''
as $$
  select ann.sub_cat_id
  from pfin.account_trans_annotation ann
  join pfin.account_trans t
    on t.trans_id = ann.trans_id
  join pfin.account_users au
    on au.account_id = t.account_id
   and au.users_id   = auth.uid()
   and au.rd_access
  where ann.sub_cat_id is not null
    and p_vendor is not null
    and btrim(p_vendor) <> ''
    and t.vendor is not null
    and lower(btrim(t.vendor)) = lower(btrim(p_vendor))
  order by ann.updated_at desc, ann.trans_id desc
  limit 1
$$;

revoke execute on function pfin.fn_suggest_subcat_for_vendor(text) from public;
grant  execute on function pfin.fn_suggest_subcat_for_vendor(text) to authenticated;

comment on function pfin.fn_suggest_subcat_for_vendor(text) is
  'Recurring-vendor Sub-Cat suggestion primitive (PRD §2.3.1.a; SELF-248 AC7/AC8). '
  'Returns the sub_cat_id (a pfin.posting_prototype id, bigint) of the most '
  'recently updated annotation on a prior transaction whose vendor matches '
  'p_vendor, or NULL when there is no such history. SECURITY INVOKER + STABLE + '
  'set search_path='''' with NO tenant parameter — isolation is the caller''s '
  'own RLS context (Lock 11 read-composition; the 076 / 049 / 051 convention), and '
  'pfin.account_trans carries no users_id to pass. MATCHING IS DEFINED, NOT '
  'IMPLIED (the AC requires the rule be stated): exact, case-insensitive, on the '
  'TRIMMED vendor string on both sides — lower(btrim(...)) — and NOTHING FURTHER. '
  'Internal whitespace, punctuation, and merchant-id suffixes are NOT normalized '
  'in V1, so ''AMZN Mktp US*2K4TH'' and ''AMZN Mktp US*9QB1L'' are different '
  'vendors here. That is a deliberate V1 bound: fuzzy vendor matching is a product '
  'decision with its own false-positive cost, and a suggestion that is confidently '
  'wrong is worse than absent. A NULL or blank-after-trim p_vendor returns NULL '
  'rather than matching every blank-vendor row. ⚠ RECENCY IS BY ann.updated_at, '
  'which pfin.fn_refresh_updated_at (023 trigger) refreshes on ANY update to the '
  'annotation row — a note edit or a journal attach moves it too. So this is '
  '"most recently EDITED annotation", not "most recently RECLASSIFIED"; '
  'pfin.reclass_history (031) is where a stricter reclassification recency would '
  'come from if one is ever wanted. Ties broken by trans_id desc so the result is '
  'deterministic. ⚠ ADVISORY ONLY: this applies NO classifiability filter and '
  'makes NO write. It can suggest a prototype that the SELF-248 write path then '
  'refuses (for example on a journaled leg, per '
  'fn_account_trans_annotation_journaled_cat_fence) — the suggestion is a hint for '
  'the UI, and every rule that decides what may be STORED lives on the write path '
  'and its triggers. The account_users conjunct in the body is deliberately '
  'redundant with the 006 account_trans SELECT policy: the join key is a '
  'shared-vocabulary vendor STRING, so an RLS regression would fail OPEN here '
  '(matching another tenant''s rows) where a surrogate-id join would fail closed. '
  'Do not remove it as duplication.';
