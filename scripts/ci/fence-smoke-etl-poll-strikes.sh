#!/usr/bin/env bash
#
# fence-smoke-etl-poll-strikes.sh -- offline strike-proof for
# scripts/smoke-etl-poll.sh's STRUCTURAL logic: container resolution,
# worker exit-code propagation, the completion-log-line check, and the
# row-count threshold (>=1 vs 0). BACKLOG.md §7.36 item 68 (W-3).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- stated, not glossed:
# whether `run_nav_daily.py` actually computes a correct NAV or whether
# `pfin.nav_daily`'s real schema/grants genuinely allow the write. Both
# fake-docker legs (the worker run and the row-count read-back) return
# CANNED output -- they never touch a real Postgres, a real
# TenantBoundConnection, or real tenant data. This fence proves the
# SHELL SCRIPT's own control flow is correct (it refuses on the right
# conditions, passes on the right conditions); it is not, and cannot be,
# a substitute for actually running scripts/smoke-etl-poll.sh against a
# real box -- that leg is live-only, same posture the script's own
# header states for the F/CTO+Backend-consult compose-wiring gap it
# works around.
#
# Scenarios:
#   1. HAPPY-PATH -- worker exits 0 with a completion line, row count
#      >=1 -> exit 0.
#   2. WORKER-FAILS -- worker exits non-zero -> refuses.
#   3. NO-COMPLETION-LINE -- worker exits 0 but never prints "Finished
#      at" -> refuses (an incomplete run, not trusted on exit code
#      alone).
#   4. ZERO-ROWS -- worker exits 0 with a completion line, but the
#      row-count read-back is 0 -> refuses (a silent no-op).
#   5. COUNT-CONN-ERROR -- the row-count read-back itself fails to
#      connect -> exit 2 (a precondition this smoke could not even
#      attempt under, not a poll failure).
#   6. AMBIGUOUS -- 2 running containers match the compose service ->
#      refuses, never silently picking one (Sec F4 discipline).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-etl-poll"
SMOKE_SH="$REPO_ROOT/scripts/smoke-etl-poll.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-docker" ]] || { echo "FATAL: $FIXTURE_DIR/fake-docker missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=fake-coolify-token-do-not-leak\n' > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"
ln -s "$FIXTURE_DIR/fake-docker" "$FAKE_BIN/docker"

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
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\${FAKE_CURL_LOG:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_WORKER_MODE="\${FAKE_WORKER_MODE:-}" FAKE_COUNT_MODE="\${FAKE_COUNT_MODE:-}" \\
  FAKE_COUNT="\${FAKE_COUNT:-}" FAKE_CONTAINERS="\${FAKE_CONTAINERS:-}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <worker_mode> <count_mode> <count> <containers>
  local desc="$1" expect_exit="$2" worker_mode="$3" count_mode="$4" count="$5" containers="$6"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$WORK/curl.log.$$.$RANDOM" \
    FAKE_WORKER_MODE="$worker_mode" FAKE_COUNT_MODE="$count_mode" FAKE_COUNT="$count" FAKE_CONTAINERS="$containers" \
    bash "$SMOKE_SH" < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  return 0
}

FAIL=0

run_scenario "happy-path" 0 ok ok 3 1 || FAIL=1
run_scenario "worker fails: refuses" 1 fail ok 3 1 || FAIL=1
run_scenario "no completion line: refuses" 1 no-completion-line ok 3 1 || FAIL=1
run_scenario "zero rows: refuses (silent no-op)" 1 ok ok 0 1 || FAIL=1
run_scenario "row-count connection error: precondition, exit 2" 2 ok conn-error 3 1 || FAIL=1
run_scenario "ambiguous: 2 running containers refuses" 1 ok ok 3 2 || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-etl-poll.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-etl-poll.sh strike-proofs passed."
exit 0
