---
name: local-cluster-duplicate-grantor-drift
description: The local dev cluster grants pfin_etl each membership TWICE (postgres + supabase_admin), so 054's h12/h18 RED locally — pre-existing environment state, not a code defect.
metadata:
  type: reference
---

Measured 2026-09-08 on the local stack (`supabase_db_mosko-fintech`, port 54322):

```
pfin_etl -> authenticated  granted by postgres        set=t inherit=f
pfin_etl -> authenticated  granted by supabase_admin  set=t inherit=f
pfin_etl -> service_role   granted by postgres        set=t inherit=f
pfin_etl -> service_role   granted by supabase_admin  set=t inherit=f
```

**Consequence:** a full pgTAP sweep against any DB on this cluster shows **3 RED in
`supabase/tests/rls/054_nav_daily_rls.sql`** and nowhere else —
`(h12)` membership-set, `(h18)` set_option (both `string_agg` with no `distinct`, which is
what catches the drift), and `(h14b)` no-password (the documented
**expected-different-locally** leg: the `pfin_etl` password was deliberately retained,
F/CTO-ratified).

**Baseline figure:** 111 test files, **2913 ok / 3 not ok** on a clean scratch clone.
Anything beyond those 3 is yours.

**Why it is not a test defect.** Sec's standing ruling: *"the legs are correct; the
environment is wrong."* `distinct` is FORBIDDEN in those queries — it would make them
permanently tolerate the drift they exist to catch. Fix a real duplicate with
`REVOKE <role> FROM <member> GRANTED BY <grantor>`, per grantor.

**How to apply:** do not report these 3 as a regression, and do not "fix" the battery.
Any new role battery on the same shape ([[reference_worker_login_role_minimum_grant_is_the_empty_set]])
inherits the same exposure deliberately. Note that **roles are cluster-level**: a scratch
DB clone shares them, so a role-existence dependency guard cannot distinguish "migration
applied to THIS database" from "role exists in the cluster".
