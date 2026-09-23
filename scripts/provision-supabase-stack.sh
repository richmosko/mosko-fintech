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
#   script it calls is already idempotent. Deploy: a pre-existing `db-data`
#   volume is a THREE-WAY branch (team-lead follow-up, live --dry-run,
#   2026-09-20 -- the old unconditional refusal broke `provision.sh`'s own
#   "re-run = no-op" contract against a stack that was genuinely healthy) --
#   (a) no volume -> deploy, as always; (b) volume present AND
#   check_stack_already_healthy() (see that function's own header for the
#   exact four-probe definition of "healthy" -- this is a Sec-reviewed
#   CONTROL, not a loosening of one) confirms it -> "already provisioned
#   and healthy, nothing to deploy", VERIFIED, skips the deploy call but
#   still runs the full verification battery; (c) volume present and NOT
#   confirmed healthy -> the same refusal as before (2026-09-10's poisoned-
#   mount incident), naming `docker compose ... down -v` as the manual,
#   never-automatic destroy path.
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

# REPO_ROOT resolution -- .env lives at the MAIN checkout root, never inside
# an agent worktree. 2026-09-16 incident: `dirname "$0"/..` resolved to the
# worktree itself under .claude/worktrees/<name>/, so record-coolify-uuids.sh
# and provision-vps.sh's BOX_IP writer silently wrote MIGRATOR_SERVICE_UUID /
# APP_UUID / MIGRATOR_TASK_UUID / BOX_IP / CI_MIGRATE_SSH_PUBKEY into a
# throwaway per-worktree .env -- discarded when that worktree was removed at
# merge, leaving the real repo-root .env (what F/CTO's own --apply run reads)
# never updated. Refuse by default when invoked from inside
# .claude/worktrees/ rather than silently redirecting into the main
# checkout's .env; set REPO_ROOT explicitly to override.
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
CHECK_HEALTHY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    # --check-healthy (team-lead follow-up, live --dry-run, 2026-09-20):
    # a FAST, read-only, live done-predicate -- resolves the application
    # by name (the same lookup the main Preflight step below performs
    # anyway) then calls check_stack_already_healthy() and stops, WITHOUT
    # ever reaching project/environment/application creation, secrets
    # minting, or mount materialization. Exists so provision.sh's own
    # run_standup() can ask "is this already done?" BEFORE ever calling
    # `standup.sh --apply` -- the live defect this whole fix addresses
    # was discovered by --apply running several idempotent-but-not-free
    # steps before finally reaching the (then-unconditional) poisoned-
    # volume refusal. Mutually exclusive with --apply (checked below).
    --check-healthy) CHECK_HEALTHY=1 ;;
    *) echo "unknown flag: $arg" >&2; echo "usage: $0 [--apply] | [--check-healthy]" >&2; exit 2 ;;
  esac
done
if [[ $APPLY -eq 1 && $CHECK_HEALTHY -eq 1 ]]; then
  echo "FATAL: --apply and --check-healthy are mutually exclusive -- --check-healthy is a read-only probe, never paired with a mutating run." >&2
  exit 2
fi

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

# ADR-074 Decision A + Part 2(c) items 1-2: SITE_URL is operator-provided
# (scripts/provision.env.example), unconditional overwrite, same
# mechanism as SMTP_PASS above -- NONSECRET_DEFAULTS below still carries
# the localhost literal as a mint-if-absent fallback for a genuinely
# fresh box; this override corrects it once DNS/domain has a real value.
# Fail-closed guards (Sec ship-block, F/CTO ruling 2026-09-23): this
# provisioner has no local/dev mode -- it only ever targets a real box
# over SSH/Coolify -- so both guards below fire UNCONDITIONALLY on every
# run, never behind a self-declared "is this production" flag.
SITE_URL_OVERRIDE="$(read_env_var SITE_URL)"
if [[ -n "$SITE_URL_OVERRIDE" ]]; then
  [[ "$SITE_URL_OVERRIDE" == https://* ]] \
    || die "SITE_URL='$SITE_URL_OVERRIDE' in .env does not start with https:// -- refusing (ADR-074: the confirmation-email link's own host is dereferenced by mail clients over the public internet)."
  case "$SITE_URL_OVERRIDE" in
    *localhost*|*127.0.0.1*)
      die "SITE_URL='$SITE_URL_OVERRIDE' in .env contains localhost/127.0.0.1 -- refusing (this would ship a dead link in every auth email; see ADR-074 Part 0)." ;;
  esac
fi
if [[ -n "$SMTP_PASS" ]]; then
  [[ -n "$SMTP_ADMIN_EMAIL_OVERRIDE" ]] \
    || die "SMTP_PASS is set in .env but SMTP_ADMIN_EMAIL is not -- refusing (Sec ship-block: a real SMTP credential with no admin-email override would send from the placeholder admin@example.com)."
  case "$SMTP_ADMIN_EMAIL_OVERRIDE" in
    *@example.com)
      die "SMTP_ADMIN_EMAIL='$SMTP_ADMIN_EMAIL_OVERRIDE' ends in @example.com -- refusing (Sec ship-block: this is the non-functional placeholder domain, never a real sender)." ;;
  esac
fi

# The five GOTRUE_MAILER_TEMPLATES_* values are FIXED literals this
# script computes itself -- never operator-provided, never read from
# .env (ADR-074 Part 2(a) "New" column). Computed unconditionally
# (independent of SITE_URL_OVERRIDE being set) since they point at the
# `app` container over the private stack network, not at SITE_URL --
# measured live, 2026-09-23: `getent hosts app` from inside the `auth`
# container resolves 10.0.2.11 on the stack's own network
# (nz7mbexygw9lesjlazcxeltn), discharging the ADR's own "app alias
# UNMEASURED" residual risk.
MAILER_TEMPLATES_INVITE="http://app:3000/email-templates/invite.html"
MAILER_TEMPLATES_CONFIRMATION="http://app:3000/email-templates/confirmation.html"
MAILER_TEMPLATES_RECOVERY="http://app:3000/email-templates/recovery.html"
MAILER_TEMPLATES_MAGIC_LINK="http://app:3000/email-templates/magic_link.html"
MAILER_TEMPLATES_EMAIL_CHANGE="http://app:3000/email-templates/email_change.html"
# Guard (Sec, ADR-074 Part 2(c) item 2 + team-lead addendum A): each
# value must carry an explicit scheme (Consequence 2 -- a bare path is
# silently rewritten to SITE_URL + path by GoTrue's own
# loadEntryBody(), an unnoticed public fetch) AND must not itself begin
# with SITE_URL (the identical failure one layer up, or a copy-paste
# mistake -- indistinguishable from the bug this guard exists to
# catch). Asserted once, here, where the values are computed, so a
# future edit to the literals above is protected too -- "a guard never
# made to fail is an assumption" (Sec), struck by hand once below, not
# by a new fixture (F/CTO ruling: no new tests for this build).
for _tmpl_url in "$MAILER_TEMPLATES_INVITE" "$MAILER_TEMPLATES_CONFIRMATION" "$MAILER_TEMPLATES_RECOVERY" "$MAILER_TEMPLATES_MAGIC_LINK" "$MAILER_TEMPLATES_EMAIL_CHANGE"; do
  case "$_tmpl_url" in
    http://*|https://*) ;;
    *) die "template URL '$_tmpl_url' does not start with http:// or https:// -- refusing (a bare path is silently rewritten to SITE_URL + path by GoTrue, becoming an unintended public fetch)." ;;
  esac
  if [[ -n "$SITE_URL_OVERRIDE" && "$_tmpl_url" == "$SITE_URL_OVERRIDE"* ]]; then
    die "template URL '$_tmpl_url' begins with SITE_URL ('$SITE_URL_OVERRIDE') -- refusing (this is indistinguishable from the bare-path-rewrite failure this guard exists to catch)."
  fi
done
unset _tmpl_url

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
# FENCE-EXTRACT-FUNC-BEGIN: check-stack-already-healthy-func -- scripts/ci/fence-supabase-stack-healthy-check-strikes.sh
# extracts this function VERBATIM (between these markers) rather than
# hand-duplicating its logic, so the fence can never silently drift from
# what actually ships. Keep marker lines exactly as they are. Defined THIS
# early (before the main Preflight step) so --check-healthy (below) can call
# it without running any of the project/environment/application creation
# logic that follows.
# check_stack_already_healthy -- team-lead follow-up (live --dry-run,
# 2026-09-20): a stack provisioned 2026-09-09, fully healthy, hit the OLD
# unconditional "db-data volume exists -> refuse" guard on a plain re-run
# of this script, breaking provision.sh's own re-run = no-op contract.
# This is a CONTROL CHANGE (Sec review required) -- the poisoned-volume
# refusal below still exists and still fires whenever this cannot prove
# the volume is genuinely healthy; this function is the new, PRECISE
# DEFINITION of "healthy" for that purpose, not a loosening of the guard.
#
# WHAT "HEALTHY" MEANS HERE -- five READ-ONLY checks, all reused from
# elsewhere in this file (never a new, heavier mechanism invented just for
# this): (1) N/7 containers report Docker health=healthy (same query the
# "Verification battery" step below already runs after a fresh deploy);
# (2) api-gw's /auth/v1/health route is a TWO-PART probe (measured
# 2026-09-21 against the live box -- team-lead's own `--from standup`
# run -- and structurally: this stack's gateway is ENVOY (infra/supabase/
# docker-compose.yml api-gw = envoyproxy/envoy, container_name
# supabase-envoy; the `kong` name there is a legacy network ALIAS only),
# and its inline Lua apikey filter lists `auth-v1-protected` in
# PROTECTED_ROUTES (infra/supabase/volumes/api/envoy/lds.template.yaml).
# That route is the bare `/auth/v1/` PREFIX and there is no exact-path
# carve-out for /auth/v1/health, so an
# unkeyed GET answers 401, never 200; the ORIGINAL one-part version here
# expected 200 unkeyed and refused a genuinely healthy stack on every
# re-run): unkeyed GET -> 401 (proves the gateway is up AND key-auth is
# genuinely enforced), THEN the same anon apikey -> 200 (proves the key
# itself authenticates). Both probed from inside the supavisor container,
# same probe() shape and same box-side ANON_KEY tinker readback
# mint-supabase-jwt-keys.sh's own --verify-live already uses -- reused,
# not reinvented; (3) Postgres is reachable and reports major version 17 (same
# `select server_version` query below); (4) the STATE-BASED init marker
# below already documents as the real proof that /docker-entrypoint-
# initdb.d/ actually ran (Postgres runs it exactly once, ever) --
# EXACTLY FOUR role rows (authenticator/pgbouncer/supabase_auth_admin/
# supabase_functions_admin, cardinality itself checked -- Sec C-1, PR
# #852 AMBER review: a single matching row used to pass this check
# silently, since a non-empty one-line result is still non-empty) all
# have a password set; (5) `app.settings.jwt_secret` is set and
# non-empty, asserted server-side without retrieving the value (Sec F-2 +
# C-4, PR #852 AMBER review -- the "Verification battery" step below
# already treats (4) and (5) together as ONE two-part tell that init
# scripts genuinely ran; this function only carried the first half until
# now, and the first version of (5) here retrieved the secret into this
# process and was fail-open on any non-canonical answer other than the
# one error string it checked for).
# (4) and (5) are the ones that actually answer "was this volume
# initialized by a real deploy of THIS stack, not a bogus mount" -- (1)-
# (3) only prove "something is currently running and answering", which a
# poisoned-but-since-patched-around volume could also produce. ALL FIVE
# must pass; any single failure means "not confirmed healthy" and the
# caller refuses exactly as before.
check_stack_already_healthy() {
  local containers=0
  for _ in $(seq 1 5); do
    containers="$(sshx "docker ps --filter 'label=com.docker.compose.project=$APP_UUID' --filter 'health=healthy' --format '{{.Names}}'" | wc -l | tr -d ' ')"
    [[ "$containers" == "7" ]] && break
    sleep 2
  done
  info "healthy-check (1/5): $containers/7 containers healthy"
  if [[ "$containers" != "7" ]]; then info "healthy-check FAILED at (1/5): expected 7 healthy containers, got $containers"; return 1; fi

  # team-lead's live measurement, 2026-09-21: this stack's gateway route
  # for /auth/v1/health enforces key-auth -- an unkeyed GET answers 401,
  # not 200 (measured from a sibling container: no apikey -> 401, anon
  # apikey -> 200, same for /rest/v1/). The gateway is ENVOY, not Kong
  # (infra/supabase/docker-compose.yml: api-gw = envoyproxy/envoy,
  # container_name supabase-envoy; the `kong` name there is a legacy
  # network ALIAS). The enforcement lives in Envoy's inline Lua apikey
  # filter, whose PROTECTED_ROUTES table lists `auth-v1-protected` --
  # the bare `/auth/v1/` PREFIX route, with no exact-path carve-out for
  # /auth/v1/health (infra/supabase/volumes/api/envoy/lds.template.yaml).
  # So the 401 is a repo-grounded invariant, not only a one-off live
  # observation. The ORIGINAL probe here expected 200
  # unkeyed and refused a genuinely healthy stack on every re-run --
  # exactly the false-negative that stopped the live `--from standup`
  # pass. Fixed to a two-part probe, reusing the SAME mechanism
  # mint-supabase-jwt-keys.sh's own --verify-live already uses (same
  # supavisor-exec-curl container, same box-side tinker readback of
  # ANON_KEY, never a new mechanism): no-key MUST answer 401 (proves the
  # gateway is up AND key-auth is genuinely enforced -- the RT-32/
  # private-bind posture, not merely "something answers"), and the SAME
  # anon key MUST answer 200 (proves the key itself authenticates, not
  # just that a key was supplied). ANON_KEY is read back on the box via
  # the same on-box Eloquent tinker pattern used throughout this file and
  # in mint-supabase-jwt-keys.sh -- never echoed to this script's own
  # stdout -- only the ANON_KEY_PRESENT boolean and the two HTTP status
  # codes cross back.
  local gw_probe anon_key_present gw_nokey gw_withkey
  # Strike-tested: removing each of the three checks below in turn takes
  # the fence red at exactly the right scenario (5a+5c / 5d / 5b -- 5c
  # watches the no-key half's own message, so it moves with 5a).
  gw_probe="$(sshx "env APP_UUID=\"$APP_UUID\" bash -s" 2>/dev/null <<'REMOTE' || true
set -e
ANON_KEY="$(docker exec coolify php artisan tinker --execute="
\$app = \App\Models\Application::where('uuid','$APP_UUID')->firstOrFail();
echo (string) \$app->environment_variables()->where('key','ANON_KEY')->first()->value;
" 2>/dev/null | tail -1)"
set +e
NOKEY_STATUS="$(docker compose --project-name $APP_UUID exec -T supavisor curl -s -o /dev/null -w '%{http_code}' http://api-gw:8000/auth/v1/health </dev/null)"
if [[ -n "$ANON_KEY" ]]; then
  WITHKEY_STATUS="$(docker compose --project-name $APP_UUID exec -T supavisor curl -s -o /dev/null -w '%{http_code}' -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" http://api-gw:8000/auth/v1/health </dev/null)"
else
  WITHKEY_STATUS=""
fi
set -e
printf 'ANON_KEY_PRESENT=%s NOKEY=%s WITHKEY=%s\n' "$([[ -n "$ANON_KEY" ]] && echo 1 || echo 0)" "${NOKEY_STATUS:-<none>}" "${WITHKEY_STATUS:-<none>}"
REMOTE
)"
  anon_key_present="$(printf '%s' "$gw_probe" | grep -oE 'ANON_KEY_PRESENT=[01]' | cut -d= -f2)"
  gw_nokey="$(printf '%s' "$gw_probe" | grep -oE 'NOKEY=[^ ]+' | cut -d= -f2)"
  gw_withkey="$(printf '%s' "$gw_probe" | grep -oE 'WITHKEY=[^ ]+' | cut -d= -f2)"
  info "healthy-check (2/5, no-key): api-gw GET /auth/v1/health without an apikey -> HTTP ${gw_nokey:-<none>} (expect 401 -- proves the gateway is up AND key-auth is enforced)"
  if [[ "$gw_nokey" != "401" ]]; then
    info "healthy-check FAILED at (2/5, no-key half): expected 401 without an apikey, got ${gw_nokey:-<none>}"
    if [[ "$gw_nokey" == "200" ]]; then
      info "  ^ a 200 here means the gateway served /auth/v1/ with NO apikey -- key-auth is not being enforced. That is a security finding, not a health blip: fix the gateway (Envoy lds PROTECTED_ROUTES / apikey filter), never relax this expectation to make the check pass."
    fi
    return 1
  fi
  if [[ "$anon_key_present" != "1" ]]; then
    info "healthy-check FAILED at (2/5, with-key half): could not read ANON_KEY back from the Coolify store -- cannot probe the with-key case"
    return 1
  fi
  info "healthy-check (2/5, with-key): api-gw GET /auth/v1/health with the anon apikey -> HTTP ${gw_withkey:-<none>} (expect 200)"
  if [[ "$gw_withkey" != "200" ]]; then
    info "healthy-check FAILED at (2/5, with-key half): expected 200 with the anon apikey, got ${gw_withkey:-<none>}. Most likely cause: the Coolify store's ANON_KEY and the key baked into the RUNNING Envoy config have diverged -- Envoy renders the expected key into its lds config at container-start, so rotating the store value without redeploying the stack leaves the gateway checking the OLD key (mint-supabase-jwt-keys.sh's header documents the same hazard)."
    return 1
  fi

  local pgver
  pgver="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc 'show server_version;'" 2>/dev/null | cut -d. -f1)"
  info "healthy-check (3/5): Postgres server_version starts '${pgver:-<none>}'"
  if [[ "$pgver" != "17" ]]; then info "healthy-check FAILED at (3/5): db not reachable, or not major version 17"; return 1; fi

  local init_state all_pw_set=1 role has_pw init_row_count
  init_state="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"select rolname||':'||(rolpassword is not null) from pg_authid where rolname in ('authenticator','pgbouncer','supabase_auth_admin','supabase_functions_admin') order by rolname;\"" 2>/dev/null || true)"
  # Sec C-1 (PR #852 AMBER review): the OLD guard only checked "is
  # init_state non-empty" -- a SINGLE matching role row (e.g. a partial or
  # foreign-volume init that only happens to define 'authenticator')
  # passed this check silently, since a non-empty string with one line is
  # still non-empty. Count rows explicitly and require exactly 4 -- the
  # cardinality itself is part of the proof, not just presence.
  init_row_count="$(printf '%s\n' "$init_state" | grep -c ':' || true)"
  if [[ "$init_row_count" != "4" ]]; then
    info "healthy-check FAILED at (4/5): expected 4 role rows, got $init_row_count -- pg_authid does not carry all four init-marker roles (a partial or foreign-volume init)"
    return 1
  fi
  while IFS=: read -r role has_pw; do
    [[ -z "$role" ]] && continue
    info "healthy-check (4/5): role $role password set: $has_pw"
    [[ "$has_pw" == "true" ]] || all_pw_set=0
  done < <(printf '%s\n' "$init_state")
  if [[ "$all_pw_set" != "1" ]]; then
    info "healthy-check FAILED at (4/5): not all four roles have a password set -- init scripts did not run against this volume (or it is from a different/bogus mount)"
    return 1
  fi

  # Sec F-2 (PR #852 AMBER review): the "Verification battery" step
  # further down (run after a FRESH deploy) treats the role-password
  # state AND app.settings.jwt_secret's presence as ONE two-part tell
  # that init scripts genuinely ran -- "ok all four role passwords set +
  # app.settings.jwt_secret present" is that step's own closing line.
  # check_stack_already_healthy() only carried the first half; this adds
  # the second so --check-healthy's own live done-predicate proves the
  # SAME two-part tell the archive's own procedure relies on, not a
  # narrower one.
  #
  # Sec C-4 (PR #852 AMBER review round 2): the ORIGINAL version here
  # (`show app.settings.jwt_secret;`, refuse only on the literal
  # "unrecognized configuration parameter" substring) was fail-open on
  # every OTHER non-canonical answer -- an empty result (psql/container
  # gone), a different error string, or the GUC explicitly set to the
  # empty string all read as "healthy" (a negative-only check: "absence
  # of one string" instead of "presence of the expected positive
  # token"). It also RETRIEVED the secret's actual value into this
  # script's own process via `2>&1` to see that error text at all --
  # `secrets-manifest.yml` classes JWT_SECRET production_only, and this
  # file's own header (SS3 CORRECTED 2026-09-11) names exactly one value
  # that legitimately crosses into local memory (SMTP_PASS); this probe
  # silently added a second, and unlike the "Verification battery" step
  # below (which only runs once, after a fresh deploy), this probe runs
  # on EVERY `provision.sh --dry-run` (live_done_standup calls
  # --check-healthy every time). `current_setting(name, true)` moves the
  # boolean decision server-side -- returns NULL (never an error) for an
  # unset GUC, so a two-arg equality test collapses "unset", "empty",
  # "unreachable db", and "dead psql" into the SAME refusal, and the
  # secret's value never leaves Postgres at all.
  local jwt_present
  jwt_present="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"select current_setting('app.settings.jwt_secret', true) <> '';\"" 2>/dev/null || true)"
  info "healthy-check (5/5): app.settings.jwt_secret present: '${jwt_present:-<none>}' (value never leaves Postgres)"
  if [[ "$jwt_present" != "t" ]]; then
    info "healthy-check FAILED at (5/5): app.settings.jwt_secret is unset, empty, or the db did not answer -- init scripts did not run against this volume"
    return 1
  fi

  ok "healthy-check: all five probes pass -- this db-data volume was genuinely initialized by a real deploy of this stack"
  return 0
}
# FENCE-EXTRACT-FUNC-END: check-stack-already-healthy-func


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

if [[ $CHECK_HEALTHY -eq 1 ]]; then
  step "--check-healthy: live done-predicate only, stopping here"
  if [[ -z "${APP_UUID:-}" ]]; then
    echo "NOT VERIFIED: application '$APP_NAME' does not exist yet." >&2
    exit 1
  fi
  if check_stack_already_healthy; then
    ok "VERIFIED: stack already provisioned and healthy."
    exit 0
  else
    echo "NOT VERIFIED: see the healthy-check output above for which probe failed." >&2
    exit 1
  fi
fi

step "Preflight — Source commit availability (docs/deployment-runbook.md §4, ADR-072 Amendment 6)"
# Read-only print, same as scripts/provision-migrator-app.sh's own preflight
# step -- --apply's own assert step below is the one that PATCHes and fails
# closed.
if [[ -n "${APP_UUID:-}" ]]; then
  SOURCE_COMMIT_JSON="$(api GET "/applications/$APP_UUID")"
  if echo "$SOURCE_COMMIT_JSON" | "$REPO_ROOT/scripts/ci/check-source-commit-in-build.sh" >/tmp/stack-source-commit-check.$$ 2>&1; then
    ok "settings.include_source_commit_in_build — true"
  else
    info "settings.include_source_commit_in_build — NOT true ($(cat /tmp/stack-source-commit-check.$$ | tr -d '\n')) — --apply will PATCH this before deploying"
  fi
  rm -f /tmp/stack-source-commit-check.$$
else
  info "application does not exist yet — will be created with include_source_commit_in_build=true"
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
  # include_source_commit_in_build -- same field, same reasoning as
  # scripts/provision-migrator-app.sh's own create body (docs/deployment-runbook.md
  # §4, ADR-072 Amendment 6). This stack application has carried true since
  # 2026-09-17 (set by hand, per §4's note); setting it here too means a
  # from-scratch re-create of this application never depends on that
  # by-hand step. The ASSERT step below is the watcher either way.
  'include_source_commit_in_build': True,
}))")"
  APP_UUID="$(api POST /applications/public "$CREATE_BODY" | jqp "print(json.load(sys.stdin)['uuid'])")"
  ok "application created — $APP_UUID (compose parse queued, not deployed yet)"
fi

step "Assert — settings.include_source_commit_in_build == true (BEFORE deploying)"
# Watcher, per docs/deployment-runbook.md §4 (ADR-072 Amendment 6): this
# has been true on the live resource since 2026-09-17 (set by hand), but
# nothing previously asserted it on a re-run. Same PATCH+re-read+die-closed
# shape as scripts/provision-migrator-app.sh's own assert step; see that
# script's header comment and scripts/ci/check-source-commit-in-build.sh
# for the strike-proven predicate both scripts call.
SOURCE_COMMIT_JSON="$(api GET "/applications/$APP_UUID")"
if ! echo "$SOURCE_COMMIT_JSON" | "$REPO_ROOT/scripts/ci/check-source-commit-in-build.sh" >/tmp/stack-source-commit-assert.$$ 2>&1; then
  info "settings.include_source_commit_in_build is not true — PATCHing to true"
  api PATCH "/applications/$APP_UUID" '{"include_source_commit_in_build": true}' >/dev/null
  SOURCE_COMMIT_JSON="$(api GET "/applications/$APP_UUID")"
  if ! echo "$SOURCE_COMMIT_JSON" | "$REPO_ROOT/scripts/ci/check-source-commit-in-build.sh" >/tmp/stack-source-commit-assert.$$ 2>&1; then
    cat /tmp/stack-source-commit-assert.$$ >&2
    rm -f /tmp/stack-source-commit-assert.$$
    die "settings.include_source_commit_in_build is still not true after PATCH -- refusing to deploy. See docs/deployment-runbook.md §4."
  fi
fi
rm -f /tmp/stack-source-commit-assert.$$
ok "settings.include_source_commit_in_build — true (asserted before deploy)"

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

# Bash-side mirror of the python heredoc's own to_set["SMTP_PORT"] =
# "2465" literal below (Resend's own fixed value, applied whenever
# SMTP_PASS is seeded -- 2465 = implicit TLS from the first byte on
# Resend; 465 is blocked outbound on Hetzner by default, measured
# 2026-09-23 from the auth container's own network namespace, 2465
# measured OPEN). Kept here ONLY so the post-deploy container-env
# check further down has something to assert against; if that python
# literal ever changes, this one must change with it (same duplication
# class scripts/coolify-env.sh's own value-shape constraints already
# accept for MAILER_TEMPLATES_*).
EXPECTED_SMTP_PORT="2465"

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

step "SITE_URL + email templates (ADR-074): operator/script-provided URLs (unconditional overwrite)"
# Same boundary-crossing shape as the SMTP block above -- a path pushed
# over SSH stdin, read back by PATH only downstream, never a value on
# argv or in a heredoc literal. Unlike SMTP, this file is ALWAYS pushed:
# the five MAILER_TEMPLATES_* values are the same computed literals on
# every run (never "nothing to push"), and they must reach the box
# regardless of whether SITE_URL_OVERRIDE itself is set yet.
URL_SEED_FILE="/root/.pfin/_url_seed.env.$$"
{
  printf 'SITE_URL=%s\n' "$SITE_URL_OVERRIDE"
  printf 'MAILER_TEMPLATES_INVITE=%s\n' "$MAILER_TEMPLATES_INVITE"
  printf 'MAILER_TEMPLATES_CONFIRMATION=%s\n' "$MAILER_TEMPLATES_CONFIRMATION"
  printf 'MAILER_TEMPLATES_RECOVERY=%s\n' "$MAILER_TEMPLATES_RECOVERY"
  printf 'MAILER_TEMPLATES_MAGIC_LINK=%s\n' "$MAILER_TEMPLATES_MAGIC_LINK"
  printf 'MAILER_TEMPLATES_EMAIL_CHANGE=%s\n' "$MAILER_TEMPLATES_EMAIL_CHANGE"
} | sshx "umask 077; mkdir -p /root/.pfin; cat > $URL_SEED_FILE"
if [[ -n "$SITE_URL_OVERRIDE" ]]; then
  ok "pushed SITE_URL + 5 mailer template URLs to the box -- will overwrite placeholders below"
else
  info "no SITE_URL in .env -- pushing the 5 mailer template URLs only; SITE_URL stays at its mint-if-absent localhost default until DNS/domain is decided (ADR-074 open question 2)"
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
\\\$check = ['POSTGRES_PASSWORD','JWT_SECRET','SECRET_KEY_BASE','VAULT_ENC_KEY','SERVICE_ROLE_KEY','ANON_KEY','DASHBOARD_PASSWORD','PG_META_CRYPTO_KEY','STUDIO_DEFAULT_ORGANIZATION','STUDIO_DEFAULT_PROJECT','DASHBOARD_USERNAME','DISABLE_SIGNUP','ENABLE_ANONYMOUS_USERS','ENABLE_EMAIL_AUTOCONFIRM','ENABLE_EMAIL_SIGNUP','ENABLE_PHONE_AUTOCONFIRM','ENABLE_PHONE_SIGNUP','JWT_EXPIRY','MAILER_URLPATHS_CONFIRMATION','MAILER_URLPATHS_EMAIL_CHANGE','MAILER_URLPATHS_INVITE','MAILER_URLPATHS_RECOVERY','PGRST_DB_EXTRA_SEARCH_PATH','PGRST_DB_MAX_ROWS','PGRST_DB_SCHEMAS','POOLER_DB_POOL_SIZE','POOLER_DEFAULT_POOL_SIZE','POOLER_MAX_CLIENT_CONN','POOLER_TENANT_ID','POSTGRES_DB','POSTGRES_HOST','POSTGRES_PORT','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASS','SMTP_SENDER_NAME','SMTP_ADMIN_EMAIL','SUPABASE_PUBLIC_URL','API_EXTERNAL_URL','SITE_URL','MAILER_TEMPLATES_INVITE','MAILER_TEMPLATES_CONFIRMATION','MAILER_TEMPLATES_RECOVERY','MAILER_TEMPLATES_MAGIC_LINK','MAILER_TEMPLATES_EMAIL_CHANGE'];
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

# ADR-074 Consequence 9 / team-lead's redeploy-when-changed ruling: NEED_MINT
# above only distinguishes EMPTY-vs-not, not old-value-vs-new -- it cannot
# tell "this run reasserts the identical value" from "this run actually
# changes what's live", and only the second case needs a redeploy. Read the
# CURRENT live values of the six auth-email keys (all non-secret -- safe to
# echo in full, unlike the ~35 keys $check/$required cover above) and diff
# them against what this run is about to set, in bash, before anything is
# PATCHed.
CURRENT_EMAIL_ENV="$(sshx_in <<REMOTE
docker exec coolify php artisan tinker --execute="
(function () {
\\\$app = \\App\\Models\\Application::where('uuid','$APP_UUID')->firstOrFail();
\\\$keys = ['SITE_URL','MAILER_TEMPLATES_INVITE','MAILER_TEMPLATES_CONFIRMATION','MAILER_TEMPLATES_RECOVERY','MAILER_TEMPLATES_MAGIC_LINK','MAILER_TEMPLATES_EMAIL_CHANGE'];
foreach (\\\$keys as \\\$key) {
  \\\$env = \\\$app->environment_variables()->where('key', \\\$key)->first();
  echo \\\$key . '=' . (\\\$env ? (string) \\\$env->value : '') . PHP_EOL;
}
return null;
})();
"
REMOTE
)"
EMAIL_ENV_CHANGED=0
_email_env_diff() {
  local key="$1" new="$2" old
  old="$(printf '%s\n' "$CURRENT_EMAIL_ENV" | sed -n "s/^${key}=//p")"
  [[ "$old" == "$new" ]] || EMAIL_ENV_CHANGED=1
}
# SITE_URL only counts if this run is actually overriding it -- comparing
# against an intentionally-not-applied empty string would always read as
# "changed" and force a needless redeploy on every run with no override set.
[[ -z "$SITE_URL_OVERRIDE" ]] || _email_env_diff SITE_URL "$SITE_URL_OVERRIDE"
_email_env_diff MAILER_TEMPLATES_INVITE "$MAILER_TEMPLATES_INVITE"
_email_env_diff MAILER_TEMPLATES_CONFIRMATION "$MAILER_TEMPLATES_CONFIRMATION"
_email_env_diff MAILER_TEMPLATES_RECOVERY "$MAILER_TEMPLATES_RECOVERY"
_email_env_diff MAILER_TEMPLATES_MAGIC_LINK "$MAILER_TEMPLATES_MAGIC_LINK"
_email_env_diff MAILER_TEMPLATES_EMAIL_CHANGE "$MAILER_TEMPLATES_EMAIL_CHANGE"

# Item 19 fix (Sec-gated, booked BACKLOG.md §7.36 #19): this heredoc used
# to be `sshx_in <<REMOTE` (unquoted delimiter), which made the LOCAL shell
# perform command AND variable substitution on the ENTIRE body before it
# ever reached SSH -- including on lines that only look like they belong
# to the REMOTE bash -s script. Three plain documentation comments below
# contain backtick-quoted `migrator` (Markdown-style code-format, not
# executable anywhere on the remote side); to the local unquoted heredoc
# reader, backtick...backtick IS a command-substitution request, so it ran
# `migrator` as a local command three times ("migrator: command not
# found") before the mint step's real output ever printed. Not exploitable
# (the minted values are hex from openssl rand -hex, nothing
# shell-meaningful), but the mechanism generalizes badly to any future
# bareword in this body. Fixed by quoting the delimiter (<<'REMOTE') so
# the local shell performs ZERO substitution on the body -- it is sent to
# the box byte-for-byte. Sec's forward note: this heredoc still needs
# THREE host-side values (APP_UUID / NEED_MINT / SMTP_SEED_FILE) that a
# quoted delimiter can no longer interpolate inline -- those now cross via
# `env VAR="value"` on the ssh command line instead (same trust model as
# every other sshx() call in this file: values are our own script's UUID/
# key-list/path, not attacker input, so no extra %q-quoting beyond the
# existing double-quote convention). bash -s then sees them as ordinary
# already-exported variables, same names, same values, as before.
sshx "env APP_UUID=\"$APP_UUID\" NEED_MINT=\"$NEED_MINT\" SMTP_SEED_FILE=\"$SMTP_SEED_FILE\" URL_SEED_FILE=\"$URL_SEED_FILE\" bash -s" <<'REMOTE'
set -e
umask 077
mkdir -p /root/.pfin
TOKEN="$(grep -m1 '^COOLIFY_API_TOKEN=' /root/.pfin/coolify.env | cut -d= -f2-)"

# Sec-flagged hardening (pre-prod review follow-up, 2026-09-11): the manual
# cleanup this used to rely on sat AFTER the python step, inside this same
# `set -e` script -- if python (or an earlier line) failed, `set -e`
# aborted BEFORE cleanup ran, leaving the mode-600 root-owned seed file
# behind in /root/.pfin (accumulates across failed runs; on-box, root-only,
# holds a key already destined for Coolify -- not an off-box exposure, but
# untidy and worth closing cheaply). A trap runs on ANY exit from this
# point on -- success, `set -e` abort, or signal -- so cleanup can no
# longer be skipped by a failure partway through. $SMTP_SEED_FILE is
# resolved when the trap FIRES, not when it's registered (single-quoted
# trap body), so it correctly sees whatever this script's variable holds
# at exit time, including if it's still empty (no seed was ever pushed --
# the guard below is then a no-op).
trap 'if [ -n "$SMTP_SEED_FILE" ]; then shred -u "$SMTP_SEED_FILE" 2>/dev/null || rm -f "$SMTP_SEED_FILE"; fi; if [ -n "$URL_SEED_FILE" ]; then shred -u "$URL_SEED_FILE" 2>/dev/null || rm -f "$URL_SEED_FILE"; fi' EXIT

python3 - "$TOKEN" "$APP_UUID" "$NEED_MINT" "$SMTP_SEED_FILE" "$URL_SEED_FILE" <<'PYEOF'
import json, subprocess, sys, secrets as pysecrets

token, app_uuid, need_mint_raw, smtp_seed_file, url_seed_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
need_mint = set(need_mint_raw.split())

# SECURITY FIX, 2026-09-11 (Sec-flagged sibling finding to #734 -- Backend
# hit this EXACT defect class live in mint-supabase-jwt-keys.sh's own api()
# during the clean prod rebuild: a Coolify API call failed on a stale uuid,
# subprocess.run(cmd, ..., check=True) raised CalledProcessError, and its
# default string representation embeds its WHOLE argv -- including the
# literal -H f"Authorization: Bearer {token}" element -- which then
# reached the operator/log/team-lead's context over this script's own SSH
# channel. This file's api() had the IDENTICAL shape and never happened to
# leak only because no call here failed on that run -- any future
# create/deploy failure would leak the live Coolify token the same way.
# Mirrors #734's fix exactly, for consistency across both scripts:
#   (1) the token is now a 'header = "Authorization: Bearer <token>"'
#       config-file directive fed to curl over STDIN (-K -), never a
#       -H/argv element at all -- it cannot appear in ps, and it cannot
#       appear in an exception's string representation because it was
#       never part of cmd.
#   (2) every call is wrapped in try/except CalledProcessError, re-raising
#       a SANITIZED message (exit status + curl's own -S diagnostic text,
#       truncated -- which describes URL/connection status, never request
#       headers) instead of letting Python's default unhandled-exception
#       traceback through.
# Note this ALSO closes the wider exposure team-lead asked to check: the
# -d json.dumps(body) argv element (unchanged, still present -- matching
# #734, which does not move the body out of argv either) carries every OTHER
# secret this step PATCHes in the SAME call -- JWT_SECRET, POSTGRES_PASSWORD,
# SECRET_KEY_BASE, VAULT_ENC_KEY, SERVICE_ROLE_KEY, ANON_KEY,
# DASHBOARD_PASSWORD, PG_META_CRYPTO_KEY, and SMTP_PASS when the operator
# override applies -- ALL of them, not just the Coolify token, would have
# been printed by the SAME unhandled CalledProcessError. The try/except
# wrapper protects all of them at once, since it controls what die() prints
# regardless of what cmd itself contains.
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
# ADR-072 Amendment 4 (2026-09-16, F/CTO-ratified) / BACKLOG.md §7.36 item
# 29 -- MIGRATOR_DB_PASSWORD (and MIGRATOR_DB_USER in NONSECRET_DEFAULTS
# below) REMOVED from this dict, 2026-09-18. `migrator` moved OFF this
# Coolify Compose resource to its OWN standalone application -- see
# infra/supabase/migrator/docker-compose.yaml and
# scripts/provision-migrator-app.sh (the new resource's own mint-if-absent
# path). Amendment 1's premise ("migrator is a SIBLING service in THIS SAME
# Compose resource") was FALSIFIED by Amendment 3 (2026-09-14): Coolify
# gives every service in a multi-service application the WHOLE env store
# via `env_file:`, so minting this credential HERE put it in every
# sibling's environment too, not just migrator's. ⚠ Leaving these two names
# out of this dict is NOT itself the remedy -- MINT_SECRETS is
# mint-if-ABSENT, so simply removing them here would silently leave a
# PRE-EXISTING value in this resource's store untouched forever. The
# removal half of the remedy is the POST-MOVE ABSENCE ASSERTION below
# (`assert_migrator_names_absent`), which is what actually enforces that
# neither name is present in THIS store going forward -- see that
# function's own header for why it is strike-proven rather than merely
# asserted once.
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
# set from the hand-run era).
#
# ADR-074 (ratified, F/CTO 2026-09-23) resolves that "open ARCH call" for
# SITE_URL only: it gets a dedicated operator-override block below (see
# "SITE_URL + email templates"), unconditional overwrite once DNS/domain
# is decided. API_EXTERNAL_URL and SUPABASE_PUBLIC_URL DELIBERATELY stay
# at their localhost literals here, mint-if-absent, no override path --
# Consequences 3+4: API_EXTERNAL_URL is only GOTRUE_JWT_ISSUER (nothing
# validates `iss` today) and SUPABASE_PUBLIC_URL is only Studio + Envoy
# CORS (no browser origin reaches it under this design); both need only
# to PARSE, never to be dereferenced by a mail client or a browser.
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
                       # BACKLOG.md §7.36 item 22 (F/CTO-ruled 2026-09-19): `pfin` belongs
                       # here per ADR-023's ratified Data-API exposure posture. `public`
                       # stays FIRST -- PostgREST's first listed schema is its default
                       # Accept-Profile, so `pfin` alone (or first) would un-expose the
                       # other two. This is check-if-absent (NONSECRET_DEFAULTS), so
                       # correcting this line does NOT correct an already-set live store
                       # value -- see the post-deploy fence-pgrst-schemas-live.sh
                       # assertion below, which is the production-observable half.
                       "PGRST_DB_SCHEMAS": "public,graphql_public,pfin",
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
                       # ADR-072 Amendment 4 / BACKLOG.md §7.36 item 29 --
                       # MIGRATOR_DB_USER REMOVED from this dict, 2026-09-18.
                       # `migrator` moved to its OWN Coolify application --
                       # see scripts/provision-migrator-app.sh for its own
                       # mint-if-absent NONSECRET_DEFAULTS entry of the same
                       # name. See MINT_SECRETS above for the full removal
                       # rationale (Amendment 3's falsification of Amendment
                       # 1's confinement premise).
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
    # 2465, not 465 -- measured 2026-09-23 from the auth container's own
    # network namespace, live production: outbound 465 is BLOCKED
    # (Hetzner's default egress policy on new projects), 2465 is OPEN.
    # 2465 = implicit TLS from the first byte on Resend, retiring the
    # STARTTLS-stripping residual Sec recorded on PR #887 (BACKLOG item
    # 100) without a Hetzner unblock request.
    to_set["SMTP_PORT"] = "2465"
    to_set["SMTP_USER"] = "resend"
    if seed.get("SMTP_ADMIN_EMAIL"):
        to_set["SMTP_ADMIN_EMAIL"] = seed["SMTP_ADMIN_EMAIL"]
    if seed.get("SMTP_SENDER_NAME"):
        to_set["SMTP_SENDER_NAME"] = seed["SMTP_SENDER_NAME"]
    print("SMTP: operator-provided Resend credentials applied (overwrote placeholders)")

# ADR-074 Part 2(c) item 1: SITE_URL is operator-provided (unconditional
# overwrite, like SMTP_PASS above); the five MAILER_TEMPLATES_* are
# ALWAYS applied -- they are fixed literals this script computes, not an
# optional operator value, so url_seed_file always carries them and this
# block always runs (unlike the SMTP block, which only runs when
# SMTP_PASS was present in .env).
if url_seed_file:
    with open(url_seed_file) as f:
        useed = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
    if useed.get("SITE_URL"):
        to_set["SITE_URL"] = useed["SITE_URL"]
    for _k in ("MAILER_TEMPLATES_INVITE", "MAILER_TEMPLATES_CONFIRMATION", "MAILER_TEMPLATES_RECOVERY", "MAILER_TEMPLATES_MAGIC_LINK", "MAILER_TEMPLATES_EMAIL_CHANGE"):
        if useed.get(_k):
            to_set[_k] = useed[_k]
    print("URLS: SITE_URL (if provided) + 5 mailer template URLs applied (ADR-074)")

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
# Seed file cleanup now happens via the `trap ... EXIT` registered above --
# fires here on normal completion same as it would on an earlier failure.
# No separate manual cleanup call needed at this specific point anymore.

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
#
# Escaping note (item 19 fix): this block is a genuinely nested
# double-quoted string -- the `--execute="..."` argument is parsed by the
# REMOTE bash itself (the only remaining quoting layer now that the outer
# heredoc delimiter is quoted). So `\$app`-style single-backslash escapes
# below are load-bearing (they stop REMOTE bash from expanding $app as
# its own variable, leaving literal "$app" for PHP) and are UNCHANGED from
# before. What changed: the top-level `$(...)`, `$ASSERT_OUT`, and the
# grep pattern's end-of-line `$` anchor are no longer inside the old local
# heredoc's substitution pass, so their escaping is removed -- they were
# only ever escaped to survive that pass, and a literal `\$` reaching grep
# as `MISSING\$` would have matched a literal "$" character, never the
# end-of-line anchor the FATAL check actually needs.
ASSERT_OUT="$(docker exec coolify php artisan tinker --execute="
(function () {
\$app = \App\Models\Application::where('uuid','$APP_UUID')->firstOrFail();
\$required = ['POSTGRES_PASSWORD','JWT_SECRET','SECRET_KEY_BASE','VAULT_ENC_KEY','SERVICE_ROLE_KEY','ANON_KEY','DASHBOARD_PASSWORD','PG_META_CRYPTO_KEY','STUDIO_DEFAULT_ORGANIZATION','STUDIO_DEFAULT_PROJECT','DASHBOARD_USERNAME','DISABLE_SIGNUP','ENABLE_ANONYMOUS_USERS','ENABLE_EMAIL_AUTOCONFIRM','ENABLE_EMAIL_SIGNUP','ENABLE_PHONE_AUTOCONFIRM','ENABLE_PHONE_SIGNUP','JWT_EXPIRY','MAILER_URLPATHS_CONFIRMATION','MAILER_URLPATHS_EMAIL_CHANGE','MAILER_URLPATHS_INVITE','MAILER_URLPATHS_RECOVERY','PGRST_DB_EXTRA_SEARCH_PATH','PGRST_DB_MAX_ROWS','PGRST_DB_SCHEMAS','POOLER_DB_POOL_SIZE','POOLER_DEFAULT_POOL_SIZE','POOLER_MAX_CLIENT_CONN','POOLER_TENANT_ID','POSTGRES_DB','POSTGRES_HOST','POSTGRES_PORT','SMTP_HOST','SMTP_PORT','SMTP_USER','SMTP_PASS','SMTP_SENDER_NAME','SMTP_ADMIN_EMAIL','SUPABASE_PUBLIC_URL','API_EXTERNAL_URL','SITE_URL','MAILER_TEMPLATES_INVITE','MAILER_TEMPLATES_CONFIRMATION','MAILER_TEMPLATES_RECOVERY','MAILER_TEMPLATES_MAGIC_LINK','MAILER_TEMPLATES_EMAIL_CHANGE'];
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

# check_stack_already_healthy() now lives earlier in this file (right after
# jqp()) so the --check-healthy flag below can call it before reaching this
# point -- see that definition for the full "what healthy means" derivation.

# FENCE-EXTRACT-DISPATCH-BEGIN: check-stack-already-healthy-dispatch -- scripts/ci/fence-supabase-stack-healthy-check-strikes.sh extracts this dispatcher block VERBATIM too (concatenated after the function extraction) so the fence can never silently drift from what actually ships.
step "db-data volume check (idempotent-re-run guard, Sec-reviewed 2026-09-20)"
EXISTING_DB_VOLUME="$(sshx "docker volume ls -q --filter name=${APP_UUID}_db-data")"
NEED_DEPLOY=1
if [[ -z "$EXISTING_DB_VOLUME" ]]; then
  ok "no pre-existing db-data volume -- safe to deploy"
else
  info "${APP_UUID}_db-data already exists -- checking whether the stack is already healthy (a genuine idempotent re-run) before treating this as a poisoned volume"
  if check_stack_already_healthy; then
    if [[ -n "$SMTP_SEED_FILE" || -n "$SITE_URL_OVERRIDE" ]]; then
      info "stack already healthy, but this run pushed an operator SMTP credential and/or a SITE_URL override -- redeploying UNCONDITIONALLY, not on a value diff (measured 2026-09-23, live production: the SITE_URL/MAILER_TEMPLATES_*-only diff below missed an SMTP_PORT change entirely, since it never looked at any SMTP_* key; a diff also structurally cannot see a SMTP_PASS rotation, since that value is never read back for comparison. A stack restart per --apply run when a seed is present is the accepted cost -- ADR-074 Consequence 9: a store PATCH alone does not reach a container Coolify does not restart)."
      NEED_DEPLOY=1
    elif [[ "$EMAIL_ENV_CHANGED" == "1" ]]; then
      info "stack already healthy, but this run changed the auth-email env (SITE_URL and/or a MAILER_TEMPLATES_* value) -- redeploying so the running auth container picks it up (ADR-074 Consequence 9: a store PATCH alone does not reach a container Coolify does not restart)."
      NEED_DEPLOY=1
    else
      ok "stack already provisioned and healthy -- nothing to deploy (still running the full verification battery below to confirm, not stopping at this quick check)"
      NEED_DEPLOY=0
    fi
  else
    die "${APP_UUID}_db-data exists but the stack is NOT confirmed healthy (see the healthy-check output above for which probe failed) -- this script does not know whether it initialized against a bogus mount at some point. See docs/deployment-runbook.md §4 for how to confirm by hand, and 'docker compose --project-name $APP_UUID down -v' to destroy it ONLY once you've confirmed it's poisoned -- never automatic, never inferred from this failure alone. Refusing to deploy onto it silently."
  fi
fi
# FENCE-EXTRACT-DISPATCH-END: check-stack-already-healthy-dispatch

if [[ "$NEED_DEPLOY" == "1" ]]; then
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
fi

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

# ADR-074 Part 2(c) item 5: a DIFFERENT instrument than the store PATCH --
# `docker inspect` on the running `auth` container's own Config.Env,
# never `docker exec`, since GoTrue's image ships neither node nor curl
# (measured, real run 27; same instrument smoke-remaining-checks.sh's own
# resend_probe() already uses for exactly this reason). Confirms the
# change actually reached the container Coolify started, not just the
# Coolify env store this script PATCHed.
#
# ⚠ CORRECTED 2026-09-23, live production apply: this used to inspect
# the compose file's own fixed `container_name: supabase-auth` directly
# and died `no such object: supabase-auth` -- Coolify ignores
# docker-compose.yml's `container_name:` entirely and names every stack
# container `<service>-<project-uuid>-<timestamp>` instead (same class
# of bug scripts/invite-user.sh's own header now documents for
# `api-gw`/supabase-envoy). Resolved by compose project + service below,
# same `docker compose --project-name <uuid> ps -q <service>` +
# RUNNING-state-filter idiom scripts/smoke-remaining-checks.sh's own
# find_running_container() already uses -- never a fixed name again.
AUTH_CID_LIST="$(sshx "docker compose --project-name $APP_UUID ps -q auth | xargs -r -I{} docker inspect --format '{{.State.Running}}{{\"\\t\"}}{{.Id}}' {} | awk -F'\t' '\$1==\"true\"{print \$2}'")"
AUTH_CID_COUNT="$(printf '%s\n' "$AUTH_CID_LIST" | grep -c . || true)"
[[ "$AUTH_CID_COUNT" == "1" ]] || die "expected exactly one RUNNING 'auth' container under compose project '$APP_UUID', found $AUTH_CID_COUNT -- investigate before treating this run as done."
AUTH_CID="$AUTH_CID_LIST"
AUTH_ENV="$(sshx "docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' $AUTH_CID")"
AUTH_SITE_URL="$(printf '%s\n' "$AUTH_ENV" | sed -n 's/^GOTRUE_SITE_URL=//p')"
AUTH_MAILER_CONFIRMATION="$(printf '%s\n' "$AUTH_ENV" | sed -n 's/^GOTRUE_MAILER_TEMPLATES_CONFIRMATION=//p')"
info "auth container GOTRUE_SITE_URL=$AUTH_SITE_URL"
info "auth container GOTRUE_MAILER_TEMPLATES_CONFIRMATION=$AUTH_MAILER_CONFIRMATION"
if [[ -n "$SITE_URL_OVERRIDE" && "$AUTH_SITE_URL" != "$SITE_URL_OVERRIDE" ]]; then
  die "auth container's own GOTRUE_SITE_URL ('$AUTH_SITE_URL') does not match the SITE_URL this run set ('$SITE_URL_OVERRIDE') -- the env store PATCH did not reach the running container. Investigate before treating this run as done."
fi
[[ "$AUTH_MAILER_CONFIRMATION" == "$MAILER_TEMPLATES_CONFIRMATION" ]] \
  || die "auth container's own GOTRUE_MAILER_TEMPLATES_CONFIRMATION ('$AUTH_MAILER_CONFIRMATION') does not match the value this run computed ('$MAILER_TEMPLATES_CONFIRMATION') -- the env store PATCH did not reach the running container. Investigate before treating this run as done."
# Conditional on SMTP_SEED_FILE (an operator SMTP_PASS was provided this
# run) -- a fresh/no-seed box legitimately still carries the mint-if-
# absent local-dev placeholder port, not 2465, so asserting this
# unconditionally would false-fail that case (same conditional shape the
# SITE_URL_OVERRIDE check above already uses).
if [[ -n "$SMTP_SEED_FILE" ]]; then
  AUTH_SMTP_PORT="$(printf '%s\n' "$AUTH_ENV" | sed -n 's/^GOTRUE_SMTP_PORT=//p')"
  info "auth container GOTRUE_SMTP_PORT=$AUTH_SMTP_PORT"
  [[ "$AUTH_SMTP_PORT" == "$EXPECTED_SMTP_PORT" ]] \
    || die "auth container's own GOTRUE_SMTP_PORT ('$AUTH_SMTP_PORT') does not match the expected value ('$EXPECTED_SMTP_PORT') -- the env store PATCH did not reach the running container. Investigate before treating this run as done."
fi
ok "auth container's own env confirms the current SITE_URL/SMTP_PORT/MAILER_TEMPLATES_CONFIRMATION values (names+values, non-secret)"

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
# Sec N-5 (PR #852 AMBER review round 2): identical shape to
# check_stack_already_healthy()'s own probe (5/5), fixed there under C-4
# for the same two reasons -- negative-only (refuses on one error string,
# fail-open on every other non-canonical answer) and it retrieved the
# secret's actual value into this process via `2>&1` just to see that
# error text. `current_setting(name, true)` moves the boolean decision
# server-side; the value never leaves Postgres.
JWT_PRESENT="$(sshx "docker compose --project-name $APP_UUID exec -T db psql -U supabase_admin -d postgres -Atc \"select current_setting('app.settings.jwt_secret', true) <> '';\"" 2>/dev/null || true)"
[[ "$JWT_PRESENT" == "t" ]] || die "app.settings.jwt_secret is unset, empty, or the db did not answer -- init scripts did not run"
ok "all four role passwords set + app.settings.jwt_secret present"

ENVOY_LOG="$(sshx "docker compose --project-name $APP_UUID logs api-gw 2>&1 | tail -80")"
echo "$ENVOY_LOG" | grep -q "lds: add/update listener 'supabase'" || die "api-gw log does not show a real Envoy config load"
ok "api-gw loaded a real Envoy config"

SIGNUP_ENV="$(sshx "docker compose --project-name $APP_UUID exec -T auth printenv GOTRUE_DISABLE_SIGNUP" 2>/dev/null || true)"
[[ "$SIGNUP_ENV" == "true" ]] || die "GOTRUE_DISABLE_SIGNUP is '$SIGNUP_ENV', expected 'true' -- standing gate violated"
ok "GOTRUE_DISABLE_SIGNUP=true"

# rest is EXPECTED unhealthy until §6's migrations create the pfin schema --
# assert the SPECIFIC expected error, not just "unhealthy" (§4's rest-
# unhealthy-pre-migrations note). This branch's premise -- that PGRST_DB_SCHEMAS
# actually NAMES pfin, so PostgREST is waiting on the SCHEMA rather than never
# looking for it at all -- was FALSE in production before BACKLOG.md §7.36 item
# 22's ruling (2026-09-19); see NONSECRET_DEFAULTS above and the
# fence-pgrst-schemas-live.sh assertion just below, which is what makes this
# branch's premise checkable rather than merely stated.
REST_LOG="$(sshx "docker compose --project-name $APP_UUID logs rest 2>&1 | tail -20")"
if echo "$REST_LOG" | grep -q 'schema "pfin" does not exist'; then
  ok "rest unhealthy as expected pre-§6 (schema \"pfin\" does not exist) -- not a defect"
elif sshx "docker compose --project-name $APP_UUID ps rest --format '{{.Health}}'" 2>/dev/null | grep -qi healthy; then
  ok "rest healthy (§6 must have already run)"
else
  die "rest is unhealthy for a DIFFERENT reason than the expected pre-§6 schema gap -- check the log, this is a real failure: $(echo "$REST_LOG" | tail -5)"
fi

step "Production-observable fence: PGRST_DB_SCHEMAS live value (BACKLOG.md §7.36 item 22, Sec's fence half 2)"
# CI's own literal-match fence (scripts/ci/fence-pgrst-schemas-pfin.sh) can only
# see the REPO'S committed default (NONSECRET_DEFAULTS above), never the live
# Coolify store -- that default is check-if-absent, so correcting it never
# corrects an already-set store value. This is the half that observes the box.
#
# The grep is deliberate (Sec joint-review, PR #822, F1): the rest container's
# full environment also carries PGRST_DB_URI (with the authenticator DB
# password) and PGRST_JWT_SECRET/PGRST_APP_SETTINGS_JWT_SECRET. Filter to the
# one name this fence needs BEFORE the value leaves the container -- never run
# the bare `env` half on its own "to see what's there".
REST_ENV="$(sshx "docker compose --project-name $APP_UUID exec -T rest env | grep '^PGRST_DB_SCHEMAS=' || true" 2>&1 || true)"
if ! printf '%s\n' "$REST_ENV" | "$REPO_ROOT/scripts/ci/fence-pgrst-schemas-live.sh"; then
  die "fence-pgrst-schemas-live.sh rejected the running rest container's PGRST_DB_SCHEMAS -- see its output above. Fail closed: do not proceed while the live value disagrees with the ruled literal (BACKLOG.md §7.36 item 22)."
fi
ok "rest container's live PGRST_DB_SCHEMAS matches the ruled literal"

step "Post-move: MIGRATOR_DB_* absence assertion (ADR-072 Amendment 4 / BACKLOG.md §7.36 item 29)"
# Sec's own words on why this must be a WATCHER, not a one-time check at
# migration time: "A remedy that a routine operation reverts, with no
# watcher, is not a remedy." MINT_SECRETS is mint-if-ABSENT -- removing
# MIGRATOR_DB_USER/MIGRATOR_DB_PASSWORD from that dict (see above) stops
# THIS script from re-minting them, but it does not by itself prove the
# stack's shared env store no longer holds them (a value minted before this
# PR landed would survive silently forever otherwise). This step runs on
# EVERY --apply, not just the cutover run, so a future regression -- a
# hand-edit, a rollback, a copy-paste from an old runbook page -- is caught
# the next time this script runs, not left for someone to notice by
# accident.
#
# Proof predicate is NAMES, not values, and NOT a declared `environment:`
# block (Amendment 4, quoted exactly: "A declared `environment:` block is
# not evidence and must not be offered again -- it is exactly what failed
# at Amendment 1"). Runs `docker compose ... exec -T meta env` against a
# container INSIDE the stack's own compose project (Sec's own
# falsification used `meta`; this script uses the same container for
# continuity) and hands its raw KEY=VALUE output to
# scripts/ci/check-migrator-names-absent.sh, which reduces to names via
# `cut -d= -f1` -- a BLANKED key still carries its name and correctly
# FAILS this check; only a DELETED key passes it.
#
# ⚠ TWO DIFFERENT STRIKES, TWO DIFFERENT PLACES -- do not conflate them.
# The NAME-vs-VALUE PREDICATE (does an env dump containing this key fail
# closed?) is strikeable OFFLINE and IS strike-proven, in CI, against the
# tests/fixtures/ci/migrator-names-absent-*.env fixtures wired into
# security-scan.yml's fence-migrator-bind job -- see
# scripts/ci/check-migrator-names-absent.sh's own header for why it was
# extracted into a separate script specifically so that strike could exist
# without a live box. What is NOT strike-proven until it is actually run
# is the END-TO-END property that THIS LIVE BOX's real store is clean --
# that live strike (re-add a name to the real store, confirm this step
# goes RED naming the real box, remove it, confirm GREEN) is
# docs/deployment-runbook.md §6.8 CUTOVER PROCEDURE step 10, a numbered
# operator step, not run by this PR.
STACK_ENV_RAW="$(sshx "docker compose --project-name $APP_UUID exec -T meta env" 2>/dev/null || true)"
if [[ -z "$STACK_ENV_RAW" ]]; then
  die "could not read env off the 'meta' container in project $APP_UUID -- cannot confirm MIGRATOR_DB_* absence. Failing closed rather than skipping this assertion."
fi
if ! printf '%s\n' "$STACK_ENV_RAW" | "$REPO_ROOT/scripts/ci/check-migrator-names-absent.sh"; then
  die "the Supabase-stack's own env store still carries MIGRATOR_DB_USER and/or MIGRATOR_DB_PASSWORD (measured on the 'meta' container, names-only -- see the FAIL line above for which). ADR-072 Amendment 4's remedy is NOT complete until neither name is present -- a blanked value does not pass this check, only a deleted one does. Remove the offending key(s) from this Coolify application's env store by hand (or via the Coolify API) and re-run this script."
fi
ok "MIGRATOR_DB_USER and MIGRATOR_DB_PASSWORD both absent from the stack's own env store (measured on 'meta', names-only)"

step "External exposure -- must publish nothing but the one Studio loopback"
HOST_PORTS="$(sshx "docker ps --filter 'label=com.docker.compose.project=$APP_UUID' --format '{{.Ports}}'" | grep -oE '[0-9.]+:[0-9]+->' | sort -u || true)"
UNEXPECTED_PORTS="$(echo "$HOST_PORTS" | grep -v '^127.0.0.1:3000->' || true)"
[[ -z "$UNEXPECTED_PORTS" ]] || die "unexpected host-published port(s): $UNEXPECTED_PORTS -- only 127.0.0.1:3000 (Studio) should ever be published"
echo "$HOST_PORTS" | grep -q '^127.0.0.1:3000->' && ok "only 127.0.0.1:3000 published (Studio) -- nothing else" || info "no host ports published at all (also fine if Studio isn't in this deploy)"

info "External probe (run from OUTSIDE the box, this script cannot self-check it): nmap -Pn -p 5432,6543,8000,3000 $BOX_IP -- EXPECT all four filtered."

step "Done"
if [[ "$NEED_DEPLOY" == "1" ]]; then
  info "Deploy $DEPLOY_UUID finished and passed the verification battery."
else
  info "No new deploy was needed -- the pre-existing db-data volume's stack was already healthy, and passed the verification battery."
fi
info "Studio, once you want to look at it: ssh -L 3000:localhost:3000 root@$BOX_IP then http://localhost:3000"
