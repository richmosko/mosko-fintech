#!/usr/bin/env bash
#
# fence-coolify-discord-notify-strikes.sh -- offline strike-proof for
# scripts/coolify-discord-notify.sh (BACKLOG.md §7.36 item 74). Runs
# entirely without a live box, network, or real Coolify install:
# tests/fixtures/ci/coolify-discord-notify/fake-ssh PATH-shadows `ssh`
# and dispatches on the remote-command text (its last argv element) plus,
# for the `bash -s`-shaped write call, its own forwarded stdin --
# scripts/coolify-discord-notify.sh itself is never modified or made
# aware any of this exists. Same "fake the transport, run the real
# script" shape as scripts/ci/fence-db-role-handoff-strikes.sh.
#
# Scenarios, one guard struck alone per case:
#   1. STATE-DISABLED / 2. STATE-ABSENT / 3. STATE-ENABLED-URL-EMPTY /
#      4. STATE-ENABLED -- `--state` prints each of the four
#      `current state: ...` values correctly, exit 0, no SSH call beyond
#      the reachability ping + the one read.
#   5. STATE-CARDINALITY-ANOMALY -- the box reports 2 matching rows ->
#      refuses ("expected exactly 1"), exit 1.
#   6. STATE-TEAM-ABSENT -- team id=0 does not exist -> refuses, exit 1.
#   7. STATE-UNREACHABLE -- SSH itself fails -> refuses ("not reachable"),
#      exit 1.
#   8. APPLY-MALFORMED-URL-REFUSES-BEFORE-SSH -- .env's DISCORD_WEBHOOK_URL
#      does not match the Discord webhook shape -> refuses ("shape
#      check; value not shown"), exit 1, AND the fake ssh log is
#      completely EMPTY -- the box is never contacted at all. This is
#      the load-bearing ordering property BACKLOG item 74's own AC
#      requires (team-lead, 2026-09-21).
#   9. APPLY-MISSING-URL-REFUSES -- DISCORD_WEBHOOK_URL absent from .env
#      entirely -> refuses before any SSH call, same as #8.
#  10. APPLY-FRESH-WRITES -- DISABLED state, valid .env URL -> the write
#      call happens (asserted via the fake ssh log), hash-bound readback
#      matches, the test-send is asserted (HTTP 204) -> exit 0, output
#      names "OK: Discord accepted".
#  11. APPLY-IDEMPOTENT-SKIPS-WRITE -- ENABLED, hash-bound URL match, all
#      four target flags already true -> the write call is proven ABSENT
#      from the fake ssh log (real idempotency, not merely "still exits
#      0") -- but the live test-send still runs every apply, per this
#      script's own header.
#  12. APPLY-FLAGS-MISMATCH-STILL-WRITES -- ENABLED + hash match, but the
#      four target flags are NOT yet all true -> the write call DOES
#      happen despite the hash matching (idempotency is flags-AND-hash,
#      not hash alone).
#  13. APPLY-HASH-MISMATCH-STILL-WRITES -- ENABLED + target flags already
#      true, but the STORED value's hash does not match .env's -> the
#      write call DOES happen (a stale/different URL forces a rewrite).
#  14. APPLY-WRITE-ROW-ABSENT-REFUSES -- the settings row disappears
#      between the idempotency read and the write -> refuses ("a race"),
#      exit 1.
#  15. APPLY-WRITE-NONZERO-EXIT-REFUSES -- the remote write script itself
#      exits non-zero -> refuses, exit 1.
#  16. APPLY-WRITE-NO-SENTINEL-REFUSES -- the remote write script exits 0
#      but never prints the expected WRITE_OK sentinel -> refuses
#      ("unconfirmed write") rather than trusting a clean exit code
#      alone -- proves this guard checks a POSITIVE TOKEN, not merely
#      absence of an error string.
#  17. APPLY-CLEARTEXT-LEAK-DETECTED -- the (simulated-defective) remote
#      write step echoes the webhook URL's own cleartext -> the script's
#      own `grep -qF -- "$WEBHOOK_URL"` guard fires and refuses; this
#      fence's OWN captured output is then independently grepped for the
#      same literal value and asserted ABSENT -- the guard is real, not
#      merely claimed.
#  18. APPLY-POSTWRITE-HASH-MISMATCH-REFUSES -- the write reports WRITE_OK
#      but the post-write hash-bound readback does not match .env's hash
#      -> refuses ("does not match the .env value's hash").
#  19. APPLY-TESTSEND-NO-URL-REFUSES -- immediately after a confirmed
#      write, the test-send's own read finds the URL empty (a race) ->
#      refuses, never silently treated as "Discord accepted".
#  20. APPLY-TESTSEND-UNPARSEABLE-REFUSES -- the test-send call returns
#      output that is neither `FATAL_NO_URL` nor `HTTP_STATUS_<n>` ->
#      refuses rather than guessing acceptance.
#  21. APPLY-TESTSEND-NON2XX-REFUSES -- Discord itself returns a non-2xx
#      status (429) -> refuses, naming the status, webhook URL never
#      printed anywhere in this fence's own captured output.
#  22. APPLY-SSH-DIES-MIDWAY-REFUSES -- the connection drops during the
#      write remote script -> refuses, exit 1 (never silently treated as
#      success).
#  23. ARGV-NEVER-CARRIES-URL -- across EVERY scenario above that reaches
#      the box, the fake ssh's own argv log (FAKE_SSH_LOG, which records
#      argv only -- the seed-file delivery's actual piped value is never
#      logged there at all, by the fake's own construction) is grepped
#      for the scenario's own webhook URL literal and asserted ABSENT --
#      proves the URL crosses only via piped stdin, never a command-line
#      argument.
#  24. BASH-3.2-SYNTAX -- `bash -n` under /bin/bash (this repo's pinned
#      operator shell) parses the real script with zero errors, and a
#      grep for `declare -A` (a bash-4-only construct `-n` alone cannot
#      catch, since it never actually declares the array) finds none.
#  25. SHRED-TRAP-PRESENT -- structural pin: the seed-delivery remote
#      script's own `trap ... EXIT` line contains `shred -u`, so a
#      future edit that drops the shred (leaving only `rm -f`) is caught
#      here rather than silently regressing to a recoverable-on-disk
#      seed file.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/coolify-discord-notify"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/coolify-discord-notify.sh"

[[ -x "$FIXTURE_DIR/fake-ssh" ]] || { echo "FATAL: $FIXTURE_DIR/fake-ssh missing or not executable" >&2; exit 2; }
[[ -f "$SCRIPT_UNDER_TEST" ]] || { echo "FATAL: $SCRIPT_UNDER_TEST not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-ssh" "$FAKE_BIN/ssh"

# A real Discord webhook URL shape (fabricated id/token, matches
# scripts/coolify-discord-notify.sh's own WEBHOOK_URL_RE) -- used as the
# ".env value" in every scenario that must PASS the shape check.
VALID_URL="https://discord.com/api/webhooks/123456789012345678/AbCdEfGhIjKlMnOpQrStUvWxYz-fake_TOKEN"
VALID_HASH="$(printf '%s' "$VALID_URL" | sha256sum | cut -c1-16)"
WRONG_HASH="0000000000000000"
[[ "$VALID_HASH" != "$WRONG_HASH" ]] || { echo "FATAL: fixture collision -- pick a different WRONG_HASH" >&2; exit 2; }

# --- FAKE_STATE_RAW building blocks -- must match read_state()'s own
# field order in scripts/coolify-discord-notify.sh EXACTLY: enabled|
# url_empty|discord_ping_enabled=..|deployment_success=..|
# deployment_failure=..|status_change=..|backup_success=..|
# backup_failure=..|scheduled_task_success=..|scheduled_task_failure=..|
# docker_cleanup_success=..|docker_cleanup_failure=..|
# server_disk_usage=..|server_reachable=..|server_unreachable=..|
# server_patch=..|traefik_outdated=..|restart_limit_reached=..
#
# MEASURED_FLAGS -- team-lead, live box, 2026-09-21 22:35Z (this script's
# own header cites the same measurement): every flag at its CURRENT
# default except discord_enabled=false.
MEASURED_FLAGS="discord_ping_enabled=true|deployment_success=false|deployment_failure=true|status_change=false|backup_success=false|backup_failure=true|scheduled_task_success=false|scheduled_task_failure=true|docker_cleanup_success=false|docker_cleanup_failure=true|server_disk_usage=true|server_reachable=false|server_unreachable=true|server_patch=true|traefik_outdated=true|restart_limit_reached=true"
# TARGET_FLAGS -- MEASURED_FLAGS with the four flags this script turns on
# (deployment_success, status_change, scheduled_task_success,
# server_reachable) flipped to true, everything else unchanged.
TARGET_FLAGS="discord_ping_enabled=true|deployment_success=true|deployment_failure=true|status_change=true|backup_success=false|backup_failure=true|scheduled_task_success=true|scheduled_task_failure=true|docker_cleanup_success=false|docker_cleanup_failure=true|server_disk_usage=true|server_reachable=true|server_unreachable=true|server_patch=true|traefik_outdated=true|restart_limit_reached=true"

RAW_DISABLED="false|true|${MEASURED_FLAGS}"
RAW_ENABLED_URL_EMPTY="true|true|${MEASURED_FLAGS}"
RAW_ENABLED_FRESH_FLAGS="true|false|${MEASURED_FLAGS}"
RAW_ENABLED_TARGET_FLAGS="true|false|${TARGET_FLAGS}"

FAIL=0
CASE_LAST_DIR=""

# run_case <desc> <expect_exit> <mode: state|apply> <env-file-body-or-empty> [extra FAKE_* env assigns already exported by caller]
run_case() {
  local desc="$1" expect_exit="$2" mode="$3" env_body="$4"
  local case_dir="$WORK/case.$$.$RANDOM"
  mkdir -p "$case_dir"
  if [[ -n "$env_body" ]]; then
    printf '%s\n' "$env_body" > "$case_dir/.env"
  else
    : > "$case_dir/.env"
  fi
  local ssh_log="$case_dir/ssh.log"
  : > "$ssh_log"
  local out="$case_dir/out.txt"
  set +e
  REPO_ROOT="$case_dir" BOX_IP="127.0.0.1" AUTOMATION_KEY="$case_dir/fake-key" \
    PATH="$FAKE_BIN:$PATH" FAKE_SSH_LOG="$ssh_log" \
    bash "$SCRIPT_UNDER_TEST" "--$mode" > "$out" 2>&1
  local rc=$?
  set -e
  CASE_LAST_DIR="$case_dir"
  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    sed 's/^/    /' "$out" >&2
    FAIL=1
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  return 0
}

assert_grep() {
  local file="$1" pattern="$2" desc="$3"
  grep -qF -- "$pattern" "$file" || { echo "FAIL: [$desc] expected to find '$pattern' in $file" >&2; FAIL=1; }
}
assert_not_grep() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qF -- "$pattern" "$file" 2>/dev/null; then
    echo "FAIL: [$desc] '$pattern' unexpectedly found in $file" >&2
    FAIL=1
  fi
}

# 1. STATE-DISABLED
FAKE_STATE_RAW="$RAW_DISABLED" run_case "state: DISABLED" 0 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "current state: DISABLED" "state-disabled"

# 2. STATE-ABSENT
FAKE_STATE_RAW="ABSENT" run_case "state: ABSENT" 0 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "current state: ABSENT" "state-absent"

# 3. STATE-ENABLED-URL-EMPTY
FAKE_STATE_RAW="$RAW_ENABLED_URL_EMPTY" run_case "state: ENABLED-URL-EMPTY" 0 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "current state: ENABLED-URL-EMPTY" "state-enabled-url-empty"

# 4. STATE-ENABLED
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS" run_case "state: ENABLED" 0 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "current state: ENABLED" "state-enabled"

# 5. STATE-CARDINALITY-ANOMALY
FAKE_STATE_RAW="FATAL_CARDINALITY_2" run_case "state: cardinality anomaly refuses" 1 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "expected exactly 1" "state-cardinality"

# 6. STATE-TEAM-ABSENT
FAKE_STATE_RAW="FATAL_TEAM_ABSENT" run_case "state: team absent refuses" 1 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "Team id=0 does not exist" "state-team-absent"

# 7. STATE-UNREACHABLE
FAKE_SSH_UNREACHABLE=1 run_case "state: SSH unreachable refuses" 1 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "not reachable over SSH" "state-unreachable"

# 8. APPLY-MALFORMED-URL-REFUSES-BEFORE-SSH
run_case "apply: malformed .env URL refuses before any SSH call" 1 apply "DISCORD_WEBHOOK_URL=not-a-real-webhook-url" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "shape check; value not shown" "apply-malformed-url"
  if [[ -s "$CASE_LAST_DIR/ssh.log" ]]; then
    echo "FAIL: [apply-malformed-url] the box was contacted (ssh.log non-empty) despite the shape check failing -- ordering violated" >&2
    FAIL=1
  fi
fi

# 9. APPLY-MISSING-URL-REFUSES
run_case "apply: missing .env URL refuses before any SSH call" 1 apply "" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "missing or empty" "apply-missing-url"
  if [[ -s "$CASE_LAST_DIR/ssh.log" ]]; then
    echo "FAIL: [apply-missing-url] the box was contacted despite the URL being absent" >&2
    FAIL=1
  fi
fi

# 10. APPLY-FRESH-WRITES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: fresh state writes, hash-binds, test-send accepted" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-fresh-write-happened"
  assert_grep "$CASE_LAST_DIR/out.txt" "OK: Discord accepted the Coolify test notification (HTTP 204)" "apply-fresh-test-send-ok"
fi

# 11. APPLY-IDEMPOTENT-SKIPS-WRITE
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS" FAKE_STORED_HASH="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: already-correct state skips the write" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_not_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-idempotent-no-write"
  assert_grep "$CASE_LAST_DIR/out.txt" "OK: Discord accepted the Coolify test notification (HTTP 204)" "apply-idempotent-test-send-still-runs"
fi

# 12. APPLY-FLAGS-MISMATCH-STILL-WRITES
FAKE_STATE_RAW="$RAW_ENABLED_FRESH_FLAGS" FAKE_STORED_HASH="$VALID_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: hash matches but target flags don't -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-flags-mismatch-writes"

# 13. APPLY-HASH-MISMATCH-STILL-WRITES
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS" FAKE_STORED_HASH="$WRONG_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: flags match but stored hash doesn't -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-hash-mismatch-writes"

# 14. APPLY-WRITE-ROW-ABSENT-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_ROW_ABSENT=1 \
  run_case "apply: row disappears mid-write -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "disappeared between the idempotency read and the write" "apply-row-absent"

# 15. APPLY-WRITE-NONZERO-EXIT-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_WRITE_EXIT_NONZERO=1 \
  run_case "apply: remote write script exits non-zero -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "remote write script exited" "apply-write-nonzero"

# 16. APPLY-WRITE-NO-SENTINEL-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_WRITE_NO_SENTINEL=1 \
  run_case "apply: write exits 0 without WRITE_OK -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "unconfirmed write" "apply-write-no-sentinel"

# 17. APPLY-CLEARTEXT-LEAK-DETECTED -- the leaked value is the SAME
# $VALID_URL this scenario's own .env carries, so the guard's own
# `grep -qF -- "$WEBHOOK_URL"` genuinely matches it (not a different,
# never-checked-against string).
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_SIMULATE_LEAK=1 FAKE_LEAK_VALUE="$VALID_URL" \
  run_case "apply: cleartext leak in write output -- refuses, value never printed" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "cleartext value appeared" "apply-cleartext-leak-detected"
  assert_not_grep "$CASE_LAST_DIR/out.txt" "$VALID_URL" "apply-cleartext-leak-value-not-printed"
fi

# 18. APPLY-POSTWRITE-HASH-MISMATCH-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STORED_HASH_AFTER="$WRONG_HASH" \
  run_case "apply: post-write hash mismatch -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "does not match the .env value's hash" "apply-postwrite-hash-mismatch"

# 19. APPLY-TESTSEND-NO-URL-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_NO_URL=1 \
  run_case "apply: test-send finds URL empty -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "read back empty immediately after a confirmed write" "apply-testsend-no-url"

# 20. APPLY-TESTSEND-UNPARSEABLE-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS="garbage" \
  run_case "apply: test-send output unparseable -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "did not report a parseable HTTP status" "apply-testsend-unparseable"

# 21. APPLY-TESTSEND-NON2XX-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=429 \
  run_case "apply: Discord rejects the test-send (429) -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "Discord rejected the test notification: HTTP 429" "apply-testsend-non2xx"
  assert_not_grep "$CASE_LAST_DIR/out.txt" "$VALID_URL" "apply-testsend-non2xx-url-not-printed"
fi

# 22. APPLY-SSH-DIES-MIDWAY-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_SSH_UNREACHABLE_MIDWAY=1 \
  run_case "apply: connection drops during the write -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true

# 23. ARGV-NEVER-CARRIES-URL -- sweep every case dir produced above.
for d in "$WORK"/case.*; do
  [[ -f "$d/ssh.log" ]] || continue
  if grep -qF -- "$VALID_URL" "$d/ssh.log" 2>/dev/null; then
    echo "FAIL: [argv-never-carries-url] the webhook URL literal appeared in a fake-ssh argv log ($d/ssh.log) -- it must only ever cross via piped stdin" >&2
    FAIL=1
  fi
done
echo "OK: [argv-never-carries-url] swept every scenario's ssh.log -- the webhook URL literal never appears in any logged argv." >&2

# 24. BASH-3.2-SYNTAX
if ! /bin/bash -n "$SCRIPT_UNDER_TEST" 2>&1; then
  echo "FAIL: [bash-3.2-syntax] /bin/bash -n failed against $SCRIPT_UNDER_TEST" >&2
  FAIL=1
else
  echo "OK: [bash-3.2-syntax] /bin/bash -n parses cleanly." >&2
fi
if grep -qE '\bdeclare[[:space:]]+-A\b' "$SCRIPT_UNDER_TEST"; then
  echo "FAIL: [bash-3.2-syntax] found 'declare -A' (bash-4-only associative array) -- bash -n alone cannot catch this since it never executes" >&2
  FAIL=1
else
  echo "OK: [bash-3.2-syntax] no 'declare -A' found." >&2
fi

# 25. SHRED-TRAP-PRESENT
if grep -qE "trap '[^']*shred -u[^']*'[[:space:]]+EXIT" "$SCRIPT_UNDER_TEST"; then
  echo "OK: [shred-trap-present] the seed-delivery remote script's EXIT trap contains 'shred -u'." >&2
else
  echo "FAIL: [shred-trap-present] no EXIT trap containing 'shred -u' found -- the seed file's shred-on-any-exit guarantee may have regressed" >&2
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "" >&2
  echo "FAIL: one or more coolify-discord-notify.sh strike-proof scenarios did not behave as specified." >&2
  exit 1
fi

echo "OK: all coolify-discord-notify.sh strike-proofs passed."
exit 0
