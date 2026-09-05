-- ============================================================================
-- Migration: pfin.fn_open_monthly_report_draft — the A10 generate-a-draft write
--   path (SELF-366 AC 1–4 and the E15 amendment items 9 and 11). Phase 6 Build
--   Loop. One SECURITY INVOKER plpgsql function; no new table, no new column, no
--   new policy. apply-migration procedure applied.
--   ⚠⚠ JOINT-REVIEW-MANDATORY (Sec veto surface), on TWO independent grounds:
--   a new **user-reachable WRITE** onto an [ADR-011](DECISIONS.md#adr-011)
--   Decision 2 audit-class table (the governing trigger per AC 7, independent of
--   the RT-25 obligation), and a **call site for a SECURITY DEFINER function**.
--
-- ⚠ BRANCH NOTE: authored on a branch STACKED on the A1+A2+A3 design unit
--   (`108`–`111`). **It rebases when that unit does**, and **nothing under
--   `108`–`111` is edited here.**
--
-- ----------------------------------------------------------------------------
-- WHAT IT DOES. Given a target month, return the caller's LIVE DRAFT for it —
--   opening the existing one if there is one, and otherwise creating it with the
--   same shape the cron writes. **It is idempotent**, it never returns a `final`
--   row, and it never supersedes anything.
--   ⚠ **"GENERATE" ON A MONTH THAT ALREADY HAS A DRAFT *OPENS* THAT DRAFT** (E15
--   item 9). It does not insert a second one, and the reason is not tidiness — see
--   the falsifying case below.
--   **Regenerating a `final` month is NOT this function.** That is `114`, which
--   performs the Decision 2 transition and then delegates the insert half back
--   here, so the INSERT shape exists once.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE RACE THIS IS BUILT AROUND, AND WHY AN APP-LEVEL CHECK-THEN-INSERT IS THE
--   CONTROL THAT LOSES IT. The falsifying case is **silent commentary loss, not a
--   duplicate listing**: the author opens the editor on draft #1 in tab A, clicks
--   Generate again in tab B producing draft #2, tab A's Save lands on #1 — still
--   `draft`, so `108`'s trigger permits it — and P4 then finalizes **#2, blank**.
--   The author's work is gone, and #1 **persists forever**, because `108` blocks
--   DELETE on everything and no role holds a DELETE grant even for drafts.
--   **Every fence behaves exactly as designed throughout that story**, which is what
--   makes it a schema gap rather than a bug — and why the fence is the partial
--   unique index at `108`, not a check in this function.
--   **CONSEQUENTLY THIS FUNCTION EXPECTS ITS OWN INSERT TO BE REFUSED IN THE RACE
--   AND RESOLVES BY RE-READING**, rather than trying to avoid the refusal:
--     (1) read for an existing draft, taking `FOR UPDATE`;
--     (2) if none, INSERT;
--     (3) **if that INSERT raises `unique_violation`, a concurrent caller won —
--         re-read and return THEIR draft.**
--   Step (3) is not defensive programming around an unlikely event; it is the
--   ordinary outcome of two Generate clicks, and E15 item 11 (i) requires that two
--   concurrent calls yield ONE row **with both callers receiving its id**.
--   ⚠ **A pre-check alone cannot close this and must not be mistaken for the fence.**
--   Between step (1) and step (2) another transaction can commit its own draft; the
--   index is what makes that collision an error instead of a second row.
--
-- ----------------------------------------------------------------------------
-- ⚠ `data_as_of` IS SERVER-DERIVED AND IS NOT A PARAMETER (AC 3; Lock 15; RT-25).
--   **A client-supplied as-of is REFUSED, not ignored — and the strongest form of
--   refusal is that there is no argument to supply.** This function takes the month
--   and derives the as-of itself via `pfin.fn_server_today()`, so RT-25's
--   parameter-bypass class is closed **by the signature** rather than by validation
--   inside it. There is nothing for an adversarial input battery to bypass, which is
--   the point.
--   ⚠ `p_target_month` IS a parameter, and it is not the same kind of thing: it names
--   WHICH month the report is about, which is the caller's legitimate choice, and it
--   is fenced by `108`'s month-start CHECK. **What must never be client-asserted is
--   the as-of the data was composed at**, because that is a claim about when the
--   world was observed.
--
-- ----------------------------------------------------------------------------
-- ⚠ NO TENANT PARAMETER ANYWHERE (AC 1; Gate A). The endpoint runs under the user's
--   OWN session, so **the session IS the tenant binding** — which is precisely why
--   this path does NOT inherit the cron's impersonation pattern. `users_id` comes
--   from `auth.uid()`: it is the column DEFAULT on `108`, so the INSERT does not
--   even name it, and the read is scoped by RLS.
--   ⚠ **AND THERE IS DELIBERATELY NO `users_id = auth.uid()` PREDICATE IN THE BODY**,
--   for the reason `112` records: a hand-written copy of the policy reads as the
--   fence while not being it, and a later reader removing the "redundant" line could
--   not tell which was load-bearing.
--
-- ----------------------------------------------------------------------------
-- ⚠ IT WRITES `draft` AND CANNOT WRITE `final` (AC 2; R9 rider 1). The INSERT names
--   no `generation_status`, so it takes `108`'s `'draft'` DEFAULT — and even if it
--   named one, `108`'s BEFORE INSERT state fence admits `draft` only. **Two
--   independent reasons, and the second is the one that holds against a future edit
--   of this file.** Finalization is P4's path; this function opens the window and
--   does not close it (AC 5).
--   **The row is the one the cron would have written on the 1st** — same shape, so
--   the two paths are interchangeable from every reader's point of view.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE AUDIT ROW IS EMITTED IN THE SAME TRANSACTION, THROUGH `111`'s DEFINER
--   HELPER, AND ONLY WHEN A ROW IS ACTUALLY INSERTED (AC 4).
--   `pfin.fn_emit_audit_log(...)` with `trigger_source = 'on_demand'` — the second of
--   the helper's two V1.5 callers (R7 rider 4), writing the same shape as the cron
--   and discriminated only by that value.
--   ⚠ **IT IS NOT EMITTED WHEN AN EXISTING DRAFT IS OPENED**, and that is a decision
--   rather than an oversight: the audit surface records **privileged writes that
--   happened**, and opening a draft writes nothing. Emitting on the idempotent path
--   would put rows in an append-only table for events that did not occur, and — since
--   Generate is expected to be clicked repeatedly — would make the audit trail's
--   volume a function of UI behaviour rather than of generation.
--   ⚠ **CALLING A `SECURITY DEFINER` FUNCTION IS ITSELF A REVIEWABLE FACT**, which is
--   the second joint-review ground on this file. The helper stamps `users_id` from
--   `auth.uid()` and takes no tenant parameter, so this call site cannot mis-attribute
--   a row; and because the helper is DEFINER, this function needs **no grant** on
--   `pfin.audit_log` and has none.
--   ⚠ **THE SAME-TRANSACTION PROPERTY IS THE POINT AND IT IS FREE HERE:** a plpgsql
--   body is one transaction, so a rolled-back generation takes its audit row with it.
--   A row that survives a rolled-back generation is worse than no row.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER; NOT SECURITY DEFINER. INVOKER is
--   load-bearing rather than merely default: it is what makes the read scoped by the
--   caller's RLS and the INSERT subject to `108`'s WITH CHECK and aal2 clause.
--   **The Decision 9 allowlist is UNCHANGED by this file** — it authors no DEFINER
--   function; it CALLS one. Read Decision 9 live; no size is stated here.
--   `set search_path = ''`. **VOLATILITY: `volatile`, declared explicitly** — it
--   writes, and an explicit declaration is the form that survives a future
--   `CREATE OR REPLACE`, which resets volatility.
--   EXECUTE revoked from `public`, granted to `authenticated` only — **never to a
--   `rolbypassrls` role**, for which RLS applies to nothing and the EXECUTE grant
--   would be the entire perimeter.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — UNTOUCHED. No table, no column, no FK-shaped reference.
--   Read Decision 3 live; no count carried.
-- §10 3-AXIS CROSS-CHECK (Decision 4 read VERBATIM and LIVE, 2026-09-05; Path B).
--   (i) instance-numbering: nothing added, removed, reordered or renumbered.
--   (ii) layer-attribution: nothing moves; no surface becomes "four-layer".
--   (iii) verbatim-vs-paraphrase: Decision 4 is LINKED, never restated.
--
-- ----------------------------------------------------------------------------
-- Numbering: 113 follows 112. Depends on `108` (the table, its policies, its state
--   fence and its two partial unique indexes), `111` (`fn_emit_audit_log`) and `070`
--   (`fn_server_today`). `114` depends on THIS file.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST (legs land at P10; E15 item 11 is ruled):
--   1. **TWO CONCURRENT Generate calls for the same month yield ONE `draft` row and
--      BOTH callers receive its id** (E15 item 11 (i)). ⚠ The second half is the leg —
--      a version that returns NULL or raises for the loser passes a row-count check
--      and still breaks the endpoint.
--   2. **A second `draft` INSERT for `(users_id, target_month)` submitted DIRECTLY
--      through PostgREST is refused by the DB** (E15 item 11 (ii)) — the same fact
--      this function relies on, proved without the app.
--   3. **Idempotence:** calling twice in sequence returns the same `report_id` and
--      leaves exactly one row.
--   4. **No audit row on the idempotent path**, and exactly ONE on the inserting path.
--      ⚠ Both halves; the first is what catches an emit moved outside the branch.
--   5. **Rollback:** a transaction that calls this and then aborts leaves **no report
--      row and no audit row**.
--   6. **Cross-tenant:** tenant B cannot open or create a draft under tenant A's
--      month; the returned id is never tenant A's row.
--   7. **aal2 as a separate leg** from cross-tenant (Sec F-9).
--   8. **`data_as_of` is server-derived:** the stored value equals the server's date
--      and there is no argument by which a caller could have set it (RT-25).
--   9. **It never writes `final`:** the inserted row is `draft`, and the state fence
--      at `108` refuses a hand-built INSERT naming `final`.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_open_monthly_report_draft(p_target_month date) returns bigint
--     — the `report_id` of the caller's live draft for that month, whether this call
--       created it or found it.
--   SECURITY INVOKER · volatile · set search_path = '' · EXECUTE: authenticated only.
--   NO tenant parameter. NO `data_as_of` parameter — server-derived (RT-25).
--   IDEMPOTENT: at most one live draft exists per (users_id, target_month) by `108`'s
--     partial unique index, and this function converges on it from either direction —
--     finding it, or losing the insert race and re-reading it.
--   WRITES, when it inserts: one `pfin.monthly_report` row in `draft`, plus one
--     `pfin.audit_log` row through `pfin.fn_emit_audit_log` with trigger source
--     `on_demand`, in the SAME transaction.
--   WRITES NOTHING when a live draft already exists.
--   REFUSES: a `target_month` that is not a month start (`108`'s CHECK), and — via
--     RLS — anything outside the caller's own tenancy or step-up level.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_open_monthly_report_draft(p_target_month date)
returns bigint
language plpgsql
security invoker
volatile
set search_path = ''
as $$
declare
  v_report_id  bigint;
  v_data_as_of date;
begin
  -- (0) Existing live draft? Locked, so a concurrent caller in this same branch
  -- serializes behind us rather than both proceeding to INSERT. Under SECURITY
  -- INVOKER this resolves through the caller's own RLS — there is deliberately no
  -- users_id predicate here; the policy is the fence.
  select r.report_id
    into v_report_id
    from pfin.monthly_report r
   where r.target_month      = p_target_month
     and r.generation_status = 'draft'
     for update;

  if v_report_id is not null then
    -- OPEN, do not insert. No audit row: nothing privileged happened.
    return v_report_id;
  end if;

  -- (1) SERVER-DERIVED as-of. Never a parameter, so RT-25's parameter-bypass class
  -- is closed by the signature rather than by validation.
  v_data_as_of := pfin.fn_server_today();

  begin
    -- generation_status is NOT named: it takes 108's 'draft' DEFAULT, and 108's
    -- BEFORE INSERT state fence admits nothing else regardless. users_id is NOT
    -- named either: it takes the auth.uid() DEFAULT, so there is no tenant value in
    -- this statement for a caller to influence.
    insert into pfin.monthly_report (target_month, data_as_of)
    values (p_target_month, v_data_as_of)
    returning report_id into v_report_id;

  exception when unique_violation then
    -- (2) A concurrent Generate won the race. This is the ORDINARY outcome of two
    -- clicks, not an exceptional one: re-read and return THEIR draft, so both
    -- callers receive the same id and exactly one row exists. The partial unique
    -- index at 108 is what turned a second row into this error.
    select r.report_id
      into v_report_id
      from pfin.monthly_report r
     where r.target_month      = p_target_month
       and r.generation_status = 'draft';

    if v_report_id is null then
      -- The violation was not the draft index — re-raise rather than swallow it.
      -- Swallowing here would convert an unrelated constraint failure into a silent
      -- NULL return, which is the shape this whole function exists to avoid.
      raise;
    end if;

    return v_report_id;
  end;

  -- (3) The audit row, in THIS transaction, and only because a row was inserted.
  -- fn_emit_audit_log is SECURITY DEFINER and stamps users_id from auth.uid(), so
  -- this call site cannot mis-attribute it and needs no grant on pfin.audit_log.
  perform pfin.fn_emit_audit_log(
    'monthly_report_generation',
    'on_demand',
    'user session: auth.uid() (A10 on-demand path; the session is the tenant binding)',
    v_data_as_of,
    'pfin.monthly_report',
    v_report_id
  );

  return v_report_id;
end;
$$;

revoke execute on function pfin.fn_open_monthly_report_draft(date) from public;
grant  execute on function pfin.fn_open_monthly_report_draft(date) to authenticated;

comment on function pfin.fn_open_monthly_report_draft(date) is
  'The A10 generate-a-draft write path (SELF-366 AC 1-4 and E15 items 9 and 11). Returns the report_id of the caller''s LIVE DRAFT for the given month, whether this call created it or found it. SECURITY INVOKER, volatile, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry; it AUTHORS no DEFINER function, it CALLS one (read ADR-011 Decision 9 live; no size stated here). EXECUTE revoked from public, granted to authenticated only, never to a rolbypassrls role. ⚠ JOINT-REVIEW-MANDATORY on TWO grounds: a user-reachable WRITE onto a Decision 2 audit-class table, and a call site for a SECURITY DEFINER function. IDEMPOTENT — "Generate" on a month that already has a draft OPENS that draft and inserts nothing (E15 item 9). ⚠ THE RACE IT IS BUILT AROUND, and the reason an app-level check-then-insert is the control that LOSES it: the falsifying case is SILENT COMMENTARY LOSS, not a duplicate listing — the author edits draft #1 in tab A, clicks Generate in tab B producing draft #2, tab A''s Save lands on #1 (still draft, so the immutability trigger permits it), and P4 finalizes #2 BLANK; the orphan then persists forever because DELETE is blocked and no role holds the grant. Every fence behaves as designed throughout, which is what makes it a schema gap rather than a bug. So this function EXPECTS ITS OWN INSERT TO BE REFUSED IN THE RACE AND RESOLVES BY RE-READING: read-with-FOR-UPDATE, else INSERT, and on unique_violation re-read and return the winner''s draft so BOTH callers receive the same id. A pre-check alone cannot close the window between the read and the insert; 108''s partial unique index is what makes the collision an error instead of a second row. ⚠ An unrelated unique_violation is RE-RAISED rather than swallowed — swallowing would turn a different constraint failure into a silent NULL return. ⚠ data_as_of IS SERVER-DERIVED AND IS NOT A PARAMETER (Lock 15; RT-25): the strongest refusal of a client-asserted as-of is that there is no argument to supply, so the parameter-bypass class is closed BY THE SIGNATURE rather than by validation inside it. p_target_month is a different kind of thing — it names which month the report is ABOUT, the caller''s legitimate choice, fenced by 108''s month-start CHECK; what must never be client-asserted is when the world was observed. ⚠ NO TENANT PARAMETER (Gate A): the endpoint runs under the user''s own session, so the session IS the tenant binding, which is exactly why this path does not inherit the cron''s impersonation pattern. users_id is never named in the INSERT — it takes the auth.uid() DEFAULT — and there is deliberately no users_id predicate in the body, because a hand-written copy of the policy reads as the fence while not being it. It writes draft and CANNOT write final: the INSERT names no generation_status so it takes the DEFAULT, and 108''s BEFORE INSERT state fence admits nothing else regardless — two independent reasons, the second of which holds against a future edit of this file. ⚠ THE AUDIT ROW IS EMITTED IN THE SAME TRANSACTION AND ONLY WHEN A ROW WAS ACTUALLY INSERTED: opening an existing draft writes nothing, so emitting there would put rows in an append-only table for events that did not occur and would make audit volume a function of UI clicking rather than of generation. A plpgsql body is one transaction, so a rolled-back generation takes its audit row with it — a row that survives a rolled-back generation is worse than no row. REGENERATING A final MONTH IS NOT THIS FUNCTION: that is pfin.fn_regenerate_monthly_report, which performs the Decision 2 transition and then delegates the insert half back here so the INSERT shape exists exactly once.';
