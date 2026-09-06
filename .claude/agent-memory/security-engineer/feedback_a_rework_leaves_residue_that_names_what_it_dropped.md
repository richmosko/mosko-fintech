---
name: a-rework-leaves-residue-that-names-what-it-dropped
description: After a re-leg or a signature change, the OLD shape leaves greppable residue — an unused fixture binding marks a dropped leg, and the superseded identifier survives in the very ADR that records the change; sweep for the residue, it names the gap for you.
metadata:
  type: feedback
---

When a battery is re-legged or a function is re-specced, the old shape does not
vanish cleanly. It leaves **residue that is greppable and that names exactly what
was lost**. Sweeping for the residue is faster and more complete than re-deriving
coverage from the requirement list — because the requirement list is what the
reworker was looking at, and the residue is what they were not.

**Three residue classes, all measured on SELF-345 / `111` (2026-09-06):**

1. **A declared-but-unreferenced fixture binding = a DROPPED LEG.**
   `\set m_bad_subject '%requires p_subject_table%'` sat at L145 of a re-legged
   battery and was referenced **nowhere**. The guard it was written for — C2's
   `p_subject_table is distinct from 'pfin.monthly_report' or p_subject_id is null`
   — had zero observers, and `p_subject_table` is written **verbatim** into the
   audit row, so that guard was the only thing between an EXECUTE holder and a
   forged locator on an otherwise-valid emit. Delete the guard and the battery
   stayed green at 34/34. ⚠ `plan(N)` matching the assertion count does **not**
   catch this: both numbers move together when a leg is dropped.
   **Check:** for every `\set m_*` / expected-message / fixture variable, grep its
   own name and require ≥ 2 hits. One hit is the declaration alone.

2. **The SUPERSEDED SIGNATURE survives in the ADR that records the change.**
   The ADR-011 D9 amendment said the helper *"is realized as
   `pfin.fn_emit_audit_log(text, text, text, date, text, bigint)`"* — **six** args.
   The shipped function is five, and the six-arg form is precisely what the same
   migration's `drop function if exists` exists to remove. The amendment named a
   function that does not exist after apply. Both halves came from the same draft,
   one was updated and one was not.
   **Check:** after any parameter-list change, grep the bare function name across
   `DECISIONS.md` + docs + the migration and diff every rendered signature against
   the `create` and the `grant`/`revoke`/`comment on` — they are four independent
   sites and the ADR is the one nobody re-reads.

3. **`comment on function` is INVISIBLE to every `prosrc`-based structural leg.**
   The body's inline comment said *"THE CLOG TEST … NOT A SNAPSHOT TEST"* while the
   outer `comment on function` still said *"THE TRANSACTION TEST IS A
   SNAPSHOT-VISIBILITY TEST"* — the expression that had just been **ruled unsound**,
   documented as the shipped one, in the single place a maintainer reads before
   touching that predicate. ⚠ **The comment-stripping discipline that makes a
   `prosrc` leg sound is the same thing that puts the outer comment out of its
   reach**: `comment on` lives in `pg_description`, not `pg_proc.prosrc`. So the
   better the structural legs, the more confidently an outer comment can ship false.
   **Check:** on any predicate/mechanism change, read `comment on` as its own
   artifact and diff its positive claims against the body. A sentence whose
   *negative* half is still true (*"NOT AN xid EQUALITY TEST"*) is the camouflage —
   it reads as reviewed.

**Why:** VETO-1's clearance read. The battery met the entire specified required set
and was GREEN; all three findings came from residue sweeps, not from the checklist.
The third one licensed re-introducing the exact defect two rounds of joint review
had just measured out.

**How to apply:** run the three sweeps as a fixed pass whenever a diff's commit
message contains "re-leg", "re-aim", "replaced", "dropped … signature", or a
predicate name change. They are cheap greps and they are aimed at what the
reworker's own attention could not cover.

Related: [[feedback_prosrc_presence_checks_are_vacuous_because_the_comments_are_good]] ·
[[feedback_signature_change_needs_a_drop_not_a_runbook]] ·
[[feedback_catalog_comments_carry_live_state_tallies]] ·
[[feedback_enumeration_and_watcher_stop_one_short]] ·
[[feedback_read_decisions_from_the_pr_branch_when_the_pr_edits_it]]
