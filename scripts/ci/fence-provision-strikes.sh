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
#   3. MANUAL-STOPS -- db-bootstrap (a genuine MANUAL step, no fake
#      needed) is reached -> provision.sh stops there, resume hint names
#      db-bootstrap, exit 1.
#   4. FAILED-STOPS -- a step's apply returns 1 -> provision.sh stops
#      there, resume hint names that step, exit 2; steps AFTER it never
#      run (their call-log entries absent).
#   5. DRY-RUN-NEVER-APPLIES -- --dry-run: every step's preflight runs,
#      but --apply is NEVER passed to anything (checked via the call log
#      -- zero "--apply" tokens anywhere in it).
#   6. FROM-SKIPS-EARLIER -- --from provision-resources: steps before it
#      never run at all (absent from the call log), it and after do.
#   7. ONLY-RUNS-EXACTLY-ONE -- --only etl-role: exactly one step's
#      scripts run, nothing before or after.
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

# 1. HAPPY-PATH -- dns(20) -> ci-keypair(21) -> github-ci(22), three
# CONSECUTIVE, fully-scripted steps, correctly STOPPING at cutover(23),
# the always-MANUAL terminal gate (run_cutover returns 4 unconditionally,
# --confirm-cutover or not -- it only changes the printed message). This
# is this orchestrator's real terminal behavior BY DESIGN: no --from
# invocation can ever complete past cutover with exit 0, because that gate
# is a deliberate one-way door, never auto-satisfied. A "happy path"
# scenario for THIS registry is therefore "N steps VERIFIED, then a clean
# MANUAL stop at cutover" -- not "exit 0 across the whole remaining run".
CASE_ENV=()
run_case "happy-path (dns -> ci-keypair -> github-ci VERIFIED, stops at cutover)" 1 --from dns || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  VERIFIED_COUNT="$(grep -c ': VERIFIED' "$CASE_LAST_DIR/out.txt" 2>/dev/null || echo 0)"
  [[ "$VERIFIED_COUNT" == "3" ]] || { echo "FAIL: [happy-path] expected 3 VERIFIED steps, saw $VERIFIED_COUNT" >&2; FAIL=1; }
  grep -q -- "--from cutover" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [happy-path] resume hint does not name cutover" >&2; FAIL=1; }
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

# 3. MANUAL-STOPS -- db-bootstrap is reached (no --from/--only needed, it's step 3)
CASE_ENV=()
run_case "manual step (db-bootstrap) stops the run, exit 1" 1 --only db-bootstrap || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -q -- "--from db-bootstrap" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [manual step] resume hint does not name db-bootstrap" >&2
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
  set +e
  OTHER_CALLS="$(grep -vc "db-role-handoff" "$CASE_LAST_DIR/calls.log" 2>/dev/null)"
  set -e
  if [[ "$OTHER_CALLS" != "0" ]]; then
    echo "FAIL: [--only] a non-target script was called" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

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
run_case "keygen absent -> generated" 1 --only db-bootstrap || FAIL=1
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
  bash "$PROVISION_SH" --only db-bootstrap > "$PRESENT_DIR/out.txt" 2>&1
PRESENT_RC=$?
set -e
if [[ "$PRESENT_RC" != "1" ]]; then
  echo "FAIL: [keygen present] expected exit 1 (db-bootstrap is MANUAL), got $PRESENT_RC" >&2
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

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more provision.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision.sh strike-proofs passed."
exit 0
