# `migrator` Coolify Scheduled Task — config reference

ADR-072 (Option E) chunk 1. DevOps-owned. Documents the Coolify Scheduled
Task that runs the `migrator` service's fixed apply verb and exposes the
fail-closed exit-code-backed status ADR-072 Decision 3 gates on.

> **Why this lives here and not `docs/deployment-runbook.md`:** this note is
> scoped to DevOps's own `.github/workflows/` + Dockerfile + secrets-manifest
> write surface for this chunk. `docs/deployment-runbook.md` §6 already
> carries the ADR-072 mechanism narrative (landed with the ADR); folding this
> reference table into that file, or leaving it here as a linked note, is a
> call for whoever reviews this PR — flagged in the PR description, not
> decided unilaterally.

## What this is NOT (chunk boundary)

This is the Scheduled Task **definition** only — the resource that CAN be
executed. The trigger path that actually calls it (the `ci-migrate` SSH user,
the forced-command orchestration script, the GitHub Actions workflow that
polls `.../executions` and gates the app deploy on `success`) is **chunk 2**.
Until chunk 2 lands, this task exists but nothing calls it automatically —
an operator can still run it by hand from the Coolify dashboard or via a
direct API `POST` for the first supervised bootstrap (ADR-072 Decision 6).

## Resource attachment

Attach the Scheduled Task to the **Supabase stack Coolify resource**
(`infra/supabase/docker-compose.yml` — the one Compose application that also
runs `db`/`auth`/`rest`/`api-gw`/`supavisor`/`meta`/`studio`), targeting the
**`migrator`** service specifically. `migrator` is a sibling service in that
same Compose file, not a standalone Coolify application (see
`secrets-manifest.yml`'s `MIGRATOR_DB_PASSWORD` entry and
`scripts/provision-supabase-stack.sh` for why its credential is minted
there rather than pushed by `scripts/push-production-secrets.sh`).

## Task fields (Coolify UI: Scheduled Tasks tab on the Supabase resource)

| Field | Value |
|---|---|
| Name | `migrator-db-push` |
| Container | `migrator` |
| Command | `supabase db push --db-url "$PROD_DB_URL" --workdir /workspace` |
| Frequency | **On-demand only** — leave the cron expression as Coolify's own "manual"/on-demand option if the UI offers one; otherwise set an intentionally-inert far-future cron (e.g. `0 0 31 2 *`, which never fires on the Gregorian calendar) so the task exists as an executable resource without an unintended automatic cadence. ADR-072 Decision 2 makes the trigger an **explicit** `POST .../scheduled-tasks/{uuid}/execute` call (chunk 2's orchestration script, or an operator during bootstrap) — never a timer. |
| Container must be running | Yes (Coolify requirement for `docker exec`-based Scheduled Tasks — matches the `provider-sync` daily-poll and `pfin_back_etl` monthly-report tasks already documented in `docs/deployment-runbook.md` §7, same Pattern-A convention) |

`$PROD_DB_URL` is already present in the `migrator` container's own env
(assembled at deploy time from `MIGRATOR_DB_USER`/`MIGRATOR_DB_PASSWORD`/
`POSTGRES_HOST`/`POSTGRES_PORT`/`POSTGRES_DB` — see
`infra/supabase/docker-compose.yml`'s `migrator` service) — the command
above does not need to construct or receive it as an argument.

## The fail-closed signal (ADR-072 Decision 3)

Gate on the Scheduled Task's own **`status`**, never on Coolify's deployment
status:

- `scheduled_task_executions.status` ∈ `{running, success, failed}`.
- The real process exit code is captured as `${PIPESTATUS[0]}` by Coolify's
  own `ScheduledTaskJob.php` — a non-zero `supabase db push` exit (including
  a mid-file failure on a non-transactional migration) surfaces as `failed`,
  not swallowed the way a `post_deployment_command` failure would be.
- **Poll, don't assume finished-means-success.** `GET
  /api/v1/scheduled-tasks/{task-uuid}/executions` (or the dashboard's own
  execution history) until the latest entry's `status != running`, then
  branch on `success` vs `failed`. This polling + branch is chunk 2's
  orchestration script; this task definition is what it polls.
- **On `failed`:** the existing Coolify→Discord Scheduled-Task-failure
  routing fires (incumbent — `docs/deployment-runbook.md` §8) with no
  further action from this task; the app deploy must NOT be triggered.
- **On `success`:** the caller (chunk 2's script, or an operator during
  bootstrap) proceeds to the app deploy step.

## First-bootstrap use (ADR-072 Decision 6 — before chunk 2 exists)

An operator can execute this Scheduled Task by hand (Coolify dashboard
"Run now", or a direct authenticated
`POST /api/v1/scheduled-tasks/{task-uuid}/execute`) as the supervised
first-apply step, in place of the `supabase db push --db-url "$PROD_DB_URL"`
operator command `docs/deployment-runbook.md` §4/§6 already documents for
the interim/bootstrap path — same verb, same tracking table
(`supabase_migrations.schema_migrations`), executed inside the baked
`migrator` image instead of from an ad hoc operator shell.
