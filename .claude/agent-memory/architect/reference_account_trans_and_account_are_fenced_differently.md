---
name: account-trans-and-account-are-fenced-differently
description: pfin.account_trans is fenced by the Lock 3 account_users rd_access ACL JOIN while pfin.account is fenced by users_id = auth.uid() — so a caller can read a transaction whose account row is invisible, making INNER joins between them fail OPEN
metadata:
  type: reference
---

`pfin.account_trans`'s SELECT policy is **not** `users_id = auth.uid()`. Measured in the
catalog (`pg_policy`, scratch chain-apply, 2026-09-02):

- `account_trans_select` → `EXISTS (account_users au WHERE au.account_id = ... AND
  au.users_id = auth.uid() AND au.rd_access)` — the Lock 3 ACL JOIN — AND the `025` aal2 clause.
- `account_select` → `users_id = auth.uid()` AND the `025` clause.

**These are different predicates.** A caller holding `rd_access` on an account they do not
OWN reads that account's transactions while `pfin.account` hides the account row. So in any
read composition spanning both, an **INNER join to `pfin.account` is a row filter that fails
OPEN** — the contributor/row silently vanishes while its money remains in the figure the
same query computed. Use LEFT, and make the resulting NULL a *checkable* signal (e.g.
`pfin.account.name` is NOT NULL, so a NULL name can only mean "not visible to this caller").

**Second, sharper consequence — the taxonomy labels desynchronize from their id.**
`093 fn_cashflow_items` resolves `cat`/`sub_cat` by LEFT JOIN to the per-user RLS-scoped
`pfin.posting_prototype` while copying `sub_cat_id` from the annotation unchanged. On a
readable-but-not-owned account the reader therefore emits **`sub_cat_id` NOT NULL with
`cat` AND `sub_cat` both NULL** — a third state. Never write "these are NULL together"
about that trio, and never infer *classified* from `sub_cat_id IS NOT NULL` or
*unclassified* from `sub_cat IS NULL`; the two tests disagree exactly there.
It also means such an item passes `093`/`094`'s `sub_cat_id is not null` conjunct and is
summed into a rendered row keyed `(cat NULL, sub_cat NULL)` — neither the unclassified
banner nor a named Sub-Cat.

**Reachability, stated honestly: DORMANT in V1.** `pfin.account_users` carries a SELECT
policy only — no INSERT/UPDATE policy, no write grant to `authenticated` — so its rows come
solely from the `003` `fn_grant_creator_access` creator self-grant. **Revival condition: the
first write path inserting an `account_users` row for a non-owner** (V2 sharing, Lock 2).
Simulate it by inserting that row directly; no V1 path will.

See [[reference_join_key_decides_failure_direction]] and
[[feedback_scope_the_invariant_before_writing_it]] — this is the concrete case that
falsified an "always NULL together" invariant I had already written into a draft CONTRACT.
