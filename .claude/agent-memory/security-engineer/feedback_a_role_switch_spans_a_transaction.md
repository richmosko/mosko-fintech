---
name: a-role-switch-spans-a-transaction
description: Before approving `set local role X` in a fixture or migration, enumerate every statement inside that transaction — a transaction-wide switch assumes uniform privilege needs, and a transaction spanning two schemas with two owners does not have them.
metadata:
  type: feedback
---

**A `set local role` is not scoped to the statement that needed it — it is scoped to the TRANSACTION. Before
approving one, list every statement between the switch and the reset and ask which identity each one needs.**

**Why:** I approved a cleanup fixture shape where `set local role pfin_owner` was the second statement and
`reset role` the last. **Nine deletes sat between them, and the ninth touched `auth.users`**, where `pfin_owner`
deliberately holds only `select (id)` / `references (id)` — **a narrowing I had myself required** so that
`encrypted_password` would not be reachable from the standing credential. The switch that fixed the `pfin`
statements broke the `auth` statement, **and the failure surfaced in a different schema, looking unrelated to
the change that caused it.** The narrowing was right; approving a switch that spanned it was not.

**How to apply:**
- **Enumerate the statement span**, not just the statement that prompted the change. The tell is a transaction
  touching **more than one schema** or more than one object owner — that is where privilege needs stop being
  uniform.
- Prefer the **narrowest window**: move the foreign statement outside the switch, or bracket only the statements
  that need the role. "Move the `auth.users` delete outside the window" was the right fix at every option.
- ⚠ **Any per-test / per-file `set role` regime inherits this property permanently** — it is an argument against
  such a regime at scale, not merely a bug at one site. If one is adopted anyway, require **one shared
  GUC→role→reset helper per language** so the span is defined in one place.
- This is the same failure shape as [[hazard-mechanism-vs-reachability]] on a new axis: I had just adopted
  "enumerate the LIFECYCLE phases" and did not enumerate the **statement span**. **When a rule keeps catching me
  on new axes, the rule is about scope enumeration generally, not about its original axis.**
