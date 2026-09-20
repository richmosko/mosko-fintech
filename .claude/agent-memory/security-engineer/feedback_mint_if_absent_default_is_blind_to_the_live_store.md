---
name: mint-if-absent-default-is-blind-to-the-live-store
description: A repo-side default that is mint-if-ABSENT never overwrites an existing value, so a CI fence over that literal goes green while production still serves the old one. Pair every such fence with a running-container assertion.
metadata:
  type: feedback
---

**A repo-side default written by a mint-if-ABSENT provisioner is structurally blind to the live store. A CI
fence whose subject is that literal is HALF a control, and the missing half is the one that matters.**

**Why:** §7.36 item 22 (2026-09-19). The production `PGRST_DB_SCHEMAS` value lives in
`scripts/provision-supabase-stack.sh`'s `NONSECRET_DEFAULTS`, which writes a key **only when it is absent**.
Correcting the repo literal therefore does **not** correct the live Coolify store — and that same script's own
header already says so for the sibling `MIGRATOR_DB_*` case: *"MINT_SECRETS is mint-if-ABSENT, so simply
removing them here would silently leave a PRE-EXISTING value in this resource's store untouched forever."*
Left unaddressed, the ruling would have landed as a **green CI check over a box still serving the wrong value**
— the most reassuring possible failure.

**How to apply:**
- Whenever a fence's subject is a **default / seed / mint-if-absent / check-if-absent** value, say in the
  hand-off that the repo lane cannot be the whole control, and make the production-observable half a
  **CONDITION**, not a recommendation.
- The production-observable slot: a post-deploy assertion in the provisioner's own verification battery that
  reads the **running container** (`docker compose exec -T <svc> printenv <VAR>`) and **fails the deploy** on
  mismatch. Cite ADR-072 Amendment 4's `assert_migrator_names_absent` as the shape precedent — **strike-proven,
  not asserted once**.
- Prefer the instrument the original finding already used. Item 22's divergence was measured with exactly that
  `printenv` on the running `rest` container; proposing the same instrument as the standing watcher makes the
  control obviously adequate instead of arguable.
- **Generalise the question, not the instance:** "does correcting this file change the thing the finding was
  about?" A provisioner that is idempotent-by-skipping answers *no* for every key it owns.

See [[which-lane-does-the-watcher-observe]], [[a-disposition-without-a-mechanism]],
[[a-described-control-is-not-a-built-one]], and [[a-fence-exists-is-not-a-fence-blocks]].
