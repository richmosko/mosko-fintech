---
name: a-correction-target-can-state-the-wrong-value
description: A booking's AC names artifacts to "correct to the ruled value" — but one of those artifacts may state a value that is wrong under EVERY option, so correcting to it ships a second defect. Also: an ordered config list defeats a set-membership fence.
metadata:
  type: feedback
---

**When a booking's AC says "correct artifacts X, Y, Z to whatever the ruling decides", read what X, Y and Z
currently SAY. One of them may state a value that is wrong under every option on the table.**

**Why:** BACKLOG §7.36 item 22 (Sec consult, 2026-09-19) named three artifacts to reconcile to the ruled
`PGRST_DB_SCHEMAS` value, one of them `docs/deployment-runbook.md:484` — which states `PGRST_DB_SCHEMAS=pfin`.
Per PostgREST's *API / Schemas* reference, **"If no profile header is provided, the first schema in `db-schemas`
becomes the default."** So `pfin` alone would (i) make `pfin` the default profile and (ii) un-expose `public`
and `graphql_public` entirely — worse than either option the ruling was choosing between. The AC read as
"align three artifacts"; done literally, using the runbook's own stated literal as the target, it would have
shipped a **second defect wearing the first one's clothes**. The ruled literal was `public,graphql_public,pfin`
— `public` retained first, `pfin` appended last — and I vetoed `pfin`-alone **by name, as an enumerated option**,
precisely so it is not reachable by someone "just correcting the docs".

**How to apply:**
- A booking that says *"correct A, B and C to match"* has named **three claims**, not three chores. Open each
  and grade its current text before agreeing to the reconciliation. The divergence that produced the booking is
  evidence that at least one of them was already wrong.
- **State the ruled value as an EXACT LITERAL in the position text**, never as "add X to the list" — the latter
  licenses any ordering and any co-members.
- **VETO the wrong shapes by name.** An option enumerated and rejected cannot be arrived at accidentally; an
  option merely not-chosen can.

**⚠ The companion fence lesson — ORDER is a property a membership check cannot see.**
When the ruled value is a **list**, ask whether the consuming software gives the ORDER meaning (first entry =
default profile, first entry = search-path head, first matching rule wins…). If it does, a fence that checks
*"does the value contain `pfin`?"* passes `pfin,public,graphql_public` — right members, wrong order, live
defect. **Require a golden fixture whose members are correct and whose order is wrong, and say in the hand-off
that it is the load-bearing fixture** — it is the one a set-membership implementation silently fails.

See [[fence-shape-stated-in-prose-is-wrong-twice]] (derive the refused set from the defect mechanism),
[[read-the-whole-cell-before-diagnosing-doc-drift]] (a handed-over replacement figure can be the wrong axis),
and [[which-lane-does-the-watcher-observe]].
