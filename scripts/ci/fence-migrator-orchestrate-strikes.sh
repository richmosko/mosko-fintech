#!/usr/bin/env bash
#
# fence-migrator-orchestrate-strikes.sh -- offline strike-proofs for
# BACKLOG.md §7.36 item 59 (ADR-072 Amendment 6 consequence (i)): the
# deploy-then-execute section scripts/migrator-orchestrate.sh's own header
# comment describes, inserted after the pre-fire task-command integrity
# check and before the execution-binding snapshot.
#
# Runs the REAL scripts/migrator-orchestrate.sh (never a copy, never a
# rewritten path) against a PATH-shadowed fake `curl`
# (tests/fixtures/ci/migrator-orchestrate/fake-curl) and a no-op fake
# `sleep` -- migrator-orchestrate.sh is never modified to know either
# exists. `sleep` is shadowed ONLY so the poll-timeout scenario's 180
# iterations (DEPLOY_POLL_MAX_ATTEMPTS * DEPLOY_POLL_INTERVAL_S = 15
# simulated minutes) complete in real seconds -- the loop still runs the
# SAME NUMBER of iterations and the SAME comparison logic; only the wait
# between them is removed.
#
# ⚠ REQUIRES REAL ROOT PATHS, REQUIRES SUDO, LINUX ONLY -- deliberately,
# not a shortcoming to fix later. migrator-orchestrate.sh's own CONFIG
# section states why its three absolute paths (/etc/pfin/migrator-
# trigger.conf, /etc/pfin/migrator-coolify-token.env, and
# /run/lock/pfin/pfin-migrator-orchestrate.lock, C2/C5) are HARD-CODED
# literals, never environment-overridable: C2 exists to stop a caller
# steering this script via anything it controls, and an env-var escape
# hatch for "which config file to trust" is exactly that class of hole
# one layer over. This fence therefore does NOT ask the script to accept
# fixture paths -- it materializes the fixture AT the script's real,
# hard-coded paths, using passwordless sudo (present on GitHub-hosted
# ubuntu-latest runners for the default user), inside this job's own
# throwaway VM. It cannot be run un-audited against a real production box
# (there is no production box inside a GitHub Actions runner), and it is
# NOT runnable on a developer's own machine without sudo and a Linux
# /run -- CI (security-scan.yml, ubuntu-latest) is the only place this is
# expected to execute; a bash -n syntax check is the extent of what a
# non-Linux/non-root dev machine can verify locally.
#
# Eight scenarios (BACKLOG.md §7.36 item 59's four new legs, the three
# added on Sec's PR #831 joint review, plus the happy path proving a
# clean hand-off into the pre-existing execute leg):
#   name-mismatch   -- exit 16, the application at MIGRATOR_SERVICE_UUID
#                      is named something other than MIGRATOR_APP_NAME.
#   base-dir-mismatch -- exit 16, the application's `base_directory` is
#                      not `/infra/supabase/migrator` even though its
#                      name matches (Sec's defence-in-depth ask, PR #831).
#   deploy-failed   -- generic exit 1 (fail()), same convention this
#                      script already uses for the Scheduled Task's own
#                      `failed` status -- the migrator deploy reaches a
#                      terminal 'failed' state.
#   deploy-timeout  -- generic exit 1 (fail()), same convention as the
#                      Scheduled Task's own poll-timeout branch -- the
#                      migrator deploy never reaches a terminal state.
#   deploy-cancelled -- generic exit 1 (fail()) -- the migrator deploy
#                      reaches a terminal 'cancelled-by-user', distinct
#                      from 'failed' and must not be misdiagnosed as a
#                      timeout (Sec, PR #831 joint review).
#   commit-mismatch -- exit 18, the deploy FINISHES but its own `commit`
#                      field never equals $MIGRATOR_EXPECT_SHA.
#   happy           -- exit 0, proceeding all the way through the
#                      pre-existing execute leg (DEPLOY_ON_SUCCESS
#                      suppressed).
#   happy-deploy-on-success -- exit 0, same as happy but with the fixture
#                      conf's DEPLOY_ON_SUCCESS flipped to 1, exercising
#                      the GET -> POST fix on the app-deploy-on-success
#                      call (Sec, PR #831 joint review: otherwise
#                      unexercised by any offline leg until the runbook's
#                      own flag flip).
#
# Each scenario is also INVERSION-tested at the harness level implicitly:
# every non-happy scenario is asserted to STOP before the tagged-line
# "outcome verified" log line ever appears, proving the new section
# actually gates rather than merely logging a warning and continuing.
#
# Exit 0 only if all eight scenarios behave exactly as specified. Any
# other outcome (wrong exit code, wrong/missing message text, or the fake
# Coolify API token leaking into a logged curl argv) fails closed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/migrator-orchestrate"
ORCHESTRATE_SH="$REPO_ROOT/scripts/migrator-orchestrate.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$ORCHESTRATE_SH" ]] || { echo "FATAL: $ORCHESTRATE_SH not found" >&2; exit 2; }

CONF_FILE="/etc/pfin/migrator-trigger.conf"
TOKEN_FILE="/etc/pfin/migrator-coolify-token.env"
LOCK_DIR="/run/lock/pfin"
LOCK_FILE="$LOCK_DIR/pfin-migrator-orchestrate.lock"

# ⚠⚠ SEC MERGE CONDITION (F1, PR #831 joint review) — THIS FENCE SUDO-WRITES
# AND THEN EXIT-TRAP-DELETES THE REAL PRODUCTION PATHS. Run anywhere but a
# throwaway CI VM, it destroys the box's real trigger conf and Coolify
# token file. `command -v sudo` alone (this file's previous only gate) is
# not a host check -- a developer's own machine can have sudo too. Two
# independent guards, both fail closed, in the order Sec required:
[[ "${GITHUB_ACTIONS:-}" == "true" ]] || { echo "FATAL: GITHUB_ACTIONS is not 'true' -- this fence sudo-writes and then deletes the REAL $CONF_FILE and $TOKEN_FILE. Refusing to run anywhere but a GitHub Actions runner. See this file's own header." >&2; exit 2; }
# The host-independent, load-bearing guard: even ON a GitHub Actions
# runner, a file already present at either path means something else put
# it there (this job's own retry, a prior step, a misconfigured runner
# image) -- and this fence's EXIT trap unconditionally deletes both paths.
# Refuse rather than adopt-and-later-destroy a file this fence did not
# create itself.
if [[ -e "$CONF_FILE" || -e "$TOKEN_FILE" ]]; then
  echo "FATAL: $CONF_FILE or $TOKEN_FILE already exists -- refusing to overwrite it or clean it up later. This fence only ever touches a path it created itself in THIS run." >&2
  exit 2
fi
command -v sudo >/dev/null 2>&1 || { echo "FATAL: sudo not available -- this fence only runs where migrator-orchestrate.sh's real hard-coded paths (/etc/pfin, /run/lock/pfin) can be materialized (GitHub Actions ubuntu-latest). See this file's own header." >&2; exit 2; }

FAKE_TOKEN="fake-migrator-orchestrate-token-$(date +%s)-do-not-leak"
SVC_UUID="aaaaaaaaaaaaaaaaaaaaaaaa"
TASK_UUID="bbbbbbbbbbbbbbbbbbbbbbbb"
APP_UUID_FIXTURE="cccccccccccccccccccccccc"
EXPECT_SHA="111111111111111111111111111111111111aaaa"

WORK="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK"
  sudo rm -f "$CONF_FILE" "$TOKEN_FILE" "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# Materialize the fixture at the script's REAL, hard-coded paths -- see
# header comment for why this fence does not ask the script to accept an
# override instead. `sudo install` sets ownership/mode in one step so no
# window exists where the file is world-writable.
sudo mkdir -p /etc/pfin "$LOCK_DIR"
sudo bash -c "cat > '$CONF_FILE'" <<CONF
MIGRATOR_SERVICE_UUID=$SVC_UUID
MIGRATOR_TASK_UUID=$TASK_UUID
APP_UUID=$APP_UUID_FIXTURE
DEPLOY_ON_SUCCESS=0
MIGRATOR_TASK_COMMAND=sh /workspace/pfin-task.sh
MIGRATOR_APP_NAME=pfin-migrator-test
CONF
sudo bash -c "cat > '$TOKEN_FILE'" <<TOKEN
COOLIFY_API_TOKEN=$FAKE_TOKEN
TOKEN
sudo chown "$(id -u)":"$(id -g)" "$CONF_FILE" "$TOKEN_FILE"
sudo chmod 0640 "$CONF_FILE" "$TOKEN_FILE"
# The lock DIRECTORY must be writable by the invoking (unprivileged) user
# so `exec 200>"$LOCK_FILE"` (run as that user, matching how ci-migrate
# runs it for real) can create the lock file under it -- production
# provisions this via a systemd-tmpfiles drop-in (provision-vps.sh's own
# comment); this fence reproduces the STATE that drop-in produces, not
# the mechanism that produces it.
sudo chown "$(id -u)":"$(id -g)" "$LOCK_DIR"
sudo chmod 0750 "$LOCK_DIR"
rm -f "$LOCK_FILE" 2>/dev/null || true

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"
# No-op `sleep` -- see header comment. Never touches the real coreutils
# sleep; only shadows it for the duration of THIS fence's own PATH.
cat > "$FAKE_BIN/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN/sleep"

FAILURES=0

run_scenario() {
  # 4th arg (fake_mode) is OPTIONAL and defaults to $name -- added so the
  # DEPLOY_ON_SUCCESS=1 leg can carry its own scenario NAME (for its own
  # state dir / log file / PASS-FAIL line) while still selecting
  # fake-curl's existing 'happy' canned responses (no fake-curl change
  # needed: the SAME responses answer the one extra call that mode
  # triggers).
  local name="$1" want_exit="$2" want_grep="$3" fake_mode="${4:-$1}"
  local state_dir log_file out rc
  state_dir="$WORK/state-$name"
  mkdir -p "$state_dir"
  log_file="$WORK/curl-log-$name.txt"
  : > "$log_file"

  set +e
  out="$(env -i \
    PATH="$FAKE_BIN:/usr/bin:/bin:/usr/local/bin" \
    HOME="$HOME" \
    FAKE_MODE="$fake_mode" \
    FAKE_STATE_DIR="$state_dir" \
    FAKE_CURL_LOG="$log_file" \
    MIGRATOR_EXPECT_SHA="$EXPECT_SHA" \
    bash "$ORCHESTRATE_SH" 2>&1)"
  rc=$?
  set -e

  local ok=1
  if [[ "$rc" != "$want_exit" ]]; then
    echo "FAIL [$name]: expected exit $want_exit, got $rc" >&2
    ok=0
  fi
  if ! printf '%s' "$out" | grep -qF "$want_grep"; then
    echo "FAIL [$name]: expected output to contain: $want_grep" >&2
    echo "----- actual output -----" >&2
    printf '%s\n' "$out" >&2
    echo "--------------------------" >&2
    ok=0
  fi
  if grep -qF "$FAKE_TOKEN" "$log_file"; then
    echo "FAIL [$name]: the fake Coolify API token leaked into a logged curl argv" >&2
    ok=0
  fi
  # Every non-happy scenario must stop BEFORE the tagged-line outcome
  # assertion ever runs -- proving the new section gates, not merely logs.
  # (Matches "happy" and "happy-deploy-on-success" -- both are expected to
  # reach it; every failure leg is not.)
  if [[ "$name" != happy* ]] && printf '%s' "$out" | grep -qF "outcome verified via the execution's own message"; then
    echo "FAIL [$name]: reached the post-execute tagged-line assertion -- the new deploy-then-execute section did not actually stop the run" >&2
    ok=0
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS [$name]"
  else
    FAILURES=$((FAILURES + 1))
  fi
}

run_scenario "name-mismatch"   16 "is named 'pfin-supabase-stack', not the expected 'pfin-migrator-test'"
# Sec joint review, PR #831 (defence-in-depth, F/CTO's call, taken): the
# name guard alone is one field deep -- base_directory is a SECOND,
# independent field this leg proves is actually checked, not merely
# declared in a comment. Correct NAME, wrong base_directory.
run_scenario "base-dir-mismatch" 16 "but its base_directory is '/', not the expected '/infra/supabase/migrator'"
run_scenario "deploy-failed"   1  "reached a non-finished TERMINAL state (status=failed"
# Sec F3, PR #831 joint review: "gave up after" is NOT a unique anchor --
# it appears twice in migrator-orchestrate.sh (this deploy-poll timeout at
# one site, the pre-existing execution-poll timeout at another), so this
# leg could pass on the wrong branch. Anchor on the deploy-poll's own
# unique clause instead.
run_scenario "deploy-timeout"  1  "waiting for the migrator deploy to reach a terminal state"
# Sec joint review, PR #831: a cancelled deployment (an operator hitting
# Cancel in the Coolify UI mid-build) is a DISTINCT terminal state from
# 'failed' and must not be misdiagnosed as a poll timeout -- the poll
# loop's own `case` breaks on ANY non-queued/non-in_progress status, so
# this is the leg proving 'cancelled-by-user' takes the same fail-closed
# branch as 'failed', not the (wrong) generic-timeout branch.
run_scenario "deploy-cancelled" 1 "reached a non-finished TERMINAL state (status=cancelled-by-user"
run_scenario "commit-mismatch" 18 "not the sha this fire was triggered for"
run_scenario "happy"           0  "app deploy SUPPRESSED"

# Sec joint review, PR #831 (Q9): the app-deploy-on-success call was fixed
# GET -> POST in this same PR, but DEPLOY_ON_SUCCESS defaults to 0 in
# production (the runbook's own §6.4 step 3 note), so nothing exercises
# that line until an operator flips the flag at runbook §7 step 7 -- add
# the leg BEFORE that flip, not after. Flips the fixture conf's own
# DEPLOY_ON_SUCCESS to 1 (sudo, in place -- this fence already owns this
# file) for this ONE scenario; nothing runs after it in this script, so no
# restore is needed. FAKE_MODE stays "happy" (4th arg) -- the same canned
# responses answer the one extra POST /deploy?uuid=<app-uuid> call this
# mode triggers; only the scenario's own NAME (and therefore its state
# dir / log file / PASS-FAIL line) differs.
sudo sed -i 's/^DEPLOY_ON_SUCCESS=.*/DEPLOY_ON_SUCCESS=1/' "$CONF_FILE"
run_scenario "happy-deploy-on-success" 0 "app deploy triggered" "happy"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "FATAL: $FAILURES scenario(s) failed -- see above." >&2
  exit 1
fi
echo "OK: all 8 migrator-orchestrate.sh deploy-then-execute scenarios behaved as specified."
