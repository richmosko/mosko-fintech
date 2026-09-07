-- ============================================================================
-- Migration: pfin.fn_regenerate_monthly_report — the A10 REGENERATE affordance
--   (SELF-366 E15 item 10; the Decision 2 transition at `108` item 6(ii)).
--   Phase 6 Build Loop. One SECURITY INVOKER plpgsql function.
--   apply-migration procedure applied.
--   ⚠⚠ JOINT-REVIEW-MANDATORY (Sec veto surface). **This is the ONLY user-reachable
--   path that performs the `final → superseded` transition** — the single mutation
--   [ADR-011](DECISIONS.md#adr-011) Decision 2's immutability rule permits outside
--   the draft window. It is a separate file for exactly that reason.
--
-- ⚠ BRANCH NOTE: authored on a branch STACKED on the A1+A2+A3 design unit
--   (`108`–`111`). **It rebases when that unit does**, and **nothing under
--   `108`–`111` is edited here.**
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ WHY THIS IS ITS OWN FILE AND ITS OWN FUNCTION, RATHER THAN A BRANCH OR A FLAG
--   INSIDE `113`. The question was put to me explicitly, and the reasoning is the
--   part worth keeping:
--     · **A boolean flag on `113` was rejected.** `fn_open_monthly_report_draft(month,
--       p_allow_supersede => true)` keeps one lock site, but it makes *whether a
--       final report gets superseded* a PARAMETER — so a reviewer asking "what can
--       supersede a final report?" has to reason about an argument's value at every
--       call site instead of reading one function. **On the wave's most sensitive
--       transition, the shape should make the answer greppable.**
--     · **Merging the two into one unconditional function was rejected outright.**
--       Then "Generate" on a month whose only row is `final` would **silently
--       supersede it** — destroying a finalized report because the user pressed the
--       wrong button. E15 item 10 makes Regenerate a **`final`-only affordance**, and
--       two affordances with different consequences want two contracts.
--     · **The TOCTOU objection to splitting does not survive contact**, and it was
--       the strongest argument for merging: if the CALLER had to read the state and
--       then choose a function, a concurrent transition between the read and the call
--       would send it to the wrong one. **It does not, because each function reads the
--       state under its OWN lock and refuses if it is not the state it handles.** The
--       caller maps a BUTTON to a function, not a state to a function.
--   **LOSING SIDE, NAMED: two functions now take a lock on rows of the same month**,
--   so a lock-ordering surface exists where a single function had none. It is
--   bounded — both take the month's rows in the same order, and `114` calls `113`
--   rather than running concurrently with it — but it is a surface, and a third
--   writer on this table must be checked against it rather than assumed compatible.
--
-- ----------------------------------------------------------------------------
-- WHAT IT DOES, AND WHAT IT REFUSES.
--   Given a month whose current row is `final`: move that row to `superseded` and
--   open a new `draft`, **in one transaction**, returning the new draft's id.
--   ⚠ **A REGENERATE REQUEST ON A MONTH WHOSE CURRENT ROW IS A `draft` IS ANSWERED BY
--   OPENING THAT DRAFT — never by a second INSERT** (E15 item 10, verbatim in
--   substance). A draft already composes LIVE through the read helper, so
--   "regenerate a draft" has nothing to produce. **This function therefore delegates
--   to `113` in that case rather than refusing**, which is what makes the endpoint
--   answer the user's intent instead of the schema's state machine.
--   ⚠ **A month with NO report at all is also answered by `113`** — the user asked
--   for a draft of that month and there is nothing to supersede. Refusing would be
--   pedantry that the caller would have to work around by calling the other function.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE INSERT SHAPE EXISTS EXACTLY ONCE, AND THAT IS THE POINT OF DELEGATING.
--   This function performs the transition and then **calls
--   `pfin.fn_open_monthly_report_draft`** for the insert half. It does not re-write
--   the INSERT, so the `data_as_of` derivation, the `draft` default, the absent
--   tenant value, the audit-log emission and the race handling all exist in **one**
--   place and cannot drift between the two paths.
--   ⚠ **ORDER IS LOAD-BEARING: the supersede happens FIRST.** `108`'s partial unique
--   index permits at most one `final` per month, and `113` inserts a `draft` — so the
--   two do not collide on the same index and the order is not forced by uniqueness.
--   It is forced by **meaning**: if the insert ran first and the transition then
--   failed, the month would hold a `final` and a `draft` simultaneously with no
--   record that a regeneration was attempted. Doing the irreversible-looking thing
--   first, inside a transaction that can still roll back, keeps the two halves
--   inseparable.
--   ⚠ **AND EXACTLY ONE AUDIT ROW IS WRITTEN**, by the delegated call, because a row
--   IS inserted on this path. The transition itself emits none — `108`'s trigger and
--   the row's own successor are the record that it happened.
--
-- ----------------------------------------------------------------------------
-- ⚠ THIS FUNCTION DOES NOT ENFORCE THE TRANSITION RULE; `108`'s TRIGGER DOES, AND
--   THAT SEPARATION IS DELIBERATE. The UPDATE below sets `generation_status` to
--   `'superseded'` and changes nothing else. If the row were not `final`, if a
--   second column were touched, or if `superseded` were somehow already terminal
--   here, `108`'s immutability trigger refuses — **not this function**. It is a
--   caller of the rule, not a copy of it. A copy would be a second statement of
--   Decision 2's exemption that could drift from the ratified one.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER; NOT SECURITY DEFINER. INVOKER is
--   load-bearing: the caller's RLS is what scopes the row this function supersedes,
--   and `108`'s aal2 clause therefore gates the transition through the lock statement
--   itself. **The Decision 9 allowlist is UNCHANGED** — this file authors no DEFINER
--   function and calls one only transitively, through `113`. Read Decision 9 live; no
--   size stated here. `set search_path = ''`. **VOLATILITY: `volatile`, declared
--   explicitly.** EXECUTE revoked from `public`, granted to `authenticated` only —
--   **never to a `rolbypassrls` role**, which on this function would be the entire
--   perimeter around the wave's most consequential transition.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — UNTOUCHED. No table, no column, no FK-shaped reference.
--   Read Decision 3 live; no count carried.
-- §10 3-AXIS CROSS-CHECK (Decision 4 read VERBATIM and LIVE, 2026-09-05; Path B).
--   (i) instance-numbering unchanged. (ii) no layer attribution moves; no surface
--   becomes "four-layer". (iii) Decision 4 LINKED, never restated.
--
-- ----------------------------------------------------------------------------
-- Numbering: 114 follows 113 and DEPENDS ON IT (it calls
--   `fn_open_monthly_report_draft`). Also depends on `108`.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST (legs land at P10):
--   1. **Regenerate against a `final` month:** the old row is `superseded`, a new
--      `draft` exists, the month holds exactly one of each, and the returned id is
--      the new draft's.
--   2. **Regenerate against a `draft` month INSERTS NOTHING** (E15 item 11 (iii)) and
--      returns the existing draft's id. ⚠ Assert the row count is unchanged, not only
--      that an id came back.
--   3. **Regenerate against a month with NO report** creates one draft and nothing
--      else.
--   4. **Atomicity:** force the delegated insert to fail (e.g. a `target_month` that
--      is not a month start) and assert the `final` row is **still `final`** — the
--      transition must not survive a failed regeneration.
--   5. **Exactly ONE audit row** per successful regeneration; **zero** on the
--      draft-month path. ⚠ Its trigger source is **DERIVED BY THE DELEGATE**, not
--      fixed here: `113` reads the transaction-local GUC `app.report_generation_source`,
--      so a regeneration from an ordinary session records `on_demand` and one issued
--      inside the cron's impersonated block records `cron`. Assert `on_demand` from an
--      ordinary session — and do NOT assert it unconditionally, which would encode the
--      hardcoded value this leg's own defect was.
--   6. **Three regenerations of one month** → three rows, exactly one `final` at each
--      settled point and exactly one `draft` in flight. ⚠ Sec D-5's
--      three-not-two rule applies here too: two regenerations pass against a
--      defective index.
--   7. **Cross-tenant:** tenant B cannot supersede tenant A's `final` row; assert
--      afterwards that A's row is still `final`.
--   8. **aal2 as a separate leg** from cross-tenant.
--   9. **It cannot write `final`:** the new row is a `draft`; the only status this
--      function ever writes is `superseded`, onto a row that was `final`.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_regenerate_monthly_report(p_target_month date) returns bigint
--     — the `report_id` of the LIVE DRAFT the caller should now edit.
--   SECURITY INVOKER · volatile · set search_path = '' · EXECUTE: authenticated only.
--   NO tenant parameter. NO `data_as_of` parameter (derived inside `113`).
--   BEHAVIOUR by the month's current state:
--     · `final` present  → that row moves to `superseded`, a new `draft` is opened,
--                          BOTH IN ONE TRANSACTION; returns the new draft's id.
--     · `draft` present  → returns that draft's id and INSERTS NOTHING.
--     · nothing present  → opens a draft; returns its id.
--   WRITES, on the regenerating path: one `generation_status` UPDATE, one
--     `pfin.monthly_report` INSERT, and one `pfin.audit_log` row — all in the same
--     transaction, the last two via `pfin.fn_open_monthly_report_draft`.
--   REFUSES: via `108`'s immutability trigger, anything the Decision 2 exemption does
--     not permit; via RLS, anything outside the caller's tenancy or step-up level.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_regenerate_monthly_report(p_target_month date)
returns bigint
language plpgsql
security invoker
volatile
set search_path = ''
as $$
declare
  v_final_id bigint;
  v_draft_id bigint;
begin
  -- (0) Is there a live draft already? If so the user's intent is answered by
  -- opening it — a draft composes live, so there is nothing to regenerate INTO
  -- (E15 item 10). Delegating rather than refusing is what makes the endpoint
  -- answer the button rather than the state machine.
  select r.report_id
    into v_draft_id
    from pfin.monthly_report r
   where r.target_month      = p_target_month
     and r.generation_status = 'draft'
     for update;

  if v_draft_id is not null then
    return v_draft_id;
  end if;

  -- (1) The current final, locked. Under SECURITY INVOKER this resolves through the
  -- caller's own RLS, so another tenant's month finds nothing — and 108's aal2
  -- clause gates the transition through this statement without a line about aal2
  -- appearing here. No users_id predicate: the policy is the fence.
  select r.report_id
    into v_final_id
    from pfin.monthly_report r
   where r.target_month      = p_target_month
     and r.generation_status = 'final'
     for update;

  -- (2) SUPERSEDE FIRST, and the order is meaning rather than uniqueness: if the
  -- insert ran first and this failed, the month would hold a final and a draft at
  -- once with no record that a regeneration was attempted. Both halves are in one
  -- transaction, so doing the consequential half first costs nothing and keeps them
  -- inseparable.
  -- ⚠ THIS FUNCTION DOES NOT ENFORCE THE TRANSITION RULE. It sets exactly one column
  -- and changes nothing else; 108's immutability trigger is what permits or refuses
  -- the move. A copy of that rule here would be a second statement of Decision 2's
  -- exemption that could drift from the ratified one.
  if v_final_id is not null then
    update pfin.monthly_report r
       set generation_status = 'superseded'
     where r.report_id = v_final_id;
  end if;

  -- (3) Open the new draft through the ONE place the INSERT shape lives, so the
  -- as-of derivation, the draft default, the absent tenant value, the audit-log
  -- emission and the race handling cannot drift between the two entry paths.
  -- Exactly one audit row is written here, because a row IS inserted on this path;
  -- the transition itself emits none.
  v_draft_id := pfin.fn_open_monthly_report_draft(p_target_month);

  return v_draft_id;
end;
$$;

revoke execute on function pfin.fn_regenerate_monthly_report(date) from public;
grant  execute on function pfin.fn_regenerate_monthly_report(date) to authenticated;

comment on function pfin.fn_regenerate_monthly_report(date) is
  'The A10 REGENERATE affordance (SELF-366 E15 item 10; the Decision 2 transition at 108 item 6(ii)). Returns the report_id of the LIVE DRAFT the caller should now edit. SECURITY INVOKER, volatile, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry; it authors none and calls one only transitively through fn_open_monthly_report_draft (read ADR-011 Decision 9 live; no size stated here). EXECUTE revoked from public, granted to authenticated only, never to a rolbypassrls role — which here would be the entire perimeter around the wave''s most consequential transition. ⚠ JOINT-REVIEW-MANDATORY: THIS IS THE ONLY USER-REACHABLE PATH THAT PERFORMS THE final -> superseded TRANSITION, the single mutation Decision 2''s immutability rule permits outside the draft window, and it is a separate function for exactly that reason. WHY NOT A FLAG ON fn_open_monthly_report_draft: a boolean would make WHETHER A FINAL REPORT GETS SUPERSEDED a parameter, so a reviewer asking "what can supersede a final report?" would have to reason about an argument''s value at every call site instead of reading one function — on this transition the shape should make the answer greppable. WHY NOT ONE UNCONDITIONAL FUNCTION: then "Generate" on a month whose only row is final would SILENTLY SUPERSEDE IT because the user pressed the wrong button; E15 item 10 makes Regenerate a final-only affordance, and two affordances with different consequences want two contracts. THE TOCTOU OBJECTION TO SPLITTING DOES NOT SURVIVE CONTACT — it would hold only if the CALLER had to read the state and then choose; each function reads the state under its OWN lock and handles or delegates, so the caller maps a BUTTON to a function, never a state. ⚠ LOSING SIDE: two functions now lock rows of the same month, so a lock-ordering surface exists where one function had none — bounded, since both take the month''s rows in the same order and this one CALLS the other rather than racing it, but a third writer on this table must be checked against it rather than assumed compatible. BEHAVIOUR BY STATE: a live draft is RETURNED and nothing is inserted (a draft already composes live, so "regenerate a draft" has nothing to produce); a final row is moved to superseded and a new draft opened IN ONE TRANSACTION; a month with no report at all simply gets a draft, because refusing would be pedantry the caller works around by calling the other function. ⚠ THE SUPERSEDE HAPPENS FIRST, and the order is MEANING rather than uniqueness — the two touch different partial indexes and do not collide — because if the insert ran first and the transition then failed, the month would hold a final and a draft at once with no record that a regeneration was attempted. ⚠ THE INSERT SHAPE EXISTS EXACTLY ONCE: this function delegates the insert half rather than re-writing it, so the data_as_of derivation, the draft default, the absent tenant value, the audit emission and the unique_violation race handling cannot drift between the two entry paths. Exactly ONE audit row is written per successful regeneration, by the delegated call, because a row IS inserted; the transition itself emits none — 108''s trigger and the successor row are the record that it happened. ⚠ THIS FUNCTION DOES NOT ENFORCE THE TRANSITION RULE: it sets one column and changes nothing else, and 108''s immutability trigger permits or refuses the move. It is a CALLER of the rule, not a copy of it.';
