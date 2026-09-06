-- ============================================================================
-- Migration: pfin.fn_finalize_monthly_report — the P4 freeze point: the
--   `draft` -> `final` transition that composes A1 item 2's payload and writes it
--   ONCE, in the transition's own transaction (SELF-356 §2.6.2.c; A10 AC item 6).
--   Phase 6 Build Loop. ONE SECURITY INVOKER plpgsql function; no new table, no new
--   column, no new policy. apply-migration procedure applied.
--   ⚠⚠ JOINT-REVIEW-MANDATORY (Sec veto surface): a user-reachable WRITE performing
--   the one transition that makes an [ADR-011](DECISIONS.md#adr-011) Decision 2
--   audit-class row immutable. After this function returns, every column on the row
--   is read-only forever.
--
-- ⚠ BRANCH NOTE: authored on a branch STACKED on the A1+A2+A3 design unit
--   (`108`–`111`). **It rebases when that unit does**, and **nothing under
--   `108`–`111` is edited here.**
--
-- ----------------------------------------------------------------------------
-- WHAT IT DOES. Takes the caller's live draft for a month, records whether the
--   author wrote commentary or explicitly skipped it, composes the report through
--   `110`, freezes the result into the row, and promotes the row to `final` — all in
--   ONE transaction, so **a half-finalized report cannot exist**. That single-
--   transaction property is the requirement, not an implementation nicety: the
--   payload column and the status column are two halves of one fact, and a crash
--   between them would leave a `final` row with no artifact (which `108`'s
--   `monthly_report_payload_by_status` CHECK would refuse) or an artifact on a row
--   still advertising itself as editable.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE ORDER IS LOAD-BEARING AND IS NOT THE ORDER IT LOOKS LIKE.
--   **The disposition is written BEFORE the composition, not with it.**
--   `110` builds `sections.rebalancing_targets.disposition` **by reading
--   `commentary_disposition` off the draft row**. So composing first and writing the
--   disposition afterwards would freeze a payload whose disposition field is NULL
--   while the column beside it says `authored` — permanently, on an immutable row,
--   with no way to tell which one a later reader should believe.
--   The sequence is therefore:
--     (1) lock the live draft (`FOR UPDATE`);
--     (2) UPDATE the disposition — **still `draft`**, so this is an ordinary draft
--         edit and `108`'s immutability trigger returns early on it;
--     (3) snapshot the owner header;
--     (4) compose via `110`, which now sees the disposition;
--     (5) assert the composition is ABOUT the row we locked;
--     (6) INSERT the Lock 12 per-account children — **still `draft`**, which `109`'s
--         FLAG-4 fence now REQUIRES;
--     (7) ONE UPDATE writes the payload, its version, the freeze instant, the owner
--         header and `generation_status = 'final'`.
--   ⚠ Steps (2) and (6) are two UPDATEs by NECESSITY, not by preference — `110` reads
--   committed-in-transaction state, so there is no ordering in which one statement
--   both supplies its input and consumes its output. **Do not "simplify" them into
--   one.**
--
-- ----------------------------------------------------------------------------
-- ⚠ THE FREEZE INSTANT IS `generated_at`. THERE IS NO `finalized_at` COLUMN AND NONE
--   IS ADDED. `108` already designates the slot and proves it by construction:
--   `monthly_report_payload_by_status` requires `generated_at` NOT NULL on `final`
--   and `superseded`, `113` does not set it when it inserts the draft, and `108`'s
--   own column comment defines it as *"the wall-clock instant the rendered payload
--   was FROZEN"*. Adding a second timestamp would create two answers to one question
--   on an immutable row.
--   `now()` is the TRANSACTION timestamp, which is the wanted semantics: the compose
--   and the freeze share one clock, exactly as `data_as_of` threads one date through
--   the whole composition (Lock 15, ONE CALL ONE CLOCK).
--
-- ----------------------------------------------------------------------------
-- ⚠ IT WRITES `owner_header_at_generation`, WHICH NOTHING ELSE DOES.
--   `108` records that the header is *"part of R1's frozen content, copied here
--   rather than joined live — the Lock 14 settings store carries no edit history, so
--   a live join could not reproduce what the report actually said."* **This function
--   is the only surface at which that copy can happen**, because finalization is the
--   only moment there is something to freeze. Were it omitted, the column would be
--   NULL on every row in the shipped product and `108`'s stated rationale would be
--   false in practice while remaining true on paper.
--   ⚠ **NULL IS A LEGITIMATE VALUE, NOT A FAILURE** (PM A-13, authorized at R10): a
--   report generated before the user set a header stays NULL, and renders as an
--   in-app prompt with NO PDF line — never an empty line or a placeholder. So this
--   reads the header and does not require one. The read is scoped by the caller's
--   own RLS on `pfin.owner_identification` (`106`), which holds at most one row per
--   tenant by its `unique (users_id)`.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ IT WRITES THE LOCK 12 CHILDREN, AND IT IS THEIR ONLY WRITER IN THE PRODUCT.
--   Before this, `pfin.monthly_report_account_snapshot` had **no legitimate writer
--   anywhere** in `supabase/migrations`, `api` or `workers` (swept 2026-09-05). It
--   shipped with RLS, grants, its Decision 3 #4 matched-account fence and an
--   immutability trigger, and was **always empty** — so any row in it could only have
--   arrived through the `authenticated` INSERT grant, i.e. caller-originated.
--   ⚠ **THREE CONTROLS WERE HOLLOW AND ONE PRODUCT SURFACE WAS DEGRADED**, which is
--   the difference between a gap and a latent gap: the #4 fence had nothing to fence,
--   `109`'s FLAG-4 parent-must-be-draft predicate had nothing to refuse, ADR-068
--   Decision 7's queryable-index justification had nothing to filter — and **P8's
--   staleness banner takes its account membership from this table for `final`
--   reports, so with the table empty it degrades to the full live-stale set forever.**
--   That last one is a live defect, not a latent one.
--   **THIS SITE WAS CHOSEN, and `109` had already assumed it**: its own header reads
--   *"children are written at finalization, so a genuine draft has none."* Finalization
--   is the moment the names and tax treatments are frozen, so writing them anywhere
--   else would capture them at a different instant than the payload they accompany.
--   ⚠ **THE ORDERING IS ENFORCED, NOT MERELY INTENDED, AND THE TWO CHANGES PROVE EACH
--   OTHER.** FLAG-4 gave `109`'s BEFORE INSERT fence a parent-must-be-`draft`
--   predicate, so these rows MUST be inserted before the status flip — and the fence
--   stops being moot precisely because a writer now exists.
--   ⚠ **THE ACCOUNT SET IS THE PAYLOAD'S, NOT THE CALLER'S.** `fn_nav_composition`
--   deliberately excludes tax-authority ledger accounts, so snapshotting every account
--   the caller owns would describe a **different set than the report shows**. The
--   values (`acct_name_at_generation`, `tax_treatment_at_generation` — `109`'s
--   contract) are read from `pfin.account` in this same transaction under the caller's
--   own RLS, which is the same read that produced the payload's `account_name` moments
--   earlier; they agree by construction. `tax_treatment` is not in the payload at all.
--   ⚠ **REVERSIBILITY, STATED: this is not a schema one-way door, but each ROW is
--   permanent.** `109`'s children are immutable and DELETE-blocked, so a report frozen
--   with the wrong set keeps it — the correction is to REGENERATE the month, which
--   writes a new parent with its own children. Changing the SOURCE later (payload vs
--   live account set) is a migration that affects future reports only; it cannot
--   retro-fix frozen ones.
--
-- ----------------------------------------------------------------------------
-- ⚠ `included_reconciliation_event_ids` IS DELIBERATELY NOT WRITTEN.
--   `108` states, verified by grep at its authoring, that **no V1.5 surface writes
--   that array at all** — it is empty on every row in the shipped product, and its
--   Decision 3 #3 matched-tenant fence is correspondingly dormant on the product
--   path. Populating it here would be scope creep onto a Decision 3 surface and would
--   silently activate a fence nobody has asked to activate. The column keeps `108`'s
--   `'{}'` default. **Stated rather than left to inference, because "the finalize
--   path freezes the report" reads like an invitation to freeze this too.**
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ NO AUDIT ROW IS EMITTED, AND THAT IS A DECISION WITH A NAMED ALTERNATIVE —
--   NOT AN OMISSION. Read this before "fixing" it.
--   `pfin.audit_log`'s `audit_log_surface_name_vocab` CHECK admits exactly ONE
--   surface today, `monthly_report_generation`, and R7 rider 5 fixes that the
--   vocabulary **grows only by migration**. A finalize event is not a generation
--   event, so emitting one would require adding a member — and that is a **ONE-WAY
--   DOOR**: the table blocks UPDATE and DELETE, so the first finalize row written
--   under a new surface name can never be removed, and the CHECK can never be
--   narrowed back.
--   **It is also someone else's hazard.** `111`'s own `data_as_of` column comment
--   records that the V1.final "month of operation" measurement *"reads exactly this
--   field alongside `trigger_source = 'cron'`"* — with **no surface filter**. Adding
--   a second surface that a cron-initiated transaction could write would therefore
--   change that measurement's result without touching the measurement, which is the
--   shape of defect that gets attributed to the query rather than to this migration.
--   **What is taken instead: the ROW IS THE RECORD.** After this function returns,
--   `generation_status = 'final'`, `generated_at` carries the freeze instant,
--   `users_id` carries the tenant, and `108`'s immutability trigger makes every one
--   of those permanently unforgeable — a stronger record than an append-only log
--   entry, because it cannot drift from the artifact it describes. **This is the
--   reasoning `114` already applies, verbatim in kind, to the sibling transition:**
--   *"the transition itself emits none — `108`'s trigger and the successor row are
--   the record that it happened."* Two transitions on one table now answer the same
--   way.
--   ⚠ **THE ALTERNATIVE WAS COSTED AND IS RULED CLOSED (E45), NOT MERELY DECLINED:**
--   add `monthly_report_finalization` to the vocabulary and emit through `111`. It
--   buys one thing the row cannot give — WHICH PATH finalized. It costs the one-way
--   door above, and it **requires the V1.final measurement's predicate to gain
--   `surface_name = 'monthly_report_generation'` IN THE SAME PR**, or N is overcounted
--   from the first finalize.
--
--   ⚠⚠ **REVIVAL CONDITION — THE "NOT PRIVILEGED" HALF OF THIS ARGUMENT IS SCOPED,
--   NOT PERMANENT, AND THE SCOPE IS "USER-ONLY"** (Sec, accepting the
--   no-audit-at-finalize call with this condition attached). The reason no audit row
--   is owed is that finalization is performed **by the tenant, in their own session,
--   under their own RLS** — it is not a privileged-context write, so
--   [ADR-011](DECISIONS.md#adr-011) Decision 1 clause (d) does not attach and the row
--   genuinely is the record.
--   **THE FIRST WORKER OR CRON SURFACE THAT CALLS THIS FUNCTION ENDS THAT.** An
--   auto-finalize, a close-the-month job, a backfill — any caller reaching
--   `fn_finalize_monthly_report` from an impersonated or `service_role` session makes
--   this a **privileged-context write**, clause (d) attaches immediately, and **the
--   alternative above stops being an alternative and becomes MANDATORY**.
--   ⚠ **THE TRIGGER CANNOT SUPPLY IT, AND THAT IS THE TRAP INSIDE THIS CONDITION.**
--   `111`'s emitter is `AFTER INSERT` and this function performs UPDATEs only, so a
--   worker-initiated finalize would emit **nothing at all while looking audited** —
--   the surface would be **silently uncovered rather than visibly missing**, which is
--   the failure mode that survives review. **Whoever adds that caller owes the
--   emission in the same PR**, as a Sec joint-review event, because it grows
--   `audit_log_surface_name_vocab` — a one-way door on an append-only table.
--   ⚠ **THE CHECKABLE FORM OF THIS CONDITION, so it does not rest on a reader
--   noticing:** EXECUTE on this function is granted to `authenticated` **and to no
--   other role**. A grant to `service_role`, or to any new role, IS the moment the
--   condition fires — watch the grant, not the prose.
--
-- ----------------------------------------------------------------------------
-- ⚠ AUTHOR-BEFORE-GENERATE IS A DISPOSITION, NOT A CONTENT CHECK (R12 rider 1).
--   `p_commentary_disposition` is `authored` or `skipped`, and **`authored` does NOT
--   require non-empty commentary — four empty strings ARE an authored state**, which
--   is ruled. So this function validates the VOCABULARY and never inspects the four
--   commentary columns. **Written down because the opposite is the natural
--   assumption**, and a well-meaning later edit adding "authored implies non-blank"
--   would refuse a state the product defines as valid.
--   The vocabulary is re-checked in the body although `108`'s
--   `monthly_report_commentary_disposition_vocab` CHECK also enforces it. That is a
--   MESSAGE, not a second fence: `108`'s CHECK is directly reachable through
--   PostgREST and remains the enforcement point; the body raise exists so a caller of
--   THIS function is told about R12 rider 1 rather than reading a bare 23514.
--   ⚠ The §7.34 item 2 pre-finalize prompt (no designated tax-authority ledger) is
--   **P4/P5 UI and is NOT enforced here** — it is a prompt, not a gate, and encoding
--   it in the DB would convert a nudge into a refusal.
--
-- ----------------------------------------------------------------------------
-- ⚠ NO TENANT PARAMETER AND NO `data_as_of` PARAMETER (Gate A; Lock 15; RT-25).
--   The tenant is the session, as in `112` / `113`. The as-of is **the row's own
--   `data_as_of`**, read from the draft under lock and threaded into `110` unchanged
--   — so the frozen artifact is composed at the as-of the draft was opened at, and
--   there is no argument by which a caller could compose "as of" some other day.
--   ⚠ **AND THERE IS DELIBERATELY NO `users_id = auth.uid()` PREDICATE IN THE BODY**,
--   for the reason `112` records: a hand-written copy of the policy reads as the
--   fence while not being it, and a later reader removing the "redundant" line could
--   not tell which was load-bearing.
--
-- ----------------------------------------------------------------------------
-- ⚠ MONOTONICITY IS ENFORCED BY `108`, NOT COPIED HERE (R4). The `FOR UPDATE` read
--   selects on `generation_status = 'draft'`, so a month whose report is already
--   `final` or `superseded` yields no row and is refused before anything is written.
--   The refusal message **does not discriminate** absent / not-yours / already-final:
--   under RLS those are one condition, and separating them leaks existence — the
--   same reasoning `058` applies to its close gate.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE COMPOSITION IS ASSERTED TO BE ABOUT THE ROW WE LOCKED (Finding 4).
--   `110` selects its own draft row — the highest `report_id` in `draft` for
--   `(auth.uid(), target_month)` — and echoes it back as
--   `sections.rebalancing_targets.source_report_id` **precisely so a caller can check
--   it**. This function checks it and RAISES on mismatch. Without that check, a future
--   divergence between `110`'s selection and this function's lock would freeze one
--   draft's numbers onto another draft's row, and every fence involved would report
--   success. `108`'s one-live-draft-per-month partial unique index makes the two
--   agree today; the assertion is what will notice if that ever stops being true.
--   `payload_schema_version` is likewise EXTRACTED FROM THE PAYLOAD rather than
--   hardcoded, so the column and the artifact cannot disagree about which schema was
--   frozen.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER; NOT SECURITY DEFINER. INVOKER is
--   load-bearing rather than merely default: it is what scopes the draft read, the
--   owner-header read and BOTH UPDATEs by the caller's own RLS and the `025` aal2
--   clause, and it is what makes `110`'s composition run as the caller so every
--   figure in the frozen payload is one the caller was entitled to see. **A DEFINER
--   posture here would compose one tenant's report with another tenant's
--   visibility.** The Decision 9 allowlist is UNCHANGED by this file — it authors no
--   DEFINER function and, unlike `113`, calls none. Read Decision 9 live; no size is
--   stated here.
--   `set search_path = ''`. **VOLATILITY: `volatile`, declared explicitly** — it
--   writes, and an explicit declaration is the form that survives a future
--   `CREATE OR REPLACE`, which resets volatility.
--   EXECUTE revoked from `public`, granted to `authenticated` only — **never to a
--   `rolbypassrls` role**, for which RLS applies to nothing and the EXECUTE grant
--   would be the entire perimeter around the wave's freeze point.
--
-- ----------------------------------------------------------------------------
-- ⚠ PERFORMANCE: THE RENDER BUDGET APPLIES HERE, AND THIS IS ITS WORST CASE.
--   ≤ 2000 ms p95 synchronous, per the closed `110` probe. This path is strictly
--   heavier than the probe measured: it is `110`'s composition PLUS two UPDATEs and a
--   row lock, and it holds `FOR UPDATE` on the draft for the whole composition. That
--   lock duration is acceptable because the only contender is another finalize or a
--   commentary save on the SAME month by the SAME tenant — never a cross-tenant or
--   cross-month waiter. **If the budget is ever missed, the answer is not to move the
--   composition outside the transaction**: that would reintroduce exactly the
--   half-finalized report this function exists to make impossible.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — UNTOUCHED. No table, no column, no FK-shaped reference; the
--   one FK-shaped column in reach (`included_reconciliation_event_ids`) is
--   deliberately not written. Read Decision 3 live; no count carried.
-- §10 3-AXIS CROSS-CHECK (Decision 4 read VERBATIM and LIVE, 2026-09-05; Path B).
--   (i) instance-numbering: nothing added, removed, reordered or renumbered.
--   (ii) layer-attribution: nothing moves; no surface becomes "four-layer".
--   (iii) verbatim-vs-paraphrase: Decision 4 is LINKED, never restated.
--
-- ----------------------------------------------------------------------------
-- Numbering: 115 follows 114. Depends on `108` (the table, its status CHECK, its
--   disposition vocabulary CHECK, its immutability trigger and its one-final-per-month
--   partial unique index), `110` (`fn_render_monthly_report`) and `106`
--   (`pfin.owner_identification`). Nothing depends on this file yet; P4's UI calls it.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST (legs land at P10):
--   1. **Finalize a draft** → the row is `final`, `rendered_payload` is NOT NULL, and
--      the payload's `sections.rebalancing_targets.source_report_id` **equals the
--      returned id**. ⚠ The echo half is the leg — a payload that is merely non-NULL
--      passes a NOT NULL check while being about a different row.
--   2. **Finalize twice** → the second call is REFUSED (no live draft remains), and
--      the row is unchanged — assert `generated_at` did not move, not merely that an
--      error was raised.
--   3. **Finalize a `final` month** → refused. **Finalize a `superseded` month** →
--      refused. Two legs: they fail at different fences and a single leg proves one.
--   4. **Cross-tenant:** tenant B finalizing tenant A's month affects ZERO rows and
--      A's report is still `draft` afterwards. ⚠ Assert A's state after, not only
--      that B got an error.
--   5. **aal2 as a separate leg** from cross-tenant (Sec F-9).
--   6. **ATOMICITY:** a transaction that finalizes and then ROLLS BACK leaves the row
--      `draft` with `rendered_payload` NULL, `generated_at` NULL, **and the
--      disposition NULL** — the third is the one that catches the two-UPDATE shape
--      leaking a committed half.
--   7. **DISPOSITION-BEFORE-COMPOSE, the ordering leg and the reason this file exists
--      in the order it does:** finalize with `'skipped'` and assert the FROZEN
--      payload's `sections.rebalancing_targets.disposition` is `'skipped'` — **not
--      NULL**. ⚠ A version that composed first passes every other leg here.
--   8. **The disposition vocabulary is enforced**: `'authored'` and `'skipped'`
--      succeed; NULL and an invented value are refused.
--   9. **`'authored'` with four EMPTY-STRING commentary columns SUCCEEDS** (R12 rider
--      1). ⚠ A leg asserting the opposite would encode a gate the product does not
--      have.
--  10. **The immutability trigger then blocks every later column write**: after
--      finalize, an UPDATE of `rendered_payload`, of a commentary column, and of
--      `owner_header_at_generation` are each refused, and the ONLY permitted move is
--      `final` -> `superseded`.
--  11. **`owner_header_at_generation` is frozen from `106`**: set a header, finalize,
--      change the header, and assert the report still carries the OLD one. ⚠ That
--      third step is the leg — copying a value and joining it live are
--      indistinguishable until the source changes.
--  12. **A tenant with NO owner-identification row finalizes successfully** with
--      `owner_header_at_generation` NULL (PM A-13). A refusal here would be the
--      defect.
--  13. **`payload_schema_version` equals the payload's own
--      `payload_schema_version`** — not a hardcoded 1.
--  14. **`included_reconciliation_event_ids` is still `'{}'`** after finalize.
--  14a. **THE CHILDREN ARE WRITTEN, and the set matches the payload EXACTLY** — one
--      `monthly_report_account_snapshot` row per account appearing in
--      `rendered_payload -> 'sections' -> 'account_holdings' -> 'groups' -> … ->
--      'accounts'`, with the same `account_id` set. ⚠ Assert **set equality in both
--      directions**, not just a non-zero count: a writer that captured every account
--      the caller owns passes a count check and captures a DIFFERENT set, because the
--      composition excludes tax-authority ledger accounts.
--  14b. **A tenant holding a tax-authority ledger account finalizes, and that account
--      is ABSENT from the children.** This is the leg that discriminates the two
--      candidate sources; without it, 14a passes for a live-account-table writer on
--      any tenant that happens to have no ledger account.
--  14c. **`acct_name_at_generation` and `tax_treatment_at_generation` are FROZEN:**
--      finalize, then rename the account and change its tax treatment, and assert the
--      child row still carries the old values. ⚠ The third step is the leg — a copy
--      and a live join are indistinguishable until the source changes.
--  14d. **Rollback takes the children with it** — abort the finalize transaction and
--      assert zero snapshot rows for that report, alongside the existing leg 6.
--  14e. **The children are immutable and DELETE-blocked afterwards**, and the parent
--      cannot be deleted while they exist (`ON DELETE RESTRICT`).
--  14f. **⚠ FLAG-4 IS NO LONGER MOOT AND THE LEG MUST NOW BE DRIVEN THROUGH THIS
--      FUNCTION:** a direct INSERT against a `final` parent is still refused, and the
--      finalize path succeeds only because it inserts while the parent is still
--      `draft`. Assert both — the refusal alone passed while the table was empty.
--  14g. **A tenant with NO accounts finalizes successfully with ZERO children.** An
--      empty set is a valid outcome, not a failure.
--  15. **`data_as_of` is unchanged by finalization** and the payload's `as_of` equals
--      it — the draft's as-of is what was composed, and no clock was re-derived.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.fn_finalize_monthly_report(p_target_month date, p_commentary_disposition text)
--     returns bigint — the `report_id` of the row it froze.
--   SECURITY INVOKER · volatile · set search_path = '' · EXECUTE: authenticated only.
--   NO tenant parameter. NO `data_as_of` parameter — the row's own `data_as_of` is
--     threaded into `110` unchanged.
--   WRITES, in ONE transaction: `commentary_disposition`, then the Lock 12 per-account
--     children (`pfin.monthly_report_account_snapshot`, one row per account in the
--     composed payload — THIS FUNCTION IS THEIR ONLY WRITER IN THE PRODUCT), then
--     `rendered_payload` +
--     `payload_schema_version` + `generated_at` + `owner_header_at_generation` +
--     `generation_status = 'final'`. Writes NO audit-log row — see the block above.
--   REFUSES: a month with no live draft (absent / already final / already superseded
--     / another tenant's — one undifferentiated condition under RLS); a disposition
--     outside `authored` / `skipped`; a composition that does not echo the locked row.
--   AFTER IT RETURNS the row is immutable except for `final` -> `superseded`.
--   ⚠ NO AUDIT ROW — and that holds ONLY WHILE FINALIZE IS USER-ONLY (see the revival
--     condition above). EXECUTE granted to `authenticated` and to NO other role is the
--     checkable form of that scope.
-- ============================================================================

create schema if not exists pfin;

create or replace function pfin.fn_finalize_monthly_report(
  p_target_month           date,
  p_commentary_disposition text
)
returns bigint
language plpgsql
security invoker
volatile
set search_path = ''
as $$
declare
  v_report_id  bigint;
  v_data_as_of date;
  v_owner_hdr  text;
  v_payload    jsonb;
  v_echoed_id  bigint;
begin
  -- (0) Vocabulary. 108's CHECK is the enforcement point and is directly reachable
  -- through PostgREST; this raise exists so a caller of THIS function learns the rule
  -- instead of reading a bare 23514. It validates the DISPOSITION and never the
  -- commentary: R12 rider 1 makes four empty strings an AUTHORED state.
  if p_commentary_disposition is null
     or p_commentary_disposition not in ('authored', 'skipped') then
    raise exception
      'pfin.fn_finalize_monthly_report refused: p_commentary_disposition must be ''authored'' or ''skipped'' (108 monthly_report_commentary_disposition_vocab; PRD author-before-generate). Attempted: %. ⚠ ''authored'' does NOT require non-empty commentary — four empty strings are an authored state (R12 rider 1) — so the choice here is the AUTHOR''S DECLARATION, not a content assessment.',
      coalesce(p_commentary_disposition, '<null>');
  end if;

  -- (1) The live draft, LOCKED for the whole transition. Under SECURITY INVOKER this
  -- resolves through the caller's own RLS — there is deliberately no users_id
  -- predicate here; the policy is the fence. Selecting on 'draft' is also what
  -- enforces R4 monotonicity: a final or superseded month simply yields no row.
  select r.report_id, r.data_as_of
    into v_report_id, v_data_as_of
    from pfin.monthly_report r
   where r.target_month      = p_target_month
     and r.generation_status = 'draft'
     for update;

  if v_report_id is null then
    -- Undifferentiated by design: absent, another tenant's, already final and already
    -- superseded are ONE condition under RLS, and separating them leaks existence.
    raise exception
      'pfin.fn_finalize_monthly_report refused: no live draft for that month. A report is finalized ONCE, from the draft state (V1.5 pre-flight ruling R4); a month that is already final must be regenerated (pfin.fn_regenerate_monthly_report) before it can be finalized again.';
  end if;

  -- (2) THE DISPOSITION IS WRITTEN FIRST, WHILE THE ROW IS STILL `draft`.
  -- This is not stylistic ordering: 110 builds the payload's
  -- sections.rebalancing_targets.disposition BY READING THIS COLUMN, so composing
  -- before writing it would freeze NULL into the artifact while the column beside it
  -- said 'authored' — permanently, on a row that can never be corrected. 108's
  -- immutability trigger returns early for a draft, so this is an ordinary draft edit.
  update pfin.monthly_report
     set commentary_disposition = p_commentary_disposition
   where report_id = v_report_id;

  -- (3) The owner header, SNAPSHOT rather than joined live — the Lock 14 settings
  -- store keeps no edit history, so a live join could not reproduce what the report
  -- actually said. Scoped by the caller's RLS on 106, which holds at most one row per
  -- tenant. NULL IS A VALID OUTCOME (PM A-13): a tenant who never set a header
  -- finalizes successfully and renders an in-app prompt, never a placeholder line.
  select o.owner_id_header_text
    into v_owner_hdr
    from pfin.owner_identification o;

  -- (4) COMPOSE. The row's OWN data_as_of is threaded in unchanged — Lock 15's one
  -- call, one clock — so the frozen artifact is composed at the as-of the draft was
  -- opened at, and no caller has an argument with which to compose as of another day.
  v_payload := pfin.fn_render_monthly_report(p_target_month, v_data_as_of);

  -- (5) ASSERT THE COMPOSITION IS ABOUT THE ROW WE LOCKED (Finding 4). 110 selects
  -- its own draft row and echoes its id back for exactly this check. They agree today
  -- because 108's one-live-draft-per-month partial unique index makes them agree; this
  -- assertion is what notices if that ever stops being true, instead of freezing one
  -- draft's numbers onto another draft's row with every fence reporting success.
  v_echoed_id := (v_payload #>> '{sections,rebalancing_targets,source_report_id}')::bigint;
  if v_echoed_id is distinct from v_report_id then
    raise exception
      'pfin.fn_finalize_monthly_report refused: the composed payload is about report_id % but this transaction locked report_id %. Refusing rather than freezing one draft''s figures onto another draft''s row (SELF-347 Finding 4). This should be unreachable while 108''s one-live-draft-per-month partial unique index holds.',
      coalesce(v_echoed_id::text, '<null>'), v_report_id;
  end if;

  -- (6) THE LOCK 12 CHILDREN — WRITTEN HERE, AND NOWHERE ELSE IN THE PRODUCT.
  -- ⚠ Until this statement existed, pfin.monthly_report_account_snapshot had NO
  -- legitimate writer anywhere in supabase/migrations, api or workers (verified by
  -- sweep, 2026-09-05): it shipped with RLS, grants, its Decision 3 #4 matched-account
  -- fence and an immutability trigger, and was ALWAYS EMPTY. Three things were hollow
  -- because of that, and all three become live here: the #4 fence had nothing to
  -- fence, 109's parent-must-be-draft predicate had nothing to refuse, and ADR-068
  -- Decision 7's queryable-index justification had nothing to filter. ⚠ A FOURTH is
  -- a live product defect rather than a latent one: P8's staleness banner takes its
  -- account membership from this table for FINAL reports and, with the table empty,
  -- degrades to the full live-stale set forever.
  -- ⚠⚠ IT MUST PRECEDE THE STATUS FLIP, AND 109's OWN FENCE IS WHAT MAKES THAT TRUE.
  -- FLAG-4 added `parent must be draft` to 109's BEFORE INSERT fence, so inserting
  -- these rows after `generation_status = 'final'` would be REFUSED. The ordering is
  -- therefore enforced, not merely intended — and the two changes prove each other:
  -- the fence stops being moot because a writer exists, and the writer cannot drift
  -- past the fence.
  -- ⚠ THE ACCOUNT SET COMES FROM THE COMPOSED PAYLOAD, NOT FROM pfin.account.
  -- Reading every account the caller owns would capture a DIFFERENT set: the
  -- composition deliberately excludes tax-authority ledger accounts, so a live read
  -- would snapshot accounts the report does not show. The payload is the artifact
  -- being frozen, so its account set is the one the children must describe.
  -- ⚠ THE VALUES come from pfin.account, read in THIS transaction under the caller's
  -- own RLS — which is the same read, at the same instant, that produced the payload's
  -- account_name moments earlier, so they agree BY CONSTRUCTION rather than by luck.
  -- tax_treatment is not carried in the payload at all, which is why the join is
  -- needed rather than optional.
  -- ⚠ NO `on conflict` CLAUSE, DELIBERATELY. 109's unique (monthly_report_id,
  -- account_id) is a real watcher here: fn_nav_composition groups by
  -- account.account_type, and an account has exactly one, so a duplicate would mean
  -- the composition itself is malformed. Swallowing that would freeze a report whose
  -- children silently disagree with its payload.
  insert into pfin.monthly_report_account_snapshot
    (monthly_report_id, account_id, acct_name_at_generation, tax_treatment_at_generation)
  select v_report_id, a.account_id, a.name, a.tax_treatment
    from jsonb_array_elements(v_payload #> '{sections,account_holdings,groups}') g
    cross join lateral jsonb_array_elements(g -> 'accounts') acc
    join pfin.account a on a.account_id = (acc ->> 'account_id')::bigint;

  -- (7) FREEZE. One statement, same transaction: payload, its version (taken FROM the
  -- payload so column and artifact cannot disagree), the freeze instant (now() is the
  -- TRANSACTION timestamp, so compose and freeze share one clock), the owner-header
  -- snapshot, and the promotion. After this commits, 108's immutability trigger makes
  -- every column read-only and the only remaining move is final -> superseded.
  update pfin.monthly_report
     set rendered_payload           = v_payload,
         payload_schema_version     = (v_payload ->> 'payload_schema_version')::smallint,
         generated_at               = now(),
         owner_header_at_generation = v_owner_hdr,
         generation_status          = 'final'
   where report_id = v_report_id;

  return v_report_id;
end;
$$;

revoke execute on function pfin.fn_finalize_monthly_report(date, text) from public;
grant  execute on function pfin.fn_finalize_monthly_report(date, text) to authenticated;

comment on function pfin.fn_finalize_monthly_report(date, text) is
  'The P4 FREEZE POINT (SELF-356 §2.6.2.c; A10 AC item 6): the draft -> final transition that composes A1 item 2''s payload and writes it ONCE, in the transition''s own transaction, so a HALF-FINALIZED REPORT CANNOT EXIST — the payload column and the status column are two halves of one fact, and a crash between them would leave either a final row with no artifact (which 108''s payload-by-status CHECK refuses) or an artifact on a row still advertising itself as editable. Returns the report_id it froze. SECURITY INVOKER, volatile, set search_path = '''' — and INVOKER is LOAD-BEARING, not merely default: it scopes the draft read, the owner-header read and both UPDATEs by the caller''s RLS and the aal2 clause, and it makes 110''s composition run AS THE CALLER so every figure frozen is one the caller was entitled to see; a DEFINER posture here would compose one tenant''s report with another tenant''s visibility. It authors no DEFINER function and, unlike fn_open_monthly_report_draft, calls none — read ADR-011 Decision 9 live; no size stated here. EXECUTE revoked from public, granted to authenticated only, never to a rolbypassrls role. ⚠ JOINT-REVIEW-MANDATORY: a user-reachable write performing the ONE transition that makes a Decision 2 audit-class row immutable — after it returns, every column is read-only forever. ⚠⚠ THE ORDER IS LOAD-BEARING AND IS NOT THE ORDER IT LOOKS LIKE: the disposition is written BEFORE the composition, because fn_render_monthly_report builds sections.rebalancing_targets.disposition BY READING commentary_disposition off the draft row, so composing first would freeze NULL into the artifact while the column beside it said ''authored'' — permanently, on a row that can never be corrected. The two UPDATEs are a NECESSITY, not a preference: no single statement can both supply 110''s input and consume its output. Sequence: lock the live draft FOR UPDATE; UPDATE the disposition while still draft (an ordinary draft edit, which 108''s immutability trigger returns early on); snapshot the owner header; compose; assert; freeze. ⚠ THE FREEZE INSTANT IS generated_at AND NO finalized_at COLUMN IS ADDED — 108 already designates the slot and proves it by construction (payload-by-status requires it NOT NULL on final, the draft insert does not set it, and its column comment defines it as the instant the payload was frozen); a second timestamp would give an immutable row two answers to one question. now() is the TRANSACTION timestamp, so compose and freeze share one clock. ⚠ IT WRITES owner_header_at_generation, WHICH NOTHING ELSE DOES: 108 requires the header COPIED rather than joined live because the Lock 14 settings store keeps no edit history, and finalization is the only moment there is something to freeze — omitting it would leave the column NULL on every shipped row while 108''s rationale stayed true only on paper. NULL is a LEGITIMATE VALUE (PM A-13): a tenant who never set a header finalizes successfully and renders an in-app prompt, never a placeholder. ⚠⚠ IT WRITES THE LOCK 12 CHILDREN AND IS THEIR ONLY WRITER IN THE PRODUCT: before this, pfin.monthly_report_account_snapshot had NO legitimate writer anywhere in supabase/migrations, api or workers (swept 2026-09-05) and was ALWAYS EMPTY, so any row in it could only have arrived through the authenticated INSERT grant. Three controls were hollow and one product surface was degraded: the Decision 3 #4 fence had nothing to fence, 109''s parent-must-be-draft predicate had nothing to refuse, ADR-068 Decision 7''s queryable-index justification had nothing to filter, and P8''s staleness banner — which takes its account membership from this table for final reports — degraded to the full live-stale set forever. THE SITE WAS CHOSEN AND 109 HAD ALREADY ASSUMED IT ("children are written at finalization, so a genuine draft has none"): finalization is the moment the names and tax treatments are frozen. ⚠ THE ORDERING IS ENFORCED RATHER THAN INTENDED, AND THE TWO CHANGES PROVE EACH OTHER — FLAG-4 gave 109''s BEFORE INSERT fence a parent-must-be-draft predicate, so the children must be inserted BEFORE the status flip, and the fence stops being moot precisely because a writer now exists. ⚠ THE ACCOUNT SET IS THE PAYLOAD''S, NOT THE CALLER''S: fn_nav_composition deliberately excludes tax-authority ledger accounts, so snapshotting every account the caller owns would describe a different set than the report shows. The values are read from pfin.account in the same transaction under the caller''s own RLS — the same read that produced the payload''s account_name moments earlier, so they agree by construction — and tax_treatment is not carried in the payload at all, which is why the join is needed rather than optional. There is deliberately NO on-conflict clause: 109''s unique (monthly_report_id, account_id) is a real watcher, since fn_nav_composition groups by account_type and an account has exactly one, so a duplicate would mean the composition itself is malformed. ⚠ EACH ROW IS PERMANENT even though this is not a schema one-way door: the children are immutable and DELETE-blocked, so a report frozen with the wrong set keeps it and the correction is to REGENERATE the month. ⚠ included_reconciliation_event_ids IS DELIBERATELY NOT WRITTEN — no V1.5 surface writes it, its Decision 3 fence is dormant on the product path, and populating it here would be scope creep that silently activates a fence nobody asked to activate. ⚠⚠ NO AUDIT ROW IS EMITTED, WITH A NAMED ALTERNATIVE RATHER THAN BY OMISSION: audit_log''s surface vocabulary admits one member and grows only by migration (R7 rider 5), so a finalize surface would be a ONE-WAY DOOR on an append-only table, and the V1.final month-of-operation measurement reads data_as_of alongside trigger_source = ''cron'' with NO surface filter — a second cron-writable surface would change that result without touching the measurement. ⚠⚠ THE "NOT PRIVILEGED" HALF OF THAT ARGUMENT IS SCOPED TO USER-ONLY FINALIZATION AND IS NOT PERMANENT (Sec''s revival condition): no audit row is owed because the tenant finalizes in their own session under their own RLS, so ADR-011 Decision 1 clause (d) does not attach. THE FIRST WORKER OR CRON CALLER — auto-finalize, close-the-month, a backfill — makes this a PRIVILEGED-CONTEXT WRITE, clause (d) attaches, and the costed alternative becomes MANDATORY rather than optional. ⚠ The AFTER INSERT trigger cannot cover it: this function performs UPDATEs only, so a worker-initiated finalize would emit NOTHING while looking audited — silently uncovered rather than visibly missing — and whoever adds that caller owes the emission in the same PR, as a Sec joint-review event because it grows the surface vocabulary, a one-way door on an append-only table. THE CHECKABLE FORM OF THE SCOPE is that EXECUTE is granted to authenticated and to NO other role; a grant to service_role or to a new role is the moment the condition fires. What is taken instead is that THE ROW IS THE RECORD: generation_status, generated_at and users_id are made permanently unforgeable by 108''s trigger, which cannot drift from the artifact it describes. This is the same answer fn_regenerate_monthly_report already gives for the sibling transition. The alternative — add monthly_report_finalization and emit — buys WHICH PATH finalized and costs the one-way door plus a same-PR change to the measurement''s predicate; it is routed to Sec and F/CTO, not taken here. ⚠ AUTHOR-BEFORE-GENERATE IS A DISPOSITION, NOT A CONTENT CHECK: ''authored'' does NOT require non-empty commentary — four empty strings ARE an authored state (R12 rider 1) — so this validates the vocabulary and never inspects the commentary columns, and a later edit adding "authored implies non-blank" would refuse a state the product defines as valid. The §7.34 pre-finalize no-tax-ledger prompt is P4/P5 UI and is NOT enforced here: it is a nudge, and encoding it in the DB would convert it into a refusal. ⚠ NO TENANT PARAMETER and NO data_as_of PARAMETER (Gate A; Lock 15; RT-25) — the tenant is the session and the as-of is the ROW''S OWN, read under lock and threaded into 110 unchanged; there is deliberately no users_id predicate in the body, because a hand-written copy of the policy reads as the fence while not being it. MONOTONICITY IS ENFORCED BY 108, NOT COPIED HERE: the FOR UPDATE read selects on generation_status = ''draft'', so an already-final or superseded month yields no row, and the refusal DOES NOT DISCRIMINATE absent / not-yours / already-final because under RLS those are one condition and separating them leaks existence. ⚠ THE COMPOSED PAYLOAD IS ASSERTED TO BE ABOUT THE LOCKED ROW: 110 echoes source_report_id precisely so a caller can check it, and a mismatch RAISES rather than freezing one draft''s figures onto another draft''s row — unreachable while 108''s one-live-draft-per-month index holds, which is exactly why the assertion is what will notice if that stops being true. payload_schema_version is EXTRACTED FROM THE PAYLOAD rather than hardcoded, so the column and the artifact cannot disagree about which schema was frozen. ⚠ PERFORMANCE: the 2000 ms p95 render budget applies and this is its WORST CASE — 110''s composition plus two UPDATEs, holding FOR UPDATE on the draft throughout; the lock duration is acceptable because the only contender is another finalize or a commentary save on the SAME month by the SAME tenant. If the budget is ever missed, the answer is NOT to move the composition outside the transaction: that reintroduces exactly the half-finalized report this function exists to make impossible.';
