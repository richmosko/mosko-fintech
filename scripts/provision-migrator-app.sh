#!/usr/bin/env bash
#
# provision-migrator-app.sh — stand up the `migrator` Coolify resource as
# its OWN standalone application (ADR-072 Amendment 4, F/CTO-ratified
# 2026-09-16 / BACKLOG.md §7.36 item 29). DevOps-owned. Sibling to
# scripts/provision-supabase-stack.sh — same PROJECT ("pfin-supabase"), same
# ENVIRONMENT ("production"), a SEPARATE application/env store.
#
# WHY THIS IS A SEPARATE SCRIPT, NOT AN EXTENSION OF provision-supabase-stack.sh
#   provision-supabase-stack.sh is already 900+ lines deeply threaded through
#   ONE application's lifecycle (its own APP_NAME/APP_UUID globals, its own
#   mount-materialization step, its own 7-container verification battery).
#   Threading a second, structurally different application (one service, no
#   volumes, no compose mounts, a different build-pack base directory)
#   through those same code paths would either duplicate most of the file
#   under new conditionals or risk the two applications' state leaking into
#   each other's checks. A sibling script keeps each application's
#   provisioning independently readable and independently safe to re-run,
#   at the cost of a second file to keep in sync on shared conventions
#   (sshx/api helpers, mint-if-absent discipline, --apply gating) — those
#   conventions are copied deliberately, not imported, matching this repo's
#   existing pattern of small single-purpose provisioning scripts
#   (provision-vps.sh / provision-supabase-stack.sh / record-coolify-uuids.sh
#   already don't share code with each other either).
#
# WHAT IT REFUSES TO DO
#   No secret value is ever PRINTED or LOGGED. The Coolify API token is read
#   FROM THE BOX on every call (/root/.pfin/coolify.env) — never from a
#   local .env. Nothing is created or mutated without --apply.
#
# IDEMPOTENCE
#   Application: looked up by NAME (MIGRATOR_APP_NAME, default
#   "pfin-migrator"), adopted if present and matching, refused (diff shown)
#   if present and DISAGREEING with this file, created only if absent.
#   Secrets: minted only for a key genuinely absent from THIS application's
#   env (checked by decrypting server-side and testing non-empty — never by
#   ciphertext length). MIGRATOR_STACK_NETWORK_NAME: looked up fresh from
#   the live stack container on every run and unconditionally OVERWRITTEN
#   (not mint-if-absent) — it is not a secret, and a stale value here would
#   silently point `migrator` at a network the stack no longer uses after
#   any stack-side network change.
#
# PREREQUISITE — READ BEFORE RUNNING
#   The Supabase-stack application (scripts/provision-supabase-stack.sh)
#   must already exist and be deployed — this script reads its live
#   Docker network off the box to populate MIGRATOR_STACK_NETWORK_NAME.
#   Running this script before the stack is up will fail closed at that
#   lookup, not silently proceed with a guessed value.
#
# USAGE
#   BOX_IP=<box-ip> scripts/provision-migrator-app.sh          # preflight: read-only
#   BOX_IP=<box-ip> scripts/provision-migrator-app.sh --apply  # create/mint/deploy
#
set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- .env lives at the main checkout root and would be silently discarded when this worktree is removed. Set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  GIT_COMMON_DIR="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || GIT_COMMON_DIR=""
  if [[ -z "$GIT_COMMON_DIR" ]]; then
    printf '\n\033[31mFAIL\033[0m  could not resolve the repo root via git rev-parse --git-common-dir from %s (not inside a git checkout?). Set REPO_ROOT explicitly.\n' "$SCRIPT_DIR" >&2
    exit 1
  fi
  REPO_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
fi

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROJECT_NAME="${PROJECT_NAME:-pfin-supabase}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
# The Supabase-stack application's own name — used ONLY to find its live
# Docker network for MIGRATOR_STACK_NETWORK_NAME. Same default as
# provision-supabase-stack.sh's own APP_NAME, and as
# record-coolify-uuids.sh's SUPABASE_STACK_APP_NAME.
SUPABASE_STACK_APP_NAME="${SUPABASE_STACK_APP_NAME:-pfin-supabase-stack}"
# MIGRATOR_APP_NAME — the new standalone application's own name.
# record-coolify-uuids.sh resolves MIGRATOR_SERVICE_UUID by this same
# name (see that script's own MIGRATOR_APP_NAME default) — keep both in
# sync if this default ever changes.
MIGRATOR_APP_NAME="${MIGRATOR_APP_NAME:-pfin-migrator}"
GIT_REPOSITORY="${GIT_REPOSITORY:-https://github.com/richmosko/mosko-fintech}"
GIT_BRANCH="${GIT_BRANCH:-main}"
BASE_DIRECTORY="/infra/supabase/migrator"
DOCKER_COMPOSE_LOCATION="/docker-compose.yaml"

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

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly, e.g. BOX_IP=188.245.166.206 for prod or BOX_IP=<scratch-ip> for a scratch box. No default means no silent fall-through to prod (same discipline as provision-supabase-stack.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" -H 'Content-Type: application/json' -d '$body' http://localhost:8000/api/v1$path"
  else
    sshx "TOKEN=\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-); curl -fsS -X $method -H \"Authorization: Bearer \$TOKEN\" http://localhost:8000/api/v1$path"
  fi
}
jqp() { python3 -c "import json,sys;$1"; }

step "Preflight — project / environment (adopted, never created by this script)"
# This script deliberately does NOT create the project/environment --
# provision-supabase-stack.sh already owns that lifecycle and must have run
# first. Refuse rather than duplicate that creation logic.
PROJECT_JSON="$(api GET /projects | jqp "
d=json.load(sys.stdin)
m=[p for p in d if p['name']=='$PROJECT_NAME']
print(json.dumps(m[0]) if m else '')")"
[[ -n "$PROJECT_JSON" ]] || die "project '$PROJECT_NAME' does not exist -- run scripts/provision-supabase-stack.sh --apply first (it creates the project)."
PROJECT_UUID="$(echo "$PROJECT_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
ok "project '$PROJECT_NAME' exists — $PROJECT_UUID"

ENV_JSON="$(api GET "/projects/$PROJECT_UUID/environments" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['name']=='$ENVIRONMENT_NAME']
print(json.dumps(m[0]) if m else '')")"
[[ -n "$ENV_JSON" ]] || die "environment '$ENVIRONMENT_NAME' does not exist under project $PROJECT_UUID -- run scripts/provision-supabase-stack.sh --apply first."
ENV_UUID="$(echo "$ENV_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
ok "environment '$ENVIRONMENT_NAME' exists — $ENV_UUID"

step "Preflight — the Supabase-stack application must already be deployed"
STACK_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$SUPABASE_STACK_APP_NAME']
print(json.dumps(m[0]) if m else '')")"
[[ -n "$STACK_APP_JSON" ]] || die "no application named '$SUPABASE_STACK_APP_NAME' -- run scripts/provision-supabase-stack.sh --apply first. This script needs the stack's live Docker network to attach migrator to it."
STACK_APP_UUID="$(echo "$STACK_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
ok "Supabase-stack application '$SUPABASE_STACK_APP_NAME' exists — $STACK_APP_UUID"

step "Looking up the stack's live Docker network (for MIGRATOR_STACK_NETWORK_NAME)"
# ⚠ UNMEASURED MECHANISM, stated per ADR-072 Amendment 4: this reads the
# Docker network membership of a live container in the stack's compose
# project (the same 'meta' container provision-supabase-stack.sh's own
# post-move absence assertion uses, for continuity) and takes the ONE
# non-default (not bridge/host/none) network name it finds. Coolify's own
# per-project network naming is NOT documented and is read here empirically
# -- if a resource ever has MORE than one custom network, or none, this
# step fails closed rather than guessing which one migrator should join.
STACK_NETWORKS="$(sshx "docker inspect --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{println \$k}}{{end}}' \$(docker compose --project-name $STACK_APP_UUID ps -q meta)" 2>/dev/null | grep -Ev '^(bridge|host|none)$' || true)"
NETWORK_COUNT="$(echo "$STACK_NETWORKS" | grep -c . || true)"
if [[ "$NETWORK_COUNT" -ne 1 ]]; then
  die "expected exactly ONE non-default Docker network on the stack's 'meta' container, found $NETWORK_COUNT: [$STACK_NETWORKS]. Cannot safely pick which network migrator should join -- investigate by hand (docker inspect on the box) rather than guessing. This is also where Amendment 4's UNMEASURED question (whether Coolify 4.3.18's dockercompose pack permits an external: network) gets its first real signal -- if the stack itself shows zero custom networks, mechanism (b) may not be viable and the runbook's fallback-(a) path applies instead."
fi
MIGRATOR_STACK_NETWORK_NAME="$STACK_NETWORKS"
ok "stack network — $MIGRATOR_STACK_NETWORK_NAME"

step "Preflight — migrator application (name-keyed lookup)"
GIT_REPOSITORY_STORED="${GIT_REPOSITORY#https://github.com/}"
GIT_REPOSITORY_STORED="${GIT_REPOSITORY_STORED#http://github.com/}"
GIT_REPOSITORY_STORED="${GIT_REPOSITORY_STORED%.git}"

APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$MIGRATOR_APP_NAME']
print(json.dumps(m[0]) if m else '')")"
if [[ -n "$APP_JSON" ]]; then
  APP_UUID="$(echo "$APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  echo "$APP_JSON" | jqp "
d=json.load(sys.stdin)
mismatches=[]
want={'build_pack':'dockercompose','base_directory':'$BASE_DIRECTORY','docker_compose_location':'$DOCKER_COMPOSE_LOCATION','git_repository':'$GIT_REPOSITORY_STORED','git_branch':'$GIT_BRANCH'}
for k,v in want.items():
    if d.get(k)!=v: mismatches.append('%s: file wants %r, resource has %r'%(k,v,d.get(k)))
if mismatches:
    print('MISMATCH')
    for m in mismatches: print('  '+m)
else:
    print('MATCH')
" > /tmp/migrator-app-diff-check.$$
  if grep -q '^MISMATCH' /tmp/migrator-app-diff-check.$$; then
    cat /tmp/migrator-app-diff-check.$$ >&2
    rm -f /tmp/migrator-app-diff-check.$$
    die "application '$MIGRATOR_APP_NAME' exists but disagrees with this file — resolve by hand, refusing to mutate a live resource."
  fi
  rm -f /tmp/migrator-app-diff-check.$$
  ok "application '$MIGRATOR_APP_NAME' exists and matches this file's settings — $APP_UUID"
else
  info "application '$MIGRATOR_APP_NAME' does not exist — would create with build_pack=dockercompose, base_directory=$BASE_DIRECTORY, docker_compose_location=$DOCKER_COMPOSE_LOCATION, branch=$GIT_BRANCH, SAME project/environment as the stack"
fi

step "Plan"
cat <<PLAN
      project        $PROJECT_NAME  $PROJECT_UUID
      environment    $ENVIRONMENT_NAME  $ENV_UUID
      application    $MIGRATOR_APP_NAME  ${APP_UUID:-<to be created>}
      network        $MIGRATOR_STACK_NETWORK_NAME (external, attached to the stack's own network)
      secrets        mint-if-absent: MIGRATOR_DB_USER (default "migrator"), MIGRATOR_DB_PASSWORD (32B)
                      unconditional overwrite (non-secret): MIGRATOR_STACK_NETWORK_NAME
PLAN

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was created, minted, or deployed. Re-run with --apply to execute.\n'
  exit 0
fi

step "Applying — application creation"
if [[ -z "${APP_UUID:-}" ]]; then
  SERVER_UUID="$(api GET /servers | jqp "
d=json.load(sys.stdin)
m=[s for s in d if s['name']=='localhost']
print(m[0]['uuid'] if m else '')")"
  [[ -n "$SERVER_UUID" ]] || die "no server named 'localhost' -- expected Coolify's own auto-registered entry for this box"
  CREATE_BODY="$(python3 -c "
import json
print(json.dumps({
  'project_uuid': '$PROJECT_UUID', 'environment_uuid': '$ENV_UUID',
  'server_uuid': '$SERVER_UUID',
  'git_repository': '$GIT_REPOSITORY', 'git_branch': '$GIT_BRANCH',
  'build_pack': 'dockercompose', 'name': '$MIGRATOR_APP_NAME',
  'base_directory': '$BASE_DIRECTORY',
  'docker_compose_location': '$DOCKER_COMPOSE_LOCATION',
  'instant_deploy': False,
}))")"
  APP_UUID="$(api POST /applications/public "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "application created — $APP_UUID (compose parse queued, not deployed yet)"
fi

step "Secrets: mint-if-absent into THIS application's OWN env store -- never the stack's"
# Same non-echoing tinker mechanism as provision-supabase-stack.sh's own
# mint step -- see that script's header comment for the full IIFE-wrapping
# rationale (Sec-required, pre-prod review 2026-09-11) applied identically
# here.
NEED_MINT="$(sshx_in <<REMOTE
docker exec coolify php artisan tinker --execute="
(function () {
\\\$app = \\App\\Models\\Application::where('uuid','$APP_UUID')->firstOrFail();
\\\$check = ['MIGRATOR_DB_USER','MIGRATOR_DB_PASSWORD'];
foreach (\\\$check as \\\$key) {
  \\\$env = \\\$app->environment_variables()->where('key', \\\$key)->first();
  \\\$nonEmpty = \\\$env && strlen((string) \\\$env->value) > 0;
  if (!\\\$nonEmpty) { echo \\\$key . PHP_EOL; }
}
return null;
})();
"
REMOTE
)"

sshx "env APP_UUID=\"$APP_UUID\" NEED_MINT=\"$NEED_MINT\" MIGRATOR_STACK_NETWORK_NAME=\"$MIGRATOR_STACK_NETWORK_NAME\" bash -s" <<'REMOTE'
set -e
umask 077
TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"

python3 - "$TOKEN" "$APP_UUID" "$NEED_MINT" "$MIGRATOR_STACK_NETWORK_NAME" <<'PYEOF'
import json, subprocess, sys, secrets as pysecrets

token, app_uuid, need_mint_raw, stack_network_name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
need_mint = set(need_mint_raw.split())

# Same argv-safe curl + try/except pattern as provision-supabase-stack.sh's
# own api() -- see that script's header comment for the full incident
# citation (#734-class token-in-exception leak) this mirrors.
def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    cmd = ["curl", "-fsS", "-K", "-", "-X", method]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as exc:
        die(f"Coolify API {method} {path} failed: exit {exc.returncode} ({exc.stderr.strip()[:200]})")
    return json.loads(result.stdout) if result.stdout.strip() else None

MINT_SECRETS = {"MIGRATOR_DB_PASSWORD": 32}
NONSECRET_DEFAULTS = {"MIGRATOR_DB_USER": "migrator"}

to_set = {}
for key, nbytes in MINT_SECRETS.items():
    if key in need_mint:
        to_set[key] = pysecrets.token_hex(nbytes)
for key, default in NONSECRET_DEFAULTS.items():
    if key in need_mint:
        to_set[key] = default

# MIGRATOR_STACK_NETWORK_NAME is NOT mint-if-absent -- it is non-secret,
# environment-specific, and must reflect the STACK's CURRENT network on
# every run, not whatever value was true the first time this script ran.
to_set["MIGRATOR_STACK_NETWORK_NAME"] = stack_network_name

if to_set:
    data = [{"key": k, "value": v} for k, v in to_set.items()]
    api("PATCH", f"/applications/{app_uuid}/envs/bulk", {"data": data})
    with open("/root/.pfin/migrator-app.env", "a") as f:
        for k in MINT_SECRETS:
            if k in to_set:
                f.write(f"{k}={to_set[k]}\n")
    print(f"SET: {sorted(to_set.keys())}")
else:
    print("SET: none new -- MIGRATOR_STACK_NETWORK_NAME still refreshed unconditionally above")
PYEOF
chmod 600 /root/.pfin/migrator-app.env 2>/dev/null || true

# Re-assert non-empty via Eloquent decryption -- same IIFE-wrapped,
# die-on-MISSING discipline as provision-supabase-stack.sh's own
# post-mint assert.
ASSERT_OUT="$(docker exec coolify php artisan tinker --execute="
(function () {
\$app = \App\Models\Application::where('uuid','$APP_UUID')->firstOrFail();
\$required = ['MIGRATOR_DB_USER','MIGRATOR_DB_PASSWORD','MIGRATOR_STACK_NETWORK_NAME'];
foreach (\$required as \$key) {
  \$env = \$app->environment_variables()->where('key', \$key)->first();
  \$nonEmpty = \$env && strlen((string) \$env->value) > 0;
  echo \$key . ': ' . (\$nonEmpty ? 'OK' : 'MISSING') . PHP_EOL;
}
return null;
})();
")"
echo "$ASSERT_OUT"
if echo "$ASSERT_OUT" | grep -q ': MISSING$'; then
  echo "" >&2
  echo "FATAL: required secret(s)/config var(s) still empty after mint -- refusing to deploy:" >&2
  echo "$ASSERT_OUT" | grep ': MISSING$' >&2
  exit 1
fi
REMOTE

step "Deploying"
DEPLOY_UUID="$(api POST "/deploy?uuid=$APP_UUID" | jqp "
d=json.load(sys.stdin)
print((d.get('deployments') or [{}])[0].get('deployment_uuid',''))")"
[[ -n "$DEPLOY_UUID" ]] || die "deploy call did not return a deployment_uuid"
info "deployment $DEPLOY_UUID queued"

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
raw=d.get('logs') or '[]'
entries=json.loads(raw) if isinstance(raw,str) else (raw or [])
print('\n'.join(e.get('output','') for e in entries[-60:]))" || true
  die "deployment $DEPLOY_UUID status=$STATUS -- see log above. If the failure names the 'networks:' block (a parse error, or the network failing to attach), this is Amendment 4's UNMEASURED question resolving negative -- fall back to mechanism (a) per infra/supabase/migrator/docker-compose.yaml's own fallback comment, and record which resources share that predefined network in the runbook's cutover log."
fi
ok "deployment finished"

step "Verification -- proof predicate is NAMES, per ADR-072 Amendment 4"
# Instrument: `docker compose ... exec -T migrator env`, reduced to names
# via `cut -d= -f1` -- names-equivalent to `docker inspect
# --format '{{range .Config.Env}}...'` in practice (a blanked key still
# prints `KEY=`, so either instrument observes the same NAME set), but
# this is the instrument the code below actually runs -- say what it does,
# not a different-but-equivalent one (Sec F4, PR #819 joint review).
CONTAINER_ENV_NAMES="$(sshx "docker compose --project-name $APP_UUID exec -T migrator env" 2>/dev/null | cut -d= -f1 | sort -u || true)"
[[ -n "$CONTAINER_ENV_NAMES" ]] || die "could not read env names off the new migrator container -- deploy may not have produced a running container yet."
for required in MIGRATOR_DB_USER MIGRATOR_DB_PASSWORD PROD_DB_URL PGSSLMODE; do
  echo "$CONTAINER_ENV_NAMES" | grep -qx "$required" || die "new migrator container is missing '$required' -- re-run 'docker compose --project-name $APP_UUID exec -T migrator env' on the box to investigate."
done
STACK_ONLY_LEAK=""
for offender in POSTGRES_PASSWORD JWT_SECRET SERVICE_ROLE_KEY VAULT_ENC_KEY ANON_KEY SECRET_KEY_BASE; do
  if echo "$CONTAINER_ENV_NAMES" | grep -qx "$offender"; then
    STACK_ONLY_LEAK="$STACK_ONLY_LEAK $offender"
  fi
done
if [[ -n "$STACK_ONLY_LEAK" ]]; then
  die "the new migrator container ALSO carries:$STACK_ONLY_LEAK -- this is exactly the C7 confinement failure ADR-072 Amendment 3 measured on the OLD sibling-service topology, now reproduced on the new one. Investigate before treating item 29 as discharged."
fi
ok "new migrator container carries MIGRATOR_DB_USER/MIGRATOR_DB_PASSWORD/PROD_DB_URL/PGSSLMODE, and none of the stack's own secrets — confinement confirmed by measurement, not declaration"

step "Done"
info "Deploy $DEPLOY_UUID finished. Record MIGRATOR_SERVICE_UUID with scripts/record-coolify-uuids.sh --apply (it now resolves by MIGRATOR_APP_NAME, not the stack's own name)."
info "Next: re-create the Scheduled Task under THIS application (scripts/migrator-scheduled-task.md), then run docs/deployment-runbook.md §6.8's CUTOVER PROCEDURE for the credential rotation and stack-side removal."
