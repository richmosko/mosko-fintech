#!/usr/bin/env bash
#
# provision.sh -- the single entry point for the V1 greenfield production
# stand-up. BACKLOG.md §7.36 item 76 (W-5). DevOps-owned. Runs the 26
# ordered steps this file's own STEP_KEYS registry defines below (the
# registry IS docs/deployment-runbook.md Part 3's spec -- read `--list`
# or the array itself, never a stale row count in a comment) as ONE call
# instead of an operator running each script by hand in order.
#
# WHAT THIS IS NOT -- it does not invent new logic. Every step below
# shells out to a script that already exists and is already idempotent on
# its own; this file is the REGISTRY (order + invocation + how to tell if
# a step is already satisfied) and the LOOP (preflight, then --apply,
# stop on the first real failure, print how to resume). Read a step's own
# script for what it actually does and why -- rationale lives there, not
# here, same convention docs/deployment-runbook.md's own Part 3 uses.
#
# STEP CLASSIFICATION -- every step's OWN preflight is its done-predicate
# (each script already reports live state before touching anything; there
# is no separate "check if done" query duplicated here). After running a
# step (preflight, then --apply unless --dry-run), the exit code is read
# as:
#   0  VERIFIED       -- continue to the next step.
#   3  SKIPPED        -- non-fatal-but-not-verified (e.g.
#                         smoke-etl-poll.sh at zero active tenants);
#                         printed distinctly, continue to the next step.
#   4  MANUAL         -- this step has no script yet, or is a deliberate
#                         one-way decision (cutover) -- this script prints
#                         the by-hand instructions and STOPS; the operator
#                         completes the step, then resumes with
#                         `--from <this-step>` (its preflight will report
#                         "already satisfied" once it genuinely is, or
#                         re-print the same instructions if not).
#   anything else      -- REFUSED/FAILED -- STOP, print the resume command.
#
# WHAT --dry-run PROVES, AND WHAT IT DOES NOT -- every step's preflight
# runs (nothing mutated anywhere), but a preflight is a snapshot of
# CURRENT state, not a simulation of what --apply would do to a DIFFERENT
# state a real run might encounter later (the same limitation each
# individual script's own header already states for itself). On a
# partially-provisioned box, a step whose preflight fails because an
# EARLIER step's own output does not exist yet (--dry-run never applies
# anything, so that output genuinely is absent) is reported
# `BLOCKED-BY <step>`, using that step's own declared STEP_REQUIRES
# prerequisite -- this is EXPECTED on a fresh/partial box, not a defect,
# and does not fail the dry run. A step that fails for any OTHER reason
# is reported `would likely fail` and DOES fail the dry run (exit 3) --
# see EXIT CODES. (D-2, live `--dry-run`, 2026-09-20: the prior version
# of this script printed every non-zero preflight the same way and still
# reported overall success, which was false on the box that surfaced
# this.)
#
# USAGE
#   scripts/provision.sh                          # run every step in order: preflight, then --apply, stop on first failure
#   scripts/provision.sh --dry-run                 # every step's preflight only, nothing applied anywhere, full walkthrough
#   scripts/provision.sh --from <step-key>          # skip earlier steps, start at <step-key>
#   scripts/provision.sh --only <step-key>          # run exactly one step (preflight + apply) and stop
#   scripts/provision.sh --list                     # print the step registry (in order) and exit, nothing run
#   scripts/provision.sh --confirm-cutover          # required to let the 'cutover' step proceed past its own gate
#
# EXIT CODES
#   0  every step (or the one selected by --only, or every remaining step
#      from --from) reported VERIFIED or SKIPPED -- or, under --dry-run,
#      every step reported VERIFIED/SKIPPED/MANUAL/BLOCKED-BY-an-earlier-
#      step-not-yet-applied (see the summary counts printed at the end).
#   1  a step reported MANUAL and this run stopped there (an unavoidable
#      by-hand moment, not a script defect).
#   2  a step reported a real failure (REFUSED/FAILED) and this run
#      stopped there.
#   3  a precondition this script could not even attempt under (missing
#      operator-provided .env names, unknown --from/--only step key) --
#      OR, under --dry-run only, one or more steps reported "would likely
#      fail" for a reason other than an earlier step's own output being
#      absent (the summary names how many and each rc=).
#
# ORCHESTRATOR CONTRACT: non-interactive, no prompts, no `read` anywhere
# in this file or any step it calls in preflight/--apply mode. Every step
# is re-run from its own live state, never from this script's own cached
# assumptions about a prior run.

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
# SCRIPTS override exists solely for scripts/ci/fence-provision-strikes.sh
# to point every per-step invocation at fake stand-ins -- never set this
# in a real run.
SCRIPTS="${SCRIPTS:-$REPO_ROOT/scripts}"

die3() { printf '\n\033[31mFAIL\033[0m  %s\n' "$*" >&2; exit 3; }
ok()    { printf '\033[32m  ok\033[0m  %s\n' "$*"; }
info()  { printf '      %s\n' "$*"; }
step()  { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
warn()  { printf '\033[33m  ..\033[0m  %s\n' "$*"; }

# --- Flags -------------------------------------------------------------
DRY_RUN=0
FROM_STEP=""
ONLY_STEP=""
LIST_ONLY=0
CONFIRM_CUTOVER=0
SKIP_DEPENDENCY_CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --from) shift; FROM_STEP="${1:-}" ;;
    --only) shift; ONLY_STEP="${1:-}" ;;
    --list) LIST_ONLY=1 ;;
    --confirm-cutover) CONFIRM_CUTOVER=1 ;;
    --skip-dependency-check) SKIP_DEPENDENCY_CHECK=1 ;;
    *) echo "unknown flag: $1" >&2; echo "usage: $0 [--dry-run] [--from <step>] [--only <step>] [--list] [--confirm-cutover] [--skip-dependency-check]" >&2; exit 3 ;;
  esac
  shift || true
done

# --- Ordered step registry (bash 3.2: parallel arrays, no assoc arrays) -
# 26 steps. Re-sequenced a THIRD time (Sec VETO-1, PR #849 review):
# `migrator-app` now runs BEFORE `db-bootstrap`, not after --
# `db-bootstrap`'s Phase 2 (`docker compose --project-name $MIGRATOR_UUID
# exec -T migrator ...`) needs a RUNNING migrator container, which
# `migrator-app` (provision-migrator-app.sh) is what creates AND deploys;
# `db-bootstrap.sh` also resolves the migrator app's uuid by name and
# `die2`s if it does not exist yet. `db-bootstrap` still precedes
# `pgrst-gates` -- B-2's live migration-ledger count is meaningless
# against an empty (pre-bootstrap) ledger. Prior order (this session):
# db-bootstrap -> the §6.9 PGRST-exposure pre-flip gates + flip (BEFORE
# any Coolify resource creation -- smoke-pfin-exposure.sh's default mode
# asserts pfin is ALREADY exposed) -> the standalone migrator app + its
# Scheduled Task -> app/worker resource creation -> every env-writing
# step for a resource VERIFIED before that resource is ever deployed
# (mint-jwt is the LAST env write on app, by construction) -> deploys ->
# scheduled tasks -> smokes -> the CA-1/§10 checks -> DNS/GitHub-CI -> the
# DEPLOY_ON_SUCCESS flip -> cutover. Do not build this registry from
# memory of an earlier draft -- it has moved three times already this
# session. The unnumbered "GitHub Environment reviewer approval" row is
# deliberately NOT a step here -- it recurs on every migrator trigger
# fire, not once at stand-up.
STEP_KEYS=(
  provision-vps
  standup
  migrator-app
  db-bootstrap
  pgrst-gates
  pgrst-flip
  migrator-scheduled-task
  provision-resources
  record-uuids
  nonsecret-env
  secrets
  mint-jwt
  etl-role
  provider-sync-role
  deploy-app
  deploy-workers
  scheduled-tasks
  smokes
  ca1-gate
  remaining-checks
  discord
  dns
  ci-keypair
  github-ci
  deploy-on-success
  cutover
)
STEP_LABELS=(
  "Provision + harden the box, install Coolify, bootstrap the admin account (§1+§3)"
  "Stand up the Supabase stack; mint real JWT keys (§4)"
  "Create the standalone migrator Coolify resource (ADR-072 Amendment 4)"
  "Database bootstrap: pfin_owner/migrator, migrations, vault decrypt view (§6.3)"
  "Pre-flip gates B-1/B-2/B-3: VETO trigger, migration count, 025 presence (§6.9 steps 1-3)"
  "Flip the pfin Data-API exposure (§6.9 steps 4-6)"
  "Create the migrator db-push Scheduled Task"
  "Create app/etl/pdf-render/provider-sync Coolify resources (§7.1/§7.2 step i)"
  "Record all Coolify resource UUIDs into .env"
  "Set non-secret env: app's PUBLIC_SUPABASE_URL, each worker's PFIN_DB_*/PLAID_ENV (§7.2 step ii)"
  "Push the mapped production secrets to all four resources (§5)"
  "Mint real ANON_KEY/SERVICE_ROLE_KEY onto app -- LAST of every env write on app"
  "Activate pfin_etl login, deliver PFIN_DB_PASSWORD (§6.1)"
  "Activate pfin_provider_sync login, deliver PFIN_DB_PASSWORD (§6.2)"
  "Deploy app, smoke its own Data-API path"
  "Deploy etl/provider-sync/pdf-render (§7.2 deploy steps)"
  "Create the etl monthly-report and provider-sync daily-poll Scheduled Tasks"
  "Smoke: admission endpoint (CA-2), ETL poll, PDF round-trip, pfin exposure"
  "CA-1 deploy-gate: provider-sync's injected env names vs PUBLIC_ROUTE_ENV_MATCHERS"
  "Remaining §10 checks: CA-7 reachability, TZ-1 pin, RLS isolation, auth login (unavoidable manual, no script exists for any)"
  "Re-establish Coolify -> Discord notifications (§8) -- unavoidable manual, no API surface measured"
  "DNS + Coolify domain assignment + LE cert (§2)"
  "CI-trigger keypair + box-side wiring (§6.4)"
  "GitHub-side CI setup: Actions secret/variable, production-migrator Environment (§6.4)"
  "Flip DEPLOY_ON_SUCCESS=1 (provision-vps.sh re-run)"
  "Cutover: tear down the incumbent pfindash.com stack (§9)"
)

# --- STEP_REQUIRES (Sec F-5, PR #849 review) -- a declared, semantic
# dependency per step (comma-separated step keys, empty = no hard
# prerequisite). Checked ONLY for the step NAMED on --only/--from itself
# (the jump target) -- never during a full, unfiltered run (registry
# order already enforces it there; this closes the gap --only/--from
# opens at the exact point of the jump).
# SCOPE, stated plainly: the check LIVE-RE-RUNS the prerequisite's own
# PREFLIGHT (mode "", no --apply -- read-only by every script in this
# registry's own documented convention, safe to re-run any number of
# times) and requires it to report VERIFIED/SKIPPED/MANUAL, never a
# `--apply` re-run of the prerequisite itself (that would perform its
# real side effects as a side effect of CHECKING a precondition -- wrong
# for a gate). This is NOT a query of "has this step's resource ever
# been fully created" for every step -- several scripts' own preflight
# reports 0 regardless of completion state (it means "I can assess state
# without error", not "the target condition is met"); it DOES catch an
# ACTIVELY UNSATISFIED precondition, which is the exact case Sec named:
# pgrst-gates has NO preflight/apply distinction at all (every call IS
# the real, live B-1/B-2/B-3 check), so re-running it here as
# `pgrst-flip`'s prerequisite check is the actual gate, not a proxy for
# one. Worst instance this closes (Sec, PR #849 review): `--only
# pgrst-flip` used to run with the VETO gate never evaluated, exposing
# `pfin` on the Data API with no check that anon holds no grant on it.
# `--skip-dependency-check` overrides this gate explicitly, printing what
# it is skipping -- for a prerequisite already known-satisfied from a
# state this check cannot observe (e.g. re-running a single downstream
# step, well after its own prerequisites landed, where the prerequisite
# script itself has no live way to prove "already done" via preflight
# alone).
STEP_REQUIRES=(
  ""                        # provision-vps
  "provision-vps"           # standup
  "standup"                 # migrator-app
  "migrator-app"            # db-bootstrap
  "db-bootstrap"            # pgrst-gates
  "pgrst-gates"              # pgrst-flip -- Sec's own named minimum
  "migrator-app"            # migrator-scheduled-task
  "pgrst-flip"               # provision-resources -- no app/worker creation before the flip (registry's own stated rule)
  "provision-resources"      # record-uuids
  "record-uuids"             # nonsecret-env
  "nonsecret-env"            # secrets
  "secrets"                  # mint-jwt
  "db-bootstrap"             # etl-role -- the role must exist (055/116 migrations)
  "db-bootstrap"             # provider-sync-role
  "mint-jwt"                 # deploy-app -- Sec's own named "milder" example
  "secrets"                  # deploy-workers
  "deploy-workers"           # scheduled-tasks
  "deploy-app,deploy-workers" # smokes
  "deploy-workers"           # ca1-gate -- provider-sync must be deployed
  "smokes"                   # remaining-checks
  ""                          # discord -- independent notification wiring, no hard prerequisite
  "deploy-app"               # dns
  "provision-vps"            # ci-keypair
  "ci-keypair"                # github-ci
  "github-ci"                 # deploy-on-success
  ""                          # cutover -- gated separately by --confirm-cutover, not this mechanism
)

if [[ "$LIST_ONLY" -eq 1 ]]; then
  step "Step registry"
  for i in "${!STEP_KEYS[@]}"; do
    printf '  %2d. %-20s %s\n' "$((i + 1))" "${STEP_KEYS[$i]}" "${STEP_LABELS[$i]}"
  done
  exit 0
fi

# --- .env operator-provided-name preflight (names only, per Part 2 of
# docs/deployment-runbook.md -- hand-maintained here, same posture as
# that prose list; keep in sync with it by hand, not derived, since "what
# a human must fill in before the FIRST run" is a judgment list distinct
# from fence-operator-env-template.sh's derived "what does any script
# READ" set) -------------------------------------------------------------
REQUIRED_OPERATOR_NAMES=(
  HETZNER_API_TOKEN
  COOLIFY_ADMIN_EMAIL
  COOLIFY_ADMIN_NAME
  COOLIFY_ADMIN_PASSWORD
  SMTP_PASS
  PDF_WORKER_SIGNING_KEY
  WORKER_ADMISSION_SHARED_SECRET
  DISCORD_WEBHOOK_URL
  FMP_API_KEY
  BLS_API_KEY
  PLAID_CLIENT_ID
  PLAID_SECRET
  SIMPLEFIN_TOKEN
  PORKBUN_API_KEY
  PORKBUN_SECRET_KEY
)
[[ -f "$REPO_ROOT/.env" ]] || die3 ".env not found at $REPO_ROOT/.env -- copy scripts/provision.env.example to .env and fill in the operator-provided values (Part 1/Part 2 of docs/deployment-runbook.md) first"
MISSING_NAMES=()
for name in "${REQUIRED_OPERATOR_NAMES[@]}"; do
  val="$(grep -m1 "^$name=" "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
  [[ -n "$val" ]] || MISSING_NAMES+=("$name")
done
if [[ ${#MISSING_NAMES[@]} -gt 0 ]]; then
  die3 "$REPO_ROOT/.env is missing a value for: ${MISSING_NAMES[*]} (names only -- see scripts/provision.env.example)"
fi
ok ".env carries every operator-provided name this run needs"

# --- ci-migrate keypair check-and-create (non-interactive) --------------
CI_MIGRATE_SSH_PUBKEY="$(grep -m1 '^CI_MIGRATE_SSH_PUBKEY=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true)"
[[ -n "$CI_MIGRATE_SSH_PUBKEY" ]] || CI_MIGRATE_SSH_PUBKEY="$HOME/.ssh/id_ed25519_ci_migrate.pub"
CI_MIGRATE_SSH_PRIVATE_KEY_PATH="${CI_MIGRATE_SSH_PUBKEY%.pub}"
if [[ -f "$CI_MIGRATE_SSH_PUBKEY" && -f "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH" ]]; then
  ok "ci-migrate keypair already present at $CI_MIGRATE_SSH_PRIVATE_KEY_PATH{,.pub}"
elif [[ -f "$CI_MIGRATE_SSH_PUBKEY" || -f "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH" ]]; then
  die3 "ci-migrate keypair is HALF present ($CI_MIGRATE_SSH_PRIVATE_KEY_PATH / $CI_MIGRATE_SSH_PUBKEY) -- investigate by hand before this script generates over it"
elif [[ "$DRY_RUN" -eq 1 ]]; then
  info "ci-migrate keypair absent -- would run: ssh-keygen -t ed25519 -N '' -f $CI_MIGRATE_SSH_PRIVATE_KEY_PATH (skipped, --dry-run)"
else
  mkdir -p "$(dirname "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH")"
  ssh-keygen -t ed25519 -N '' -f "$CI_MIGRATE_SSH_PRIVATE_KEY_PATH" -q
  ok "generated ci-migrate keypair at $CI_MIGRATE_SSH_PRIVATE_KEY_PATH{,.pub}"
fi

load_box_ip() {
  grep -m1 '^BOX_IP=' "$REPO_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '\r\n' || true
}

# require_box_ip -- ONE mechanism for every run_* function whose
# underlying script requires BOX_IP passed via the environment, never
# defaulted, never self-read from .env (provision-migrator-app.sh,
# migrator-scheduled-task.sh, coolify-env.sh, provision-app.sh,
# provision-worker.sh, record-coolify-uuids.sh, push-production-
# secrets.sh, mint-supabase-jwt-keys.sh, db-role-handoff.sh, deploy-
# app.sh, every smoke-*.sh, worker-scheduled-task.sh -- "the same
# discipline as provision-supabase-stack.sh", per those scripts' own
# headers). Sets and EXPORTS the global BOX_IP, read FRESH from .env on
# every call -- never cached across steps, because provision-vps.sh's
# own --apply (step 1) writes BOX_IP to .env for the first time mid-run,
# so a later step in the SAME invocation must see the value THIS run
# just produced, not a stale empty read from before step 1 executed.
# Once exported here, every subsequent `bash "$SCRIPTS/...sh"` call in
# the calling function inherits it automatically -- replacing the prior
# per-call-site `BOX_IP="$box_ip" bash ...` prefix, which was correct
# but duplicated across ~13 functions and ~20 call sites, and is the
# exact shape that let two sub-scripts (provision-migrator-app.sh,
# migrator-scheduled-task.sh) get missed entirely (D-1, live
# `--dry-run`, 2026-09-20 -- both failed "BOX_IP is required, not
# defaulted" at the real run's step 3). A third, MASKED instance:
# run_mint_jwt below used to omit BOX_IP entirely too, silently falling
# through to mint-supabase-jwt-keys.sh's own hardcoded
# `${BOX_IP:-188.245.166.206}` default -- happened to be this
# deployment's real box IP, so it "worked", but is the exact silent-
# prod-fallback shape every OTHER script in this registry explicitly
# refuses to do. Fixed the same way: explicit, never assumed.
require_box_ip() {
  BOX_IP="$(load_box_ip)"
  [[ -n "$BOX_IP" ]] || return 2
  export BOX_IP
  return 0
}

resume_hint() {
  printf '\nresume: scripts/provision.sh --from %s\n' "$1" >&2
}

# result_status_for <key> -- prints THIS run's already-recorded
# RESULT_STATUS for <key> (steps run in order, so a step's own declared
# STEP_REQUIRES prerequisite -- always earlier in STEP_KEYS -- has
# already been recorded by the time this is called); prints nothing and
# returns 1 if <key> has not run in this invocation (e.g. --from/--only
# skipped it -- treated as "unknown", never as blocked, since this run
# never observed its actual state).
result_status_for() {
  local want="$1" j
  for j in "${!RESULT_KEYS[@]}"; do
    if [[ "${RESULT_KEYS[$j]}" == "$want" ]]; then
      printf '%s' "${RESULT_STATUS[$j]}"
      return 0
    fi
  done
  return 1
}

# is_satisfied_status <status> -- true if a prerequisite step's own
# RESULT_STATUS this dry run counts as "its own condition is met", for
# BLOCKED-BY classification purposes (D-2, live --dry-run, 2026-09-20).
is_satisfied_status() {
  case "$1" in
    "VERIFIED (dry-run)"|"SKIPPED (dry-run)"|"MANUAL (dry-run)") return 0 ;;
    *) return 1 ;;
  esac
}

# print_summary_and_exit <failed-step-key> <exit-code> -- prints the
# resume hint, the summary table so far, and exits. Single choke point so
# every stop path (preflight MANUAL/FAILED, apply MANUAL/FAILED) prints
# the identical shape.
print_summary_and_exit() {
  local failed_key="$1" code="$2" j
  resume_hint "$failed_key"
  step "Summary"
  for j in "${!RESULT_KEYS[@]}"; do printf '  %-20s %s\n' "${RESULT_KEYS[$j]}" "${RESULT_STATUS[$j]}"; done
  exit "$code"
}

# --- Per-step command functions -----------------------------------------
# Each takes one arg: "" (preflight) or "--apply". Prints what it does;
# returns the underlying script's own exit code, or 4 for a MANUAL step.

run_provision_vps()      { bash "$SCRIPTS/provision-vps.sh" ${1:+--apply}; }
run_standup()             { bash "$SCRIPTS/standup.sh" ${1:+--apply}; }

run_db_bootstrap() { bash "$SCRIPTS/db-bootstrap.sh" ${1:+--apply}; }

run_pgrst_gates() { bash "$SCRIPTS/pgrst-exposure-gates.sh"; }

run_pgrst_flip() {
  require_box_ip || return 2
  bash "$SCRIPTS/coolify-env.sh" set pfin-supabase-stack PGRST_DB_SCHEMAS=public,graphql_public,pfin ${1:+--apply --deploy}
}

run_migrator_app() { require_box_ip || return 2; bash "$SCRIPTS/provision-migrator-app.sh" ${1:+--apply}; }

run_migrator_scheduled_task() { require_box_ip || return 2; bash "$SCRIPTS/migrator-scheduled-task.sh" ${1:+--apply}; }

run_provision_resources() {
  require_box_ip || return 2
  bash "$SCRIPTS/provision-app.sh" ${1:+--apply} || return $?
  local rc
  for name in pfin-back-etl pfin-pdf-render pfin-provider-sync; do
    bash "$SCRIPTS/provision-worker.sh" "$name" ${1:+--apply}; rc=$?
    [[ $rc -eq 0 ]] || return $rc
  done
  return 0
}

run_record_uuids() { require_box_ip || return 2; bash "$SCRIPTS/record-coolify-uuids.sh" ${1:+--apply}; }

run_nonsecret_env() {
  require_box_ip || return 2
  bash "$SCRIPTS/coolify-env.sh" set pfin-app PUBLIC_SUPABASE_URL=http://api-gw:8000 ${1:+--apply} || return $?
  bash "$SCRIPTS/coolify-env.sh" set pfin-back-etl \
    PFIN_DB_HOST=db PFIN_DB_PORT=5432 PFIN_DB_NAME=postgres PFIN_DB_USER=pfin_etl PFIN_DB_SSLMODE=disable ${1:+--apply} || return $?
  bash "$SCRIPTS/coolify-env.sh" set pfin-provider-sync \
    PFIN_DB_HOST=db PFIN_DB_PORT=5432 PFIN_DB_NAME=postgres PFIN_DB_USER=pfin_provider_sync PFIN_DB_SSLMODE=disable PLAID_ENV=production ${1:+--apply}
}

run_secrets() { require_box_ip || return 2; bash "$SCRIPTS/push-production-secrets.sh" ${1:+--apply --skip-missing-resource}; }

run_mint_jwt() { require_box_ip || return 2; bash "$SCRIPTS/mint-supabase-jwt-keys.sh" ${1:+--apply --app-name pfin-app --verify-live}; }

run_etl_role()             { require_box_ip || return 2; bash "$SCRIPTS/db-role-handoff.sh" pfin_etl ${1:+--apply}; }
run_provider_sync_role()   { require_box_ip || return 2; bash "$SCRIPTS/db-role-handoff.sh" pfin_provider_sync ${1:+--apply}; }

run_deploy_app() {
  require_box_ip || return 2
  bash "$SCRIPTS/deploy-app.sh" pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app \
    --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY \
    --require-network APP_STACK_NETWORK_NAME --resolve-host api-gw ${1:+--apply} || return $?
  [[ -n "${1:-}" ]] || return 0
  bash "$SCRIPTS/smoke-pfin-exposure.sh" pfin-app --compose-service app
}

run_deploy_workers() {
  require_box_ip || return 2
  for name in pfin-back-etl pfin-provider-sync pfin-pdf-render; do
    case "$name" in
      pfin-back-etl)      bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/etl --expect-build-pack dockercompose --compose-service pfin-back-etl-monthly-report --require-network ETL_STACK_NETWORK_NAME --resolve-host db ${1:+--apply} || return $? ;;
      pfin-provider-sync) bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/provider-sync --expect-build-pack dockercompose --compose-service provider-sync --require-network PROVIDER_SYNC_STACK_NETWORK_NAME --resolve-host db ${1:+--apply} || return $? ;;
      pfin-pdf-render)    bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/pdf-render --expect-build-pack dockercompose --compose-service pdf-render --require-network PDF_RENDER_STACK_NETWORK_NAME ${1:+--apply} || return $? ;;
    esac
  done
}

run_scheduled_tasks() {
  require_box_ip || return 2
  bash "$SCRIPTS/worker-scheduled-task.sh" pfin-back-etl-monthly-report ${1:+--apply} || return $?
  bash "$SCRIPTS/worker-scheduled-task.sh" pfin-provider-sync-daily-poll ${1:+--apply}
}

run_smokes() {
  require_box_ip || return 2
  local rc
  bash "$SCRIPTS/smoke-admission-endpoint.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  local worst=$rc
  bash "$SCRIPTS/smoke-etl-poll.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  [[ $rc -eq 3 ]] && worst=3
  bash "$SCRIPTS/smoke-pdf-roundtrip.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  [[ $rc -eq 3 ]] && worst=3
  bash "$SCRIPTS/smoke-pfin-exposure.sh" pfin-app --compose-service app; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  [[ $rc -eq 3 ]] && worst=3
  return "$worst"
}

run_ca1_gate() { require_box_ip || return 2; bash "$SCRIPTS/smoke-ca1-env-pattern.sh"; }

run_remaining_checks() {
  step "remaining-checks: BY-HAND (CA-7 reachability, TZ-1 pin, RLS isolation, auth login -- see docs/archive/deployment-runbook-rationale-2026-09-20.md §10)"
  info "No script covers any of these four today. TZ-1's own canonical query is fenced verbatim in this file's own header comment block (kept token-identical to supabase/tests/01_session_timezone.sql's (T3) by scripts/ci/check-tz-sweep-identical.py) -- scripting it was considered and deliberately NOT done in this pass (not named in team-lead's explicit ask; a hasty SSH-logic addition inside this orchestrator, duplicating the sshx() pattern every sibling script already carries in its OWN file, was judged worse than leaving this one query manual for now). CA-7 (Supabase datastore reachability) has no smoke script built at all. RLS isolation and auth login are QA-owned by design, not a DevOps scripting gap."
  info "Ship-block gate on the cutover step -- all four must pass before that step's own --confirm-cutover is meaningful."
  return 4
}

run_discord() {
  step "discord: BY-HAND (BACKLOG §7.36 item 74). Measured-as-absent by omission, not confirmed by a live 404: every api() call in every script in this repo targets /applications, /applications/<uuid>, /environments -- grepped across scripts/*.sh for a notification-channel or webhook-config endpoint, zero hits. No live Coolify 4.3.18 install was reachable to confirm this offline -- if a notification-config surface DOES exist and this measurement is wrong, correct this step, don't just work around it by hand indefinitely."
  info "Coolify dashboard -> Notifications -> add/confirm the Discord webhook. Verify: a test event is received."
  return 4
}

# Sec F-6 (PR #849 review): gated behind --confirm-cutover, the SAME
# structural gate as run_cutover() below -- the apex A repoint is the
# user-visible go-live switch (DNS resolving to the new box IS the
# cutover, from every outside observer's point of view), so it must not
# be reachable via a bare --apply any more than the incumbent-stack
# tear-down is. Once --confirm-cutover is passed, this behaves exactly
# as before (preflight then --apply as $1 dictates) -- on THIS
# deployment DNS already points at the box (measured live, pfindash.com
# -> this box's IP), so the step reads VERIFIED/no-op even after the
# gate opens; the gate is structural, not a response to a real pending
# change.
run_dns() {
  if [[ "$CONFIRM_CUTOVER" -ne 1 ]]; then
    step "dns: REFUSED without --confirm-cutover"
    info "The apex A repoint is the user-visible go-live switch (Sec F-6, PR #849 review) -- gated the same as cutover, deliberately never reachable via a bare --apply."
    info "Re-run: scripts/provision.sh --from dns --confirm-cutover  once ready to go live."
    return 4
  fi
  bash "$SCRIPTS/assign-app-domain.sh" ${1:+--apply}
}

run_ci_keypair() { run_provision_vps "$1"; }

# NOTE (bubble-up, not silently decided): the per-fire GitHub reviewer
# approval flow -- provision.sh dispatching a real migrator fire, then
# polling `gh api` for the pending-deployment state and printing the
# exact review URL rather than telling the human to go find it -- is NOT
# built in this step. Building a "fire a real production migration
# trigger" mechanism inside an orchestrator's own registry, under time
# pressure, without a live box to verify the poll loop against, is
# exactly the kind of one-way-door judgment call this repo's own
# DevOps role definition says to flag rather than self-adjudicate.
# github-ci-setup.sh's own scope (set up the secret/variable/environment
# gate) is unchanged and complete; the trigger-and-poll wrapper is
# deferred, stated here, not hidden.
run_github_ci() { bash "$SCRIPTS/github-ci-setup.sh" ${1:+--apply}; }

run_deploy_on_success() {
  step "deploy-on-success: flip DEPLOY_ON_SUCCESS=1 in .env, then re-run provision-vps.sh to push it to the box's /etc/pfin/migrator-trigger.conf"
  if [[ -n "${1:-}" ]]; then
    if grep -q '^DEPLOY_ON_SUCCESS=' "$REPO_ROOT/.env" 2>/dev/null; then
      sed -i.bak 's/^DEPLOY_ON_SUCCESS=.*/DEPLOY_ON_SUCCESS=1/' "$REPO_ROOT/.env" && rm -f "$REPO_ROOT/.env.bak"
    else
      printf 'DEPLOY_ON_SUCCESS=1\n' >> "$REPO_ROOT/.env"
    fi
  fi
  run_provision_vps "$1"
}

run_cutover() {
  if [[ "$CONFIRM_CUTOVER" -ne 1 ]]; then
    step "cutover: REFUSED without --confirm-cutover"
    info "This is a one-way F/CTO decision, not a probe -- deliberately never bundled into a bare --apply."
    info "Re-run: scripts/provision.sh --from cutover --confirm-cutover  once every prior step is genuinely green."
    return 4
  fi
  step "cutover: BY-HAND even with --confirm-cutover (the final row -- no script exists; this flag only lets provision.sh proceed PAST its own gate)"
  info "Confirm the smokes and remaining-checks steps are both fully green, then tear down the incumbent pfindash.com stack by hand."
  return 4
}

run_step() {
  local key="$1" mode="$2"
  case "$key" in
    provision-vps)           run_provision_vps "$mode" ;;
    standup)                 run_standup "$mode" ;;
    db-bootstrap)            run_db_bootstrap "$mode" ;;
    pgrst-gates)             run_pgrst_gates "$mode" ;;
    pgrst-flip)              run_pgrst_flip "$mode" ;;
    migrator-app)            run_migrator_app "$mode" ;;
    migrator-scheduled-task) run_migrator_scheduled_task "$mode" ;;
    provision-resources)     run_provision_resources "$mode" ;;
    record-uuids)            run_record_uuids "$mode" ;;
    nonsecret-env)           run_nonsecret_env "$mode" ;;
    secrets)                 run_secrets "$mode" ;;
    mint-jwt)                run_mint_jwt "$mode" ;;
    etl-role)                run_etl_role "$mode" ;;
    provider-sync-role)      run_provider_sync_role "$mode" ;;
    deploy-app)              run_deploy_app "$mode" ;;
    deploy-workers)          run_deploy_workers "$mode" ;;
    scheduled-tasks)         run_scheduled_tasks "$mode" ;;
    smokes)                  run_smokes "$mode" ;;
    ca1-gate)                run_ca1_gate "$mode" ;;
    remaining-checks)        run_remaining_checks "$mode" ;;
    discord)                 run_discord "$mode" ;;
    dns)                     run_dns "$mode" ;;
    ci-keypair)              run_ci_keypair "$mode" ;;
    github-ci)               run_github_ci "$mode" ;;
    deploy-on-success)       run_deploy_on_success "$mode" ;;
    cutover)                 run_cutover "$mode" ;;
    *) return 9 ;;
  esac
}

step_index() {
  local key="$1" i
  for i in "${!STEP_KEYS[@]}"; do
    [[ "${STEP_KEYS[$i]}" == "$key" ]] && { echo "$i"; return 0; }
  done
  return 1
}

# --- Resolve which steps to run ------------------------------------------
START_IDX=0
END_IDX=$((${#STEP_KEYS[@]} - 1))
JUMPED=0
if [[ -n "$ONLY_STEP" ]]; then
  IDX="$(step_index "$ONLY_STEP")" || { echo "FAIL: unknown step '$ONLY_STEP' -- see --list" >&2; exit 3; }
  START_IDX="$IDX"; END_IDX="$IDX"
  JUMPED=1
elif [[ -n "$FROM_STEP" ]]; then
  IDX="$(step_index "$FROM_STEP")" || { echo "FAIL: unknown step '$FROM_STEP' -- see --list" >&2; exit 3; }
  START_IDX="$IDX"
  JUMPED=1
fi

# --- Dependency check (Sec F-5, PR #849 review) -- only when --only/
# --from actually SKIPS earlier steps (a plain unfiltered run needs none
# of this; registry order already enforces it). For every step this
# invocation will run, LIVE-RECHECK its declared STEP_REQUIRES
# prerequisite's own preflight (read-only, no --apply, same call every
# script in this registry already documents as side-effect-free) and
# require it to report VERIFIED(0)/SKIPPED(3)/MANUAL(4) -- MANUAL counts
# as satisfied because it is BY DEFINITION never machine-re-verifiable
# (a human already handled it; refusing on it would make `--from <step>`
# permanently unusable right after any MANUAL step, breaking Part 3's own
# documented resume flow). This does NOT catch "the prerequisite step
# has never been run at all" for a stateful step whose own preflight
# always reports 0 regardless of completion (most resource-creation
# scripts in this registry) -- it DOES catch an ACTIVELY UNSATISFIED
# precondition, which is the exact case Sec named: pgrst-gates has no
# preflight/apply distinction at all (every call is the real, live B-1/
# B-2/B-3 check), so re-running it here as `pgrst-flip`'s prerequisite
# check IS the real gate -- `--only pgrst-flip` can no longer expose
# `pfin` on the Data API with the VETO gate never evaluated.
# Only the JUMP-TARGET's own prerequisite is checked (STEP_KEYS[START_IDX]
# -- the step named on --only/--from itself), not every step in the rest
# of the range: once execution is proceeding forward from START_IDX in
# this same invocation, every LATER step's own prerequisite that also
# falls within [START_IDX, END_IDX) is satisfied by this run's own
# sequential execution reaching it first (the registry's normal
# ordering guarantee, unchanged); a later step whose prerequisite falls
# BEFORE START_IDX (e.g. ci-keypair's own provision-vps, several steps
# ahead of a `--from provision-resources`) is a real but much lower-
# stakes gap than the one Sec named, deliberately left to
# `--skip-dependency-check` rather than making every deep `--from` pay
# for re-validating the whole prefix on every step.
reqs="${STEP_REQUIRES[$START_IDX]:-}"
if [[ "$JUMPED" -eq 1 && -n "$reqs" ]]; then
  if [[ "$SKIP_DEPENDENCY_CHECK" -eq 1 ]]; then
    echo "SKIPPING dependency check: '${STEP_KEYS[$START_IDX]}' declares '$reqs' as a prerequisite -- --skip-dependency-check passed, not verifying it." >&2
  else
    IFS=',' read -r -a req_list <<< "$reqs"
    for req in "${req_list[@]}"; do
      [[ -n "$req" ]] || continue
      set +e
      run_step "$req" ""
      req_rc=$?
      set -e
      if [[ "$req_rc" != "0" && "$req_rc" != "3" && "$req_rc" != "4" ]]; then
        echo "" >&2
        echo "FAIL: '${STEP_KEYS[$START_IDX]}' declares '$req' as a prerequisite, and $req's own live preflight just reported rc=$req_rc (not VERIFIED/SKIPPED/MANUAL) -- refusing to jump past it. Run '$req' first, or pass --skip-dependency-check to override (prints what it is skipping)." >&2
        exit 3
      fi
    done
  fi
fi

# --- Run ------------------------------------------------------------------
RESULT_KEYS=()
RESULT_STATUS=()
for ((i = START_IDX; i <= END_IDX; i++)); do
  key="${STEP_KEYS[$i]}"
  label="${STEP_LABELS[$i]}"
  step "Step $((i + 1))/${#STEP_KEYS[@]}: $key -- $label"

  info "preflight"
  set +e
  run_step "$key" ""
  PREFLIGHT_RC=$?
  set -e

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ $PREFLIGHT_RC -eq 0 ]]; then
      RESULT_STATUS+=("VERIFIED (dry-run)")
    elif [[ $PREFLIGHT_RC -eq 3 ]]; then
      RESULT_STATUS+=("SKIPPED (dry-run)")
    elif [[ $PREFLIGHT_RC -eq 4 ]]; then
      RESULT_STATUS+=("MANUAL (dry-run)")
    else
      # D-2 (live --dry-run, 2026-09-20): a real preflight failure code
      # here does NOT always mean a genuine defect -- nothing is ever
      # applied in --dry-run, so once one step's resource is absent (a
      # fresh/partially-provisioned box), every step downstream of it
      # ALSO fails its own preflight for the exact same underlying
      # reason (its own resource, built by an earlier step, was never
      # actually created either). Distinguish that expected cascade from
      # an independent failure by checking whether THIS step's own
      # declared STEP_REQUIRES prerequisite was itself satisfied earlier
      # in this SAME dry run.
      blocked_by=""
      reqs_i="${STEP_REQUIRES[$i]:-}"
      if [[ -n "$reqs_i" ]]; then
        IFS=',' read -r -a req_list_i <<< "$reqs_i"
        for req_i in "${req_list_i[@]}"; do
          [[ -n "$req_i" ]] || continue
          prior_status="$(result_status_for "$req_i")" && {
            if ! is_satisfied_status "$prior_status"; then
              blocked_by="$req_i"
              break
            fi
          }
        done
      fi
      if [[ -n "$blocked_by" ]]; then
        RESULT_STATUS+=("BLOCKED-BY $blocked_by (dry-run, rc=$PREFLIGHT_RC)")
      else
        RESULT_STATUS+=("would likely fail (dry-run, rc=$PREFLIGHT_RC)")
      fi
    fi
    RESULT_KEYS+=("$key")
    continue
  fi

  if [[ $PREFLIGHT_RC -eq 4 ]]; then
    RESULT_KEYS+=("$key"); RESULT_STATUS+=("MANUAL")
    print_summary_and_exit "$key" 1
  fi
  if [[ $PREFLIGHT_RC -ne 0 && $PREFLIGHT_RC -ne 3 ]]; then
    RESULT_KEYS+=("$key"); RESULT_STATUS+=("FAILED (preflight rc=$PREFLIGHT_RC)")
    print_summary_and_exit "$key" 2
  fi

  info "apply"
  set +e
  run_step "$key" "--apply"
  APPLY_RC=$?
  set -e

  case $APPLY_RC in
    0) RESULT_KEYS+=("$key"); RESULT_STATUS+=("VERIFIED"); ok "$key: VERIFIED" ;;
    3) RESULT_KEYS+=("$key"); RESULT_STATUS+=("SKIPPED"); warn "$key: SKIPPED (non-fatal-but-not-verified)" ;;
    4)
      RESULT_KEYS+=("$key"); RESULT_STATUS+=("MANUAL")
      print_summary_and_exit "$key" 1
      ;;
    *)
      RESULT_KEYS+=("$key"); RESULT_STATUS+=("FAILED (apply rc=$APPLY_RC)")
      print_summary_and_exit "$key" 2
      ;;
  esac
done

step "Summary"
for j in "${!RESULT_KEYS[@]}"; do printf '  %-20s %s\n' "${RESULT_KEYS[$j]}" "${RESULT_STATUS[$j]}"; done

if [[ "$DRY_RUN" -eq 1 ]]; then
  # D-2 (live --dry-run, 2026-09-20): the old unconditional "ok all
  # selected steps VERIFIED or SKIPPED" + exit 0 was FALSE on a
  # partially-provisioned box -- ten steps read "would likely fail" yet
  # the run still reported success. Count truthfully instead: a
  # BLOCKED-BY step is EXPECTED (nothing is ever applied in --dry-run,
  # so a step downstream of one not yet run cannot preflight clean) and
  # does not fail the run; a genuine "would likely fail" does.
  V=0; S=0; M=0; B=0; F=0
  for j in "${!RESULT_STATUS[@]}"; do
    case "${RESULT_STATUS[$j]}" in
      "VERIFIED "*)   V=$((V + 1)) ;;
      "SKIPPED "*)    S=$((S + 1)) ;;
      "MANUAL "*)     M=$((M + 1)) ;;
      "BLOCKED-BY "*) B=$((B + 1)) ;;
      *)              F=$((F + 1)) ;;
    esac
  done
  info "$V VERIFIED, $S SKIPPED, $M MANUAL, $B BLOCKED-BY-earlier-step (expected on a partial box), $F would likely fail"
  if [[ $F -gt 0 ]]; then
    echo "" >&2
    echo "FAIL: $F step(s) would likely fail for a reason OTHER than an earlier step not yet being applied -- see the rc= value(s) above; investigate before a real run." >&2
    exit 3
  fi
  ok "dry-run: every step VERIFIED, SKIPPED, MANUAL, or BLOCKED-BY a step this dry run never applied (expected -- --dry-run applies nothing)"
  exit 0
fi

ok "all selected steps VERIFIED or SKIPPED"
exit 0
