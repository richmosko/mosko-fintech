#!/usr/bin/env bash
#
# migrator-scheduled-task.sh — create (or assert-identical) the
# `migrator-db-push` Coolify Scheduled Task on the `pfin-migrator`
# application, per scripts/migrator-scheduled-task.md's own "Task fields"
# table, and record its UUID into the repo-root `.env`. DevOps-owned.
# Replaces the by-hand Coolify-UI creation
# docs/deployment-runbook.md §6.8 step 4 named -- F/CTO correction,
# 2026-09-19: every by-hand step with a scriptable API equivalent becomes
# one command.
#
# WHAT THIS DOES
#   1. Resolves the `pfin-migrator` application by NAME (same lookup
#      shape as scripts/record-coolify-uuids.sh's own MIGRATOR_APP_NAME).
#   2. Reads the task's `command` literal FROM scripts/provision-vps.sh's
#      own `MIGRATOR_TASK_COMMAND='...'` line, rather than hand-copying
#      it a fifth time -- migrator-scheduled-task.md's own "Amendment 8"
#      note already counts FOUR hand-maintained copies of this literal
#      (the task's Command row, infra/supabase/docker-compose.yml's
#      pointer comment, provision-vps.sh's own $CONF_FILE writer, and
#      Coolify's own stored task) and is explicit that a fifth would be
#      one too many; this script reads copy #3 (provision-vps.sh) rather
#      than adding a sixth.
#   3. If NO Scheduled Task named `migrator-db-push` exists on that
#      application: with --apply, creates it with the fields below;
#      without --apply, prints the plan and exits.
#   4. If a Scheduled Task named `migrator-db-push` ALREADY exists:
#      asserts it is IDENTICAL on `command` / `container` / `enabled`
#      (byte-exact on `command`, using the SAME strip_ws -- leading and
#      trailing space/tab/CR/LF only, nothing else -- as
#      scripts/migrator-orchestrate.sh's own pre-fire integrity check) --
#      and REFUSES to mutate a live, disagreeing resource, same posture
#      as scripts/provision-migrator-app.sh's own app-diff check. This
#      script never PATCHes an existing task; the fix for a genuine drift
#      is a decision for a human to make on purpose, not a silent
#      overwrite by this script.
#   5. Reads the task back after creation and compares `command`
#      byte-exact (same comparison shape as
#      scripts/migrator-orchestrate.sh's own pre-fire check) before
#      declaring success.
#   6. Writes/asserts `MIGRATOR_TASK_UUID` into the repo-root `.env`, same
#      REPO_ROOT-worktree-refusal guard and record_kv() shape as
#      scripts/record-coolify-uuids.sh (this script does NOT call that
#      one -- it already needs the task's uuid mid-flow to do the
#      read-back in step 5, so it writes .env directly rather than
#      shelling out to a second script for one key).
#
# TASK FIELDS (scripts/migrator-scheduled-task.md's own table; changing
# any of these belongs there first, per that file's own instruction)
#   Name       migrator-db-push
#   Container  migrator
#   Command    <read from provision-vps.sh's MIGRATOR_TASK_COMMAND>
#   Frequency  any syntactically valid cron (Coolify v4.3.18 rejects the
#              impossible-date trick; `0 0 1 1 *` used here) -- inertness
#              comes from `enabled: false`, not the expression.
#   Enabled    false (the automatic scheduler never fires it; the trigger
#              always addresses it directly by UUID -- ADR-072 Decision 2)
#
# No secret value or API token is ever placed in this script's own OR the
# box's on-box process argv -- same `-K <temp-config-file>` + stdin-body
# curl pattern as scripts/coolify-env.sh (BACKLOG.md §7.36 item 25's
# class). This script's own request bodies (task name/command/container)
# are none of them secrets, but the token itself always is.
#
# USAGE
#   BOX_IP=<box-ip> scripts/migrator-scheduled-task.sh            # preflight
#   BOX_IP=<box-ip> scripts/migrator-scheduled-task.sh --apply    # create

set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- .env lives at the main checkout root and would be silently discarded when this worktree is removed. Set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || GIT_COMMON_DIR=""
  if [[ -z "$GIT_COMMON_DIR" ]]; then
    printf '\n\033[31mFAIL\033[0m  could not resolve the repo root via git rev-parse --git-common-dir from %s. Set REPO_ROOT explicitly.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  REPO_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
fi

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
MIGRATOR_APP_NAME="${MIGRATOR_APP_NAME:-pfin-migrator}"
TASK_NAME="migrator-db-push"
TASK_CONTAINER="migrator"
TASK_FREQUENCY="0 0 1 1 *"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) die "unknown flag: $arg (usage: $0 [--apply])" ;;
  esac
done

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly, e.g. BOX_IP=188.245.166.206 for prod or BOX_IP=<scratch-ip> for a scratch box."

# --- Read the command literal from provision-vps.sh -- copy #3, not a --
#     new #5 (see header comment).
VPS_SCRIPT="$REPO_ROOT/scripts/provision-vps.sh"
[[ -f "$VPS_SCRIPT" ]] || die "$VPS_SCRIPT not found -- cannot read MIGRATOR_TASK_COMMAND"
TASK_COMMAND_LINE="$(grep -m1 "^MIGRATOR_TASK_COMMAND=" "$VPS_SCRIPT" || true)"
[[ -n "$TASK_COMMAND_LINE" ]] || die "no MIGRATOR_TASK_COMMAND= line found in $VPS_SCRIPT -- has it moved or been renamed? This script reads copy #3 of the literal from there rather than hand-maintaining a new one; update this script's read, not a hardcoded literal, if it moved."
# Strip the leading NAME= and one layer of single-quotes, e.g.
# MIGRATOR_TASK_COMMAND='sh /workspace/pfin-task.sh' -> sh /workspace/pfin-task.sh
TASK_COMMAND="${TASK_COMMAND_LINE#MIGRATOR_TASK_COMMAND=}"
TASK_COMMAND="${TASK_COMMAND#\'}"
TASK_COMMAND="${TASK_COMMAND%\'}"
[[ -n "$TASK_COMMAND" ]] || die "MIGRATOR_TASK_COMMAND resolved to an empty string after unquoting -- refusing to create a task with an empty command"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same hardened api() shape as scripts/coolify-env.sh -- token via a real
# on-disk `-K <tempfile>` (0600, unlinked in `finally`), request body (if
# any) via `--data-binary @-` fed through subprocess stdin. Neither ever
# touches this process's own argv.
read -r -d '' PY_API_HELPER <<'PY' || true
import json, os, subprocess, sys

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    cfg_path = f"/root/.pfin/.curlcfg.{os.getpid()}.{path.__hash__() & 0xffffff}"
    old_umask = os.umask(0o077)
    try:
        with open(cfg_path, "w") as f:
            f.write('header = "Authorization: Bearer ' + token + '"\n')
            if body is not None:
                f.write('header = "Content-Type: application/json"\n')
        cmd = ["curl", "-fsS", "-K", cfg_path, "-X", method]
        stdin_input = None
        if body is not None:
            cmd += ["--data-binary", "@-"]
            stdin_input = json.dumps(body).encode()
        cmd += [f"http://localhost:8000/api/v1{path}"]
        try:
            result = subprocess.run(cmd, input=stdin_input, capture_output=True, check=True)
        except subprocess.CalledProcessError as exc:
            die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    finally:
        os.umask(old_umask)
        try:
            os.unlink(cfg_path)
        except OSError:
            pass
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None

# Same strip_ws as scripts/migrator-orchestrate.sh's own pre-fire
# integrity check: strip LEADING AND TRAILING space/tab/CR/LF only --
# no internal-whitespace collapse, no quote handling. A genuine quoting
# mismatch must remain a real mismatch, not be normalized away.
import re
def strip_ws(s):
    return re.sub(r'^[ \t\r\n]+|[ \t\r\n]+$', '', s)
PY

step "Resolving '$MIGRATOR_APP_NAME'"
APP_UUID="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$MIGRATOR_APP_NAME" <<'PYEOF'
$PY_API_HELPER
import sys
token, name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == name]
if not matches:
    die(f"no application named '{name}' found -- run scripts/provision-migrator-app.sh --apply first")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ -n "$APP_UUID" ]] || die "could not resolve '$MIGRATOR_APP_NAME' to a UUID"
ok "application '$MIGRATOR_APP_NAME' -> $APP_UUID"

step "Checking for an existing '$TASK_NAME' Scheduled Task"
CHECK_OUT="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$TASK_NAME" "$TASK_CONTAINER" "$TASK_COMMAND" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, name, container, command = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
tasks = api(token, "GET", f"/applications/{app_uuid}/scheduled-tasks")
matches = [t for t in tasks if t.get("name") == name]
if not matches:
    print("ABSENT")
    sys.exit(0)
t = matches[0]
mismatches = []
if strip_ws(str(t.get("command", ""))) != strip_ws(command):
    mismatches.append(f"command: live={t.get('command')!r} want={command!r}")
if t.get("container") != container:
    mismatches.append(f"container: live={t.get('container')!r} want={container!r}")
if t.get("enabled", True) != False:
    mismatches.append(f"enabled: live={t.get('enabled')!r} want=False")
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
  info "no existing '$TASK_NAME' task -- would create: container=$TASK_CONTAINER frequency='$TASK_FREQUENCY' enabled=false command='$TASK_COMMAND'"
  EXISTING_TASK_UUID=""
elif [[ "$CHECK_OUT" == MATCH* ]]; then
  EXISTING_TASK_UUID="$(printf '%s\n' "$CHECK_OUT" | tail -1)"
  ok "existing '$TASK_NAME' task ($EXISTING_TASK_UUID) already matches this script's fields -- nothing to change"
else
  printf '%s\n' "$CHECK_OUT" >&2
  die "existing '$TASK_NAME' task disagrees with this script's fields (see above) -- resolve by hand (Coolify dashboard or scripts/coolify-env.sh-style API call), this script refuses to mutate a live, disagreeing Scheduled Task."
fi

if [[ -n "$EXISTING_TASK_UUID" ]]; then
  TASK_UUID="$EXISTING_TASK_UUID"
else
  if [[ $APPLY -eq 0 ]]; then
    printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing created. Re-run with --apply to create the task.\n'
    exit 0
  fi

  step "Creating '$TASK_NAME'"
  TASK_UUID="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$TASK_NAME" "$TASK_CONTAINER" "$TASK_COMMAND" "$TASK_FREQUENCY" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, name, container, command, frequency = sys.argv[1:7]
created = api(token, "POST", f"/applications/{app_uuid}/scheduled-tasks", {
    "name": name,
    "command": command,
    "frequency": frequency,
    "container": container,
    "enabled": False,
})

# Read back and compare command byte-exact (same strip_ws comparison as
# scripts/migrator-orchestrate.sh uses in its own pre-fire check) before
# declaring success -- do not trust the create response alone.
tasks = api(token, "GET", f"/applications/{app_uuid}/scheduled-tasks")
matches = [t for t in tasks if t.get("name") == name]
if not matches:
    die("task creation returned success but a re-list does not show it")
t = matches[0]
if strip_ws(str(t.get("command", ""))) != strip_ws(command):
    die(f"post-create read-back MISMATCH on command: live={t.get('command')!r} want={command!r}")
if t.get("enabled", True) != False:
    die(f"post-create read-back MISMATCH on enabled: live={t.get('enabled')!r} want=False")
print(t["uuid"])
PYEOF
REMOTE
)"
  [[ -n "$TASK_UUID" ]] || die "task creation did not return a UUID"
  ok "created '$TASK_NAME' ($TASK_UUID), read-back verified byte-exact on command"
fi

step "Recording MIGRATOR_TASK_UUID into .env"
[[ -f "$REPO_ROOT/.env" ]] || (umask 077; : > "$REPO_ROOT/.env")
# record_kv -- identical shape to scripts/record-coolify-uuids.sh's own
# helper (update-in-place if present, append if not; `sed -i ''`,
# BSD/macOS sed, no transient world-readable backup file).
if grep -q '^MIGRATOR_TASK_UUID=' "$REPO_ROOT/.env"; then
  sed -i '' "s|^MIGRATOR_TASK_UUID=.*|MIGRATOR_TASK_UUID=$TASK_UUID|" "$REPO_ROOT/.env"
else
  printf 'MIGRATOR_TASK_UUID=%s\n' "$TASK_UUID" >> "$REPO_ROOT/.env"
fi
chmod 600 "$REPO_ROOT/.env" 2>/dev/null || true
ok "recorded MIGRATOR_TASK_UUID=$TASK_UUID"

step "Done"
info "Task '$TASK_NAME' ($TASK_UUID) on application '$MIGRATOR_APP_NAME' ($APP_UUID). Next: scripts/record-coolify-uuids.sh --apply to (re)confirm MIGRATOR_SERVICE_UUID, then scripts/provision-vps.sh --apply to propagate into /etc/pfin/migrator-trigger.conf."
