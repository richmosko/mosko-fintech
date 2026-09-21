#!/usr/bin/env bash
#
# resolve-stack-network.sh -- prints the Supabase-stack's own live Docker
# network name to stdout. team-lead's own live measurement, run 4
# (realrun4.log), 2026-09-21: provision.sh's run_deploy_app()/
# run_deploy_workers() passed `--require-network APP_STACK_NETWORK_NAME`
# (etc.) to deploy-app.sh -- the ENV-VAR NAME, as a literal string, not
# a resolved network value. deploy-app.sh's own `--require-network`
# compares its argument byte-for-byte against the deployed container's
# actual Docker network attachments (real values like
# `nz7mbexygw9lesjlazcxeltn`) -- a literal `APP_STACK_NETWORK_NAME` can
# never match one of those, so step 15 (deploy-app) FAILED on a
# genuinely-successful deploy: `NETWORK-ATTACHMENT CHECK FAILED:
# container ... is not attached to network 'APP_STACK_NETWORK_NAME'.
# Networks it IS attached to: 7frkiyqnetb4bgev7j7sw5eg
# nz7mbexygw9lesjlazcxeltn`. Also: `.env` defines no `*_STACK_NETWORK_NAME`
# name at all, so even `"${APP_STACK_NETWORK_NAME}"` would have expanded
# to empty, not fixed it.
#
# WHY A SEPARATE SCRIPT, NOT LOGIC INSIDE provision.sh -- provision.sh's
# own header states the orchestrator does not carry its own ssh/API
# logic (a prior TZ-1 decision, "duplicating the sshx() pattern every
# sibling script already carries in its OWN file, was judged worse").
# This is the SAME resolution scripts/provision-migrator-app.sh already
# performs correctly (for MIGRATOR_STACK_NETWORK_NAME) -- extracted here,
# not re-derived, so provision.sh can call it as an external script the
# same way it already calls pgrst-schemas-live-check.sh for a different
# read.
#
# MECHANISM (unchanged from provision-migrator-app.sh's own proven
# version, live-confirmed by run 4 resolving `nz7mbexygw9lesjlazcxeltn`
# correctly for MIGRATOR_STACK_NETWORK_NAME the same run that step 15
# used the wrong VALUE for the app's own network): resolve the named
# Coolify application, inspect the Docker network membership of its
# stack's own 'meta' container, and take the ONE non-default
# (not bridge/host/none) network name found. Coolify's own per-project
# network naming is not documented and is read here empirically -- if a
# stack ever has more than one custom network, or none, this refuses
# rather than guessing which one a deploy target should require.
#
# USAGE
#   scripts/resolve-stack-network.sh [--stack-app-name <name>]
#     (default: pfin-supabase-stack)
#
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#
# OUTPUT / EXIT CODES
#   stdout: the resolved network name, and NOTHING else, on exit 0.
#   1  REFUSED -- the stack app does not resolve, or its 'meta' container
#      does not show exactly one non-default network.
#   2  FAILED -- a precondition this script could not even attempt under
#      (box unreachable, no coolify.env on the box).

set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || GIT_COMMON_DIR=""
  if [[ -z "$GIT_COMMON_DIR" ]]; then
    printf '\n\033[31mFAIL\033[0m  could not resolve the repo root via git rev-parse --git-common-dir from %s (not inside a git checkout?). Set REPO_ROOT explicitly.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  REPO_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
fi

AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
STACK_APP_NAME="${STACK_APP_NAME:-pfin-supabase-stack}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
info() { printf '      %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-app-name) [[ $# -ge 2 ]] || die2 "--stack-app-name requires an argument"; STACK_APP_NAME="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; echo "usage: $0 [--stack-app-name <name>]" >&2; exit 2 ;;
  esac
done

BOX_IP="$(grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP absent/blank in $REPO_ROOT/.env -- run scripts/provision-vps.sh --apply first"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

api() {
  sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X GET -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1$1"
}
jqp() { python3 -c "import json,sys;$1"; }

STACK_APP_JSON="$(api /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$STACK_APP_NAME']
print(json.dumps(m[0]) if m else '')")"
[[ -n "$STACK_APP_JSON" ]] || die "no application named '$STACK_APP_NAME' -- run scripts/provision-supabase-stack.sh --apply first."
STACK_APP_UUID="$(echo "$STACK_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
info "resolved '$STACK_APP_NAME' -> $STACK_APP_UUID"

STACK_NETWORKS="$(sshx "docker inspect --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{println \$k}}{{end}}' \$(docker compose --project-name $STACK_APP_UUID ps -q meta)" 2>/dev/null | grep -Ev '^(bridge|host|none)$' || true)"
NETWORK_COUNT="$(echo "$STACK_NETWORKS" | grep -c . || true)"
if [[ "$NETWORK_COUNT" -ne 1 ]]; then
  die "expected exactly ONE non-default Docker network on '$STACK_APP_NAME's 'meta' container, found $NETWORK_COUNT: [$STACK_NETWORKS]. Refusing to guess which network a deploy target should require."
fi
printf '%s\n' "$STACK_NETWORKS"
