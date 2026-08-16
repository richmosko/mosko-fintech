---
name: pfin-etl-required-for-any-local-etl-run
description: workers/etl has no local-dev bypass for the pfin_etl login role — CPI pull, NAV backfill, and any other ETL script all require pfin_etl armed (LOGIN + password), even for a dry run.
metadata:
  type: reference
---

`workers/etl/.env.example` hardcodes `PFIN_DB_USER=pfin_etl` with no alternative identity, and `pfin_back_etl.utils.load_env_variables` reads it via a bare `os.getenv(env_prefix + "DB_USER")` — no fallback, no local-only override (unlike `BLS_API_KEY_TEST`, which *does* have a distinct local/CI variant per `secrets-manifest.yml`). Every worker entry point (`run_cpi_backfill.py`, `run_nav_backfill.py`, `main.py`) opens its DB connection through this same env contract, so **all of them** — including a NAV-backfill dry run, which only reads — require `pfin_etl` to already be armed (`rolcanlogin = true` + password set, per migration `055`'s two-step deploy handoff: `\password pfin_etl` then `ALTER ROLE pfin_etl LOGIN`).

**Why this matters:** a task brief that authorizes "CPI re-pull" or "dry-run only" while separately prohibiting "arming pfin_etl" is internally contradictory whenever `pfin_etl` is currently NOLOGIN (e.g. right after a `supabase db reset`, which recreates the role inert from migration `055`). Check `select rolname, rolcanlogin, rolinherit from pg_roles where rolname = 'pfin_etl'` before assuming any workers/etl script is runnable locally — a `false` there blocks the whole category, not just writes.

**How to apply:** any local workers/etl task. If `pfin_etl` reads NOLOGIN and arming it is out of scope (F/CTO-gated, or otherwise not authorized in the brief), stop and flag the contradiction rather than either arming it unilaterally or silently skipping the step. See [[project_seed_sql_gitignored_per_checkout]].
