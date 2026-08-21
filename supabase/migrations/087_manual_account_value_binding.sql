-- ============================================================================
-- Migration: pfin.fn_create_manual_account — CREATE-TIME VALUE BINDING.
-- Extends the manual-account write-composition RPC so a manual account's opening
-- value can be bound to real pfin.asset instruments at create time, instead of
-- landing entirely as unbound cash.
-- Phase 6 Build Loop. SELF-325. F/CTO-ratified 2026-08-21 (Option 2 of the
-- Architect design pass; classify-after-create is F/CTO's Option B product ruling).
-- Closes no SD/RT; extends no lock.
--
-- ----------------------------------------------------------------------------
-- THE DEFECT. Post-048, fn_create_manual_account writes ONE acct_setup row with
--   security_id NULL. The account's whole value is therefore CASH — bound to no
--   instrument, invisible to the allocation surface, and unreachable by the
--   classify UI (which lists only ever-transacted securities). A user who enters
--   a $450,000 house gets $450,000 of cash.
--
-- WHAT THIS MIGRATION IS NOT. It adds NO table, NO column, NO FK-shaped
--   reference, NO trigger, NO policy, NO grant, and NO SECURITY DEFINER function.
--   The substrate it needs already exists in full; the gap was composition. In
--   particular the GL already models an acct_setup row that carries a position —
--   084 P2 (position book add: security_id NOT NULL + cost_basis <> 0) and 084 P5
--   (Opening-Balance-Equity contra, -(amount + cost_basis)). This migration writes
--   rows that branch set was already written for. The opening-balance / purchase
--   provenance distinction it encodes is load-bearing and is preserved exactly:
--   an OPENING position is transaction_type='acct_setup' with amount=0 (no cash
--   moved, Opening-Balance-Equity contra); a PURCHASE is transaction_type=
--   'standard' with amount=-cost (cash moved, no contra — P1+P2 balance alone).
--   ⚠ This migration does not author the purchase path. That is a separate,
--   unresolved scope question (038's fn_create_manual_trans hard-codes
--   transaction_type='standard' AND security_id NULL, so it cannot carry an
--   instrument) and it is deliberately OUT of this migration.
--
-- ----------------------------------------------------------------------------
-- THREE PROPERTIES THE BODY ENFORCES, each of which produces SILENTLY WRONG MONEY
-- if it is ever dropped. They are stated here because the reasons live in other
-- files and a future editor of THIS body would not otherwise meet them.
--
--   (F1) THE CASH REMAINDER ROW CARRIES security_id NULL — it is NOT bound to the
--        global USD currency-asset, and an 'currency' asset_type is REJECTED in
--        the positions payload. Three independent reasons:
--          (i)   056 fn_account_cash_as_of sums EVERY account_trans.amount for the
--                account with NO security_id filter. Cash is amount-carried, never
--                instrument-carried; binding it changes the cash figure by nothing.
--          (ii)  081 fn_subcat_market_value's cash leg already routes cash
--                CLASSIFICATION through the GLOBAL currency-asset's per-user 022
--                junction row. "Instrument-routed cash" is a classification-layer
--                model and is already in place; it is not a ledger-layer model.
--          (iii) A cash row bound to USD would make USD appear in the classify
--                pending queue (api/src/lib/server/queries/pendingSymbols.ts
--                derives pending as ever-transacted security_id MINUS classified),
--                i.e. it would ask the user to classify their cash.
--
--   (F2) EVERY INSTRUMENT-BOUND acct_setup ROW CARRIES amount = 0. 056 sums amount
--        unconditionally (F1(i)) and 019 fn_holdings_as_of rolls quantity by
--        security_id, so a row carrying BOTH a nonzero amount AND a quantity is
--        counted as cash AND as a position — the opening value, twice.
--        ⚠ NOTHING IN THE DDL PREVENTS THE WRONG SHAPE. A CHECK was considered and
--        deliberately NOT taken (F/CTO 2026-08-21, standing by the Architect
--        sub-decision): the hazard is real but the DDL commitment on an immutable
--        table is not yet earned, and a CHECK here would foreclose an opening row
--        that is simultaneously a position and a cash movement. The observer is a
--        paired QA battery leg asserting fn_account_cash_as_of == the cash
--        remainder alone, and SUM(fn_subcat_market_value) == fn_compute_nav.
--        That leg IS the fence. If it is ever deleted, this property is unwatched.
--
--   (F3) EVERY INSTRUMENT-BOUND POSITION ALSO WRITES ITS eod_price ROW. 049
--        fn_account_unrealized_gl and 050 fn_compute_nav value a position as
--        quantity x eod_price x fx; an UNPRICED asset yields a NULL term which SUM
--        drops. Binding an opening value to an asset with no price row therefore
--        contributes ZERO to NAV — silently, with no error and no log line — where
--        the same value as unbound cash contributed in full. The price written is
--        round(cost_basis / quantity, 4), source='manual_valuation', price_date =
--        p_as_of_date, which is reachable by the caller under 019's existing
--        eod_price_insert policy (manual_valuation on an asset they own).
--        ⚠ (F3) HAS TWO SPELLINGS AND THIS BULLET ORIGINALLY NAMED ONLY ONE.
--        A MISSING price row is the obvious one. A price row that EXISTS but is
--        ZERO produces the identical silent-zero-NAV outcome, and it defeats any
--        watcher that checks for row PRESENCE rather than row VALUE. Sec found
--        that second spelling at the SELF-325 joint review; see the ZERO-ROUNDED
--        PRICE block below for the reachable input, the fence, and the bound.
--
-- ----------------------------------------------------------------------------
-- ROUNDING ARTIFACT, stated rather than hidden — AND ITS BOUND CORRECTED. Sec,
--   at the SELF-325 joint review. eod_price.price and account_trans.price are
--   numeric(20,4), so round(cost_basis/quantity, 4) can be inexact against the
--   basis: cost_basis=100 over quantity=3 gives 33.3333, and 33.3333 x 3 =
--   99.9999. A position's opening MARKET value can therefore differ from its
--   COST BASIS.
--   ⚠ AN EARLIER DRAFT OF THIS BLOCK CALLED THAT DIFFERENCE "sub-cent amounts".
--   THAT IS WRONG AT SCALE and wrong in the direction that understates. The
--   per-unit rounding error is up to 0.00005, so the position-level error is
--   bounded by QUANTITY x 0.00005 — a cent only up to quantity ~= 200, and
--   $50.00 at quantity 1,000,000. MEASURED. The artifact is inherent to the
--   price grain (019), not introduced here, and it is why the paired battery
--   uses exactly divisible fixture values rather than a tolerance.
--
-- ZERO-ROUNDED PRICE — Sec's BLOCKING finding at the SELF-325 joint review, and
--   it is (F3) re-entering through a spelling (F3)'s own watcher could not see.
--   When quantity > 20000 x cost_basis the quotient falls below 0.00005 and
--   round(...,4) yields EXACTLY 0.0000 — a perfectly legal eod_price row, since
--   019's only CHECK on price is the NaN fence. The position then values at
--   quantity x 0 = ZERO: the account's bound value vanishes from NAV silently,
--   which is precisely the failure (F3) exists to prevent. The (F3) watcher
--   asserted a price row EXISTS, and one does — it is just worthless.
--   REPRODUCED before fixing: quantity 1000000, cost_basis 10.00 passes every
--   guard in this body, writes price 0.0000, and fn_account_unrealized_gl
--   reports current_market_value 0.0000 for a position whose basis is $10.
--   The body now REJECTS that input (see statement (3b)). Scope of the fix is
--   the body only — no new column, CHECK, trigger, policy or grant, and no
--   change to 017 or 019.
--
-- ----------------------------------------------------------------------------
-- Numbering: 087 follows 086 (fn_subcat_contributors); taken at authoring time
--   against the live listing (git ls-tree origin/main), not reserved.
--   Order-dependent on: 003 (pfin.account; the AFTER INSERT fn_grant_creator_access
--   trigger whose same-txn creator-grant row satisfies 006's write policy) · 006
--   (account_trans grant + the wr_access-JOIN INSERT policy) · 015 (account.currency,
--   copied onto the created asset so the 049/050 fx term resolves consistently) ·
--   016 (pfin.asset, its grants, its hybrid RLS, the asset_type + pricing_source
--   CHECK vocabs, and asset_user_name_uniq) · 017 (security_id / quantity /
--   cost_basis / price columns, the Decision-3 #7 fence, the NaN CHECKs and
--   account_trans_qty_requires_security) · 019 (pfin.eod_price, its grants and its
--   manual_valuation-on-owned write policy) · 030 (acct_setup in the
--   transaction_type vocab) · 048 (the 6-arg signature replaced here).
--   Consumed by 084 (the live GL branch set) and 019/049/050/081 (valuation).
--   No later migration depends on 087.
--
-- DEPLOY-ORDERING NOTE — ⚠ THE DIRECTION IS THE OPPOSITE OF 048's, and 048's note
--   must not be carried across by analogy. 048 REMOVED a parameter, so
--   migration-first was the breaking direction. 087 ADDS one WITH A DEFAULT, so an
--   existing 6-named-arg PostgREST call satisfies the 7-arg function unchanged:
--   MIGRATION-FIRST IS BACKWARD-COMPATIBLE. The app change may land before, with,
--   or after this migration. (App-change-first is the breaking direction here — a
--   7-named-arg call against the still-6-arg function would 404.)
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER, and it needs no elevation.
--   Every write this body performs is reachable by the owner under an EXISTING
--   policy, evaluated as the caller: pfin.account via account_insert WITH CHECK
--   (users_id = auth.uid()) (003) · pfin.account_trans via account_trans_insert's
--   wr_access-JOIN (006), satisfied inside this same transaction by the
--   fn_grant_creator_access creator-grant row (003) · pfin.asset via asset_insert
--   WITH CHECK (users_id = auth.uid()) (016) · pfin.eod_price via eod_price_insert,
--   which admits ONLY source='manual_valuation' on an asset the caller owns (019).
--   This is the Lock 11 INVOKER write-composition shape, unchanged from 013 / 048.
--   NOT a SECURITY DEFINER allowlist entry — this file states no allowlist count;
--   read ADR-011 Decision 9 live.
--   `set search_path = ''` is the injection fence; every reference is schema-
--   qualified. EXECUTE revoked from PUBLIC (which denies anon) and granted to
--   authenticated only.
--
--   ⚠ DEVIATION FROM 048 — a new auth.uid() IS NULL guard. It is DEFENSE IN
--   DEPTH over an ALREADY-CLOSED path, and this paragraph is a CORRECTION of an
--   earlier draft of this same file that claimed more.
--     WHAT THE EARLIER DRAFT CLAIMED, AND WHY IT WAS WRONG: it said an RLS-EXEMPT
--     caller with no JWT reaching this body "would mint GLOBAL market-security
--     rows out of user-supplied names", on the ground that pfin.asset.users_id is
--     NULLABLE and a NULL there means GLOBAL (016's hybrid posture: readable by
--     every tenant, inside the asset_global_symbol_uniq dedup namespace). That
--     premise about pfin.asset is TRUE. The conclusion is FALSE, because the
--     caller never reaches the asset INSERT: pfin.account.users_id is NOT NULL,
--     so statement (1) already fails with 23502 (null value in column "users_id"
--     of relation "account"). MEASURED, not reasoned — by removing this guard
--     from a copy of the function and calling it as an RLS-exempt role with no
--     claims set. The path was closed before this guard existed.
--     WHAT THE GUARD IS ACTUALLY WORTH, stated honestly because the overclaim
--     above is exactly the kind of thing that gets a fence accepted for the wrong
--     reason: (i) it fails EARLY and LEGIBLY — a named error naming the cause,
--     instead of a NOT NULL violation three statements deep whose message points
--     at a column rather than at the missing caller context; and (ii) it pins the
--     requirement LOCALLY, in the function whose whole security model is
--     "evaluate as the caller", rather than leaving it to depend on another
--     table's column staying NOT NULL. An assertion that rests on a distant
--     property is worth restating where it is relied upon.
--     THE LOSING SIDE, corrected: NONE that was ever exercisable. The earlier
--     draft told Sec that an RLS-exempt caller COULD invoke this RPC before 087
--     and cannot after. Measured, such a caller — with no auth context — could
--     not successfully invoke it before either. The guard changes the ERROR, not
--     the OUTCOME. ⚠ And it does NOT reach an RLS-exempt caller that DOES set a
--     JWT claim (the ADR-023 impersonate-then-write shape): auth.uid() is
--     non-NULL there, so that path is unaffected in both directions.
--
-- ----------------------------------------------------------------------------
-- LOCK 14 ADVERSARIAL-NUMERIC POSTURE — WHICH GUARD ACTUALLY OBSERVES WHICH INPUT.
--   The positions payload carries user-supplied numerics, so the Lock 14 numeric
--   battery obligation applies. This block states which layer rejects what,
--   because a body-guard that CANNOT FIRE must not be described as the observer:
--     - "NaN" / "Infinity" / "-Infinity" / "$1,000" / "1.000,50" / any quoted
--       number  ->  rejected by the jsonb_typeof(...) = 'number' TYPE CHECK. JSON
--       has no NaN or Infinity literal, so these arrive as STRINGS. The type check
--       is their sole observer.
--     - 0 and negative values  ->  rejected by the `<= 0` disjunct.
--     - 1e400 and other finite-but-huge magnitudes  ->  NOT rejected by this body.
--       jsonb stores them as numeric and they are finite, so they pass every guard
--       here and are rejected by numeric(28,8) / numeric(20,4) COLUMN COERCION
--       (017). That rejection is real and role-agnostic; only its message is less
--       specific. Stated so a battery leg asserts rejection rather than a message.
--     - The `= 'NaN'::numeric` and `>= 'Infinity'::numeric` disjuncts below are
--       therefore UNREACHABLE THROUGH jsonb. They are retained as belt-and-braces
--       guards on the numeric local — not as the observer for that input class —
--       and this comment is the record that they are not load-bearing today.
--   ⚠ The trap they exist against, measured in this repo before: `'NaN'::numeric
--   > 0` is TRUE (numeric NaN sorts above every number), so a positivity check
--   ALONE re-admits NaN and Infinity. The four disjuncts are named separately for
--   that reason and must not be collapsed into one.
--
-- ----------------------------------------------------------------------------
-- SINGLE AUTHORITY FOR VOCABULARY AND UNIQUENESS — deliberately NOT re-stated here.
--   asset_type is validated by 016's own CHECK, not by a copy in this body; a copy
--   would be a second list to keep in step. The ONE exception is 'currency', which
--   016 legitimately admits and F1 forbids, so it is rejected explicitly and the
--   asymmetry is stated rather than left to look like an oversight.
--   Duplicate position names within one payload are rejected by
--   asset_user_name_uniq (016), not by a pre-check here — same reason.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — UNCHANGED. NO LABEL TAKEN.
--   ADR-011 Decision 3 read live from DECISIONS.md before drafting, per its own
--   rule. This migration creates, alters and drops NO COLUMN of any kind, FK-shaped
--   or otherwise, and no INTEGER[]. The FK-shaped columns it WRITES THROUGH are
--   existing DDL-realized instances, exercised rather than extended:
--     - account_trans.security_id -> pfin.asset  (#7, 017, Pattern 2 novel
--       global-OR-matched-tenant; BEFORE INSERT; tenant resolved via the account
--       chain). It fires on every position row this body inserts.
--     - user_asset_category.asset_id -> pfin.asset (#9, 022, Pattern 2) and
--       .sub_cat_id -> pfin.user_taxonomy (#8, 022, Pattern 1) fire later, when the
--       user classifies the asset through the existing classify surface — a path
--       this migration does not touch.
--   pfin.asset.users_id -> auth.users(id) is that table's TENANT ANCHOR, not a
--   cross-tenant reference.
--   ⚠ ON THE jsonb ARGUMENT: p_positions is a TRANSIENT ARGUMENT, not a stored
--   column, and it carries NO ids at all — it names assets to CREATE. ADR-056's
--   rejection of a STORED jsonb key-set (FK-shaped in substance while being no
--   column Decision 3 can fence) does not reach it: nothing is persisted as jsonb,
--   and the only FK-shaped value in play (v_asset_id) is minted inside this
--   transaction and lands in a real, fenced column in the next statement.
--   ⚠ A CONSEQUENCE WORTH STATING: because the RPC MINTS the asset rather than
--   accepting an asset_id, cross-tenant binding is unreachable THROUGH THIS PATH by
--   construction. #7 is not thereby weakened and is not removed — it still guards
--   the direct-INSERT path — but it can no longer FAIL here, so the paired battery
--   asserts its continued presence structurally (pg_trigger) rather than
--   behaviourally. An unreachable fence with no structural observer is how a fence
--   quietly disappears.
--   Read Decision 3's body live at authoring time: the family GROWS, its labels are
--   NON-CONTIGUOUS, at least one is DROPPED, and *labeled* vs *DDL-realized*
--   diverge. NO COUNT IS CARRIED IN THIS FILE.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (ADR-011 Decision 4 read VERBATIM and LIVE before
-- drafting, 2026-08-21). Path B — Decision 4 is LINKED, not restated; the
-- catalogued numbered list is NOT reproduced here and NO count is carried.
--   (i)   Instance-numbering: no catalogued instance is added, removed, reordered
--         or renumbered by this migration.
--   (ii)  Layer-attribution: no catalogued instance is re-attributed, and no
--         surface becomes "four-layer". This is authenticated-tier INVOKER
--         write-composition; it touches no container-credential surface, no
--         service_role key allowlist, and no network-admission surface. The create
--         path uses NO service_role.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is referenced, never restated.
--   LOCK 14 CLASS MEMBERSHIP: the manual-account create form is a user-facing
--   direct-DB-write surface and its numeric inputs inherit the Lock 14 adversarial
--   -numeric battery obligation (see the posture block above). CLASS MEMBERSHIP IS
--   NOT A CATALOGUED INSTANCE — that ruling is ADR-042's, in its Consequences.
--   ⚠ It is NOT ADR-047's; that pairing is the false-composite citation ADR-011
--   Decision 4's own attribution CHANGELOG records, and it is not reproduced here.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED set are DIFFERENT SETS and are not
--   reconciled here or anywhere.
--
-- ----------------------------------------------------------------------------
-- CONTRACT (post-087)
--   pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--     p_tax_treatment text, p_initial_value numeric, p_as_of_date date,
--     p_positions jsonb DEFAULT '[]'::jsonb) RETURNS bigint
--     SECURITY INVOKER, set search_path = ''. ONE transaction, all-or-nothing.
--   p_initial_value is the CASH REMAINDER ONLY (F1) — it is NOT the account total
--     when positions are supplied. The caller computes the split.
--   p_positions element shape (extra keys are IGNORED here; app-layer Zod .strict()
--     is what rejects them):
--       asset_type  JSON string, in 016's vocab, NOT 'currency' (F1)
--       name        JSON string, non-empty after btrim; unique per user (016)
--       symbol      JSON string or null; OPTIONAL
--       quantity    JSON number, > 0
--       cost_basis  JSON number, > 0
--   Rows written, in one transaction:
--     1 x pfin.account (users_id NOT a parameter — DEFAULT auth.uid(), un-forgeable)
--     1 x pfin.account_trans  acct_setup, amount=p_initial_value, security_id NULL
--     per position: 1 x pfin.asset (users_id = the caller, pricing_source=
--       'manual_valuation', currency copied from the account)
--                   1 x pfin.eod_price (manual_valuation, p_as_of_date,
--                       round(cost_basis/quantity, 4))
--                   1 x pfin.account_trans (acct_setup, amount=0, security_id,
--                       quantity, cost_basis, price)
--   p_positions omitted, '[]', JSON null, or SQL NULL -> the body executes exactly
--     048's two statements and returns. THE $0 / ZERO-HOLDINGS PATH IS UNCHANGED,
--     not merely permitted: instrument binding is optional, so an acquisition can
--     instead be recorded later as a real purchase rather than asserted as an
--     opening balance.
--   RETURNS the new account_id. Raises (and rolls the whole transaction back, so no
--     orphan account survives) on: an unauthenticated caller; a non-array
--     p_positions; a non-object element; a missing/mistyped/empty field; asset_type
--     'currency'; quantity or cost_basis <= 0. Magnitude overflow is rejected
--     downstream by column coercion (see the Lock 14 block).
--   Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed) — the
--     6-arg signature is REPLACED by this 7-arg one. Adding the parameter WITH A
--     DEFAULT keeps existing 6-named-arg call sites working (see the deploy note).
--   Same-transaction audit-log still DEFERRED (A2; forward-hook retained in body;
--     SELF-201 Task #7).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- Replace the 6-arg signature. CREATE OR REPLACE cannot ADD a parameter to an
-- existing function without creating an OVERLOAD, and an overload plus a DEFAULT
-- would make a 6-argument call ambiguous — so DROP then CREATE (the 048 manoeuvre).
-- No DB object depends on the function; the only dependant is the app RPC call
-- site, which the deploy note above shows is unaffected in this direction.
-- ----------------------------------------------------------------------------
drop function if exists pfin.fn_create_manual_account(text, text, text, text, numeric, date);

create or replace function pfin.fn_create_manual_account(
  p_name          text,
  p_account_type  text,
  p_scope         text,
  p_tax_treatment text,
  p_initial_value numeric,
  p_as_of_date    date,
  p_positions     jsonb default '[]'::jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid        uuid;
  v_account_id bigint;
  v_currency   text;
  v_pos        jsonb;
  v_idx        integer := 0;
  v_asset_type text;
  v_name       text;
  v_symbol     text;
  v_qty        numeric;
  v_basis      numeric;
  v_price      numeric;
  v_asset_id   bigint;
begin
  -- (0) Caller-context guard — DEFENSE IN DEPTH, not the sole fence, and the
  -- distinction is measured (see the POSTURE RATIONALE deviation note). Without
  -- it the call still fails, at statement (1), because pfin.account.users_id is
  -- NOT NULL — but it fails with 23502 pointing at a column instead of at the
  -- missing caller context. This guard fails early and names the real cause, and
  -- it pins the requirement in the function that relies on it rather than
  -- borrowing it from another table's constraint. v_uid is also used EXPLICITLY
  -- at (3a) so the asset's owner is stated rather than inherited from a default,
  -- which matters because pfin.asset.users_id is NULLABLE and a NULL there means
  -- GLOBAL (016's hybrid posture), not ownerless.
  v_uid := auth.uid();
  if v_uid is null then
    raise exception
      'fn_create_manual_account requires an authenticated caller: auth.uid() is NULL. This RPC is SECURITY INVOKER and every fence it relies on evaluates as the caller (SELF-325 / 087). Defense in depth: without this guard the account INSERT below fails anyway at account.users_id NOT NULL, but with an error naming a column rather than the missing caller context.';
  end if;

  -- (1) Create the manual account. users_id is deliberately NOT a parameter — it
  -- defaults to auth.uid() (003), the un-forgeable creator linchpin fenced by
  -- account_insert WITH CHECK (users_id = auth.uid()). The AFTER INSERT trigger
  -- fn_grant_creator_access (003, DEFINER) seeds account_users(rd,wr=true) in THIS
  -- same transaction before statement (2) runs. The account-level Sub-Cat column
  -- and its matched-tenant fence were removed at 048 — accounts are not classified
  -- per-account. `currency` (015, default 'USD') is read back so the created assets
  -- are denominated the same way the account is, keeping the 049/050 fx term
  -- consistent between the security leg and the cash leg.
  insert into pfin.account (name, account_type, scope, tax_treatment)
  values (p_name, p_account_type, p_scope, p_tax_treatment)
  returning account_id, currency into v_account_id, v_currency;

  -- (2) The AcctSetup opening-balance CASH row on the immutable audit-class ledger
  -- (004 / 012). ⚠ security_id STAYS NULL — this is (F1) and it is not an omission.
  -- Cash is amount-carried (056 sums every amount with no security filter) and its
  -- CLASSIFICATION already routes through the global currency-asset's 022 junction
  -- row (081). Binding this row to USD would change no figure and would put USD in
  -- the classify queue. When positions are supplied, p_initial_value is the cash
  -- REMAINDER, not the account total.
  -- account_trans carries no own users_id — tenant scope derives via account_id ->
  -- account_users wr_access-JOIN (006), satisfied by the creator-grant row from
  -- statement (1) in this same transaction.
  insert into pfin.account_trans (account_id, transaction_date, amount, transaction_type)
  values (v_account_id, p_as_of_date, p_initial_value, 'acct_setup');

  -- (3) Opening POSITIONS, if any. Absent / empty / null in every spelling returns
  -- here, so the body above is exactly what 048 executed: the $0 / zero-holdings
  -- path is unchanged code, not a defaulted special case.
  if p_positions is null or p_positions = 'null'::jsonb then
    return v_account_id;
  end if;

  if jsonb_typeof(p_positions) <> 'array' then
    raise exception
      'p_positions must be a JSON array of opening positions, got %. Pass ''[]'' (or omit it) for a zero-holdings account (SELF-325 / 087).',
      jsonb_typeof(p_positions);
  end if;

  for v_pos in select value from jsonb_array_elements(p_positions) loop
    v_idx := v_idx + 1;

    if jsonb_typeof(v_pos) <> 'object' then
      raise exception 'p_positions[%] must be a JSON object, got %.', v_idx, jsonb_typeof(v_pos);
    end if;

    -- asset_type. 016's CHECK is the single authority for the VOCABULARY; this body
    -- keeps no copy of it. The one explicit rejection is 'currency', which 016
    -- legitimately admits and (F1) forbids — cash must never be instrument-bound.
    if jsonb_typeof(v_pos -> 'asset_type') is distinct from 'string' then
      raise exception 'p_positions[%].asset_type must be a JSON string.', v_idx;
    end if;
    v_asset_type := v_pos ->> 'asset_type';
    if v_asset_type = 'currency' then
      raise exception
        'p_positions[%].asset_type may not be ''currency'': cash is amount-carried, not instrument-carried, and its classification already routes through the global currency-asset (SELF-325 / 087 F1; 056 + 081). Put cash in p_initial_value.',
        v_idx;
    end if;

    -- name. Non-empty after btrim; per-user uniqueness is asset_user_name_uniq's
    -- (016) to enforce, not this body's — one authority, no drifting copy.
    if jsonb_typeof(v_pos -> 'name') is distinct from 'string' then
      raise exception 'p_positions[%].name must be a JSON string.', v_idx;
    end if;
    v_name := btrim(v_pos ->> 'name');
    if v_name = '' then
      raise exception 'p_positions[%].name must not be empty.', v_idx;
    end if;

    -- symbol. Optional; a JSON null or an absent key both mean "no symbol".
    if (v_pos ? 'symbol') and jsonb_typeof(v_pos -> 'symbol') not in ('string', 'null') then
      raise exception 'p_positions[%].symbol must be a JSON string or null.', v_idx;
    end if;
    v_symbol := nullif(btrim(coalesce(v_pos ->> 'symbol', '')), '');

    -- quantity. The TYPE CHECK is the observer for "NaN"/"Infinity"/currency
    -- strings/locale-formatted strings — JSON has no NaN or Infinity literal, so
    -- those arrive quoted. See the Lock 14 block for which layer catches what; the
    -- four disjuncts are named separately because `'NaN'::numeric > 0` is TRUE.
    if jsonb_typeof(v_pos -> 'quantity') is distinct from 'number' then
      raise exception
        'p_positions[%].quantity must be a JSON number (unquoted). Quoted values — including "NaN", "Infinity" and currency- or locale-formatted strings — are rejected here.',
        v_idx;
    end if;
    v_qty := (v_pos ->> 'quantity')::numeric;
    if v_qty is null
       or v_qty = 'NaN'::numeric
       or v_qty <= 0
       or v_qty >= 'Infinity'::numeric then
      raise exception 'p_positions[%].quantity must be a finite number greater than zero, got %.', v_idx, v_qty;
    end if;

    -- cost_basis. Same posture as quantity.
    if jsonb_typeof(v_pos -> 'cost_basis') is distinct from 'number' then
      raise exception
        'p_positions[%].cost_basis must be a JSON number (unquoted). Quoted values — including "NaN", "Infinity" and currency- or locale-formatted strings — are rejected here.',
        v_idx;
    end if;
    v_basis := (v_pos ->> 'cost_basis')::numeric;
    if v_basis is null
       or v_basis = 'NaN'::numeric
       or v_basis <= 0
       or v_basis >= 'Infinity'::numeric then
      raise exception 'p_positions[%].cost_basis must be a finite number greater than zero, got %.', v_idx, v_basis;
    end if;

    -- (3a) The per-user asset. users_id is passed EXPLICITLY from the local
    -- resolved at (0) rather than left to the column DEFAULT, so this row's owner
    -- is stated in the statement that creates it. asset_insert's WITH CHECK
    -- (users_id = auth.uid()) still evaluates as the caller and still fences it.
    -- pricing_source='manual_valuation' is what (3b)'s price row is allowed to
    -- attach to under 019's write policy.
    insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
    values (v_uid, v_asset_type, 'manual_valuation', v_symbol, v_name, v_currency)
    returning asset_id into v_asset_id;

    -- (3b) The manual valuation. ⚠ THIS IS (F3) AND IT IS NOT OPTIONAL: 049 / 050
    -- value a position as quantity x price x fx, so the account's whole bound
    -- value vanishes from NAV silently in EITHER of two ways — a MISSING price row
    -- (NULL term, dropped by SUM) or a price row that EXISTS and is ZERO (fenced
    -- immediately below; do not read this paragraph as naming the whole hazard).
    -- Written under 019's eod_price_insert policy, which admits only
    -- source='manual_valuation' on an asset the caller owns. round(...,4) matches
    -- the numeric(20,4) grain so this value and (3c)'s price are the same number;
    -- see the ROUNDING ARTIFACT note. Division is safe: v_qty > 0 is established.
    v_price := round(v_basis / v_qty, 4);

    -- ⚠ ZERO-ROUNDED PRICE FENCE (Sec, blocking, SELF-325 joint review). A price
    -- that rounds to 0.0000 is a LEGAL eod_price row — 019's only CHECK on price
    -- is the NaN fence — and it re-admits exactly the silent-zero-NAV failure
    -- (F3) exists to prevent, by the one spelling (F3)'s watcher cannot see: the
    -- row EXISTS, it is simply worthless, so the position values at quantity x 0.
    -- Reachable by input that passes every guard above (quantity 1000000,
    -- cost_basis 10.00). The predicate is <= 0 rather than = 0 defensively; with
    -- v_basis > 0 and v_qty > 0 established the quotient cannot be negative, so
    -- the reachable case is exactly the zero one.
    -- ⚠ TESTS v_price, THE LOCAL ASSIGNED ABOVE — not a second round(...) of the
    -- same expression (Sec, SELF-325 delta review). An earlier draft recomputed
    -- it, which is two copies of one rule and exactly the drift this file's own
    -- single-authority discipline forbids elsewhere: the fence and the value
    -- actually written must be the same number by construction, not by two
    -- expressions agreeing.
    if v_price <= 0 then
      raise exception
        'p_positions[%] derives a price of 0.0000 and would value at zero: cost_basis % over quantity % is below the numeric(20,4) price grain of pfin.eod_price (a per-unit price under 0.00005, i.e. quantity > 20000 x cost_basis). The position would be stored with a price row that exists but is worthless, so its value would vanish from NAV silently. Re-express the position with a smaller quantity or a larger cost_basis (SELF-325 / 087 F3).',
        v_idx, v_basis, v_qty;
    end if;

    insert into pfin.eod_price (asset_id, price_date, source, price)
    values (v_asset_id, p_as_of_date, 'manual_valuation', v_price);

    -- (3c) The instrument-routed opening row. ⚠ amount = 0 IS (F2): 056 sums every
    -- amount as cash and 019 fn_holdings_as_of rolls this quantity as a position,
    -- so a nonzero amount here would count the opening value TWICE. The GL is
    -- already written for this exact shape — 084 P2 books the position from
    -- cost_basis, and 084 P5 contras -(amount + cost_basis) to Opening Balance
    -- Equity, which balances at amount=0. This is an OPENING BALANCE, not a
    -- purchase: a purchase is transaction_type='standard' with amount=-cost, and
    -- keeping the two distinguishable is the point of writing acct_setup here.
    -- The Decision-3 #7 fence (017) fires on this INSERT and passes: the asset was
    -- created at (3a) owned by this same caller.
    insert into pfin.account_trans
      (account_id, transaction_date, amount, transaction_type,
       security_id, quantity, cost_basis, price)
    values
      (v_account_id, p_as_of_date, 0, 'acct_setup',
       v_asset_id, v_qty, v_basis, v_price);
  end loop;

  -- AUDIT FORWARD-HOOK (A2 deferral — conscious documented deviation; ADR-026).
  -- The same-transaction audit-log (api/CLAUDE.md; Decision 1 / Lock 4 mod #5) is
  -- DEFERRED: the audit-log table + its DEFINER insert-helper (the reserved/
  -- unauthored allowlist entry) do not exist yet, so no V1 path emits audit rows.
  -- WHEN the audit-infra issue (SELF-201 Task #7) lands, insert the same-transaction
  -- audit row HERE (this body, same txn). The immutable acct_setup rows above are
  -- the V1 creation-provenance stand-in. F/CTO-ratified defer; mirrors 006 mod #1.

  return v_account_id;
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default — revoke it (denies anon, which is in
-- PUBLIC), then grant to authenticated only. The create path is authenticated-tier;
-- anon must not reach it.
revoke execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb) from public;
grant execute on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb) to authenticated;

comment on function pfin.fn_create_manual_account(text, text, text, text, numeric, date, jsonb) is
  'SECURITY INVOKER write-composition RPC (SELF-201 §2.4.2; ADR-026; p_sub_cat_id dropped at 048 / SELF-319; p_positions added at 087 / SELF-325). Atomically creates a manual account, its AcctSetup opening-balance CASH account_trans row, and — for each entry in p_positions — a per-user pfin.asset row, its manual_valuation pfin.eod_price row, and an instrument-routed AcctSetup account_trans row, in ONE transaction under the caller''s RLS, RETURNING the new account_id. Three properties are load-bearing and each produces silently wrong money if dropped: the CASH row carries security_id NULL and asset_type ''currency'' is rejected, because cash is amount-carried (056 sums every amount) and its classification already routes through the global currency-asset (081), so binding it would change no figure and would put USD in the classify queue; every instrument-routed row carries amount=0, because 056 counts amount as cash while 019 fn_holdings_as_of counts quantity as a position and a nonzero amount would count the opening value twice (NO DDL enforces this — the observer is the paired QA battery leg); and every position also writes a USABLE eod_price row, because 049/050 value a position as quantity x price x fx. That hazard has TWO spellings and both zero the account''s bound value silently: a MISSING price row yields a NULL term that SUM drops, and a price row that EXISTS but rounds to 0.0000 (legal — 019 CHECKs only for NaN) values the position at quantity x 0. The second defeats any watcher that checks row PRESENCE rather than row VALUE, and is reachable whenever quantity > 20000 x cost_basis pushes the per-unit price below the numeric(20,4) grain; the body REJECTS that input (Sec, SELF-325 joint review). Opening balance and purchase stay distinguishable: acct_setup with amount=0 books an Opening-Balance-Equity contra (084 P5), a purchase is transaction_type=''standard'' with amount=-cost. Instrument binding is OPTIONAL: p_positions omitted/[]/null executes exactly 048''s statements, so an acquisition may instead be recorded later as a real purchase. users_id is NOT a parameter (DEFAULT auth.uid() per 003 — un-forgeable); an auth.uid() IS NULL caller is REJECTED — a deviation from 048 that is DEFENSE IN DEPTH over an already-closed path, not a new fence: measured, such a call already failed at account.users_id NOT NULL (23502), so the guard changes the error, not the outcome, and removes no exercisable capability. It earns its place by failing early with a named cause and by pinning the caller-context requirement in the function that relies on it instead of borrowing it from another table''s constraint. It does not reach an RLS-exempt caller that sets a JWT claim (ADR-023 impersonate-then-write): auth.uid() is non-NULL there. Fences evaluate as the caller: account_insert WITH CHECK, account_trans_insert wr_access-JOIN (006, satisfied by the same-txn fn_grant_creator_access creator-grant row), asset_insert WITH CHECK (016), eod_price_insert manual_valuation-on-owned (019), and the Decision-3 #7 security_id fence (017), which passes by construction because the asset is minted in this same transaction for this same caller. NOT a DEFINER allowlist entry — needs no elevation; read ADR-011 Decision 9 live. Needs NO service_role (anon-key client + RLS + INVOKER). set search_path = '''' injection fence. EXECUTE revoked from PUBLIC, granted to authenticated only (anon denied). Lock 14 numeric posture: quoted values including "NaN" and "Infinity" are rejected by the JSON type check, zero and negative by an explicit guard, and finite-but-huge magnitudes by numeric column coercion (017) rather than by this body. Adds NO FK-shaped column — ADR-011 Decision 3 family unchanged, no label taken; read Decision 3 live. Same-transaction audit-log DEFERRED (A2; forward-hook in body; SELF-201 Task #7). Signature is an API contract (PostgREST /rpc; pfin is [api]-exposed) — the 6-arg signature is replaced by this 7-arg one, and because the added parameter carries a DEFAULT an existing 6-named-arg call site is unaffected (migration-first is the backward-compatible direction here, the OPPOSITE of 048).';
