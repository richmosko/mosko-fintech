---
name: before-row-fence-makes-the-fk-unreachable
description: A Decision-3 BEFORE ROW fence whose predicate is a strict subset of its FK's makes that FK structurally unreachable on INSERT/UPDATE (P0001, never 23503) — and session_replication_role=replica skips BOTH
metadata:
  type: reference
---

**On the normal write path a D3 matched-tenant fence, not the FK, is what rejects a bad
reference — and it is structural, not an ordering accident.** The fence is `BEFORE ROW`; FK
enforcement is `AFTER ROW` internal RI triggers (`RI_ConstraintTrigger_c_*`). More importantly the
fence's predicate (`pp.id = new.sub_cat_id AND pp.users_id = acc.users_id`) is a **strict subset**
of the FK's existence test, so **fence passes ⟹ FK already satisfied**. No non-NULL value passes
one and fails the other, and a `WHEN (… IS NOT NULL)` clause leaves no gap because the FK permits
NULL too.

**Consequences worth not re-deriving:**
- **The raise is `SQLSTATE P0001`** (bare plpgsql `raise exception`), **never `23503`.** A test leg
  pinned to 23503 fails for the wrong reason forever. Assert P0001 or the message.
- **It is a STACK.** Disabling one fence surfaced a *second* BEFORE ROW fence
  (`trade_constraints`) before the FK was ever reached. Never assume one fence is the only one.
- **The FK is NOT vestigial** — it fires cleanly (23503) with all user triggers disabled, and it is
  independently load-bearing in the other direction via `ON DELETE RESTRICT`. Unreachable in one
  direction ≠ removable.

⚠ **`session_replication_role = replica` skips BOTH the fence and the FK.** Measured: a row landed
referencing an id present in no `posting_prototype` row, with a control confirming rejection
without the GUC. Both D3 fences and internal RI triggers are origin-enabled, so `replica` disables
the lot.

**Bound it correctly before repeating it:** the GUC is `context=superuser`; `authenticated` and
`service_role` are **both denied** (measured). Not tenant-reachable, not a vulnerability, and no
capability a superuser lacks. **Where it bites is that Decision 3's whole rationale is that the
fence catches an RLS-EXEMPT writer** — migration role, restore, bulk tooling — which are exactly
the identities that can set `replica`, and setting it is routine for `pg_restore`/bulk loads. So a
restore path is **not a validated path**: every fence and FK is inert across it. **LANDED: this is now
ADR-011 Decision 4's `Amendment (2026-09-03 / Phase 6 Build Loop, SELF-257)`, live on `main` at
`5a6e6ff` (PR #597).** Read it there rather than re-deriving — it carries the policy-vs-trigger
split, the ZERO-not-one layer consequence for an RLS-exempt writer, and the severity bounding.
⚠ **The amendment states the all-triggers inventory as a DATED FACT, not a law** — D3 sanctions a
`WITH CHECK` form too, so re-survey each new instance (see
[[reference_with_check_is_a_policy_not_a_check_constraint]]). The restore/bulk-load runbook half
stayed with DevOps and is NOT discharged by the ADR.

Related: [[feedback_watcher_not_fence_for_by_construction_properties]] ·
[[feedback_a_check_chained_to_its_action_is_decoration]].
