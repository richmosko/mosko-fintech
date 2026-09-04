---
name: signature-change-needs-a-drop-not-a-runbook
description: A `create or replace function` whose PARAMETER LIST changed adds an overload — the superseded form survives with its EXECUTE grant; check for an explicit drop, and check whether the battery's detector can fire in CI at all
metadata:
  type: feedback
---

When a migration changes an RPC's **parameter list** under `create or replace function`, the old
form is **not replaced** — it survives as an overload, carrying its own `grant execute … to
authenticated`. Ask three questions, in this order:

1. **Is there a `drop function if exists <old exact signature>` ahead of the create?** Grep the
   migration for `drop function` / `drop routine`. Absence is the finding.
2. **What can the surviving overload still do?** Walk its body against the new column. At SELF-259
   the stale 6-arg replace-all's `UPDATE` never touched the new `NOT NULL` column, so `NOT NULL`
   did **not** stop it — it rewrote the brackets and silently carried the stale caption forward,
   i.e. it was a live write path that reproduced the exact defect the new column was added to
   prevent. **`NOT NULL` on a column an old writer never names is not a fence.**
3. **Where can the catch actually fire?** Legs keyed on `proname` alone are accidental detectors —
   a count leg goes off-by-one and a scalar subquery errors on the second row. **But CI builds the
   DB from scratch and structurally cannot hold the stale object**, so those legs can never fire
   where it matters. A detector that only fires in the environment nobody runs the battery in is
   not the fence; the `drop` is. See [[probe-that-only-asserts-failure-goes-vacuous]].

**Why:** the mitigation offered was a runbook paragraph in the *endpoint's* header and the
*battery's* header — neither of which is read by the person applying migrations. A runbook is not
a control; it degrades to nothing the moment nobody reads it. The `drop … if exists` no-ops on a
fresh DB and removes the hazard **by construction**.

**How to apply:** any diff whose stat touches a migration AND shows a changed function argument
list. Also: before letting a same-named repo convention retire the flag, read that convention —
`docs/MILESTONE-FRAMING.md` §8.2's "drop-replace migration pattern" is the Google-Sheets→V1
data-plane transition, **not** a fresh-apply rule, and the name collision is exactly the kind of
thing that gets a finding dismissed. Related: [[verify-the-stated-correctness-mechanism]],
[[a-prose-described-fence-is-wrong-twice]].

**Companion drift:** the same branch's battery header described the superseded form by the **new**
form's arity ("the old 7-argument signature" when the old one had six). Comment-only, but it is the
one sentence an operator reads to decide whether their DB is affected, and it points them at the
safe object. **When a signature moves, grep every prose mention of its arity, not just the SQL.**

## ⚠ The drop is half a fix — generalize to RE-APPLIABILITY

A function's missing `drop` and a table's `create table if not exists` are **the same defect**. A
column declared *inline* in a `create table if not exists` is **never created** on a DB that already
holds the table — and neither is any change to an inline `CHECK`. Measure the whole file, not the
function: grep for `alter table … add column if not exists` and `drop constraint` / `add constraint`.
At `101` there were none, while the repo's own convention uses `add column if not exists` across 13
other migrations — so the file was the outlier, and landing only the `drop function` would have made
it **look** re-appliable while the table half silently was not. **The half-state is worse than the
uniform one.** Force the choice: finish the job to the repo convention, or declare the file
fresh-apply-only *in that file's own header*.

## The catch-leg trap this always ships with

A proposed leg of the form *"exactly one function of that name with `pronargs = N`"* **cannot fire**:
the arity predicate filters the stale overload out of its own count. It must be **two facts that can
disagree** — count over `proname` alone = 1, then separately assert that row's `pronargs`. Same
family as [[measure-the-fence-regex-not-its-comment]] and
[[an-enumeration-and-its-watcher-both-stop-one-short]]. Also check the `drop`'s **placement**: if its
signature names a type the same file creates (an enum in a `do $$` block), a drop hoisted to the head
of the file errors on a fresh DB.

## When a blank-check gets added to a length CHECK

`length(btrim(x)) between 1 and N` **stops bounding what is stored** — padding passes, so a direct
writer (the Lock 14 premise: `authenticated` holds full CRUD) can store arbitrarily long values. And
**one-arg `btrim` strips ASCII SPACE only** — not tab/newline/CR/NBSP — while JS `.trim()` strips all
of them, so the DB ends up MORE permissive than the app on the surface where the DB must hold.
Prefer a canonical-form **state** invariant: `check (x = btrim(x, E' \t\n\r\f\v') and length(x)
between 1 and N)`. ⚠ **Never claim layer parity here** — exact JS-`.trim()`/SQL equivalence is not
reachable (exotic Unicode whitespace stays DB-legal and app-illegal); record the residual instead.
Related: [[adding-vs-qualifying]] — my own qualifier is the unchecked one.
