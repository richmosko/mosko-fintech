---
name: cashflow-target-shape-supersession
description: 090 built pfin.cashflow_target as the WIDE row; ADR-011 D18's forward note and SECURITY SD-22 still record the inherited (users_id, target_kind) 2-row shape — an open, owner-routed correction
metadata:
  type: project
---

`090_cashflow_target.sql` (SELF-246, committed `3a5c2e8` 2026-08-24) builds
`pfin.cashflow_target` as **one row per user, two named nullable scalars,
`unique (users_id)`** — the Wave-4 Gate-A "Option B with internal C" shape.

**ADR-011 Decision 18's forward note and SECURITY SD-22's acceptance cell both
still record a different key shape**: 2 rows per tenant, `unique (users_id,
target_kind)`. Both label that shape **inherited from the then-`planning_target`,
not independently specified**, and both instruct *"confirm the key shape at build
rather than inheriting it silently."* That instruction is discharged by `090`;
their recorded text is superseded by DDL and the corrections belong to their
owners (SECURITY → Sec; D18's forward note → ADR route). ⚠ Also open: SD-22's RT
column says *"RT owed at build … modelled on RT-23"* — no RT was created by the
`090` PR; it is routed to Sec, and it is a §4.5 catalog change, **not** a §10
ledger or CI-fence change.

**Why:** SD-22 + D18 anticipated exactly this and asked for the confirmation
rather than assuming; the answer changes their text.

**How to apply:** if you meet either artifact's 2-row/`target_kind` description,
it is **stale, not the spec** — grep `supabase/migrations/090_cashflow_target.sql`
for the built shape. Do not "correct" the migration to match them.
Related: [[ratified-name-is-not-a-built-table]], [[a-consequence-list-inherits-its-authors-instrument]].
