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
#   No secret value is ever PRINTED or LOGGED. Every step that touches secret
#   material (minting, setting env vars, reading env vars back to assert
#   they're non-empty) runs as ONE remote script over SSH that never echoes a
#   value -- only key names and true/false presence. The Coolify API token is
#   read FROM THE BOX on every call (/root/.pfin/coolify.env, written by
#   provision-vps.sh's admin-bootstrap step) — never from a local .env; that
#   file's COOLIFY_API_TOKEN entry (a hand-run-era artifact) can be deleted
#   once this script has run once. Nothing is created or mutated without
#   --apply; the default is a preflight that only reads.
#
#   ⚠ CORRECTED 2026-09-11 -- this paragraph used to also claim no secret is
#   ever "returned to this script's local process." That was true when
#   written and stopped being true the moment this script gained an
#   operator-provided secret: SMTP_PASS (the Resend API key -- see the SMTP_*
#   paragraph below) is read from the repo-root .env into a LOCAL bash
#   variable, exactly like provision-vps.sh already does for
#   COOLIFY_ADMIN_PASSWORD. Never echoed, never logged, held only long enough
#   to pipe it over SSH stdin into a file on the box (same mechanism, same
#   file, same discipline provision-vps.sh's own "THE PASSWORD BOUNDARY"
#   comment documents for that value) -- but it DOES pass through this
#   script's memory, and the old absolute claim was wrong to leave standing.
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
#   This mints/sets the 8 Supabase-stack secrets named in secrets-manifest.yml's
#   production_only set (POSTGRES_PASSWORD, JWT_SECRET, SECRET_KEY_BASE,
#   VAULT_ENC_KEY, SERVICE_ROLE_KEY, ANON_KEY, DASHBOARD_PASSWORD,
#   PG_META_CRYPTO_KEY), plus ~20 non-secret compose-required config vars
#   (Studio defaults, POSTGRES_HOST/PORT/DB, POOLER_*, PGRST_DB_*, JWT_EXPIRY,
#   MAILER_URLPATHS_*, ENABLE_*/DISABLE_* auth flags — see NONSECRET_DEFAULTS
#   below for the full set and where each value comes from). It is NOT §5's
#   general secrets-provisioning procedure (still a STUB, still Sec-gated)
#   and does not touch the four app-service secrets or anything outside
#   this one Coolify resource.
#
#   ⚠ SMTP_* — set with Supabase's own reference NON-FUNCTIONAL placeholder
#   values (SMTP_HOST=supabase-mail etc.) by default, NOT real credentials.
#   Measured 2026-09-11: `auth` (GoTrue) FATALs on startup if SMTP_PORT isn't
#   a parseable integer -- unlike the URL vars below, SMTP config blocks the
#   stack from coming up at all, not just from sending real mail, so this
#   script cannot leave it genuinely unset the way its scope note used to
#   claim.
#
#   ⚠ OPERATOR OVERRIDE, added 2026-09-11 (F/CTO ask: "where do I enter the
#   Resend token, and as what variable?"). SMTP_PASS is OPERATOR-PROVIDED --
#   like HETZNER_API_TOKEN/COOLIFY_ADMIN_PASSWORD -- not box-generated the
#   way POSTGRES_PASSWORD/JWT_SECRET are, so it follows THAT pattern, not
#   mint-if-absent: read from the repo-root .env (see
#   scripts/provision.env.example), and if present, unconditionally
#   OVERWRITES the placeholders -- SMTP_PASS itself, plus SMTP_HOST/
#   SMTP_PORT/SMTP_USER hardcoded to Resend's own values (this .env doesn't
#   carry a provider CHOICE, only the key -- see docs/email-smtp-runbook.md's
#   Provider B section to switch to SES, which means editing this script,
#   not .env), plus the operator's own SMTP_ADMIN_EMAIL/SMTP_SENDER_NAME if
#   those are also set in .env. If SMTP_PASS is absent from .env, this
#   script changes nothing about SMTP_* (the mint-if-absent placeholders
#   below still apply, unchanged) and prints a one-line reminder, every run,
#   naming docs/email-smtp-runbook.md -- the documented, safe-inert state:
#   the stack starts; auth email silently doesn't send until this is set.
#   SMTP_PASS is production_only in secrets-manifest.yml (Sec joint-review);
#   the other five SMTP_* vars are non-secret provider config, same
#   reasoning that file already applies to SUPABASE_ANON_KEY/
#   STUDIO_DEFAULT_ORGANIZATION.
#
#   ⚠ SITE_URL / API_EXTERNAL_URL / SUPABASE_PUBLIC_URL — set to Supabase's
#   OWN reference docker/.env.example localhost defaults (see the
#   NONSECRET_DEFAULTS comment below for the measurement that forced this:
#   `auth` FATALs on startup with none of the three set, the same class as
#   POSTGRES_PORT/SMTP_PORT above). ⚠ CORRECTED 2026-09-11 -- an earlier
#   revision of this paragraph said these were "deliberately NOT set by
#   this script at all," true when written and false since the FATAL was
#   measured; left uncorrected until now. mint-if-absent means the
#   placeholders never overwrite a box that already has real values (prod
#   already does, from the hand-run era). These are box/domain-specific and
#   affect OAuth-callback and email-confirmation link correctness; picking
#   the REAL public-facing scheme (once pfindash.com DNS/domain routing is
#   decided) is a separate, still-open ARCH/F/CTO call this script's
#   placeholder values do not make.
#
# WHAT THIS SCRIPT HAS NOT BEEN EXERCISED AGAINST
#   The project/environment/application CREATE path (all three already exist
#   in production, so every run against this box adopts them — the create
#   branch is researched against Coolify's own source, not proven against a
#   live instance). Say so if you hit it and it's wrong; don't assume it's
#   right because the rest of the script is.
#
# USAGE
#   BOX_IP is REQUIRED, not defaulted (2026-09-11 incident: a missing
#   override used to fall through silently to prod's IP -- see the check
#   right after this script's die()/ok()/info()/step() definitions).
#   BOX_IP=<box-ip> scripts/provision-supabase-stack.sh          # preflight: read-only
#   BOX_IP=<box-ip> scripts/provision-supabase-stack.sh --apply  # create/mint/deploy
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOX_IP="${BOX_IP:-}"
AUTOMATION_KEY="${AUTOMATION_KEY:-$HOME/.ssh/id_ed25519_claude_mosko-fintech}"
PROJECT_NAME="${PROJECT_NAME:-pfin-supabase}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
APP_NAME="${APP_NAME:-pfin-supabase-stack}"
# Measured 2026-09-11 against a genuinely fresh scratch box: Coolify's
# /applications/public validator rejects the GitHub short form
# ("owner/repo") outright -- "must start with https://, http://, git://, or
# git@." -- a full URL is required, not a slug.
GIT_REPOSITORY="${GIT_REPOSITORY:-https://github.com/richmosko/mosko-fintech}"
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

# Same helper, same file, same `|| true` pipefail guard as
# provision-vps.sh's own read_env_var() -- a no-match grep (the normal
# "not set in .env" case) must not abort this script under set -e/pipefail.
read_env_var() { grep -m1 "^$1=" "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true; }

# Operator-provided SMTP credential (scripts/provision.env.example) --
# OPERATOR-provided like HETZNER_API_TOKEN/COOLIFY_ADMIN_PASSWORD, not
# box-generated like POSTGRES_PASSWORD/JWT_SECRET below. Read here,
# unconditionally, so the Plan step can show its status even during
# preflight (APPLY=0 exits before anything is pushed to the box) -- never
# echoed, matching COOLIFY_ADMIN_PASSWORD's own discipline in
# provision-vps.sh. See this script's own "OPERATOR OVERRIDE" header
# comment for the full mechanism.
SMTP_PASS="$(read_env_var SMTP_PASS)"
SMTP_ADMIN_EMAIL_OVERRIDE="$(read_env_var SMTP_ADMIN_EMAIL)"
SMTP_SENDER_NAME_OVERRIDE="$(read_env_var SMTP_SENDER_NAME)"
if [[ -n "$SMTP_PASS" ]]; then
  SMTP_STATUS="real Resend credentials found in .env -- will OVERWRITE the stack's SMTP_* placeholders"
else
  SMTP_STATUS="none in .env -- placeholders stay (stack starts; real auth email won't send) -- see docs/email-smtp-runbook.md"
fi

# INCIDENT, 2026-09-11: BOX_IP used to default to prod's IP
# (188.245.166.206) when unset. Running this script against a scratch box
# with BOX_IP correctly overridden still left ONE downstream call (to
# coolify-materialize-supabase-mounts.sh) on ITS OWN separate hardcoded
# prod default, because that call didn't explicitly pass BOX_IP through --
# it fell through silently and wrote files to prod. That specific call is
# fixed below (passes COOLIFY_SSH_HOST explicitly now), but the GENERAL
# fix is here: BOX_IP is no longer defaulted at all, anywhere in this
# script. A missing override now fails loud, immediately, before anything
# runs -- not a silent fall-through to prod from whichever line happens to
# have (or lack) its own default. Every downstream call in this script
# already routes through this one variable via the sshx()/sshx_in()
# helpers below; requiring it here is what makes "no BOX_IP set"
# impossible to reach any of them by accident.
[[ -n "$BOX_IP" ]] || die "BOX_IP is required, not defaulted (deliberately, after 2026-09-11's incident) -- set it explicitly, e.g. BOX_IP=188.245.166.206 for prod or BOX_IP=<scratch-ip> for a scratch box. No default means no silent fall-through to prod."

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

# Measured 2026-09-11 against a genuinely fresh scratch box: Coolify's
# create_application (public branch) NORMALIZES git_repository on save --
# it parses the submitted URL and stores just the URL path's owner/repo
# segments (app/Http/Controllers/Api/ApplicationsController.php:
# `$application->git_repository = ...->getSegment(1).'/'.->getSegment(2)`),
# regardless of the full-URL form the create validator requires on input.
# GET on an existing application therefore returns the SHORT form even
# though this script must POST the full https:// form to pass validation
# (see the create block below). Comparing $GIT_REPOSITORY (full URL)
# against that short-form response made every re-run report a false
# MISMATCH and refuse to proceed on an application that was actually
# correctly configured. Compare against a normalized (stripped-prefix)
# copy instead -- the POST body below still uses the full URL, unchanged.
GIT_REPOSITORY_STORED="${GIT_REPOSITORY#https://github.com/}"
GIT_REPOSITORY_STORED="${GIT_REPOSITORY_STORED#http://github.com/}"
GIT_REPOSITORY_STORED="${GIT_REPOSITORY_STORED%.git}"

APP_JSON="$(api GET /applications | jqp "
d=json.load(sys.stdin)
m=[a for a in d if a['name']=='$APP_NAME']
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
      smtp          $SMTP_STATUS
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
  # Re-check for an existing environment before creating one. Measured
  # 2026-09-11 against a genuinely fresh scratch box: Coolify auto-creates
  # a default "production" environment the moment a project is created --
  # a blind POST here 409'd against that auto-created row. The preflight
  # lookup above only runs when the project ALREADY EXISTED at preflight
  # time; a first-ever run against a brand-new project never populates
  # ENV_UUID before reaching this line, so "empty here" does not mean
  # "needs creating" -- look it up for real, the same way preflight does,
  # rather than assuming.
  ENV_JSON="$(api GET "/projects/$PROJECT_UUID/environments" | jqp "
d=json.load(sys.stdin)
m=[e for e in d if e['name']=='$ENVIRONMENT_NAME']
print(json.dumps(m[0]) if m else '')")"
  if [[ -n "$ENV_JSON" ]]; then
    ENV_UUID="$(echo "$ENV_JSON" | jqp "print(json.load(sys.stdin)['uuid'])")"
    ok "environment '$ENVIRONMENT_NAME' already existed (Coolify auto-creates one per new project) — $ENV_UUID"
  else
    ENV_UUID="$(api POST "/projects/$PROJECT_UUID/environments" "{\"name\":\"$ENVIRONMENT_NAME\"}" | jqp "print(json.load(sys.stdin)['uuid'])")"
    ok "environment created — $ENV_UUID"
  fi
fi
if [[ -z "${APP_UUID:-}" ]]; then
  # Measured 2026-09-11 against a genuinely fresh scratch box (this create
  # path was UNEXERCISED against a live instance before then -- see the
  # header): the original version of this step POSTed to
  # /applications/private-github-app using the box's default "Public
  # GitHub" github_apps row (id=0, no private_key -- that row exists
  # precisely so PUBLIC repos don't need one). Coolify's own controller
  # (app/Http/Controllers/Api/ApplicationsController.php) rejected that
  # combination with a 500: "Attempt to read property \"private_key\" on
  # null" -- the private-github-app endpoint expects a REAL GitHub App
  # integration (OAuth credentials + a private key), which a public repo
  # deliberately has none of. Source-verified in routes/api.php: Coolify
  # ships a SEPARATE endpoint for exactly this case --
  # POST /applications/public (create_public_application), which needs no
  # github_app_uuid at all. This repo (mosko-fintech) is public, so that is
  # the correct endpoint, not a workaround.
  #
  # server_uuid / destination_uuid resolved by name/singleton lookup, not
  # hardcoded, so a rebuild on a differently-shaped instance still works.
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
  'build_pack': 'dockercompose', 'name': '$APP_NAME',
  'base_directory': '$BASE_DIRECTORY',
  'docker_compose_location': '$DOCKER_COMPOSE_LOCATION',
  'instant_deploy': False,
}))")"
  APP_UUID="$(api POST /applications/public "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
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
# INCIDENT, 2026-09-11: this call passed COOLIFY_APP_UUID but not
# COOLIFY_SSH_HOST -- coolify-materialize-supabase-mounts.sh's own default
# for that var is root@188.245.166.206 (PROD's IP, hardcoded there as the
# ordinary case since that script is normally run standalone against
# prod). Run against a scratch box with only COOLIFY_APP_UUID overridden,
# this correctly materialized the SCRATCH app's manifest -- onto PROD's
# filesystem, under a path scoped to the scratch app's UUID
# (/data/coolify/applications/<scratch-uuid>/volumes/**). No real Coolify
# resource on prod references that UUID, so nothing there should have
# consumed the files, but they were still an unintended write to prod's
# disk from this script, and must not recur. Fixed by threading BOX_IP
# through explicitly rather than relying on the sibling script's own
# default matching by coincidence.
COOLIFY_APP_UUID="$APP_UUID" COOLIFY_SSH_HOST="root@$BOX_IP" "$REPO_ROOT/scripts/coolify-materialize-supabase-mounts.sh" --apply

step "SMTP: operator-provided credential (if any)"
# Crosses the local->box boundary the same way provision-vps.sh's own
# COOLIFY_ADMIN_PASSWORD does: piped over SSH stdin into a file on the box
# (never a command-line arg on either side, never heredoc-embedded literal
# text), read back by PATH only (never by value) everywhere downstream.
# SMTP_SEED_FILE itself is just a path -- safe to interpolate into the
# unquoted heredoc below the way APP_UUID/NEED_MINT already are.
if [[ -n "$SMTP_PASS" ]]; then
  SMTP_SEED_FILE="/root/.pfin/_smtp_seed.env.$$"
  {
    printf 'SMTP_PASS=%s\n' "$SMTP_PASS"
    printf 'SMTP_ADMIN_EMAIL=%s\n' "$SMTP_ADMIN_EMAIL_OVERRIDE"
    printf 'SMTP_SENDER_NAME=%s\n' "$SMTP_SENDER_NAME_OVERRIDE"
  } | sshx "umask 077; mkdir -p /root/.pfin; cat > $SMTP_SEED_FILE"
  ok "pushed operator-provided SMTP credential to the box -- will overwrite placeholders below"
else
  SMTP_SEED_FILE=""
  info "no SMTP_PASS in .env -- leaving the stack's non-functional SMTP placeholders in place. See docs/email-smtp-runbook.md to wire real delivery."
fi

step "Secrets: mint-if-absent, set env vars, assert non-empty -- all on the box, no value ever leaves it"
# Measured 2026-09-11 against a genuinely fresh scratch box: the OLD
# "absent" check asked the API which KEYS have a row at all
# (GET .../envs), then skipped minting any key that already had one. But
# Coolify's own compose parser PRE-CREATES an EMPTY EnvironmentVariable
# row for every var the compose file references as an interpolation
# placeholder (e.g. api-gw's `SERVICE_ROLE_KEY: ${SERVICE_ROLE_KEY}`) the
# moment the application is created -- BEFORE this script ever runs. The
# row existing was mistaken for the SECRET existing, so every mint was
# skipped and every required key was left genuinely empty -- caught only
# by the assert-non-empty step at the bottom, which is exactly why that
# step exists, but the mint DECISION itself needs to ask the SAME
# question (real decrypted non-emptiness, not row presence) to be
# correct. Fixed: determine what needs minting via Eloquent decryption
# FIRST (same non-echoing tinker --execute mechanism the assert step
# already used), THEN mint only those, THEN re-assert.
#
# Sec REQUIRED fix (pre-prod review, 2026-09-11): this body, like the
# assert-non-empty body below, has bare top-level statements ($app = ...,
# $check = [...]) whose return values --execute may auto-echo the same way
# it auto-echoed $user = $user->createToken(...) in provision-vps.sh's own
# incident. Its output IS captured into NEED_MINT below -- whether an
# auto-echoed $app (an Eloquent model with decrypted attributes on it,
# depending on Application's $appends/$with, unverifiable from here) would
# leak a secret into that capture is exactly the assumption
# provision-vps.sh's own fix refused to make. Same fix: wrap the whole body
# in one IIFE so there is exactly one top-level statement, whose value is
# an explicit null -- the intended `echo $key` name-only prints inside it
# still work; nothing else can echo regardless of how many intermediate
# statements execute or whether --execute echoes every one or only the last.
NEED_MINT="$(sshx_in <<REMOTE
docker exec coolify php artisan tinker --execute="
(function () {
\\\$app = \\App\\Models\\Application::where('uuid','$APP_UUID')->firstOrFail();
\\\$check = ['POSTGRES_PASSWORD','JWT_SECRET','SECRET_KEY_BASE','VAULT_ENC_KEY','SERVICE_ROLE_KEY','ANON_KEY','DASHBOARD_PASSWORD','PG_META_CRYPTO_KEY','STUDIO_DEFAULT_ORGANIZATION','STUDIO_DEFAULT_PROJECT','DASHBOARD_USERNAME','DISABLE_SIGNUP','ENABLE_ANONYMOUS_USERS','ENABLE_EMAIL_AUTOCONFIRM','ENABLE_EMAIL_SIGNUP','ENABLE_PHONE_AUTOCONFIRM','ENABLE_PHONE_SIGNUP','JWT_EXPIRY','MAILER_URLPATHS_CONFIRMATION','MAILER_URLPATHS_EMAIL_CHANGE','MAILER_URLPATHS_INVITE','MAILER_URLPATHS_RECOVERY','PGRST_DB_EXTRA_SEARCH_PATH','PGRST_DB_MAX_ROWS','PGRST_DB_SCHEMAS','POOLER_DB_POOL_SIZE','POOLER_DEFAULT_POOL_SIZE','POOLER_MAX_CLIENT_CONN','POOLER_TENANT_ID','POSTGRES_DB','POSTGRES_HOST','POSTGRES_PORT','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASS','SMTP_SENDER_NAME','SMTP_ADMIN_EMAIL','SUPABASE_PUBLIC_URL','API_EXTERNAL_URL','SITE_URL'];
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

sshx_in <<REMOTE
set -e
umask 077
mkdir -p /root/.pfin
TOKEN="\$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"
APP_UUID="$APP_UUID"
NEED_MINT="$NEED_MINT"
SMTP_SEED_FILE="$SMTP_SEED_FILE"

python3 - "\$TOKEN" "\$APP_UUID" "\$NEED_MINT" "\$SMTP_SEED_FILE" <<'PYEOF'
import json, subprocess, sys, secrets as pysecrets

token, app_uuid, need_mint_raw, smtp_seed_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
need_mint = set(need_mint_raw.split())

def api(method, path, body=None):
    cmd = ["curl", "-fsS", "-X", method, "-H", f"Authorization: Bearer {token}"]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    cmd += [f"http://localhost:8000/api/v1{path}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out) if out.strip() else None

# Measured 2026-09-11: MOST secrets have no length requirement (any random
# value is fine, 64 hex chars is generous), but VAULT_ENC_KEY does --
# Supavisor's Cloak/AES-256-GCM config needs EXACTLY 32 characters used
# directly as raw key bytes (Supabase's own reference doc: "Must be
# exactly 32 characters; generate with: openssl rand -hex 16" -- 16 BYTES
# hex-encoded is 32 CHARACTERS). The original 64-char value (token_hex(32),
# 32 bytes hex-encoded) crashed supavisor on startup:
# "Unknown cipher or invalid key size". Per-key byte count, not one
# constant for all of MINT_SECRETS.
MINT_SECRETS = {"POSTGRES_PASSWORD": 32, "JWT_SECRET": 32, "SECRET_KEY_BASE": 32,
                "VAULT_ENC_KEY": 16, "SERVICE_ROLE_KEY": 32, "ANON_KEY": 32,
                "DASHBOARD_PASSWORD": 32, "PG_META_CRYPTO_KEY": 32}
# Measured 2026-09-11 against a genuinely fresh scratch box: this script's
# own header claims its scope is "exactly the Supabase-stack secrets ...
# plus the two non-secret Studio vars" -- that was never actually
# sufficient. The compose file references ~30 non-secret config vars
# total; on prod every one of them was already set from the 2026-09
# hand-run era, so this gap was invisible until a genuinely fresh
# deploy hit it: 'db' itself failed to start
# ('FATAL: invalid value for parameter "port": ""') because
# POSTGRES_PORT was never set anywhere. Values below are Supabase's own
# documented defaults (github.com/supabase/supabase docker/.env.example,
# read live 2026-09-11), not guessed.
#
# SITE_URL / API_EXTERNAL_URL / SUPABASE_PUBLIC_URL: measured 2026-09-11
# that 'auth' FATALs on startup ("parse \"\": empty url") without at
# least one of these being a parseable URL -- unlike a wrong VALUE (a
# genuine ARCH/F/CTO call, still open), a MISSING one blocks the stack
# from starting at all, the same class as POSTGRES_PORT and SMTP_PORT
# above. Set to Supabase's OWN reference docker/.env.example literal
# defaults (http://localhost:8000 / :8000/auth/v1 / :3000) -- not an
# invented value, upstream's own documented dev/fresh-install default.
# mint-if-absent means this never overwrites prod's real values (already
# set from the hand-run era). The REAL public-facing URL scheme (once
# pfindash.com DNS/domain routing is decided) is still an open ARCH call.
NONSECRET_DEFAULTS = {"STUDIO_DEFAULT_ORGANIZATION": "mosko-fintech",
                       "STUDIO_DEFAULT_PROJECT": "pfin-supabase",
                       "DASHBOARD_USERNAME": "supabase",
                       "DISABLE_SIGNUP": "false",
                       "ENABLE_ANONYMOUS_USERS": "false",
                       "ENABLE_EMAIL_AUTOCONFIRM": "false",
                       "ENABLE_EMAIL_SIGNUP": "true",
                       "ENABLE_PHONE_AUTOCONFIRM": "true",
                       "ENABLE_PHONE_SIGNUP": "true",
                       "JWT_EXPIRY": "3600",
                       "MAILER_URLPATHS_CONFIRMATION": "/auth/v1/verify",
                       "MAILER_URLPATHS_EMAIL_CHANGE": "/auth/v1/verify",
                       "MAILER_URLPATHS_INVITE": "/auth/v1/verify",
                       "MAILER_URLPATHS_RECOVERY": "/auth/v1/verify",
                       "PGRST_DB_EXTRA_SEARCH_PATH": "public",
                       "PGRST_DB_MAX_ROWS": "1000",
                       "PGRST_DB_SCHEMAS": "public,graphql_public",
                       "POOLER_DB_POOL_SIZE": "5",
                       "POOLER_DEFAULT_POOL_SIZE": "20",
                       "POOLER_MAX_CLIENT_CONN": "100",
                       # Stable across rebuilds (not box-IP-derived) --
                       # this is a Supavisor tenant identifier, not a
                       # secret or a URL.
                       "POOLER_TENANT_ID": "pfin-supabase",
                       "POSTGRES_DB": "postgres",
                       "POSTGRES_HOST": "db",
                       "POSTGRES_PORT": "5432",
                       # NON-FUNCTIONAL PLACEHOLDERS (Supabase's own
                       # reference docker/.env.example values, read live
                       # 2026-09-11) -- mint-if-absent means these NEVER
                       # overwrite a box that already has real SMTP set
                       # (prod already does, from the hand-run era). Where
                       # they ARE absent, they exist ONLY so 'auth' can
                       # start at all (GoTrue FATALs on an unparseable
                       # SMTP_PORT) -- real outbound email needs a real
                       # provider, wired by an operator: see
                       # docs/email-smtp-runbook.md end to end (Resend is
                       # the V1 default, SES the documented alternative).
                       # SMTP_PASS is the one SECRET here (production_only
                       # in secrets-manifest.yml) -- the other five below
                       # are non-secret provider config an operator
                       # overwrites in Coolify per that runbook's table.
                       "SMTP_HOST": "supabase-mail",
                       "SMTP_PORT": "2500",
                       "SMTP_USER": "fake_mail_user",
                       "SMTP_PASS": "fake_mail_password",
                       "SMTP_SENDER_NAME": "fake_sender",
                       "SMTP_ADMIN_EMAIL": "admin@example.com",
                       "SUPABASE_PUBLIC_URL": "http://localhost:8000",
                       "API_EXTERNAL_URL": "http://localhost:8000/auth/v1",
                       "SITE_URL": "http://localhost:3000"}

to_set = {}
for key, nbytes in MINT_SECRETS.items():
    if key in need_mint:
        to_set[key] = pysecrets.token_hex(nbytes)
for key, default in NONSECRET_DEFAULTS.items():
    if key in need_mint:
        to_set[key] = default

# Operator-provided override (scripts/provision.env.example: SMTP_PASS) --
# unconditional OVERWRITE, not mint-if-absent, per F/CTO's ask: an operator
# who has set a real Resend key in .env wants it applied even on a re-run
# where the placeholder is already sitting there from before. smtp_seed_file
# is a PATH (never a secret itself) pushed over SSH stdin by the outer
# script -- see this file's own "OPERATOR OVERRIDE" header comment. Resend's
# own fixed HOST/PORT/USER: this .env carries the KEY, not a provider
# CHOICE -- see docs/email-smtp-runbook.md's Provider B section to switch
# providers, which means editing this script, not .env.
if smtp_seed_file:
    with open(smtp_seed_file) as f:
        seed = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
    to_set["SMTP_PASS"] = seed.get("SMTP_PASS", "")
    to_set["SMTP_HOST"] = "smtp.resend.com"
    to_set["SMTP_PORT"] = "465"
    to_set["SMTP_USER"] = "resend"
    if seed.get("SMTP_ADMIN_EMAIL"):
        to_set["SMTP_ADMIN_EMAIL"] = seed["SMTP_ADMIN_EMAIL"]
    if seed.get("SMTP_SENDER_NAME"):
        to_set["SMTP_SENDER_NAME"] = seed["SMTP_SENDER_NAME"]
    print("SMTP: operator-provided Resend credentials applied (overwrote placeholders)")

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
    print("MINTED: none -- all required keys already non-empty")
PYEOF
chmod 600 /root/.pfin/supabase.env 2>/dev/null || true
# Seed file cleanup -- same shred-then-rm-fallback convention
# provision-vps.sh's own SEED_ENV_FILE uses. No-op (empty path fails the
# -n test) when no operator SMTP_PASS was pushed this run.
if [ -n "\$SMTP_SEED_FILE" ]; then
  shred -u "\$SMTP_SEED_FILE" 2>/dev/null || rm -f "\$SMTP_SEED_FILE"
fi

# Re-assert non-empty via Eloquent decryption, never ciphertext length --
# proof the mint above actually worked, not just that it ran.
#
# Sec REQUIRED fixes (pre-prod review, 2026-09-11), both applied here:
#   (B) Same IIFE wrap as NEED_MINT above and provision-vps.sh's own fix --
#       this body's bare top-level statements could auto-echo an Eloquent
#       model under --execute; wrapping removes the dependency on an
#       unverifiable appends/with-cast assumption entirely.
#   (A) This step previously only PRINTED "KEY: OK/MISSING" -- nothing
#       ever died on a MISSING, so a partial PATCH failure or a future
#       required key added to the check list without a matching
#       mint/default would deploy anyway, empty. Today's MINT_SECRETS union
#       NONSECRET_DEFAULTS covers every checked key, so a normal run never
#       hits this -- but "doesn't happen today" is not fail-closed. Capture
#       the output, then die on any line ending ": MISSING" before the
#       poisoned-volume check / deploy step that follows.
ASSERT_OUT="\$(docker exec coolify php artisan tinker --execute="
(function () {
\\\$app = \\App\\Models\\Application::where('uuid','$APP_UUID')->firstOrFail();
\\\$required = ['POSTGRES_PASSWORD','JWT_SECRET','SECRET_KEY_BASE','VAULT_ENC_KEY','SERVICE_ROLE_KEY','ANON_KEY','DASHBOARD_PASSWORD','PG_META_CRYPTO_KEY','STUDIO_DEFAULT_ORGANIZATION','STUDIO_DEFAULT_PROJECT','DASHBOARD_USERNAME','DISABLE_SIGNUP','ENABLE_ANONYMOUS_USERS','ENABLE_EMAIL_AUTOCONFIRM','ENABLE_EMAIL_SIGNUP','ENABLE_PHONE_AUTOCONFIRM','ENABLE_PHONE_SIGNUP','JWT_EXPIRY','MAILER_URLPATHS_CONFIRMATION','MAILER_URLPATHS_EMAIL_CHANGE','MAILER_URLPATHS_INVITE','MAILER_URLPATHS_RECOVERY','PGRST_DB_EXTRA_SEARCH_PATH','PGRST_DB_MAX_ROWS','PGRST_DB_SCHEMAS','POOLER_DB_POOL_SIZE','POOLER_DEFAULT_POOL_SIZE','POOLER_MAX_CLIENT_CONN','POOLER_TENANT_ID','POSTGRES_DB','POSTGRES_HOST','POSTGRES_PORT','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASS','SMTP_SENDER_NAME','SMTP_ADMIN_EMAIL','SUPABASE_PUBLIC_URL','API_EXTERNAL_URL','SITE_URL'];
foreach (\\\$required as \\\$key) {
  \\\$env = \\\$app->environment_variables()->where('key', \\\$key)->first();
  \\\$nonEmpty = \\\$env && strlen((string) \\\$env->value) > 0;
  echo \\\$key . ': ' . (\\\$nonEmpty ? 'OK' : 'MISSING') . PHP_EOL;
}
return null;
})();
")"
echo "\$ASSERT_OUT"
if echo "\$ASSERT_OUT" | grep -q ': MISSING\$'; then
  echo "" >&2
  echo "FATAL: required secret(s)/config var(s) still empty after mint -- refusing to deploy:" >&2
  echo "\$ASSERT_OUT" | grep ': MISSING\$' >&2
  exit 1
fi
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
  # Measured 2026-09-11 against a genuinely fresh scratch box: `logs` in the
  # deployment API response is a JSON-encoded STRING (Coolify stores/returns
  # it that way), not an array -- `d.get('logs')` handed a raw string to the
  # `for l in ...` loop, which iterated CHARACTER BY CHARACTER (Python's
  # normal behavior for iterating a string), so `l.get('output','')` failed
  # with "'str' object has no attribute 'get'" on the first character. This
  # bug fired on every failed deployment, masking whatever the REAL failure
  # was behind a Python traceback about string iteration. Parse it as the
  # nested JSON it actually is before treating it as a list of log entries.
  api GET "/deployments/$DEPLOY_UUID" | jqp "
d=json.load(sys.stdin)
raw=d.get('logs') or '[]'
entries=json.loads(raw) if isinstance(raw,str) else (raw or [])
print('\n'.join(e.get('output','') for e in entries[-60:]))" || true
  die "deployment $DEPLOY_UUID status=$STATUS -- see log above"
fi
ok "deployment finished"

step "Verification battery"
# Measured 2026-09-11: right after "deployment finished", supavisor (last
# to pass its own health check's start_period) can still read as
# "starting" for several more seconds even though the deploy itself
# succeeded -- a single immediate check here reported 5/7 or 6/7 on a
# stack that was fully healthy 10-15s later. Poll rather than assume the
# deploy's own "finished" status means every container's healthcheck has
# also converged yet.
CONTAINERS=0
for _ in $(seq 1 15); do
  CONTAINERS="$(sshx "docker ps --filter 'label=com.docker.compose.project=$APP_UUID' --filter 'health=healthy' --format '{{.Names}}'" | wc -l | tr -d ' ')"
  [[ "$CONTAINERS" == "7" ]] && break
  sleep 3
done
info "$CONTAINERS/7 containers healthy (db auth rest api-gw supavisor studio meta)"
[[ "$CONTAINERS" == "7" ]] || die "expected 7 healthy containers, got $CONTAINERS after 45s of polling"
ok "all 7 containers healthy"

PGVER="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc 'show server_version;'" 2>/dev/null | cut -d. -f1)"
[[ "$PGVER" == "17" ]] || die "expected Postgres 17, got server_version starting '$PGVER'"
ok "Postgres major version 17"

# State-based init check, not filename grep -- the filename check (§4 (1b))
# only works on a FRESH db-data volume; this works regardless.
INIT_STATE="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"select rolname||':'||(rolpassword is not null) from pg_authid where rolname in ('authenticator','pgbouncer','supabase_auth_admin','supabase_functions_admin') order by rolname;\"")"
# Two bugs, both measured 2026-09-11 against the real scratch box, fixed
# together:
#   1. `(rolpassword is not null)` concatenated into text with `||` prints
#      the WORD "true"/"false", not "t"/"f" (that shorthand is what a bare
#      boolean COLUMN renders as -- this is a boolean EXPRESSION). The
#      check compared against "t", which a correctly-initialized role
#      never matches -- died on the FIRST role checked (authenticator)
#      EVERY time, even confirmed non-poisoned, correctly-initialized
#      volumes (direct query on the box: all four roles genuinely true).
#   2. `echo "$INIT_STATE" | while read ...; done` runs the loop body in a
#      SUBSHELL (bash's pipe-to-while behavior) -- die()'s `exit 1` inside
#      it only exits that subshell, not this script; it happened to still
#      abort correctly here only because the pipeline's own non-zero exit
#      then tripped this script's own `set -eo pipefail` from outside the
#      loop, which is fragile to rely on, not the actual intended
#      mechanism. Process substitution avoids the subshell entirely.
while IFS=: read -r role has_pw; do
  info "  $role password set: $has_pw"
  [[ "$has_pw" == "true" ]] || die "role $role has no password set -- init scripts did not run (or db-data was already initialized before this deploy)"
done < <(printf '%s\n' "$INIT_STATE")
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
