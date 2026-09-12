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
COOLIFY_BASE="http://localhost:8000/api/v1"
POLL_INTERVAL_S=5
POLL_MAX_ATTEMPTS=120   # 120 * 5s = 10 minutes ceiling on the migration apply

log() { printf '[migrator-orchestrate] %s\n' "$*" >&2; }
fail() { log "FAIL: $*"; exit 1; }

[[ -r "$CONF_FILE" ]] || fail "missing or unreadable $CONF_FILE — provision-vps.sh must materialize this before the trigger is usable"
[[ -r "$TOKEN_FILE" ]] || fail "missing or unreadable $TOKEN_FILE — provision-vps.sh must mint the scoped migrator-trigger Coolify token before the trigger is usable"

# `set -a` so both files' KEY=value lines become exported vars for the rest
# of this script without a second parsing pass; both are box-resident,
# root-authored, never client input, so a plain source is safe here in a way
# it would NOT be for anything derived from $SSH_ORIGINAL_COMMAND (see the
# C2 note above — this is exactly the boundary that note draws).
set -a
# shellcheck source=/etc/pfin/migrator-trigger.conf
source "$CONF_FILE"
# shellcheck source=/etc/pfin/migrator-coolify-token.env
source "$TOKEN_FILE"
set +a

: "${MIGRATOR_SERVICE_UUID:?$CONF_FILE must set MIGRATOR_SERVICE_UUID}"
: "${MIGRATOR_TASK_UUID:?$CONF_FILE must set MIGRATOR_TASK_UUID}"
: "${APP_UUID:?$CONF_FILE must set APP_UUID}"
: "${COOLIFY_API_TOKEN:?$TOKEN_FILE must set COOLIFY_API_TOKEN}"

api() { # api <METHOD> <PATH>
  curl -fsS -X "$1" -H "Authorization: Bearer $COOLIFY_API_TOKEN" "$COOLIFY_BASE$2"
}
jqp() { python3 -c "import json,sys;$1"; }

log "executing migrator Scheduled Task ($MIGRATOR_TASK_UUID) on service $MIGRATOR_SERVICE_UUID"
api POST "/services/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/execute" >/dev/null \
  || fail "could not start the Scheduled Task (execute call itself failed — check the token's write ability and the UUIDs in $CONF_FILE)"

log "polling execution status (never Coolify's deployment status — ADR-072 Decision 3)"
STATUS=""
for _ in $(seq 1 "$POLL_MAX_ATTEMPTS"); do
  STATUS="$(api GET "/services/$MIGRATOR_SERVICE_UUID/scheduled-tasks/$MIGRATOR_TASK_UUID/executions" | jqp "
d=json.load(sys.stdin)
rows=d if isinstance(d, list) else d.get('data', d)
print((rows[0] or {}).get('status','') if rows else '')
")"
  [[ "$STATUS" != "running" && -n "$STATUS" ]] && break
  sleep "$POLL_INTERVAL_S"
done

case "$STATUS" in
  success)
    log "migration apply SUCCEEDED — triggering app deploy (uuid $APP_UUID)"
    api GET "/deploy?uuid=$APP_UUID" >/dev/null \
      || fail "migration succeeded but the app-deploy call itself failed — check the token's deploy ability. THE DB IS MIGRATED; the app was NOT redeployed. Investigate and redeploy manually before assuming this is a full failure."
    log "app deploy triggered"
    ;;
  failed)
    fail "migration apply FAILED (Scheduled Task execution status=failed) — app deploy NOT triggered. Coolify->Discord Scheduled-Task-failure routing already fired; check the execution log in the Coolify dashboard for the migration error."
    ;;
  *)
    fail "gave up after $((POLL_MAX_ATTEMPTS * POLL_INTERVAL_S))s waiting for a terminal execution status (last seen: '${STATUS:-<empty>}') — app deploy NOT triggered. This is a poll-timeout, not a confirmed migration failure; check the Coolify dashboard directly before retriggering."
    ;;
esac
