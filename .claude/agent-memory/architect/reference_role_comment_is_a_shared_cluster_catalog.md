---
name: role-comment-is-a-shared-cluster-catalog
description: comment on role writes pg_shdescription, a SHARED cluster-wide catalog — so a scratch-DB apply of a role-comment migration is NOT isolated and leaks into every database on that cluster, including the shared dev DB.
metadata:
  type: reference
---

`comment on role` / `comment on database` / `comment on tablespace` write
**`pg_shdescription`**, a **shared** catalog — one row per object for the whole
cluster, not per database. `comment on table` / `on function` / `on column` write
`pg_description`, which **is** per-database.

**The consequence that bites:** the standard "verify on a scratch clone, then drop
the clone" isolation does **not** hold for a role-comment migration. Applying it to
`scratch117` changed the comment the shared dev DB reads, and dropping `scratch117`
did not undo it — measured 2026-09-09 at `117`. A fresh `pfin_tmpl` clone inherits
it too, because the template's stamp covers the migrations tree, not shared catalogs.

Read it back with `shobj_description(oid,'pg_authid')` (note **`sh`**obj_ — plain
`obj_description` will not find it):

    select shobj_description(oid,'pg_authid') from pg_authid where rolname='…';

**Why it still verifies cleanly:** `COMMENT ON ROLE` **is transactional**, so
`begin; \i mig.sql; rollback;` genuinely parses-and-reverts. So are `alter role …
login` / `password null`, which is how to fire a `rolcanlogin`-gated `raise warning`
in a re-apply guard without leaving the cluster changed — flip inside a transaction,
run the guard, roll back, then re-read the catalog to prove restoration.

**⚠ Sec escalated this from a caveat to a REQUIREMENT (2026-09-09, #675 C7):** a
scratch DATABASE is the wrong instrument, not merely an imperfect one. Render-verify
and any replay of a role-comment migration must run in a **disposable CLUSTER** (a
fresh container). A scratch-DB run reads the right bytes without isolating them —
the "before" capture is unrepeatable once the first apply lands, and a failed run
leaves the cluster changed with nothing to roll back to.

**How to apply:** for any migration whose only DDL is a shared-catalog comment, say
so in the CONTRACT block and in the PR body, so whoever applies it knows the blast
radius is the cluster and not the database. Do not present a scratch-DB apply of one
as isolated. See [[reference_db_template_scripts_supersede_the_scratch_recipes]] and
[[feedback_migration_verify_resets_local_db]].
