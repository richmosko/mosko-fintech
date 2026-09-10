#!/usr/bin/env bash
#
# mint-supabase-jwt-keys.sh — replace the placeholder-random-hex ANON_KEY /
# SERVICE_ROLE_KEY minted by scripts/provision-supabase-stack.sh with REAL
# Supabase API keys: classic HS256 JWTs signed with the JWT_SECRET actually
# deployed on the box. Backend-owned. Sibling to provision-supabase-stack.sh,
# same house rules (no secret value ever leaves the box, --apply-gated,
# name-keyed idempotence).
#
# WHY THIS EXISTS
#   provision-supabase-stack.sh mints ANON_KEY/SERVICE_ROLE_KEY as
#   `secrets.token_hex(32)` -- 64 bytes of random hex, deliberately inert
#   (Sec: "safe-but-inert", fails closed, zero access, no RLS bypass) so the
#   stack can stand up before real keys exist. Random hex is NOT a JWT:
#   PostgREST (`rest`) and GoTrue (`auth`) both verify the `apikey` /
#   `Authorization: Bearer` value as an HS256-signed JWT against
#   PGRST_JWT_SECRET / GOTRUE_JWT_SECRET (= JWT_SECRET) -- a random hex
#   string has no valid signature over any header/payload, so PostgREST and
#   GoTrue reject it and the app cannot authenticate to Supabase at all.
#   This script mints the real thing and overwrites the placeholder.
#
# KEY MODEL -- verified against the tree, not assumed (2026-09-10)
#   This compose runs the CLASSIC HS256 model, not the newer asymmetric
#   publishable/secret-key family:
#     - rest:  PGRST_JWT_SECRET: ${JWT_JWKS:-${JWT_SECRET}} -- JWT_JWKS is
#       never set anywhere in this stack, so this always resolves to
#       JWT_SECRET (HS256, shared-secret verification).
#     - auth:  GOTRUE_JWT_SECRET: ${JWT_SECRET} directly. Same secret.
#     - api-gw (Envoy): infra/supabase/volumes/api/envoy/lds.template.yaml
#       does a Lua `TRANSLATION_ENABLED = SECRET_KEY ~= "" and
#       PUBLISHABLE_KEY ~= "" and SERVICE_ROLE_JWT ~= "" and ANON_JWT ~= ""`
#       gate around the ANON_KEY_ASYMMETRIC / SERVICE_ROLE_KEY_ASYMMETRIC /
#       SUPABASE_PUBLISHABLE_KEY / SUPABASE_SECRET_KEY family -- all four are
#       `${VAR:-}` (empty by default) in docker-compose.yml and nothing in
#       this repo ever sets them, so TRANSLATION_ENABLED is permanently
#       false and Envoy's apikey check is a plain `apikey == ANON_KEY` /
#       `apikey == SERVICE_ROLE_KEY` exact-string match against the classic
#       pair.
#     - secrets-manifest.yml (production_only, JWT_SECRET / ANON_KEY /
#       SERVICE_ROLE_KEY entries) states this explicitly: "unused while this
#       stack mints ANON_KEY/SERVICE_ROLE_KEY as classic JWTs instead" and
#       "ANON_KEY/SERVICE_ROLE_KEY pair ... are JWTs minted FROM this secret
#       [JWT_SECRET], not independent credentials."
#   App side agrees: api/src/hooks.server.ts reads PUBLIC_SUPABASE_ANON_KEY
#   into createServerClient() (the standard @supabase/ssr client, which
#   expects a classic anon-role JWT, not the newer publishable-key format);
#   api/src/lib/server/supabase-admin.ts reads SUPABASE_SERVICE_ROLE_KEY the
#   same way. secrets-manifest.yml ties the name pairs explicitly: stack-side
#   ANON_KEY == app-side PUBLIC_SUPABASE_ANON_KEY (same value, two names);
#   stack-side SERVICE_ROLE_KEY == app-side SUPABASE_SERVICE_ROLE_KEY (same
#   value, two names). No ambiguity between the two models -- this is a
#   "just decide" verified fact, not a judgment call presented as one.
#
# CLAIMS SHAPE
#   {"role": "anon" | "service_role", "iss": "supabase", "iat": <mint time>,
#   "exp": <mint time + 10 years>} -- the standard classic self-hosted
#   Supabase key shape (matches Supabase's own self-hosting docs example).
#   No `aud` claim: GOTRUE_JWT_AUD/GOTRUE_JWT_ADMIN_ROLES gate GoTrue's
#   validation of USER-issued session JWTs, not the anon/service_role API
#   keys themselves, and PostgREST's role-claim mapping does not consult
#   `aud`. 10-year expiry is a judgment call (matches upstream convention;
#   this repo has no stated rotation policy for these two keys) -- flagged
#   to F/CTO, not decided unilaterally as a security posture.
#
# WHAT IT REFUSES TO DO
#   No secret value (JWT_SECRET, the minted ANON_KEY/SERVICE_ROLE_KEY JWTs,
#   or the service_role JWT specifically) is ever printed, returned to this
#   script's local process, or written anywhere off the box. Every step that
#   touches secret material runs as ONE remote script over SSH that never
#   echoes a value -- only key names, claim shapes (role/iss/exp), and
#   true/false presence/verification results. JWT_SECRET is read FROM THE
#   BOX (/root/.pfin/supabase.env, written by provision-supabase-stack.sh)
#   on every run -- never cached locally, never accepted as a script
#   argument or env var from this side.
#
# WHAT IT OVERWRITES (the whole point -- read before running)
#   Unlike provision-supabase-stack.sh's mint-if-absent secrets, THIS script
#   unconditionally overwrites ANON_KEY / SERVICE_ROLE_KEY on the Supabase
#   stack Coolify resource, and PUBLIC_SUPABASE_ANON_KEY /
#   SUPABASE_SERVICE_ROLE_KEY on the `app` (V1 web-app) Coolify resource
#   when --app-name names one that exists. It also rewrites (not appends)
#   the ANON_KEY=/SERVICE_ROLE_KEY= lines in /root/.pfin/supabase.env so a
#   future `grep -m1` against that file reads the real value, not the first
#   (now-stale) placeholder line provision-supabase-stack.sh appended.
#
# IDEMPOTENCE
#   Re-running re-mints and re-overwrites both keys every time (signing is
#   deterministic modulo `iat`, so re-running without a JWT_SECRET rotation
#   produces functionally-equivalent tokens with a fresh iat/exp window).
#   Safe to run before the `app` Coolify resource exists (--app-name omitted
#   or not found: stack-side keys are set, app-side step is skipped with a
#   clear message) and safe to re-run once it does, to propagate the
#   app-side names.
#
# SCOPE
#   Only ANON_KEY / SERVICE_ROLE_KEY (stack) and PUBLIC_SUPABASE_ANON_KEY /
#   SUPABASE_SERVICE_ROLE_KEY (app). Does not touch JWT_SECRET itself, any
#   other secrets-manifest.yml entry, or DB roles/passwords.
#
# USAGE
#   scripts/mint-supabase-jwt-keys.sh                        # preflight only
#   scripts/mint-supabase-jwt-keys.sh --apply                # mint + overwrite
#   scripts/mint-supabase-jwt-keys.sh --apply --app-name NAME
#                                                   # also propagate app-side
#   scripts/mint-supabase-jwt-keys.sh --apply --verify-live
#                                     # + a real apikey call against api-gw
#                                     # (only meaningful once the stack is
#                                     # actually deployed and healthy)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_IP="${BOX_IP:-188.245.166.206}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
# Matches scripts/coolify-materialize-supabase-mounts.sh's documented
# default -- the pfin-supabase-stack production resource's known UUID.
STACK_APP_UUID="${COOLIFY_APP_UUID:-eepvlmaq4uortakmido7jgvn}"
APP_NAME=""
APPLY=0
VERIFY_LIVE=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --verify-live) VERIFY_LIVE=1 ;;
    --app-name=*) APP_NAME="${arg#--app-name=}" ;;
    --app-name) shift_next_is_name=1 ;;
    *)
      if [[ "${shift_next_is_name:-0}" == "1" ]]; then
        APP_NAME="$arg"
        shift_next_is_name=0
      else
        echo "unknown flag: $arg" >&2
        echo "usage: $0 [--apply] [--app-name NAME] [--verify-live]" >&2
        exit 2
      fi
      ;;
  esac
done

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"

sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

sshx 'grep -q "^JWT_SECRET=" /root/.pfin/supabase.env 2>/dev/null' \
  || die "no JWT_SECRET line in /root/.pfin/supabase.env -- run scripts/provision-supabase-stack.sh --apply first (it mints JWT_SECRET)"

step "Preflight -- current key shape on $STACK_APP_UUID (structure only, never a value)"
sshx_in <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "$STACK_APP_UUID" <<'PYEOF'
import json, subprocess, sys

token, app_uuid = sys.argv[1], sys.argv[2]

def api(method, path):
    cmd = ["curl", "-fsS", "-X", method, "-H", f"Authorization: Bearer {token}",
           f"http://localhost:8000/api/v1{path}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else None

envs = {e["key"]: e for e in api("GET", f"/applications/{app_uuid}/envs")}
for key in ("ANON_KEY", "SERVICE_ROLE_KEY"):
    if key not in envs:
        print(f"{key}: ABSENT")
        continue
    # v1 /envs listing never carries a value field -- structural facts only
    # (id/key/is_build_time/... presence), consistent with
    # provision-supabase-stack.sh's own documented assumption.
    print(f"{key}: present (value not inspectable via this endpoint -- decrypt check follows if --apply)")
PYEOF
REMOTE

if [[ -n "$APP_NAME" ]]; then
  step "Preflight -- looking up app resource '$APP_NAME'"
  APP_RESOURCE_UUID="$(sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1/applications" | python3 -c "
import json, sys
d = json.load(sys.stdin)
m = [a for a in d if a['name'] == '$APP_NAME']
print(m[0]['uuid'] if m else '')")"
  if [[ -n "$APP_RESOURCE_UUID" ]]; then
    ok "app resource '$APP_NAME' found -- $APP_RESOURCE_UUID"
  else
    info "app resource '$APP_NAME' not found -- app-side key propagation will be skipped this run"
  fi
else
  info "no --app-name given -- app-side (PUBLIC_SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY) propagation skipped. Re-run with --app-name once the V1 web-app Coolify resource exists (docs/deployment-runbook.md §6)."
fi

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing minted or overwritten. Re-run with --apply to execute.\n'
  exit 0
fi

step "Minting real HS256 JWTs from the deployed JWT_SECRET and overwriting the placeholders"
# One remote script, python3 on the box: reads JWT_SECRET (never leaves the
# box), mints ANON_KEY/SERVICE_ROLE_KEY as classic Supabase HS256 JWTs
# (stdlib hmac/hashlib/base64/json only -- no third-party JWT library added
# to this box's dependency surface), overwrites both on the stack app via
# envs/bulk (unconditional -- that is this script's entire purpose), and
# rewrites (not appends) the corresponding lines in supabase.env. Prints
# claim shapes and true/false verification results ONLY -- never a value.
sshx_in <<REMOTE
set -e
umask 077
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
JWT_SECRET="\$(grep -m1 '^JWT_SECRET=' /root/.pfin/supabase.env | cut -d= -f2-)"
STACK_APP_UUID="$STACK_APP_UUID"
APP_RESOURCE_UUID="${APP_RESOURCE_UUID:-}"

python3 - "\$TOKEN" "\$JWT_SECRET" "\$STACK_APP_UUID" "\$APP_RESOURCE_UUID" <<'PYEOF'
import base64, hashlib, hmac, json, subprocess, sys, time

token, jwt_secret, stack_uuid, app_uuid = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def api(method, path, body=None):
    cmd = ["curl", "-fsS", "-X", method, "-H", f"Authorization: Bearer {token}"]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else None

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def mint(role: str, secret: str, iat: int, years: int = 10) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {"role": role, "iss": "supabase", "iat": iat, "exp": iat + years * 365 * 24 * 3600}
    signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        b64url(json.dumps(payload, separators=(",", ":")).encode())
    sig = hmac.new(secret.encode(), signing_input.encode(), hashlib.sha256).digest()
    return signing_input + "." + b64url(sig)

if not jwt_secret:
    print("ERROR: JWT_SECRET read as empty -- refusing to mint", file=sys.stderr)
    sys.exit(1)

now = int(time.time())
anon_jwt = mint("anon", jwt_secret, now)
service_jwt = mint("service_role", jwt_secret, now)
print(f"minted: ANON_KEY (role=anon, iat={now}, exp={now + 10*365*24*3600}, dots={anon_jwt.count('.')})")
print(f"minted: SERVICE_ROLE_KEY (role=service_role, iat={now}, exp={now + 10*365*24*3600}, dots={service_jwt.count('.')})")

# Overwrite, unconditionally, on the stack app.
api("PATCH", f"/applications/{stack_uuid}/envs/bulk", {"data": [
    {"key": "ANON_KEY", "value": anon_jwt},
    {"key": "SERVICE_ROLE_KEY", "value": service_jwt},
]})
print(f"OVERWRITTEN on stack app {stack_uuid}: ANON_KEY, SERVICE_ROLE_KEY")

if app_uuid:
    api("PATCH", f"/applications/{app_uuid}/envs/bulk", {"data": [
        {"key": "PUBLIC_SUPABASE_ANON_KEY", "value": anon_jwt},
        {"key": "SUPABASE_SERVICE_ROLE_KEY", "value": service_jwt},
    ]})
    print(f"OVERWRITTEN on app resource {app_uuid}: PUBLIC_SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY")
else:
    print("SKIPPED app-side propagation -- no app resource UUID given/found this run")

# Rewrite (not append) supabase.env so grep -m1 reads the real value next
# time, not the stale placeholder line provision-supabase-stack.sh appended.
env_path = "/root/.pfin/supabase.env"
try:
    with open(env_path) as f:
        lines = [l for l in f if not l.startswith(("ANON_KEY=", "SERVICE_ROLE_KEY="))]
except FileNotFoundError:
    lines = []
lines.append(f"ANON_KEY={anon_jwt}\n")
lines.append(f"SERVICE_ROLE_KEY={service_jwt}\n")
with open(env_path, "w") as f:
    f.writelines(lines)
print(f"rewrote {env_path}: ANON_KEY/SERVICE_ROLE_KEY lines replaced (real values, on-box only)")
PYEOF
chmod 600 /root/.pfin/supabase.env 2>/dev/null || true

# Verify non-empty + JWT-shaped via Eloquent decryption (never ciphertext
# length, never the value) -- same pattern as provision-supabase-stack.sh's
# tinker --execute assertion step.
docker exec coolify php artisan tinker --execute="
\\\$app = \\App\\Models\\Application::where('uuid','$STACK_APP_UUID')->firstOrFail();
foreach (['ANON_KEY','SERVICE_ROLE_KEY'] as \\\$key) {
  \\\$env = \\\$app->environment_variables()->where('key', \\\$key)->first();
  \\\$val = \\\$env ? (string) \\\$env->value : '';
  \\\$shape = (substr_count(\\\$val, '.') === 2) ? 'JWT-shaped' : 'NOT-JWT-shaped';
  echo \\\$key . ': ' . (\\\$val !== '' ? \\\$shape : 'EMPTY') . PHP_EOL;
}
"
REMOTE

if [[ $VERIFY_LIVE -eq 1 ]]; then
  step "Live verification -- real apikey call against the running gateway"
  HEALTHY="$(sshx "docker ps --filter 'label=com.docker.compose.project=$STACK_APP_UUID' --filter 'health=healthy' --format '{{.Names}}'" | wc -l | tr -d ' ')"
  if [[ "$HEALTHY" -lt 3 ]]; then
    info "stack does not look deployed/healthy ($HEALTHY healthy containers) -- skipping live verify. Re-run with --verify-live once the stack is up."
  else
    # Runs entirely on the box: reads the just-set ANON_KEY back via the
    # SAME tinker decrypt path (never echoes it to this script's own
    # stdout beyond the remote shell -- it stays inside the SSH session),
    # then execs into `supavisor` (has curl per its own healthcheck; no new
    # image pulled, matching the verification battery's existing
    # `docker compose --project-name ... exec -T <service>` idiom) to hit
    # api-gw's internal service DNS name (`api-gw:8000`) with it as the
    # apikey header. 200/anything-but-401 means PostgREST verified the JWT
    # signature and mapped the role; 401 means the key still does not
    # authenticate. Container healthy is NOT sufficient evidence on its own
    # (the gap that hid the original random-hex-key defect) -- this is a
    # real authenticated call.
    sshx_in <<REMOTE2
set -e
ANON_KEY="\$(docker exec coolify php artisan tinker --execute="
\\\$app = \\App\\Models\\Application::where('uuid','$STACK_APP_UUID')->firstOrFail();
echo (string) \\\$app->environment_variables()->where('key','ANON_KEY')->first()->value;
" 2>/dev/null | tail -1)"
STATUS="\$(docker compose --project-name $STACK_APP_UUID exec -T supavisor curl -s -o /dev/null -w '%{http_code}' -H "apikey: \$ANON_KEY" -H "Authorization: Bearer \$ANON_KEY" http://api-gw:8000/rest/v1/)"
echo "PostgREST /rest/v1/ with minted ANON_KEY -> HTTP \$STATUS"
if [[ "\$STATUS" == "200" ]]; then
  echo "VERIFIED: gateway/PostgREST accepted the minted anon JWT"
else
  echo "NOT VERIFIED: expected 200, got \$STATUS -- investigate before relying on this key"
fi
REMOTE2
  fi
fi

step "Done"
info "Operator step once prod is up: scripts/mint-supabase-jwt-keys.sh --apply --app-name <the V1 web-app Coolify resource name> --verify-live"
info "Restart the affected containers (auth, rest, api-gw, and the app once it exists) after the env-var overwrite -- Coolify env changes require a redeploy/restart to take effect, this script does not trigger one."
