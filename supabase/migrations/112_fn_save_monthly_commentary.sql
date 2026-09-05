-- ============================================================================
-- Migration: pfin.fn_save_monthly_commentary — the §2.6.2 commentary WRITE path,
--   the DB half of P3 (SELF-355 AC 5). Phase 6 Build Loop. One SECURITY INVOKER
--   plpgsql function; no new table, no new column, no new policy, no new grant on
--   any table. apply-migration procedure applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): a user-reachable WRITE onto a
--   Lock 11 audit-class row. Canonical test label **RT-11**.
--
-- ⚠ BRANCH NOTE: this file is authored on a branch STACKED on the A1+A2+A3 design
--   unit (`108`–`111`). **It rebases when that unit does**, and **nothing under
--   `108`–`111` is edited here.** If the unit's numbering moves, this file's
--   number moves with it and its body does not change.
--
-- ----------------------------------------------------------------------------
-- WHAT IT DOES, IN ONE PARAGRAPH. Replace-all of the four §2.6.2 commentary
--   columns on the caller's LIVE DRAFT for one month, plus
--   `commentary_disposition = 'authored'`. It takes a MONTH, not a report id, and
--   it returns the `report_id` it wrote so the caller can assert it hit the row it
--   meant to. It creates nothing, and it can only ever touch a `draft`.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE RATIFIED SHAPE, AND WHY IT IS NOT "SERIALIZABLE".
--   AC 5 says replace-all per the Lock 14 pattern, and Lock 14's own words are
--   *"under SERIALIZABLE"*. **That phrase is not reachable from this transport** and
--   [ADR-011](DECISIONS.md#adr-011) Decision 18's 2026-09-03 amendment records the
--   realization this file follows: PostgREST runs **each** call as its own
--   transaction, and `SET TRANSACTION ISOLATION LEVEL` **cannot be issued inside a
--   function body** because the calling statement has already taken its snapshot.
--   So the atomic body is ONE plpgsql function — therefore one transaction — whose
--   **FIRST statement takes a `FOR UPDATE` row lock**, exactly as
--   `fn_tax_bracket_schedule_replace_all` does at `101`.
--   ⚠ **THAT FIRST STATEMENT IS ALSO THE TENANT FENCE, and it is the whole of it.**
--   Under SECURITY INVOKER it runs with the caller's own RLS, so another tenant's
--   month — or an absent one — resolves to **zero rows** and the function refuses.
--   **There is NO tenant parameter** (Gate A; the `101` / `105` precedent):
--   `users_id` comes from `auth.uid()` via RLS and never from an argument.
--   ⚠ **AND THERE IS DELIBERATELY NO `users_id = auth.uid()` PREDICATE IN THE BODY.**
--   Writing one would be the `p_users_id` trap wearing a `WHERE` clause: it reads as
--   the fence while the actual fence is RLS, and a later reader who removes the
--   "redundant" line would not be able to tell which of the two was load-bearing.
--   The predicate that IS load-bearing is the policy, and it fails closed.
--   ⚠ **A CONSEQUENCE WORTH HAVING ON PURPOSE: the aal2 step-up clause gates this
--   write through the lock statement itself.** `108`'s policies carry the `025`
--   backstop, and `SELECT … FOR UPDATE` is checked against both the SELECT policy
--   and the UPDATE policy's `USING`. So a totp/passkey-enrolled caller presenting a
--   below-aal2 JWT finds **zero rows to lock** and is refused here, without this
--   function containing a single line about aal2.
--
-- ----------------------------------------------------------------------------
-- ⚠ DRAFT-WINDOW ONLY, AND THE ANSWER TO *"PRE-CHECK OR RELY ON THE TRIGGER?"* IS
--   NEITHER — **THE ILLEGAL STATEMENT IS NEVER CONSTRUCTED.**
--   PM **D-6**, ratified at R4: this write targets a Lock 11 row and is legitimate
--   only inside the draft window. `108`'s immutability trigger already refuses any
--   column change once `generation_status` leaves `draft`.
--   **This function does not pre-check that and does not rely on catching it.** The
--   lock statement's own predicate is `generation_status = 'draft'`, so a `final` or
--   `superseded` row **is not among the rows it can lock**; the UPDATE that follows
--   can only ever name a draft. **The trigger is therefore never reached from this
--   path** — and that is not a reason to think it redundant: it remains the fence for
--   **every other** write path, including a caller reaching `pfin.monthly_report`
--   directly through PostgREST with their own JWT, which is the whole premise of a
--   Lock 14 direct-write surface. **Two controls, disjoint callers.**
--   ⚠ **THE COST OF FILTERING IN THE LOCK, AND HOW IT IS PAID:** a `final` row and a
--   row that does not exist both resolve to zero and would otherwise produce the same
--   unhelpful error. A **second, NON-LOCKING, diagnostic read** classifies the
--   failure so the message can say which — *no report for this month* versus *this
--   month's report is already final*. **That read widens no fence and holds no lock**;
--   it runs under the same RLS, and if it disagrees with the first read (a concurrent
--   finalization landed between them) the message may name the newer state while the
--   refusal is already correct. **A refusal that is right for a slightly stale reason
--   is the acceptable failure here; a wrong write is not.**
--
-- ----------------------------------------------------------------------------
-- REPLACE-ALL IS LITERAL, AND `NULL` IS A VALUE THIS PATH CAN WRITE.
--   All four columns are assigned on every call from the four arguments. **A
--   sub-section the author cleared comes back as `NULL` or `''` and is written as
--   such** — this function has no notion of "unchanged", by design, because the
--   editor submits the whole form. A caller that wants to change one sub-section
--   must send the other three back unchanged; that is what replace-all means and it
--   is why the editor is the only intended caller.
--   ⚠ **`commentary_disposition` IS SET TO `'authored'` ON EVERY SUCCESSFUL CALL**
--   (R12 rider 1), **INCLUDING WHEN ALL FOUR VALUES ARE EMPTY.** Four empty strings
--   are a **legitimate authored state** and are NOT a skip — that is the entire
--   reason the column exists, since the skip cannot otherwise be distinguished from
--   them. **The skip is P4's affordance and is not writable from here.**
--   ⚠ Saving commentary therefore MOVES a report out of the un-dispositioned state,
--   and there is no path back to `NULL` from this function. That is intended:
--   `NULL` means *the author has done neither*, which stops being true the moment
--   they save.
--
-- ----------------------------------------------------------------------------
-- LENGTH: **THIS FUNCTION ADDS NO BOUND.** `108`'s four CHECK constraints are the
--   DB-layer fence, at 4000 **code points** each. A second bound here would be a
--   third fact that can disagree with the other two, and Sec **N-5**'s criterion is
--   an EQUALITY between the app layer and the database — adding a third participant
--   makes that criterion unstatable. A body one character over raises `23514` from
--   the CHECK, through this function, unmodified.
--   ⚠ P3's Zod bound must count **code points** (`Array.from(s).length`), not
--   `s.length` — see `108`'s CONTRACT block for why the unit is the load-bearing
--   half of that mirror.
--
--   ⚠⚠ **FINDING — THE N-5 EQUALITY ALSO DEPENDS ON A CLIENT-SIDE NEWLINE
--   NORMALIZATION THAT THE DATABASE CANNOT VERIFY, AND NOTHING HERE CAN FENCE IT.**
--   P3's ruled AC has the client normalize `\r\n` → `\n` **before counting and
--   before submit**, so a line break is one code point on both sides. **That
--   normalization is the only reason the two layers agree on a multi-line body.** If
--   it is ever dropped — or if any OTHER caller reaches this function or the table
--   through PostgREST without doing it — a body the app counted at 4000 arrives as
--   up to 8000 code points and is refused by `108`'s CHECK, with the app's counter
--   having said it was fine.
--   **This function deliberately does NOT normalize.** Doing so would silently
--   rewrite the author's stored text — line endings are content on a plain-text
--   surface — and would make the DB's count disagree with the bytes it stored, which
--   trades a visible refusal for an invisible mutation. **The right place is the
--   client, which is where the ruling puts it.** Recorded here because it is a third
--   participant in an equality Sec N-5 states over two, and it is invisible from
--   either end: the app sees only normalized text, and the database cannot tell
--   normalized text from text that never contained a carriage return.
--   **QA leg for it is listed below.**
--
-- ----------------------------------------------------------------------------
-- NO AUDIT ROW, AND THAT IS A DECISION RATHER THAN AN OMISSION. `111`'s
--   `fn_emit_audit_log` discharges [ADR-011](DECISIONS.md#adr-011) Decision 1
--   clause (d), which is about **privileged writes** — a write executed under an
--   identity the tenant did not supply. **This write is the tenant, under their own
--   session, editing their own draft.** There is no resolved-tenant question to
--   record and no resolution chain to name, so an audit row here would carry two
--   empty answers to the questions clause (d) exists to ask. The report's own
--   `updated_at` records that a draft was edited. ⚠ Recorded because `111` ships in
--   the same wave and "why does this write not audit?" is the obvious question.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (Lock 11 default; and load-bearing here,
--   since INVOKER is what makes the lock statement a tenant fence at all); NOT
--   SECURITY DEFINER. **The Decision 9 allowlist is UNCHANGED** — read it live; no
--   size is stated here. `set search_path = ''`.
--   **VOLATILITY: `volatile`, DECLARED EXPLICITLY.** It writes, so `stable` would be
--   a false promise the planner is entitled to act on. `volatile` is plpgsql's
--   default, and it is written out anyway because `CREATE OR REPLACE` resets
--   volatility and an explicit declaration is the only form that survives a future
--   re-issue unchanged.
--   EXECUTE revoked from `public`, granted to `authenticated` only — **never to a
--   `rolbypassrls` role**, for which RLS applies to nothing and the EXECUTE grant
--   would be the entire perimeter rather than the weakest fence. ⚠ On THIS function
--   that would be worse than usual: RLS is not merely one of its fences, it is the
--   ONLY thing scoping the row it locks and updates.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — UNTOUCHED. No table, no column, no FK-shaped reference.
--   Read Decision 3 live; no count is carried here.
-- §10 3-AXIS CROSS-CHECK (Decision 4 read VERBATIM and LIVE, 2026-09-05; Path B —
--   not restated, no count carried). (i) instance-numbering: nothing added, removed,
--   reordered or renumbered. (ii) layer-attribution: nothing moves; no surface
--   becomes "four-layer". (iii) verbatim-vs-paraphrase: Decision 4 is LINKED.
--
-- ----------------------------------------------------------------------------
-- Numbering: 112 follows 111. Depends on `108` (the table, its policies and its
--   immutability trigger). Nothing depends on this file.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST (RT-11; two-tenant battery):
--   1. **Cross-tenant:** tenant B calls this for a month tenant A owns → refused,
--      and tenant A's row is UNCHANGED afterwards. ⚠ Assert the second half too — a
--      refusal that still wrote is the failure this leg exists to catch.
--   2. **aal2 as a SEPARATE leg from cross-tenant** (Sec F-9): a totp/passkey-enrolled
--      caller with a below-aal2 JWT is refused. ⚠ It is refused **by finding no row to
--      lock**, so a battery asserting a specific message must assert THIS path's
--      message, not the policy's.
--   3. **Draft window:** the same call against a `final` month → refused, and against
--      a `superseded` month → refused. Then the owner's own `final` row is asserted
--      unchanged.
--   4. **Replace-all is literal:** save four values, then save with two of them empty
--      → the two are now empty, NOT left at their old values.
--   5. **`commentary_disposition` becomes `'authored'`** on a successful save, **and
--      also when all four arguments are empty** — the four-empty-strings-are-authored
--      leg. ⚠ Without the second half the leg passes against an implementation that
--      only sets the disposition when something non-empty was written.
--   6. **Length, with the ruled numbers:** a 4,000-code-point body saves; 4,001 is
--      refused `23514` by the DB **when submitted directly through PostgREST**, not
--      only 400ed by the app — that pair is Sec N-5's criterion and the app half alone
--      proves nothing about this layer.
--   6b. **THE UNIT LEG, and it is the one that fails if anyone reverts to `.length`:**
--      a body of **3,996 ASCII + 4 astral characters** — 4,000 code points, 4,004
--      UTF-16 units — is **ACCEPTED**. ⚠ A battery that only tests ASCII passes
--      identically against both units and cannot tell them apart.
--   6c. **NEWLINES:** a body of 4,000 `\n`-separated code points is accepted, and the
--      SAME body with `\r\n` line endings is **refused** once its code-point count
--      crosses the bound. ⚠ This leg does not test a defect — it **documents the
--      dependency** that the client normalizes before counting, which the database
--      cannot verify and this function deliberately does not perform. See the FINDING
--      above.
--   7. **Return value:** the returned `report_id` is the row that changed.
--   8. **Both roles:** the function is not reachable as `service_role` in a way that
--      bypasses RLS — assert no `rolbypassrls` role holds EXECUTE (standing leg).
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_save_monthly_commentary(
--     p_target_month           date,
--     p_cash                   text,
--     p_bonds                  text,
--     p_marketable_securities  text,
--     p_alternatives           text
--   ) returns bigint  — the `report_id` written.
--   SECURITY INVOKER · volatile · set search_path = '' · EXECUTE: authenticated only.
--   NO tenant parameter. NO report-id parameter — it takes the MONTH, so the caller
--     never has to read the row id separately and then race a concurrent write for it.
--   PRECONDITION: a LIVE DRAFT exists for (auth.uid(), p_target_month). `108`'s
--     partial unique index guarantees there is at most one, so "the draft" is
--     well-defined and this function never has to choose.
--   EFFECT: all four commentary columns are replaced from the arguments and
--     `commentary_disposition` is set to `'authored'`. Nothing else is written;
--     `updated_at` refreshes via `108`'s draft-window trigger.
--   REFUSES, with distinguishable messages: no report for the month · the month's
--     report is not a draft · (implicitly, via RLS) not the caller's, or the caller's
--     session does not meet the aal2 step-up their own settings demand.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_save_monthly_commentary(
  p_target_month          date,
  p_cash                  text,
  p_bonds                 text,
  p_marketable_securities text,
  p_alternatives          text
)
returns bigint
language plpgsql
security invoker
volatile
set search_path = ''
as $$
declare
  v_report_id bigint;
  v_status    text;
begin
  -- (0) SERIALIZATION POINT AND TENANT FENCE, IN ONE STATEMENT, AND IT MUST STAY
  -- FIRST. Under SECURITY INVOKER this resolves through the caller's own RLS, so a
  -- month belonging to another tenant — or a caller whose session does not satisfy
  -- the aal2 step-up their settings demand — finds ZERO ROWS here and the function
  -- refuses below. There is deliberately no `users_id = auth.uid()` predicate: the
  -- policy is the fence, and a hand-written copy of it would read as the fence while
  -- not being it. The `generation_status` predicate is what confines this whole
  -- function to the draft window (ADR-011 Decision 18's 2026-09-03 amendment; the
  -- `101` shape).
  select r.report_id
    into v_report_id
    from pfin.monthly_report r
   where r.target_month      = p_target_month
     and r.generation_status = 'draft'
     for update;

  if v_report_id is null then
    -- DIAGNOSTIC ONLY, and deliberately NOT `for update`: it takes no lock, widens
    -- no fence, and exists solely so the refusal can say WHICH state it found. If a
    -- concurrent finalization lands between the two reads this may name the newer
    -- state while the refusal above is already correct — a refusal that is right for
    -- a slightly stale reason is acceptable; a wrong write is not.
    select r.generation_status::text
      into v_status
      from pfin.monthly_report r
     where r.target_month = p_target_month
     order by r.report_id desc
     limit 1;

    if v_status is null then
      raise exception
        'pfin.fn_save_monthly_commentary: no monthly report exists for % that you can write. Either the month has no report yet, or it is not yours, or your session does not meet the step-up your settings require. Commentary is saved into an existing DRAFT; this function never creates one.',
        p_target_month;
    else
      raise exception
        'pfin.fn_save_monthly_commentary refused: the report for % is `%` and commentary is writable only inside the DRAFT window (PM D-6, ratified at R4). A finalized report is immutable apart from the single final -> superseded transition; regenerate the month to author again.',
        p_target_month, v_status;
    end if;
  end if;

  -- (1) REPLACE-ALL. Every column is assigned from its argument on every call —
  -- there is no notion of "unchanged" here, because the editor submits the whole
  -- form. commentary_disposition becomes 'authored' even when all four values are
  -- empty: four empty strings are a legitimate AUTHORED state and are not a skip,
  -- which is the entire reason that column exists. The skip is P4's affordance and
  -- is not writable from this function. Length is fenced by 108's CHECKs, which
  -- raise 23514 through this call unmodified; no second bound is applied here.
  update pfin.monthly_report r
     set commentary_cash                   = p_cash,
         commentary_bonds                  = p_bonds,
         commentary_marketable_securities  = p_marketable_securities,
         commentary_alternatives           = p_alternatives,
         commentary_disposition            = 'authored'
   where r.report_id = v_report_id;

  return v_report_id;
end;
$$;

revoke execute on function pfin.fn_save_monthly_commentary(date, text, text, text, text) from public;
grant  execute on function pfin.fn_save_monthly_commentary(date, text, text, text, text) to authenticated;

comment on function pfin.fn_save_monthly_commentary(date, text, text, text, text) is
  'The §2.6.2 commentary WRITE path — the DB half of P3 (SELF-355 AC 5); canonical test label RT-11. Replace-all of the four commentary columns on the caller''s LIVE DRAFT for one month, plus commentary_disposition = ''authored''. Returns the report_id written, so a caller can assert it hit the row it meant to. SECURITY INVOKER, volatile (it writes — stable would be a false promise the planner may act on; declared explicitly because CREATE OR REPLACE resets volatility), set search_path = '''' — NOT a SECURITY DEFINER allowlist entry (read ADR-011 Decision 9 live; no size is stated here). EXECUTE revoked from public, granted to authenticated only, NEVER to a rolbypassrls role — and on this function that would be worse than usual, because RLS is not merely one of its fences but the ONLY thing scoping the row it locks and updates. ⚠ THE SHAPE IS RATIFIED, NOT CHOSEN: Lock 14 says replace-all "under SERIALIZABLE", which is NOT REACHABLE FROM THIS TRANSPORT — PostgREST runs each call as its own transaction and SET TRANSACTION ISOLATION LEVEL cannot be issued inside a function body. ADR-011 Decision 18''s 2026-09-03 amendment records the realization this follows: one plpgsql body, therefore one transaction, whose FIRST statement takes a FOR UPDATE row lock (the fn_tax_bracket_schedule_replace_all shape at 101). ⚠ THAT FIRST STATEMENT IS ALSO THE ENTIRE TENANT FENCE: under INVOKER it runs with the caller''s own RLS, so another tenant''s month or an absent one resolves to ZERO ROWS and the function refuses. THERE IS NO TENANT PARAMETER, and there is deliberately NO users_id = auth.uid() PREDICATE IN THE BODY — a hand-written copy of the policy would read as the fence while not being it, and a later reader removing the "redundant" line could not tell which was load-bearing. ⚠ A CONSEQUENCE WORTH HAVING ON PURPOSE: because SELECT ... FOR UPDATE is checked against both the SELECT policy and the UPDATE policy''s USING, the ADR-029 / 025 aal2 step-up clause gates this write through the lock statement itself — a totp/passkey-enrolled caller on a below-aal2 JWT finds no row to lock — without this function containing a line about aal2. ⚠ DRAFT-WINDOW ONLY, and the illegal statement is NEVER CONSTRUCTED rather than pre-checked or caught: the lock predicate includes generation_status = ''draft'', so a final or superseded row is not among the rows it can lock and 108''s immutability trigger is never reached from this path. That does NOT make the trigger redundant — it remains the fence for every OTHER write path, including a caller reaching the table directly through PostgREST with their own JWT, which is the premise of a Lock 14 direct-write surface. Two controls, disjoint callers. A second NON-LOCKING diagnostic read classifies the refusal so the message can distinguish "no report for this month" from "already final"; it takes no lock and widens no fence. ⚠ REPLACE-ALL IS LITERAL: all four columns are assigned every call, so a cleared sub-section is WRITTEN empty and there is no notion of "unchanged" — the editor submits the whole form. commentary_disposition becomes ''authored'' EVEN WHEN ALL FOUR ARE EMPTY, because four empty strings are a legitimate AUTHORED state and not a skip; that distinction is the whole reason the column exists, and the SKIP is P4''s affordance, not writable here. There is no path back to NULL from this function, which is intended: NULL means the author has done neither, and that stops being true the moment they save. LENGTH IS FENCED BY 108''s CHECKS AND NOT HERE — a second bound would be a third fact that can disagree, making Sec N-5''s app-versus-DB EQUALITY unstatable; a body one character over raises 23514 through this call unmodified, and P3''s mirror must count CODE POINTS. NO AUDIT ROW, deliberately: ADR-011 Decision 1 clause (d) governs PRIVILEGED writes, and this is the tenant editing their own draft under their own session — there is no resolved-tenant question to record and no resolution chain to name. JOINT-REVIEW-MANDATORY (a user-reachable write onto a Lock 11 audit-class row).';
