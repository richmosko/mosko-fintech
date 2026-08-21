---
name: feedback-count-distinct-silently-drops-null
description: count(distinct col) never counts a NULL value in Postgres/SQL — recurred twice in one battery file (SELF-330, 086) even after being caught once
metadata:
  type: feedback
---

`count(distinct sub_cat_id)` in Postgres (and standard SQL generally) silently excludes NULL from
its distinct-value tally — COUNT never counts NULL, full stop, regardless of DISTINCT. A construct
meant to prove "N groups including the Unsorted/NULL group" will therefore always undercount by
exactly one whenever a NULL-keyed group is genuinely present.

**Why:** measured twice in the same file (086_fn_subcat_contributors_rls.sql, SELF-330) — first in
assertion (P1), caught by a real `pg_prove` run against Architect's committed function ("have: 2
want: 3"); then AGAIN in a sibling assertion (F1) using the identical unsafe construct, self-caught
only on a second pass before delivery. Naming one NULL-blind instrument in a self-test (the file's
own N1/N2 EXCEPT-vs-NOT-IN section) did NOT immunize the file against a DIFFERENT NULL-blind
construct one leg over — Architect's own framing, and it is exactly right.

**How to apply:** any time an assertion needs "how many distinct GROUPS, including a possible NULL
key" — never write `count(distinct col)`. Write `count(*) from (select distinct col from ...) x` (a
subquery materializes one row for NULL, which COUNT(*) over it then counts normally), or use
`array_agg(distinct col)` and check array length, or `EXCEPT`-based set comparison instead. When
reviewing a battery that touches a nullable key (an Unsorted/unclassified row, a LEFT JOIN degrade
target, any "sub_cat_id IS NULL" population), grep the file for `count(distinct` as a class, not
just the specific site under review — the same file having the bug at two independent sites is the
default expectation, not a coincidence to be surprised by.

Same family as [[feedback_rt26_fence_matches_tokens_not_intent]] and the EXCEPT-vs-NOT-IN
instrument this file's own N1/N2 section documents — NULL-blindness is a recurring SQL-semantics
trap, not a one-off typo, and the fix is to check the CLASS of construct, not just patch the
instance found.
