---
name: impersonate-block-write-ratified-at-self351
description: Sec ratified ONE write through TenantBoundConnection.impersonate() — the monthly_report cron's fn_open_monthly_report_draft call; any other write through that block is joint-review-mandatory.
metadata:
  type: project
---

**Fact.** At the A7 / SELF-351 review (PR #642, 2026-09-06) Sec **ratified** a write performed
*inside* `TenantBoundConnection.impersonate()`'s block — the monthly_report cron's
`select pfin.fn_open_monthly_report_draft(:target_month)`. Architect had shipped it as a
**provisional** ruling in `113`'s comment reading *"SEC RATIFIES AT SELF-351"*, i.e. the decision
was explicitly deferred to Sec and had to be made, not inherited.

**Why it was ratified rather than refused.** The established codebase shape — exit impersonation,
assume `service_role`, write with a Python-supplied `users_id` — is **mechanically unavailable**
here, and both halves were measured rather than accepted from a docstring:

- `113` grants EXECUTE to `authenticated` only (`revoke … from public; grant … to authenticated;`),
  with **zero** `to service_role`.
- `fn_open_monthly_report_draft(date)` takes **no** `p_users_id`; the row's tenant comes from
  `pfin.monthly_report.users_id`'s `auth.uid()` DEFAULT.

So under impersonation the write is attributed by the **database-resolved identity under live RLS**,
which is a *stronger* ADR-011 Decision 1 clause (c) discharge than the pattern it departs from —
where a Python variable is the only tenant fence. Adding `p_users_id` for a `service_role` call
would reopen Gate A and reproduce ADR-068 Decision 1's own **F-4** finding: *"a bypass-RLS caller
makes the PARAMETER the only tenant fence."* **The never-wrap-a-write rule was written against
direct DML by an RLS-exempt role; this is neither.**

**⚠ The scope of the ratification is ONE call.** `_reject_write_while_impersonating` bounds the
statement surface, not function bodies — a `select` invoking a data-modifying function is not
statically detectable and passes. That residual is now a **load-bearing, exercised path** rather
than a theoretical one. **Any other write through an impersonate block is joint-review-mandatory.**
Sec explicitly **did not** require a watcher over the residual (not cheaply expressible, likely
vacuous) and accepted it as a *named* residual with the joint-review trigger as its control.

**How to apply.** When any future caller writes through `impersonate()`, do not treat SELF-351 as
precedent for the general case — re-run the same two measurements (is there a `service_role` EXECUTE
grant? does the function take a tenant parameter?). If either answer differs, the exit-then-write
shape is available and the ratification does not extend. Related:
[[a-definer-grant-hands-back-the-channel]] (reachability / shape-vs-truth / repairability) and
[[my-requirement-can-be-voided-by-an-artifact-i-did-not-read]].

**Companion:** the ratification required correcting `connection.py`'s docstring, which asserted
*"THIS IS A READ-ONLY PRIMITIVE… The read-only property is ENFORCED."* **A control whose
documentation asserts a property the ratified use case falsifies is the same class as a stale
`comment on function`** — and it sits where a maintainer looks before touching it. Ratifying an
exception without correcting the claim would have shipped the drift, not closed it.
