---
name: per-role-settings-bypass-a-login-roles-posture
description: Every new cluster LOGIN role needs a rolconfig/pg_db_role_setting assertion — ALTER ROLE ... SET is a DEMONSTRATED, catalog-invisible bypass measured on this project
metadata:
  type: feedback
---

When reviewing any new cluster-level **LOGIN** role, assert `pg_roles.rolconfig IS NULL`
(equivalently: no `pg_db_role_setting` row) as its own leg. A role-attribute battery
that checks `rolinherit` / `rolsuper` / `rolbypassrls` / memberships / `set_option` /
the ACL inventory can be **100% green while the posture is entirely defeated**.

**Why:** `ALTER ROLE <r> SET <guc>` is a per-role default that (i) an *ordinary* role may
set **on itself** — no privileged actor required, (ii) applies at **LOGIN and does not
survive `SET ROLE`**, so it binds exactly the login-role class and is invisible from any
other role's session, and (iii) is a **demonstrated** vector here, not theoretical:
`supabase/migrations/061_pin_database_timezone_utc.sql` records that an
`ALTER ROLE ... SET timezone` was live on the LOGIN role `authenticator` on 2026-08-04
(found by QA, cleared 08-05) while a `postgres`-session read-back showed clean
`UTC | database` throughout **and the suite ran green**.

The two vectors to name explicitly:
- `ALTER ROLE r SET role = '<privileged>'` → every session starts ambiently elevated.
  This defeats NOINHERIT fail-closed while `rolinherit=f`, MEMBER-yes/USAGE-no,
  `set_option=true` and an empty ACL inventory ALL still read correctly.
- `ALTER ROLE r SET timezone` → escapes the `061` database-level UTC pin on that
  role's sessions only.

**How to apply:** at the surface-introducing PR for any new LOGIN role — (1) require the
`rolconfig` leg with a strike; (2) check whether `docs/deployment-runbook.md` §10 TZ-1
still enumerates login roles **by name** (it did at 2026-09-08: `authenticator`,
`pfin_etl`) and require the new role be added, because an un-enumerated login role is
unchecked by construction. Also check the ACL-inventory leg for `pg_parameter_acl`:
a `GRANT SET ON PARAMETER session_replication_role` re-opens the trigger bypass that
"needs superuser" rationales rely on, and neither an attribute leg nor a relation/
function/schema ACL sweep sees it.

Related: [[feedback_measure_the_fence_regex_not_its_comment]] ·
[[feedback_assertion_with_no_watcher]] ·
[[feedback_a_grep_over_comments_measures_intent_not_data]]
