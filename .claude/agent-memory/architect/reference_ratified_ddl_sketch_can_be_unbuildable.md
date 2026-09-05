---
name: ratified-ddl-sketch-can-be-unbuildable
description: A ruling's parenthetical DDL sketch can be structurally unbuildable; a delegated-DDL-call clause is the licence to realize it, not to re-open the ruling
metadata:
  type: reference
---

A F/CTO ruling often carries a **parenthetical DDL sketch** alongside its substance
("freeze the payload at finalization (`rendered_payload JSONB NOT NULL` +
`payload_schema_version SMALLINT`, or a payload child — Architect's DDL call)").
**The sketch can be structurally impossible while the substance is exactly right.**

Measured instance — V1.5 sitting R1 (A), 2026-09-04: `rendered_payload JSONB NOT NULL`
cannot ship, because the cron writes the `draft` row **before** any payload exists
(same sitting, R9 rider 1). An unconditional NOT NULL fails the cron's own INSERT.
The ruling's substance — *written once, at finalization* — is realized instead as a
NULLable column plus a CHECK: `draft` permits NULL, `final`/`superseded` require it
NOT NULL. That is the ruling stated as a constraint that **can fail**, which is what
it wanted.

**Why this is not a re-opening.** R1 said *"Architect's DDL call"*. A delegation clause
in the ruling is the licence to realize the substance in buildable form. Without such a
clause, an unbuildable sketch goes **back to F/CTO**, not into the migration.

**How to apply.**
- Read every parenthetical DDL in a ruling as a **sketch**, and test it against the
  other rulings in the same sitting before treating it as spec — the falsifier is
  usually a sibling ruling about write ORDER (who writes the row first, and in what state).
- If a delegation clause exists: realize it, state the divergence in the AC **in terms**,
  and route it into the consolidated ADR so the ruling's sketch and the shipped shape do
  not later read as two different decisions.
- If no delegation clause exists: it is an F/CTO item, one line, not a silent fix.
- ⚠ Never quote the sketch as though it were the built shape — that is the sound-quote
  class ([[feedback_prove_derived_text_against_its_source]]): byte-exact and false.

Distinct from [[reference_lock_join_lists_are_dated_artifacts]] — that is a ratified
identifier that went stale; this is a ratified shape that was **never** buildable, and
the handling differs (grep the identifier vs. test the sketch against sibling rulings).
