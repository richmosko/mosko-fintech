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
| Command | ```sh /workspace/pfin-task.sh``` — ⚠ **ADR-072 Amendment 8 (2026-09-18, F/CTO-ratified option (B), Architect's `architect-a7-command-length.md`; Sec pre-graded in `sec-pregrade-baked-task-script.md`):** the ORIGINAL inline literal (357 bytes — three tagged `echo`s, the `db push`, the `rc` capture, all spelled out here) did **NOT FIT** Coolify's `scheduled_tasks.command` column (`character varying(255)`, measured, never widened by any migration through v4.3.18 — confirmed by a real `SQLSTATE 22001` save failure). Every rewrite that fits 255 bytes deletes either the `rc=$?` failure-capture (making every FAILED migration report SUCCESS — Sec **VETO**) or one of the two ledger-comparison tags (making the delivery assertion one-sided, meaningless — Sec **VETO**). Neither is acceptable, so the full logic is now **baked into the image** instead: `infra/supabase/migrator/pfin-task.sh` (COPYed in by the Dockerfile, `chmod 0755`, with a build-time existence-and-syntax assertion so a corrupted COPY fails the build rather than fire time). This Command row now holds only the 26-byte invocation of that script — see `pfin-task.sh`'s own header for the full logic (byte-for-byte identical to what this row used to spell out inline). ⚠ **CORRECTED (Sec, #812 GREEN pin, 2026-09-18 — pre-existing since #802's original literal, first caught here because the script is new and the box gets one image):** the `PFIN-NEWEST-FILE` read (`ls /workspace/supabase/migrations | ... | sort -V | tail -1 | cut -d_ -f1`) now **filters to migration-shaped names (`^[0-9]+_.*\.sql$`) before sorting** — a bare `ls` of the whole directory listed every entry, and a stray non-migration file sorting last with `sort -V` would wedge the trigger at exit 8 (malformed tag) on every future fire. ⚠⚠ **NAMED PROHIBITION, stated here too, not only in the script (Architect's ADR-072 Amendment 8 addendum):** the `rc=$?; …; exit $rc` capture inside `pfin-task.sh` is **load-bearing for ADR-072 Decision 3** — `sh -c 'false; echo TAG=x'` exits `0`. **Never remove it to save bytes.** A future edit that shortens `pfin-task.sh` and drops that capture makes every FAILED migration report SUCCESS, silently, forever. **This Command row is still the literal's home (Sec FLAG B fix, #802) — edit it first** if the invocation path ever changes (the LOGIC itself lives in `pfin-task.sh`, never duplicated). **The hand-maintained-copy count is genuinely TWO now (refined per Sec's #811 verdict), not four:** this row, and `MIGRATOR_TASK_COMMAND` in `/etc/pfin/migrator-trigger.conf` (written by `scripts/provision-vps.sh`). `infra/supabase/docker-compose.yml`'s comment is a **pointer**, not a third copy — it names where the literal lives and where the real logic lives, never restating the invocation string. Coolify's own stored task is the live **target** this gets compared against, not a repo-tracked copy. `docs/deployment-runbook.md` §6.5 documents the propagation procedure between the two real copies and that live target — `migrator-orchestrate.sh` fails closed (exit 10/11) if Coolify's live task ever drifts from that literal. **Why (B) over shortening the inline literal to fit 255 (Architect's measurement):** a rewrite that keeps the `rc` capture and drops `PFIN-BUILD-SHA` reaches 230 bytes but removes the sha gate's only evidence; a rewrite that keeps all three tags but drops `rc=$?; ...; exit $rc` also reaches budget but means `sh -c 'false; echo TAG=x'` exits **0** — a failed migration reporting success, the exact vacuous-green defect ADR-072 Amendment 6 exists to close. **Why (B) is a net C5 improvement, not merely a workaround (Sec's pre-grade):** the evidence-producing instruction moves OUT of a store the trigger token's `write` ability can rewrite (`PATCH .../scheduled-tasks/{uuid}`) and INTO an image layer built from merged, CI-reviewed `main`, anchored by Amendment 6's own sha assertion — a stronger anchor than the `$CONF_FILE` literal comparison ever was. **Named residual (Sec):** the sha self-report (`PFIN-BUILD-SHA`) now also carries a TAMPERING threat it was not originally graded for (it was accepted for STALENESS only — "a stale image honestly reports its stale sha and is caught... it fails only against a container that lies, which is not this assertion's threat model") — this residual is recorded, not resolved, by this change; see the ADR text for the full re-grade. |
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
- **Poll, don't assume finished-means-success — and don't poll "the latest
  entry," poll THE EXECUTION THIS FIRE CAUSED.** ⚠ **CORRECTED 2026-09-18,
  same defect on the manual path as the automated one:** Coolify creates
  the execution row only once a queue worker actually starts processing
  the dispatched job, never when `POST .../execute` returns — so a poll
  run right after firing can see only a PREVIOUS execution's row, and
  "the latest entry" is that previous row, not this fire's. `scripts/
  migrator-orchestrate.sh` binds this by a **uuid set difference**, and an
  operator doing this by hand should do the same, not read the list head:
  1. **Before** executing: `GET /api/v1/scheduled-tasks/{task-uuid}/executions`
     and note every `uuid` present (or, at minimum, the count).
  2. `POST /api/v1/scheduled-tasks/{task-uuid}/execute`.
  3. Poll `GET .../executions` again, repeatedly, until **exactly one**
     `uuid` appears that was **not** in step 1's set. Zero new uuids
     means this fire's execution hasn't shown up yet — keep polling; two
     or more means another execution fired concurrently (e.g. someone
     else's "Run now") — stop and disambiguate by hand rather than
     guessing.
  4. Read `status` (and, on `success`, `message`) from **that uuid's row
     specifically**, never from the list's head, until `status !=
     running`, then branch on `success` vs `failed`.
  This polling + branch is chunk 2's orchestration script
  (`scripts/migrator-orchestrate.sh`); this task definition is what it
  polls. (Read-only `curl` via a config file with the API token, never a
  pasted bearer token on the command line — operator hygiene, not a new
  rule.)
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
