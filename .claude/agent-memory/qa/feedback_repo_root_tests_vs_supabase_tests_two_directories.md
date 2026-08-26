---
name: repo-root-tests-vs-supabase-tests-two-directories
description: Two directories both named "tests"/"tests/rls" exist in this repo — only supabase/tests/rls holds the real pgTAP batteries. Grepping repo-root /tests/ for battery coverage gives a false "zero hits" negative.
metadata:
  type: feedback
---

Reported a "migration 092 shipped without its pgTAP battery" finding on SELF-249's walk gate.
Refuted by team-lead: the battery exists at `supabase/tests/rls/092_classify_journaled_cat_fence_rls.sql`
(23 legs, 12 references to the function I searched for). It was there the whole time.

**The trap:** the repo has TWO directories that look like the battery home:
- `/tests/` (repo root) — `fixtures/ci`, `fixtures/parity`, and a `tests/rls/` that holds only
  `DESIGN.md`. This is QA's scratch/fixture/design area, NOT where per-migration pgTAP files live.
- `supabase/tests/` — the REAL pgTAP tree (Supabase CLI's own convention): flat self-test files
  (`00_rls_inversion_self_test.sql`, `01_session_timezone.sql`, `sd15_fn_mask_acct_number.sql`)
  plus `supabase/tests/rls/<NNN>_..._rls.sql` per migration.

I ran `grep -rl "..." tests/` from the worktree root and got zero hits — a confidently-wrong
negative, because it silently searched the DESIGN.md-only decoy directory, not the real one one
level down. [[feedback_pg_prove_scope_full_tests_tree_not_rls_only]] already had the real paths
spelled out verbatim (`supabase/tests/00_rls_inversion_self_test.sql` etc.) from an EARLIER
incident about pg_prove's container-mount `/tests` shorthand papering over the actual repo path —
I didn't cross-reference it before grepping, so the same confusion recurred in a new form (a
coverage-gap claim, not a pg_prove scope error, but the identical root directory conflation).

**How to apply:** before reporting ANY "no battery exists for X" finding, grep
`supabase/tests/` (not bare `tests/`) from the repo root, or `git show main:supabase/tests/...`
directly for the specific expected filename pattern `<NNN>_..._rls.sql`. A bare `tests/` grep
from a worktree cwd is not proof of absence — verify which of the two directories a "zero hits"
result actually searched before treating it as a finding. The role's tool-boundary text saying
"`/tests/**`" is shorthand that does NOT mean the repo-root `/tests/` alone — it covers
`supabase/tests/` too, and that's where the substance actually lives.
