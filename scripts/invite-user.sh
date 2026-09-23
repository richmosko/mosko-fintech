#!/usr/bin/env bash
#
# invite-user.sh -- create the founding (and any subsequent) production
# auth account via GoTrue's admin invite endpoint. DevOps-owned.
#
# WHY THIS EXISTS
#   Production auth.users is 0|0|0 (total|confirmed|invited, measured
#   2026-09-23) and GOTRUE_DISABLE_SIGNUP is hardcoded "true" (see
#   infra/supabase/docker-compose.yml's auth service, F/CTO Q5) -- the
#   ONLY way to create a production account is GoTrue's service-role-
#   gated admin invite, per F/CTO's 2026-09-09 ruling
#   (docs/records/v1final/production-standup.md step 5a). Nothing in the
#   repo scripted that mechanism until now. The invite email is also the
#   FIRST real send this stack will ever make -- there is no existing
#   user to run a password-recovery round trip against, so this script's
#   own BY-HAND follow-up (see docs/deployment-runbook.md Part 3) IS the
#   ADR-074 verification round trip for a from-empty production stack.
#
# WHAT THIS DOES
#   Resolves BOTH the stack's `api-gw` container and the sibling `app`
#   container the same way scripts/smoke-remaining-checks.sh's own LEG 4
#   does: Coolify API resolve_app() (by name -> project uuid) +
#   find_running_container() (`docker compose --project-name <uuid> ps -q
#   <service>`, Sec F4 ambiguity discipline: refuses on 0 or >1 running
#   matches). NEVER by a fixed container name -- MEASURED live, real
#   production run 2026-09-23: Coolify ignores docker-compose.yml's own
#   `container_name:` directive entirely and names every stack container
#   `<service>-<project-uuid>-<timestamp>` instead (the compose file's
#   literal `container_name: supabase-envoy` never reaches the actual
#   container). Reads SERVICE_ROLE_KEY from the resolved `api-gw`
#   container via `docker inspect` FROM THE HOST -- no shell needed
#   inside that container. (Also measured live: SERVICE_ROLE_KEY is
#   present in the env of all seven stack containers, including `auth` --
#   `api-gw` is still the resolution target here because it is the
#   component that actually consumes this value for its own routing, not
#   because it is the only holder.) The key and the target email are
#   then piped, NUL-separated, into `docker exec -i <app-container> node
#   -e '<script>'`,
#   which POSTs http://api-gw:8000/auth/v1/invite (plain http -- this
#   never leaves the private stack network) with the key as both the
#   `apikey` and `Authorization: Bearer` headers and `{"email": ...}` as
#   the body. The key is read, used, and discarded entirely ON THE BOX:
#   never assigned to a local (operator-side) shell variable, never
#   printed, never on any process's own argv (same discipline as
#   scripts/smoke-remaining-checks.sh's own resend_probe()). Only the
#   resulting HTTP status is printed; on a non-2xx response, GoTrue's own
#   JSON error-message field is also printed (so a re-run against an
#   already-invited address doesn't read as ambiguous silence).
#
# WHAT THIS DOES NOT DO
#   Accepts NO key parameter and NO env-var override for the key --
#   SERVICE_ROLE_KEY is always read from the one `api-gw` container this
#   script itself resolves off the stack's own Coolify project, full
#   stop, so no wrong or stale key can ever be passed in by a caller
#   (Sec C2). Does not touch GoTrue's SMTP config, templates, or
#   SITE_URL (scripts/provision-supabase-stack.sh's job) -- this script
#   only ever calls the one already-provisioned /invite endpoint.
#
#   This is a privileged-context write surface (ADR-011 Decision 1):
#   operator-run, service-role-authenticated, joins
#   scripts/deploy-app.sh / scripts/push-production-secrets.sh /
#   scripts/mint-supabase-jwt-keys.sh / scripts/coolify-env.sh in that
#   registry -- no new registry entry, same class.
#
# USAGE
#   scripts/invite-user.sh <email>              # preflight only, exit 0
#   BOX_IP=<box-ip> scripts/invite-user.sh <email> --apply
#
#   Without --apply: validates the address is a single well-formed email
#   and nothing else -- no SSH, no box contact, no BOX_IP requirement.
#   Prints "would invite <address> on pfin-supabase-stack" and exits 0
#   (Sec C3 -- invite is the only account-creation path on production and
#   a typo creates a real account with no self-service removal, so the
#   default run must be inert).
#
#   With --apply: echoes the target address first (Sec C3, so the
#   operator sees exactly what is about to be invited before the network
#   call fires), then performs the resolve + invite. Same
#   STACK_APP_NAME/SIBLING_APP_NAME/COMPOSE_SERVICE env-var-override
#   convention as scripts/smoke-remaining-checks.sh (defaults:
#   pfin-supabase-stack / pfin-app / app).
#
# EXIT CODES
#   0  invite accepted (HTTP 2xx from GoTrue), or preflight-only run.
#   1  any failure: bad address, box/stack unreachable, key absent,
#      ambiguous/missing container, or a non-2xx response from GoTrue
#      (message printed alongside the status).

set -euo pipefail

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

APPLY=0
EMAIL=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -*) die "unknown flag: $arg -- usage: scripts/invite-user.sh <email> [--apply]" ;;
    *)
      [[ -z "$EMAIL" ]] || die "exactly one email address is accepted, got a second argument: '$arg'"
      EMAIL="$arg"
      ;;
  esac
done

[[ -n "$EMAIL" ]] || die "usage: scripts/invite-user.sh <email> [--apply]"

# Single well-formed address -- refuses anything comma/space-separated,
# any bare local-part, any missing TLD. Not a full RFC 5322 validator;
# this only needs to catch a typo before it becomes a real invite (Sec
# C3's own stated failure mode).
EMAIL_RE='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
[[ "$EMAIL" =~ $EMAIL_RE ]] || die "'$EMAIL' does not look like a single well-formed email address -- refusing (a typo here creates a real production account with no self-service removal)."

if [[ "$APPLY" -eq 0 ]]; then
  ok "would invite $EMAIL on pfin-supabase-stack (dry run -- pass --apply to send it)"
  exit 0
fi

info "target address: $EMAIL"

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
STACK_APP_NAME="${STACK_APP_NAME:-pfin-supabase-stack}"
SIBLING_APP_NAME="${SIBLING_APP_NAME:-pfin-app}"
COMPOSE_SERVICE="${COMPOSE_SERVICE:-app}"

[[ -n "$BOX_IP" ]] || die "BOX_IP is required with --apply, not defaulted -- same discipline as every other scripts/smoke-*.sh / provision-*.sh."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api()/-K- shape as every sibling script (resolve_app() in
# scripts/smoke-remaining-checks.sh) -- Coolify token on curl's stdin
# config, never argv.
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
  # resolve_app <name> -- prints "<uuid>". Same shape as
  # scripts/smoke-remaining-checks.sh's own resolve_app(), trimmed to the
  # one field this script needs.
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
print(matches[0]["uuid"])
PYEOF
REMOTE
}

find_running_container() {
  # find_running_container <project-uuid> <compose-service> -- prints the
  # container id, refuses on 0 or >1 running matches (Sec F4 discipline,
  # same as scripts/smoke-remaining-checks.sh).
  local uuid="$1" svc="$2"
  local list
  list="$(sshx "docker compose --project-name $uuid ps -q $svc | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}' {} | awk -F'\t' '\$1==\"true\"{print \$2}'")"
  [[ -n "$list" ]] || return 1
  local count
  count="$(printf '%s\n' "$list" | grep -c .)"
  [[ "$count" -eq 1 ]] || { echo "AMBIGUOUS: $count running containers match compose service '$svc' under project '$uuid'" >&2; return 2; }
  printf '%s' "$list"
}

step "Resolving '$STACK_APP_NAME' and '$SIBLING_APP_NAME'"
STACK_UUID="$(resolve_app "$STACK_APP_NAME")" || die "could not resolve '$STACK_APP_NAME'"
ok "resolved '$STACK_APP_NAME' -> $STACK_UUID"
API_GW_CID="$(find_running_container "$STACK_UUID" "api-gw")" \
  || die "could not find exactly one running 'api-gw' container under '$STACK_APP_NAME' ($STACK_UUID)"
ok "resolved running 'api-gw' container -> $API_GW_CID"
SIBLING_UUID="$(resolve_app "$SIBLING_APP_NAME")" || die "could not resolve '$SIBLING_APP_NAME'"
ok "resolved '$SIBLING_APP_NAME' -> $SIBLING_UUID"
SIBLING_CID="$(find_running_container "$SIBLING_UUID" "$COMPOSE_SERVICE")" \
  || die "could not find exactly one running '$COMPOSE_SERVICE' container under '$SIBLING_APP_NAME' ($SIBLING_UUID)"
ok "resolved running '$COMPOSE_SERVICE' container -> $SIBLING_CID"

step "Inviting $EMAIL"

# Everything from reading SERVICE_ROLE_KEY through the HTTP POST happens
# in ONE remote ssh session, mirroring resend_probe()'s own shape: the
# key is never assigned to a local shell variable, never printed, and
# never appears on any process's argv. Single-quoted heredoc --
# API_GW_CID, SIBLING_CID and EMAIL arrive via the `env VAR=val` prefix,
# not local interpolation. Both container ids were already resolved
# above via Coolify API + compose project/service (never a fixed
# container name -- see this file's own header for why).
INVITE_OUT="$(sshx "env API_GW_CID=\"$API_GW_CID\" SIBLING_CID=\"$SIBLING_CID\" TARGET_EMAIL=\"$EMAIL\" bash -s" <<'REMOTE'
set -e
if [[ -z "$API_GW_CID" ]] || ! docker inspect "$API_GW_CID" >/dev/null 2>&1; then
  # Defensive -- should be unreachable: the caller only invokes this
  # after find_running_container() already succeeded.
  echo "INVITE_ENVOY_CONTAINER_NOT_FOUND"
  exit 0
fi
KEY="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$API_GW_CID" | grep -m1 '^SERVICE_ROLE_KEY=' | cut -d= -f2-)"
if [[ -z "$KEY" ]]; then
  echo "INVITE_KEY_ABSENT"
  exit 0
fi
NODE_SCRIPT='
const http = require("http");
let stdin = "";
process.stdin.on("data", (c) => { stdin += c; });
process.stdin.on("end", () => {
  let payload;
  try { payload = JSON.parse(stdin); } catch (e) { console.log("INVITE_PAYLOAD_PARSE_ERROR"); return; }
  const body = JSON.stringify({ email: payload.email });
  const req = http.request({
    host: "api-gw", port: 8000, path: "/auth/v1/invite", method: "POST",
    headers: {
      "apikey": payload.key,
      "Authorization": "Bearer " + payload.key,
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(body)
    }
  }, (res) => {
    let out = "";
    res.on("data", (c) => { out += c; });
    res.on("end", () => {
      console.log("INVITE_STATUS_" + res.statusCode);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        let msg = out.slice(0, 500);
        try {
          const parsed = JSON.parse(out);
          msg = parsed.msg || parsed.message || parsed.error_description || parsed.error || msg;
        } catch (e) { /* keep raw slice */ }
        console.log("INVITE_MSG_" + msg);
      }
    });
  });
  req.on("error", () => console.log("INVITE_CONN_ERROR"));
  req.write(body);
  req.end();
});
'
printf '%s\0%s' "$KEY" "$TARGET_EMAIL" \
  | python3 -c 'import json,sys; parts = sys.stdin.buffer.read().split(b"\x00"); k = parts[0].decode(); e = parts[1].decode() if len(parts) > 1 else ""; print(json.dumps({"key": k, "email": e}))' \
  | docker exec -i "$SIBLING_CID" node -e "$NODE_SCRIPT"
REMOTE
)"

case "$(sed -n 1p <<<"$INVITE_OUT")" in
  INVITE_ENVOY_CONTAINER_NOT_FOUND)
    die "the resolved 'api-gw' container ($API_GW_CID) is no longer inspectable on the box -- it may have been replaced mid-run; re-run this script." ;;
  INVITE_KEY_ABSENT)
    die "SERVICE_ROLE_KEY is absent from the 'api-gw' container's own env -- run scripts/provision-supabase-stack.sh --apply / scripts/mint-supabase-jwt-keys.sh first." ;;
  INVITE_PAYLOAD_PARSE_ERROR)
    die "internal error building the invite payload -- this is a bug in this script, not a GoTrue/network failure." ;;
  INVITE_CONN_ERROR)
    die "could not reach http://api-gw:8000 from inside the '$COMPOSE_SERVICE' container -- is api-gw healthy and on the same network (CA-7)?" ;;
  INVITE_STATUS_2*)
    ok "GoTrue accepted the invite: $(sed -n 1p <<<"$INVITE_OUT")"
    info "open the invite email once it arrives -- the link must read https://\$SITE_URL_HOST/auth/confirm?token_hash=...&type=invite; a link containing /auth/v1/verify means the template fetch failed (stock fallback), not a successful invite."
    exit 0 ;;
  INVITE_STATUS_*)
    die "GoTrue rejected the invite: $(sed -n 1p <<<"$INVITE_OUT") -- $(sed -n 2p <<<"$INVITE_OUT" | sed 's/^INVITE_MSG_//')" ;;
  *)
    die "unexpected output from the remote invite call: $INVITE_OUT" ;;
esac
