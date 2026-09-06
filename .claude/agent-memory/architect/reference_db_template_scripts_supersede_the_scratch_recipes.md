---
name: db-template-scripts-supersede-the-scratch-recipes
description: scripts/db-template-build.sh + db-template-clone.sh are the canonical scratch-DB path (seconds, three-legged staleness fence) and supersede the hand-rolled full-chain recipes; they export PGPASSWORD, a direct psql does not
metadata:
  type: reference
---

DevOps owns `scripts/db-template-build.sh` (applies the FULL current migrations tree into
`pfin_tmpl` and stamps `public._template_meta`) and `scripts/db-template-clone.sh <name>`
(clones it, refusing on any of three staleness legs: head migration filename, sha256 of the
whole tree, container image id — and replaying `pg_db_role_setting` rows, which
`CREATE DATABASE ... TEMPLATE` silently drops). This is the canonical path and it
supersedes the hand-rolled recipes in [[reference_scratch_db_full_chain_recipe]] and
[[reference_scratch_db_for_migration_verify]]. A full 001–115 build ran in ~7 s.

⚠ **Editing an already-numbered migration file invalidates the template** — the content-sha
leg catches it (a filename-only check would not), so `build` must be re-run before `clone`.

⚠ **The scripts `export PGPASSWORD` (default `postgres`); your own `psql` does not.** A bare
`psql -h 127.0.0.1 -p 54322 -U postgres` after a successful clone BLOCKS on `Password for
user postgres:` and reads as a hang, not an error — the prompt lands in the redirect file,
so the command looks like it produced nothing. Prefix `PGPASSWORD=postgres` on every direct
probe. Host/port default to `127.0.0.1:54322`.

⚠ **`pfin_tmpl` is shared across agents.** Rebuilding it stamps YOUR branch's tree sha, so a
teammate on a different branch gets a refusal (correct, not a break) telling them to rebuild.
Say so when you rebuild it mid-wave.

**How to apply:** any migration clean-apply verification. Never the dev DB, and never the
banned Supabase local-reset subcommand — see
[[feedback_migration_verify_resets_local_db]] and
[[feedback_a_banned_command_string_blocks_the_commit_message]] (naming that subcommand
literally in a heredoc gets the whole tool call blocked; this file was rewritten for exactly
that reason).
