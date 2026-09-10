#!/usr/bin/env bash
#
# provision-supabase-stack.sh — stand up the self-hosted Supabase Coolify
# resource end to end: create (or adopt) the project/environment/application,
# mint the secrets it needs, wire its env vars, materialize the compose's
# file-shaped bind mounts BEFORE the first deploy (so the empty-directory
# failure this stack hit on 2026-09-10 never happens again), deploy, and run
# the full verification battery. DevOps-owned. F/CTO directive 2026-09-10:
# the stand-up must be a scripted re-run, zero browser steps. Sibling to
# scripts/provision-vps.sh; run that one first.
#
# WHY THIS EXISTS
#   Every step this script performs was, on 2026-09-10, executed by hand over
#   SSH or the dashboard/API across several hours and two failed deploys. The
#   failures are now understood well enough to sequence around them instead
#   of hitting them and recovering:
#     - Coolify's compose parser creates `local_file_volumes` rows the moment
#       it PARSES the compose (LoadComposeFile::dispatch, fired at resource
#       creation when instant_deploy is NOT requested — source-verified in
#       app/Http/Controllers/Api/ApplicationsController.php, not assumed),
#       separately from and BEFORE any deploy. Materializing the real files
#       into those rows' host paths BEFORE the first deploy means the
#       first-deploy empty-directory failure this stack hit never happens.
#     - A `db-data` volume that ever initialized against those bogus empty
#       directories is permanently poisoned (Postgres runs
#       /docker-entrypoint-initdb.d/ exactly once). This script refuses to
#       deploy onto one rather than silently reproducing that incident.
#
# WHAT IT REFUSES TO DO
#   No secret value is ever printed, returned to this script's local process,
#   or written anywhere off the box. Every step that touches secret material
#   (minting, setting env vars, reading env vars back to assert they're
#   non-empty) runs as ONE remote script over SSH that never echoes a value —
#   only key names and true/false presence. The Coolify API token is read
#   FROM THE BOX on every call (/root/.pfin/coolify.env, written by
#   provision-vps.sh's admin-bootstrap step) — never from a local .env; that
#   file's COOLIFY_API_TOKEN entry (a hand-run-era artifact) can be deleted
#   once this script has run once. Nothing is created or mutated without
#   --apply; the default is a preflight that only reads.
#
# IDEMPOTENCE
#   Project/environment/application: looked up by NAME, adopted if present
#   and matching, refused (diff shown, script stops) if present and
#   DISAGREEING with this file, created only if absent. Secrets: minted only
#   for a key genuinely absent from the application's env (checked by
#   decrypting server-side and testing non-empty — never by ciphertext
#   length, which is meaningless: Laravel's `encrypted` cast produces a
#   non-trivial blob even for an empty string). Mounts: the materialize
#   script it calls is already idempotent. Deploy: refuses to redeploy onto
#   a poisoned `db-data` volume rather than silently reproducing 2026-09-10.
#
# SCOPE — READ BEFORE ASSUMING THIS REPLACES §5
#   This mints/sets exactly the Supabase-stack secrets named in
#   secrets-manifest.yml's production_only set (POSTGRES_PASSWORD,
#   JWT_SECRET, SECRET_KEY_BASE, VAULT_ENC_KEY, SERVICE_ROLE_KEY, ANON_KEY,
#   DASHBOARD_PASSWORD, PG_META_CRYPTO_KEY) plus the two non-secret Studio
#   vars (STUDIO_DEFAULT_ORGANIZATION, STUDIO_DEFAULT_PROJECT) — the set this
#   session's Studio/meta work actually needs. It is NOT §5's general
#   secrets-provisioning procedure (still a STUB, still Sec-gated) and does
#   not touch SMTP_*, the four app-service secrets, or anything outside this
#   one Coolify resource.
#
# WHAT THIS SCRIPT HAS NOT BEEN EXERCISED AGAINST
#   The project/environment/application CREATE path (all three already exist
#   in production, so every run against this box adopts them — the create
#   branch is researched against Coolify's own source, not proven against a
#   live instance). Say so if you hit it and it's wrong; don't assume it's
#   right because the rest of the script is.
#
# USAGE
#   scripts/provision-supabase-stack.sh              # preflight: read-only
#   scripts/provision-supabase-stack.sh --apply       # create/mint/deploy
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_IP="${BOX_IP:-188.245.166.206}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROJECT_NAME="${PROJECT_NAME:-pfin-supabase}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
APP_NAME="${APP_NAME:-pfin-supabase-stack}"
GIT_REPOSITORY="${GIT_REPOSITORY:-richmosko/mosko-fintech}"
GIT_BRANCH="${GIT_BRANCH:-main}"
BASE_DIRECTORY="/infra/supabase"
DOCKER_COMPOSE_LOCATION="/docker-compose.yml"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 [--apply]" >&2; exit 2 ;;
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
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first (its admin-bootstrap step writes this file)"

# api <METHOD> <PATH> [json-body] -- reads the token FROM THE BOX on every
# call, never holds it in this script's own variables. json-body, if given,
# must not contain a secret value -- see the dedicated remote script below
# for anything that does.
api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" -H 'Content-Type: application/json' -d '$body' http://localhost:8000/api/v1$path"
  else
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1$path"
  fi
}
jqp() { python3 -c "import json,sys;$1"; }

step "Preflight — project / environment / application (name-keyed lookup)"

PROJECT_JSON="$(api GET /projects | jqp "
d=json.load(sys.stdin)
m=[p for p in d if p['name']=='$PROJECT_NAME']
print(json.dumps(m[0]) if m else '')")"
if [[ -n "$PROJECT_JSON" ]]; then
  PROJECT_UUID="$(echo "$PROJECT_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "project '$PROJECT_NAME' exists — $PROJECT_UUID"
else
  info "project '$PROJECT_NAME' does not exist — would create"
fi

if [[ -n "${PROJECT_UUID:-}" ]]; then
  ENV_JSON="$(api GET "/projects/$PROJECT_UUID/environments" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['name']=='$ENVIRONMENT_NAME']
print(json.dumps(m[0]) if m else '')")"
  if [[ -n "$ENV_JSON" ]]; then
    ENV_UUID="$(echo "$ENV_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
    ok "environment '$ENVIRONMENT_NAME' exists — $ENV_UUID"
  else
    info "environment '$ENVIRONMENT_NAME' does not exist under project $PROJECT_UUID — would create"
  fi
fi

APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$APP_NAME']
print(json.dumps(m[0]) if m else '')")"
if [[ -n "$APP_JSON" ]]; then
  APP_UUID="$(echo "$APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  echo "$APP_JSON" | jqp "
d=json.load(sys.stdin)
mismatches=[]
want={'build_pack':'dockercompose','base_directory':'$BASE_DIRECTORY','docker_compose_location':'$DOCKER_COMPOSE_LOCATION','git_repository':'$GIT_REPOSITORY','git_branch':'$GIT_BRANCH'}
for k,v in want.items():
    if d.get(k)!=v: mismatches.append('%s: file wants %r, resource has %r'%(k,v,d.get(k)))
if mismatches:
    print('MISMATCH')
    for m in mismatches: print('  '+m)
else:
    print('MATCH')
" > /tmp/app-diff-check.$$
  if grep -q '^MISMATCH' /tmp/app-diff-check.$$; then
    cat /tmp/app-diff-check.$$ >&2
    rm -f /tmp/app-diff-check.$$
    die "application '$APP_NAME' exists but disagrees with this file — resolve by hand, refusing to mutate a live resource."
  fi
  rm -f /tmp/app-diff-check.$$
  ok "application '$APP_NAME' exists and matches this file's settings — $APP_UUID"
else
  [[ -n "${PROJECT_UUID:-}" && -n "${ENV_UUID:-}" ]] || info "project/environment must exist (or be created) before the application"
  info "application '$APP_NAME' does not exist — would create with build_pack=dockercompose, base_directory=$BASE_DIRECTORY, docker_compose_location=$DOCKER_COMPOSE_LOCATION, branch=$GIT_BRANCH"
fi

step "Plan"
cat <<PLAN
      project      $PROJECT_NAME  ${PROJECT_UUID:-<to be created>}
      environment   $ENVIRONMENT_NAME  ${ENV_UUID:-<to be created>}
      application   $APP_NAME  ${APP_UUID:-<to be created>}
      secrets       mint-if-absent: POSTGRES_PASSWORD JWT_SECRET SECRET_KEY_BASE
                     VAULT_ENC_KEY SERVICE_ROLE_KEY ANON_KEY DASHBOARD_PASSWORD
                     PG_META_CRYPTO_KEY
                     set-if-absent (non-secret): STUDIO_DEFAULT_ORGANIZATION
                     STUDIO_DEFAULT_PROJECT
PLAN

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created, minted, or deployed. Re-run with --apply to execute.\n'
  exit 0
fi

step "Applying — resource creation"

if [[ -z "${PROJECT_UUID:-}" ]]; then
  PROJECT_UUID="$(api POST /projects "{\"name\":\"$PROJECT_NAME\"}" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "project created — $PROJECT_UUID"
fi
if [[ -z "${ENV_UUID:-}" ]]; then
  ENV_UUID="$(api POST "/projects/$PROJECT_UUID/environments" "{\"name\":\"$ENVIRONMENT_NAME\"}" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "environment created — $ENV_UUID"
fi
if [[ -z "${APP_UUID:-}" ]]; then
  # UNEXERCISED against a live instance -- see the header. server_uuid /
  # destination_uuid / github_app_uuid resolved by name/singleton lookup, not
  # hardcoded, so a rebuild on a differently-shaped instance still works.
  SERVER_UUID="$(api GET /servers | jqp "
d=json.load(sys.stdin)
m=[s for s in d if s['name']=='localhost']
print(m[0]['uuid'] if m else '')")"
  [[ -n "$SERVER_UUID" ]] || die "no server named 'localhost' -- expected Coolify's own auto-registered entry for this box"
  GITHUB_APP_UUID="$(sshx "docker exec coolify-db psql -U coolify -d coolify -Atc \"select uuid from github_apps order by id limit 1;\"")"
  [[ -n "$GITHUB_APP_UUID" ]] || die "no github_apps row found -- expected the default 'Public GitHub' source"
  CREATE_BODY="$(python3 -c "
import json
print(json.dumps({
  'project_uuid': '$PROJECT_UUID', 'environment_uuid': '$ENV_UUID',
  'server_uuid': '$SERVER_UUID', 'github_app_uuid': '$GITHUB_APP_UUID',
  'git_repository': '$GIT_REPOSITORY', 'git_branch': '$GIT_BRANCH',
  'build_pack': 'dockercompose', 'name': '$APP_NAME',
  'base_directory': '$BASE_DIRECTORY',
  'docker_compose_location': '$DOCKER_COMPOSE_LOCATION',
  'instant_deploy': False,
}))")"
  APP_UUID="$(api POST /applications/private-github-app "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "application created — $APP_UUID (compose parse queued, not deployed yet)"
fi

step "Waiting for the queued compose parse (LoadComposeFile) to create local_file_volumes rows"
# Source-verified: ApplicationsController dispatches LoadComposeFile::dispatch
# at creation when instant_deploy is false, which is what populates
# local_file_volumes -- separately from, and before, any deploy. Poll rather
# than assume the queue worker has already finished.
MOUNT_ROWS=0
for _ in $(seq 1 20); do
  MOUNT_ROWS="$(sshx "docker exec coolify-db psql -U coolify -d coolify -Atc \"select count(*) from local_file_volumes where resource_id=(select id from applications where uuid='$APP_UUID') and resource_type='App\\\\Models\\\\Application';\"")"
  [[ "$MOUNT_ROWS" -gt 0 ]] && break
  sleep 3
done
if [[ "$MOUNT_ROWS" -eq 0 ]]; then
  die "no local_file_volumes rows appeared for $APP_UUID after 60s -- the mount-before-deploy sequencing this script exists for did not hold; investigate before deploying by hand, don't just retry blind."
fi
ok "$MOUNT_ROWS local_file_volumes row(s) present -- safe to materialize now, before any deploy"

step "Materializing the real compose files (never a bogus empty directory this time)"
COOLIFY_APP_UUID="$APP_UUID" "$REPO_ROOT/scripts/coolify-materialize-supabase-mounts.sh" --apply

step "Secrets: mint-if-absent, set env vars, assert non-empty -- all on the box, no value ever leaves it"
# One remote script, python3 on the box (not this process): reads the token,
# lists current envs (names + flags only -- the v1 API's GET .../envs
# response carries no value field at all, confirmed by reading it), mints
# openssl-quality randomness for any of the 8 manifest secrets genuinely
# absent, PATCHes .../envs/bulk, then asserts non-empty the ONLY reliable
# way: decrypts each required key server-side via the app's own Eloquent
# cast (php artisan tinker) and reports true/false -- never ciphertext
# length (meaningless: an empty string still encrypts to a non-trivial
# blob) and never the plaintext itself.
sshx_in <<REMOTE
set -e
umask 077
mkdir -p /root/.pfin
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
APP_UUID="$APP_UUID"

python3 - "\$TOKEN" "\$APP_UUID" <<'PYEOF'
import json, subprocess, sys, secrets as pysecrets

token, app_uuid = sys.argv[1], sys.argv[2]

def api(method, path, body=None):
    cmd = ["curl", "-fsS", "-X", method, "-H", f"Authorization: Bearer {token}"]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else None

existing = {e["key"] for e in api("GET", f"/applications/{app_uuid}/envs")}

MINT_SECRETS = ["POSTGRES_PASSWORD", "JWT_SECRET", "SECRET_KEY_BASE",
                "VAULT_ENC_KEY", "SERVICE_ROLE_KEY", "ANON_KEY",
                "DASHBOARD_PASSWORD", "PG_META_CRYPTO_KEY"]
NONSECRET_DEFAULTS = {"STUDIO_DEFAULT_ORGANIZATION": "mosko-fintech",
                       "STUDIO_DEFAULT_PROJECT": "pfin-supabase"}

to_set = {}
for key in MINT_SECRETS:
    if key not in existing:
        to_set[key] = pysecrets.token_hex(32)
for key, default in NONSECRET_DEFAULTS.items():
    if key not in existing:
        to_set[key] = default

if to_set:
    data = [{"key": k, "value": v} for k, v in to_set.items()]
    api("PATCH", f"/applications/{app_uuid}/envs/bulk", {"data": data})
    # Persist secret values on the box only -- append-only, 600, never echoed.
    with open("/root/.pfin/supabase.env", "a") as f:
        for k in MINT_SECRETS:
            if k in to_set:
                f.write(f"{k}={to_set[k]}\n")
    print(f"MINTED: {sorted(to_set.keys())}")
else:
    print("MINTED: none -- all required keys already present")
PYEOF
chmod 600 /root/.pfin/supabase.env 2>/dev/null || true

# Assert non-empty via Eloquent decryption, never ciphertext length.
docker exec coolify php artisan tinker --execute="
\\\$app = \\App\\Models\\Application::where('uuid','$APP_UUID')->firstOrFail();
\\\$required = ['POSTGRES_PASSWORD','JWT_SECRET','SECRET_KEY_BASE','VAULT_ENC_KEY','SERVICE_ROLE_KEY','ANON_KEY','DASHBOARD_PASSWORD','PG_META_CRYPTO_KEY','STUDIO_DEFAULT_ORGANIZATION','STUDIO_DEFAULT_PROJECT'];
foreach (\\\$required as \\\$key) {
  \\\$env = \\\$app->environment_variables()->where('key', \\\$key)->first();
  \\\$nonEmpty = \\\$env && strlen((string) \\\$env->value) > 0;
  echo \\\$key . ': ' . (\\\$nonEmpty ? 'OK' : 'MISSING') . PHP_EOL;
}
"
REMOTE

step "Refusing to deploy onto a poisoned db-data volume"
EXISTING_DB_VOLUME="$(sshx "docker volume ls -q --filter name=${APP_UUID}_db-data")"
if [[ -n "$EXISTING_DB_VOLUME" ]]; then
  die "${APP_UUID}_db-data already exists. This script does not know whether it initialized against a bogus mount at some point -- see docs/deployment-runbook.md §4 for how to confirm, and 'docker compose --project-name $APP_UUID down -v' to destroy it if it's poisoned. Refusing to deploy onto it silently."
fi
ok "no pre-existing db-data volume -- safe to deploy"

step "Deploying"
DEPLOY_UUID="$(api POST "/deploy?uuid=$APP_UUID" | jqp "
d=json.load(sys.stdin)
print((d.get('deployments') or [{}])[0].get('deployment_uuid',''))")"
[[ -n "$DEPLOY_UUID" ]] || die "deploy call did not return a deployment_uuid"
info "deployment $DEPLOY_UUID queued"

# auto_deploy is inert without a GitHub webhook (ARCH §6 item (f), not wired)
# -- this explicit POST is the only trigger there is. See runbook §4.
STATUS=""
for _ in $(seq 1 90); do
  STATUS="$(api GET "/deployments/$DEPLOY_UUID" | jqp "print(json.load(sys.stdin).get('status',''))")"
  [[ "$STATUS" == "finished" || "$STATUS" == "failed" ]] && break
  sleep 4
done
if [[ "$STATUS" != "finished" ]]; then
  info "deployment log (last 60 lines):"
  api GET "/deployments/$DEPLOY_UUID" | jqp "
d=json.load(sys.stdin)
print('\n'.join(l.get('output','') for l in (d.get('logs') or [])[-60:]))" || true
  die "deployment $DEPLOY_UUID status=$STATUS -- see log above"
fi
ok "deployment finished"

step "Verification battery"
CONTAINERS="$(sshx "docker ps --filter 'label=com.docker.compose.project=$APP_UUID' --filter 'health=healthy' --format '{{.Names}}'" | wc -l | tr -d ' ')"
info "$CONTAINERS/7 containers healthy (db auth rest api-gw supavisor studio meta)"
[[ "$CONTAINERS" == "7" ]] || die "expected 7 healthy containers, got $CONTAINERS"
ok "all 7 containers healthy"

PGVER="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc 'show server_version;'" 2>/dev/null | cut -d. -f1)"
[[ "$PGVER" == "17" ]] || die "expected Postgres 17, got server_version starting '$PGVER'"
ok "Postgres major version 17"

# State-based init check, not filename grep -- the filename check (§4 (1b))
# only works on a FRESH db-data volume; this works regardless.
INIT_STATE="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"select rolname||':'||(rolpassword is not null) from pg_authid where rolname in ('authenticator','pgbouncer','supabase_auth_admin','supabase_functions_admin') order by rolname;\"")"
echo "$INIT_STATE" | while IFS=: read -r role has_pw; do
  info "  $role password set: $has_pw"
  [[ "$has_pw" == "t" ]] || die "role $role has no password set -- init scripts did not run (or db-data was already initialized before this deploy)"
done
JWT_SETTING="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"show app.settings.jwt_secret;\"" 2>&1 || true)"
[[ "$JWT_SETTING" != *"unrecognized configuration parameter"* ]] || die "app.settings.jwt_secret unset -- init scripts did not run"
ok "all four role passwords set + app.settings.jwt_secret present"

ENVOY_LOG="$(sshx "docker compose --project-name $APP_UUID logs api-gw 2>&1 | tail -80")"
echo "$ENVOY_LOG" | grep -q "lds: add/update listener 'supabase'" || die "api-gw log does not show a real Envoy config load"
ok "api-gw loaded a real Envoy config"

SIGNUP_ENV="$(sshx "docker compose --project-name $APP_UUID exec -T auth printenv GOTRUE_DISABLE_SIGNUP" 2>/dev/null || true)"
[[ "$SIGNUP_ENV" == "true" ]] || die "GOTRUE_DISABLE_SIGNUP is '$SIGNUP_ENV', expected 'true' -- standing gate violated"
ok "GOTRUE_DISABLE_SIGNUP=true"

# rest is EXPECTED unhealthy until §6's migrations create the pfin schema --
# assert the SPECIFIC expected error, not just "unhealthy" (§4's rest-
# unhealthy-pre-migrations note).
REST_LOG="$(sshx "docker compose --project-name $APP_UUID logs rest 2>&1 | tail -20")"
if echo "$REST_LOG" | grep -q 'schema "pfin" does not exist'; then
  ok "rest unhealthy as expected pre-§6 (schema \"pfin\" does not exist) -- not a defect"
elif sshx "docker compose --project-name $APP_UUID ps rest --format '{{.Health}}'" 2>/dev/null | grep -qi healthy; then
  ok "rest healthy (§6 must have already run)"
else
  die "rest is unhealthy for a DIFFERENT reason than the expected pre-§6 schema gap -- check the log, this is a real failure: $(echo "$REST_LOG" | tail -5)"
fi

step "External exposure -- must publish nothing but the one Studio loopback"
HOST_PORTS="$(sshx "docker ps --filter 'label=com.docker.compose.project=$APP_UUID' --format '{{.Ports}}'" | grep -oE '[0-9.]+:[0-9]+->' | sort -u || true)"
UNEXPECTED_PORTS="$(echo "$HOST_PORTS" | grep -v '^127.0.0.1:3000->' || true)"
[[ -z "$UNEXPECTED_PORTS" ]] || die "unexpected host-published port(s): $UNEXPECTED_PORTS -- only 127.0.0.1:3000 (Studio) should ever be published"
echo "$HOST_PORTS" | grep -q '^127.0.0.1:3000->' && ok "only 127.0.0.1:3000 published (Studio) -- nothing else" || info "no host ports published at all (also fine if Studio isn't in this deploy)"

info "External probe (run from OUTSIDE the box, this script cannot self-check it): nmap -Pn -p 5432,6543,8000,3000 $BOX_IP -- EXPECT all four filtered."

step "Done"
info "Deploy $DEPLOY_UUID finished and passed the verification battery."
info "Studio, once you want to look at it: ssh -L 3000:localhost:3000 root@$BOX_IP then http://localhost:3000"
