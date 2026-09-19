#!/usr/bin/env bash
#
# migrator-cutover-verify.sh -- runs docs/deployment-runbook.md §6.8's
# three post-cutover proof measurements (steps 9/10/11) as one command,
# printing PASS/FAIL per leg. DevOps-owned. Read-only against the box
# except for leg 3's own connection attempt (which is EXPECTED to fail --
# that is the proof) -- this script mutates nothing.
#
# WHAT IT DOES NOT REPLACE
#   Step 7 (delete MIGRATOR_DB_* from the stack's store + redeploy) is
#   scripts/coolify-env.sh's job, and must have ALREADY run before this
#   script is meaningful -- this script only MEASURES the result, it does
#   not perform the delete. Step 8 (the delete-vs-blank .env grep) is a
#   one-off historical measurement (docs/deployment-runbook.md itself says
#   to record the count once and stop treating it as a standing unknown)
#   and is not repeated here.
#
# LEGS (docs/deployment-runbook.md §6.8 step numbers)
#   9  -- the NEW migrator container's own Config.Env carries
#         MIGRATOR_DB_USER/MIGRATOR_DB_PASSWORD and NONE of
#         POSTGRES_PASSWORD/JWT_SECRET/SERVICE_ROLE_KEY/VAULT_ENC_KEY/
#         ANON_KEY/SECRET_KEY_BASE. Same instrument as
#         scripts/provision-migrator-app.sh's own confinement check
#         (`docker inspect --format '{{range .Config.Env}}...'`), re-run
#         here post-redeploy rather than assumed to still hold.
#  10  -- the STACK's `meta` container has NEITHER MIGRATOR_DB_USER NOR
#         MIGRATOR_DB_PASSWORD in its own live env (`docker compose ...
#         exec -T meta env`) -- a blanked-not-deleted key still carries
#         its NAME and correctly fails this leg.
#  11  -- the OLD (retiring) MIGRATOR_DB_PASSWORD, read from
#         /root/.pfin/supabase.env (the last such line -- that file is
#         append-only), fails to authenticate as `migrator` from INSIDE
#         the new container. A non-empty-value guard is mandatory here:
#         an empty/absent old value would make this leg pass vacuously
#         (an empty password also produces "password authentication
#         failed").
#
# USAGE
#   BOX_IP=<box-ip> scripts/migrator-cutover-verify.sh \
#     --migrator-app <pfin-migrator NAME|uuid> --stack-app <pfin-supabase-stack NAME|uuid>
#
# Exit 0 only if all three legs PASS. Any leg FAIL (or a structural
# problem -- can't resolve a container, can't read the old credential)
# exits non-zero and names the failing leg.

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
MIGRATOR_APP=""
STACK_APP=""

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --migrator-app) MIGRATOR_APP="$2"; shift 2 ;;
    --stack-app) STACK_APP="$2"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done
[[ -n "$MIGRATOR_APP" ]] || die "usage: $0 --migrator-app <name|uuid> --stack-app <name|uuid>"
[[ -n "$STACK_APP" ]] || die "usage: $0 --migrator-app <name|uuid> --stack-app <name|uuid>"
[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

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
        cmd = ["curl", "-fsS", "-K", cfg_path, "-X", method, f"http://localhost:8000/api/v1{path}"]
        try:
            result = subprocess.run(cmd, capture_output=True, check=True)
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
PY

resolve_uuid() {
  local query="$1"
  if [[ "$query" =~ ^[a-z0-9]{20,32}$ ]]; then
    printf '%s' "$query"
    return 0
  fi
  sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$query" <<'PYEOF'
$PY_API_HELPER
import sys
token, name = sys.argv[1], sys.argv[2]
apps = api(token, "GET", "/applications")
matches = [a for a in apps if a.get("name") == name]
if not matches:
    die(f"no application named '{name}' found")
print(matches[0]["uuid"])
PYEOF
REMOTE
}

step "Resolving applications"
MIGRATOR_UUID="$(resolve_uuid "$MIGRATOR_APP")"
STACK_UUID="$(resolve_uuid "$STACK_APP")"
[[ -n "$MIGRATOR_UUID" ]] || die "could not resolve --migrator-app '$MIGRATOR_APP'"
[[ -n "$STACK_UUID" ]] || die "could not resolve --stack-app '$STACK_APP'"
ok "migrator app -> $MIGRATOR_UUID, stack app -> $STACK_UUID"

FAIL=0

# --- Leg 9 -----------------------------------------------------------------
step "Leg 9 -- new migrator container confinement (docker inspect Config.Env)"
LEG9_OUT="$(sshx "CID=\$(docker compose --project-name $MIGRATOR_UUID ps -q migrator); [ -n \"\$CID\" ] || { echo NOCONTAINER; exit 0; }; docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' \"\$CID\" | cut -d= -f1 | sort -u" 2>&1)" || true
if [[ "$LEG9_OUT" == "NOCONTAINER" || -z "$LEG9_OUT" ]]; then
  echo "FAIL: leg 9 -- could not find a running 'migrator' container under project $MIGRATOR_UUID" >&2
  FAIL=1
else
  LEG9_BAD=0
  for want in MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD; do
    printf '%s\n' "$LEG9_OUT" | grep -qx "$want" || { echo "FAIL: leg 9 -- new migrator container missing '$want'" >&2; LEG9_BAD=1; }
  done
  for offender in POSTGRES_PASSWORD JWT_SECRET SERVICE_ROLE_KEY VAULT_ENC_KEY ANON_KEY SECRET_KEY_BASE; do
    printf '%s\n' "$LEG9_OUT" | grep -qx "$offender" && { echo "FAIL: leg 9 -- new migrator container carries stack secret '$offender' (C7 confinement failure)" >&2; LEG9_BAD=1; }
  done
  if [[ $LEG9_BAD -eq 1 ]]; then FAIL=1; else ok "leg 9 PASS -- confinement holds"; fi
fi

# --- Leg 10 ------------------------------------------------------------------
step "Leg 10 -- stack's meta container carries neither MIGRATOR_DB_* name"
LEG10_OUT="$(sshx "docker compose --project-name $STACK_UUID exec -T meta env" 2>&1 | cut -d= -f1 | sort -u) || true"
LEG10_BAD=0
for offender in MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD; do
  printf '%s\n' "$LEG10_OUT" | grep -qx "$offender" && { echo "FAIL: leg 10 -- stack's meta container still carries '$offender' (blanked, not deleted? re-check §6.8 step 7)" >&2; LEG10_BAD=1; }
done
if [[ $LEG10_BAD -eq 1 ]]; then FAIL=1; else ok "leg 10 PASS -- both names absent from meta"; fi

# --- Leg 11 ------------------------------------------------------------------
step "Leg 11 -- OLD credential must fail to authenticate as 'migrator'"
LEG11_OUT="$(sshx_in <<REMOTE
set -e
OLDPW="\$(grep '^MIGRATOR_DB_PASSWORD=' /root/.pfin/supabase.env 2>/dev/null | tail -1 | cut -d= -f2-)"
if [ -z "\$OLDPW" ]; then
  echo "NOOLDVALUE"
  exit 0
fi
CID="\$(docker compose --project-name $MIGRATOR_UUID ps -q migrator)"
if [ -z "\$CID" ]; then
  echo "NOCONTAINER"
  exit 0
fi
printf '%s' "\$OLDPW" | docker exec -i "\$CID" sh -c '
  IFS= read -r OLDPW
  PGPASSWORD="\$OLDPW" psql "postgres://migrator@db:5432/postgres?sslmode=disable" -c "select 1" 2>&1 | tail -3'
unset OLDPW
REMOTE
)"
if [[ "$LEG11_OUT" == "NOOLDVALUE" ]]; then
  echo "FAIL: leg 11 -- no MIGRATOR_DB_PASSWORD found in /root/.pfin/supabase.env -- this proof would pass vacuously on an empty value, refusing to run it" >&2
  FAIL=1
elif [[ "$LEG11_OUT" == "NOCONTAINER" ]]; then
  echo "FAIL: leg 11 -- could not find a running 'migrator' container under project $MIGRATOR_UUID" >&2
  FAIL=1
elif printf '%s' "$LEG11_OUT" | grep -qi "password authentication failed"; then
  ok "leg 11 PASS -- old credential rejected (password authentication failed)"
else
  echo "FAIL: leg 11 -- expected a specific 'password authentication failed' rejection, got:" >&2
  printf '%s\n' "$LEG11_OUT" >&2
  echo "A connection-refused/timeout here means the network hop is broken, not that the credential failed for the right reason -- re-check leg 9/leg-6-equivalent connectivity before concluding the credential is retired." >&2
  FAIL=1
fi

step "Summary"
if [[ $FAIL -ne 0 ]]; then
  info "one or more legs FAILED -- see above. Not safe to consider the §6.8 cutover proven."
  exit 1
fi
info "all three legs PASS."
exit 0
