---
name: join-key-decides-failure-direction
description: Whether a join fails OPEN or CLOSED under an RLS regression is decided by its key — a tenant-bound surrogate fails closed, a shared-vocabulary string fails open and needs an explicit users_id conjunct
metadata:
  type: reference
---

**Two joins against the same RLS-protected table can have opposite failure
directions, and the discriminator is what they key on.**

- **Keyed on a tenant-bound SURROGATE** — `ut.id = uac.sub_cat_id`, where the
  right side is itself a tenant-scoped row's column. Under an RLS regression a
  foreign row's id cannot match any of the caller's own ids, so the join **fails
  CLOSED** with no tenant predicate of its own.
- **Keyed on SHARED VOCABULARY** — `cat = 'Liabilities' and sub_cat = 'Liability
  Balances'`. Every tenant's row carries the same strings, so a leaked foreign row
  matches **by name**. The join **fails OPEN** and will attach a foreign
  surrogate id to the caller's data. An explicit `users_id` conjunct is then the
  **SOLE** tenant discriminator against an RLS regression.

**Why:** `081` (SELF-329), 2026-08-17 — mine. I added
`lut.users_id = acc.users_id` to a name-keyed taxonomy join, documented it as
**"REDUNDANT under this function's INVOKER RLS … explicit rather than
inherited"**, and flagged it to Sec as something they should feel free to reject.
Sec measured every taxonomy join in the function and **inverted** the reading:
redundant against a *correctly functioning* RLS, load-bearing against a
*regressed* one.

> ⚠ **The part worth keeping: both halves were in my own file one line apart, and
> I never joined them.** I wrote that the join is *"matched by NAME because there
> is no id to follow"* — which is exactly the reason the conjunct is not
> redundant — and then, in the next sentence, called it redundant. **Writing the
> premise is not noticing the consequence.**

**Second-order hazard, and the reason Sec required a comment rewrite rather than
just keeping the code:** a comment that justifies a fence as *"explicit rather
than inherited"* **invites its own removal** — the next reader sees the id-keyed
siblings carrying no conjunct and strikes this one for consistency. A fence's
comment must state the asymmetry that makes it necessary, not a stylistic
preference. See [[assertion-with-no-watcher]] and
[[replacement-control-name-the-losing-side]].

**How to apply:**
- Before adding or removing a tenant predicate on a join, ask **what the join
  keys on**, not whether RLS "already covers it."
- A name/label/enum key against a per-tenant table is a **fail-open** shape.
  Surrogate-id keys are fail-closed.
- When a fence's siblings correctly lack it, the comment must say **why they
  differ**, or consistency-tidying will remove it.

Related: [[rls-qual-privilege-semantics]] · [[permissive-harness-vacuous-green]] · [[safety-proof-is-the-hazard-notice]]
