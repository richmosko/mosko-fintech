#!/usr/bin/env bash
#
# smoke-pfin-exposure.sh -- BACKLOG.md §7.36 item 64's standing smoke: an
# authenticated GET against a `pfin` relation through the DEPLOYED app's
# OWN PostgREST path -- never a direct DB connection, never a curl issued
# from the operator's own machine straight at `api-gw` (that would prove
# the Data API is reachable from SOMEWHERE, not that the deployed app's
# own code path actually works). DevOps-owned. Used at
# docs/deployment-runbook.md §7.1 step 1(vi) (the pfin-app first-deploy
# procedure) and reused as §10's standing sub-check.
#
# MECHANISM
#   Resolves <APP_NAME|uuid> via the Coolify API (same api()/-K- shape as
#   scripts/deploy-app.sh), finds its RUNNING container on the box by
#   uuid-substring name match. This app is a plain-Dockerfile-pack
#   resource, not a `dockercompose` one -- there is no compose PROJECT to
#   address with `docker compose --project-name ... exec`, only a single
#   container, so `docker exec <container>` is the correct primitive
#   here (the same one scripts/deploy-app.sh's own on-box health read
#   already uses for this exact resource shape; `docker compose exec`
#   would simply fail against a Dockerfile-pack app -- no compose project
#   exists for it to address).
#   Then runs a `node -e` one-liner INSIDE that container issuing the
#   HTTP request to `api-gw:8000` -- proving the request crosses exactly
#   the path the app's own server code dials, from exactly where it runs.
#   The apikey ALWAYS crosses via the container's OWN env
#   (`process.env.PUBLIC_SUPABASE_ANON_KEY`) -- never the wire, never
#   this script's own argv, never printed.
#
# TWO MODES, TWO DIFFERENT EXPECTED OUTCOMES -- NOT interchangeable. A
# probe that accepts either outcome regardless of which credential was
# used would be vacuous in one direction (see WHY below) -- this script
# never does that.
#   Default (no --jwt): apikey AND Authorization both use the
#   container's own anon key (the pre-invite case -- Q5: signup off, no
#   user JWT exists yet). EXPECTED: 401 {"code":"42501",...} -- proves
#   `pfin` IS exposed (the request reached the schema, not a PGRST106
#   schema-not-exposed refusal) AND the B-1 anon-zero-grant fence holds
#   (docs/records/v1final/standup-log.md:695 -- this is the same shape,
#   already exercised live once). A 200 in THIS mode is NOT a success --
#   it would mean anon can read `pfin` -- and is treated as a FAILURE.
#   --jwt <user-jwt>: apikey stays the container's own anon key;
#   Authorization is OVERRIDDEN to the caller-supplied user JWT (crosses
#   via `docker exec -e`, never read from the container -- a real session
#   token is per-user, not baked into image env, and this script has no
#   way to mint one -- Q5 is invite-only). EXPECTED: 200 with a JSON
#   array (docs/deployment-runbook.md §6.9 step 6). A 401/42501 in THIS
#   mode means the JWT is invalid/expired, not that pfin is unexposed --
#   also a FAILURE for this mode, never silently accepted as the anon
#   mode's success.
#   ⚠ RESIDUAL, named not glossed: with --jwt, the token crosses via
#   `docker exec -e SMOKE_JWT_OVERRIDE=<jwt> ...`, which puts it in that
#   `docker` invocation's own argv, `ps`-visible on the box for the
#   call's lifetime -- same pre-existing class already tracked at
#   BACKLOG.md §7.36 item 60 for every sibling script's `python3 -
#   "$TOKEN"` pattern, not a new exposure this script introduces.
#
# OUTPUT
#   Prints the HTTP status and (if present) the response body's `code`
#   field ONLY -- never the full body (a real JWT's response could carry
#   actual tenant row data).
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-pfin-exposure.sh <APP_NAME|uuid> [--jwt <user-jwt>]
#
# EXIT CODES
#   0  the mode-appropriate expected outcome (401/42501 default,
#      200 with --jwt)
#   1  anything else: PGRST106 (schema not exposed), 3F000, a connection
#      failure, the wrong status/code for the mode in use, resource not
#      found, or an unreachable box/container.

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ $# -ge 1 ]] || die "usage: $0 <APP_NAME|uuid> [--jwt <user-jwt>]"
APP_QUERY="$1"; shift

USER_JWT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jwt) [[ $# -ge 2 ]] || die "--jwt requires an argument"; USER_JWT="$2"; shift 2 ;;
    --*) die "unknown flag: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done
[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh / coolify-env.sh / deploy-app.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api() shape as scripts/coolify-env.sh / scripts/deploy-app.sh --
# token on `curl -K -` (stdin config, never argv).
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

# --- Step 1: resolve the application (by name OR uuid) ----------------------
step "Resolving '$APP_QUERY'"
UUID_RE='^[a-z0-9]{20,32}$'
if [[ "$APP_QUERY" =~ $UUID_RE ]]; then MATCH_MODE="uuid"; else MATCH_MODE="name"; fi
APP_QUERY_ENV="app_query=$(printf '%q' "$APP_QUERY")"
APP_UUID="$(sshx "env $APP_QUERY_ENV bash -s" <<REMOTE
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
print(matches[0]["uuid"])
PYEOF
REMOTE
)"
[[ "$APP_UUID" =~ $UUID_RE ]] || die "could not resolve '$APP_QUERY' to a uuid-shaped application id"
ok "resolved '$APP_QUERY' -> $APP_UUID"

# --- Step 2: find the running container (plain-Dockerfile-pack -- no ------
#     compose project to address, `docker exec` by uuid-substring name
#     match, same primitive scripts/deploy-app.sh's own health read uses).
step "Finding the running container"
CONTAINER_NAME="$(sshx "docker ps --filter 'name=$APP_UUID' --filter 'status=running' --format '{{.Names}}' | head -1")"
[[ -n "$CONTAINER_NAME" ]] || die "no running container found matching '$APP_UUID' -- is the app deployed and healthy? (scripts/deploy-app.sh)"
ok "running container: $CONTAINER_NAME"

# --- Step 3: the smoke request, executed INSIDE the container --------------
step "Issuing the pfin-relation smoke request"
NODE_ONE_LINER='const k=process.env.PUBLIC_SUPABASE_ANON_KEY; const j=process.env.SMOKE_JWT_OVERRIDE||k; if(!k){console.error("NO_ANON_KEY");process.exit(2);} require("http").get({host:"api-gw",port:8000,path:"/rest/v1/user_settings?select=users_id&limit=1",headers:{apikey:k,Authorization:"Bearer "+j,"Accept-Profile":"pfin"}},r=>{let b="";r.on("data",d=>b+=d);r.on("end",()=>{let c="";try{c=JSON.parse(b).code||"";}catch(e){}console.log(r.statusCode+" "+c);});}).on("error",e=>{console.error("CONN_ERROR "+e.message);process.exit(2);});'

if [[ -n "$USER_JWT" ]]; then
  # Crosses via `docker exec -e`, never read from the container's own
  # env, never this script's own argv beyond this one exec call -- see
  # the header's named residual (ps-visible on the box for this call).
  RESULT="$(sshx "docker exec -e SMOKE_JWT_OVERRIDE=$(printf '%q' "$USER_JWT") $CONTAINER_NAME node -e $(printf '%q' "$NODE_ONE_LINER")")"
else
  RESULT="$(sshx "docker exec $CONTAINER_NAME node -e $(printf '%q' "$NODE_ONE_LINER")")"
fi

STATUS="$(awk '{print $1}' <<<"$RESULT")"
CODE="$(awk '{print $2}' <<<"$RESULT")"
info "HTTP $STATUS${CODE:+ code=$CODE}"

if [[ -n "$USER_JWT" ]]; then
  if [[ "$STATUS" == "200" ]]; then
    ok "post-invite JWT smoke: 200 -- pfin reachable via the deployed app's own PostgREST path"
    exit 0
  fi
  die "post-invite JWT smoke expected 200, got HTTP $STATUS${CODE:+ (code=$CODE)} -- either the JWT is invalid/expired, or pfin is not correctly exposed. Not evidence of the other cause without further investigation."
else
  if [[ "$STATUS" == "401" && "$CODE" == "42501" ]]; then
    ok "pre-invite anon smoke: 401/42501 -- pfin IS exposed (not PGRST106) and the anon-zero-grant fence holds"
    exit 0
  fi
  if [[ "$STATUS" == "406" || "$CODE" == "PGRST106" ]]; then
    die "pfin is NOT exposed via PostgREST (PGRST106) -- docs/deployment-runbook.md §6.9's flip has not run, or reverted."
  fi
  if [[ "$CODE" == "3F000" ]]; then
    die "schema 'pfin' does not exist yet (3F000) -- migrations have not applied to this database."
  fi
  if [[ "$STATUS" == "200" ]]; then
    die "SECURITY ANOMALY: anon-bearer request against pfin returned 200 -- the anon-zero-grant fence does NOT hold. This is not a pass in this mode; escalate to Sec immediately, do not re-run and hope."
  fi
  die "expected 401/42501 (pre-invite anon smoke), got HTTP $STATUS${CODE:+ (code=$CODE)} -- unexpected outcome, investigate before treating this as either pass or a known failure shape."
fi
