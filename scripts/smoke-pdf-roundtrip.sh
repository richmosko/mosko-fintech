#!/usr/bin/env bash
#
# smoke-pdf-roundtrip.sh -- docs/deployment-runbook.md §10 "PDF render
# round-trips via the signed-JWT path": from a sibling `pfin-app`
# container, mint a real SD-20 short-lived HS256 JWT using THAT
# container's own `PDF_WORKER_SIGNING_KEY`, POST a small HTML document to
# the pdf-render worker's `/render` endpoint over the internal Docker
# network, and assert real PDF bytes come back. BACKLOG.md §7.36 item 68
# (W-3). DevOps-owned.
#
# WHY THIS MINTS ITS OWN JWT RATHER THAN CALLING api/src's renderClient.ts
#   There is no CLI entrypoint into the SvelteKit app's compiled server
#   bundle this script could invoke — `app` is a web server, not a
#   batch worker. Re-implementing the mint is the only way to exercise
#   the REAL network hop (app's container -> pdf-render:8080) without
#   inventing a debug route this repo does not otherwise need. The
#   implementation matches api/src/lib/server/pdf/renderClient.ts's
#   `mintRenderToken()` EXACTLY (verified against that file this PR):
#   HS256, claims `{ users_id, nonce, iat }`, signed with
#   `PDF_WORKER_SIGNING_KEY`. Built with Node's own `crypto` module only
#   (HMAC-SHA256 + base64url, the whole of a compact HS256 JWS) — no
#   dependency on `jose` being resolvable from an ad hoc `node -e`
#   context, which would be a real risk (module resolution depends on
#   the exec'd process's cwd inside the container, an assumption this
#   script has no reason to make).
#
#   The signing key crosses via the SAME mechanism
#   scripts/smoke-admission-endpoint.sh already established for
#   WORKER_ADMISSION_SHARED_SECRET: read from the SIBLING CONTAINER'S OWN
#   env (`process.env.PDF_WORKER_SIGNING_KEY`, pushed there by
#   scripts/push-production-secrets.sh) — never this script's own env,
#   never this script's own argv, never printed, never crosses back to
#   the operator's machine.
#
# WHAT THIS PROVES
#   The FULL real path: app's container -> DNS resolves `pdf-render` (the
#   CA-4-shaped network-attachment check, same property
#   scripts/smoke-admission-endpoint.sh's P1 leg proves for provider-sync)
#   -> the worker's own JWT verification (SD-20/RT-21, `iat` freshness,
#   HS256-only) -> a real headless-Chromium render -> PDF bytes returned.
#   A wrong/absent signing key would 401 here exactly as it would for the
#   real app; this script does not special-case that path.
#
# USAGE
#   BOX_IP=<box-ip> scripts/smoke-pdf-roundtrip.sh [--compose-service <name>]
#
#   SIBLING_APP_NAME (default pfin-app) is env-var-overridable.
#   --compose-service defaults to `app`.
#
# EXIT CODES
#   0  VERIFIED -- 200 response whose body starts with the PDF magic
#      bytes (%PDF)
#   1  REFUSED -- any other status, a body that does not start with
#      %PDF, the signing key absent from the sibling container's own
#      env, or ambiguous (>1) running container match
#   2  FAILED -- a precondition this smoke could not even attempt under
#      (box unreachable, resource/container not found)
#
# ORCHESTRATOR CONTRACT (BACKLOG.md §7.36 item 68 W-5's provision.sh will
# call this directly): non-interactive, no prompts, no `read`. Idempotent
# -- each run mints its own fresh, single-use JWT (a new nonce every
# time) and renders a fixed, harmless HTML string; no state is created or
# mutated on either side, safe to re-run any number of times. Every fact
# used (container id, signing key) is resolved LIVE from the sibling
# container's own env each run, never cached.

set -euo pipefail

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
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

step "Resolving '$SIBLING_APP_NAME'"
UUID_RE='^[a-z0-9]{20,32}$'
MATCH_MODE="name"
[[ "$SIBLING_APP_NAME" =~ $UUID_RE ]] && MATCH_MODE="uuid"
APP_QUERY_ENV="app_query=$(printf '%q' "$SIBLING_APP_NAME")"
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
[[ "$APP_UUID" =~ $UUID_RE ]] || die2 "could not resolve '$SIBLING_APP_NAME' to a uuid-shaped application id"
ok "resolved '$SIBLING_APP_NAME' -> $APP_UUID"

step "Finding the running container"
RUNNING_LIST="$(sshx "docker compose --project-name $APP_UUID ps -q $COMPOSE_SERVICE | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}{{\"\\t\"}}{{.Created}}' {} | awk -F'\t' '\$1==\"true\"{print \$2\"\t\"\$3}'")"
[[ -n "$RUNNING_LIST" ]] || die2 "no running container found for compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- is '$SIBLING_APP_NAME' deployed and healthy? (scripts/deploy-app.sh)"
RUNNING_COUNT="$(printf '%s\n' "$RUNNING_LIST" | grep -c .)"
[[ "$RUNNING_COUNT" -eq 1 ]] \
  || die "AMBIGUOUS: $RUNNING_COUNT running containers match compose service '$COMPOSE_SERVICE' under project '$APP_UUID' -- refusing to silently pick one. Matches:
$RUNNING_LIST
Investigate on the box (docker compose --project-name $APP_UUID ps -a) before trusting which one this smoke should target."
CONTAINER="$(awk -F'\t' '{print $1}' <<<"$RUNNING_LIST")"
ok "running container: $CONTAINER"

step "Minting a real SD-20 JWT and rendering a tiny HTML document via pdf-render"
# Mirrors api/src/lib/server/pdf/renderClient.ts's mintRenderToken() +
# renderReportHtml() exactly (HS256, claims {users_id, nonce, iat}, POST
# /render, Authorization: Bearer <token>, content-type text/html). The
# signing key is read from process.env.PDF_WORKER_SIGNING_KEY -- THIS
# CONTAINER'S OWN env, never this script's, never printed.
NODE_ONE_LINER='
const crypto = require("crypto");
const http = require("http");
function b64url(buf) {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const key = process.env.PDF_WORKER_SIGNING_KEY || "";
if (!key) { console.log("000 NO_SIGNING_KEY"); process.exit(0); }
const header = b64url(Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })));
const payload = b64url(Buffer.from(JSON.stringify({
  users_id: "00000000-0000-0000-0000-000000000000",
  nonce: crypto.randomUUID(),
  iat: Math.floor(Date.now() / 1000),
})));
const signingInput = header + "." + payload;
const sig = b64url(crypto.createHmac("sha256", key).update(signingInput).digest());
const jwt = signingInput + "." + sig;
const html = "<html><body>pdf-roundtrip smoke</body></html>";
const req = http.request(
  { host: "pdf-render", port: 8080, path: "/render", method: "POST",
    headers: { authorization: "Bearer " + jwt, "content-type": "text/html", "content-length": Buffer.byteLength(html) } },
  (res) => {
    const chunks = [];
    res.on("data", (d) => chunks.push(d));
    res.on("end", () => {
      const body = Buffer.concat(chunks);
      const magic = body.slice(0, 4).toString("latin1");
      console.log(res.statusCode + " " + (magic === "%PDF" ? "PDF_MAGIC_OK" : "PDF_MAGIC_MISSING") + " " + body.length);
    });
  }
);
req.on("error", () => console.log("000 CONN_ERROR 0"));
req.write(html);
req.end();
'
RESULT="$(sshx "docker exec $CONTAINER node -e $(printf '%q' "$NODE_ONE_LINER")")"
STATUS="$(awk '{print $1}' <<<"$RESULT")"
MAGIC="$(awk '{print $2}' <<<"$RESULT")"
BYTES="$(awk '{print $3}' <<<"$RESULT")"
info "HTTP $STATUS $MAGIC (${BYTES:-0} bytes)"

if [[ "$MAGIC" == "NO_SIGNING_KEY" ]]; then
  die "PDF_WORKER_SIGNING_KEY is absent from '$SIBLING_APP_NAME' ($CONTAINER)'s own env -- run scripts/push-production-secrets.sh --apply first."
fi
if [[ "$STATUS" != "200" ]]; then
  die "POST /render -> HTTP $STATUS (expected 200) -- either the signing key is wrong (a 401 from pdf-render's own auth check), the network attachment to pdf-render is missing (CA-4-shaped), or the worker itself failed to render. Investigate before treating this as a known-failure shape."
fi
if [[ "$MAGIC" != "PDF_MAGIC_OK" ]]; then
  die "POST /render -> HTTP 200 but the response body does not start with the PDF magic bytes (%PDF) -- a 200 with a non-PDF body is not a pass."
fi

ok "POST /render -> 200, $BYTES bytes, valid PDF magic"

step "Done"
info "a real HTML document round-tripped through the deployed pdf-render worker via the signed-JWT path and came back as PDF bytes."
exit 0
