---
name: pg-authid-has-no-rolconfig-column
description: pg_authid carries no rolconfig column (confirmed \d pg_authid, PG17); rolconfig exists only on the pg_roles view, a LEFT JOIN onto pg_db_role_setting at setdatabase=0 — a Sec brief named the wrong catalog for 116's C2 leg.
metadata:
  type: feedback
---

Sec's C2 condition on PR #671 (116_pfin_provider_sync_role, SELF-386-adjacent)
directed a new leg asserting `pg_authid.rolconfig IS NULL`. Running it against
a live PG 17 scratch DB raised `column a.rolconfig does not exist` — verified
with `\d pg_authid` (no such column) and `pg_get_viewdef('pg_roles', true)`,
which shows `pg_roles.rolconfig` is populated by
`LEFT JOIN pg_db_role_setting s ON pg_authid.oid = s.setrole AND
s.setdatabase = 0` — i.e. it IS the global-scope slice of the SAME table a
"no rows in pg_db_role_setting" check already reads.

**Consequence for leg design:** a `pg_roles.rolconfig IS NULL` check is not
an independent surface from an unrestricted `pg_db_role_setting` scan — it's
formally redundant with that scan restricted to `setdatabase = 0`. Kept both
in 116's (r12) anyway (view-level legibility + the unrestricted scan alone
covers `IN DATABASE <db>`-scoped rows the view never surfaces), but the
redundancy should be named in review, not silently absorbed as "two
independent checks" the way the brief phrased it.

**General rule:** a security brief that names a specific catalog column is a
claim about that catalog's shape at authoring time, same as any other
memory-adjacent claim — verify with `\d <table>` before writing the
assertion, don't transcribe the column name as given. `pg_authid` carries
only role-attribute columns (rolsuper/rolinherit/.../rolpassword/
rolvaliduntil); `rolconfig` and the redacted `rolpassword='********'` both
live on the `pg_roles` view layer, not the underlying table.

See [[reference_role_battery_inversion_recipes_self386_s5]] for the sibling
`pg_largeobject_metadata.lomacl` / `pg_parameter_acl` blind-spot fixes on the
same file (116's r10), landed in the same PR as this correction.
