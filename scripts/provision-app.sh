#!/usr/bin/env bash
#
# provision-app.sh — recreate the `pfin-app` Coolify resource as a
# `dockercompose` application (F/CTO ruling 2026-09-19,
# docs/deployment-runbook.md Open Flags #12, option A). DevOps-owned.
# Sibling to scripts/provision-migrator-app.sh — same conventions, same
# sshx/api helper shape, copied deliberately rather than shared (this
# repo's existing precedent: provision-vps.sh / provision-supabase-
# stack.sh / provision-migrator-app.sh don't share code with each other
# either).
#
# WHY THIS SCRIPT EXISTS
#   MEASURED (team-lead, 2026-09-19): the existing `pfin-app` resource is
#   a plain-Dockerfile-pack application, in a DIFFERENT Coolify project/
#   environment than the Supabase stack, with `connect_to_docker_network`
#   FALSE on both sides -- it has never had a working path to
#   `api-gw:8000`. F/CTO ruled option A: recreate it as a `dockercompose`
#   application with an `external:` network attachment to the stack's own
#   Docker network (the migrator's own proven shape, ADR-072 Amendment 4).
#   `pfin-app` has ZERO deployments and ZERO env names in its store as of
#   this ruling (measured 2026-09-19) -- recreating it loses no DATA.
#   Sec wording note (PR #836 review): CONFIG is not preserved by this
#   claim -- persistent-storage entries, fqdn/Traefik labels, scheduled
#   tasks, and webhook/git bindings are all re-created by §7.1 step 1's
#   own remaining steps, not carried over from the deleted resource.
#
# WHAT THIS SCRIPT DOES
#   1. DELETE the existing `pfin-app` resource, IF one exists AND it is
#      NOT already a `dockercompose` application (idempotent re-run: if
#      it's already the target shape, this step is a no-op) -- but ONLY
#      after asserting the resource is a genuinely empty shell: zero
#      containers ever created for its uuid (`docker ps -a`, on the box),
#      zero images ever built for it (`docker images`, on the box), and
#      zero env-store names (API, `GET /applications/<uuid>/envs`).
#      MEASURED (team-lead, 2026-09-20): `GET
#      /applications/<uuid>/deployments` is 404 on this Coolify (4.3.18)
#      -- this script's original predicate, unusable as history evidence
#      and not a real Coolify route. `GET /deployments?uuid=<uuid>`
#      returns 200 `[]` even for an application (`pfin-migrator`) with
#      FOUR completed deployments earlier the same day -- that route
#      lists only in-flight/queued deployments, so an empty list there is
#      NOT evidence a resource was never deployed; unfiltered `GET
#      /deployments` is equally uninformative. The on-box `docker`
#      reads are the only measurable substitute found. Refuses (does not
#      delete) if any of the three counts is non-zero, naming the
#      offending predicate and its count (names only -- no env values, no
#      full env dump): this script must never be the vehicle that
#      silently destroys a resource that turned out to hold real state.
#      Sec wording note (PR #836 review): `docker ps -a` / `docker
#      images` are PRUNABLE (`docker system prune`, image GC) -- 0/0
#      here is weaker evidence than "never deployed" on its own; the
#      2026-09-20 measurement that motivated this predicate swap was
#      pinned alongside INDEPENDENT never-deployed evidence for
#      `pfin-app` specifically (zero matching containers/images/env
#      names measured directly on the box at that time), not derived
#      from this predicate in isolation. Also fails CLOSED, not open, if
#      a docker read itself fails (daemon down, permission error) --
#      reported as `unknown`, treated as non-zero.
#   2. Create `pfin-app` as `dockercompose` (base_directory `/api`,
#      compose location `/docker-compose.yaml`, branch `main`), in the
#      SAME project/environment as the Supabase-stack application --
#      resolved from the stack's OWN live resource, never a hardcoded
#      project/environment name (see the PROJECT/ENVIRONMENT RESOLUTION
#      note below for the exact mechanism and its stated uncertainty).
#   3. Read the stack's live Docker network (same `docker inspect`
#      lookup provision-migrator-app.sh already uses) and set
#      `APP_STACK_NETWORK_NAME` on `pfin-app`'s own env store,
#      unconditionally overwritten on every run (non-secret,
#      environment-specific -- a stale value here would silently point
#      `app` at a network the stack no longer uses after any stack-side
#      network change; same discipline as MIGRATOR_STACK_NETWORK_NAME).
#   4. Report `settings.include_source_commit_in_build`'s current value
#      -- NOT forced either way. Unlike the migrator Dockerfile, `api/
#      Dockerfile` has NO `SOURCE_COMMIT`/`GIT_SHA` build-arg guard
#      (confirmed by grep, docs/deployment-runbook.md §7.1 step 1's own
#      measured flag), so this setting does not gate a successful deploy
#      here the way it does for the migrator -- reported for visibility
#      only.
#   Does NOT deploy. scripts/deploy-app.sh is the deploy vehicle,
#   invoked separately (docs/deployment-runbook.md §7.1 step 1) after
#   this script has created the resource SKELETON and the secrets-
#   pushing steps have populated its env store.
#
# PROJECT/ENVIRONMENT RESOLUTION — provenance stated, not overclaimed
#   Team-lead's directive: "resolve by the stack's environment_id, never
#   hard-code." This script reads the Supabase-stack application's OWN
#   `GET /applications/<uuid>` response and tries, in order: (a) a nested
#   `environment` object carrying its own `uuid` field (the Eloquent
#   `->load('environment')` shape Laravel's API commonly returns
#   alongside a bare numeric `environment_id` FK); (b) if that shape is
#   absent, falls back to the BY-NAME project/environment lookup
#   provision-migrator-app.sh already uses (PROJECT_NAME/ENVIRONMENT_NAME
#   env-var overrides, same defaults). Which path actually fires is
#   PRINTED, not silently chosen -- this has NOT been independently
#   measured against a live Coolify response as of this script's
#   authoring (DevOps does not touch the box); if the live shape differs
#   from either guess, fix the python here, do not silently trust
#   whichever path happened to return something.
#
# USAGE
#   BOX_IP=<box-ip> scripts/provision-app.sh          # preflight: read-only
#   BOX_IP=<box-ip> scripts/provision-app.sh --apply  # delete-if-needed + create + set network var
#
set -euo pipefail

if [[ -n "${REPO_ROOT:-}" ]]; then
  :
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$SCRIPT_DIR" == *"/.claude/worktrees/"* ]]; then
    printf '\n\033[31mFAIL\033[0m  running from an agent worktree (%s) -- set REPO_ROOT=<main checkout path> to override, or run this script from the main checkout.\n' "$SCRIPT_DIR" >&2
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
SUPABASE_STACK_APP_NAME="${SUPABASE_STACK_APP_NAME:-pfin-supabase-stack}"
APP_NAME="${APP_NAME:-pfin-app}"
GIT_REPOSITORY="${GIT_REPOSITORY:-https://github.com/richmosko/mosko-fintech}"
GIT_BRANCH="${GIT_BRANCH:-main}"
BASE_DIRECTORY="/api"
DOCKER_COMPOSE_LOCATION="/docker-compose.yaml"

# Sec R2-F3 (PR #833 joint review): shape-guard every API/box-derived
# string before it crosses into a remote shell command or a JSON body --
# same UUID_RE deploy-app.sh:195 and smoke-pfin-exposure.sh use. Not a
# live vector (values come from our own Coolify on our own box; a Docker
# network name cannot contain a quote) -- defense-in-depth, cheap to add.
UUID_RE='^[a-z0-9]{20,32}$'
NETWORK_NAME_RE='^[a-zA-Z0-9][a-zA-Z0-9_.-]*$'

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

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }
sshx_in() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" bash -s; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Sec R2-F1 (PR #833 joint review): same api() shape as
# scripts/deploy-app.sh -- the Coolify token is passed to a remote
# python3 process's own argv (never to curl's argv or a curl -H header
# value). This does NOT close the residual deploy-app.sh's own header
# already names and does not claim to close (python3's own argv stays
# ps-visible on the box, root-only, for that process's lifetime --
# BACKLOG.md §7.36 item 60); it makes this script carry the SAME named
# residual as its two siblings in this PR, instead of a strictly weaker,
# unnamed one (the prior form put the token on curl's own -H argv).
read -r -d '' PY_API_HELPER <<'PY' || true
import json, sys, subprocess, tempfile, os

def die(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)

def api(token, method, path, body=None):
    if '"' in token or "\n" in token:
        die("Coolify API token contains an unexpected character -- refusing to build a curl config for it")
    config = 'header = "Authorization: Bearer ' + token + '"\n'
    tmppath = None
    cmd = ["curl", "-fsS", "-K", "-", "-X", method]
    if body is not None:
        fd, tmppath = tempfile.mkstemp(prefix="pfin-app-body-")
        os.write(fd, body.encode())
        os.close(fd)
        cmd += ["-H", "Content-Type: application/json", "--data-binary", f"@{tmppath}"]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    try:
        result = subprocess.run(cmd, input=config.encode(), capture_output=True)
    finally:
        if tmppath:
            os.unlink(tmppath)
    if result.returncode != 0:
        die(f"Coolify API {method} {path} failed: exit {result.returncode} ({result.stderr.decode(errors='replace').strip()[:200]})")
    out = result.stdout.decode()
    return json.loads(out) if out.strip() else None
PY

api() {
  local method="$1" path="$2" body="${3:-}"
  local env_assign="method=$(printf '%q' "$method") path=$(printf '%q' "$path") body=$(printf '%q' "$body")"
  sshx "env $env_assign bash -s" <<REMOTE
set -e
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
python3 - "\$TOKEN" "\$method" "\$path" "\$body" <<'PYEOF'
$PY_API_HELPER
import sys
token, method, path = sys.argv[1], sys.argv[2], sys.argv[3]
body = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
result = api(token, method, path, body)
print(json.dumps(result) if result is not None else '')
PYEOF
REMOTE
}
jqp() { python3 -c "import json,sys;$1"; }

step "Preflight — the Supabase-stack application must already be deployed"
STACK_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$SUPABASE_STACK_APP_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one.' % (len(m), '$SUPABASE_STACK_APP_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
[[ -n "$STACK_APP_JSON" ]] || die "no application named '$SUPABASE_STACK_APP_NAME' -- run scripts/provision-supabase-stack.sh --apply first. This script needs the stack's live Docker network and project/environment identity."
STACK_APP_UUID="$(echo "$STACK_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
[[ "$STACK_APP_UUID" =~ $UUID_RE ]] || die "resolved stack application uuid '$STACK_APP_UUID' does not match the expected uuid shape -- refusing to use it in a remote command."
ok "Supabase-stack application '$SUPABASE_STACK_APP_NAME' exists — $STACK_APP_UUID"

step "Resolving project/environment from the stack's own resource (never hard-coded)"
# See this script's own header "PROJECT/ENVIRONMENT RESOLUTION" note for
# the full provenance statement. Path (a) tried first; path (b) is the
# provision-migrator-app.sh-precedented fallback.
RESOLVE_OUT="$(echo "$STACK_APP_JSON" | jqp "
d=json.load(sys.stdin)
env_obj = d.get('environment')
if isinstance(env_obj, dict) and env_obj.get('uuid'):
    print('PATH_A')
    print(env_obj['uuid'])
else:
    print('PATH_B')
")"
RESOLVE_PATH="$(sed -n 1p <<<"$RESOLVE_OUT")"

if [[ "$RESOLVE_PATH" == "PATH_A" ]]; then
  ENV_UUID="$(sed -n 2p <<<"$RESOLVE_OUT")"
  info "resolved via path (a): stack's own nested 'environment.uuid' field — $ENV_UUID"
  # PROJECT_UUID is not separately needed by the create call once ENV_UUID
  # is known (Coolify's create endpoint accepts environment_uuid alone
  # alongside server_uuid, per provision-migrator-app.sh's own create
  # body) -- left unresolved on this path; the Plan printout says so
  # rather than fabricating a value.
  PROJECT_UUID="<not resolved on path (a) -- not required for creation>"
else
  info "path (a) unavailable (no stack.environment.uuid) — falling back to BY-NAME lookup (PROJECT_NAME='$PROJECT_NAME', ENVIRONMENT_NAME='$ENVIRONMENT_NAME')"
  PROJECT_JSON="$(api GET /projects | jqp "
d=json.load(sys.stdin)
m=[p for p in d if p['name']=='$PROJECT_NAME']
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$PROJECT_JSON" ]] || die "path (b) fallback failed too: project '$PROJECT_NAME' does not exist. Fix PROJECT_NAME/ENVIRONMENT_NAME, or fix path (a)'s field-path guess in this script against the stack's actual live JSON shape."
  PROJECT_UUID="$(echo "$PROJECT_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$PROJECT_UUID" =~ $UUID_RE ]] || die "resolved project uuid '$PROJECT_UUID' does not match the expected uuid shape -- refusing to use it in a remote command."
  ENV_JSON="$(api GET "/projects/$PROJECT_UUID/environments" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['name']=='$ENVIRONMENT_NAME']
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$ENV_JSON" ]] || die "path (b) fallback failed too: environment '$ENVIRONMENT_NAME' does not exist under project $PROJECT_UUID."
  ENV_UUID="$(echo "$ENV_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
fi
[[ "$ENV_UUID" =~ $UUID_RE ]] || die "resolved environment uuid '$ENV_UUID' does not match the expected uuid shape -- refusing to use it in a remote command or JSON body."
ok "environment resolved — $ENV_UUID (project: $PROJECT_UUID)"

step "Looking up the stack's live Docker network (for APP_STACK_NETWORK_NAME)"
# Same mechanism as provision-migrator-app.sh's own MIGRATOR_STACK_NETWORK_NAME
# lookup -- see that script's header for the full "UNMEASURED MECHANISM"
# citation this reuses verbatim (Coolify's per-project network naming is
# not documented; read empirically off a live container, fail closed if
# not exactly one non-default network is found).
STACK_NETWORKS="$(sshx "docker inspect --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{println \$k}}{{end}}' \$(docker compose --project-name $STACK_APP_UUID ps -q meta)" 2>/dev/null | grep -Ev '^(bridge|host|none)$' || true)"
NETWORK_COUNT="$(echo "$STACK_NETWORKS" | grep -c . || true)"
if [[ "$NETWORK_COUNT" -ne 1 ]]; then
  die "expected exactly ONE non-default Docker network on the stack's 'meta' container, found $NETWORK_COUNT: [$STACK_NETWORKS]. Cannot safely pick which network 'app' should join -- investigate by hand (docker inspect on the box) rather than guessing."
fi
APP_STACK_NETWORK_NAME="$STACK_NETWORKS"
[[ "$APP_STACK_NETWORK_NAME" =~ $NETWORK_NAME_RE ]] || die "stack network name '$APP_STACK_NETWORK_NAME' does not match the expected Docker-network-name shape -- refusing to use it in a remote command or JSON body."
ok "stack network — $APP_STACK_NETWORK_NAME"

step "Preflight — existing '$APP_NAME' resource (delete-if-stale-shape check)"
OLD_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$APP_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one to delete.' % (len(m), '$APP_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
DELETE_NEEDED=0
if [[ -n "$OLD_APP_JSON" ]]; then
  OLD_APP_UUID="$(echo "$OLD_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$OLD_APP_UUID" =~ $UUID_RE ]] || die "resolved existing '$APP_NAME' uuid '$OLD_APP_UUID' does not match the expected uuid shape -- refusing to use it in a DELETE call."
  OLD_BUILD_PACK="$(echo "$OLD_APP_JSON" | jqp "print(json.load(sys.stdin).get('build_pack',''))")"
  if [[ "$OLD_BUILD_PACK" == "dockercompose" ]]; then
    info "'$APP_NAME' ($OLD_APP_UUID) already exists as build_pack=dockercompose — treating as already-migrated, no delete needed."
    APP_UUID="$OLD_APP_UUID"
  else
    info "'$APP_NAME' ($OLD_APP_UUID) exists with build_pack='$OLD_BUILD_PACK' — needs replacement with a dockercompose resource."
    # Empty-shell predicate, on-box + API (MEASURED team-lead 2026-09-20 --
    # see this script's own header "WHAT THIS SCRIPT DOES" item 1 for why
    # the deployments-count API family was replaced with these three
    # reads). $OLD_APP_UUID is already UUID_RE-validated above, before it
    # reaches these greps.
    #
    # Sec F-1 (PR #836 review): fail CLOSED when the on-box docker read
    # itself fails (daemon down/restarting, docker missing, permission
    # error) -- checking the SSH command's own exit status BEFORE piping
    # into grep locally, rather than `... | grep -c ... || true` inside
    # the remote command string. The prior shape ran with no pipefail on
    # the remote shell: a failed `docker` fed grep empty stdin, which
    # printed 0 and exited 1, and the trailing `|| true` swallowed that
    # 1 -- so a failed read and a genuinely empty box were indistinguishable,
    # both reporting count=0 and letting the guard pass. Same fail-closed
    # shape as the env-store read below (ENV_COUNT="unknown" on failure).
    if CONTAINER_RAW="$(sshx "docker ps -a --format '{{.Names}}'" 2>/dev/null)"; then
      CONTAINER_COUNT="$(printf '%s\n' "$CONTAINER_RAW" | grep -c "$OLD_APP_UUID" || true)"
    else
      CONTAINER_COUNT="unknown"
    fi
    if IMAGE_RAW="$(sshx "docker images --format '{{.Repository}}'" 2>/dev/null)"; then
      IMAGE_COUNT="$(printf '%s\n' "$IMAGE_RAW" | grep -c "$OLD_APP_UUID" || true)"
    else
      IMAGE_COUNT="unknown"
    fi
    ENV_COUNT="$(api GET "/applications/$OLD_APP_UUID/envs" | jqp "
d=json.load(sys.stdin)
print(len(d))" 2>/dev/null || echo "unknown")"
    info "measured on '$OLD_APP_UUID': containers=$CONTAINER_COUNT, images=$IMAGE_COUNT, env-store names=$ENV_COUNT"
    if [[ "$CONTAINER_COUNT" != "0" ]]; then
      die "REFUSING TO DELETE '$APP_NAME' ($OLD_APP_UUID): containers=$CONTAINER_COUNT -- either \`docker ps -a\` shows at least one container ever created for this uuid, or the on-box read itself failed ('unknown', treated as non-zero). This resource may hold real state, or could not be confirmed empty; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    if [[ "$IMAGE_COUNT" != "0" ]]; then
      die "REFUSING TO DELETE '$APP_NAME' ($OLD_APP_UUID): images=$IMAGE_COUNT -- either \`docker images\` shows at least one image ever built for this uuid, or the on-box read itself failed ('unknown', treated as non-zero). This resource may hold real state, or could not be confirmed empty; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    if [[ "$ENV_COUNT" != "0" ]]; then
      die "REFUSING TO DELETE '$APP_NAME' ($OLD_APP_UUID): env-store names=$ENV_COUNT -- expected zero. This resource may hold real state; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    DELETE_NEEDED=1
  fi
else
  info "'$APP_NAME' does not exist — will be created fresh."
fi

step "Plan"
cat <<PLAN
      project        $PROJECT_UUID
      environment    $ENV_UUID
      application    $APP_NAME  ${APP_UUID:-<to be created>}
      delete-first   $([[ $DELETE_NEEDED -eq 1 ]] && echo "YES — old build_pack='$OLD_BUILD_PACK', ${OLD_APP_UUID:-}" || echo "no")
      network        $APP_STACK_NETWORK_NAME (external, attached to the stack's own network)
      env-var        unconditional overwrite (non-secret): APP_STACK_NETWORK_NAME
PLAN

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was deleted, created, or set. Re-run with --apply to execute.\n'
  exit 0
fi

if [[ $DELETE_NEEDED -eq 1 ]]; then
  step "Deleting stale '$APP_NAME' ($OLD_APP_UUID) — zero deployments, zero env names, confirmed above"
  api DELETE "/applications/$OLD_APP_UUID" >/dev/null
  STILL_PRESENT="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['uuid']=='$OLD_APP_UUID']
print('yes' if m else 'no')")"
  [[ "$STILL_PRESENT" == "no" ]] || die "deleted '$OLD_APP_UUID' but it is still present in /applications -- investigate before proceeding."
  ok "deleted — absence confirmed by re-read, not inferred from the DELETE call's own reported success"
fi

if [[ -z "${APP_UUID:-}" ]]; then
  step "Applying — application creation (dockercompose)"
  SERVER_UUID="$(api GET /servers | jqp "
d=json.load(sys.stdin)
m=[s for s in d if s['name']=='localhost']
print(m[0]['uuid'] if m else '')")"
  [[ -n "$SERVER_UUID" ]] || die "no server named 'localhost' -- expected Coolify's own auto-registered entry for this box"
  [[ "$SERVER_UUID" =~ $UUID_RE ]] || die "resolved server uuid '$SERVER_UUID' does not match the expected uuid shape -- refusing to use it in a JSON body."
  CREATE_BODY="$(python3 -c "
import json
print(json.dumps({
  'environment_uuid': '$ENV_UUID',
  'server_uuid': '$SERVER_UUID',
  'git_repository': '$GIT_REPOSITORY', 'git_branch': '$GIT_BRANCH',
  'build_pack': 'dockercompose', 'name': '$APP_NAME',
  'base_directory': '$BASE_DIRECTORY',
  'docker_compose_location': '$DOCKER_COMPOSE_LOCATION',
  'instant_deploy': False,
}))")"
  APP_UUID="$(api POST /applications/public "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$APP_UUID" =~ $UUID_RE ]] || die "created-application uuid '$APP_UUID' does not match the expected uuid shape -- refusing to use it in later API calls."
  ok "application created — $APP_UUID (compose parse queued, not deployed — scripts/deploy-app.sh handles the deploy separately)"
fi

step "Reporting settings.include_source_commit_in_build (NOT forced — see header)"
SOURCE_COMMIT_JSON="$(api GET "/applications/$APP_UUID")"
if echo "$SOURCE_COMMIT_JSON" | "$REPO_ROOT/scripts/ci/check-source-commit-in-build.sh" >/tmp/app-source-commit-check.$$ 2>&1; then
  info "settings.include_source_commit_in_build — true (harmless here; api/Dockerfile has no SOURCE_COMMIT/GIT_SHA guard)"
else
  info "settings.include_source_commit_in_build — not true ($(cat /tmp/app-source-commit-check.$$ | tr -d '\n')) — not a blocker, api/Dockerfile has no such guard"
fi
rm -f /tmp/app-source-commit-check.$$

step "Setting APP_STACK_NETWORK_NAME (non-secret, unconditional overwrite)"
api PATCH "/applications/$APP_UUID/envs/bulk" "$(python3 -c "
import json
print(json.dumps({'data': [{'key': 'APP_STACK_NETWORK_NAME', 'value': '$APP_STACK_NETWORK_NAME'}]}))")" >/dev/null
ENVS_AFTER="$(api GET "/applications/$APP_UUID/envs")"
READBACK="$(echo "$ENVS_AFTER" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['key']=='APP_STACK_NETWORK_NAME']
print(m[0]['value'] if m else '')")"
[[ "$READBACK" == "$APP_STACK_NETWORK_NAME" ]] \
  || die "wrote APP_STACK_NETWORK_NAME='$APP_STACK_NETWORK_NAME' but read back '$READBACK' -- byte-exact mismatch, refusing to trust the store."
ok "APP_STACK_NETWORK_NAME set and byte-exact read-back verified — $APP_STACK_NETWORK_NAME"

step "Done"
info "Resource '$APP_NAME' ($APP_UUID) is a dockercompose application, network var set, NOT yet deployed."
info "Record APP_UUID with scripts/record-coolify-uuids.sh --apply (it resolves by name, confirm it still does after this recreation)."
info "Next: docs/deployment-runbook.md §7.1 step 1's remaining steps (push secrets, coolify-env.sh set, mint, then scripts/deploy-app.sh)."
