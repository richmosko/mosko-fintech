#!/usr/bin/env bash
#
# provision.sh -- the single entry point for the V1 greenfield production
# stand-up. BACKLOG.md §7.36 item 76 (W-5). DevOps-owned. Runs the 16
# ordered steps of docs/deployment-runbook.md Part 3 (as reconciled with
# BACKLOG.md §7.36 item 68's own worker-deploy sequence, PR #848) as ONE
# call instead of an operator running each script by hand in order.
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
# individual script's own header already states for itself).
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
#      from --from) reported VERIFIED or SKIPPED.
#   1  a step reported MANUAL and this run stopped there (an unavoidable
#      by-hand moment, not a script defect).
#   2  a step reported a real failure (REFUSED/FAILED) and this run
#      stopped there.
#   3  a precondition this script could not even attempt under (missing
#      operator-provided .env names, unknown --from/--only step key).
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --from) shift; FROM_STEP="${1:-}" ;;
    --only) shift; ONLY_STEP="${1:-}" ;;
    --list) LIST_ONLY=1 ;;
    --confirm-cutover) CONFIRM_CUTOVER=1 ;;
    *) echo "unknown flag: $1" >&2; echo "usage: $0 [--dry-run] [--from <step>] [--only <step>] [--list] [--confirm-cutover]" >&2; exit 3 ;;
  esac
  shift || true
done

# --- Ordered step registry (bash 3.2: parallel arrays, no assoc arrays) -
# Matches docs/deployment-runbook.md Part 3's 23 rows exactly, one
# provision.sh step per table row (re-read live from `main` at 6e17ad92,
# after PR #847 merged and re-sequenced this table -- team-lead's grading
# pass moved db-role-handoff to AFTER resource creation and moved the
# §6.9 PGRST-exposure flip EARLIER, among other changes; do not build this
# registry from memory of an earlier draft of that table). The unnumbered
# "GitHub Environment reviewer approval" row is deliberately NOT a step
# here -- it recurs on every migrator trigger fire, not once at stand-up.
STEP_KEYS=(
  provision-vps
  standup
  db-bootstrap
  pre-cutover-gates
  pgrst-flip
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
  cutover
)
STEP_LABELS=(
  "Provision + harden the box, install Coolify, bootstrap the admin account (§1+§3)"
  "Stand up the Supabase stack; mint real JWT keys (§4)"
  "Database bootstrap: pfin_owner/migrator, migrations, vault decrypt view (§6.3)"
  "Pre-flip gates: VETO trigger, migration count, 025 presence (§6.9 steps 1-3)"
  "Flip the pfin Data-API exposure (§6.9 steps 4-6)"
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
  "Smoke: admission endpoint (CA-2), ETL poll, PDF round-trip"
  "CA-1 deploy-gate: provider-sync's injected env names vs PUBLIC_ROUTE_ENV_MATCHERS"
  "Remaining §10 checks: CA-7 reachability, TZ-1 pin, RLS isolation, auth login"
  "Re-establish Coolify -> Discord notifications (§8)"
  "DNS + Coolify domain assignment + LE cert (§2)"
  "CI-trigger keypair + box-side wiring (§6.4)"
  "GitHub-side CI setup: Actions secret/variable, production-migrator Environment (§6.4)"
  "Cutover: tear down the incumbent pfindash.com stack (§9)"
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

resume_hint() {
  printf '\nresume: scripts/provision.sh --from %s\n' "$1" >&2
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

run_db_bootstrap() {
  step "db-bootstrap: NOT YET SCRIPTED (BACKLOG §7.36 item 75)"
  info "By hand, in order (full command text: docs/archive/deployment-runbook-rationale-2026-09-20.md §6.3):"
  info "  1. psql -U supabase_admin -f supabase/roles.sql"
  info "  2. psql -U supabase_admin -f supabase/auth-grants.sql"
  info "  3. the engine-backstop REVOKEs (same file)"
  info "  4. \\password migrator  (interactive, piped stdin -- never a -c literal)"
  info "  5. ALTER ROLE migrator LOGIN;"
  info "  6. the role-comment files"
  info "  7. docker compose exec migrator supabase db push --yes --db-url \"\$PROD_DB_URL\""
  info "  8. psql -U supabase_admin -f supabase/post-step-vault-view.sql"
  info "Verify: every pfin object owned by pfin_owner; bootstrap_complete = t; exactly one decrypt view."
  return 4
}

run_pre_cutover_gates() {
  step "pre-cutover-gates: BY-HAND (one-time measurement, BACKLOG §7.36 item 66 books scripting this)"
  info "Run against the production DB as an appropriately-privileged role:"
  info "  1. select has_schema_privilege('anon','pfin','USAGE');  -- expect f"
  info "  2. enumerate every pfin relation anon holds any grant on -- expect zero rows"
  info "  3. select count(*) from supabase_migrations.schema_migrations;  -- expect the migration-file count (ls supabase/migrations/*.sql | wc -l) at the deployed sha -- re-count, do not assume"
  info "  4. select version from supabase_migrations.schema_migrations where version like '025%';  -- expect exactly one row"
  info "STOP on any violation -- do not proceed to the pgrst-flip step."
  return 4
}

run_pgrst_flip() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  BOX_IP="$box_ip" bash "$SCRIPTS/coolify-env.sh" set pfin-supabase-stack PGRST_DB_SCHEMAS=public,graphql_public,pfin ${1:+--apply --deploy}
}

run_provision_resources() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  BOX_IP="$box_ip" bash "$SCRIPTS/provision-app.sh" ${1:+--apply} || return $?
  local rc
  for name in pfin-back-etl pfin-pdf-render pfin-provider-sync; do
    BOX_IP="$box_ip" bash "$SCRIPTS/provision-worker.sh" "$name" ${1:+--apply}; rc=$?
    [[ $rc -eq 0 ]] || return $rc
  done
  return 0
}

run_record_uuids() { local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2; BOX_IP="$box_ip" bash "$SCRIPTS/record-coolify-uuids.sh" ${1:+--apply}; }

run_nonsecret_env() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  BOX_IP="$box_ip" bash "$SCRIPTS/coolify-env.sh" set pfin-app PUBLIC_SUPABASE_URL=http://api-gw:8000 ${1:+--apply} || return $?
  BOX_IP="$box_ip" bash "$SCRIPTS/coolify-env.sh" set pfin-back-etl \
    PFIN_DB_HOST=db PFIN_DB_PORT=5432 PFIN_DB_NAME=postgres PFIN_DB_USER=pfin_etl PFIN_DB_SSLMODE=disable ${1:+--apply} || return $?
  BOX_IP="$box_ip" bash "$SCRIPTS/coolify-env.sh" set pfin-provider-sync \
    PFIN_DB_HOST=db PFIN_DB_PORT=5432 PFIN_DB_NAME=postgres PFIN_DB_USER=pfin_provider_sync PFIN_DB_SSLMODE=disable PLAID_ENV=production ${1:+--apply}
}

run_secrets() { local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2; BOX_IP="$box_ip" bash "$SCRIPTS/push-production-secrets.sh" ${1:+--apply --skip-missing-resource}; }

run_mint_jwt() { bash "$SCRIPTS/mint-supabase-jwt-keys.sh" ${1:+--apply --app-name pfin-app --verify-live}; }

run_etl_role()             { local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2; BOX_IP="$box_ip" bash "$SCRIPTS/db-role-handoff.sh" pfin_etl ${1:+--apply}; }
run_provider_sync_role()   { local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2; BOX_IP="$box_ip" bash "$SCRIPTS/db-role-handoff.sh" pfin_provider_sync ${1:+--apply}; }

run_deploy_app() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  BOX_IP="$box_ip" bash "$SCRIPTS/deploy-app.sh" pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app \
    --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY \
    --require-network APP_STACK_NETWORK_NAME --resolve-host api-gw ${1:+--apply} || return $?
  [[ -n "${1:-}" ]] || return 0
  BOX_IP="$box_ip" bash "$SCRIPTS/smoke-pfin-exposure.sh" pfin-app --compose-service app
}

run_deploy_workers() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  for name in pfin-back-etl pfin-provider-sync pfin-pdf-render; do
    case "$name" in
      pfin-back-etl)      BOX_IP="$box_ip" bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/etl --expect-build-pack dockercompose --compose-service pfin-back-etl-monthly-report --require-network ETL_STACK_NETWORK_NAME --resolve-host db ${1:+--apply} || return $? ;;
      pfin-provider-sync) BOX_IP="$box_ip" bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/provider-sync --expect-build-pack dockercompose --compose-service provider-sync --require-network PROVIDER_SYNC_STACK_NETWORK_NAME --resolve-host db ${1:+--apply} || return $? ;;
      pfin-pdf-render)    BOX_IP="$box_ip" bash "$SCRIPTS/deploy-app.sh" "$name" --expect-base-directory /workers/pdf-render --expect-build-pack dockercompose --compose-service pdf-render --require-network PDF_RENDER_STACK_NETWORK_NAME ${1:+--apply} || return $? ;;
    esac
  done
}

run_scheduled_tasks() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  BOX_IP="$box_ip" bash "$SCRIPTS/worker-scheduled-task.sh" pfin-back-etl-monthly-report ${1:+--apply} || return $?
  BOX_IP="$box_ip" bash "$SCRIPTS/worker-scheduled-task.sh" pfin-provider-sync-daily-poll ${1:+--apply}
}

run_smokes() {
  local box_ip; box_ip="$(load_box_ip)"; [[ -n "$box_ip" ]] || return 2
  local rc
  BOX_IP="$box_ip" bash "$SCRIPTS/smoke-admission-endpoint.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  local worst=$rc
  BOX_IP="$box_ip" bash "$SCRIPTS/smoke-etl-poll.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  [[ $rc -eq 3 ]] && worst=3
  BOX_IP="$box_ip" bash "$SCRIPTS/smoke-pdf-roundtrip.sh"; rc=$?
  [[ $rc -eq 0 || $rc -eq 3 ]] || return $rc
  [[ $rc -eq 3 ]] && worst=3
  return "$worst"
}

run_ca1_gate() {
  step "ca1-gate: BY-HAND (BACKLOG §7.36 item 79 books smoke-ca1-env-pattern.sh)"
  info "docker exec into provider-sync, 'env | cut -d= -f1' (names only, never values)."
  info "(A) For each injected name, judge whether it is a public-route/FQDN/URL signal on the LIVE Coolify version (docker exec coolify ... --version); confirm PUBLIC_ROUTE_ENV_MATCHERS covers every one that is."
  info "(B) Confirm zero injected names match any matcher today -- a match means the container should already be refusing to boot."
  return 4
}

run_remaining_checks() {
  step "remaining-checks: BY-HAND (CA-7 reachability, TZ-1 pin, RLS isolation, auth login -- see archive §10)"
  info "One-time measurement (CA-7/TZ-1); RLS/auth rows stay QA-owned. Ship-block gate on the cutover step."
  return 4
}

run_discord() {
  step "discord: BY-HAND (BACKLOG §7.36 item 74 books measuring whether Coolify's API exposes this)"
  info "Coolify dashboard -> Notifications -> add/confirm the Discord webhook. Verify: a test event is received."
  return 4
}

run_dns() { bash "$SCRIPTS/assign-app-domain.sh" ${1:+--apply}; }

run_ci_keypair() { run_provision_vps "$1"; }

run_github_ci() { bash "$SCRIPTS/github-ci-setup.sh" ${1:+--apply}; }

run_cutover() {
  if [[ "$CONFIRM_CUTOVER" -ne 1 ]]; then
    step "cutover: REFUSED without --confirm-cutover"
    info "This is a one-way F/CTO decision, not a probe -- deliberately never bundled into a bare --apply."
    info "Re-run: scripts/provision.sh --from cutover --confirm-cutover  once every prior step is genuinely green."
    return 4
  fi
  step "cutover: BY-HAND even with --confirm-cutover (Part 3 row 23 -- no script exists; this flag only lets provision.sh proceed PAST its own gate)"
  info "Confirm the smokes and remaining-checks steps are both fully green, then tear down the incumbent pfindash.com stack by hand."
  return 4
}

run_step() {
  local key="$1" mode="$2"
  case "$key" in
    provision-vps)         run_provision_vps "$mode" ;;
    standup)                run_standup "$mode" ;;
    db-bootstrap)            run_db_bootstrap "$mode" ;;
    pre-cutover-gates)       run_pre_cutover_gates "$mode" ;;
    pgrst-flip)              run_pgrst_flip "$mode" ;;
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
if [[ -n "$ONLY_STEP" ]]; then
  IDX="$(step_index "$ONLY_STEP")" || { echo "FAIL: unknown step '$ONLY_STEP' -- see --list" >&2; exit 3; }
  START_IDX="$IDX"; END_IDX="$IDX"
elif [[ -n "$FROM_STEP" ]]; then
  IDX="$(step_index "$FROM_STEP")" || { echo "FAIL: unknown step '$FROM_STEP' -- see --list" >&2; exit 3; }
  START_IDX="$IDX"
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
      RESULT_STATUS+=("would likely fail (dry-run, rc=$PREFLIGHT_RC)")
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
ok "all selected steps VERIFIED or SKIPPED"
exit 0
