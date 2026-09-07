---
name: a-definer-helper-taking-a-classification-parameter-is-a-forgery-channel
description: EXECUTE on a SECURITY DEFINER function that INSERTs IS a table grant, one level up — the 111 forgery, Sec-vetoed and RESOLVED 2026-09-05 by moving emission to an AFTER INSERT trigger with no callable form.
metadata:
  type: project
---

`pfin.fn_emit_audit_log` (migration `111`, block AH) is `SECURITY DEFINER`, EXECUTE
is granted to `authenticated`, and `pfin` is in `[api] schemas`. It validates
`p_surface_name` and `p_tenant_resolution_chain` and stamps `users_id` from
`auth.uid()` — but `p_trigger_source` is passed straight through to a CHECK that
admits `'cron'`. **Measured on a clean `001`–`114` chain (2026-09-05):** an ordinary
`authenticated` session, in the shape PostgREST produces, minted a
`trigger_source = 'cron'` row by calling the helper directly. `audit_log` blocks
UPDATE and DELETE, so the row is permanently uncorrectable.

**Why it matters:** not tenant isolation (the tenant is still stamped). It is
**provenance + metric integrity** — R12 clause (2) counts `trigger_source = 'cron'`
rows toward V1.final's N, so any user can inflate that metric. `111`'s own header
says the DEFINER posture exists so *"the caller cannot forge one"*; this is the
channel it left open.

**How to apply:**
- The general lesson, which outlives the fix: **on a DEFINER helper whose EXECUTE
  reaches `authenticated`, every parameter is caller-controlled — so a parameter that
  CLASSIFIES the row (source, actor, kind, reason) is forgeable provenance, not
  metadata.** Derive it inside the function, or the grant is the whole fence.
- Fixing it in `113` is impossible — `113` can only make its *own* writes honest.
  Say so explicitly rather than letting a downstream comment imply the channel closed.
- ⚠ QA's `111` battery models "the cron wrote this" by having its own session pass
  `'cron'`, so its *two callers, one shape* leg is one caller twice and stays green
  either way. **There is no watcher on provenance integrity.**
- Verify before acting on this: it was routed to Sec at SELF-351 and may be fixed —
  grep `111` for `p_trigger_source` and re-run the forge before repeating the claim.

Related: [[feedback_execute_acl_stakes_invert_on_definer]],
[[guc-locality-is-not-checkable]], [[feedback_assertion_with_no_watcher]].


---

## RESOLVED 2026-09-05 — Sec VETO-1 (PR #636), option A. Do not re-report it.

Emission moved to `pfin.fn_monthly_report_emit_audit()`, an `AFTER INSERT` row
trigger on `pfin.monthly_report`; **the callable RPC was dropped entirely, not
revoked.** No caller supplies any field. `pfin.fn_emit_audit_log` has zero `pg_proc`
rows on the tree — verify with a catalog query before citing any of this.

**The lesson that outlives the fix, and the one to actually carry forward:**

> **EXECUTE on a `SECURITY DEFINER` function that INSERTs IS a table grant, one
> level up.** `111`'s own argument rejected an INVOKER+grant path *because a user
> holding INSERT on an append-only table can POST forged rows* — and then reached a
> conclusion that handed the caller the same write through a different door, because
> "grant" was read as meaning a **table** grant.

Two mechanical consequences:

1. **The CI-checkable predicate is the GENERAL one:** *no `prosecdef` function in
   `pfin` that performs an INSERT is EXECUTE-granted to `authenticated`.* The
   per-function assertion is the one that **passed while the hole was open**.
2. **A trigger beats an RPC for same-transaction audit** on three axes, and they are
   worth separating: emission becomes *unforgettable* (the write IS the event, so no
   caller can omit it and no edit can move it onto a no-op branch), provenance
   becomes *unforgeable* (no callable surface exists to assert into), and event
   scoping becomes structural (`after insert` with no UPDATE listed cannot be made
   to fire on an UPDATE by editing the body).

⚠ **And name the losing side:** the RPC refused when `auth.uid()` was NULL; the
trigger does not, because it reads the tenant off `NEW`. That is a **trade** — drift
resistance gained, a fail-closed refusal lost — not a strengthening. See
[[feedback_replacement_control_name_the_losing_side]].
