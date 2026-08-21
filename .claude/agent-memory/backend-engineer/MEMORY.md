# Memory index

- [Draft-verify-revert when not branch owner](feedback_draft_verify_revert_when_not_branch_owner.md) — verify commit-ready text locally, then revert the worktree before hand-off.
- [Local smoke-verify idiom](reference_local_smoke_verify_idiom.md) — `supabase migration up` (not link/push); `set_config` role/claims + rollback for read-only RLS smoke tests against seeded data.
- [pfin_etl required for ANY local ETL run](reference_pfin_etl_required_for_any_local_etl_run.md) — no local bypass; a brief that permits CPI/dry-run but bans arming pfin_etl is self-contradicting whenever it's NOLOGIN.
- [seed.sql is gitignored per-checkout](project_seed_sql_gitignored_per_checkout.md) — absent in a fresh worktree; apply by absolute path from the main checkout, don't copy.
- [Symlinked worktree node_modules can zero-collect suites silently](feedback_worktree_symlinked_node_modules_zero_collection.md) — "0 failures" ≠ full coverage; check file counts + `(0 test)` failed suites, not just pass/fail.
- [Linear comment ruling supersedes a stale AC](feedback_linear_comment_ruling_supersedes_stale_ac.md) — pull the issue's COMMENTS, not just the AC text, when an AC looks schema-impossible or duplicative.
- [Verify against the commit, not HEAD, when disputing history](feedback_verify_against_commit_not_head_when_disputing_history.md) — `git show <sha>:path`, never diff-against-worktree, when a teammate claims an earlier commit "already had" a later fix.
- [Outer fence masks inner fence](feedback_outer_fence_masks_inner_fence.md) — a denial error only proves the FIRST fence fired (schema USAGE before EXECUTE); check the specific privilege directly.
- [Never pad an abbreviated sha](feedback_never_pad_an_abbreviated_sha.md) — `git commit`'s 7-char output isn't the full sha; run `git rev-parse HEAD` before quoting one in a handoff.
