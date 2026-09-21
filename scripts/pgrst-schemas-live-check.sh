#!/usr/bin/env bash
#
# pgrst-schemas-live-check.sh -- reads the RUNNING `rest` container's own
# PGRST_DB_SCHEMAS value (never the Coolify store) and validates it via
# scripts/ci/fence-pgrst-schemas-live.sh. Sec C-1, PR #854 review:
# coolify-env.sh's own preflight read is a `GET /applications/{uuid}/envs`
# call against the STORE -- PostgREST reads PGRST_DB_SCHEMAS from its
# environment at CONTAINER START, so a store-only read cannot observe
# what the running container is actually serving. Before this script
# existed, provision.sh's own live_done_pgrst_flip() read the store
# alone; on a store-correct-but-not-yet-redeployed box that reported
# VERIFIED while PostgREST kept serving the previous schema set --
# exactly backwards on the direction that matters (a NARROWED exposure
# that never actually took effect would still read "already flipped").
#
# This is the SAME mechanism coolify-env.sh's own header already
# documents as the correct `--post-check` shape for this exact value
# (scripts/coolify-env.sh:165-167) -- extracted into its own script so
# provision.sh's live_done_pgrst_flip() can call it BEFORE deciding
# whether to apply at all, not only after (`--post-check` only runs
# post-`--apply`, which is too late for a done-predicate). Never a
# second, divergent implementation of the grep-on-the-box-then-validate
# shape -- reuses fence-pgrst-schemas-live.sh's own exact-string,
# order-sensitive comparison verbatim.
#
# WHY THE GREP RUNS ON THE BOX, NOT AFTER THE SSH HOP: `docker compose
# exec -T rest env` dumps the WHOLE container environment, including
# PGRST_DB_URI and PGRST_JWT_SECRET -- filtering to the one non-secret
# PGRST_DB_SCHEMAS line INSIDE the remote command string (before it ever
# crosses the wire) is coolify-env.sh's own documented hygiene boundary
# (`scripts/coolify-env.sh:159-162`); this script does not repeat that
# rationale, it inherits the same shape.
#
# USAGE
#   scripts/pgrst-schemas-live-check.sh              # read-only, no --apply flag exists
#
#   BOX_IP is read from .env (script-written by provision-vps.sh --apply).
#
# EXIT CODES (mirrors scripts/ci/fence-pgrst-schemas-live.sh exactly --
# its own three-way split, not re-derived here)
#   0  the running container's PGRST_DB_SCHEMAS already equals the ruled
#      exact literal, in the ruled exact order.
#   1  the container carries PGRST_DB_SCHEMAS, but a different value.
#   2  a precondition this script could not even attempt under (box
#      unreachable, stack resource not found) OR the container's env
#      carries no PGRST_DB_SCHEMAS entry at all.

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
FENCE_SH="$REPO_ROOT/scripts/ci/fence-pgrst-schemas-live.sh"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 (read-only, no flags)" >&2; exit 2 ;;
  esac
done

[[ -x "$FENCE_SH" ]] || die2 "$FENCE_SH missing or not executable"

BOX_IP="$(grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$BOX_IP" ]] || die2 "BOX_IP absent/blank in $REPO_ROOT/.env -- run scripts/provision-vps.sh --apply first"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    cmd = ["curl", "-fsS", "-K", "-", "-X", method, f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config.encode(), capture_output=True, check=True)
    except subprocess.CalledProcessError as exc:
        die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.decode(errors='replace').strip()[:200]})")
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None
PY

step "Resolving '$STACK_APP_NAME'"
UUID_RE='^[a-z0-9]{20,32}$'
STACK_UUID="$(sshx "env stack_name=$(printf '%q' "$STACK_APP_NAME") bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$stack_name" <<'PYEOF'
$PY_API_HELPER
import sys
token, stack_name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == stack_name]
if len(matches) != 1:
    die(f"expected exactly one application named '{stack_name}', found {len(matches)}")
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ "$STACK_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$STACK_APP_NAME' to a uuid-shaped application id"
ok "resolved '$STACK_APP_NAME' -> $STACK_UUID"

step "Reading PGRST_DB_SCHEMAS from the RUNNING rest container (filtered on the box -- never the full env crosses the wire)"
LIVE_LINE="$(sshx "env STACK_UUID=\"$STACK_UUID\" bash -s" <<'REMOTE'
set -e
docker compose --project-name "$STACK_UUID" exec -T rest env </dev/null | grep '^PGRST_DB_SCHEMAS=' || true
REMOTE
)"

# `if ... ; then rc=0; else rc=$?; fi` deliberately, not a bare pipeline
# + `RC=$?` -- under this file's own `set -euo pipefail`, a non-zero exit
# from $FENCE_SH (exit 1 or 2, both real/expected outcomes here, not
# script bugs) would abort THIS SCRIPT at the pipeline itself, before
# RC=$? is ever reached (same class of bug this PR's own provision.sh
# and fence-heredoc-stdin-drain.sh fixes already had to correct).
if printf '%s\n' "$LIVE_LINE" | "$FENCE_SH"; then
  RC=0
else
  RC=$?
fi
if [[ $RC -eq 0 ]]; then
  ok "running rest container already serves the ruled PGRST_DB_SCHEMAS value"
else
  info "running rest container's PGRST_DB_SCHEMAS does not (yet) match -- see fence-pgrst-schemas-live.sh's own output above"
fi
exit $RC
