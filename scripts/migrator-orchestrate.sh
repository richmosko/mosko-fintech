#!/usr/bin/env bash
#
# migrator-orchestrate.sh — ADR-072 (Option E) chunk 2: the forced-command
# script that IS the `ci-migrate` SSH trigger (Decision 2 C2/C4/C5). Runs AS
# `ci-migrate` on the production box, invoked ONLY via that user's
# authorized_keys forced command — never run directly, never run as any
# other user. DevOps-owned; materialized onto the box (root-owned, mode 0755,
# NOT writable by ci-migrate) by scripts/provision-vps.sh, which is the
# versioned source of truth for what's on the box (ADR-072 Decision 5,
# box-side update channel).
#
# WHAT THIS SCRIPT REFUSES TO DO (Sec C2 — load-bearing, read before editing)
#   It NEVER reads, evals, or dispatches on $SSH_ORIGINAL_COMMAND. A forced
#   command already ignores it in the sense that sshd runs THIS script
#   regardless of what the client asked for — C2 goes further: this script's
#   OWN body must not even reference the variable, because a future edit that
#   starts reading it for "convenience" (e.g. a --dry-run flag from the
#   client) reopens exactly the client-controlled-dispatch hole the forced
#   command exists to close. If you are about to add
#   `case "$SSH_ORIGINAL_COMMAND" in ...` to this file, stop — that is the
#   change C2 forbids, not a refinement of it. Every input this script acts
#   on comes from the box-resident config file below, never from the
#   invoking SSH session.
#
# WHAT IT DOES (ADR-072 Decision 2 + Decision 3)
#   1. Execute the migrator Coolify Scheduled Task (the `supabase db push`
#      apply, scripts/migrator-scheduled-task.md).
#   2. Poll that task's own execution status to a terminal state — NEVER
#      Coolify's deployment status (that swallows a post-deploy-command
#      failure; this is the exact D-shaped trap ADR-072 Decision 3 records).
#   3. On SUCCESS: trigger the app deploy. On FAILURE or a poll timeout:
#      exit non-zero and do NOT deploy — the existing Coolify->Discord
#      Scheduled-Task-failure routing fires on its own, no action needed
#      here.
#
#   The calling GitHub Actions workflow gates on THIS script's own SSH exit
#   code — GHA's native step-sequencing is the fail-closed gate (ADR-072
#   Consequences / this ADR's GitHub Actions item): a non-zero exit here
#   fails the SSH step, which fails the job, which stops the workflow before
#   anything downstream runs. There is no separate "poll Coolify" step in the
#   workflow — polling happens HERE, inside the one orchestrated unit whose
#   exit code the SSH channel carries.
#
# CONFIGURATION — box-resident only, never client-supplied
#   /etc/pfin/migrator-trigger.conf   Non-secret: MIGRATOR_SERVICE_UUID,
#                                     MIGRATOR_TASK_UUID, APP_UUID. Written by
#                                     provision-vps.sh from the operator's
#                                     local .env (these UUIDs come from the
#                                     Coolify resources chunk 1 documents
#                                     creating — see
#                                     scripts/migrator-scheduled-task.md).
#   /etc/pfin/migrator-coolify-token.env
#                                     `COOLIFY_API_TOKEN=...` — the SCOPED
#                                     token this box mints for exactly this
#                                     script (ADR-072 C4/C5; see
#                                     provision-vps.sh's "migrator trigger
#                                     token" step for how it's minted and why
#                                     its abilities are `read,write,deploy`,
#                                     NOT `root`). Owned ci-migrate:ci-migrate,
#                                     mode 0600 — root mints it, chowns it to
#                                     ci-migrate, and this script (running AS
#                                     ci-migrate) is the only reader.
#
# WHY THE COOLIFY API IS REACHED ON localhost:8000 FROM HERE
#   Coolify's API/dashboard is not publicly reachable at all (ADR-072
#   Decision 2, measured) — :8000 has no Traefik route and is excluded from
#   the box firewall. This script runs ON the box (as the SSH session's
#   remote command), so `localhost:8000` is reachable from inside it exactly
#   the way an operator's own SSH-tunneled `curl` reaches it today
#   (docs/deployment-runbook.md §3's explicit-deploy pattern) — this script
#   is that same curl, invoked by CI instead of by a human.
set -euo pipefail

CONF_FILE="/etc/pfin/migrator-trigger.conf"
TOKEN_FILE="/etc/pfin/migrator-coolify-token.env"
# TOKEN_VAR_NAME must match MIGRATOR_TOKEN_VAR_NAME in scripts/provision-vps.sh
# -- one name, asserted in both files, not two copies that can drift.
TOKEN_VAR_NAME="COOLIFY_API_TOKEN"
COOLIFY_BASE="http://localhost:8000/api/v1"
POLL_INTERVAL_S=5
POLL_MAX_ATTEMPTS=120   # 120 * 5s = 10 minutes ceiling on the migration apply

log() { printf '[migrator-orchestrate] %s\n' "$*" >&2; }
fail() { log "FAIL: $*"; exit 1; }

[[ -r "$CONF_FILE" ]] || fail "missing or unreadable $CONF_FILE — provision-vps.sh must materialize this before the trigger is usable"
[[ -r "$TOKEN_FILE" ]] || fail "missing or unreadable $TOKEN_FILE — provision-vps.sh must mint the scoped migrator-trigger Coolify token before the trigger is usable"

# 2026-09-16 incident: this used to `source` both files under `set -a`.
# $TOKEN_FILE on the box held the bare token VALUE with no `NAME=` prefix
# (a stale write from before the writer's current format) -- `source`
# executed that value as a shell command, printing it to F/CTO's terminal.
# Never execute box-resident file content as commands, even root-authored,
# never-client-input content: read each expected NAME by grep, not by
# sourcing. A malformed file (missing prefix, garbage, anything) then
# yields an EMPTY variable, not an executed line -- caught by the `:?`
# guards below, never by bash's command dispatcher.
read_kv() { # read_kv <file> <name>
  grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- || true
}
MIGRATOR_SERVICE_UUID="$(read_kv "$CONF_FILE" MIGRATOR_SERVICE_UUID)"
MIGRATOR_TASK_UUID="$(read_kv "$CONF_FILE" MIGRATOR_TASK_UUID)"
APP_UUID="$(read_kv "$CONF_FILE" APP_UUID)"
DEPLOY_ON_SUCCESS="$(read_kv "$CONF_FILE" DEPLOY_ON_SUCCESS)"
COOLIFY_API_TOKEN="$(read_kv "$TOKEN_FILE" "$TOKEN_VAR_NAME")"

: "${MIGRATOR_SERVICE_UUID:?$CONF_FILE must set MIGRATOR_SERVICE_UUID}"
: "${MIGRATOR_TASK_UUID:?$CONF_FILE must set MIGRATOR_TASK_UUID}"
: "${APP_UUID:?$CONF_FILE must set APP_UUID}"
: "${COOLIFY_API_TOKEN:?$TOKEN_FILE must set $TOKEN_VAR_NAME}"

api() { # api <METHOD> <PATH>
  curl -fsS -X "$1" -H "Authorization: Bearer $COOLIFY_API_TOKEN" "$COOLIFY_BASE$2"
}
jqp() { python3 -c "import json,sys;$1"; }

# ⚠ ADR-072 Amendment 6 (draft) — Sec's "assert the OUTCOME, not the
# STATUS" ruling on the 119 fire (2026-09-17). Three Phase D fires ran
# `db push` against a STALE migrator container — the image was never
# rebuilt/redeployed after the sha that added new migrations merged — and
# reported clean success, because an empty diff is a valid `db push`
# outcome. Every hop this script controls (execute -> poll -> deploy) was
# working correctly; nothing here could have caught it, because nothing
# here asked "does the container about to run this actually carry the
# migration set I was triggered for." This check asks exactly that,
# LOCALLY on this box, no Coolify API involved -- a mismatch fails BEFORE
# the Scheduled Task is ever executed.
#
# ⚠ THIS READS MIGRATOR_EXPECT_SHA, A NEW NAMED ENVIRONMENT VARIABLE -- NOT
# $SSH_ORIGINAL_COMMAND, AND THIS IS NOT AN EXCEPTION TO C2 SWALLOWED
# QUIETLY. C2 (this script's own header, above) forbids reading
# $SSH_ORIGINAL_COMMAND or case-dispatching on client input -- that
# invariant is UNCHANGED and this code does not touch that variable.
# MIGRATOR_EXPECT_SHA arrives over a DIFFERENT, narrower channel (OpenSSH's
# `SetEnv`/`AcceptEnv`, sshd_config-gated to this ONE variable name, added
# by scripts/provision-vps.sh -- see that script's own comment at the
# `AcceptEnv` line) and this script treats it PURELY AS A COMPARISON VALUE:
# it is never eval'd, never used to construct a command, never branched on
# beyond the single equality check below. It is data, not dispatch -- the
# same distinction Decision 2's design already draws between "the box
# decides what runs" (true here, still) and "the caller decides what value
# is compared" (new, and exactly what an outcome-assertion needs to have
# ANY meaning). ⚠ THIS IS STILL A WIDENED TRUST SURFACE AND IS NAMED AS ONE:
# Sec joint-review is mandatory on the provision-vps.sh sshd_config change
# this depends on, same as any other change to ci-migrate's authorized_keys
# posture (C1/C3). This PR ships as DRAFT for exactly that reason — not to
# merge before Amendment 6 is ratified.
# ⚠ THIS SHA CHECK IS THE SUCCESS CRITERION for "the container about to run
# carries the migration set from the merged sha" -- Sec's exact wording
# requirement (Amendment 6 draft, Consequence 3): a deployment-status poll,
# if one is EVER added here, is a PRECONDITION ONLY (e.g. "don't even try
# until Coolify says the deploy finished") and its success is NEVER
# evidence the migration applied -- Decision 3 already ruled deployment
# status unreliable for exactly that purpose (it marks FINISHED before its
# post-deploy command's failure is known), and putting that same status in
# FRONT of this check would just bless a stale-image run one step earlier.
# If a future edit adds a deploy-status wait, it MUST be named
# "precondition" in the same comment that names THIS check "success
# criterion" -- the two roles are different and Sec's ruling is explicit
# that the distinction will drift if not stated together, every time.
# ⚠ CORRECTED per Sec's re-review of #790 @ 96db622c (sec-790-96db622c.md,
# 2026-09-17), Condition C-2: this used to SKIP the check when
# MIGRATOR_EXPECT_SHA was unset, reasoning that the workflow always sets
# it. Sec's measurement: $GITHUB_SHA IS always set inside the workflow, so
# the skip branch is UNREACHABLE from .github/workflows/migrator-trigger.yml
# -- but it IS reachable from a manual `ssh ci-migrate@box` fire with no
# `-o SetEnv=...` (exactly what §6.7's own recipe, and any operator
# emergency fire, does). "The fail-open path is the human one, which is the
# one most likely to be run in an emergency and least likely to be read
# carefully" (Sec, verbatim). There is NO skip branch any more, on ANY
# path, including this one: MIGRATOR_EXPECT_SHA is now REQUIRED, always,
# full stop.
if [[ -z "${MIGRATOR_EXPECT_SHA:-}" ]]; then
  log "FAIL (exit 4): MIGRATOR_EXPECT_SHA is not set. This check no longer skips when the variable is absent (Sec correction, 2026-09-17) -- every fire, workflow-triggered or a manual \`ssh ci-migrate@box\`, must supply it. Manual fire: \`ssh -o SetEnv=\"MIGRATOR_EXPECT_SHA=<40-hex-sha>\" ci-migrate@<box>\` (requires provision-vps.sh's AcceptEnv change to have landed). NOT executing the Scheduled Task."
  exit 4
fi
# 40-hex format validation -- DEFENCE-IN-DEPTH, not the primary control.
# Sec's original C-1 argued this was BLOCKING (an attacker-controlled string
# reaching a log line); measured on this path, MIGRATOR_EXPECT_SHA is always
# $GITHUB_SHA (40 hex, workflow_dispatch takes no inputs) so that harm does
# not exist TODAY -- Sec downgraded C-1 to defence-in-depth accordingly.
# Kept as a guard against a future workflow input or a mistyped/truncated
# manual SetEnv value, not because today's path can be attacker-steered.
if [[ ! "$MIGRATOR_EXPECT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  log "FAIL (exit 5): MIGRATOR_EXPECT_SHA ('$MIGRATOR_EXPECT_SHA') is not a well-formed 40-character hex git sha. Defence-in-depth check (Sec C-1, downgraded from blocking since \$GITHUB_SHA cannot currently be attacker-steered on this path) -- refusing rather than comparing against a malformed value. NOT executing the Scheduled Task."
  exit 5
fi
log "checking migrator container's baked sha against MIGRATOR_EXPECT_SHA (ADR-072 Amendment 6 draft)"
RUNNING_SHA="$(docker compose --project-name "$MIGRATOR_SERVICE_UUID" exec -T migrator cat /workspace/.build-sha 2>/dev/null || true)"
if [[ -z "$RUNNING_SHA" ]]; then
  log "FAIL (exit 3): could not read /workspace/.build-sha from the running migrator container — either the image predates this marker (rebuild needed) or the container is unreachable. Refusing to fire against an unverifiable image."
  exit 3
fi
if [[ "$RUNNING_SHA" != "$MIGRATOR_EXPECT_SHA" ]]; then
  log "FAIL (exit 3): migrator container's baked sha ($RUNNING_SHA) does NOT match the sha this run was triggered for ($MIGRATOR_EXPECT_SHA). The container has NOT been rebuilt since that commit merged -- this is exactly the defect the 2026-09-17 119 fire surfaced. Rebuild and redeploy the migrator image (Amendment 4 / this Amendment 6's Consequence 2) before re-firing. NOT executing the Scheduled Task."
  exit 3
fi
log "sha check OK: migrator container carries $RUNNING_SHA, matches the triggering commit"

log "executing migrator Scheduled Task ($MIGRATOR_TASK_UUID) on application $MIGRATOR_SERVICE_UUID"
# Item 15 fix (Sec-gated, booked BACKLOG.md §7.36 #15): the migrator
# Scheduled Task is attached to an APPLICATION resource (the Supabase-stack
# Coolify app, standup-log.md Phase A.2 — created via
# `POST /applications/{uuid}/scheduled-tasks`, i.e.
# ScheduledTasksController::create_scheduled_task_by_application_uuid), not
# a Service resource. Coolify 4.3.18's routes/api.php defines TWO separate
# route families for scheduled tasks, each bound to its own controller
# method and resource table: `/applications/{uuid}/scheduled-tasks/...`
# (execute -> execute_scheduled_task_by_application_uuid, executions ->
# executions_by_application_uuid) and `/services/{uuid}/scheduled-tasks/...`
# (its own distinct by_service_uuid methods). Addressing an
# application-attached task under `/services/` 404s — confirmed by reading
# routes/api.php directly (github.com/coollabsio/coolify, tag v4.3.18),
# not assumed. Corrected to the `/applications/` family below.
api POST "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/execute" >/dev/null \
  || fail "could not start the Scheduled Task (execute call itself failed — check the token's write ability and the UUIDs in $CONF_FILE)"

log "polling execution status (never Coolify's deployment status — ADR-072 Decision 3)"
STATUS=""
for _ in $(seq 1 "$POLL_MAX_ATTEMPTS"); do
  STATUS="$(api GET "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print((rows[0] or {}).get('status','') if rows else '')
")"
  [[ "$STATUS" != "running" && -n "$STATUS" ]] && break
  sleep "$POLL_INTERVAL_S"
done

case "$STATUS" in
  success)
    # DEPLOY_ON_SUCCESS gate (Sec-ruled, Phase D deploy-gate consult): the
    # first live exercise of this externally-reachable path (ci-migrate's
    # forced command, reachable from GitHub Actions, holding a
    # [read,write,deploy] token) should do the smallest thing it is capable
    # of — apply the migration and stop, not also fire a real production
    # deploy the first time this trigger is ever pulled for real. Read from
    # $CONF_FILE ONLY, never from $SSH_ORIGINAL_COMMAND or any argument (C2
    # — this key sits on the trusted side of that line: $CONF_FILE is
    # already root:ci-migrate 0640, ci-migrate-unwritable, sourced wholesale
    # as fully-trusted box-resident input; this is one more key in that same
    # file, not a new control, and needs no fence or watcher of its own.
    # Fail-closed by POSITIVE test (deliberately NOT the ":?" abort pattern
    # the other keys above use) — unset, unreadable, "0", or any other value
    # withholds the deploy rather than aborting a migration that already
    # succeeded.
    if [[ "${DEPLOY_ON_SUCCESS:-0}" == "1" ]]; then
      log "migration apply SUCCEEDED — triggering app deploy (uuid $APP_UUID)"
      api GET "/deploy?uuid=$APP_UUID" >/dev/null \
        || fail "migration succeeded but the app-deploy call itself failed — check the token's deploy ability. THE DB IS MIGRATED; the app was NOT redeployed. Investigate and redeploy manually before assuming this is a full failure."
      log "app deploy triggered"
    else
      # A suppressed deploy is a SUCCESS, not a failure — exit 0 so the
      # GitHub Actions job is green. Exiting non-zero here would invert
      # ADR-072 Decision 3's meaning: a red job would then mean "worked as
      # configured", exactly the signal-degradation D3 exists to prevent.
      log "migration apply SUCCEEDED — app deploy SUPPRESSED (DEPLOY_ON_SUCCESS!=1)"
    fi
    ;;
  failed)
    fail "migration apply FAILED (Scheduled Task execution status=failed) — app deploy NOT triggered. Coolify->Discord Scheduled-Task-failure routing already fired; check the execution log in the Coolify dashboard for the migration error."
    ;;
  *)
    fail "gave up after $((POLL_MAX_ATTEMPTS * POLL_INTERVAL_S))s waiting for a terminal execution status (last seen: '${STATUS:-<empty>}') — app deploy NOT triggered. This is a poll-timeout, not a confirmed migration failure; check the Coolify dashboard directly before retriggering."
    ;;
esac
