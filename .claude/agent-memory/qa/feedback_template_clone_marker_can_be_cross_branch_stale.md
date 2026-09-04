---
name: feedback-template-clone-marker-can-be-cross-branch-stale
description: pfin_tmpl's staleness marker can point at a SIBLING branch's head migration (missing your branch's own migration, carrying one yours doesn't have) — db-template-clone.sh's fence only checks staleness, not branch identity. Verify the marker's head_migration before trusting the fast clone; fall back to a genuine sequential apply (db-template-build.sh's own steps 1-6, run by hand) when it doesn't match your tree.
metadata:
  type: reference
---

SELF-263 (2026-09-03): `scripts/db-template-clone.sh`'s staleness fence compares
three legs (head migration filename, migrations-tree sha256, container image id)
against `public._template_meta` on `pfin_tmpl` and refuses to clone if any
mismatch. It does NOT check branch identity — nothing stops the template from
being built off a DIFFERENT branch's tip than the one you're verifying.

Measured: `pfin_tmpl`'s marker read `head_migration=101_tax_bracket_tables.sql`
— a file that does not exist on `feature/self-263` (which tops out at `100`) and
belongs to a sibling milestone branch (SELF-259). A bypass-the-staleness-fence
clone (`createdb --template=pfin_tmpl`, the documented workaround for "my branch
adds a migration the template doesn't have yet") would have handed back a DB
built from the WRONG branch — missing `100` entirely and carrying an unrelated
`101` — not merely a stale one.

**How to apply:** before bypassing the staleness fence, read the marker's
`head_migration` (`select head_migration from public._template_meta` on
`pfin_tmpl`) and compare it to your own tree's actual highest-numbered migration
file. If they diverge in a way staleness alone doesn't explain (the template's
head is a DIFFERENT number/name than what a strict superset of your tree would
produce — not just "behind"), the template was built off a different branch, not
just an old commit on the same one — don't clone it, even via the documented
bypass. Fall back to `db-template-build.sh`'s own steps 1-6 (dump auth/
extensions/vault/etc from the running container, load as supabase_admin, create
extensions, hand ownership to postgres, apply `supabase/migrations/*.sql`
sequentially, `create extension pgtap schema public`) run BY HAND against a
throwaway DB name — this sidesteps both the cross-branch contamination and the
`pg_db_role_setting`/TimeZone gap a template clone carries
([[feedback_scratch_db_pgtap_harness_gotchas]] item 4), letting the FULL
`supabase/tests` tree (including `01_session_timezone.sql`) run clean via
`supabase test db --db-url ...` with no path override, matching CI's own
invocation exactly. Never write to `pfin_tmpl` itself while doing this — only
read its marker.
