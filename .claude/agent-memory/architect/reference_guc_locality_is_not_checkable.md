---
name: guc-locality-is-not-checkable
description: A function cannot tell a SET LOCAL from a session-level set_config — current_setting is blind and an undeclared custom GUC is absent from pg_settings entirely; transaction-locality is always a CALLER obligation.
metadata:
  type: reference
---

`current_setting('app.x', true)` returns the same thing whether the value was set
with `set_config('app.x', v, true)` (transaction-local) or `false` (session-level).
There is **no catalog discriminator either**: an *undeclared* custom GUC does not
appear in `pg_settings` at all — measured, **zero rows** for both forms on PG 17.

**Why:** so a GUC-carrier fence (the `054` / `107` / `113` shape) can never enforce
that its carrier was scoped to one transaction. A session-level set **does** reach a
later transaction's row (measured at `113`).

**How to apply:** when you write a GUC-carrier fence, say **"transaction-locality is
a caller obligation, held by the perimeter"** — never imply the function checks it.
And write the QA leg as *"a `is_local => true` set does not survive its transaction"*
(true, enforced by Postgres). ⚠ The leg you will naturally reach for — *"a session-level
set does not reach the next transaction"* — **goes RED, correctly**, and a battery
asserting it would be asserting a fence that does not exist.

Related: [[a-definer-helper-taking-a-classification-parameter-is-a-forgery-channel]],
[[feedback_watcher_not_fence_for_by_construction_properties]].
