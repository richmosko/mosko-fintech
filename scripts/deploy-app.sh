#!/usr/bin/env bash
#
# deploy-app.sh -- thin, guarded redeploy vehicle for a single Coolify
# application: resolve by name/uuid, assert its identity (name +
# base_directory) against what the caller expects, POST /deploy, wait for
# a terminal state, then read back the resulting container's RUNNING
# state on the box. DevOps-owned.
#
# WHY THIS EXISTS
#   docs/deployment-runbook.md §7.1 step 1 needs a deploy step for
#   `pfin-app` (the V1 web-app's first-ever deploy) that is scriptable by
#   a stranger, not a Coolify-UI click (F/CTO, 2026-09-19, "this should be
#   a procedure that can be run by a stranger with minimal by-hand
#   intervention"). The deploy+poll shape already exists, proven, in
#   scripts/coolify-env.sh's own --deploy flag and in
#   scripts/provision-migrator-app.sh's deploy step -- this file does not
#   reinvent that shape, it extracts the SAME
#   POST /deploy?uuid=<uuid> + 90x4s poll idiom into a script whose ONLY
#   job is "deploy this ONE already-configured application, safely," with
#   an identity guard neither of those two scripts carries (they don't
#   need one -- coolify-env.sh only ever deploys the resource its own
#   preceding `set`/`delete` just touched and resolved, and
#   provision-migrator-app.sh only ever targets the one application it
#   just created/verified against its own file). A bare "deploy by name"
#   vehicle invoked by a stranger has no such preceding context, so it
#   asserts one itself: the resolved application's base_directory must
#   match what the caller passed, or it refuses. The failure mode this
#   guards against is a typo'd or stale APP_NAME resolving to the WRONG
#   Coolify application (e.g. a future `pfin-app-staging`) and firing a
#   real production deploy at it.
#
# WHAT THIS DOES NOT DO
#   Does not set/delete any env var (scripts/coolify-env.sh's job) and
#   does not create or configure a Coolify application
#   (scripts/provision-*.sh's job). Pure deploy-and-verify, generic across
#   any single-container Dockerfile-pack application, not `pfin-app`-
#   specific code -- the name/base_directory are caller-supplied, never
#   hardcoded here.
#
#   No secret value or Coolify API token is ever placed in curl's own
#   argv on either machine -- same `-K -` stdin-config-directive
#   convention as scripts/coolify-env.sh (see that script's own header
#   for the full incident citation this mirrors: the #734/#735
#   CalledProcessError-leak fix). ⚠ Same residual as coolify-env.sh's own
#   header names and does not claim to close: the box-side
#   `python3 - "$TOKEN"` invocation puts the token in THAT process's own
#   argv, `ps`-visible on the box for the call's lifetime (BACKLOG.md
#   §7.36 item 60).
#
# USAGE
#   BOX_IP=<box-ip> scripts/deploy-app.sh <APP_NAME|uuid> --expect-base-directory <dir> [--require-env NAME[,NAME...]] [--apply] [--health-path </path>]
#
#   Without --apply: preflight only -- resolves the app, prints its
#   current name/base_directory/fqdn, asserts the identity guard AND (if
#   given) the required-env-names guard below, writes nothing, deploys
#   nothing.
#   --require-env NAME[,NAME...]: a names-only presence check against the
#   resolved application's OWN Coolify env store (GET
#   /applications/<uuid>/envs, keys only -- no value is ever read,
#   printed, or compared) -- refuses (before any /deploy call, in BOTH
#   preflight and --apply) if any named key is absent. This is the guard
#   against deploying a container that will throw at its first request
#   for a missing required env var (docs/deployment-runbook.md §7.1 step
#   1 uses this for PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY /
#   SUPABASE_SERVICE_ROLE_KEY, run AFTER scripts/mint-supabase-jwt-keys.sh
#   has propagated the real anon/service-role values onto the app
#   resource) -- generic across any application, not app-specific code.
#   --apply: deploys for real (POST /deploy, wait for terminal state),
#   then reads back the resulting container's RUNNING state on the box.
#   --health-path <path>: after a successful deploy, also curl this path
#   against the application's OWN Coolify fqdn (read live from the API,
#   never hardcoded) from the OPERATOR's machine and print the HTTP
#   status -- best-effort and NOT fatal on a non-200 (a pre-DNS/no-TLS
#   sslip.io-style placeholder fqdn may not route yet; the on-box
#   container-running check above is this script's load-bearing
#   assertion, not this one).
#
# EXIT CODES
#   0  clean run (preflight or --apply)
#   1  a real failure (missing BOX_IP, unreachable box, resource not
#      found, identity-guard mismatch, a required env name absent,
#      deploy failed, no running container after a 'finished' deploy,
#      Coolify API error)

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[[ $# -ge 1 ]] || die "usage: $0 <APP_NAME|uuid> --expect-base-directory <dir> [--require-env NAME[,NAME...]] [--apply] [--health-path </path>]"
APP_QUERY="$1"; shift

EXPECT_BASE_DIR=""
REQUIRE_ENV_RAW=""
APPLY=0
HEALTH_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-base-directory) [[ $# -ge 2 ]] || die "--expect-base-directory requires an argument"; EXPECT_BASE_DIR="$2"; shift 2 ;;
    --require-env) [[ $# -ge 2 ]] || die "--require-env requires an argument"; REQUIRE_ENV_RAW="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --health-path) [[ $# -ge 2 ]] || die "--health-path requires an argument"; HEALTH_PATH="$2"; shift 2 ;;
    --*) die "unknown flag: $1" ;;
    *) die "unexpected argument: $1" ;;
  esac
done
[[ -n "$EXPECT_BASE_DIR" ]] || die "--expect-base-directory is required -- this is the identity guard this script exists to enforce, not an optional extra."
[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh / coolify-env.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api() shape as scripts/coolify-env.sh -- token on `curl -K -`
# (stdin config, never argv); see that script's header for the full
# incident citation (#734/#735 CalledProcessError-leak fix) this mirrors.
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

# --- Step 1: resolve the application (by name OR uuid) and read identity --
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
print(a.get("name") or "")
print(a.get("base_directory") or "")
print(a.get("fqdn") or "")
PYEOF
REMOTE
)"
APP_UUID="$(sed -n 1p <<<"$RESOLVED")"
APP_NAME_LIVE="$(sed -n 2p <<<"$RESOLVED")"
APP_BASE_DIR_LIVE="$(sed -n 3p <<<"$RESOLVED")"
APP_FQDN_LIVE="$(sed -n 4p <<<"$RESOLVED")"
[[ "$APP_UUID" =~ $UUID_RE ]] || die "could not resolve '$APP_QUERY' to a uuid-shaped application id"
ok "resolved '$APP_QUERY' -> $APP_UUID (name=$APP_NAME_LIVE, base_directory=$APP_BASE_DIR_LIVE)"

# --- Step 2: identity guard -------------------------------------------------
[[ "$APP_BASE_DIR_LIVE" == "$EXPECT_BASE_DIR" ]] \
  || die "IDENTITY GUARD FAILED: resolved application '$APP_NAME_LIVE' ($APP_UUID) has base_directory='$APP_BASE_DIR_LIVE', expected '$EXPECT_BASE_DIR' -- refusing to deploy a resource that does not match what the caller expects. This is the exact failure class this script exists to catch (a typo'd/stale name resolving to the wrong application)."
ok "identity guard passed: base_directory matches '$EXPECT_BASE_DIR'"

# --- Step 2.5: required-env-names guard (names only, no values read) -------
if [[ -n "$REQUIRE_ENV_RAW" ]]; then
  step "Required env-name presence check"
  REQUIRE_ENV_LIST="$(tr ',' ' ' <<<"$REQUIRE_ENV_RAW")"
  set +e
  ENV_CHECK_OUT="$(sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" "$REQUIRE_ENV_LIST" <<'PYEOF'
$PY_API_HELPER
import sys
token, app_uuid, required_s = sys.argv[1], sys.argv[2], sys.argv[3]
required = required_s.split()
envs = api(token, "GET", f"/applications/{app_uuid}/envs")
present = {e["key"] for e in envs if not e.get("is_preview", False)}
missing = [n for n in required if n not in present]
for n in required:
    print(f"{n}: {'PRESENT' if n not in missing else 'MISSING'}")
if missing:
    sys.exit(1)
PYEOF
REMOTE
)"
  ENV_CHECK_RC=$?
  set -e
  printf '%s\n' "$ENV_CHECK_OUT" | while IFS= read -r line; do info "$line"; done
  [[ $ENV_CHECK_RC -eq 0 ]] \
    || die "REQUIRED-ENV GUARD FAILED: one or more of [$REQUIRE_ENV_LIST] is absent from '$APP_NAME_LIVE' ($APP_UUID)'s env store -- refusing to deploy a container that will throw at its first request for a missing env var. Run whatever step is supposed to have set it (see the caller's own procedure) before retrying."
  ok "required env names present: $REQUIRE_ENV_LIST"
fi

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing deployed. Re-run with --apply to execute.\n'
  exit 0
fi

# --- Step 3: deploy + poll to terminal state --------------------------------
step "Deploying $APP_UUID"
sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$APP_UUID" <<'PYEOF'
$PY_API_HELPER
import sys, time
token, app_uuid = sys.argv[1], sys.argv[2]

d = api(token, "POST", f"/deploy?uuid={app_uuid}")
deployments = (d or {}).get("deployments") or [{}]
deploy_uuid = deployments[0].get("deployment_uuid", "")
if not deploy_uuid:
    die("deploy call did not return a deployment_uuid")
print(f"QUEUED: {deploy_uuid}")

# Same 90x4s ceiling as scripts/coolify-env.sh / provision-migrator-app.sh's
# own deploy waits -- polled server-side, inside this one SSH session,
# rather than 90 separate SSH round trips from the caller.
status = ""
for _ in range(90):
    dep = api(token, "GET", f"/deployments/{deploy_uuid}")
    status = (dep or {}).get("status", "")
    if status in ("finished", "failed"):
        break
    time.sleep(4)

if status != "finished":
    dep = api(token, "GET", f"/deployments/{deploy_uuid}") or {}
    raw = dep.get("logs") or "[]"
    import json as _json
    entries = _json.loads(raw) if isinstance(raw, str) else (raw or [])
    print("\n".join(e.get("output", "") for e in entries[-60:]), file=sys.stderr)
    die(f"deployment {deploy_uuid} status={status!r} -- see log above")

print("FINISHED")
PYEOF
REMOTE
ok "deploy finished"

# --- Step 4: on-box health read ---------------------------------------------
# ⚠ THIS IS A RUNNING-STATE READ, NOT A HEALTHCHECK READ -- api/Dockerfile
# carries no HEALTHCHECK directive, so Docker's own `.State.Health` is
# never populated for this container; filtering on `health=healthy` here
# would hang forever waiting for a signal this image never emits. RUNNING
# state is the honest predicate available on-box; --health-path below is
# the actual application-level check, best-effort because it depends on
# Coolify's Traefik routing (and, pre-DNS-cutover, a placeholder fqdn)
# rather than anything this container guarantees.
RUNNING="$(sshx "docker ps --filter 'name=$APP_UUID' --filter 'status=running' --format '{{.Names}}\t{{.Status}}'")"
[[ -n "$RUNNING" ]] || die "no running container found matching '$APP_UUID' after a 'finished' deploy -- check 'docker ps -a' on the box before trusting this deploy."
ok "running container: $RUNNING"

# --- Step 5: optional external health check ---------------------------------
if [[ -n "$HEALTH_PATH" ]]; then
  step "External health check (best-effort)"
  if [[ -z "$APP_FQDN_LIVE" ]]; then
    info "NOTE: application has no fqdn recorded -- skipping external health check."
  else
    # APP_FQDN_LIVE is Coolify API output (e.g. a pre-DNS-cutover
    # "http://<uuid>.<box-ip>.sslip.io" placeholder, or the real domain
    # post-cutover) -- may carry a trailing slash or not; a multi-value
    # comma-separated fqdn field takes the first entry.
    URL="$(cut -d, -f1 <<<"$APP_FQDN_LIVE")"
    URL="${URL%/}${HEALTH_PATH}"
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" || echo "000")"
    if [[ "$CODE" == "200" ]]; then
      ok "external health check: $URL -> 200"
    else
      info "NOTE: external health check $URL -> $CODE (not fatal here -- a pre-DNS/no-TLS placeholder fqdn may not route yet; the on-box container-running check above is this script's load-bearing assertion, not this one)."
    fi
  fi
fi

step "Done"
info "deployed $APP_UUID (base_directory=$EXPECT_BASE_DIR), container running$( [[ -n "$HEALTH_PATH" ]] && echo ", external health checked" )"
