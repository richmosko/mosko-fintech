#!/usr/bin/env bash
#
# record-coolify-uuids.sh — read MIGRATOR_SERVICE_UUID / APP_UUID /
# MIGRATOR_TASK_UUID off the live Coolify API (by resource NAME, never
# hardcoded) and record them into the repo-root gitignored .env,
# idempotently. DevOps-owned. BACKLOG.md §7.36 item 33 ("the runbook must
# serve a stranger") — docs/deployment-runbook.md §6.4 step 3 already
# expects these three names in .env; before this script the only way to
# get them was to read them off the dashboard by hand or re-derive them
# from an agent's own prior API calls. This makes it one scripted step.
#
# Sibling to scripts/provision-vps.sh / provision-supabase-stack.sh — same
# preflight-by-default / --apply-to-write convention, same api()/sshx()
# shape (read the Coolify API token FROM THE BOX, never hold it locally).
#
# USAGE
#   BOX_IP=<box-ip> scripts/record-coolify-uuids.sh            # preflight: print, don't write
#   BOX_IP=<box-ip> scripts/record-coolify-uuids.sh --apply    # write to .env
#
# What it looks up, by NAME (never a stored/assumed UUID):
#   MIGRATOR_SERVICE_UUID — the Supabase-stack Coolify application (default
#     name "pfin-supabase-stack", matching provision-supabase-stack.sh's own
#     APP_NAME default) — migrator is a SIBLING SERVICE inside this one
#     application, not a standalone resource (see docs/deployment-runbook.md
#     §6's migrator Credential bullet).
#   APP_UUID — the V1 web-app Coolify application (default name "pfin-app").
#   MIGRATOR_TASK_UUID — the "migrator-db-push" Scheduled Task attached to
#     the Supabase-stack application (scripts/migrator-scheduled-task.md).
#
# Override the names this script searches for via env vars
# (SUPABASE_STACK_APP_NAME / WEB_APP_NAME / MIGRATOR_TASK_NAME) if a
# rebuild ever uses different resource names — never hardcode a second copy
# of this script's defaults elsewhere.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
SUPABASE_STACK_APP_NAME="${SUPABASE_STACK_APP_NAME:-pfin-supabase-stack}"
WEB_APP_NAME="${WEB_APP_NAME:-pfin-app}"
MIGRATOR_TASK_NAME="${MIGRATOR_TASK_NAME:-migrator-db-push}"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted — set it explicitly, e.g. BOX_IP=188.245.166.206 for prod. No default means no silent fall-through to prod."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first (its admin-bootstrap step writes this file)"

# api <METHOD> <PATH> -- reads the token FROM THE BOX on every call, never
# holds it in this script's own variables (same shape as
# provision-supabase-stack.sh's api()).
api() {
  local method="$1" path="$2"
  sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1$path"
}
jqp() { python3 -c "import json,sys;$1"; }

step "Looking up resource UUIDs by name"

MIGRATOR_SERVICE_UUID="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$SUPABASE_STACK_APP_NAME']
print(m[0]['uuid'] if m else '')")"
[[ -n "$MIGRATOR_SERVICE_UUID" ]] || die "no application named '$SUPABASE_STACK_APP_NAME' found -- run scripts/provision-supabase-stack.sh --apply first, or override SUPABASE_STACK_APP_NAME"
ok "MIGRATOR_SERVICE_UUID ($SUPABASE_STACK_APP_NAME) — $MIGRATOR_SERVICE_UUID"

APP_UUID="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$WEB_APP_NAME']
print(m[0]['uuid'] if m else '')")"
if [[ -n "$APP_UUID" ]]; then
  ok "APP_UUID ($WEB_APP_NAME) — $APP_UUID"
else
  info "no application named '$WEB_APP_NAME' found yet — leaving APP_UUID unset (create it per runbook §7.1 first, or override WEB_APP_NAME)"
fi

MIGRATOR_TASK_UUID=""
if [[ -n "$MIGRATOR_SERVICE_UUID" ]]; then
  MIGRATOR_TASK_UUID="$(api GET "/applications/$MIGRATOR_SERVICE_UUID/scheduled-tasks" | jqp "
d=json.load(sys.stdin)
m=[t for t in d if t['name']=='$MIGRATOR_TASK_NAME']
print(m[0]['uuid'] if m else '')")"
fi
if [[ -n "$MIGRATOR_TASK_UUID" ]]; then
  ok "MIGRATOR_TASK_UUID ($MIGRATOR_TASK_NAME) — $MIGRATOR_TASK_UUID"
else
  info "no Scheduled Task named '$MIGRATOR_TASK_NAME' found yet — leaving MIGRATOR_TASK_UUID unset (create it per scripts/migrator-scheduled-task.md first)"
fi

step "Recording into .env"

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing written. Re-run with --apply to record into .env.\n'
  exit 0
fi

[[ -f "$REPO_ROOT/.env" ]] || (umask 077; : > "$REPO_ROOT/.env")

# record_kv <KEY> <VALUE> -- update-in-place if the key exists, append if
# not; never touch any other line. Skips silently if VALUE is empty (a
# resource that doesn't exist yet shouldn't blank out a prior good value).
# File-mode discipline matches provision-supabase-stack.sh's own convention
# (umask 077 on create, chmod 600 after write) -- .env is the same
# gitignored file that holds local development secrets, so it should never
# be left world-readable, even though the three values THIS script writes
# are themselves non-secret. `sed -i ''` (BSD/macOS sed, this script
# family's target platform) edits in place with no separate backup file --
# unlike `sed -i.bak`, there is no transient world-readable copy to clean
# up.
record_kv() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || return 0
  if grep -q "^$key=" "$REPO_ROOT/.env"; then
    sed -i '' "s|^$key=.*|$key=$value|" "$REPO_ROOT/.env"
  else
    printf '%s=%s\n' "$key" "$value" >> "$REPO_ROOT/.env"
  fi
  chmod 600 "$REPO_ROOT/.env" 2>/dev/null || true
  ok "recorded $key"
}

record_kv MIGRATOR_SERVICE_UUID "$MIGRATOR_SERVICE_UUID"
record_kv APP_UUID "$APP_UUID"
record_kv MIGRATOR_TASK_UUID "$MIGRATOR_TASK_UUID"
