---
name: seed-sql-gitignored-per-checkout
description: supabase/seed.sql is gitignored (F/CTO's personal taxonomy seed) and therefore exists only in whichever checkout created it — not automatically present in a fresh worktree.
metadata:
  type: project
---

`supabase/seed.sql` (F/CTO's dev-user taxonomy materialization, read from the committed `pfin.taxonomy_default` table added at migration `041`) is listed in `.gitignore` (line 9/11, "Personal financial taxonomy seed (SELF-231)"). Because it's untracked, it does not exist in a fresh `git worktree` checkout even though `git worktree`s share the same repo history — untracked files are per-working-directory, not per-repo. Confirmed 2026-08-14: the file was absent from `mosko-fintech-worktrees/backend` but present at `/Users/mosko/Projects/mosko-fintech/supabase/seed.sql` (the main/shared checkout).

**How to apply:** when a task asks you to apply `supabase/seed.sql` (or any other gitignored root-tracked-by-convention file) from a worktree, don't assume it's there — check the main checkout first and reference it by absolute path in `psql -f`, rather than copying it into the worktree (copying risks the two copies drifting, and the file is F/CTO's own data, not something Backend authors). See [[reference_local_smoke_verify_idiom]] for the sibling pattern of applying SQL directly against the local dev DB without `supabase db reset`.
