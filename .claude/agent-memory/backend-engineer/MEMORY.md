# Memory index

- [Draft-verify-revert when not branch owner](feedback_draft_verify_revert_when_not_branch_owner.md) — verify commit-ready text locally, then revert the worktree before hand-off.
- [Local smoke-verify idiom](reference_local_smoke_verify_idiom.md) — `supabase migration up` (not link/push); `set_config` role/claims + rollback for read-only RLS smoke tests against seeded data.
- [pfin_etl required for ANY local ETL run](reference_pfin_etl_required_for_any_local_etl_run.md) — no local bypass; a brief that permits CPI/dry-run but bans arming pfin_etl is self-contradicting whenever it's NOLOGIN.
- [seed.sql is gitignored per-checkout](project_seed_sql_gitignored_per_checkout.md) — absent in a fresh worktree; apply by absolute path from the main checkout, don't copy.
