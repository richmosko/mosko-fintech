-- ============================================================================
-- 058_account_closure.sql — closed_at + the standing zero-value invariant
--   (ADR-042 Decisions 2/3/4). THE COLUMN NEVER EXISTS UNGATED.
--
-- Numbering: 058 follows 057 (account_event must exist — the gate writes to it).
--
-- EVERYTHING IN THIS FILE IS ONE UNIT. 003:124 grants authenticated a
--   TABLE-LEVEL update on pfin.account with no column list, so closed_at is
--   writable by every caller the instant it exists. Splitting the column from
--   its fences would put a closure column with no guard on main. Same-file, not
--   merely same-merge: `supabase migration up` applies each file in its own
--   transaction, so a failure between files would strand a real database in the
--   ungated state.
--
-- WHAT 059 DOES, so this file is read as half a pair: validates the constraint
--   added NOT VALID below, then drops the sync trigger, the constraint and
--   is_active, then re-points 049/050/051 to the as-of predicate.
-- ============================================================================

create schema if not exists pfin;

alter table pfin.account
  add column if not exists closed_at timestamptz;

comment on column pfin.account.closed_at is
  'Account closure, AS-OF DATED (ADR-042 Decision 2; this is ADR-039''s rejected Option D, ratified). NULL = open. A boolean cannot answer an as-of question, which is why is_active is retired at 059 rather than kept alongside. Set ONLY through the gated path: the 058 close gate proves the account holds zero as of this date. Never back-fill it from is_active — those rows are unvalidated by definition and the gate is the only thing that validates them.';

-- ----------------------------------------------------------------------------
-- (1) ONE-DIRECTIONAL sync: closed_at -> is_active. NEVER the reverse.
--
--   THIS TRIGGER SURVIVES the move to a CHECK and is REQUIRED by it. The CHECK
--   below enforces the biconditional, so every write must leave both columns
--   consistent — a close control writing closed_at alone would be REJECTED AT
--   THE WRITE. Something must do the pairing, and requiring every caller to
--   write both columns is an app-layer obligation, which is not a control.
--   This trigger makes the pairing structural; the CHECK verifies it.
--
--   *** DO NOT "FINISH" THIS BY MAKING IT BIDIRECTIONAL. *** A reverse sync
--   (is_active -> closed_at) would let a user CLOSE AN ACCOUNT BY FLIPPING
--   is_active, bypassing the gate entirely — which is the defect this whole
--   migration exists to fix. It stops where it stops on purpose.
--
--   Dropped at 059 with the column.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_sync_is_active()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.closed_at is distinct from old.closed_at then
    new.is_active := (new.closed_at is null);
  end if;
  return new;
end;
$$;

comment on function pfin.fn_account_sync_is_active() is
  'BEFORE UPDATE transitional sync (ADR-042 058; TRANSITIONAL — dropped at 059 with is_active). ONE-DIRECTIONAL: closed_at -> is_active, NEVER the reverse. A reverse sync would let a user close an account by flipping is_active, bypassing the gate — the exact defect this migration fixes. Required by the biconditional CHECK: that CHECK rejects any write leaving the two columns inconsistent, so a close control writing closed_at alone would fail; this trigger makes the pairing structural rather than an obligation on every caller (an app-layer obligation is not a control). IS DISTINCT FROM, not <>, so a NULL transition in either direction is detected. SECURITY INVOKER; allowlist stays 4.';

create trigger account_sync_is_active
  before update on pfin.account
  for each row execute function pfin.fn_account_sync_is_active();

-- ----------------------------------------------------------------------------
-- (2) The biconditional, as a CHECK — NOT a trigger.
--
--   A BEFORE UPDATE trigger would NOT see an INSERT. The 049/050/051 batteries
--   INSERT is_active in the column list, so INSERT (is_active=false,
--   closed_at=null) creates exactly the state 059 must abort on. A CHECK covers
--   INSERT and UPDATE, for ALL roles (a CHECK is not RLS), with no ordering
--   concerns.
--
--   NOT VALID IS DELIBERATE AND IS PAIRED. Sec's standing caution — that a
--   NOT VALID CHECK "papers straight over" pre-existing violators — applies to
--   one that is NEVER VALIDATED. Here 059 runs VALIDATE CONSTRAINT, which IS
--   the fail-loud mechanism: it errors if any pre-existing row still violates.
--   NOT VALID is what lets the operator disposition accounts through the gate
--   during the window instead of being blocked at 058.
--   (Residual: VALIDATE errors on the FIRST violator rather than listing all,
--   so the operator's enumeration is a separate read, not this constraint.)
--
--   PLAIN `=` IS CORRECT, AND THE SAFETY IS INHERITED RATHER THAN LOCAL.
--   is_active is NOT NULL DEFAULT true (003:104), and `closed_at is null`
--   yields only true/false — so neither side is ever NULL and the predicate
--   never evaluates to NULL. That matters because A CHECK CONSTRAINT PASSES ON
--   NULL: were is_active ever made nullable, this fence would stop failing loud
--   and start passing everything, silently, for exactly the write shape someone
--   would reach for to evade it. The window is bounded (the column dies at 059),
--   which caps the exposure but does not make it legible. This is the same class
--   as the now()-in-a-CHECK note below: invisible from the DDL, and the reader
--   most likely to break it is not thinking about closure at all.
-- ----------------------------------------------------------------------------
alter table pfin.account
  add constraint account_closure_biconditional
  check (is_active = (closed_at is null)) not valid;

comment on constraint account_closure_biconditional on pfin.account is
  'ADR-042 058: is_active = (closed_at is null). TRANSITIONAL — validated then dropped at 059 with is_active. NOT VALID is deliberate and PAIRED with 059''s VALIDATE CONSTRAINT, which is the fail-loud gate on pre-existing rows; the standing caution against NOT VALID applies to one that is never validated. A CHECK rather than a trigger because a BEFORE UPDATE trigger does not see an INSERT, and INSERT (is_active=false, closed_at=null) creates exactly the state 059 aborts on. Plain = is correct because is_active is NOT NULL (003:104) so neither side is ever NULL — but a CHECK PASSES ON NULL, so if is_active were ever made nullable this fence would silently pass everything.';

-- ----------------------------------------------------------------------------
-- (3) The close gate + the currency conjunct — one trigger, two conditions.
--
--   GATE fires on the INTO-CLOSED transition only. AUDIT (below) fires in both
--   directions. Reopening is deliberately UNGATED: a reopened account starts at
--   zero and is funded by new dated entries; closure entries are historical
--   facts and are not un-booked. Gating the exit would be incoherent — a closed
--   account is already at zero by the gate that admitted it.
--
--   THREE LEGS, THREE DISTINCT MESSAGES, so a battery can assert WHICH fired.
--   An assertion that cannot identify the leg proves less than it appears to.
--     (i)  zero HOLDINGS as of closed_at — QUANTITY-based via fn_holdings_as_of.
--          NOT market value: an unpriced asset yields a NULL price term that SUM
--          drops, so a value test reads 10 shares of an unpriced asset as zero.
--          Price coverage is not a security control.
--     (ii) zero CASH as of closed_at — via fn_account_cash_as_of (056), which is
--          NATIVE and applies no fx multiplier. Measured live: a negative
--          fx_feed rate sign-flips fn_compute_nav and leaves the measure at
--          100.0000. The gate is immune to a rate a bad feed controls.
--          fn_account_cash_as_of is TOTAL over pfin.account, so a missing row
--          means the contract is broken -> RAISE rather than treat as zero.
--    (iii) no ACTIVITY dated after closed_at. Without this, a backdated closure
--          over a live period orphans that activity on the wrong side of the
--          invariant the instant it lands.
--
--   PLAUSIBILITY BOUND lives HERE, not in a CHECK: now() is STABLE and a
--   temporal CHECK is a dump/restore foot-gun (a row valid at insert can fail
--   re-validation on restore). One-sided only — NOT in the future. It must NOT
--   be two-sided: closed_at >= created_at is table-local and tempting and WRONG,
--   because a user may legitimately add a historical account and close it as of
--   a date before the row existed.
--
--   CURRENCY CONJUNCT (Decision 4): account.currency feeds fn_compute_nav's
--   cash-leg FX multiplier (015:541, its own comment), so changing it on a
--   CLOSED account retroactively re-values every date INCLUDING closed_at and
--   falsifies the invariant that admitted the closure. Reachable: authenticated
--   holds table-level UPDATE and pfin is Data-API-exposed, so updateAttributes'
--   Zod schema omitting currency is not a control. Columns checked, not assumed:
--   account_type selects 049's investment branch but never enters fn_compute_nav;
--   backfill_cutover_date is provenance-only; users_id is fenced by
--   account_update's WITH CHECK.
--   (The OPEN-account half — currency is mutable on every account and silently
--   restates history — is deliberately OUT OF SCOPE here; BACKLOG.md §7.7.)
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_closure_gate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cash numeric;
begin
  -- currency immutability on an already-closed account
  if old.closed_at is not null and new.currency is distinct from old.currency then
    raise exception
      'currency is immutable on a closed account (account %): it feeds the fn_compute_nav cash-leg FX multiplier and would retroactively re-value the closure date (ADR-042 Decision 4)',
      new.account_id;
  end if;

  -- gate only the into-closed transition
  if old.closed_at is null and new.closed_at is not null then

    if new.closed_at > now() then
      raise exception
        'account closure blocked: account % has a future closed_at (%) — the bound is one-sided, not-in-the-future',
        new.account_id, new.closed_at;
    end if;

    if exists (
      select 1 from pfin.fn_holdings_as_of(new.closed_at::date) h
      where h.account_id = new.account_id and h.quantity <> 0
    ) then
      raise exception
        'account closure blocked: account % holds non-zero positions as of % (leg 1 of 3: holdings)',
        new.account_id, new.closed_at::date;
    end if;

    select c.balance_native into v_cash
    from pfin.fn_account_cash_as_of(new.closed_at::date) c
    where c.account_id = new.account_id;

    if not found then
      raise exception
        'account closure blocked: account % returned no row from fn_account_cash_as_of — that function is TOTAL over pfin.account, so this means its totality contract is broken (leg 2 of 3: cash)',
        new.account_id;
    end if;

    if v_cash <> 0 then
      raise exception
        'account closure blocked: account % holds a non-zero cash balance (% native) as of % (leg 2 of 3: cash)',
        new.account_id, v_cash, new.closed_at::date;
    end if;

    if exists (
      select 1 from pfin.account_trans t
      where t.account_id = new.account_id and t.transaction_date > new.closed_at::date
    ) or exists (
      select 1 from pfin.account_balance_checkpoint b
      where b.account_id = new.account_id and b.as_of_date > new.closed_at::date
    ) or exists (
      select 1 from pfin.holdings_checkpoint hc
      where hc.account_id = new.account_id and hc.as_of_date > new.closed_at::date
    ) then
      raise exception
        'account closure blocked: account % has activity dated after % (leg 3 of 3: post-closure activity)',
        new.account_id, new.closed_at::date;
    end if;

  end if;

  return new;
end;
$$;

comment on function pfin.fn_account_closure_gate() is
  'BEFORE UPDATE close gate + currency conjunct on pfin.account (ADR-042 Decisions 3 + 4). Gate fires on the INTO-CLOSED transition ONLY; reopening is deliberately ungated (a reopened account starts at zero and is funded by new dated entries; closure entries are historical facts and are not un-booked). Three legs with THREE DISTINCT messages so a battery can assert which fired: (1) zero holdings as of closed_at, QUANTITY-based via fn_holdings_as_of — a market-value test reads 10 shares of an unpriced asset as zero, and price coverage is not a security control; (2) zero cash via fn_account_cash_as_of, which is NATIVE and applies no fx multiplier — measured live, a negative fx_feed rate sign-flips fn_compute_nav and leaves the measure unchanged, so the gate is immune to a rate a bad feed controls; a missing row RAISES because that function is total over pfin.account; (3) no activity dated after closed_at, without which a backdated closure orphans live activity. Plausibility bound is here rather than in a CHECK because now() is STABLE and a temporal CHECK is a dump/restore foot-gun; ONE-SIDED only — closed_at >= created_at would be wrong, since a historical account may legitimately be closed as of a date before its row existed. Currency conjunct: account.currency feeds the fn_compute_nav cash-leg FX multiplier (015:541), so changing it on a closed account retroactively re-values the closure date. SECURITY INVOKER; allowlist stays 4.';

create trigger account_closure_gate
  before update on pfin.account
  for each row execute function pfin.fn_account_closure_gate();

-- ----------------------------------------------------------------------------
-- (4) Transfer-in fences: a closed account is FROZEN.
--
--   REJECT ALL WRITES, not just post-closure-dated ones. The permissive form
--   ("permit if the closure-date position stays zero") cannot be an immediate
--   row trigger — a legitimate netting pair fails on the first row before its
--   partner arrives — so it would need a DEFERRABLE constraint trigger, which
--   fires at COMMIT, and releasing a savepoint does not fire deferred triggers,
--   so per-row quarantine becomes reachable only by relocating deferred-check
--   machinery into the ingest worker. AND IT BUYS NOTHING: the netting
--   correction still works under reject-all, via reopen -> insert both -> re-close.
--   Both forms admit it; reject-all merely makes the transition visible.
--
--   SCOPE IS THE POSITION-DETERMINING TABLES ONLY. Every exemption names its
--   dependency, because an unnamed one is an unexamined one:
--     account_trans_split      — position-neutral BY 029's Sigma=parent deferred
--                                constraint (splits carry real signed amounts;
--                                they are safe only because they must decompose
--                                an amount that already exists)
--     account_trans_annotation — position-neutral BY 004 immutability of
--                                account_trans.account_id and amount (an
--                                annotation can only re-classify a value it
--                                cannot change)
--     pfin.account itself      — NOT fenced, and this is load-bearing: the
--                                design DEPENDS on reopen being reachable, so
--                                fencing it would make closure irreversible and
--                                turn this into the blunt lock we rejected.
--
--   NAMING: 037:633 already ships fn_account_trans_annotation_freeze_closed for
--   a closed JOURNAL, and supabase/tests/rls/self209_close_gate.sql is the
--   §2.4.5 ONBOARDING close-gate. Three different subjects, one word. The
--   subject is in the name here on purpose.
--
--   INGEST CONTRACT (Backend, not this file): a refusal must NOT fail the whole
--   sync batch and advance a cursor over dropped data. Per-row quarantine,
--   durably recorded to linked_source_sync_audit, surfaced via a NEW named count
--   key on the 040 view — NOT transactions_skipped, because a dedup-skip is
--   benign and a closed-account refusal needs user action, and NULL != 0 on that
--   key because "we were not counting" must not render as "nothing was refused".
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_block_write_closed_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1 from pfin.account a
    where a.account_id = new.account_id and a.closed_at is not null
  ) then
    raise exception
      'write blocked: account % is closed (%). A closed account is frozen — reopen it, make the correction, then re-close (which re-proves the zero invariant).',
      new.account_id, tg_table_name;
  end if;
  return new;
end;
$$;

comment on function pfin.fn_block_write_closed_account() is
  'BEFORE INSERT transfer-in fence for the position-determining tables (ADR-042 Decision 3). A closed account is FROZEN: reject ALL writes, not merely post-closure-dated ones — the permissive form would need a DEFERRABLE constraint trigger (a netting pair fails on the first row under an immediate one), and it buys nothing, since the netting correction still works via reopen -> insert both -> re-close. Names the table in the message (tg_table_name) so a battery can assert WHICH fence fired. Fires for service_role too, which bypasses RLS but NOT triggers (the 004:165 precedent) — that is the whole point, since 008/018 grant service_role INSERT on these tables. SECURITY INVOKER; allowlist stays 4. NOT applied to account_trans_split (position-neutral by 029 Sigma=parent), account_trans_annotation (position-neutral by 004 immutability), or pfin.account itself (fencing it would make closure irreversible — the design depends on reopen being reachable).';

create trigger account_trans_block_closed_account
  before insert on pfin.account_trans
  for each row execute function pfin.fn_block_write_closed_account();

create trigger account_balance_checkpoint_block_closed_account
  before insert on pfin.account_balance_checkpoint
  for each row execute function pfin.fn_block_write_closed_account();

create trigger holdings_checkpoint_block_closed_account
  before insert on pfin.holdings_checkpoint
  for each row execute function pfin.fn_block_write_closed_account();

-- ----------------------------------------------------------------------------
-- (5) 042's re-land: preserve RETURNING, drop the resurrection.
--
--   042:101 records, in its own header, that DO UPDATE was chosen OVER DO
--   NOTHING *so RETURNING yields the account_id for already-existing rows* —
--   "the caller gets the id for every selected account, whether freshly inserted
--   or reactivated". DO NOTHING produces no row for a conflicting insert, so
--   RETURNING yields nothing and the landing flow silently gets FEWER account_ids
--   than the user selected. (An earlier draft of this migration proposed DO
--   NOTHING on the reasoning that the dedup arbiter was the clause's purpose.
--   The file states a second purpose 160 lines above the clause.)
--
--   `set provider_account_id = excluded.provider_account_id` is provably a NO-OP
--   — provider_account_id is part of the conflict arbiter, so excluded's value
--   equals the existing one — while still counting as an UPDATE, so RETURNING
--   fires. No concept-2 transition occurs; the 021 dedup arbiter is untouched.
--   It DOES fire account_set_updated_at, so updated_at moves on a re-land. That
--   is correct rather than a side effect (the row was touched by a landing
--   operation), and is named here so it is not read as an accident.
--
--   WHY THIS MUST CHANGE — and the reason is not "to forbid the transition":
--   the biconditional CHECK ALREADY makes silent resurrection impossible, by
--   converting `set is_active = true` on a closed row into a CHECK VIOLATION.
--   042 changes so that a user re-running connect+map over a connection
--   containing a closed account does not simply ERROR. Same edit, different
--   justification — and the justification is what the next reader will act on.
--
--   PRODUCT-VISIBLE CONSEQUENCE, stated because no PRD sentence describes it
--   yet: a provider re-landing an account the user closed now LEAVES IT CLOSED.
--   Under the three-concept model a closed account is still re-offered in the
--   connect selection list, so selecting it becomes a no-op — a control that
--   accepts an action and discards it. PM/UX own the resolution (exclude closed
--   accounts from the offer list, or route the selection to the close control as
--   "this account is closed — reopen it?"); neither is implied by anything
--   ratified, and this file only stops the silent resurrection.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_land_linked_accounts(
  p_linked_source_id bigint,
  p_accounts         jsonb
)
returns table (account_id bigint, provider_account_id text)
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_acct jsonb;
begin
  -- Fail-closed input-shape guard: p_accounts must be a JSON array. A non-array (or
  -- NULL) is a malformed call — abort before any write (no partial landing).
  if p_accounts is null or jsonb_typeof(p_accounts) <> 'array' then
    raise exception 'p_accounts must be a non-null JSON array of account objects'
      using errcode = '22023';  -- invalid_parameter_value
  end if;

  for v_acct in select value from jsonb_array_elements(p_accounts) as t(value)
  loop
    -- Guard the dedup key: provider_account_id must be present. A NULL key would be
    -- treated as distinct by the 021 partial index (insert-always) → silent duplicates
    -- on re-land. Adapter AccountRefs always carry it; make the invariant fail-closed.
    if v_acct ->> 'provider_account_id' is null then
      raise exception 'each p_accounts element must carry a non-null provider_account_id'
        using errcode = '22023';
    end if;

    -- One pfin.account row per selected provider account. users_id is deliberately NOT
    -- set — it defaults to auth.uid() (003), the un-forgeable creator linchpin fenced by
    -- account_insert WITH CHECK. The AFTER INSERT fn_grant_creator_access (003, DEFINER)
    -- seeds account_users(rd,wr=true) per row in THIS same transaction. linked_source_id
    -- is fenced by fn_account_matched_linked_source (015, Decision-3 #6) — a cross-tenant
    -- p_linked_source_id fails closed even through this RPC. Missing NOT NULL keys resolve
    -- to NULL via ->> and are rejected by the pfin.account NOT NULL + CHECK constraints,
    -- aborting the whole transaction (fail-closed). is_active defaults true.
    -- ON CONFLICT reactivates the canonical row (021 reconciliation model — never a 2nd
    -- row; recovers a soft-deleted account); attribute edits are a separate update path,
    -- so a re-land does NOT overwrite stored attributes.
    return query
    insert into pfin.account (
      name, account_type, scope, tax_treatment,
      linked_source_id, provider_account_id
    )
    values (
      v_acct ->> 'name',
      v_acct ->> 'account_type',
      v_acct ->> 'scope',
      v_acct ->> 'tax_treatment',
      p_linked_source_id,
      v_acct ->> 'provider_account_id'
    )
    on conflict (linked_source_id, provider_account_id) where linked_source_id is not null
    do update set provider_account_id = excluded.provider_account_id
    returning pfin.account.account_id, pfin.account.provider_account_id;

    -- AUDIT FORWARD-HOOK (A2-lite deferral — conscious documented deviation; mirrors 013).
    -- WHEN the audit-infra issue (SELF-201 Task #7) lands, insert the same-transaction
    -- audit row HERE (this body, same txn; Decision 1 / Lock 4 mod #5). The append-only
    -- linked_source_sync_audit (015) + the immutable account_trans ledger are the V1
    -- provenance stand-ins for provider-landed accounts.
  end loop;
end;
$$;
