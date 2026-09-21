#!/usr/bin/env bash
#
# provision-worker.sh — generalised sibling of scripts/provision-app.sh:
# recreate one of the three worker Coolify resources (`pfin-back-etl`,
# `pfin-pdf-render`, `pfin-provider-sync`) as a `dockercompose` application
# with an `external:` network attachment to the Supabase stack's own Docker
# network. BACKLOG.md §7.36 item 68 (F/CTO-ruled fleet convention,
# 2026-09-19; ADR-073). DevOps-owned.
#
# TABLE-DRIVEN, not three copies of provision-app.sh — the only things that
# differ between the three workers are: which Coolify application NAME to
# resolve, which Base Directory it builds from, and which uniquely-named
# env var carries the attached network's name (same per-resource-name
# discipline as MIGRATOR_STACK_NETWORK_NAME / APP_STACK_NETWORK_NAME — never
# a var shared across resources). Every other step is IDENTICAL logic to
# provision-app.sh: same delete-if-empty-shell guard (fail-closed docker
# reads), same exact-name resolution with a >1-match refusal, same
# project/environment resolution off the stack's own live resource, same
# stack-network lookup, same create-body shape (project_uuid +
# environment_uuid + server_uuid, UUID_RE-guarded), same PATCH-into-a-
# variable-first env-write shape (the bash-3.2 argument-position fix
# provision-app.sh's own header documents), same byte-exact readback.
# provision-app.sh itself is UNCHANGED by this PR — kept as its own script,
# not refactored into this one (flagged as a possible follow-up in the
# PR hand-off, not decided here).
#
# WHAT THIS SCRIPT DOES (per invocation, one resource at a time)
#   1. Refuse an unrecognised <resource-name> before any network call.
#   2. DELETE the existing resource, IF one exists AND it is NOT already a
#      `dockercompose` application — but ONLY after asserting it is a
#      genuinely empty shell: zero on-box containers ever created for its
#      uuid, zero on-box images ever built for it, zero env-store names.
#      Fails CLOSED (refuses to delete) if any predicate is non-zero OR if
#      an on-box docker read itself fails (reported "unknown", treated as
#      non-zero) — this script must never be the vehicle that silently
#      destroys a resource holding real state.
#   3. Create it fresh as `dockercompose` (base_directory per the table,
#      compose location `/docker-compose.yaml`, branch `main`), in the SAME
#      project/environment as the Supabase-stack application — resolved
#      from the stack's own live resource, never hard-coded.
#   4. Read the stack's live Docker network and set this resource's OWN
#      uniquely-named network var (per the table) on its own env store,
#      unconditionally overwritten on every run (non-secret,
#      environment-specific).
#   5. Report `settings.include_source_commit_in_build`'s current value —
#      NOT forced either way. None of the three worker Dockerfiles carry a
#      `SOURCE_COMMIT`/`GIT_SHA` build-arg guard (confirmed by grep, same
#      check provision-app.sh's own header states for api/Dockerfile), so
#      this setting does not gate a successful deploy for any of them
#      either — reported for visibility only.
#   6. Clear any default Coolify-assigned `fqdn`/`ports_exposes` (CA-1,
#      run-8 stop, 2026-09-19) — runs on EVERY --apply, not just at
#      create, so it is a live done-predicate as much as a one-time
#      action: Coolify 4.3.18 assigns a default sslip.io domain + 80 to
#      every application at create, whether or not one was requested,
#      which trips `admissionGuard.ts`'s CA-1 refusal on boot (correct
#      behavior — the fix belongs here, on the resource, never in the
#      guard). `ports_exposes` clears via a MEASURED-working PATCH,
#      read-back verified. `fqdn` has NO public-API clear path for a
#      dockercompose application (MEASURED 2026-09-21) — this script
#      STOPS (die) rather than build around it; see the step's own
#      header for the full measurement and why a box-side tinker write
#      is not implemented here without Sec's sign-off.
#   Does NOT deploy. A deploy vehicle (mirroring scripts/deploy-app.sh) is
#   named in this PR's hand-off as a PENDING follow-up (docs/deployment-
#   runbook.md §7.2), not built here.
#
# USAGE
#   BOX_IP=<box-ip> scripts/provision-worker.sh <resource-name>          # preflight
#   BOX_IP=<box-ip> scripts/provision-worker.sh <resource-name> --apply  # delete-if-needed + create + set network var
#   BOX_IP=<box-ip> scripts/provision-worker.sh <resource-name> --state  # PROVABLY READ-ONLY: print current
#                                                                         # fqdn/ports_exposes state, nothing else
#
#   --state (run-11 stop fix, 2026-09-21, Sec's five requirements) exists
#   because the PREFLIGHT-mode "current state: fqdn=..., ports_exposes=..."
#   line that provision.sh's worker_fqdn_clear_if_needed() reads is
#   produced by code that sits AFTER the `if [[ $APPLY -eq 0 ]]; then exit
#   0; fi` gate below -- a plain preflight run (no flag) NEVER reaches it,
#   and never printed it, contrary to this script's own prior header claim
#   ("printed unconditionally, apply or not"). That gap made the caller's
#   `grep` silently see NO state line and read absence-of-match as
#   "nothing is SET" -- fail-open on exactly the resume-path gap this
#   script exists to close. --state short-circuits IMMEDIATELY after
#   resolving the resource's own uuid by name (one GET /applications) with
#   ONE more GET (/applications/<uuid>) + the same classify_domain_state()
#   used by --apply's own pre/post-clear reads, then exits -- before the
#   stack-application check, project/environment resolution, network
#   lookup, or ANY create/delete/PATCH/tinker call. Two GETs, zero writes,
#   by construction (see fence-provision-worker-strikes.sh's own
#   provably-read-only scenario: a fake that fails closed on ANY
#   POST/PATCH/DELETE/tinker call, and --state still exits 0 against it).
#
#   <resource-name> is a Coolify APPLICATION NAME, one of:
#     pfin-back-etl       -- workers/etl/          -- ETL_STACK_NETWORK_NAME
#     pfin-pdf-render     -- workers/pdf-render/    -- PDF_RENDER_STACK_NETWORK_NAME
#     pfin-provider-sync  -- workers/provider-sync/ -- PROVIDER_SYNC_STACK_NETWORK_NAME
#   Any other value is refused before any SSH/API call is made.
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

# --- Argument parsing --------------------------------------------------------
RESOURCE_NAME="${1:-}"
APPLY=0
STATE_ONLY=0
if [[ $# -ge 1 ]]; then shift; fi
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --state) STATE_ONLY=1 ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 <resource-name> [--apply | --state]" >&2; exit 2 ;;
  esac
done
if [[ "$APPLY" -eq 1 && "$STATE_ONLY" -eq 1 ]]; then
  echo "FATAL: --apply and --state are mutually exclusive." >&2
  exit 2
fi

# --- Table: resource-name -> base_directory / network-var-name -------------
# The ONLY per-worker difference in this script's own logic. Refusing an
# unknown name here, before any SSH/API call, is deliberate -- a typo'd
# resource name must never silently fall through to touching the wrong
# Coolify application.
case "$RESOURCE_NAME" in
  pfin-back-etl)
    BASE_DIRECTORY="/workers/etl"
    NETWORK_VAR_NAME="ETL_STACK_NETWORK_NAME"
    ;;
  pfin-pdf-render)
    BASE_DIRECTORY="/workers/pdf-render"
    NETWORK_VAR_NAME="PDF_RENDER_STACK_NETWORK_NAME"
    ;;
  pfin-provider-sync)
    BASE_DIRECTORY="/workers/provider-sync"
    NETWORK_VAR_NAME="PROVIDER_SYNC_STACK_NETWORK_NAME"
    ;;
  "")
    echo "FATAL: missing <resource-name> argument." >&2
    echo "usage: $0 <resource-name> [--apply]" >&2
    echo "  <resource-name> is one of: pfin-back-etl, pfin-pdf-render, pfin-provider-sync" >&2
    exit 2
    ;;
  *)
    echo "FATAL: unrecognised resource-name '$RESOURCE_NAME' -- refusing." >&2
    echo "  <resource-name> is one of: pfin-back-etl, pfin-pdf-render, pfin-provider-sync" >&2
    echo "  (case-sensitive, exact Coolify application names -- not a conceptual key like 'etl')." >&2
    exit 2
    ;;
esac

BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROJECT_NAME="${PROJECT_NAME:-pfin-supabase}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
SUPABASE_STACK_APP_NAME="${SUPABASE_STACK_APP_NAME:-pfin-supabase-stack}"
GIT_REPOSITORY="${GIT_REPOSITORY:-https://github.com/richmosko/mosko-fintech}"
GIT_BRANCH="${GIT_BRANCH:-main}"
DOCKER_COMPOSE_LOCATION="/docker-compose.yaml"

# Sec R2-F3 precedent (provision-app.sh) -- same guards, same shape-check
# discipline before any API/box-derived string crosses into a remote shell
# command or a JSON body.
UUID_RE='^[a-z0-9]{20,32}$'
NETWORK_NAME_RE='^[a-zA-Z0-9][a-zA-Z0-9_.-]*$'

die()  { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m  %s\n' "$*" >&2; }

[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted -- set it explicitly (same discipline as every other scripts/provision-*.sh)."

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -i "$AUTOMATION_KEY")
sshx() { ssh "${SSH_OPTS[@]}" "root@$BOX_IP" "$@"; }

sshx true >/dev/null 2>&1 || die "box at $BOX_IP not reachable over SSH with $AUTOMATION_KEY -- run scripts/provision-vps.sh first"
sshx 'test -s /root/.pfin/coolify.env' >/dev/null 2>&1 \
  || die "no /root/.pfin/coolify.env on the box -- run scripts/provision-vps.sh --apply first"

# Same api()/jqp() shape as provision-app.sh -- see that script's own header
# for the Sec R2-F1 rationale (token passed to the REMOTE python3 process's
# argv, never to curl's own argv or a -H header value) and the Sec-adjacent
# `-w '\n%{http_code}'` fix (curl's own `-f` discards the response body on a
# non-2xx status; dropped in favour of parsing an appended status line so a
# 4xx's real error body is visible, not just a generic curl exit code).
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
    cmd = ["curl", "-sS", "-K", "-", "-X", method, "-w", "\n%{http_code}"]
    if body is not None:
        fd, tmppath = tempfile.mkstemp(prefix="pfin-worker-body-")
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
        die(f"Coolify API {method} {path} failed: curl exit {result.returncode} ({result.stderr.decode(errors='replace').strip()[:200]})")
    raw = result.stdout.decode()
    out, _, code = raw.rpartition("\n")
    if not code.isdigit():
        die(f"Coolify API {method} {path}: could not parse an HTTP status code off curl's own -w output -- refusing to guess success or failure. Raw tail: {raw[-200:]!r}")
    status = int(code)
    if not (200 <= status < 300):
        die(f"Coolify API {method} {path} -> HTTP {status}: {out.strip()[:500]}")
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
jqp() {
  # Same empty-stdin guard as provision-app.sh's own jqp() (team-lead
  # finding, PR #836 follow-up) -- an empty api() stdout (its own die()
  # already printed the real diagnostic) must not also crash into an
  # unrelated python traceback.
  local input
  input="$(cat)"
  [[ -n "$input" ]] || exit 1
  printf '%s' "$input" | python3 -c "import json,sys;$1"
}

# Sec (PR #862 review): the read must distinguish ABSENT (key not in the
# JSON at all), EMPTY (present but null/""), and SET (present with a
# real value) -- not collapse all three via a Python-truthiness `or ''`.
# This is the same class of bug this repo already paid for once
# (Coolify compose-parse env rows: a row existing is not the same fact
# as a row holding a real value) -- one shared classifier used for the
# pre-clear read, the post-clear read-back, AND --state's own read below,
# so none of the three can drift apart on what "cleared" means. Read from
# stdin via a STATIC heredoc (no bash variable spliced into the python
# source) -- also closes Sec's separate note on an earlier revision of
# this step that interpolated a bash variable into a python string
# literal. Moved up from its original position (just before the
# ports_exposes-clear step) so --state's short-circuit below can use it
# without duplicating it.
read -r -d '' PY_CLASSIFY_HELPER <<'PY' || true
import json, sys
d = json.load(sys.stdin)
for key in ('fqdn', 'ports_exposes'):
    if key not in d:
        state, val = 'ABSENT', ''
    else:
        v = d[key]
        if v is None or v == '':
            state, val = 'EMPTY', ''
        else:
            state, val = 'SET', str(v)
    print(f'{state}\t{val}')
PY
classify_domain_state() {
  # stdin: the application JSON. stdout: "FQDN_STATE\tFQDN_VAL\nPORTS_STATE\tPORTS_VAL".
  python3 -c "$PY_CLASSIFY_HELPER"
}

# --state (run-11 stop fix) -- see this script's own USAGE header for the
# full gap this closes. Resolves the resource by NAME (one GET), refuses
# on >1 match (same discipline as every other by-name resolution in this
# repo), dies if it does not exist at all (a resource that was never
# provisioned has no fqdn/ports_exposes state to report -- this is a
# precondition failure, not a "state: absent" fact), then ONE more GET
# for the classify + the SAME "current state: ..." line format the
# apply-path already prints (byte-for-byte -- provision.sh's caller greps
# this exact format). Exits before the stack-application check, before
# project/environment resolution, before the network lookup, and before
# ANY create/delete/PATCH/tinker call exists in this script's control
# flow -- two GETs total, nothing else, so a hostile fake that fails
# closed on any write call still sees --state exit 0 (Sec requirement 3).
if [[ "$STATE_ONLY" -eq 1 ]]; then
  step "State-only read for '$RESOURCE_NAME' (--state: two GETs, zero writes)"
  STATE_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$RESOURCE_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one.' % (len(m), '$RESOURCE_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$STATE_APP_JSON" ]] || die "'$RESOURCE_NAME' does not exist -- cannot report fqdn/ports_exposes state for a resource that was never created. Run scripts/provision-worker.sh $RESOURCE_NAME --apply first (provision-resources step)."
  STATE_APP_UUID="$(echo "$STATE_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$STATE_APP_UUID" =~ $UUID_RE ]] || die "resolved '$RESOURCE_NAME' uuid '$STATE_APP_UUID' does not match the expected uuid shape -- refusing to use it in a GET call."
  STATE_APP_JSON_FULL="$(api GET "/applications/$STATE_APP_UUID")"
  STATE_CLASSIFIED="$(echo "$STATE_APP_JSON_FULL" | classify_domain_state)"
  STATE_FQDN_STATE="$(sed -n '1p' <<<"$STATE_CLASSIFIED" | cut -f1)"
  STATE_FQDN_VAL="$(sed -n '1p' <<<"$STATE_CLASSIFIED" | cut -f2)"
  STATE_PORTS_STATE="$(sed -n '2p' <<<"$STATE_CLASSIFIED" | cut -f1)"
  STATE_PORTS_VAL="$(sed -n '2p' <<<"$STATE_CLASSIFIED" | cut -f2)"
  info "current state: fqdn=$STATE_FQDN_STATE${STATE_FQDN_VAL:+ ('$STATE_FQDN_VAL')}, ports_exposes=$STATE_PORTS_STATE${STATE_PORTS_VAL:+ ('$STATE_PORTS_VAL')}"
  exit 0
fi

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
  PROJECT_JSON="$(api GET /projects | jqp "
d=json.load(sys.stdin)
m=[p for p in d if p['name']=='$PROJECT_NAME']
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$PROJECT_JSON" ]] || die "path (a) resolved environment.uuid but the project_uuid the create call also requires could not be found by name: project '$PROJECT_NAME' does not exist. Fix PROJECT_NAME, or investigate whether the stack's own resource actually lives under a different project than PROJECT_NAME names."
  PROJECT_UUID="$(echo "$PROJECT_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
else
  info "path (a) unavailable (no stack.environment.uuid) — falling back to BY-NAME lookup (PROJECT_NAME='$PROJECT_NAME', ENVIRONMENT_NAME='$ENVIRONMENT_NAME')"
  PROJECT_JSON="$(api GET /projects | jqp "
d=json.load(sys.stdin)
m=[p for p in d if p['name']=='$PROJECT_NAME']
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$PROJECT_JSON" ]] || die "path (b) fallback failed too: project '$PROJECT_NAME' does not exist. Fix PROJECT_NAME/ENVIRONMENT_NAME, or fix path (a)'s field-path guess in this script against the stack's actual live JSON shape."
  PROJECT_UUID="$(echo "$PROJECT_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ENV_JSON="$(api GET "/projects/$PROJECT_UUID/environments" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['name']=='$ENVIRONMENT_NAME']
print(json.dumps(m[0]) if m else '')")"
  [[ -n "$ENV_JSON" ]] || die "path (b) fallback failed too: environment '$ENVIRONMENT_NAME' does not exist under project $PROJECT_UUID."
  ENV_UUID="$(echo "$ENV_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
fi
[[ "$PROJECT_UUID" =~ $UUID_RE ]] || die "resolved project uuid '$PROJECT_UUID' does not match the expected uuid shape -- refusing to use it in a remote command or JSON body."
[[ "$ENV_UUID" =~ $UUID_RE ]] || die "resolved environment uuid '$ENV_UUID' does not match the expected uuid shape -- refusing to use it in a remote command or JSON body."
ok "environment resolved — $ENV_UUID (project: $PROJECT_UUID)"

step "Looking up the stack's live Docker network (for $NETWORK_VAR_NAME)"
STACK_NETWORKS="$(sshx "docker inspect --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{println \$k}}{{end}}' \$(docker compose --project-name $STACK_APP_UUID ps -q meta)" 2>/dev/null | grep -Ev '^(bridge|host|none)$' || true)"
NETWORK_COUNT="$(echo "$STACK_NETWORKS" | grep -c . || true)"
if [[ "$NETWORK_COUNT" -ne 1 ]]; then
  die "expected exactly ONE non-default Docker network on the stack's 'meta' container, found $NETWORK_COUNT: [$STACK_NETWORKS]. Cannot safely pick which network '$RESOURCE_NAME' should join -- investigate by hand (docker inspect on the box) rather than guessing."
fi
STACK_NETWORK_NAME="$STACK_NETWORKS"
[[ "$STACK_NETWORK_NAME" =~ $NETWORK_NAME_RE ]] || die "stack network name '$STACK_NETWORK_NAME' does not match the expected Docker-network-name shape -- refusing to use it in a remote command or JSON body."
ok "stack network — $STACK_NETWORK_NAME"

step "Preflight — existing '$RESOURCE_NAME' resource (delete-if-stale-shape check)"
OLD_APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$RESOURCE_NAME']
if len(m) > 1:
    raise SystemExit('FATAL: %d applications named %r (%r) -- refusing to pick one to delete.' % (len(m), '$RESOURCE_NAME', [x['uuid'] for x in m]))
print(json.dumps(m[0]) if m else '')")"
DELETE_NEEDED=0
if [[ -n "$OLD_APP_JSON" ]]; then
  OLD_APP_UUID="$(echo "$OLD_APP_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$OLD_APP_UUID" =~ $UUID_RE ]] || die "resolved existing '$RESOURCE_NAME' uuid '$OLD_APP_UUID' does not match the expected uuid shape -- refusing to use it in a DELETE call."
  OLD_BUILD_PACK="$(echo "$OLD_APP_JSON" | jqp "print(json.load(sys.stdin).get('build_pack',''))")"
  if [[ "$OLD_BUILD_PACK" == "dockercompose" ]]; then
    info "'$RESOURCE_NAME' ($OLD_APP_UUID) already exists as build_pack=dockercompose — treating as already-migrated, no delete needed."
    APP_UUID="$OLD_APP_UUID"
  else
    info "'$RESOURCE_NAME' ($OLD_APP_UUID) exists with build_pack='$OLD_BUILD_PACK' — needs replacement with a dockercompose resource."
    # Same fail-closed empty-shell predicate as provision-app.sh's own
    # (Sec F-1, PR #836 review): check the SSH command's own exit status
    # BEFORE piping into grep locally, so a failed docker read and a
    # genuinely empty box are never indistinguishable.
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
      die "REFUSING TO DELETE '$RESOURCE_NAME' ($OLD_APP_UUID): containers=$CONTAINER_COUNT -- either \`docker ps -a\` shows at least one container ever created for this uuid, or the on-box read itself failed ('unknown', treated as non-zero). This resource may hold real state, or could not be confirmed empty; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    if [[ "$IMAGE_COUNT" != "0" ]]; then
      die "REFUSING TO DELETE '$RESOURCE_NAME' ($OLD_APP_UUID): images=$IMAGE_COUNT -- either \`docker images\` shows at least one image ever built for this uuid, or the on-box read itself failed ('unknown', treated as non-zero). This resource may hold real state, or could not be confirmed empty; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    if [[ "$ENV_COUNT" != "0" ]]; then
      die "REFUSING TO DELETE '$RESOURCE_NAME' ($OLD_APP_UUID): env-store names=$ENV_COUNT -- expected zero. This resource may hold real state; investigate by hand before deleting anything. This script only deletes a genuinely empty shell."
    fi
    DELETE_NEEDED=1
  fi
else
  info "'$RESOURCE_NAME' does not exist — will be created fresh."
fi

step "Plan"
cat <<PLAN
      resource-name  $RESOURCE_NAME
      base-directory $BASE_DIRECTORY
      network-var    $NETWORK_VAR_NAME
      project        $PROJECT_UUID
      environment    $ENV_UUID
      application    $RESOURCE_NAME  ${APP_UUID:-<to be created>}
      delete-first   $([[ $DELETE_NEEDED -eq 1 ]] && echo "YES — old build_pack='$OLD_BUILD_PACK', ${OLD_APP_UUID:-}" || echo "no")
      network        $STACK_NETWORK_NAME (external, attached to the stack's own network)
      env-var        unconditional overwrite (non-secret): $NETWORK_VAR_NAME
PLAN

if [[ $APPLY -eq 0 ]]; then
  printf '\n\033[33mPREFLIGHT ONLY.\033[0m Nothing was deleted, created, or set. Re-run with --apply to execute.\n'
  exit 0
fi

if [[ $DELETE_NEEDED -eq 1 ]]; then
  step "Deleting stale '$RESOURCE_NAME' ($OLD_APP_UUID) — zero deployments, zero env names, confirmed above"
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
  'project_uuid': '$PROJECT_UUID', 'environment_uuid': '$ENV_UUID',
  'server_uuid': '$SERVER_UUID',
  'git_repository': '$GIT_REPOSITORY', 'git_branch': '$GIT_BRANCH',
  'build_pack': 'dockercompose', 'name': '$RESOURCE_NAME',
  'base_directory': '$BASE_DIRECTORY',
  'docker_compose_location': '$DOCKER_COMPOSE_LOCATION',
  'instant_deploy': False,
}))")"
  APP_UUID="$(api POST /applications/public "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
  [[ "$APP_UUID" =~ $UUID_RE ]] || die "created-application uuid '$APP_UUID' does not match the expected uuid shape -- refusing to use it in later API calls."
  ok "application created — $APP_UUID (compose parse queued, not deployed — a deploy vehicle is a separate, PENDING follow-up per docs/deployment-runbook.md §7.2)"
fi

step "Reporting settings.include_source_commit_in_build (NOT forced — see header)"
SOURCE_COMMIT_JSON="$(api GET "/applications/$APP_UUID")"
if echo "$SOURCE_COMMIT_JSON" | "$REPO_ROOT/scripts/ci/check-source-commit-in-build.sh" >/tmp/worker-source-commit-check.$$ 2>&1; then
  info "settings.include_source_commit_in_build — true (harmless here; this worker's Dockerfile has no SOURCE_COMMIT/GIT_SHA guard)"
else
  info "settings.include_source_commit_in_build — not true ($(cat /tmp/worker-source-commit-check.$$ | tr -d '\n')) — not a blocker, this worker's Dockerfile has no such guard"
fi
rm -f /tmp/worker-source-commit-check.$$

step "Setting $NETWORK_VAR_NAME (non-secret, unconditional overwrite)"
# Body built into a variable FIRST, same shape CREATE_BODY above uses --
# NEVER an inline command-substitution argument to api() (the macOS
# /bin/bash 3.2 argument-position brace-expansion defect provision-app.sh's
# own header documents in full: an inline `api PATCH "..." "$(python3 -c
# "...")"` mis-parses under bash 3.2, splitting the dict literal's braces
# at the comma into two SyntaxErrors and silently sending an EMPTY PATCH
# body, which Coolify 400s on. This script never uses that shape.)
ENV_BODY="$(python3 -c "
import json
print(json.dumps({'data': [{'key': '$NETWORK_VAR_NAME', 'value': '$STACK_NETWORK_NAME'}]}))")"
api PATCH "/applications/$APP_UUID/envs/bulk" "$ENV_BODY" >/dev/null
ENVS_AFTER="$(api GET "/applications/$APP_UUID/envs")"
READBACK="$(echo "$ENVS_AFTER" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['key']=='$NETWORK_VAR_NAME']
print(m[0]['value'] if m else '')")"
[[ "$READBACK" == "$STACK_NETWORK_NAME" ]] \
  || die "wrote $NETWORK_VAR_NAME='$STACK_NETWORK_NAME' but read back '$READBACK' -- byte-exact mismatch, refusing to trust the store."
ok "$NETWORK_VAR_NAME set and byte-exact read-back verified — $STACK_NETWORK_NAME"

step "Clearing any default Coolify-assigned domain/ports_exposes (CA-1, run-8 stop, 2026-09-21)"
# MEASURED (team-lead, run-8, realrun8.clean.log): Coolify 4.3.18 assigns
# a DEFAULT `fqdn` (`http://<uuid>.<box-ip>.sslip.io`) and
# `ports_exposes` ("80") to every application AT CREATE, whether or not
# a domain was ever requested -- none of the three worker resources'
# create bodies above ask for one. No Traefik labels exist and the proxy
# 404s for these hosts (no LIVE exposure), but the RESOURCE RECORD
# itself claims a public domain -- and `workers/provider-sync/src/http/
# admissionGuard.ts`'s CA-1 guard correctly refuses to boot on exactly
# that signal (`COOLIFY_FQDN` non-empty), which is what crash-looped
# provider-sync in run-8. Fixed here, not in the guard -- Sec's own
# pre-review for this PR refuses in advance any change to
# PUBLIC_ROUTE_ENV_MATCHERS or any value-based exception: the guard's
# own header already says "never narrow to exact names," and this is
# the correct place to fix it -- the resource should never have carried
# a domain in the first place.
#
# TWO FIELDS, TWO DIFFERENT MECHANISMS -- MEASURED LIVE (team-lead,
# provider-sync hmjeuhdaolhw8tlz3qi6lopi, 2026-09-21), not guessed:
#   ports_exposes -- `PATCH {"ports_exposes": ""}` on
#     `/applications/<uuid>` -> HTTP 200, read-back confirms cleared.
#     WORKS via the public API. This is the mechanism below.
#   fqdn -- has NO public-API clear path for a `dockercompose`
#     application. `PATCH {"fqdn": ""}` -> HTTP 422 "This field is not
#     allowed." `PATCH {"domains": ""}` -> HTTP 422 "The domains field
#     cannot be used for dockercompose applications. Use
#     docker_compose_domains instead." `docker_compose_domains` IS
#     PATCHable (as a real JSON array, `[]`) but it is PER-SERVICE
#     compose routing, not the app-level `fqdn` column -- clearing it
#     left `fqdn` unchanged. The only mechanism that actually clears it
#     is a box-side Laravel tinker WRITE directly against the Eloquent
#     model -- a direct DB/model-layer mutation that bypasses the API's
#     own validation and authorization entirely, a materially different,
#     more privileged mechanism than every other write this script
#     makes. Sec-RULED acceptable (PR #862 review) under three
#     conditions, all held below: (a) narrow and literal -- the tinker
#     body sets ONLY `$app->fqdn = null` on a resolved-by-uuid record,
#     the pre-validated `$APP_UUID` (matched against `UUID_RE` above)
#     is the ONLY interpolation, no dynamic field/array; (b) the done-
#     predicate asserts the API read-back (this script) AND the running
#     container's env, split by WHERE each is actually checkable --
#     see below; (c) a tree-wide, sha256-pinned allowlist fence
#     (`scripts/ci/fence-tinker-write-allowlist.sh`) so a future
#     unmarked write, or this marker copy-pasted onto a new site,
#     cannot land silently. Marker `TINKER-WRITE-ALLOW-07`.
#
# ports_exposes is invisible to the admission guard (env-name based --
# it never injects a COOLIFY_*PORTS* variable) and, per team-lead's own
# measurement, not currently exploitable (no Traefik labels exist
# regardless of its value while no domain is assigned) -- cleared anyway
# for defense-in-depth: a bare ports_exposes='80' left in place is a
# residual that a FUTURE domain (re-)assignment could turn into live
# exposure without anyone re-checking this value at that time.
#
# PROVENANCE (Sec pre-review requirement): this step clears the
# Coolify-side RESOURCE field only. It never writes a
# `COOLIFY_FQDN=''`-shaped override into this resource's OWN env store
# -- doing so would make the guard's "empty value" pass a LIE about
# where the emptiness came from (a config override, not Coolify's own
# injection), which is explicitly refused, not a shortcut available
# here.
#
# (classify_domain_state()/PY_CLASSIFY_HELPER now live earlier in this
# file, right after jqp() -- --state needs them before this step exists,
# see that definition's own header for the ABSENT/EMPTY/SET rationale.)

CURRENT_APP_JSON="$(api GET "/applications/$APP_UUID")"
CURRENT_CLASSIFIED="$(echo "$CURRENT_APP_JSON" | classify_domain_state)"
CURRENT_FQDN_STATE="$(sed -n '1p' <<<"$CURRENT_CLASSIFIED" | cut -f1)"
CURRENT_FQDN_VAL="$(sed -n '1p' <<<"$CURRENT_CLASSIFIED" | cut -f2)"
CURRENT_PORTS_STATE="$(sed -n '2p' <<<"$CURRENT_CLASSIFIED" | cut -f1)"
CURRENT_PORTS_VAL="$(sed -n '2p' <<<"$CURRENT_CLASSIFIED" | cut -f2)"
info "current state: fqdn=$CURRENT_FQDN_STATE${CURRENT_FQDN_VAL:+ ('$CURRENT_FQDN_VAL')}, ports_exposes=$CURRENT_PORTS_STATE${CURRENT_PORTS_VAL:+ ('$CURRENT_PORTS_VAL')}"

if [[ "$CURRENT_PORTS_STATE" == "SET" ]]; then
  # Body built into a variable FIRST -- same bash-3.2 argument-position
  # discipline this file's own header documents, and no bash variable's
  # VALUE is spliced into the python source (the literal body is
  # static; only the fixed field name is written by this script, not
  # anything read from the API response).
  PORTS_CLEAR_BODY='{"ports_exposes": ""}'
  api PATCH "/applications/$APP_UUID" "$PORTS_CLEAR_BODY" >/dev/null
  AFTER_PORTS_JSON="$(api GET "/applications/$APP_UUID")"
  AFTER_PORTS_CLASSIFIED="$(echo "$AFTER_PORTS_JSON" | classify_domain_state)"
  AFTER_PORTS_STATE="$(sed -n '2p' <<<"$AFTER_PORTS_CLASSIFIED" | cut -f1)"
  AFTER_PORTS_VAL="$(sed -n '2p' <<<"$AFTER_PORTS_CLASSIFIED" | cut -f2)"
  if [[ "$AFTER_PORTS_STATE" == "SET" ]]; then
    die "PATCHed {\"ports_exposes\": \"\"} on '$RESOURCE_NAME' ($APP_UUID) but the read-back still shows ports_exposes SET ('$AFTER_PORTS_VAL') -- this mechanism was measured working on provider-sync (2026-09-21); a different result here means something about THIS resource differs, investigate before re-running."
  fi
  ok "ports_exposes cleared via PATCH and byte-exact read-back verified not SET (measured-working mechanism)"
else
  ok "ports_exposes already $CURRENT_PORTS_STATE — nothing to clear"
fi

if [[ "$CURRENT_FQDN_STATE" == "SET" ]]; then
  # Sec-ruled mechanism (PR #862 review, conditions a/c) -- box-side
  # Laravel tinker WRITE. MEASURED 2026-09-21 (why the API can't do
  # this): PATCH {"fqdn":""} -> HTTP 422 'This field is not allowed.';
  # PATCH {"domains":""} -> HTTP 422 'Use docker_compose_domains
  # instead'; docker_compose_domains is per-SERVICE routing, not this
  # app-level field, and clearing it does not touch fqdn.
  #
  # Condition (a): the tinker body sets ONLY `$app->fqdn = null` --
  # never ports_exposes (that stays on the API PATCH above, per Sec's
  # explicit instruction not to fold it in here) -- on a record
  # resolved by the pre-validated `$APP_UUID` (matched against UUID_RE
  # above), the ONLY interpolation. No dynamic field name, no array, no
  # value read from anywhere but this script's own validated variable.
  # `$app->refresh()` + an explicit CLEARED/STILL_SET echo makes the
  # write's own outcome self-reporting, not inferred from a bare exit
  # code. Marker TINKER-WRITE-ALLOW-07 (condition c) sits inline, at
  # the write itself, per fence-tinker-write-allowlist.sh's own catch
  # criterion (anchored on the write verb, not the --execute call).
  TINKER_OUT="$(sshx "docker exec coolify php artisan tinker --execute='/* TINKER-WRITE-ALLOW-07 */\$app = \\App\\Models\\Application::where(\"uuid\",\"$APP_UUID\")->firstOrFail(); \$app->fqdn = null; \$app->save(); \$app->refresh(); echo \$app->fqdn === null ? \"CLEARED\" : \"STILL_SET\";'" </dev/null 2>&1 | tail -1 | tr -d ' \n')"
  if [[ "$TINKER_OUT" != "CLEARED" ]]; then
    die "tinker fqdn-clear write on '$RESOURCE_NAME' ($APP_UUID) did not report CLEARED (got '$TINKER_OUT') -- the model-layer write may have failed, or firstOrFail() found no matching record. Investigate on the box before re-running."
  fi

  # Condition (b), API half -- die-level, this script's own authority.
  # The container-env half is NOT checkable here (see WARNING below and
  # this step's own header) -- it lives in run_deploy_workers, where a
  # fresh container is guaranteed to exist post-deploy.
  AFTER_FQDN_JSON="$(api GET "/applications/$APP_UUID")"
  AFTER_FQDN_CLASSIFIED="$(echo "$AFTER_FQDN_JSON" | classify_domain_state)"
  AFTER_FQDN_STATE="$(sed -n '1p' <<<"$AFTER_FQDN_CLASSIFIED" | cut -f1)"
  AFTER_FQDN_VAL="$(sed -n '1p' <<<"$AFTER_FQDN_CLASSIFIED" | cut -f2)"
  if [[ "$AFTER_FQDN_STATE" == "SET" ]]; then
    die "tinker fqdn-clear write reported CLEARED but the API read-back still shows fqdn SET ('$AFTER_FQDN_VAL') -- API/DB drift (e.g. a cache), investigate before re-running."
  fi
  ok "fqdn cleared via tinker write and API read-back verified $AFTER_FQDN_STATE"

  # Sec ruling (option C, PR #862 review): a container may already be
  # running for this resource, still carrying the PRE-clear env --
  # Coolify only injects env at container START, and this script never
  # deploys, so that is an EXPECTED state here, not a failure of this
  # step. It IS a live exposure window though (the API record now says
  # cleared, but the running container still answers on the old
  # route), so warn loudly rather than staying silent -- the die-level
  # assertion on this lives in run_deploy_workers, post-deploy.
  EXISTING_CID="$(sshx "docker ps --filter 'name=$APP_UUID' --filter 'status=running' --format '{{.ID}}' | head -1" </dev/null 2>/dev/null || true)"
  if [[ -n "$EXISTING_CID" ]]; then
    STALE_ROUTE_ENV="$(sshx "docker exec $EXISTING_CID env | grep -E '^(COOLIFY_FQDN|COOLIFY_URL)=.' || true" </dev/null 2>/dev/null || true)"
    if [[ -n "$STALE_ROUTE_ENV" ]]; then
      warn "container $EXISTING_CID is still running with a non-empty route signal -- API-level cleared, but the OLD route remains live until this resource is redeployed. Names: $(printf '%s' "$STALE_ROUTE_ENV" | cut -d= -f1 | tr '\n' ' ')-- not a failure of this step (Coolify only injects env at container start); redeploy to close this window."
    else
      ok "running container $EXISTING_CID already carries no non-empty COOLIFY_FQDN/URL -- no exposure window open"
    fi
  else
    info "no container currently running for this resource -- container-env half of the done-predicate is not applicable until first deploy"
  fi
else
  ok "fqdn already $CURRENT_FQDN_STATE — nothing to clear"
fi

step "Done"
info "Resource '$RESOURCE_NAME' ($APP_UUID) is a dockercompose application, network var set, NOT yet deployed."
info "Record its uuid with scripts/record-coolify-uuids.sh --apply (resolves by name)."
info "Next: docs/deployment-runbook.md §7.2's remaining PENDING steps (secrets, role handoff, deploy, smoke)."
