#!/usr/bin/env bash
#
# smoke-admission-endpoint.sh -- CA-2 (docs/deployment-runbook.md §10):
# post-deploy empirical proof that provider-sync's SELF-212 admission
# endpoint (`:8081`) is NOT externally reachable (the NEGATIVE control)
# while it IS reachable from a sibling container on the same Docker
# network (the POSITIVE control, doubling as the CA-4 network-attachment
# check). BACKLOG.md §7.36 item 68 (W-3). DevOps-owned.
#
# WHY BOTH CONTROLS, NOT JUST ONE
#   A negative-only smoke cannot distinguish "correctly private" from
#   "the app is simply down" -- §10's own CA-2 text names this exactly.
#   A positive-only smoke cannot distinguish "correctly private AND
#   internally reachable" from "accidentally public" (a positive result
#   reachable from EVERYWHERE proves nothing about exposure). Both
#   together are the actual claim: reachable from inside, unreachable
#   from outside.
#
# WHAT THIS PROVES, MECHANISM BY MECHANISM
#   NEGATIVE (must fail to connect -- "000"/refused, never a 2xx/4xx FROM
#   THE ADMISSION APP, which would mean it was reached):
#     N1 -- from THIS script's own machine (the operator's), a direct
#          HTTP request to the box's public IP on :8081.
#     N2 -- from the box HOST's own network namespace (SSH'd in, NOT
#          inside any container) -- `expose:`-only does not publish to
#          the host either, only to sibling containers on the SAME
#          custom bridge network; this leg proves that distinction
#          empirically rather than trusting the compose file's own
#          `expose:` vs `ports:` claim.
#     N3 -- provider-sync's own live Coolify `fqdn` field is empty --
#          no Domain was ever assigned (the RT-27 fence's own committed-
#          config lint cannot see a UI-added Domain; this is the
#          runtime check that closes that gap).
#   POSITIVE (must succeed, all three from INSIDE a sibling container --
#   `pfin-app`'s own running container, attached to the SAME Docker
#   network as provider-sync per each compose's own `external:` block):
#     P1 -- GET /healthz (unauthenticated liveness) -> 200. Proves DNS
#          resolution + basic reachability -- this IS the CA-4 network-
#          attachment check (§10's own text: "the positive control
#          passing IS the same-network-internal-DNS assertion").
#     P2 -- POST /admission/link-token with NO x-worker-admission-secret
#          header -> 401. Proves the auth gate exists and fails closed
#          on absence (not merely that SOME response came back).
#     P3 -- POST /admission/link-token WITH the header (read from the
#          SIBLING CONTAINER'S OWN env, process.env.
#          WORKER_ADMISSION_SHARED_SECRET -- same value pushed to both
#          `app` and `provider-sync` per docs/deployment-runbook.md §5 --
#          never read from this script's own environment, never crosses
#          the wire back to the operator, never printed) but an EMPTY
#          body -> 400 `invalid_request` (Zod schema rejection). Proves
#          auth SUCCEEDED (did not 401) and the request reached the
#          handler, WITHOUT invoking `deps.mintLinkToken` -- a real
#          Plaid call this smoke has no business triggering. Never calls
#          a route with real side effects.
#
# The secret crosses via the SAME 0600-seed-file mechanism this repo's
# other smokes use for a credential the box already holds where THIS
# probe needs it -- except here it never needs to cross SSH at all: it
# is already present in the sibling container's own process env (pushed
# there by scripts/push-production-secrets.sh), so P3's node one-liner
# reads it FROM THAT PROCESS'S OWN env, in-container, and never touches
# this script's own argv, this script's own env, or the wire back to the
# operator's machine.
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-admission-endpoint.sh [--compose-service <name>]
#
#   PROVIDER_SYNC_APP_NAME (default pfin-provider-sync) and
#   SIBLING_APP_NAME (default pfin-app) are env-var-overridable, same
#   discipline as MIGRATOR_APP_NAME in scripts/migrator-scheduled-task.sh.
#   --compose-service defaults to `app` (the sibling's own compose
#   service name, api/docker-compose.yaml) -- override only if the
#   sibling under test is a different resource.
#
# EXIT CODES
#   0  VERIFIED -- every negative check refused AND every positive check
#      matched its expected status (000/000/empty-fqdn, 200/401/400)
#   1  REFUSED -- a real finding: any negative check WAS reachable (an
#      exposure -- escalate, do not re-run and hope), any positive check
#      returned the wrong status, a Domain IS assigned, or ambiguous (>1)
#      running container match (Sec F4 discipline -- never silently pick
#      one)
#   2  FAILED -- a precondition this smoke could not even attempt under
#      (box unreachable, provider-sync/sibling resource not found, no
#      running container found for the compose service at all)
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 68 W-5's provision.sh will
# call this directly): non-interactive, no prompts, no `read`. Idempotent
# -- pure read/probe, no state mutation, safe to re-run any number of
# times with identical semantics. Every fact used is resolved LIVE from
# Coolify's API / the box / the sibling container's own env each run --
# nothing is cached or read from a prior invocation's own output.

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROVIDER_SYNC_APP_NAME="${PROVIDER_SYNC_APP_NAME:-pfin-provider-sync}"
SIBLING_APP_NAME="${SIBLING_APP_NAME:-pfin-app}"
COMPOSE_SERVICE="app"

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
die2() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 2; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-service) [[ $# -ge 2 ]] || die2 "--compose-service requires an argument"; COMPOSE_SERVICE="$2"; shift 2 ;;
    --*) die2 "unknown flag: $1" ;;
    *) die2 "unexpected argument: $1 (usage: $0 [--compose-service <name>])" ;;
  esac
done
[[ -n "$BOX_IP" ]] || die2 "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh / deploy-app.sh / coolify-env.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die2 "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die2 "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api() shape as every sibling script -- token on `curl -K -` (stdin
# config, never argv).
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

resolve_app() {
  # resolve_app <name> -- prints "<uuid>\n<fqdn>"
  local query="$1"
  local uuid_re='^[a-z0-9]{20,32}$'
  local mode="name"
  [[ "$query" =~ $uuid_re ]] && mode="uuid"
  local query_env
  query_env="app_query=$(printf '%q' "$query")"
  sshx "env $query_env bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$app_query" "$mode" <<'PYEOF'
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
print(a.get("fqdn") or "")
PYEOF
REMOTE
}

FAIL=0

step "Resolving '$PROVIDER_SYNC_APP_NAME'"
PS_RESOLVED="$(resolve_app "$PROVIDER_SYNC_APP_NAME")" || die2 "could not resolve '$PROVIDER_SYNC_APP_NAME'"
PS_FQDN="$(sed -n 2p <<<"$PS_RESOLVED")"
ok "resolved '$PROVIDER_SYNC_APP_NAME'"

step "N3 -- no Coolify Domain assigned to provider-sync"
if [[ -n "$PS_FQDN" ]]; then
  echo "FAIL: [N3] provider-sync carries a live fqdn ('$PS_FQDN') -- a Domain IS assigned. This is the exact silent-exposure regression RT-27/§10 fence -- escalate, do not re-run and hope." >&2
  FAIL=1
else
  ok "N3: no fqdn assigned to provider-sync"
fi

step "N1 -- unreachable from the operator's own machine"
N1_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$BOX_IP:8081/healthz" 2>/dev/null || echo "000")"
if [[ "$N1_CODE" == "000" ]]; then
  ok "N1: http://$BOX_IP:8081/healthz -> 000 (refused/unreachable, as expected)"
else
  echo "FAIL: [N1] http://$BOX_IP:8081/healthz -> HTTP $N1_CODE from the OPERATOR's own machine -- the admission port is externally reachable. This is a real exposure -- escalate immediately, do not re-run and hope." >&2
  FAIL=1
fi

step "N2 -- unreachable from the box HOST's own network namespace (not a container)"
N2_CODE="$(sshx "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8081/healthz 2>/dev/null || echo 000")"
if [[ "$N2_CODE" == "000" ]]; then
  ok "N2: box host -> http://127.0.0.1:8081/healthz -> 000 (refused, as expected -- expose:-only does not publish to the host namespace either)"
else
  echo "FAIL: [N2] box host -> http://127.0.0.1:8081/healthz -> HTTP $N2_CODE -- expose:-only should not publish to the host network namespace. Investigate the compose file / Docker network mode before treating this as anything but a real finding." >&2
  FAIL=1
fi

step "Resolving '$SIBLING_APP_NAME' and its running container"
SIBLING_RESOLVED="$(resolve_app "$SIBLING_APP_NAME")" || die2 "could not resolve '$SIBLING_APP_NAME'"
SIBLING_UUID="$(sed -n 1p <<<"$SIBLING_RESOLVED")"
ok "resolved '$SIBLING_APP_NAME' -> $SIBLING_UUID"

RUNNING_LIST="$(sshx "docker compose --project-name $SIBLING_UUID ps -q $COMPOSE_SERVICE | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
[[ -n "$RUNNING_LIST" ]] || die2 "no running container found for compose service '$COMPOSE_SERVICE' under project '$SIBLING_UUID' -- is '$SIBLING_APP_NAME' deployed and healthy? (scripts/deploy-app.sh)"
RUNNING_COUNT="$(printf '%s\n' "$RUNNING_LIST" | grep -c .)"
[[ "$RUNNING_COUNT" -eq 1 ]] \
  || die "AMBIGUOUS: $RUNNING_COUNT running containers match compose service '$COMPOSE_SERVICE' under project '$SIBLING_UUID' -- refusing to silently pick one. Matches:
$RUNNING_LIST
Investigate on the box (docker compose --project-name $SIBLING_UUID ps -a) before trusting which one this smoke should target."
CONTAINER="$(awk -F'\t' '{print $1}' <<<"$RUNNING_LIST")"
ok "running container: $CONTAINER"

step "P1/P2/P3 -- issuing the three admission-endpoint requests INSIDE '$SIBLING_APP_NAME'"
# One docker exec, three sequential requests -- the shared secret (P3) is
# read from process.env.WORKER_ADMISSION_SHARED_SECRET (this CONTAINER's
# own env, pushed by scripts/push-production-secrets.sh) and never leaves
# this process: not this script's own env, not argv on either host, not
# the wire back to the operator.
NODE_ONE_LINER='
const http = require("http");
function req(opts, body) {
  return new Promise((resolve) => {
    const r = http.request({ host: "provider-sync", port: 8081, ...opts }, (res) => {
      let b = "";
      res.on("data", (d) => (b += d));
      res.on("end", () => resolve(res.statusCode));
    });
    r.on("error", () => resolve("000"));
    if (body) r.write(body);
    r.end();
  });
}
(async () => {
  const healthz = await req({ path: "/healthz", method: "GET" });
  const noauth = await req({ path: "/admission/link-token", method: "POST", headers: { "content-type": "application/json" } }, "{}");
  const secret = process.env.WORKER_ADMISSION_SHARED_SECRET || "";
  const withauth = await req({ path: "/admission/link-token", method: "POST", headers: { "content-type": "application/json", "x-worker-admission-secret": secret } }, "{}");
  console.log(healthz + " " + noauth + " " + withauth + " " + (secret ? "SECRET_PRESENT" : "SECRET_ABSENT"));
})();
'
RESULT="$(sshx "docker exec $CONTAINER node -e $(printf '%q' "$NODE_ONE_LINER")")"
P1_CODE="$(awk '{print $1}' <<<"$RESULT")"
P2_CODE="$(awk '{print $2}' <<<"$RESULT")"
P3_CODE="$(awk '{print $3}' <<<"$RESULT")"
SECRET_STATE="$(awk '{print $4}' <<<"$RESULT")"
info "healthz=$P1_CODE noauth=$P2_CODE withauth=$P3_CODE secret=$SECRET_STATE"

if [[ "$SECRET_STATE" != "SECRET_PRESENT" ]]; then
  echo "FAIL: [precondition] WORKER_ADMISSION_SHARED_SECRET is absent from '$SIBLING_APP_NAME' ($CONTAINER)'s own env -- run scripts/push-production-secrets.sh --apply first. P3's expected-400 assertion below is not meaningful without it." >&2
  FAIL=1
fi

if [[ "$P1_CODE" == "200" ]]; then
  ok "P1: GET /healthz -> 200 (reachable from a sibling container -- CA-4 network attachment confirmed)"
else
  echo "FAIL: [P1] GET /healthz -> HTTP $P1_CODE from a sibling container, expected 200 -- either not attached to the same Docker network as provider-sync (CA-4), or provider-sync is down. Investigate before treating this as anything else." >&2
  FAIL=1
fi

if [[ "$P2_CODE" == "401" ]]; then
  ok "P2: POST /admission/link-token with NO secret header -> 401 (auth gate fails closed on absence)"
else
  echo "FAIL: [P2] POST /admission/link-token with NO secret header -> HTTP $P2_CODE, expected 401 -- the auth gate did not fail closed on an absent credential." >&2
  FAIL=1
fi

if [[ "$P3_CODE" == "400" ]]; then
  ok "P3: POST /admission/link-token WITH the secret header -> 400 invalid_request (auth succeeded, reached the handler, no real Plaid call triggered)"
else
  echo "FAIL: [P3] POST /admission/link-token WITH the secret header -> HTTP $P3_CODE, expected 400 -- either the secret is wrong (would 401, not what CA-2 tests) or the handler's own contract changed. Investigate before treating this as a pass or a known-failure shape." >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more CA-2 admission-endpoint checks did not behave as specified." >&2
  exit 1
fi

step "Done"
info "provider-sync's admission endpoint is unreachable from outside the private Docker network (operator machine + box host) and correctly reachable, auth-gated, from a sibling container on the same network."
exit 0
