-- ============================================================================
-- Migration: pfin.audit_log + pfin.fn_emit_audit_log — the GENERAL same-transaction
--   audit-log surface and its insert helper. Phase 6 Build Loop; block **AH** of the
--   V1.5 pre-flight record; ruled at **R7, option (2)**. It has no Linear id of its
--   own: SELF-345's PR is its vehicle. apply-migration procedure applied.
--   ⚠⚠ **THIS FILE AUTHORS A SECURITY DEFINER FUNCTION.** JOINT-REVIEW-MANDATORY on
--   three independent grounds — a new audit-class surface, an
--   [ADR-011](DECISIONS.md#adr-011) Decision 1 clause (d) discharge, and a Decision 9
--   event. Reviewed as part of the A1+A2+A3 design unit under ONE Sec joint-review.
--
-- ----------------------------------------------------------------------------
-- WHY THIS EXISTS AT ALL — R7, and the options that were NOT taken.
--   A7 (the monthly-report cron) owes an [ADR-011](DECISIONS.md#adr-011) **Decision 1
--   clause (d)** audit row: a same-transaction record naming the RESOLVED TENANT and
--   the TENANT-RESOLUTION CHAIN for a privileged write. That obligation is discharged
--   by AUTHORING the general audit-log helper Decision 9's amendment records as
--   **reserved-unauthored**, and A7 writes through it.
--     · Option (1) — widen `pfin.linked_source_sync_audit`'s `source` and `provider`
--       CHECKs — **NOT TAKEN.** It would change the DOMAIN of a shipped append-only
--       audit-class table from *"sync"* to *"any privileged write"*: a Decision 2
--       change reached for convenience. That table is **UNTOUCHED by this file.**
--     · Option (3) — a report-scoped audit table — **NOT TAKEN.** A fourth audit
--       surface with exactly one consumer.
--   WHAT WAS MEASURED, and re-verified at authoring rather than inherited: the
--   drafted *"Lock 13 mod #4 audit log"* `pfin.plaid_sync_audit` was created at `007`
--   and **DROPPED at `015`** — it is not a live table. Its successor
--   `pfin.linked_source_sync_audit` carries `users_id` commented *"resolved tenant
--   (Decision 1 clause (d))"* but **REJECTS a report-generation row**: its `source`
--   CHECK admits only `webhook` / `scheduled_poll`, and its provider list has no
--   internal or report member. And `git grep -lE "emit_audit_log|fn_audit_log"` over
--   `supabase/migrations/` returned **nothing**. Built as drafted, A7 would either
--   silently drop D1(d) on the wave's only privileged non-JWT writer, or widen CHECKs
--   on an audit-class table without a review that noticed.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ POSTURE — **SECURITY DEFINER**, AND IT IS FORCED BY A10's CALLER, NOT CHOSEN
--   FOR CONVENIENCE. R7 rider 1 directs Architect to draft INVOKER-FIRST and to state
--   in this header which posture it takes and why. **INVOKER WAS DRAFTED FIRST AND
--   DOES NOT SURVIVE CONTACT WITH THE SECOND CALLER.**
--
--   THE ARGUMENT, in the order it forced itself:
--     (1) R7 rider 4 gives this helper **TWO callers at V1.5, not one**: A7 (the
--         cron) and A10 (the on-demand endpoint). Both write the same shape,
--         discriminated only by trigger source.
--     (2) **A10 runs under the USER'S OWN SESSION** — its AC's first item makes the
--         session the tenant binding, with no tenant parameter anywhere on the path.
--         So one of this helper's two callers executes as `authenticated`.
--     (3) An INVOKER helper writes with the CALLER's privileges. For A10 that means
--         `authenticated` would need an **INSERT grant on the audit table itself.**
--     (4) **That is precisely the shape [ADR-011](DECISIONS.md#adr-011) Decision 9
--         has already ruled against, in its own words, on a structurally identical
--         surface:** *"an INVOKER+grant path would let a user POST forged history
--         rows — defeating the tamper-evidence."* A user holding INSERT on an
--         append-only audit table can POST rows through PostgREST claiming the cron
--         generated their report — correctly tenanted, correctly shaped, and
--         **permanently uncorrectable**, because the table is append-only.
--     (5) The escape route does not exist: moving A10's audit write to a
--         `service_role` hop would break **AC 1's same-transaction requirement** (a
--         row that survives a rolled-back generation is worse than no row) or would
--         void A10's session-as-tenant-binding. Neither is available.
--   **CONCLUSION: DEFINER, with `authenticated` holding EXECUTE on the helper and NO
--   GRANT AT ALL on the table.** That is the only shape where the audit row is written
--   in the caller's transaction while the caller controls no field that matters.
--
--   ⚠⚠ **THE ORIGINAL FORM OF THAT SENTENCE READ "…AND THE CALLER CANNOT FORGE ONE",
--   AND IT WAS FALSE AS WRITTEN. Re-derived here per Sec C4 (PR #636).** Step (4)
--   above is what falsifies it: it rejects an INVOKER+grant path because a user
--   holding INSERT on an append-only table can POST forged rows — and **EXECUTE on a
--   DEFINER function that INSERTs is that same grant, one level up.** The word
--   "grant" was read as meaning a TABLE grant. Measured 2026-09-05 on a clean chain:
--   an ordinary `authenticated` session, in the exact shape PostgREST produces, minted
--   a row with caller-chosen `trigger_source`, resolution chain and `subject_id`,
--   permanently uncorrectable on a table that blocks UPDATE and DELETE.
--   **General form, and the standing check it produces: on a DEFINER function whose
--   EXECUTE reaches `authenticated`, EVERY parameter is caller-controlled — so a
--   parameter that CLASSIFIES or LOCATES the row is forgeable content, not metadata.**
--
--   ⚠⚠ **WHAT IS AND IS NOT FORGEABLE AFTER C1 + C2 — stated as an inventory, because
--   a single adjective is what got this wrong the first time.**
--     · **`users_id` — NOT forgeable.** Stamped from `auth.uid()`; no parameter.
--     · **`trigger_source` — NOT forgeable through this function (C1), and its
--       RESIDUAL IS BOUNDED BY C2.** It has no parameter and is derived from a GUC no
--       PostgREST-reachable surface writes. ⚠ Should that unreachability ever fail,
--       the reachable outcome is not a forged row but a **mislabelled one attached to
--       a generation the forger actually performed**, and attributable to them by the
--       `auth.uid()` stamp. ⚠ **C2 BOUNDS FABRICATION, NOT ROW COUNT** — an earlier
--       form of this sentence claimed the one-live-draft index capped it per (user,
--       month), and that was WRONG: the index caps CONCURRENT live drafts, not
--       lifetime generations, and `fn_regenerate_monthly_report` supersedes the
--       incumbent before delegating an INSERT, so a second live draft never exists for
--       it to refuse. Every row still annotates a real write by that caller; how MANY
--       rows is bounded only by how often they regenerate.
--       ⚠ **That last clause is a NEGATIVE-SPACE claim, not a fence**: it holds because
--       no exposed function takes a GUC NAME from its caller, which is a property of
--       the current tree rather than something this file enforces. **Sec's C3 CI half
--       exists to watch exactly that absence**, and if it cannot be built this wave,
--       C1 alone does not carry `'cron'` — the named fallback is to move emission to
--       an `AFTER INSERT` trigger on `pfin.monthly_report`, which needs no GUC because
--       it reads the subject off `NEW`. That fallback is designed and NOT on the tree.
--     · **`subject_table` / `subject_id` — NOT forgeable for this surface (C2).** The
--       table is fixed by literal and the id must name a row that is the caller's own
--       AND was written in this very transaction.
--     · **`surface_name` — NOT INVENTABLE, but selectable.** The CHECK admits only a
--       vocabulary that grows by migration; within it a caller may still choose.
--       Today the vocabulary has one member, so the choice is empty.
--     · **`tenant_resolution_chain` — CALLER-ASSERTED, AND DELIBERATELY NOT
--       CONSTRAINED.** It is free text and this function does not and cannot check
--       that it describes what actually happened. ⚠ **Read it as an ANNOTATION ON A
--       WRITE THE HELPER HAS INDEPENDENTLY CONFIRMED, not as evidence in its own
--       right.** C2 already establishes that a real write, by this tenant, in this
--       transaction, occurred; the chain says how the caller believes the tenant was
--       resolved. A wrong chain misdescribes a write that definitely happened — it
--       cannot manufacture one. Sec is NOT asking for this column to be constrained.
--
--   ⚠ **THIS REALIZES THE RESERVED SLOT; IT DOES NOT GROW THE ALLOWLIST.** Decision 9
--   read LIVE at authoring (2026-09-05): the general same-transaction audit-log
--   insert helper is recorded there as a **committed-and-reserved, UNAUTHORED** entry
--   (Decision 1 / Lock 4 mod #5; deferred to SELF-201 Task #7 per
--   [ADR-026](DECISIONS.md#adr-026)). **This file AUTHORS that entry.** The committed
--   allowlist does not change; what changes is that one of its entries stops being
--   unauthored. **NO SIZE IS STATED HERE** — read Decision 9 live.
--   ⚠ **THE DECISION 9 AMENDMENT RIDES THIS SAME PR** (R7 rider 1; Sec R2.3 R-1
--   addition) — **never a later reconciliation.** It is written into the consolidated
--   ADR that ships with this migration.
--   ⚠ **AND THIS RESOLVES THE `⟨OPEN⟩` THE SITTING LEFT:** *"if the helper lands
--   INVOKER, the reserved DEFINER slot's disposition is not ruled — it would then be
--   a committed allowlist entry with no consumer and no author."* **It does not land
--   INVOKER, so that residual does not arise.** Recorded explicitly rather than
--   allowed to lapse, because a residual that stops applying still owes a sentence
--   saying so.
--
--   ⚠⚠ **THE EXECUTE ACL IS THE ENTIRE PERIMETER ON A DEFINER FUNCTION, AND THE
--   STAKES INVERT FROM THE INVOKER CASE.** For an INVOKER function the EXECUTE grant
--   is the weakest of several fences — RLS and the table ACL stand behind it. **Here
--   there is nothing behind it:** the body runs as the table's owner, so anyone who
--   can EXECUTE can write a row. The mechanical discriminator is
--   `pg_proc.prosecdef`. Consequently:
--     · `revoke execute … from public` FIRST, then explicit grants to exactly two
--       roles — `authenticated` (A10) and `service_role` (A7);
--     · **every argument is validated inside the body**, because the arguments are
--       the only thing a caller controls;
--     · **`users_id` IS NOT AN ARGUMENT.** It is stamped from `auth.uid()` inside the
--       body. A caller cannot attribute an audit row to another tenant, because
--       there is no parameter through which to try.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE HELPER REFUSES TO WRITE AN UNATTRIBUTED ROW, AND THAT IS TWO SEPARATE
--   REFUSALS, NOT ONE.
--   **(a) THE SURFACE NAME IS A REQUIRED ARGUMENT, CHECK-CONSTRAINED AGAINST AN
--   ENUMERATED LIST THAT GROWS ONLY BY MIGRATION (R7 rider 5).** Sec's losing side is
--   recorded and this is its mitigation, in Sec's own framing: **a general helper is
--   where per-surface discipline goes to be forgotten.** A caller that omits or
--   invents a surface name FAILS; it does not write an unattributed row that a later
--   reader must guess about. The list begins with the one surface that has a caller;
--   adding a member is a migration, therefore a review.
--   **(b) THE TENANT IS STAMPED, NOT PASSED.** `users_id` comes from `auth.uid()`.
--   ⚠ **A CALLER WITH NO RESOLVED TENANT THEREFORE FAILS CLOSED**: a `service_role`
--   session that has NOT impersonated has a NULL `auth.uid()`, the NOT NULL column
--   rejects it, and the whole transaction — the privileged write included — rolls
--   back. **That is deliberate and it is the point of D1 clause (d):** a privileged
--   write whose tenant cannot be named is not a write anyone should keep. It also
--   means this helper silently enforces R3's impersonation binding on A7 from the
--   database side.
--
-- ----------------------------------------------------------------------------
-- ROW SHAPE — R7 rider 2's minimum, and what each field is FOR.
--   · `surface_name`             — which privileged surface wrote this. (a) above.
--   · `trigger_source`           — `cron` / `on_demand`. **R7 rider 4: two callers,
--                                  one shape, discriminated ONLY by this column.**
--   · `users_id`                 — the RESOLVED tenant. Stamped, never passed.
--   · `tenant_resolution_chain`  — HOW that tenant was resolved, in words the writer
--                                  supplies (e.g. *"impersonated session:
--                                  request.jwt.claims.sub"*). This is the field
--                                  Decision 1 clause (d) actually asks for and the
--                                  one a reviewer reads; a resolved id with no
--                                  account of how it was resolved discharges half
--                                  the obligation.
--   · `data_as_of`               — the as-of the privileged write composed at.
--   · `subject_table` + `subject_id` — the row this write produced.
--   · `created_at`               — insert instant.
--   **R12 clause (2) READS EXACTLY THIS ROW** for the V1.final "month of operation"
--   measurement — `trigger_source = 'cron'` with `data_as_of` = the last day of the
--   month — which is why `data_as_of` is in the minimum shape rather than optional
--   colour, and why Decision 19 extends the clause with it.
--
-- ----------------------------------------------------------------------------
-- ⚠ ADR-011 DECISION 3 — PER-COLUMN DISPOSITION. **THIS FILE ADDS NO INSTANCE AND
--   ALLOCATES NO LABEL.** Decision 3's body read LIVE at authoring (2026-09-05); no
--   count is carried here.
--   · `users_id uuid` → `auth.users(id)` — the table's sole tenant anchor under a
--     direct predicate. **NOT an instance** (the `024` / `054` / `107` / `108`
--     disposition): the anchor IS the reference, with no second tenant fact to
--     mismatch.
--   · `subject_id bigint` — **NOT an instance, and this one needs its reasoning
--     written down rather than assumed, because `#15` is precedent that a PLAIN
--     BIGINT WITH NO DECLARED FK CAN STILL BE A FAMILY MEMBER.** The discriminator is
--     whether there is **one referenced relation** to validate against. #15's
--     `linked_source_id` has a fixed target (`pfin.linked_source`) and is fenced.
--     **This column's target VARIES WITH `subject_table` — it is a POLYMORPHIC
--     LOCATOR, not a foreign key**, and there is no relation a fence could join to
--     without dynamic SQL keyed on caller-supplied text. **Building that fence would
--     introduce a worse hazard than the one it closes** (a DEFINER function
--     assembling a query from an argument), which is why it is argued out rather than
--     built badly. ⚠ **WHAT CARRIES THE TENANT GUARANTEE INSTEAD, named because the
--     sufficiency comes from elsewhere:** `users_id` is STAMPED from `auth.uid()` and
--     is not a parameter, so a caller cannot mis-attribute a row no matter what
--     `subject_id` names — the worst a caller achieves is an audit row of their OWN
--     pointing at a row that is not theirs, which is a self-inflicted inaccuracy in
--     their own audit trail and leaks nothing.
--     ⚠ **REVIVAL CONDITION:** the day `subject_table` is narrowed to a single value,
--     or a real FK is declared, **this column BECOMES a Decision 3 candidate and
--     takes a newly-allocated label.** Whoever does that must re-derive this
--     paragraph rather than re-read it.
--   · There is deliberately **NO declared FK on `subject_id`**, and that is not an
--     omission: a general audit surface cannot name one target, and an FK onto an
--     append-only table would additionally convert a legitimate deletion elsewhere
--     into an outage here. The `#15` precedent at `044` records the same shape for
--     the same class of reason.
--
-- ----------------------------------------------------------------------------
-- ⚠ DECISION 2 — APPEND-ONLY UNDER **BOTH** ROLES (R7 rider 3), AND WHICH HALF.
--   The IMMUTABLE half governs, and only it: **there is no correction path on this
--   table and there is not meant to be.** An audit row records that something
--   happened; a wrong one is corrected by writing a further row about the
--   correction, never by editing the record. UPDATE and DELETE are blocked by
--   trigger for ALL roles — no role test anywhere — and TRUNCATE by a
--   statement-level fence. `service_role` bypasses RLS but not triggers.
--   ⚠ **aal2-CLAUSE-EXEMPT, AND THE EXEMPTION IS STATED RATHER THAN ASSUMED (R7
--   rider 3).** This table falls under `025` exclusion **(ii)** — RLS enabled, ZERO
--   `authenticated` policies, no grant to `authenticated` — so it is
--   service-path-only / default-deny and there is no `authenticated` read for the
--   clause to gate. **THE MOMENT AN `authenticated` READ POLICY IS ADDED, THE
--   EXEMPTION ENDS** and the clause becomes mandatory on that policy. Stated in these
--   terms because an exemption whose CONDITION is not written down is
--   indistinguishable, later, from an omission.
--
-- ----------------------------------------------------------------------------
-- ⚠ CONSEQUENCE RECORDED, NOT DISCHARGED HERE. `BACKLOG.md` §7.6 item **S7** is the
--   standing tracker for the Decision 1 clause (d) deferral that this helper's
--   ABSENCE created on the W-1 NAV worker (`054` / ADR-040's named D1(d) deferral).
--   **Authoring this helper makes S7 DISCHARGEABLE. It does not discharge it.**
--   Whether the W-1 worker is retrofitted to write through this helper is not ruled
--   and is not this wave's — team-lead's to book. **Stated so this file is not later
--   read as having closed S7 by existing.**
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK ([ADR-011](DECISIONS.md#adr-011) Decision 4 read VERBATIM
--   and LIVE before drafting, 2026-09-05. Path B — not restated, no count carried).
--   (i)   INSTANCE-NUMBERING — nothing added, removed, reordered or renumbered.
--   (ii)  LAYER-ATTRIBUTION — nothing moves; no surface becomes "four-layer".
--   (iii) VERBATIM-VS-PARAPHRASE — Decision 4 is LINKED, never restated.
--   ⚠ A **Decision 9** event is NOT a §10 event — the two are different ledgers and
--   the SELF-187 de-conflation precedent is explicit about it.
--
-- ----------------------------------------------------------------------------
-- Numbering: 111 follows 110. Independent of `110`; depends on 001 (pfin schema) and
--   003 (the auth.users FK target). Split from `110` deliberately: `110` authors a
--   read helper and this authors a WRITE surface plus the wave's only new DEFINER
--   function — one Sec-reviewable concern per file, and a reviewer should be able to
--   read the DEFINER argument without a composition helper in the way.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING LIST for this file (legs land at P10):
--   1. **The row exists IN THE SAME TRANSACTION as the privileged write it
--      describes**, and — the restored catch criterion — **is ABSENT when the
--      generation transaction ROLLS BACK.** A row that survives a rolled-back
--      generation is worse than no row.
--   2. The row NAMES THE RESOLVED TENANT, and that tenant equals the impersonated
--      session's `auth.uid()`.
--   3. **A `service_role` session that has NOT impersonated cannot write a row** —
--      `auth.uid()` is NULL and the insert fails closed, taking the transaction with
--      it.
--   4. **An invented `surface_name` is REFUSED** (R7 rider 5), and so is an invented
--      `trigger_source`.
--   5. **`authenticated` holds NO table grant:** a direct INSERT into
--      `pfin.audit_log` through PostgREST is refused at the ACL, while the SAME
--      caller succeeds through the helper. ⚠ **Both halves are required** — the
--      positive alone cannot distinguish DEFINER-with-no-grant from
--      INVOKER-with-a-grant, which is the whole security difference.
--   6. UPDATE / DELETE / TRUNCATE refused **under both roles**.
--   7. **STANDING catalog assertions — THREE, and the second is the one that would
--      have caught the forgery:** (i) `pfin.fn_emit_audit_log` is the only
--      `prosecdef = true` function added by this wave, its EXECUTE ACL names exactly
--      `authenticated` and `service_role` and NOT `public`; (ii) **exactly ONE
--      `pfin.fn_emit_audit_log` exists in `pg_proc`** — the 6-argument signature does
--      not survive as an overload (C1); (iii) it takes **no** `p_trigger_source`
--      parameter.
--   7c. **THE UNKNOWN-SURFACE REFUSAL — TWO LEGS, BOTH REQUIRED, AND IT CHANGES WHICH
--      ERROR AN EXISTING LEG SEES.** An invented `surface_name` now hits the C2
--      dispatch's `else` (P0001, naming the missing binding) **before** reaching
--      `audit_log_surface_name_vocab`, so a leg matching on that constraint name goes
--      red and must be **re-aimed at the helper's P0001**.
--      ⚠ **AND A SECOND LEG IS REQUIRED, NOT CONDITIONAL: assert the CHECK directly,
--      by an OWNER-PATH INSERT.** The two are not interchangeable — the CHECK asks
--      *is this name storable*, the `else` asks *is this name bound*, and the `else`
--      additionally catches a vocabulary-valid-but-UNBOUND name, which the CHECK
--      cannot see. Because the `else` now fires first, **the CHECK has no observer at
--      all through the granted path**, and an unobservable constraint is precisely the
--      one a later reader drops as dead code — which would remove the storability
--      floor for the owner path. Two questions, two legs.
--   7a. **C2 legs, and the two refusals must be asserted SEPARATELY (Sec):**
--      an audit call naming a report **written in an earlier transaction** is refused
--      with the earlier-transaction message; one naming **another tenant's** report is
--      refused with the not-yours message; and — the leg that proves C2 is not
--      vacuous — a call inside the same transaction as a real INSERT **succeeds**.
--      ⚠ **The success leg MUST route through `pfin.fn_open_monthly_report_draft`,
--      not through a bare INSERT**: that function's INSERT sits inside a plpgsql
--      exception block, i.e. a SUBTRANSACTION, and a bare-INSERT leg would pass
--      against an xid-equality implementation that refuses the real product path.
--   7b. **A read-only transaction is refused** (no xid assigned) — the fail-closed leg.
--   7d. **⚠⚠ THE COUNTER-ADVANCE LEG — REQUIRED WHATEVER EXPRESSION IS IN PLACE, AND
--      IT IS THE REASON THIS DEFECT SURVIVED TO REVIEW.** Advance `latestCompletedXid`
--      between the subject write and the emit, and assert the emit **still succeeds**.
--      **An ABORTED WRITING SUBTRANSACTION between the two is a faithful proxy** — no
--      second connection or dblink needed — and its matched negative control is a
--      **non-writing** abort, which must leave the snapshot untouched. Assert the pair,
--      not just the positive: the pair is what identifies the cause as xid consumption
--      rather than as "exceptions".
--      ⚠ **A stronger form, if the harness can manage a second connection: an ordinary
--      COMMIT FROM ANOTHER SESSION between the write and the emit.** That is the real
--      shape — the counter is cluster-wide — and dblink was only ever a convenient way
--      to produce it.
--      ⚠ **WHY THIS LEG IS MANDATORY RATHER THAN NICE:** the failure it catches is
--      NON-DETERMINISTIC and rolls back THE WHOLE GENERATION, not just the audit row,
--      because the emit is inside the generation transaction. **A scratch DB is idle,
--      so every battery passes.** Without this leg the suite cannot distinguish a
--      correct expression from one that will fail in production under ordinary load.
--   7e. **A RELEASED savepoint that WROTE the subject row still permits the emit** —
--      the sub-committed-xid case, which is where a commit-status test would break if
--      it treated sub-commit as commit. ⚠ Also cover the **production shape**: a write
--      inside an exception block that **exits NORMALLY** without firing, which
--      sub-commits the same way and is what `fn_open_monthly_report_draft` actually
--      does on its winning path.
--   7g. **THE ONE-STATEMENT INVARIANT, AS A STRUCTURAL LEG ON THE INSTALLED
--      DEFINITION.** Strip `--` comments from `pg_proc.prosrc` and assert **exactly
--      one** `from pfin.monthly_report` in `pfin.fn_emit_audit_log`'s body. ⚠ **Count
--      EXECUTABLE occurrences, not raw text:** the invariant's own comment quotes the
--      statement it protects, so the raw count is **2** and the stripped count is
--      **1** (measured) — a naive watcher goes RED on correct code.
--      ⚠ **This leg exists because no BEHAVIOURAL leg can cover it:** splitting the
--      read behaves correctly on an idle database and diverges only under concurrency.
--      The migration carries an apply-time version of the same check, but that one
--      watches edits to `111`; this one watches the INSTALLED definition, so it also
--      catches a later migration re-creating the function.
--   7f. **⚠ NOT A LEG, AND THE LIST MUST NOT IMPLY OTHERWISE: another session's
--      UNCOMMITTED row is refused STRUCTURALLY BY MVCC, not by any assertion here.**
--      `'in progress'` is returned for that row too; what excludes it is that this
--      transaction's own read never resolves it. **The case is UNBUILDABLE in a
--      single-connection pgTAP battery**, so no leg can cover it and none should be
--      written to look as though it does. It is a **structural argument**, recorded
--      here so a reader of this list does not infer coverage that cannot exist — and
--      the thing that would falsify it is not a test but an edit: see the
--      one-statement invariant in the body.
--   8. Two callers, one shape — ⚠ AND THE CRON ROW MUST BE PRODUCED BY SETTING THE
--      GUC, NOT BY PASSING A VALUE (C1 removed the parameter). Only then is this a
--      genuine two-caller leg; passing `'cron'` from the battery's own session was one
--      caller twice. Rows written by the cron and by the on-demand path
--      differ ONLY in `trigger_source`.
-- ============================================================================

create schema if not exists pfin;

create table if not exists pfin.audit_log (
  audit_id                 bigint      generated always as identity primary key,
  surface_name             text        not null,
  trigger_source           text        not null,
  users_id                 uuid        not null references auth.users (id) on delete cascade,
  tenant_resolution_chain  text        not null,
  data_as_of               date,
  subject_table            text,
  subject_id               bigint,
  created_at               timestamptz not null default now(),

  -- R7 rider 5: an enumerated list that grows ONLY by migration. It begins with the
  -- one surface that has a caller; adding a member is a migration, therefore a
  -- review. A caller that invents a name FAILS rather than writing an unattributed
  -- row.
  constraint audit_log_surface_name_vocab
    check (surface_name in ('monthly_report_generation')),

  constraint audit_log_trigger_source_vocab
    check (trigger_source in ('cron', 'on_demand')),

  -- A resolution chain that says nothing discharges nothing.
  constraint audit_log_resolution_chain_nonempty
    check (length(btrim(tenant_resolution_chain)) > 0),

  -- The subject is optional as a pair, but never half-present: a table with no id,
  -- or an id with no table, is a locator that cannot be followed.
  constraint audit_log_subject_pair
    check ((subject_table is null) = (subject_id is null))
);

comment on table pfin.audit_log is
  'The GENERAL same-transaction audit-log surface (block AH of the V1.5 pre-flight '
  'record; ruled at R7 option (2)). It discharges the ADR-011 Decision 1 clause (d) '
  'obligation — a same-transaction row naming the RESOLVED TENANT and the '
  'TENANT-RESOLUTION CHAIN for a privileged write — for the monthly-report cron and '
  'the on-demand generation endpoint, which are its TWO callers at V1.5, writing the '
  'same shape and discriminated only by trigger_source. ⚠ IT IS WRITTEN ONLY THROUGH '
  'pfin.fn_emit_audit_log, WHICH IS SECURITY DEFINER: no role holds any grant on '
  'this table, so there is no direct INSERT path. ⚠⚠ AN EARLIER FORM OF THIS SENTENCE '
  'ADDED "and a caller cannot POST a forged audit row through PostgREST" AND THAT WAS '
  'FALSE — measured 2026-09-05, an ordinary authenticated session minted a row with '
  'caller-chosen trigger_source, resolution chain and subject_id by calling the helper '
  'directly. The superseded claim is quoted here AS WRONG so a reader who remembers it '
  'learns it changed rather than doubting their memory; the lesson it encodes is that '
  'EXECUTE on a DEFINER function that INSERTs is a table grant one level up. WHAT IS '
  'TRUE NOW, PER FIELD: users_id is stamped from auth.uid() and has no parameter; '
  'trigger_source has no parameter and is derived from a transaction-local GUC no '
  'PostgREST-reachable surface writes (a NEGATIVE-SPACE property of the tree, watched '
  'by a CI fence, NOT enforced by this file); subject_table is fixed by literal for '
  'the generation surface and subject_id must name a row that is the caller''s own AND '
  'was written in the SAME transaction; surface_name is not inventable but is '
  'selectable within a vocabulary that grows only by migration. ⚠⚠ THOSE TWO CONTROLS '
  'ARE NOT PARALLEL: THE SUBJECT BINDING IS LOAD-BEARING AND THE DERIVED SOURCE IS '
  'WHAT MAKES ITS RESIDUAL SMALL. If the GUC''s unreachability ever failed, the '
  'reachable outcome is a MISLABELLED row attached to a generation the forger actually '
  'performed and attributable by the auth.uid() stamp — and NOT a row minted from '
  'nothing, which '
  'is what was measured before the subject binding existed. ⚠ '
  'tenant_resolution_chain REMAINS CALLER-ASSERTED AND IS DELIBERATELY NOT '
  'CONSTRAINED: it annotates a write this function has INDEPENDENTLY CONFIRMED '
  'happened, by this tenant, in this transaction — a wrong chain misdescribes a real '
  'write and cannot manufacture one. That posture is FORCED rather than chosen — '
  'one of the two callers runs under the user''s own session, so an INVOKER helper '
  'would have required an INSERT grant to authenticated, which is exactly the shape '
  'ADR-011 Decision 9 already ruled against on a structurally identical surface '
  '("an INVOKER+grant path would let a user POST forged history rows — defeating the '
  'tamper-evidence"). THE TENANT IS STAMPED FROM auth.uid() INSIDE THE HELPER AND IS '
  'NOT A PARAMETER, so a caller cannot attribute a row to another tenant; and a '
  'session with no resolved tenant FAILS CLOSED, taking the privileged write with '
  'it, which is what Decision 1 clause (d) is for. surface_name is CHECK-constrained '
  'against an enumerated list that GROWS ONLY BY MIGRATION — the mitigation for the '
  'named risk that a general helper is where per-surface discipline goes to be '
  'forgotten. APPEND-ONLY under Decision 2''s IMMUTABLE half, under BOTH roles: '
  'UPDATE, DELETE and TRUNCATE are trigger-blocked with no role test anywhere, and a '
  'wrong row is corrected by writing a further row about the correction, never by '
  'editing the record. ⚠ aal2-CLAUSE-EXEMPT under 025 exclusion (ii) — RLS enabled, '
  'ZERO authenticated policies, no grant to authenticated — AND THE EXEMPTION ENDS '
  'THE MOMENT AN authenticated READ POLICY IS ADDED; it is stated here rather than '
  'assumed, because an exemption whose condition is unwritten is indistinguishable '
  'later from an omission. ADR-011 DECISION 3: this table adds NO instance and '
  'allocates NO label (read Decision 3 live; no count is stated here) — users_id is '
  'the sole tenant anchor, and subject_id is a POLYMORPHIC LOCATOR rather than a '
  'foreign key, with no single referenced relation a fence could join to; that '
  'disposition holds only while subject_table can vary, and narrowing it to one '
  'value or declaring a real FK makes the column a Decision 3 candidate taking a '
  'newly-allocated label. ⚠ pfin.linked_source_sync_audit is UNTOUCHED by this work: '
  'widening its source and provider CHECKs was the option R7 declined, because it '
  'would change a shipped audit-class table''s domain from "sync" to "any privileged '
  'write". ⚠ Authoring this surface makes the W-1 NAV worker''s own Decision 1 clause '
  '(d) deferral DISCHARGEABLE; it does not discharge it, and whether that worker is '
  'retrofitted is not ruled here. JOINT-REVIEW-MANDATORY on three grounds: a new '
  'audit-class surface, a Decision 1 clause (d) discharge, and a Decision 9 event.';

comment on column pfin.audit_log.surface_name is
  'WHICH privileged surface wrote this row. A REQUIRED argument to '
  'pfin.fn_emit_audit_log — NOT INVENTABLE but selectable within the vocabulary — '
  'CHECK-constrained against an enumerated list that '
  'GROWS ONLY BY MIGRATION (R7 rider 5). ⚠ THIS IS THE MITIGATION FOR A NAMED RISK, '
  'not bookkeeping: a general helper is where per-surface discipline goes to be '
  'forgotten, so a caller that omits or invents a surface name FAILS rather than '
  'writing an unattributed row a later reader must guess about. Adding a member is a '
  'migration, therefore a review.';

comment on column pfin.audit_log.trigger_source is
  'What triggered the privileged write: `cron` (the scheduled generation) or '
  '`on_demand` (the user-initiated endpoint). ⚠⚠ DERIVED, NEVER PASSED (Sec C1): '
  'there is NO p_trigger_source parameter. The helper reads the transaction-local GUC '
  'app.report_generation_source and writes ''cron'' only on an EXACT match — never a '
  'prefix, never case-folded, never trimmed — with unset, empty and every '
  'unrecognised value alike yielding ''on_demand''. UNDER-claiming is the fail-closed '
  'direction here: a cron that forgets the GUC under-counts a month it really did '
  'generate, whereas the opposite default would let ordinary UI clicking inflate the '
  'V1.final metric. ⚠ THE CRON CAN SET THAT GUC AND A POSTGREST CALLER CANNOT, BUT '
  'THAT IS A PROPERTY OF THE TREE RATHER THAN A FENCE IN THIS FILE: set_config is '
  'executable by any role, and what keeps it unreachable is that PostgREST admits no '
  'arbitrary SQL, each request is its own transaction, and no exposed function takes '
  'a GUC NAME from its caller. A CI fence watches that absence. ⚠ THE HELPER HAS TWO CALLERS AT V1.5, '
  'NOT ONE, and they write the SAME SHAPE — this column is the only thing that '
  'distinguishes them, which is why a battery must assert that and not merely that '
  'each writes something. The V1.final "month of operation" measurement reads '
  'trigger_source = ''cron'' together with data_as_of.';

comment on column pfin.audit_log.users_id is
  'The RESOLVED tenant — ADR-011 Decision 1 clause (d)''s core field. ⚠ STAMPED FROM '
  'auth.uid() INSIDE pfin.fn_emit_audit_log AND NOT A PARAMETER: there is no argument '
  'through which a caller could attribute a row to another tenant. NOT NULL, so a '
  'session with NO resolved tenant — a service_role connection that has not '
  'impersonated — fails closed and takes the whole privileged transaction with it. '
  'That is deliberate: a privileged write whose tenant cannot be named is not a write '
  'anyone should keep, and this column therefore enforces the cron''s impersonation '
  'binding from the database side. NOT an ADR-011 Decision 3 instance — sole tenant '
  'anchor, no second tenant fact to mismatch.';

comment on column pfin.audit_log.tenant_resolution_chain is
  'HOW the tenant in users_id was resolved, in the writer''s own words (e.g. '
  '"impersonated session: request.jwt.claims.sub"). ⚠ THIS IS THE FIELD ADR-011 '
  'Decision 1 clause (d) ACTUALLY ASKS FOR and the one a reviewer reads: a resolved '
  'id with no account of HOW it was resolved discharges only half the obligation, '
  'because the question the clause exists to answer is whether the resolution was '
  'sound. CHECK-constrained non-blank, so a caller cannot satisfy the column with an '
  'empty string.';

comment on column pfin.audit_log.data_as_of is
  'The as-of date the privileged write composed at. Part of R7 rider 2''s minimum row '
  'shape rather than optional colour: the V1.final "month of operation" measurement '
  'reads exactly this field alongside trigger_source = ''cron'' AND '
  'surface_name = ''monthly_report_generation''. ⚠ THE SURFACE FILTER IS LOAD-BEARING '
  'AND AN EARLIER FORM OF THIS SENTENCE OMITTED IT: the vocabulary grows by migration, '
  'and the first added surface that a cron-initiated transaction can write would '
  'change this measurement''s result WITHOUT ANYONE TOUCHING THE MEASUREMENT — the '
  'defect would then be attributed to the query rather than to the migration. ⚠ AND '
  'PROSE IS THE WEAK FORM OF THIS FIX: a predicate described in a column comment has '
  'no watcher and cannot be executed. The durable fix is to COMMIT THE PREDICATE AS '
  'SQL — a view — so the measurement has one definition instead of a description; that '
  'is routed to PM and is not in this migration. ⚠ AND THE COUNT MUST BE OVER DISTINCT '
  '(users_id, month of data_as_of), NEVER OVER ROWS: a regeneration supersedes the '
  'incumbent and inserts a fresh draft, so each regeneration writes another row for '
  'the same month and a row count is inflatable by ordinary product use. ADR-011 Decision '
  '19 extends that clause with it. NULLable at the COLUMN so a future surface with no '
  'as-of can write honestly, while the HELPER''S PARAMETER IS REQUIRED — a report '
  'caller cannot omit it by accident, only pass NULL deliberately.';

comment on column pfin.audit_log.subject_table is
  'The relation the produced row lives in — the first half of a polymorphic locator. '
  'CHECK-paired with subject_id so the two are present or absent TOGETHER: a table '
  'with no id, or an id with no table, is a locator that cannot be followed.';

comment on column pfin.audit_log.subject_id is
  'The row this privileged write produced, located together with subject_table. ⚠ NO '
  'DECLARED FK, AND THAT IS NOT AN OMISSION: a general audit surface cannot name one '
  'target, and an FK onto an append-only table would convert a legitimate deletion '
  'elsewhere into an outage here — the shape ADR-011 Decision 3 instance #15 records '
  'at 044 for the same class of reason. ⚠ NOT A DECISION 3 INSTANCE, and the '
  'reasoning is written down BECAUSE #15 is precedent that a plain bigint with no '
  'declared FK CAN be a family member: the discriminator is whether there is ONE '
  'referenced relation to validate against. #15''s target is fixed; THIS column''s '
  'target VARIES WITH subject_table, so it is a POLYMORPHIC LOCATOR rather than a '
  'foreign key and no fence could join to it without dynamic SQL keyed on '
  'caller-supplied text — a worse hazard, inside a DEFINER function, than the one it '
  'would close. WHAT CARRIES THE TENANT GUARANTEE INSTEAD: users_id is stamped from '
  'auth.uid() and is not a parameter, so the worst a caller achieves is an audit row '
  'of their OWN pointing at a row that is not theirs — a self-inflicted inaccuracy in '
  'their own trail that leaks nothing. ⚠ REVIVAL CONDITION: narrow subject_table to a '
  'single value, or declare a real FK, and this column BECOMES a Decision 3 candidate '
  'taking a newly-allocated label. Re-derive this comment then; do not re-read it.';

-- ----------------------------------------------------------------------------
-- RLS — enabled with ZERO policies and ZERO grants. This is 025 exclusion (ii)
-- (service-path-only / default-deny) realized rather than asserted: there is no
-- authenticated read for an aal2 clause to gate, and no direct write path for any
-- role. The ONLY way a row reaches this table is pfin.fn_emit_audit_log, which runs
-- as the owner. ⚠ Adding an authenticated read policy ENDS the aal2 exemption.
-- ----------------------------------------------------------------------------
alter table pfin.audit_log enable row level security;

revoke truncate on pfin.audit_log from public;

-- ----------------------------------------------------------------------------
-- Immutability (Decision 2's IMMUTABLE half, both roles — R7 rider 3).
-- NO ROLE TEST: service_role bypasses RLS but not triggers, and on this surface the
-- trigger is its only applicable layer.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_audit_log_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.audit_log is immutable (ADR-011 Decision 2, immutable half; R7 rider 3). % blocked — an audit row records that something happened. A wrong row is corrected by writing a FURTHER row about the correction, never by editing the record.', tg_op;
end;
$$;

revoke execute on function pfin.fn_audit_log_block_mutation() from public;

comment on function pfin.fn_audit_log_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.audit_log (ADR-011 Decision 2 IMMUTABLE half; R7 rider 3, append-only under BOTH roles). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry, and deliberately NOT: an immutability fence reads nothing and needs no privilege, so keeping it INVOKER keeps this file''s DEFINER surface to exactly one function (pfin.fn_emit_audit_log) rather than two. raise exception (fail loud, never return null). ⚠ NO ROLE TEST ANYWHERE IN THIS BODY: service_role bypasses RLS but NOT triggers, and on this surface — which has no policies at all — the trigger is its ONLY applicable layer. ONLY THE IMMUTABLE HALF OF DECISION 2 IS IN FORCE: there is no correction-by-INSERT-new-version path, because the correction for a wrong audit row is a FURTHER audit row, not a replacement. KNOWN LIMIT: an owner-class role can suppress this trigger, and ADR-011 Decision 4''s 2026-09-03 amendment puts the applicable-layer count for an RLS-exempt writer at ZERO under session_replication_role = replica, so any bulk-load or restore path touching this table owes an explicit post-load validation step.';

create trigger audit_log_block_mutation
  before update or delete on pfin.audit_log
  for each row execute function pfin.fn_audit_log_block_mutation();

create or replace function pfin.fn_audit_log_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.audit_log TRUNCATE blocked (ADR-011 Decision 2; R7 rider 3). The privileged-write audit trail cannot be wiped — that is the one operation an audit trail exists to make impossible.';
end;
$$;

revoke execute on function pfin.fn_audit_log_block_truncate() from public;

comment on function pfin.fn_audit_log_block_truncate() is
  'BEFORE TRUNCATE (statement-level) fence on pfin.audit_log (ADR-011 Decision 2; R7 rider 3). SECURITY INVOKER, set search_path = '''' — NOT a SECURITY DEFINER allowlist entry. Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so the row-level fence cannot see a table-wipe — which on an audit trail is the single operation the trail exists to make impossible. Paired with REVOKE TRUNCATE FROM PUBLIC; the trigger is the regardless-of-grant guarantee. Message deliberately distinct from the row-level fence''s so a battery can assert which fired.';

create trigger audit_log_block_truncate
  before truncate on pfin.audit_log
  for each statement execute function pfin.fn_audit_log_block_truncate();

-- ----------------------------------------------------------------------------
-- ⚠⚠ THE SECURITY DEFINER INSERT HELPER — this file's Decision 9 event.
-- It REALIZES the reserved, previously-unauthored general audit-log insert entry;
-- it does not grow the allowlist. Read Decision 9 live; no size is stated here.
--
-- EVERY ARGUMENT IS VALIDATED IN THE BODY, because on a DEFINER function the
-- arguments are the only thing a caller controls and the EXECUTE grant is the
-- entire perimeter. `p_users_id` IS ABSENT BY DESIGN — the tenant is stamped from
-- auth.uid(), so there is no parameter through which to attribute a row elsewhere.
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE OLD SIGNATURE IS DROPPED, NOT REPLACED, AND THE DROP IS LOAD-BEARING (C1).
-- `create or replace` CANNOT remove a parameter: it would create a SECOND, overloaded
-- function and leave the 6-argument version alive, still carrying its `authenticated`
-- EXECUTE grant. PostgREST resolves RPC overloads BY REQUEST-BODY KEYS, so a caller
-- posting a `p_trigger_source` key would be routed to the old function DELIBERATELY —
-- source closed, database open. **Invisible to a clean apply and to a scratch-clone
-- battery**, because on a fresh chain only the new function is ever created; it bites
-- only on a database where `111` had already been applied. The paired assertion is a
-- catalog check that exactly ONE `pfin.fn_emit_audit_log` exists.
drop function if exists pfin.fn_emit_audit_log(text, text, text, date, text, bigint);

create or replace function pfin.fn_emit_audit_log(
  p_surface_name            text,
  p_tenant_resolution_chain text,
  p_data_as_of              date,
  p_subject_table           text,
  p_subject_id              bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_users_id       uuid := auth.uid();
  v_audit_id       bigint;
  -- C1: DERIVED, never passed. EXACT match on 'cron' — never a prefix, never
  -- case-folded, never trimmed. Unset reads as NULL on a fresh session and as the
  -- empty string once the name has been touched; unset, empty and every unrecognised
  -- value alike yield 'on_demand'. Under-claiming provenance is the fail-closed
  -- direction: a cron that forgets the GUC under-counts a month it really did
  -- generate, whereas the opposite default would let ordinary UI clicking inflate the
  -- V1.final month-of-operation metric. No `IS DISTINCT FROM` guard is needed here —
  -- `NULL = 'cron'` is NULL and takes the ELSE branch, which is the wanted direction.
  v_trigger_source text := case
                             when current_setting('app.report_generation_source', true) = 'cron'
                               then 'cron'
                             else 'on_demand'
                           end;
  v_subject_tenant uuid;
  v_written_here   boolean;
begin
  -- FAIL CLOSED ON AN UNRESOLVED TENANT, before anything else. A service_role
  -- session that has not impersonated has a NULL auth.uid(); Decision 1 clause (d)
  -- is precisely the requirement that such a write not be kept. Raising here — rather
  -- than letting the NOT NULL column do it — makes the reason legible in the error a
  -- worker operator actually reads.
  if v_users_id is null then
    raise exception
      'pfin.fn_emit_audit_log refused: no resolved tenant (auth.uid() is NULL). ADR-011 Decision 1 clause (d) requires a privileged write to name the tenant it acted for. A worker must bind a tenant by impersonation — SET LOCAL ROLE authenticated plus request.jwt.claims, with the singular request.jwt.claim.sub GUC nulled first — BEFORE the privileged write, not after it.';
  end if;

  -- The surface name and trigger source are re-checked here as well as by the table
  -- CHECKs. That is not redundancy for its own sake: this function is the ONLY write
  -- path, so a caller only ever sees THIS message, and a bare 23514 from a CHECK
  -- would not tell them the vocabulary grows by migration.
  if p_surface_name is null or btrim(p_surface_name) = '' then
    raise exception
      'pfin.fn_emit_audit_log refused: p_surface_name is required (R7 rider 5). A general audit helper is where per-surface discipline goes to be forgotten; a caller that omits or invents a surface name FAILS rather than writing an unattributed row. The permitted vocabulary is CHECK-constrained on pfin.audit_log and grows only by migration.';
  end if;

  if p_tenant_resolution_chain is null or btrim(p_tenant_resolution_chain) = '' then
    raise exception
      'pfin.fn_emit_audit_log refused: p_tenant_resolution_chain is required and must be non-blank. A resolved tenant id with no account of HOW it was resolved discharges only half of ADR-011 Decision 1 clause (d) — the question the clause exists to answer is whether the resolution was sound.';
  end if;

  -- ==========================================================================
  -- C2 — THE ARGUMENTS ARE BOUND TO A REAL PRIVILEGED WRITE IN THIS TRANSACTION.
  -- Without this, a caller with EXECUTE could annotate a write that never happened,
  -- or annotate somebody else's.
  -- ⚠⚠ C1 AND C2 ARE NOT PARALLEL, AND THE ASYMMETRY IS THE WHOLE POSTURE (Sec's own
  -- emphasis correction, E46 follow-up). **C2 IS THE LOAD-BEARING CONTROL; C1 IS WHAT
  -- MAKES ITS RESIDUAL SMALL.** With C2 in place, the worst a GUC-forger can achieve
  -- is MISLABELLING A GENERATION THEY ACTUALLY PERFORMED, attributable to them by the
  -- auth.uid() stamp. ⚠ C2 BOUNDS FABRICATION, NOT ROW COUNT: an earlier form of this
  -- sentence claimed the one-live-draft index capped it per (user, month), and that
  -- was WRONG — the index caps CONCURRENT live drafts, not lifetime generations, and
  -- fn_regenerate_monthly_report supersedes the incumbent before delegating an INSERT,
  -- so a second live draft never exists for it to refuse. Row COUNT is bounded only by
  -- how often the caller regenerates. That is still categorically different from the
  -- measured original
  -- defect, where audit_id 1 was minted from NOTHING: no write, any tenant's subject
  -- id, any provenance. **A future discussion about C1's carrier — GUC vs session_user
  -- vs anything else — must not be allowed to erode C2**, because C1's residual is
  -- acceptable only while C2 caps the blast radius.
  -- ==========================================================================
  if p_surface_name = 'monthly_report_generation' then

    -- (a) FAIL CLOSED FIRST. A transaction that has written nothing has no assigned
    -- xid, so there is no privileged write for this row to describe. Refusing here
    -- rather than falling through is Sec's explicit condition: NULL means nothing was
    -- written, therefore refuse.
    if pg_current_xact_id_if_assigned() is null then
      raise exception
        'pfin.fn_emit_audit_log refused: this transaction has written nothing (no xid assigned), so there is no privileged write for an audit row to describe. An audit row is an ANNOTATION ON A WRITE, not a standalone assertion — emit it in the same transaction as the write it names.';
    end if;

    -- (b) The subject table is FIXED for this surface, not caller-chosen.
    if p_subject_table is distinct from 'pfin.monthly_report' or p_subject_id is null then
      raise exception
        'pfin.fn_emit_audit_log refused: surface monthly_report_generation requires p_subject_table = ''pfin.monthly_report'' and a non-null p_subject_id. Got table % and id %.',
        coalesce(p_subject_table, '<null>'), coalesce(p_subject_id::text, '<null>');
    end if;

    -- (c) Resolve the subject. This runs as the function owner, so it sees the row
    -- regardless of the caller's RLS — which is what makes the tenant comparison
    -- below meaningful rather than tautological.
    -- ⚠⚠ THE CLOG TEST, NOT AN xid EQUALITY TEST AND NOT A SNAPSHOT TEST. TWO
    -- MEASURED DEFECTS ARE AVOIDED HERE AND BOTH ARE INVISIBLE TO AN ORDINARY LEG.
    -- (i) `xmin = pg_current_xact_id_if_assigned()` IS WRONG:
    --     `fn_open_monthly_report_draft` INSERTs inside a plpgsql
    --     `begin … exception when unique_violation` block, which opens a
    --     SUBTRANSACTION with its own xid, while that function returns the TOP-LEVEL
    --     xid. Measured: top 1664121, row xmin 1664122, equality FALSE. It would
    --     refuse the one path this condition exists to permit, and pass every test
    --     whose INSERT was not wrapped in an exception block.
    -- (ii) `not pg_visible_in_snapshot(...)` IS ALSO WRONG, AND THE CAUSE IS NOT
    --     EXCEPTIONS AT ALL — that was the symptom the defect was first found by.
    --     **THE CAUSE IS THAT IT DEPENDS ON A CLUSTER-WIDE COUNTER.** Our own xid is
    --     never in our own snapshot's `xip`, and `latestCompletedXid` advances when
    --     ANY transaction ANYWHERE completes. So as soon as the snapshot's `xmax`
    --     rises past our xid, `pg_visible_in_snapshot` calls our own write visible and
    --     the attestation flips FALSE. **An ordinary COMMIT FROM A SECOND SESSION
    --     between the write and this call is enough — no exception, no trigger, no
    --     dblink.** An aborted subtransaction of our own reaches it too, but only when
    --     it CONSUMED AN XID: a writing subxact takes one and aborting completes it,
    --     whereas a non-writing abort leaves the snapshot untouched. That matched pair
    --     is the discriminator.
    --     ⚠ **AND THE CONSEQUENCE WAS NOT A MISSING AUDIT ROW.** The emit runs inside
    --     the generation transaction, so a refusal rolls back THE WHOLE REPORT
    --     GENERATION — non-deterministically, on any non-idle database. **Every
    --     battery passed because a scratch DB is idle.**
    --     MEASURED side by side in ONE transaction: with a concurrent session
    --     committing between the write and the emit, the snapshot moved
    --     `1711648:1711648:` → `1711648:1711651:`, the clog test answered
    --     `written_here = true` and the snapshot test answered `false`.
    -- ⚠⚠ **THE DISQUALIFIER, WHICH IS THE REUSABLE HALF AND OUTLIVES BOTH ATTEMPTS:
    -- a candidate for this test MUST NOT depend on `latestCompletedXid`, on snapshot
    -- `xmax`, or on ANY OTHER CLUSTER-WIDE COUNTER.** The two rejected shapes fail in
    -- opposite directions — `xmin = pg_current_xact_id()` is blind to subtransactions,
    -- `pg_visible_in_snapshot` is sensitive to unrelated transactions — and only the
    -- second is non-deterministic, which is why it survived review.
    -- **`pg_xact_status` reads the commit log for THAT XID and satisfies the
    -- disqualifier: no snapshot, no counter, nothing cluster-wide.** It answers
    -- 'in progress' for a row written by our transaction or any of its
    -- subtransactions — including a subtransaction that was RELEASED rather than
    -- aborted, which is the case the commit-status family had to survive and does —
    -- and 'committed' for a row from an earlier transaction.
    -- ⚠⚠ THE INVARIANT THAT MAKES THIS SOUND, AND IT IS A PROPERTY OF THE STATEMENT
    -- BELOW RATHER THAN OF THE PREDICATE (Sec, confirming the expression).
    -- `'in progress'` is returned for OUR transaction AND for ANY OTHER SESSION'S
    -- in-progress transaction. **The predicate does not discriminate between them and
    -- was never asked to.** What discriminates is that the row was resolved by THIS
    -- TRANSACTION'S OWN MVCC READ, IN THE SAME STATEMENT — another session's
    -- uncommitted row is invisible to that read, so it never reaches the test at all.
    -- **THEREFORE: `users_id` AND the transaction status MUST be read in ONE
    -- `select … from pfin.monthly_report where report_id = p_subject_id`.** Splitting
    -- them, caching the row, passing it in, or accepting a row obtained any other way
    -- **breaks the coupling SILENTLY** — the predicate keeps returning a value and
    -- starts answering a different question. This is the single line in this function
    -- most worth refusing to "tidy".
    -- ⚠ `pg_xact_status` tests `TransactionIdIsCurrentTransactionId` first, which is
    -- true for the current transaction AND ALL OF ITS SUBTRANSACTIONS — it is the
    -- primitive that expresses the requirement, not a workaround that happens to fit.
    -- ⚠ IT WORKS FROM AN `authenticated` CALLER — measured. `pg_xact_status` carries no
    -- ACL entry, so EXECUTE is PUBLIC; it does not depend on this function's DEFINER
    -- posture, and QA can assert it directly.
    -- ⚠ BOUNDED ASSUMPTION, NAMED, WITH ITS DIRECTION. `xmin::text::xid8` reconstructs
    -- the 64-bit id without an epoch — there is no exposed epoch-preserving
    -- conversion — so this is sound within one xid epoch. A frozen `xmin` reads as
    -- 'committed' cleanly (measured on FrozenTransactionId), so **the ordinary
    -- ancient-row path REFUSES rather than erroring**. Beyond clog retention
    -- `pg_xact_status` raises, which aborts: an AVAILABILITY failure, fail-closed.
    -- ⚠ **AND THE RAISE IS REACHABLE ONLY ON THE REFUSAL SIDE, NEVER ON THE ACCEPT
    -- SIDE** — an xid old enough to fall out of clog cannot be one this transaction
    -- just assigned. So the error path can cost availability and can never grant
    -- acceptance; it is not exploitable in either direction.
    select r.users_id,
           pg_xact_status(r.xmin::text::xid8) = 'in progress'
      into v_subject_tenant, v_written_here
      from pfin.monthly_report r
     where r.report_id = p_subject_id;

    -- (d) ABSENT and OTHER-TENANT share ONE message DELIBERATELY. Sec requires the
    -- earlier-transaction case and the other-tenant case to be distinguishable, and
    -- they are; but distinguishing ABSENT from OTHER-TENANT would hand a caller who
    -- holds EXECUTE an existence oracle over every tenant's report_ids. One condition,
    -- one message.
    if v_subject_tenant is null or v_subject_tenant <> v_users_id then
      raise exception
        'pfin.fn_emit_audit_log refused: report_id % is not a row belonging to the tenant this session resolved to. An audit row may only annotate a write the caller actually made, and the tenant is taken from auth.uid(), never from an argument.',
        p_subject_id;
    end if;

    -- (e) The EARLIER-TRANSACTION case, distinct on purpose (QA legs depend on it).
    if not v_written_here then
      raise exception
        'pfin.fn_emit_audit_log refused: report_id % exists and is yours, but was NOT written in this transaction. An audit row annotates a write that happened HERE; back-annotating an earlier report would put an unfalsifiable claim into an append-only table.',
        p_subject_id;
    end if;

  else
    -- ⚠⚠ THE DEFAULT IS REFUSE, NOT PROCEED — AND THIS ELSE IS THE POINT OF IT.
    -- Without it the dispatch falls through to the INSERT for any surface that is not
    -- monthly_report_generation, so its emissions would be UNBOUND and mintable from
    -- nothing: the original defect, returning for the new surface. There is no live
    -- gap today because the CHECK vocabulary has one member — which is exactly why an
    -- `if` with no `else` reads as safe.
    -- ⚠ R7 rider 5's grows-only-by-migration is a PROCEDURAL control, and it was
    -- sitting on a STRUCTURAL DEFAULT OF UNBOUND. The migration that adds a surface is
    -- the moment someone is thinking about the CHECK and NOT about this branch, so the
    -- default must be the one that fails. Adding a vocabulary member now BREAKS every
    -- emission for it until its binding is written here.
    -- It is C2's own lesson applied one level up: validating the SHAPE of a dispatch
    -- never establishes that a binding exists behind it.
    -- ⚠⚠ THIS ELSE AND audit_log_surface_name_vocab ARE NOT INTERCHANGEABLE, AND BOTH
    -- REMOVALS LOOK LIKE CLEANUP. The CHECK answers **is this name STORABLE**; this
    -- else answers **is this name BOUND**. The else catches an invented name AND a
    -- vocabulary-VALID-but-unbound one — and the second is the actual gap, which the
    -- CHECK cannot see at all. Because this else now fires first, the CHECK is
    -- unreachable through the only granted write path, so:
    --   · a reader who drops the ELSE believing "the CHECK covers surface names"
    --     REOPENS exactly the hole it closes, for every future vocabulary member;
    --   · a reader who drops the CHECK believing "it is dead code" loses the
    --     storability floor for the OWNER path, which does not come through here.
    -- NEITHER SUBSUMES THE OTHER. The CHECK's own watcher is therefore a REQUIRED
    -- battery leg, not an optional one — see the QA list.
    raise exception
      'pfin.fn_emit_audit_log refused: no C2 subject binding is defined for surface %. A surface added to pfin.audit_log''s vocabulary MUST add its binding in this function — the rule that arguments are bound to a real privileged write in the same transaction is per-surface, and an unbound surface would accept an audit row describing a write that never happened. This refusal is deliberate and is not a missing case.',
      p_surface_name;
  end if;

  insert into pfin.audit_log (
    surface_name, trigger_source, users_id, tenant_resolution_chain,
    data_as_of, subject_table, subject_id
  )
  values (
    p_surface_name, v_trigger_source, v_users_id, p_tenant_resolution_chain,
    p_data_as_of, p_subject_table, p_subject_id
  )
  returning audit_id into v_audit_id;

  return v_audit_id;
end;
$$;

revoke execute on function pfin.fn_emit_audit_log(text, text, date, text, bigint) from public;
grant  execute on function pfin.fn_emit_audit_log(text, text, date, text, bigint) to authenticated;
grant  execute on function pfin.fn_emit_audit_log(text, text, date, text, bigint) to service_role;

-- ----------------------------------------------------------------------------
-- ⚠⚠ APPLY-TIME STRUCTURAL WATCHER FOR THE ONE-STATEMENT INVARIANT.
-- The invariant in the body — that `users_id` and the transaction status are read in
-- ONE statement — is the only control here that **no behavioural test can watch**.
-- Splitting that read into two statements produces CORRECT BEHAVIOUR ON AN IDLE
-- DATABASE and diverges only under concurrency, which is exactly why the predicate it
-- replaced survived review. A warning is the weakest available protection for the one
-- invariant that cannot be caught any other way, so it gets a mechanism.
-- ⚠ IT COUNTS EXECUTABLE OCCURRENCES, NOT RAW TEXT, AND THAT IS NOT A REFINEMENT — IT
-- IS THE DIFFERENCE BETWEEN A WATCHER AND A FALSE ALARM. The invariant's own comment
-- QUOTES the statement it protects, so `from pfin.monthly_report` appears TWICE in
-- `prosrc` and ONCE with comments stripped (measured). A naive raw-text count goes RED
-- on correct code — the same comment-versus-code trap the C3 fence already met at
-- `058`, now living inside this file.
-- ⚠ SCOPE, STATED SO IT IS NOT OVER-READ: this fires at APPLY time and therefore
-- watches edits to THIS file. A later migration that re-creates the function is
-- outside it; that case is QA leg 7g, which reads the INSTALLED definition.
-- ⚠ The comment-stripping is `--`-only. A second read hidden inside a string literal
-- would count and go RED — fail-loud, which is the direction we want.
do $watch$
declare
  v_executable_reads int;
begin
  select count(*)
    into v_executable_reads
    from pg_proc p
    left join lateral regexp_matches(
           regexp_replace(p.prosrc, '--[^\n]*', '', 'g'),
           'from\s+pfin\.monthly_report', 'g') m on true
   where p.pronamespace = 'pfin'::regnamespace
     and p.proname      = 'fn_emit_audit_log'
     and m is not null;

  if v_executable_reads <> 1 then
    raise exception
      'pfin.fn_emit_audit_log: the C2 one-statement invariant is BROKEN — % executable reads of pfin.monthly_report in the body, expected exactly 1. The subject row''s users_id AND its transaction status must be resolved by ONE select, because the predicate pg_xact_status = ''in progress'' is ALSO true for another session''s transaction: what excludes that row is this transaction''s own MVCC read, in the same statement. Splitting the read keeps returning a value and starts answering a different question — correctly on an idle database, wrongly under concurrency. Restore the single select; do not relax this check.',
      v_executable_reads;
  end if;
end
$watch$;

comment on function pfin.fn_emit_audit_log(text, text, date, text, bigint) is
  '⚠ SECURITY DEFINER. The general same-transaction audit-log insert helper (block AH; V1.5 pre-flight ruling R7 option (2)). It discharges ADR-011 Decision 1 clause (d) for the monthly-report cron and the on-demand generation endpoint — its TWO callers at V1.5, writing the same shape and discriminated only by trigger_source. ⚠ IT REALIZES THE RESERVED, PREVIOUSLY-UNAUTHORED general audit-log insert entry on the ADR-011 Decision 9 allowlist; it does NOT grow the allowlist. Read Decision 9 live; no size is stated here, and the Decision 9 amendment recording this authoring rides the same PR rather than a later reconciliation. ⚠ THE DEFINER POSTURE IS FORCED, NOT CHOSEN. INVOKER was drafted first, per R7 rider 1, and does not survive the second caller: the on-demand path runs under the USER''S OWN SESSION, so an INVOKER helper would have required an INSERT grant on the audit table to `authenticated` — which is exactly the shape Decision 9 has already ruled against in its own words ("an INVOKER+grant path would let a user POST forged history rows — defeating the tamper-evidence"), and on an append-only table such a forged row would be permanently uncorrectable. Moving that write to a service_role hop was unavailable: it would break the same-transaction requirement, or void the endpoint''s session-as-tenant-binding. ⚠ ON A DEFINER FUNCTION THE EXECUTE ACL IS THE ENTIRE PERIMETER, not the weakest fence — there is no RLS and no table grant behind it, because the table has neither. EXECUTE is revoked from public and granted to exactly `authenticated` and `service_role`; any further grant, and any grant to a new role, is SEC-JOINT-REVIEW-MANDATORY. Consequently EVERY ARGUMENT IS VALIDATED IN THE BODY, since the arguments are the only thing a caller controls — AND THE TWO MOST DANGEROUS ONES WERE REMOVED OR BOUND RATHER THAN VALIDATED, because validating a value''s SHAPE never establishes its TRUTH. ⚠ p_trigger_source IS GONE (Sec C1): it is derived from the transaction-local GUC app.report_generation_source, exact match on ''cron'', defaulting to ''on_demand''. ⚠ p_subject_table AND p_subject_id ARE BOUND TO A REAL WRITE (Sec C2): for surface monthly_report_generation the table is fixed by literal and the id must name a pfin.monthly_report row that belongs to the tenant auth.uid() resolved to AND was written IN THIS TRANSACTION — with a read-only transaction (no assigned xid) refused outright, since a transaction that wrote nothing has nothing for an audit row to annotate. ⚠ THE TRANSACTION TEST IS A SNAPSHOT-VISIBILITY TEST, NOT AN xid EQUALITY TEST, AND THAT IS A MEASURED DEFECT AVOIDED: fn_open_monthly_report_draft INSERTs inside a plpgsql exception block, i.e. a SUBTRANSACTION with its own xid, while pg_current_xact_id_if_assigned() returns the TOP-LEVEL xid — measured 2026-09-05 as top 1664121 against row xmin 1664122, equality FALSE — so a naive equality check would refuse the very path C2 exists to permit while passing every test whose INSERT was not wrapped in an exception block. ⚠ tenant_resolution_chain REMAINS CALLER-ASSERTED AND IS DELIBERATELY UNCONSTRAINED: it ANNOTATES a write this function has independently confirmed occurred, by this tenant, in this transaction, so a wrong chain misdescribes a real write and cannot manufacture one. ⚠ THERE IS NO p_users_id PARAMETER, BY DESIGN: the tenant is STAMPED from auth.uid() inside the body, so a caller has no argument through which to attribute a row to another tenant. A session with NO resolved tenant is REFUSED with a message naming the impersonation binding it should have performed — a service_role connection that has not impersonated has a NULL auth.uid(), and Decision 1 clause (d) is precisely the requirement that such a write not be kept; the refusal takes the whole privileged transaction with it, which is the intended outcome. p_surface_name is REQUIRED and CHECK-constrained on the table against a vocabulary that grows ONLY BY MIGRATION (R7 rider 5) — the mitigation for the named risk that a general helper is where per-surface discipline goes to be forgotten. p_tenant_resolution_chain is REQUIRED and non-blank: a resolved id with no account of how it was resolved discharges only half the clause. RETURNS the new audit_id so a caller can assert in-transaction that the row exists. ⚠ THE ROW MUST BE WRITTEN IN THE SAME TRANSACTION AS THE PRIVILEGED WRITE IT DESCRIBES — a row that survives a rolled-back generation is worse than no row, and the paired battery asserts BOTH that it exists on commit and that it is ABSENT on rollback. JOINT-REVIEW-MANDATORY.';
