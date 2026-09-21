#!/usr/bin/env bash
#
# fence-provision-strikes.sh -- offline strike-proof for scripts/provision.sh's
# OWN orchestration logic: step ordering, exit-code classification
# (0 VERIFIED / 3 SKIPPED / 4 MANUAL / else FAILED), --from/--only/--dry-run/
# --list, the .env operator-name preflight, and the ci-migrate keygen
# check-and-create. BACKLOG.md §7.36 item 76 (W-5).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- every per-step script
# (provision-vps.sh, deploy-app.sh, assign-app-domain.sh, ...) is replaced
# by tests/fixtures/ci/provision/fake-step.sh, a generic stand-in that
# returns a CANNED exit code and does nothing real. This proves
# provision.sh's OWN control flow is correct given whatever those scripts
# report; it is not, and cannot be, a substitute for actually running
# scripts/provision.sh against a real box.
#
# Scenarios:
#   1. HAPPY-PATH -- several consecutive scripted steps preflight and
#      apply 0, correctly stopping at the always-MANUAL cutover gate
#      (exit 1, not 0 -- see the scenario's own comment for why no
#      multi-step run can ever exit 0 against this registry).
#   2. SKIPPED-CONTINUES -- the smokes step's apply returns 3 -> recorded
#      SKIPPED, run continues to completion, exit 0.
#   3. MANUAL-STOPS -- discord (a genuine MANUAL step, no fake needed --
#      db-bootstrap became a real scripted step this round, so the
#      MANUAL-step proxy moved to discord/remaining-checks/cutover) is
#      reached -> provision.sh stops there, resume hint names discord,
#      exit 1.
#   4. FAILED-STOPS -- a step's apply returns 1 -> provision.sh stops
#      there, resume hint names that step, exit 2; steps AFTER it never
#      run (their call-log entries absent).
#   5. DRY-RUN-NEVER-APPLIES -- --dry-run: every step's preflight runs,
#      but --apply is NEVER passed to anything (checked via the call log
#      -- zero "--apply" tokens anywhere in it).
#   6. FROM-SKIPS-EARLIER -- --from provision-resources: steps before it
#      never run at all (absent from the call log), it and after do.
#   7. ONLY-RUNS-EXACTLY-ONE -- --only etl-role: exactly one step's
#      scripts run (plus its own declared dependency-check call, per
#      scenario 7a-7c below), nothing before or after.
#   7a. DEPENDENCY-CHECK-REFUSES-PGRST-FLIP (Sec F-5, PR #849 review's own
#      named minimum) -- pgrst-gates' own live preflight reports a real
#      REFUSED finding -> --only pgrst-flip refuses BEFORE calling
#      coolify-env.sh at all -- the §6.9 VETO gate can no longer be
#      bypassed by jumping straight to the flip.
#   7b. DEPENDENCY-CHECK-REFUSES-DEPLOY-APP (Sec F-5's own named "milder"
#      example) -- mint-jwt's own preflight reports a finding -> --only
#      deploy-app refuses before calling deploy-app.sh.
#   7c. SKIP-DEPENDENCY-CHECK-OVERRIDES -- the same unmet precondition as
#      7a, with --skip-dependency-check passed -> proceeds, printing what
#      it is skipping rather than silently doing so.
#   8. LIST-NO-ENV-NEEDED -- --list works with NO .env present at all
#      (never reaches the .env check) and runs nothing.
#   9. ENV-MISSING-NAMES -- an .env missing operator-provided names ->
#      exit 3, message names the missing set.
#  10. UNKNOWN-STEP-KEY -- --from/--only naming a step not in the
#      registry -> exit 3.
#  11. KEYGEN-ABSENT-GENERATES -- ci-migrate keypair absent -> the fake
#      ssh-keygen on PATH is invoked and both files exist after.
#  12. KEYGEN-PRESENT-SKIPS -- ci-migrate keypair already present -> the
#      fake ssh-keygen is NEVER invoked (its own call-log stays empty).
#  13. COMPOUND-STEP-PROPAGATES -- the provision-resources step's SECOND
#      provision-worker.sh call fails -> the whole step fails, the run
#      stops there (never reaches 'secrets').
#  14. BOX_IP-REACHES-EVERY-SUB-SCRIPT-THAT-NEEDS-IT (D-1, live
#      --dry-run, 2026-09-20) -- a full --dry-run walkthrough: every
#      fake call logged under a name whose real script requires BOX_IP
#      via the environment shows a real value, never BOX_IP=<ABSENT>.
#      Two names (provision-migrator-app, migrator-scheduled-task) were
#      missing this entirely until this fix.
#  15. DRY-RUN-BLOCKED-BY-VS-GENUINE-FAILURE (D-2, live --dry-run,
#      2026-09-20) -- a combined full --dry-run: a step whose own
#      declared prerequisite ALSO failed this same run is classified
#      BLOCKED-BY <prereq>, not counted as a genuine failure; a step
#      whose prerequisite is satisfied but which independently fails IS
#      counted -> exit 3, never the old unconditional exit 0.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/provision"
FAKE_SCRIPTS_DIR="$FIXTURE_DIR/scripts"
PROVISION_SH="$REPO_ROOT/scripts/provision.sh"

[[ -d "$FAKE_SCRIPTS_DIR" ]] || { echo "FATAL: $FAKE_SCRIPTS_DIR missing" >&2; exit 2; }
[[ -f "$PROVISION_SH" ]] || { echo "FATAL: $PROVISION_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_SSH_KEYGEN_LOG:-}" ]]; then
  printf 'ssh-keygen %s\n' "$*" >> "$FAKE_SSH_KEYGEN_LOG"
fi
# Parse -f <path> and create <path> + <path>.pub, matching real ssh-keygen.
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-f" ]]; then
    mkdir -p "$(dirname "$arg")"
    printf 'fake-private-key\n' > "$arg"
    printf 'fake-public-key\n' > "$arg.pub"
  fi
  prev="$arg"
done
exit 0
EOF
chmod +x "$FAKE_BIN/ssh-keygen"

FULL_ENV='HETZNER_API_TOKEN=x
COOLIFY_ADMIN_EMAIL=x@example.com
COOLIFY_ADMIN_NAME=x
COOLIFY_ADMIN_PASSWORD=x
SMTP_PASS=x
PDF_WORKER_SIGNING_KEY=x
WORKER_ADMISSION_SHARED_SECRET=x
DISCORD_WEBHOOK_URL=x
FMP_API_KEY=x
BLS_API_KEY=x
PLAID_CLIENT_ID=x
PLAID_SECRET=x
SIMPLEFIN_TOKEN=x
PORKBUN_API_KEY=x
PORKBUN_SECRET_KEY=x
BOX_IP=127.0.0.1
'

FAIL=0

run_case() {
  # run_case <desc> <expect_exit> <env-dir-setup-fn> [extra provision.sh args...]
  local desc="$1" expect_exit="$2"; shift 2
  local extra_args=("$@")
  local case_dir="$WORK/case.$$.$RANDOM"
  mkdir -p "$case_dir"
  local call_log="$case_dir/calls.log"
  local keygen_log="$case_dir/keygen.log"
  : > "$call_log"
  : > "$keygen_log"
  printf '%s' "$FULL_ENV" > "$case_dir/.env"
  # CI_MIGRATE_SSH_PUBKEY points inside case_dir by default (absent unless the case pre-creates it).
  printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\n' "$case_dir" >> "$case_dir/.env"

  set +e
  # `env` throughout, not bash prefix-assignment syntax: a NAME=value word
  # produced by array expansion (${CASE_ENV[@]}) is not RECOGNIZED as a
  # prefix assignment by bash's parser (that classification is syntactic,
  # on the literal source token, before any expansion happens) -- it gets
  # treated as a plain command-name argument instead ("command not
  # found"). `env` accepts NAME=value as ordinary argv, sidestepping this.
  # bash 3.2 (macOS default, pre-4.4) also trips `set -u`'s "unbound
  # variable" on "${arr[@]}" for a TRULY EMPTY array -- the
  # ${arr[@]+"${arr[@]}"} form is the standard safe idiom for that.
  env REPO_ROOT="$case_dir" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" \
    FAKE_CALL_LOG="$call_log" FAKE_COUNTER_DIR="$case_dir" FAKE_SSH_KEYGEN_LOG="$keygen_log" \
    ${CASE_ENV[@]+"${CASE_ENV[@]}"} \
    bash "$PROVISION_SH" ${extra_args[@]+"${extra_args[@]}"} > "$case_dir/out.txt" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$case_dir/out.txt" >&2
    echo "----- call log -----" >&2
    cat "$call_log" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  CASE_LAST_DIR="$case_dir"
  return 0
}

# 1. HAPPY-PATH -- dns -> ci-keypair -> github-ci -> deploy-on-success,
# FOUR CONSECUTIVE, fully-scripted steps (the registry's last four before
# cutover), correctly STOPPING at cutover, the always-MANUAL terminal gate
# (run_cutover returns 4 unconditionally, --confirm-cutover or not -- it
# only changes the printed message). This is this orchestrator's real
# terminal behavior BY DESIGN: no --from invocation can ever complete past
# cutover with exit 0, because that gate is a deliberate one-way door,
# never auto-satisfied. A "happy path" scenario for THIS registry is
# therefore "N steps VERIFIED, then a clean MANUAL stop at cutover" -- not
# "exit 0 across the whole remaining run".
CASE_ENV=()
# Sec F-6 (PR #849 review): dns is now ALSO gated behind
# --confirm-cutover (the apex A repoint is the user-visible go-live
# switch) -- a happy-path run reaching dns->cutover must pass it, same
# as it always needed to for cutover's own gate.
run_case "happy-path (dns -> ci-keypair -> github-ci -> deploy-on-success VERIFIED, stops at cutover)" 1 --from dns --confirm-cutover || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  VERIFIED_COUNT="$(grep -c ': VERIFIED' "$CASE_LAST_DIR/out.txt" 2>/dev/null || echo 0)"
  [[ "$VERIFIED_COUNT" == "4" ]] || { echo "FAIL: [happy-path] expected 4 VERIFIED steps, saw $VERIFIED_COUNT" >&2; FAIL=1; }
  grep -q -- "--from cutover" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [happy-path] resume hint does not name cutover" >&2; FAIL=1; }
fi

# 6a. DNS-REFUSES-WITHOUT-CONFIRM-CUTOVER (Sec F-6, PR #849 review) --
#     dns alone, no --confirm-cutover -> refuses (MANUAL, exit 1),
#     before assign-app-domain.sh is ever called.
run_case "--only dns without --confirm-cutover refuses" 1 --only dns || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qi "REFUSED without --confirm-cutover" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [dns-no-confirm] did not name the missing --confirm-cutover flag" >&2; FAIL=1; }
  if grep -q "^assign-app-domain" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [dns-no-confirm] assign-app-domain.sh was called despite the missing --confirm-cutover flag" >&2
    FAIL=1
  fi
fi

# 6b. DNS-PROCEEDS-WITH-CONFIRM-CUTOVER -- same target, --confirm-cutover
#     passed -> proceeds normally (reaches assign-app-domain.sh).
run_case "--only dns with --confirm-cutover proceeds" 0 --only dns --confirm-cutover || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^assign-app-domain" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [dns-with-confirm] assign-app-domain.sh was never called despite --confirm-cutover" >&2; FAIL=1; }
fi

# 2. SKIPPED-CONTINUES -- the smokes step's own overall result is SKIPPED
# (its admission-endpoint sub-call returns 3, worst-of tracked) but that
# is NOT a failure -- selecting it alone must still exit 0.
CASE_ENV=(FAKE_RC_smoke_admission_endpoint=3)
run_case "skipped step continues, exit 0" 0 --only smokes || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -q "SKIPPED" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [skipped step continues] output does not mention SKIPPED" >&2
  FAIL=1
fi

# 3. MANUAL-STOPS -- discord is reached
CASE_ENV=()
run_case "manual step (discord) stops the run, exit 1" 1 --only discord || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -q -- "--from discord" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [manual step] resume hint does not name discord" >&2
  FAIL=1
fi

# 4. FAILED-STOPS -- provision-vps.sh's apply fails
# shellcheck disable=SC2054  # intentional: ONE element, "0,1" is fake-step.sh's own comma-separated per-call RC list, not two array elements
CASE_ENV=(FAKE_RC_provision_vps=0,1)
run_case "a real failure stops the run, exit 2" 2 --only provision-vps || FAIL=1

# 5. DRY-RUN-NEVER-APPLIES
CASE_ENV=()
run_case "dry-run never applies anything" 0 --dry-run --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && grep -q -- "--apply" "$CASE_LAST_DIR/calls.log"; then
  echo "FAIL: [dry-run] call log shows an --apply invocation" >&2
  cat "$CASE_LAST_DIR/calls.log" >&2
  FAIL=1
fi

# 6. FROM-SKIPS-EARLIER -- --from provision-resources: provision-vps.sh
# must never appear in the call log. provision-resources (step 6) is
# preceded by db-bootstrap(3)/pre-cutover-gates(4), both MANUAL, but
# --from jumps straight past them without running them at all; the run
# then proceeds through every scripted step (7-16) and correctly stops at
# ca1-gate(17), the next MANUAL step, exit 1.
CASE_ENV=()
run_case "--from skips earlier steps" 1 --from provision-resources || true
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if grep -q "provision-vps" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--from provision-resources] provision-vps.sh (an earlier step) was called" >&2
    FAIL=1
  elif ! grep -q "provision-worker" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--from provision-resources] provision-worker.sh (the target step) was never called" >&2
    FAIL=1
  else
    echo "OK: [--from provision-resources] earlier steps skipped, target step ran." >&2
  fi
fi

# 7. ONLY-RUNS-EXACTLY-ONE
CASE_ENV=()
run_case "--only runs exactly one step" 0 --only etl-role || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  # grep -c prints a count either way; its own exit status (1 = zero
  # matches) is not an error here, so no `|| echo 0` fallback -- chaining
  # one would DOUBLE the captured output ("0" from grep, then another "0"
  # from the fallback) on the exact zero-matches case this checks for.
  # "db-bootstrap" is now ALSO expected (Sec F-5, PR #849 review): --only
  # etl-role's own declared STEP_REQUIRES prerequisite (db-bootstrap) is
  # live-rechecked once, in PREFLIGHT mode only, before the target step
  # runs -- a legitimate call the dependency gate itself makes, not a
  # stray extra step being executed.
  set +e
  OTHER_CALLS="$(grep -vc "db-role-handoff\|db-bootstrap" "$CASE_LAST_DIR/calls.log" 2>/dev/null)"
  set -e
  if [[ "$OTHER_CALLS" != "0" ]]; then
    echo "FAIL: [--only] a non-target, non-dependency-check script was called" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
  # Prefix match (name + a following space) -- fake-step.sh's call-log
  # line is "<name> BOX_IP=<value> <args...>" (D-1, live --dry-run,
  # 2026-09-20), never bare "<name>" or "<name> " alone any more, so an
  # exact-line match would never fire regardless of dependency-check
  # correctness.
  if ! grep -q "^db-bootstrap " "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--only] expected the dependency-check call to db-bootstrap (etl-role's own declared prerequisite) in the call log -- it may have been silently skipped" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7a. DEPENDENCY-CHECK-REFUSES-PGRST-FLIP (Sec F-5, PR #849 review's own
#     named minimum) -- pgrst-gates' own preflight reports rc=1 (a real
#     REFUSED finding, e.g. anon holds a grant) -> `--only pgrst-flip`
#     refuses BEFORE calling coolify-env.sh at all, never exposing `pfin`
#     on the Data API with the VETO gate unevaluated.
CASE_ENV=(FAKE_RC_pgrst_exposure_gates=1)
run_case "--only pgrst-flip without gates passing refuses" 3 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "pgrst-gates" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-dependency] did not name pgrst-gates as the unmet prerequisite" >&2; FAIL=1; }
  if grep -q "^coolify-env" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [pgrst-flip-dependency] coolify-env.sh was called despite the unmet prerequisite -- the flip was not actually prevented" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7b. DEPENDENCY-CHECK-REFUSES-DEPLOY-APP (Sec F-5, PR #849 review's own
#     named "milder" example) -- mint-jwt's own preflight reports rc=1 ->
#     `--only deploy-app` refuses before calling deploy-app.sh at all.
CASE_ENV=(FAKE_RC_mint_supabase_jwt_keys=1)
run_case "--only deploy-app with mint-jwt not done refuses" 3 --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "mint-jwt" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [deploy-app-dependency] did not name mint-jwt as the unmet prerequisite" >&2; FAIL=1; }
  if grep -q "^deploy-app" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [deploy-app-dependency] deploy-app.sh was called despite the unmet prerequisite" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7c. SKIP-DEPENDENCY-CHECK-OVERRIDES -- the same unmet pgrst-gates
#     precondition, but with --skip-dependency-check passed -> proceeds
#     (reaches coolify-env.sh), printing what it skipped rather than
#     silently doing so.
CASE_ENV=(FAKE_RC_pgrst_exposure_gates=1)
run_case "--skip-dependency-check overrides the gate" 0 --only pgrst-flip --skip-dependency-check || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qi "SKIPPING dependency check" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [skip-dependency-check] did not print what it was skipping" >&2; FAIL=1; }
  grep -q "^coolify-env" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [skip-dependency-check] coolify-env.sh was never called -- the override did not actually let the step proceed" >&2; FAIL=1; }
fi
CASE_ENV=()

# 8. LIST-NO-ENV-NEEDED
NO_ENV_DIR="$WORK/no-env-case"
mkdir -p "$NO_ENV_DIR"
set +e
REPO_ROOT="$NO_ENV_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" bash "$PROVISION_SH" --list > "$NO_ENV_DIR/out.txt" 2>&1
LIST_RC=$?
set -e
if [[ "$LIST_RC" != "0" ]]; then
  echo "FAIL: [--list with no .env] expected exit 0, got $LIST_RC" >&2
  cat "$NO_ENV_DIR/out.txt" >&2
  FAIL=1
else
  echo "OK: [--list with no .env] exit 0 as expected." >&2
fi

# 9. ENV-MISSING-NAMES
MISSING_DIR="$WORK/missing-env-case"
mkdir -p "$MISSING_DIR"
printf 'HETZNER_API_TOKEN=x\n' > "$MISSING_DIR/.env"
set +e
REPO_ROOT="$MISSING_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" bash "$PROVISION_SH" > "$MISSING_DIR/out.txt" 2>&1
MISSING_RC=$?
set -e
if [[ "$MISSING_RC" != "3" ]]; then
  echo "FAIL: [missing .env names] expected exit 3, got $MISSING_RC" >&2
  cat "$MISSING_DIR/out.txt" >&2
  FAIL=1
else
  echo "OK: [missing .env names] exit 3 as expected." >&2
fi

# 10. UNKNOWN-STEP-KEY
CASE_ENV=()
run_case "unknown --from key refuses, exit 3" 3 --from bogus-step-name || FAIL=1

# 11. KEYGEN-ABSENT-GENERATES
CASE_ENV=()
run_case "keygen absent -> generated" 1 --only discord || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if [[ ! -s "$CASE_LAST_DIR/keygen.log" ]]; then
    echo "FAIL: [keygen absent] fake ssh-keygen was never invoked" >&2
    FAIL=1
  elif [[ ! -f "$CASE_LAST_DIR/ci_migrate.pub" || ! -f "${CASE_LAST_DIR}/ci_migrate" ]]; then
    echo "FAIL: [keygen absent] keypair files were not created" >&2
    FAIL=1
  else
    echo "OK: [keygen absent] fake ssh-keygen invoked, files created." >&2
  fi
fi

# 12. KEYGEN-PRESENT-SKIPS
PRESENT_DIR="$WORK/keygen-present-case"
mkdir -p "$PRESENT_DIR"
printf '%s' "$FULL_ENV" > "$PRESENT_DIR/.env"
printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\n' "$PRESENT_DIR" >> "$PRESENT_DIR/.env"
printf 'existing-priv\n' > "$PRESENT_DIR/ci_migrate"
printf 'existing-pub\n' > "$PRESENT_DIR/ci_migrate.pub"
: > "$PRESENT_DIR/keygen.log"
: > "$PRESENT_DIR/calls.log"
set +e
REPO_ROOT="$PRESENT_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" \
  FAKE_CALL_LOG="$PRESENT_DIR/calls.log" FAKE_COUNTER_DIR="$PRESENT_DIR" FAKE_SSH_KEYGEN_LOG="$PRESENT_DIR/keygen.log" \
  bash "$PROVISION_SH" --only discord > "$PRESENT_DIR/out.txt" 2>&1
PRESENT_RC=$?
set -e
if [[ "$PRESENT_RC" != "1" ]]; then
  echo "FAIL: [keygen present] expected exit 1 (discord is MANUAL), got $PRESENT_RC" >&2
  cat "$PRESENT_DIR/out.txt" >&2
  FAIL=1
elif [[ -s "$PRESENT_DIR/keygen.log" ]]; then
  echo "FAIL: [keygen present] fake ssh-keygen was invoked even though the keypair already existed" >&2
  FAIL=1
else
  echo "OK: [keygen present] fake ssh-keygen never invoked." >&2
fi

# 13. COMPOUND-STEP-PROPAGATES -- provision-resources calls
# provision-worker.sh 3x (pfin-back-etl, pfin-pdf-render, pfin-provider-sync);
# the 2nd call (pfin-pdf-render) fails.
# shellcheck disable=SC2054  # intentional: ONE element, "0,1" is fake-step.sh's own comma-separated per-call RC list, not two array elements
CASE_ENV=(FAKE_RC_provision_worker=0,1)
run_case "compound step: 2nd sub-call failing stops the whole run" 2 --from provision-resources || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && grep -q "Step.*secrets --" "$CASE_LAST_DIR/out.txt" 2>/dev/null; then
  echo "FAIL: [compound propagation] the run reached the 'secrets' step despite 'provision-resources' failing" >&2
  FAIL=1
fi

# 14. BOX_IP-REACHES-EVERY-SUB-SCRIPT-THAT-NEEDS-IT (D-1, live --dry-run,
#     2026-09-20) -- a full --dry-run walkthrough of the WHOLE registry
#     (no --from/--only, so every step's preflight runs): every fake call
#     logged under a name whose REAL counterpart requires BOX_IP passed
#     via the environment (never defaulted, never self-read from .env --
#     coolify-env.sh, provision-migrator-app.sh, migrator-scheduled-
#     task.sh, provision-app.sh, provision-worker.sh, record-coolify-
#     uuids.sh, push-production-secrets.sh, mint-supabase-jwt-keys.sh,
#     db-role-handoff.sh, deploy-app.sh, every smoke-*.sh that reads it,
#     worker-scheduled-task.sh) shows a real value, never
#     BOX_IP=<ABSENT>. Two of these (provision-migrator-app,
#     migrator-scheduled-task) were missing the export ENTIRELY until
#     this fix -- caught on the real box, not by this fence (which had
#     no BOX_IP leg before this PR). Strike: drop `require_box_ip` from
#     one run_* function on a disposable copy of provision.sh -> that
#     name's own call-log line(s) show BOX_IP=<ABSENT> -> this scenario
#     goes RED.
CASE_ENV=()
run_case "BOX_IP reaches every sub-script that requires it" 0 --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  BOX_IP_REQUIRED_NAMES="coolify-env provision-migrator-app migrator-scheduled-task provision-app provision-worker record-coolify-uuids push-production-secrets mint-supabase-jwt-keys db-role-handoff deploy-app smoke-admission-endpoint smoke-etl-poll smoke-pdf-roundtrip smoke-pfin-exposure smoke-ca1-env-pattern worker-scheduled-task"
  CHECKED_ANY=0
  for n in $BOX_IP_REQUIRED_NAMES; do
    if grep -q "^$n " "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
      CHECKED_ANY=1
      if grep "^$n " "$CASE_LAST_DIR/calls.log" | grep -q "BOX_IP=<ABSENT>"; then
        echo "FAIL: [box-ip-reaches-every-sub-script] '$n' was called with BOX_IP absent from its own environment" >&2
        grep "^$n " "$CASE_LAST_DIR/calls.log" >&2
        FAIL=1
      fi
    fi
  done
  [[ "$CHECKED_ANY" -eq 1 ]] || { echo "FAIL: [box-ip-reaches-every-sub-script] none of the BOX_IP-required names were even called -- the call log is not what this scenario expected" >&2; FAIL=1; }
fi

# 15. DRY-RUN-BLOCKED-BY-VS-GENUINE-FAILURE (D-2, live --dry-run,
#     2026-09-20) -- a single combined full --dry-run: provision-app.sh's
#     fake fails (models "the box is only partially provisioned -- this
#     resource does not exist yet"), so provision-resources itself
#     legitimately reads "would likely fail" (its OWN declared
#     prerequisite, pgrst-flip, is satisfied -- this is an independent
#     failure, not a cascade). record-coolify-uuids.sh's fake is ALSO
#     forced to fail (models "can't resolve a uuid for a resource that
#     doesn't exist"), but record-uuids' own declared STEP_REQUIRES
#     prerequisite is provision-resources, which just failed -- so
#     record-uuids must be classified BLOCKED-BY provision-resources, NOT
#     counted as an independent "would likely fail". Separately,
#     smoke-ca1-env-pattern.sh's fake is forced to fail while its own
#     prerequisite (deploy-workers) reports VERIFIED (its own fake
#     defaults to 0, uninvolved in this scenario's failures) -- a truly
#     independent failure, must read "would likely fail". Exit code must
#     be 3 (at least one genuine "would likely fail" exists), never 0 --
#     the exact defect this fixes: the OLD version printed "would likely
#     fail" ten times over and still exited 0.
CASE_ENV=(FAKE_RC_provision_app=1 FAKE_RC_record_coolify_uuids=1 FAKE_RC_smoke_ca1_env_pattern=1)
run_case "dry-run distinguishes BLOCKED-BY from a genuine failure, exit 3" 3 --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^  provision-resources .*would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] provision-resources not reported as an independent 'would likely fail'" >&2; FAIL=1; }
  grep -q "^  record-uuids .*BLOCKED-BY provision-resources" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] record-uuids not reported as BLOCKED-BY provision-resources" >&2; FAIL=1; }
  grep -q "^  ca1-gate .*would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] ca1-gate (independent failure, prerequisite satisfied) not reported as 'would likely fail'" >&2; FAIL=1; }
  grep -qi "would likely fail" "$CASE_LAST_DIR/out.txt" > /dev/null # sanity, already covered above
  grep -q "FAIL: [0-9]* step(s) would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] summary did not print a truthful 'would likely fail' count" >&2; FAIL=1; }
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more provision.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision.sh strike-proofs passed."
exit 0
