#!/usr/bin/env bash
#
# verify-worker-ca1-clear.sh -- die-level, post-deploy CA-1 container-env
# assertion. Sec ruling (PR #862 review, option C): provision-worker.sh's
# own done-predicate can only assert the API-level state (fqdn/
# ports_exposes cleared via the Coolify API/tinker write) -- it never
# deploys, so there is no guarantee a running container's OWN env
# reflects that clear (Coolify injects env only at container START).
# The authoritative check -- does the ACTUALLY RUNNING container still
# carry a CA-1 route signal -- belongs at the point a fresh container is
# guaranteed to exist: immediately after a real deploy. This script is
# that check, called from `provision.sh`'s `run_deploy_workers()`
# alongside item 10's own post-deploy store re-verify
# (`verify_worker_store_binds`).
#
# CONTAINER IDENTITY -- REWRITTEN (Sec, CA-1 identity review, run-9 stop
# 2026-09-21). The original version of this script took a bare
# <container-name> argument and looked it up with a literal `docker
# inspect <name>` -- run 9 measured that Coolify does NOT name the
# container after its compose service: the real name is
# `<service>-<uuid>-<timestamp>` (measured: `provider-sync-
# hmjeuhdaolhw8tlz3qi6lopi-194853542981`), so a caller passing the
# literal service name ('provider-sync') died "container not found" on a
# deploy that had actually succeeded. The offline strike fixture modeled
# the LITERAL name too, so this fence stayed green through the live bug
# -- fixture fidelity, again (this repo's own recurring "the fake
# restates the lie" failure class). Fixed by COPYING deploy-app.sh's
# WHOLE resolution mechanism verbatim, not re-deriving an independent
# one (Sec's explicit instruction) -- two stages:
#   1. NAME/UUID -> Coolify application uuid, via `GET /applications`
#      (exactly-one-match refusal, same as deploy-app.sh's own Step 1).
#   2. `docker compose --project-name <uuid> ps -q <service>` -> filter
#      to RUNNING via `docker inspect`, refuse on zero or on MORE THAN
#      ONE match (deploy-app.sh's own Sec F4 discipline, PR #833: "never
#      take the first of several") -- same Go-template `{{"\t"}}` STRING-
#      LITERAL ACTION escaping fix (D-1, PR #841) deploy-app.sh's own
#      header explains in full (a bare `\t` in the template's literal
#      text is NOT interpreted as a tab by `docker inspect`; only
#      `{{"\t"}}` is).
# ONLY THEN does this script run its own CA-1 env check against the
# container id that resolution produced.
#
# WHAT IT CHECKS -- `docker exec <container> env`, grepped ON THE BOX
# (inside the remote command, before the SSH hop -- same discipline as
# every other env-read in this repo) for `COOLIFY_FQDN=` / `COOLIFY_URL=`
# with a NON-EMPTY value. Either present-and-non-empty FAILS, naming
# CA-1 explicitly -- this is the exact signal
# `workers/provider-sync/src/http/admissionGuard.ts`'s own
# `detectPublicRouteSignal` reacts to; if THIS check passes, the
# guard's own refusal branch is structurally unreachable on this
# deploy.
#
# WHICH WORKERS -- this script itself takes whatever resource
# name/uuid + compose service its caller passes; it does not know or
# care which workers "have" an admission guard. That derivation lives
# in `provision.sh`'s `run_deploy_workers()` (a worker's OWN
# `docker-compose.yaml` declaring a `serve-admission.js` command
# override, checked structurally, never a hardcoded name list here or
# there) -- see that function's own header for the full rationale.
#
# USAGE
#   BOX_IP=<box-ip> scripts/verify-worker-ca1-clear.sh <resource-name|uuid> --service <compose-service>
#
# EXIT CODES
#   0  VERIFIED -- no non-empty COOLIFY_FQDN/COOLIFY_URL in the
#      container's own env.
#   1  FAILED -- a real finding: the container carries a non-empty
#      route signal. This IS a live-exposure state, not a soft warning
#      -- the caller must not treat this deploy as done.
#   2  FAILED -- a precondition this script could not even attempt
#      under (missing BOX_IP/--service, box unreachable, resource
#      resolution failure, container not found/ambiguous).

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

APP_QUERY="${1:-}"
[[ $# -gt 0 ]] && shift
COMPOSE_SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) [[ $# -ge 2 ]] || die2 "--service requires an argument"; COMPOSE_SERVICE="$2"; shift 2 ;;
    --*) die2 "unknown flag: $1" ;;
    *) die2 "unexpected argument: $1" ;;
  esac
done

[[ -n "$APP_QUERY" ]] || die2 "usage: $0 <resource-name-or-uuid> --service <compose-service> (BOX_IP env var required)"
[[ -n "$COMPOSE_SERVICE" ]] || die2 "--service is required -- this script resolves the running container via 'docker compose --project-name <uuid> ps -q <service>', the same mechanism deploy-app.sh uses; there is no default service name to guess at."
[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY."
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first."

# Same api() shape as deploy-app.sh -- token on `curl -K -` (stdin
# config, never argv); COPIED verbatim rather than re-derived, per Sec's
# instruction to copy deploy-app.sh's WHOLE resolution, not just its
# shape. See that script's header for the full #734/#735
# CalledProcessError-leak incident this convention exists to avoid.
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

# --- Stage 1: resolve <resource-name|uuid> -> application uuid -------------
step "Resolving '$APP_QUERY'"
UUID_RE='^[a-z0-9]{20,32}$'
if [[ "$APP_QUERY" =~ $UUID_RE ]]; then MATCH_MODE="uuid"; else MATCH_MODE="name"; fi
APP_QUERY_ENV="app_query=$(printf '%q' "$APP_QUERY")"
RESOLVED="$(sshx "env $APP_QUERY_ENV bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" "$MATCH_MODE" <<'PYEOF'
$PY_API_HELPER
import sys
token, query, mode = sys.argv[1], sys.argv[2], sys.argv[3]
apps = api(token, "GET", "/applications")
field = "uuid" if mode == "uuid" else "name"
matches = [a for a in apps if a.get(field) == query]
if len(matches) != 1:
    die(f"expected exactly one application matching {field}='{query}', found {len(matches)}")
a = matches[0]
print(a["uuid"])
PYEOF
REMOTE
)" || die2 "resolution of '$APP_QUERY' failed -- see the remote error above."
APP_UUID="$(sed -n 1p <<<"$RESOLVED")"
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$APP_QUERY' to a uuid-shaped application id."
ok "resolved '$APP_QUERY' -> $APP_UUID"

# --- Stage 2: application uuid + compose service -> the ONE running --------
# container. COPIED from deploy-app.sh's own compose-pack resolution
# (its header's "Two resolution mechanisms" section) -- identical
# Go-template escaping and identical exact-one-running refusal.
step "Resolving running container (compose service '$COMPOSE_SERVICE')"
RUNNING_LIST="$(sshx "docker compose --project-name $APP_UUID ps -q $COMPOSE_SERVICE | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
[[ -n "$RUNNING_LIST" ]] || die2 "no running container found for compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- check 'docker compose --project-name $APP_UUID ps -a' on the box before trusting this deploy."
RUNNING_COUNT="$(printf '%s\n' "$RUNNING_LIST" | grep -c .)"
[[ "$RUNNING_COUNT" -eq 1 ]] \
  || die2 "AMBIGUOUS: $RUNNING_COUNT running containers match compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- refusing to silently pick one (never 'the first of several'). Matches:
$RUNNING_LIST
Investigate on the box (docker compose --project-name $APP_UUID ps -a) before trusting which one is this deploy's."
CONTAINER="$(awk -F'\t' '{print $1}' <<<"$RUNNING_LIST")"
ok "resolved running container: $CONTAINER"

# --- Stage 3: the actual CA-1 check, against the RESOLVED container --------
step "CA-1 post-deploy container-env check ($CONTAINER)"
# Grepped ON THE BOX, inside the remote command -- never pull the whole
# env dump across the wire (same discipline every other env-read in
# this repo follows; COOLIFY_FQDN/URL are non-secret here, but the
# convention is the convention regardless of this call's own payload).
ROUTE_SIGNAL="$(sshx "docker exec $CONTAINER env | grep -E '^(COOLIFY_FQDN|COOLIFY_URL)=.' || true" </dev/null 2>/dev/null || true)"
if [[ -n "$ROUTE_SIGNAL" ]]; then
  die "CA-1 FINDING: container '$CONTAINER' (resolved from '$APP_QUERY', compose service '$COMPOSE_SERVICE') carries a non-empty Coolify route signal after deploy -- $(printf '%s' "$ROUTE_SIGNAL" | cut -d= -f1 | tr '\n' ' ')-- this is the exact signal admissionGuard.ts's detectPublicRouteSignal reacts to; if the guard did NOT refuse to boot on this deploy, investigate why immediately (a guard regression is worse than this finding). Do not treat this deploy as done."
fi
ok "container '$CONTAINER' carries no non-empty COOLIFY_FQDN/COOLIFY_URL -- CA-1 clear, post-deploy, confirmed on the running container."
exit 0
