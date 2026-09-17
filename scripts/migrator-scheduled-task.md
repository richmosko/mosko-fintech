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
executed. **Chunk 2 (this repo, same PR generation as this note's update)
built the trigger path** — the `ci-migrate` SSH user (C1), the forced-command
`authorized_keys` line (C3), `scripts/migrator-orchestrate.sh` (C2/C4/C5,
which polls `.../executions` and gates the app deploy on `success`), the
scoped `migrator-trigger` Coolify token, and
`.github/workflows/migrator-trigger.yml` — but the trigger is **not yet
LIVE**: the `CI_MIGRATE_SSH_PRIVATE_KEY` GitHub Actions secret is not yet
provisioned and `provision-vps.sh --apply` has not yet run this section
against the production box. Both are F/CTO `!`-steps after this PR merges
and clears Sec joint-review (docs/deployment-runbook.md §6.4). Until then,
this task exists but nothing calls it automatically — an operator can still
run it by hand from the Coolify dashboard or via a direct API `POST` for the
first supervised bootstrap (ADR-072 Decision 6).

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
| Command | `supabase db push --yes --db-url "$PROD_DB_URL" --workdir /workspace` — `--yes` added 2026-09-17 (ADR-072 Amendment 6). Measured this session against the exact pinned CLI binary (v2.107.0, not just its source): under `docker exec` with no pseudo-tty (this Scheduled Task's own invocation shape), the confirmation prompt does NOT hang and does NOT silently decline — a non-TTY read times out after 100ms and falls through to the prompt's own hardcoded default, which for `db push` is "yes" (`internal/utils/console.go`'s `ReadLine`/`PromptYesNo`, `internal/db/push/push.go`'s three `PromptYesNo(ctx, msg, true)` call sites). So this was already safe before `--yes` was added — the flag is added so correctness stops depending on an unversioned upstream default that this repo does not control and could change on a future CLI bump with no compatibility guarantee. Empirically confirmed `--yes` works on the real pinned binary (auto-answers immediately, no prompt wait), and that an actual decline (only reachable by piping literal `n` — not something this Scheduled Task's own command line ever does) exits non-zero with the ledger correctly unchanged, never a silent skip — measured against a disposable rig running the exact release binary, four cases (with/without `--yes`, closed stdin vs. a real decline), ADR-072 Amendment 6. |
| Frequency | **On-demand only.** ⚠ **Corrected 2026-09-13 (standup step 6, Phase A.2) — measured against the live Coolify 4.3.18 API, not assumed.** The impossible-date trick this row previously named (`0 0 31 2 *`, betting on a Gregorian-calendar date that never occurs) is **rejected by this Coolify version's own validator** — `validate_cron_expression()` (`bootstrap/helpers/shared.php`) wraps `dragonmantank/cron-expression`'s `CronExpression::isValid()`, which checks the day-of-month/month combination is a *real* calendar date and returns `false` for Feb 31 (confirmed live via `artisan tinker`: `0 0 31 2 *` → `false`; `0 0 1 1 *` and `@yearly` → `true`). Creating the task with that expression fails the `POST .../scheduled-tasks` call with a 422. **Actual inertness mechanism: `enabled: false`**, paired with any syntactically valid cron (`0 0 1 1 *` used at creation). Source-verified this is sufficient: `app/Jobs/ScheduledJobManager.php`'s `scheduledTaskQuery()` selects tasks with `->where('enabled', true)` (the production timer path; `app/Console/Commands/ScheduledJobDiagnostics.php` carries the same filter but is a diagnostics-only artisan command and is not load-bearing) — a disabled task is never picked up by Coolify's own automatic scheduler, regardless of what its `frequency` string says. The explicit `POST .../scheduled-tasks/{uuid}/execute` call (chunk 2's orchestration script, or an operator during bootstrap) addresses the task directly by UUID and does **not** consult the `enabled` flag or go through the scheduler's selection query — so `enabled: false` blocks the *automatic* path only, exactly the property this row needs, without depending on an expression whose "never fires" property is calendar-semantics folklore that this Coolify version's own validator happens to disagree with. ADR-072 Decision 2 makes the trigger an **explicit** execute call (chunk 2's orchestration script, or an operator during bootstrap) — never a timer. |
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
