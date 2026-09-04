---
name: rpc-held-lock-binds-only-rpc-callers
description: A FOR UPDATE lock inside a write-body function serializes callers of that function, not writers of the table — and under SECURITY INVOKER the table grants CANNOT be revoked to close the gap, so a deferred set fence is still defeatable by concurrent direct DML.
metadata:
  type: feedback
---

**When a surface replaces `SERIALIZABLE` with an explicit `FOR UPDATE` lock inside an RPC, ask who
takes the lock — then read the GRANTS.** The lock binds *callers of that function*. If
`authenticated` also holds direct `INSERT/UPDATE/DELETE` on the table, a direct PostgREST write
takes no lock and is not serialized against the RPC or against another direct write.

**Why:** at SELF-259 (`101_tax_bracket_tables.sql`) the ADR-011 D18 amendment recorded the lock and
then claimed *"the lock's narrower guarantee covers every hazard the surface has."* It named the
wrong losing side — write skew across **different** schedules — while the reachable one was write
skew **within one schedule**. The table's deferred `CONSTRAINT TRIGGER` set fence evaluates each
transaction against that transaction's own view, so two concurrent direct row UPDATEs on
**different rows** of the same parent (no row-lock conflict) can each see a valid set and both
commit into a collectively invalid one. That is exactly what SERIALIZABLE would have refused, and
the ADR sentence told the next reviewer it was covered.

**The trap that makes this worth its own memory: the obvious remediation is unavailable.**
`SECURITY INVOKER` means the function executes with the *caller's* privileges, so the table grants
the direct-DML path uses are the same grants the RPC body needs. **Revoking direct DML breaks the
RPC.** The only way to keep it revoked is `SECURITY DEFINER`, which is usually the wrong trade on a
tenant-scoped write body (under DEFINER the ownership `SELECT … FOR UPDATE` sees every tenant and
ownership becomes hand-rolled). Name that option and close it explicitly, or a reviewer will
propose it.

**The remediation that does work:** move the lock into the **fence**, not the writer — make the
deferred set-fence function's FIRST statement a `select 1 from <parent> where id = <resolved> for
update`, before it reads the set. Every transaction touching a child row then serializes on the
parent row at COMMIT, and the blocked transaction's subsequent set read takes a fresh READ
COMMITTED snapshot and sees the committed rows, so the second committer raises. Re-entrant with the
RPC's own lock on the same row. Residual to hand to QA: lock-ordering exposure for a transaction
touching rows of two or more parents.

**How to apply:**
- Any "we realized SERIALIZABLE as a row lock" claim → read the GRANTS block in the same pass, and
  ask whether the surface's own threat model already admits a direct-PostgREST caller. On Lock 14
  surfaces it always does — the shape-validation layer exists *because* of that caller, so the file
  usually states the premise that defeats its own coverage claim a few hundred lines apart.
- Grade a deferred set fence's completeness by **who can write the table**, never by what the RPC
  does. A deferred fence is single-transaction-complete and concurrency-incomplete by default.
- **Separate the two halves in the finding.** Mechanism: real. Reachability: usually narrow
  (needs the interleave between deferred-trigger execution and the commit record) and usually
  **same-tenant only** under RLS — no cross-tenant effect, no escalation. Say both, and block on
  the false coverage sentence rather than on the code. A canonical Lock register asserting total
  coverage is what stops the next reviewer looking.
- **Do not demand a pgTAP leg.** pgTAP is single-session and structurally cannot observe a
  two-transaction interleave; a `pg_get_functiondef` catalog pin honestly labelled as standing in
  for the concurrency test is the right instrument. The watcher for a fix is a manual two-session
  measurement.

Related: [[replacement-control-name-the-losing-side]] (in the shared index — the lock REPLACED an
isolation level, so name what the old form covered) · [[hazard-mechanism-vs-reachability]] ·
[[shared-predicate-then-second-narrowing]] · [[rls-delete-select-policy-conjunction-is-conditional]]
