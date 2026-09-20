#!/usr/bin/env bash
#
# worker-scheduled-task.sh — create (or assert-identical) a worker's
# native Coolify Scheduled Task, per the table below, and report its
# UUID. Table-driven generalisation of scripts/migrator-scheduled-task.sh
# across the two REAL recurring worker cron units this repo has ratified
# fields for (docs/deployment-runbook.md §7): `pfin-back-etl`'s
# monthly-report unit and `pfin-provider-sync`'s daily poll.
# BACKLOG.md §7.36 item 68 (W-3). DevOps-owned.
#
# UNLIKE migrator-scheduled-task.sh's own task (which ships `enabled:
# false`, deliberately inert, fired only by direct UUID dispatch from a
# GitHub Actions trigger -- ADR-072 Decision 2), BOTH tasks here are
# `enabled: true` -- real, self-firing recurring cron. That is their
# entire purpose (Pattern A, §7: "resident container + Coolify Scheduled
# Task").
#
# TASK TABLE (docs/deployment-runbook.md §7's own ratified fields; if this
# script and that runbook ever disagree, the runbook's own citation trail
# — the compose file comment, in each case — is canonical, and this table
# is the copy to fix, matching migrator-scheduled-task.sh's own
# "copy #N, not a new one" discipline)
#   pfin-back-etl-monthly-report
#     Application  pfin-back-etl
#     Container    pfin-back-etl-monthly-report  (workers/etl/docker-compose.yaml
#                    service name — the SAME image as the nightly unit,
#                    its own independently-deployed Coolify unit)
#     Command      python run_monthly_report.py  (workers/etl/docker-compose.yaml
#                    lines ~61-64; workers/etl/run_monthly_report.py's own
#                    docstring proposes the identical literal)
#     Frequency    0 6 1 * *  (06:00 UTC, 1st of the month — same file,
#                    same lines; known UTC-boundary residual, BACKLOG
#                    §7.34 item 3, not this script's to fix)
#     Enabled      true
#   pfin-provider-sync-daily-poll
#     Application  pfin-provider-sync
#     Container    provider-sync  (workers/provider-sync/docker-compose.yaml
#                    service name — the ONLY service in that compose file)
#     Command      node dist/cli/poll.js  (docs/deployment-runbook.md §7's
#                    "provider-sync daily poll" bullet, design memo §1)
#     Frequency    @daily  (same bullet — SimpleFIN flat-fee + Plaid
#                    bills per-Item/month, cadence ≈ cost-neutral)
#     Enabled      true
#
# WHAT THIS SCRIPT DOES (per invocation, one task at a time)
#   1. Refuse an unrecognised <task-name> before any network call.
#   2. Resolve the task's own Coolify APPLICATION by name.
#   3. If NO Scheduled Task with this name exists on that application:
#      with --apply, creates it with the table's fields; without --apply,
#      prints the plan and exits.
#   4. If one ALREADY exists: asserts it is IDENTICAL on `command` /
#      `container` / `frequency` / `enabled` (byte-exact on `command`,
#      same strip_ws — leading/trailing whitespace only — as
#      scripts/migrator-scheduled-task.sh's own comparison) — and REFUSES
#      to mutate a live, disagreeing resource. This script never PATCHes
#      an existing task.
#   5. Reads the task back after creation and compares byte-exact before
#      declaring success.
#
# No secret value or Coolify API token is ever placed in curl's own argv
# on either machine — same `-K -` stdin-token + temp-file-body pattern as
# scripts/coolify-env.sh / scripts/migrator-scheduled-task.sh. This
# script's own request bodies (task name/command/container/frequency)
# are none of them secrets.
#
# ⚠ Same residual scripts/migrator-scheduled-task.sh's own header names
# and does not claim to close (BACKLOG.md §7.36 item 25, widened at PR
# #846 N-6 to name db-role-handoff.sh's own two call sites — this script
# is a THIRD, not independently re-flagged here to avoid a fourth stale
# copy of the same finding): the box-side `python3 - "$TOKEN"`
# invocations put the token in that process's own argv, `ps`-visible on
# the box for the call's lifetime.
#
# USAGE
#   BOX_IP=<box-ip> scripts/worker-scheduled-task.sh <task-name>            # preflight
#   BOX_IP=<box-ip> scripts/worker-scheduled-task.sh <task-name> --apply    # create
#
#   <task-name> is one of: pfin-back-etl-monthly-report,
#   pfin-provider-sync-daily-poll. Any other value is refused before any
#   SSH/API call is made.
#
# EXIT CODES
#   0  clean run (preflight, or --apply that created/confirmed the task)
#   1  a real failure: unresolvable application, a live task that
#      disagrees with this table (refuses to mutate it), a post-create
#      read-back mismatch
#   2  structural/usage error: unrecognised <task-name>, missing BOX_IP,
#      unreachable box

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

TASK_NAME="${1:-}"
APPLY=0
if [[ $# -ge 1 ]]; then shift; fi
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) die2 "unknown flag: $arg (usage: $0 <task-name> [--apply])" ;;
  esac
done

# --- Table: task-name -> application / container / command / frequency ---
# The ONLY per-task difference in this script's own logic. Refusing an
# unknown name here, before any SSH/API call, is deliberate (same
# discipline as scripts/provision-worker.sh's own resource-name table).
case "$TASK_NAME" in
  pfin-back-etl-monthly-report)
    APP_NAME="pfin-back-etl"
    TASK_CONTAINER="pfin-back-etl-monthly-report"
    TASK_COMMAND="python run_monthly_report.py"
    TASK_FREQUENCY="0 6 1 * *"
    ;;
  pfin-provider-sync-daily-poll)
    APP_NAME="pfin-provider-sync"
    TASK_CONTAINER="provider-sync"
    TASK_COMMAND="node dist/cli/poll.js"
    TASK_FREQUENCY="@daily"
    ;;
  "")
    echo "FATAL: missing <task-name> argument." >&2
    echo "usage: $0 <task-name> [--apply]" >&2
    echo "  <task-name> is one of: pfin-back-etl-monthly-report, pfin-provider-sync-daily-poll" >&2
    exit 2
    ;;
  *)
    echo "FATAL: unrecognised task-name '$TASK_NAME' -- refusing." >&2
    echo "  <task-name> is one of: pfin-back-etl-monthly-report, pfin-provider-sync-daily-poll" >&2
    exit 2
    ;;
esac

[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly, e.g. BOX_IP=188.245.166.206 for prod or BOX_IP=<scratch-ip> for a scratch box."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same hardened api() shape as scripts/migrator-scheduled-task.sh -- token
# on `curl -K -` (stdin config, never touches disk), request body (if
# any) via a 0600 temp file under /root/.pfin/ (unlinked in `finally`),
# read by `--data-binary @<path>`. Neither ever touches curl's own argv.
read -r -d '' PY_API_HELPER <<'PY' || true
import json, os, subprocess, sys, tempfile

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    body_path = None
    try:
        cmd = ["curl", "-fsS", "-K", "-", "-X", method]
        if body is not None:
            config += 'header = "Content-Type: application/json"\n'
            old_umask = os.umask(0o077)
            fd, body_path = tempfile.mkstemp(dir="/root/.pfin", prefix=".curlbody.")
            os.umask(old_umask)
            with os.fdopen(fd, "wb") as f:
                f.write(json.dumps(body).encode())
            cmd += ["--data-binary", f"@{body_path}"]
        cmd += [f"http://localhost:8000/api/v1{path}"]
        try:
            result = subprocess.run(cmd, input=config.encode(), capture_output=True, check=True)
        except subprocess.CalledProcessError as exc:
            die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    finally:
        if body_path is not None:
            try:
                os.unlink(body_path)
            except OSError:
                pass
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None

# Same strip_ws as scripts/migrator-scheduled-task.sh's own comparison:
# strip LEADING AND TRAILING space/tab/CR/LF only -- no internal-
# whitespace collapse, no quote handling.
import re
def strip_ws(s):
    return re.sub(r'^[ \t\r\n]+|[ \t\r\n]+$', '', s)
PY

step "Resolving '$APP_NAME'"
APP_UUID="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_NAME" <<'PYEOF'
$PY_API_HELPER
import sys
token, name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == name]
if len(matches) != 1:
    die(f"expected exactly one application named '{name}', found {len(matches)} -- run scripts/provision-worker.sh {name} --apply first if zero")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ -n "$APP_UUID" ]] || die "could not resolve '$APP_NAME' to a UUID"
UUID_RE='^[a-z0-9]{20,32}$'
[[ "$APP_UUID" =~ $UUID_RE ]] || die "resolved UUID '$APP_UUID' is not uuid-shaped -- refusing to interpolate API output into a remote shell"
ok "application '$APP_NAME' -> $APP_UUID"

# $TASK_COMMAND is a fixed literal from THIS script's own table (not
# operator/file input like migrator-scheduled-task.sh's file-read), but
# crosses via `env` on the ssh command line the same way regardless --
# consistent mechanism across both scripts, not a special case.
TASK_COMMAND_ENV="task_command=$(printf '%q' "$TASK_COMMAND")"

step "Checking for an existing '$TASK_NAME' Scheduled Task"
CHECK_OUT="$(sshx "env $TASK_COMMAND_ENV bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$TASK_NAME" "$TASK_CONTAINER" "\$task_command" "$TASK_FREQUENCY" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, name, container, command, frequency = sys.argv[1:7]
tasks = api(token, "GET", f"/applications/{app_uuid}/scheduled-tasks")
matches = [t for t in tasks if t.get("name") == name]
if not matches:
    print("ABSENT")
    sys.exit(0)
if len(matches) > 1:
    die(f"found {len(matches)} Scheduled Tasks named '{name}' -- ambiguous, refusing to guess which one is authoritative. Resolve by hand (Coolify dashboard) before re-running.")
t = matches[0]
mismatches = []
if strip_ws(str(t.get("command", ""))) != strip_ws(command):
    mismatches.append(f"command: live={t.get('command')!r} want={command!r}")
if t.get("container") != container:
    mismatches.append(f"container: live={t.get('container')!r} want={container!r}")
if strip_ws(str(t.get("frequency", ""))) != strip_ws(frequency):
    mismatches.append(f"frequency: live={t.get('frequency')!r} want={frequency!r}")
if t.get("enabled", False) != True:
    mismatches.append(f"enabled: live={t.get('enabled')!r} want=True")
if mismatches:
    print("MISMATCH")
    for m in mismatches:
        print("  " + m)
else:
    print("MATCH")
    print(t["uuid"])
PYEOF
REMOTE
)"

if [[ "$CHECK_OUT" == ABSENT ]]; then
  info "no existing '$TASK_NAME' task -- would create: container=$TASK_CONTAINER frequency='$TASK_FREQUENCY' enabled=true command='$TASK_COMMAND'"
  EXISTING_TASK_UUID=""
elif [[ "$CHECK_OUT" == MATCH* ]]; then
  EXISTING_TASK_UUID="$(printf '%s\n' "$CHECK_OUT" | tail -1)"
  ok "existing '$TASK_NAME' task ($EXISTING_TASK_UUID) already matches this script's table -- nothing to change"
else
  printf '%s\n' "$CHECK_OUT" >&2
  die "existing '$TASK_NAME' task disagrees with this script's table (see above) -- resolve by hand (Coolify dashboard), this script refuses to mutate a live, disagreeing Scheduled Task."
fi

if [[ -n "$EXISTING_TASK_UUID" ]]; then
  TASK_UUID="$EXISTING_TASK_UUID"
else
  if [[ $APPLY -eq 0 ]]; then
    printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing created. Re-run with --apply to create the task.\n'
    exit 0
  fi

  step "Creating '$TASK_NAME'"
  TASK_UUID="$(sshx "env $TASK_COMMAND_ENV bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$TASK_NAME" "$TASK_CONTAINER" "\$task_command" "$TASK_FREQUENCY" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, name, container, command, frequency = sys.argv[1:7]
created = api(token, "POST", f"/applications/{app_uuid}/scheduled-tasks", {
    "name": name,
    "command": command,
    "frequency": frequency,
    "container": container,
    "enabled": True,
})

# Read back and compare byte-exact (same comparison the preflight leg
# above uses) before declaring success -- do not trust the create
# response alone.
tasks = api(token, "GET", f"/applications/{app_uuid}/scheduled-tasks")
matches = [t for t in tasks if t.get("name") == name]
if len(matches) != 1:
    die(f"expected exactly one Scheduled Task named '{name}' after creation, found {len(matches)}")
t = matches[0]
if strip_ws(str(t.get("command", ""))) != strip_ws(command):
    die(f"post-create read-back MISMATCH on command: live={t.get('command')!r} want={command!r}")
if t.get("container") != container:
    die(f"post-create read-back MISMATCH on container: live={t.get('container')!r} want={container!r}")
if strip_ws(str(t.get("frequency", ""))) != strip_ws(frequency):
    die(f"post-create read-back MISMATCH on frequency: live={t.get('frequency')!r} want={frequency!r}")
if t.get("enabled", False) != True:
    die(f"post-create read-back MISMATCH on enabled: live={t.get('enabled')!r} want=True")
print(t["uuid"])
PYEOF
REMOTE
)"
  [[ -n "$TASK_UUID" ]] || die "task creation did not return a UUID"
  ok "created '$TASK_NAME' ($TASK_UUID), read-back verified byte-exact on command/container/frequency/enabled"
fi

step "Done"
info "Task '$TASK_NAME' ($TASK_UUID) on application '$APP_NAME' ($APP_UUID), command='$TASK_COMMAND', frequency='$TASK_FREQUENCY', enabled=true."
