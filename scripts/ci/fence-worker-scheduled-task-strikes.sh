#!/usr/bin/env bash
#
# fence-worker-scheduled-task-strikes.sh -- offline strike-proof for
# scripts/worker-scheduled-task.sh. Runs entirely without a live box: a
# fake `ssh` rewrites the `/root/.pfin` path the script's remote driver
# hardcodes, then runs it locally with
# tests/fixtures/ci/worker-scheduled-task/fake-curl standing in for the
# real Coolify API -- scripts/worker-scheduled-task.sh itself is never
# modified or made aware this exists. Same strike shape as
# scripts/ci/fence-coolify-env-strikes.sh.
#
# Scenarios (BACKLOG.md §7.36 item 68, W-3):
#   1. UNKNOWN-TASK-NAME -- refuses before any SSH/API call, exit 2.
#   2. ABSENT-PREFLIGHT -- task does not exist, no --apply -> preflight
#      only, exit 0, prints the would-create plan, creates nothing.
#   3. ABSENT-APPLY -- task does not exist, --apply -> creates it,
#      post-create read-back matches byte-exact -> exit 0.
#   4. ALREADY-MATCH -- a task with this name already exists and matches
#      the table's command/container/frequency/enabled exactly -> exit 0,
#      no create call made (idempotent).
#   5. ALREADY-MISMATCH -- an existing task disagrees on `command` ->
#      refuses (never mutates a live, disagreeing Scheduled Task).
#   6. AMBIGUOUS -- two tasks share the same name -> refuses, never
#      guesses which is authoritative.
#   7. READBACK-MISMATCH -- the create call "succeeds" but the post-create
#      read-back disagrees on `container` -> refuses (does not trust the
#      create response alone).
#   8. SECOND-TASK -- the same script, run for the OTHER known task name
#      (pfin-provider-sync-daily-poll), resolves the correct application
#      and uses the correct table row -- proves the table-driven design
#      is not silently hardcoded to the first entry.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/worker-scheduled-task"
TASK_SH="$REPO_ROOT/scripts/worker-scheduled-task.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$TASK_SH" ]] || { echo "FATAL: $TASK_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=fake-coolify-token-do-not-leak\n' > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *" true" ]]; then
  exit 0
fi
if [[ "\$*" == *"test -s /root/.pfin/coolify.env"* ]]; then
  exit 0
fi
LAST="\${@: -1}"
if [[ "\$LAST" == "-s" || "\$LAST" == *" bash -s" ]]; then
  CMDLINE="\$LAST"
  [[ "\$CMDLINE" == "-s" ]] && CMDLINE="bash -s"
  CMDLINE="\$(printf '%s' "\$CMDLINE" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\${FAKE_CURL_LOG:-}" FAKE_TASK_MODE="\${FAKE_TASK_MODE:-}" \\
    FAKE_CALL_COUNTER="\${FAKE_CALL_COUNTER:-}" FAKE_WANT_NAME="\${FAKE_WANT_NAME:-}" \\
    FAKE_WANT_COMMAND="\${FAKE_WANT_COMMAND:-}" FAKE_WANT_CONTAINER="\${FAKE_WANT_CONTAINER:-}" \\
    FAKE_WANT_FREQUENCY="\${FAKE_WANT_FREQUENCY:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <task_name> <apply_flag> <task_mode> <want_command> <want_container> <want_frequency>
  local desc="$1" expect_exit="$2" task_name="$3" apply_flag="$4" task_mode="$5" want_command="$6" want_container="$7" want_frequency="$8"
  local counter="$WORK/counter.$$.$RANDOM"
  rm -f "$counter"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$WORK/curl.log.$$.$RANDOM" \
    FAKE_TASK_MODE="$task_mode" FAKE_CALL_COUNTER="$counter" \
    FAKE_WANT_NAME="$task_name" FAKE_WANT_COMMAND="$want_command" \
    FAKE_WANT_CONTAINER="$want_container" FAKE_WANT_FREQUENCY="$want_frequency" \
    bash "$TASK_SH" "$task_name" $apply_flag < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  cat "$WORK/out.$$"
  return 0
}

FAIL=0

# 1. UNKNOWN-TASK-NAME
OUT1="$(run_scenario "unknown task name: refuses" 2 pfin-does-not-exist "" absent "x" "x" "x")" || FAIL=1
grep -qF "unrecognised task-name" <<<"${OUT1:-}" || { echo "FAIL: [unknown task name] did not name the offending predicate" >&2; FAIL=1; }

# 2. ABSENT-PREFLIGHT
OUT2="$(run_scenario "absent, preflight: exit 0, creates nothing" 0 pfin-back-etl-monthly-report "" absent "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "PREFLIGHT ONLY" <<<"${OUT2:-}" || { echo "FAIL: [absent preflight] did not print PREFLIGHT ONLY" >&2; FAIL=1; }

# 3. ABSENT-APPLY
OUT3="$(run_scenario "absent, --apply: creates, read-back matches" 0 pfin-back-etl-monthly-report --apply absent "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "created 'pfin-back-etl-monthly-report'" <<<"${OUT3:-}" || { echo "FAIL: [absent apply] did not report a create" >&2; FAIL=1; }

# 4. ALREADY-MATCH
OUT4="$(run_scenario "already matches: exit 0, no create" 0 pfin-back-etl-monthly-report --apply match "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "already matches" <<<"${OUT4:-}" || { echo "FAIL: [already match] did not report an existing match" >&2; FAIL=1; }

# 5. ALREADY-MISMATCH
OUT5="$(run_scenario "already mismatched: refuses" 1 pfin-back-etl-monthly-report --apply mismatch "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "disagrees with this script" <<<"${OUT5:-}" || { echo "FAIL: [already mismatch] did not name the disagreement" >&2; FAIL=1; }

# 6. AMBIGUOUS
OUT6="$(run_scenario "ambiguous: refuses" 1 pfin-back-etl-monthly-report --apply ambiguous "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "ambiguous" <<<"${OUT6:-}" || { echo "FAIL: [ambiguous] did not name the ambiguity" >&2; FAIL=1; }

# 7. READBACK-MISMATCH
OUT7="$(run_scenario "post-create readback mismatch: refuses" 1 pfin-back-etl-monthly-report --apply readback-mismatch "python run_monthly_report.py" "pfin-back-etl-monthly-report" "0 6 1 * *")" || FAIL=1
grep -qF "read-back MISMATCH" <<<"${OUT7:-}" || { echo "FAIL: [readback mismatch] did not name the mismatch" >&2; FAIL=1; }

# 8. SECOND-TASK -- the other table row resolves correctly (table-driven,
#    not hardcoded to the first entry).
OUT8="$(run_scenario "second task (provider-sync poll): resolves and creates" 0 pfin-provider-sync-daily-poll --apply absent "node dist/cli/poll.js" "provider-sync" "@daily")" || FAIL=1
grep -qF "application 'pfin-provider-sync'" <<<"${OUT8:-}" || { echo "FAIL: [second task] did not resolve the correct application" >&2; FAIL=1; }

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more worker-scheduled-task.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all worker-scheduled-task.sh strike-proofs passed."
exit 0
