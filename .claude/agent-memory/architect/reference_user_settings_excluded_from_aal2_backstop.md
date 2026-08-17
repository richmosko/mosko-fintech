---
name: user-settings-excluded-from-aal2-backstop
description: pfin.user_settings can never carry the 025 aal2 step-up clause (policy recursion) — so it is the wrong home for any tenant data that should be step-up-fenced
metadata:
  type: reference
---

`025` clauses every tenant-owned pfin table with the aal2 step-up backstop
(`coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
'none') not in ('totp','passkey') or (auth.jwt()->>'aal') = 'aal2'`). Its TARGET SET block
names three deliberate exclusions; the load-bearing one is **`pfin.user_settings` itself —
"the backstop's OWN substrate; ANDing the clause here would … recurse into a policy that
reads user_settings. NON-NEGOTIABLE exclusion."**

**Why it matters at design time:** any proposal to park tenant data on `user_settings` as
"additive columns" parks it on the single pfin table that is structurally un-step-up-able.
That is a mechanical argument against such a shape, not an aesthetic one — and it is
invisible unless you read `025`'s exclusion block rather than assuming the backstop is
universal.

Also note `024`'s own coordination note designates `user_settings` as the home for deferred
settings columns, which collides with ADR-011 D18's per-domain-tables ratify. Read both
before siting anything there. Related: [[ratified-name-is-not-a-built-table]].
