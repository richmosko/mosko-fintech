---
name: rls-delete-select-policy-conjunction-is-conditional
description: A corrupt-the-control probe that fails to flip because "both policies are independently sufficient" must not be generalized into "the SELECT policy always covers DELETE" — Postgres applies SELECT policies to DELETE/UPDATE only when the statement reads columns
metadata:
  type: feedback
---

When a corrupt-the-control probe **fails to go red**, the finding is about *that statement*, not about
Postgres. Before letting the explanation become a reusable rule, bound it.

**Why:** QA's SELF-242 M12 leg found that opening `planning_target_delete`'s `USING` to `(true)` alone
did **not** admit a cross-tenant DELETE — `planning_target_select`'s tenant predicate also blocked it —
and asked that the pattern be recorded for the SD-23-family tables (`cashflow_target`,
`tax_bracket_*`) that will inherit this shape. The case-specific observation is right and the test
honestly bounds its own strength. **The generalization is not:** PostgreSQL applies SELECT policies to
a DELETE/UPDATE only when the statement **reads columns of the table** — a `WHERE` referencing columns,
or `RETURNING`. A bare `DELETE FROM t` is gated by the DELETE policy's `USING` **alone**. M12's
statement carries a `WHERE`, so its case is covered; the rule as worded is not.

**The load-bearing consequence, which is why this is worth keeping:** the DELETE policy's own tenant
predicate is **NOT redundant** and must never be trimmed on "the SELECT policy covers it" reasoning.
The tempting cleanup — dropping a predicate a probe proved "already covered" — removes the only fence
that survives an unqualified statement.

**⚠ CONFIRMED 2026-08-20 — QA measured it, I did not.** Fresh scratch DB, sequential `001`→`085`
apply, complementary corrupt-the-control pair on `pfin.planning_target`: DELETE policy opened to
`using (true)` with SELECT left intact → unqualified cross-tenant `delete from pfin.planning_target;`
**succeeded** (`DELETE 1`); corruption reversed → same statement **refused** (`DELETE 0`). The rule
holds as stated. I could not verify it myself (read-only review; will not mutate a scratch DB) and
said so in the verdict rather than asserting or hedging it — **routing the empirical half to QA is
what turned a correct reading into a citable fact.** Keep the attribution: the durable note says
"Measured, not reasoned (QA, …)" so a future challenge goes to a reproducible experiment, not to a
Sec assertion.

**⚠ The reusable half is a paired-battery trap, not a Postgres trivium.** A cross-tenant DELETE
assertion written *with* a `WHERE` is satisfied by **either** policy — so corrupting one and finding
the test still green proves the other is **sufficient**, never that the corrupted one was
**redundant**. A leg meant to isolate a DELETE policy's own clause must omit the column filter, or
corrupt both and vary them independently.

**⚠ And I got the VENUE wrong first.** I initially recommended RT-23 as the note's home ("RT-23
already scopes this write path"). QA's confirmation that the rule binds four *unbuilt* tables is what
made that wrong: three of them are RT-24's and SD-22's, so RT-23-as-home files a constraint where its
readers never arrive. It landed in **`docs/SECURITY` §4.6 Cross-cutting posture** — which already
carries family-wide bullets in that exact shape ("Audit-class surface family inventory" binds *any
future audit-class surface*) — with RT-23 carrying a pointer only. **Path A at §4.6 because that
section IS the canonical anchor and absorbs; Path B at RT-23 because the family rule is not its
territory.**

**How to apply:** whenever a mechanism claim arrives as *"Postgres does X"* rather than *"this statement
did X"*, ask what statement shape it was measured on and whether the property is conditional on that
shape. Then pick the venue by asking who must READ it, not who reported it: a rule that four unbuilt
tables inherit belongs at the cross-cutting anchor, not at the row where it was discovered — and
**never `temp/`**, which has no watcher. Related: [[uniform-response-rationale-vs-built-predicate]],
[[corrupt-the-control-canary-boundary-tie]], [[measure-the-fence-regex-not-its-comment]].
