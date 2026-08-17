---
name: set-local-outside-a-transaction-is-a-noop
description: An RLS smoke that uses `set local role` / `set_config(...,true)` outside a transaction runs as the superuser and passes everything — always include a control leg that proves the role switched
metadata:
  type: feedback
---

`set local role authenticated` and `select set_config('request.jwt.claims', …, true)`
outside an explicit transaction emit only `WARNING: SET LOCAL can only be used in
transaction blocks` and **do nothing**. The probe then runs as the RLS-exempt superuser,
every tenant's rows are visible, and every leg "passes."

**Why:** measured at `074`. My first RLS smoke reported the owner seeing 1 row, tenant B
seeing rows too, and the aal2 clause making no difference at aal1 vs aal2 — all four legs
green-looking, all four meaningless. The tell was a `leaked_from_A = 1` that should have
been a catastrophic finding and was actually just the superuser reading its own fixture.
**A vacuous RLS harness does not look empty — it looks permissive**, which is the reading
that gets reported as a defect or, worse, waved through.

**How to apply:** wrap every leg in `begin; set local role authenticated; … rollback;`,
and put a **control leg first** that selects `current_user` and asserts it is
`authenticated`. Same family as [[diff-of-two-outputs-proves-nothing-until-nonempty]]: the
instrument must be shown to be measuring before its reading means anything. Companion
mechanism at `074`: even a *correct* harness cannot exercise the write-side `WITH CHECK`
from an `authenticated` session, because a BEFORE trigger fires first — so "cross-tenant
write fails closed" can be green while the policy leg is never reached.
[[scratch-db-full-chain-recipe]] carries the venue setup.
