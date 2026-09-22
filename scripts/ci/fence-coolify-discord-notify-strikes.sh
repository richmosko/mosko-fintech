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
#  12b. APPLY-BACKUP-FAILURE-STALE-STILL-WRITES (Sec ruling, PR #871
#      review) -- every OTHER target flag + the hash already match, but
#      backup_failure is still the box's measured `true` default (this
#      script now writes it `false` -- BackupFailed.php's own `Output`
#      field is unbounded command output) -> the write call DOES happen
#      on this ONE flag alone, proving the idempotency check's
#      backup_failure comparison is independently load-bearing.
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
#      script's own `report_shred_seed()` function contains `shred -u`,
#      AND is wired to BOTH `trap report_shred_seed EXIT` and a split
#      `trap '...report_shred_seed...' HUP INT TERM` (the PR #870
#      double-fire fix: EXIT must be disarmed before the signal handler
#      re-invokes it) -- a future edit that drops the shred, or that
#      recombines the two traps back into one, is caught here.
#  26. COLUMN-NAMES-PINNED-IN-SOURCE -- structural pin (FACT-13): every
#      one of the 16 real `discord_notification_settings` column names
#      (15 `<event>_discord_notifications` + `discord_ping_enabled`) is
#      grepped directly against the real script's OWN source -- a future
#      edit that reverts any one of them to its bare display name is
#      caught here, independent of any runtime behaviour.
#  27. COLUMN-NAMES-IN-GENERATED-PAYLOAD -- a normal write scenario's
#      actual remote-script BODY (as `php_update_fields()`/
#      `php_field_map()` generate it at runtime, captured verbatim by
#      the fake via FAKE_WRITE_PAYLOAD_LOG) is grepped for the same 16
#      names -- proves the RUNTIME-GENERATED payload matches the source
#      pin in #26, not just the static text.
#  28. APPLY-SHORT-COLUMN-REGRESSION-FAILS -- models a hypothetical
#      regression where the write's columns go unrecognized by Eloquent
#      (the real silent-`$fillable`-drop behaviour: WRITE_OK still
#      prints, but nothing actually changed) by having the post-write
#      flag re-read come back IDENTICAL to the pre-write read -> the
#      real script's own post-write flag-readback check (added alongside
#      this fix) must refuse rather than report success. Proves the fix
#      has a runtime backstop, not just the static pin in #26.
#  29. APPLY-WRITE-NO-DESTROYED-LINE-REFUSES -- models run 18's own
#      defect directly: the remote write script exits 0 and prints
#      WRITE_OK, but never prints report_shred_seed()'s own "DESTROYED:
#      ..." confirmation -> the caller refuses rather than silently
#      assuming the seed file was cleaned up ("run 18 destroyed it but
#      reported nothing").
#  30. APPLY-NULL-FLAG-FORCES-WRITE -- backup_failure reads back a
#      genuine NULL (Sec requirement) instead of the box's measured
#      `true` default, with the hash and every OTHER target flag
#      already matching -> the write call DOES happen, proving NULL is
#      never coerced to "false" and accepted as an idempotency match
#      against backup_failure's own false target.
#  31. APPLY-POSTWRITE-NULL-FLAG-FAILS -- the post-write flag re-read
#      comes back with backup_failure still NULL (the write did not
#      actually land on that one column) -> the real script's post-write
#      flag-readback check refuses rather than treating NULL as
#      close-enough to false.
#  32. STATE-UNKNOWN-COLUMN -- the box's own read reports it could not
#      find `backup_failure_discord_notifications` (Sec F-1, PR #873
#      round 2: a regression to a wrong/short name on a TARGET-FALSE
#      flag specifically -- on a target-true flag the existing
#      true/false comparison would already refuse, masking whether this
#      NEW array_key_exists() guard fired at all) -> refuses
#      immediately, naming the exact column, rather than folding a
#      missing column into "false" and passing silently.
#  33. APPLY-UNKNOWN-COLUMN-REFUSES-BEFORE-WRITE -- same FATAL, surfaced
#      on --apply's own PRE-write idempotency read -> refuses, and the
#      box is never asked to write at all (ssh.log carries no write
#      call) -- the guard fires before any write is attempted, not only
#      after one silently no-ops.
#  34. APPLY-PING-STALE-STILL-WRITES (run 19 fix, team-lead) -- hash +
#      every OTHER target flag already match, but discord_ping_enabled
#      is still `false` -> the write call DOES happen on this ONE flag
#      alone, proving the idempotency check's discord_ping_enabled
#      comparison (added alongside EVENT_FLAGS membership in this fix)
#      is independently load-bearing, the same rigor scenario 12b
#      already applies to backup_failure.
#  35. APPLY-POSTWRITE-PING-ABSENT-FAILS -- the post-write flag re-read
#      omits the discord_ping_enabled field ENTIRELY (not merely
#      wrong-valued) -- the same observable shape run 19's actual defect
#      had before this fix (read_state() never printed it at all) ->
#      the post-write flag-readback check must FATAL naming
#      discord_ping_enabled specifically, not silently treat an absent
#      field as false-and-therefore-fine.
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

# --- FAKE_STATE_RAW building blocks. Field SET + target values are
# extracted LIVE from the real script's own EVENT_FLAGS array -- never
# hand-typed here anymore (team-lead's run-19 fix directive). Run 19's
# own defect is exactly what a hand-typed pipe string can't catch:
# read_state() silently stopped printing discord_ping_enabled when
# EVENT_FLAGS was refactored, and this fence's OLD MEASURED_FLAGS/
# TARGET_FLAGS strings still carried `discord_ping_enabled=true` from
# before that refactor -- the fixture just echoed them back verbatim,
# so every scenario kept "passing" against a field set the real script
# had already stopped producing. A field the script stops printing now
# shrinks this extraction; the count guard below catches it, and the
# derived string genuinely reflects what the script emits, not what a
# comment here still claims it emits.
#
# ⚠ Sec (PR #874 review): this generation is safe ONLY because it does
# not stand alone. On its own, deriving the fence's expected answer from
# the very array the script under test defines is "the test derives
# from the thing under test" -- self-referential, no independent
# constraint on EVENT_FLAGS' actual CONTENTS (only its shape/count).
# What keeps this real: FACT-13 in scripts/COOLIFY-API-MEASURED.md
# remains an EXTERNALLY measured anchor (information_schema.columns on
# the live box, not derived from this script at all), and scenarios 26/
# 27 below assert every one of FACT-13's 16 column names against BOTH
# the script's own source and the runtime-generated write payload. If
# either the FACT-13 extraction or those two per-column loops is ever
# "simplified" away, this file quietly becomes a mirror of whatever
# EVENT_FLAGS currently says and stops catching this defect class (a
# wrong/dropped column or flag) at all -- do not remove them to reduce
# scenario count.
EVENT_FLAG_DISPLAYS=()
EVENT_FLAG_TARGETS=()
while IFS= read -r __entry; do
  __display="${__entry%%:*}"
  __target="${__entry##*:}"
  EVENT_FLAG_DISPLAYS+=("$__display")
  EVENT_FLAG_TARGETS+=("$__target")
done < <(
  awk '/^EVENT_FLAGS=\(/ { grab = 1; next } grab && /^\)/ { exit } grab' "$SCRIPT_UNDER_TEST" \
    | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*,?[[:space:]]*$//'
)
if [[ "${#EVENT_FLAG_DISPLAYS[@]}" -eq 0 ]]; then
  echo "FATAL: extracted zero entries from $SCRIPT_UNDER_TEST's own EVENT_FLAGS array -- extraction broke, or the array itself is empty/renamed" >&2
  exit 2
fi

# TARGET_FLAGS -- built directly from the extraction above, in
# EVENT_FLAGS's own order. No hand-typed target values: they come from
# the exact same array the real write's update() call reads (Sec ruling,
# PR #871 review, carried through unchanged: backup_failure targets
# `false` regardless of the box's measured `true` default; the four
# enables plus discord_ping_enabled target `true`).
target_flags_string() {
  local out="" i
  for i in "${!EVENT_FLAG_DISPLAYS[@]}"; do
    out+="${EVENT_FLAG_DISPLAYS[$i]}=${EVENT_FLAG_TARGETS[$i]}|"
  done
  printf '%s' "${out%|}"
}
TARGET_FLAGS="$(target_flags_string)"

# MEASURED_FLAGS -- the box's CURRENT/default value per flag (team-lead,
# live box, 2026-09-21 22:35Z; this script's own header cites the same
# measurement) is genuine external data this fence cannot derive from
# the script itself -- but it is looked up BY DISPLAY NAME against the
# SAME extracted list above, so a flag EVENT_FLAGS gains with no entry
# here FATALs the build rather than silently omitting it from every
# scenario (the same class of gap that let discord_ping_enabled's
# absence go unnoticed, applied to the OTHER direction of drift).
measured_default_for() {
  case "$1" in
    discord_ping_enabled) printf 'true' ;;
    deployment_success) printf 'false' ;;
    deployment_failure) printf 'true' ;;
    status_change) printf 'false' ;;
    backup_success) printf 'false' ;;
    backup_failure) printf 'true' ;;
    scheduled_task_success) printf 'false' ;;
    scheduled_task_failure) printf 'true' ;;
    docker_cleanup_success) printf 'false' ;;
    docker_cleanup_failure) printf 'true' ;;
    server_disk_usage) printf 'true' ;;
    server_reachable) printf 'false' ;;
    server_unreachable) printf 'true' ;;
    server_patch) printf 'true' ;;
    traefik_outdated) printf 'true' ;;
    restart_limit_reached) printf 'true' ;;
    *) return 1 ;;
  esac
}
measured_flags_string() {
  local out="" i display val
  for i in "${!EVENT_FLAG_DISPLAYS[@]}"; do
    display="${EVENT_FLAG_DISPLAYS[$i]}"
    val="$(measured_default_for "$display")" || {
      echo "FATAL: no measured-default entry for '$display' in this fence's measured_default_for() -- EVENT_FLAGS gained a flag this fence doesn't know the box's live default for. Add it (with a fresh measurement) before trusting this fence's scenarios again." >&2
      exit 2
    }
    out+="${display}=${val}|"
  done
  printf '%s' "${out%|}"
}
MEASURED_FLAGS="$(measured_flags_string)"

RAW_DISABLED="false|true|${MEASURED_FLAGS}"
RAW_ENABLED_URL_EMPTY="true|true|${MEASURED_FLAGS}"
RAW_ENABLED_FRESH_FLAGS="true|false|${MEASURED_FLAGS}"
RAW_ENABLED_TARGET_FLAGS="true|false|${TARGET_FLAGS}"
# TARGET_FLAGS with backup_failure left at the box's measured `true`
# default (not yet corrected by a write) -- isolates that this ONE flag
# alone still forces a write even when every other target flag + the
# hash already match (scenario 12b below).
TARGET_FLAGS_BACKUP_STALE="${TARGET_FLAGS/backup_failure=false/backup_failure=true}"
RAW_ENABLED_TARGET_FLAGS_BACKUP_STALE="true|false|${TARGET_FLAGS_BACKUP_STALE}"

# TARGET_FLAGS with backup_failure read back as a genuine DB NULL
# (`read_state()`'s own fail-closed token, Sec requirement) rather than
# the box's measured `true` default -- proves NULL is never folded into
# "false" and treated as an idempotency match against backup_failure's
# false target (scenario 30 below: forces a write) or a post-write
# success (scenario 31 below: forces a die).
TARGET_FLAGS_BACKUP_NULL="${TARGET_FLAGS/backup_failure=false/backup_failure=NULL}"
RAW_ENABLED_TARGET_FLAGS_BACKUP_NULL="true|false|${TARGET_FLAGS_BACKUP_NULL}"

# TARGET_FLAGS with discord_ping_enabled left at `false` (not yet
# corrected by a write) -- isolates that THIS ONE flag alone still
# forces a write even when every other target flag + the hash already
# match (scenario 34 below), the same rigor already applied to
# backup_failure in scenario 12b -- proves the idempotency check's
# discord_ping_enabled comparison (added in this same fix) is
# independently load-bearing, not merely riding along with the other
# four enables.
TARGET_FLAGS_PING_STALE="${TARGET_FLAGS/discord_ping_enabled=true/discord_ping_enabled=false}"
RAW_ENABLED_TARGET_FLAGS_PING_STALE="true|false|${TARGET_FLAGS_PING_STALE}"

# TARGET_FLAGS with the discord_ping_enabled SEGMENT REMOVED ENTIRELY
# (not merely wrong-valued) -- models a box read that omits the field
# altogether, the same observable shape run 19's actual defect had
# BEFORE this fix (read_state() never printed discord_ping_enabled at
# all). Used post-write only (scenario 35 below): the field-completeness
# check must FATAL naming the missing flag, not silently treat an
# absent field as false-and-therefore-fine.
TARGET_FLAGS_PING_ABSENT="${TARGET_FLAGS/|discord_ping_enabled=true/}"
RAW_ENABLED_TARGET_FLAGS_PING_ABSENT="true|false|${TARGET_FLAGS_PING_ABSENT}"

# The 16 real `discord_notification_settings` columns -- parsed LIVE out
# of COOLIFY-FACT-13's own fenced `information_schema.columns` block in
# scripts/COOLIFY-API-MEASURED.md (Sec F-2, PR #873 round 2: a SECOND
# hand-typed copy of this list is a re-transcription, not a fix, for
# the exact transcription-error class this whole PR exists to close --
# if this fence's own copy ever drifted from FACT-13 it would demand
# the WRONG names from the script and both would silently agree). Same
# "extract the pinned source live, zero retyped copies" shape QA's
# smoke-remaining-checks.sh TZ-1 leg already uses via
# check-tz-sweep-identical.py's own extract_runbook(). MEASURED_FLAGS/
# TARGET_FLAGS above stay hand-typed display-name pipe strings -- those
# model read_state()'s OWN OUTPUT FORMAT (short display names), which
# this fix deliberately did not change, not the real column vocabulary
# FACT-13 pins.
COOLIFY_API_MEASURED_MD="$REPO_ROOT/scripts/COOLIFY-API-MEASURED.md"
[[ -f "$COOLIFY_API_MEASURED_MD" ]] || { echo "FATAL: $COOLIFY_API_MEASURED_MD not found -- cannot extract FACT-13's column list" >&2; exit 2; }
# Built with a plain `while read` + `+=` append, not `mapfile` (bash-4+
# only -- this repo pins bash 3.2, same discipline scenario 24 below
# checks for the script under test).
REAL_COLUMN_NAMES=()
while IFS= read -r __col; do
  REAL_COLUMN_NAMES+=("$__col")
done < <(
  awk '
    /^## COOLIFY-FACT-13/ { infact = 1 }
    infact && /^[[:space:]]*```$/ { fence++; next }
    infact && fence == 1 { print }
    infact && fence >= 2 { exit }
  ' "$COOLIFY_API_MEASURED_MD" \
    | sed -E 's/^[[:space:]]*//' \
    | awk -F: '/_discord_notifications:boolean$/ || $0 == "discord_ping_enabled:boolean" { print $1 }'
)
if [[ "${#REAL_COLUMN_NAMES[@]}" -ne 16 ]]; then
  echo "FATAL: extracted ${#REAL_COLUMN_NAMES[@]} column names from FACT-13, expected 16 -- COOLIFY-API-MEASURED.md's FACT-13 fenced block shape changed; fix the extractor above, don't silently proceed with a wrong count." >&2
  exit 2
fi

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
POSTWRITE_COUNTER_10="$WORK/postwrite-counter.10"
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_10" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: fresh state writes, hash-binds, test-send accepted" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-fresh-write-happened"
  assert_grep "$CASE_LAST_DIR/out.txt" "OK: Discord accepted the Coolify test notification (HTTP 204)" "apply-fresh-test-send-ok"
  assert_grep "$CASE_LAST_DIR/out.txt" "DESTROYED: " "apply-fresh-destroyed-line-surfaced"
fi

# 11. APPLY-IDEMPOTENT-SKIPS-WRITE
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS" FAKE_STORED_HASH="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: already-correct state skips the write" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_not_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-idempotent-no-write"
  assert_grep "$CASE_LAST_DIR/out.txt" "OK: Discord accepted the Coolify test notification (HTTP 204)" "apply-idempotent-test-send-still-runs"
fi

# 12. APPLY-FLAGS-MISMATCH-STILL-WRITES
POSTWRITE_COUNTER_12="$WORK/postwrite-counter.12"
FAKE_STATE_RAW="$RAW_ENABLED_FRESH_FLAGS" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_12" \
  FAKE_STORED_HASH="$VALID_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: hash matches but target flags don't -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-flags-mismatch-writes"

# 12b. APPLY-BACKUP-FAILURE-STALE-STILL-WRITES (Sec ruling, PR #871
# review) -- every OTHER target flag + the hash already match, but
# backup_failure is still the box's measured `true` default (not yet
# corrected to `false`) -- isolates that this ONE flag alone still
# forces a write, proving the idempotency check's backup_failure=false
# comparison is load-bearing on its own, not merely riding along with
# the other four.
POSTWRITE_COUNTER_12B="$WORK/postwrite-counter.12b"
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS_BACKUP_STALE" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_12B" \
  FAKE_STORED_HASH="$VALID_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: hash + four target flags match, but backup_failure still true -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-backup-failure-stale-writes"

# 13. APPLY-HASH-MISMATCH-STILL-WRITES
POSTWRITE_COUNTER_13="$WORK/postwrite-counter.13"
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_13" \
  FAKE_STORED_HASH="$WRONG_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
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
POSTWRITE_COUNTER_19="$WORK/postwrite-counter.19"
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_19" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_NO_URL=1 \
  run_case "apply: test-send finds URL empty -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "read back empty immediately after a confirmed write" "apply-testsend-no-url"

# 20. APPLY-TESTSEND-UNPARSEABLE-REFUSES
POSTWRITE_COUNTER_20="$WORK/postwrite-counter.20"
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_20" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS="garbage" \
  run_case "apply: test-send output unparseable -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "did not report a parseable HTTP status" "apply-testsend-unparseable"

# 21. APPLY-TESTSEND-NON2XX-REFUSES
POSTWRITE_COUNTER_21="$WORK/postwrite-counter.21"
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_21" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=429 \
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

# 25. SHRED-TRAP-PRESENT -- the seed-delivery remote script now names a
# report_shred_seed() function (execution-record standard, PR #870)
# rather than inlining `shred -u` directly in a trap line -- pin (a) the
# function body contains `shred -u`, (b) `trap report_shred_seed EXIT`
# is wired standalone, and (c) HUP/INT/TERM disarm EXIT before
# re-invoking it (the PR #870 double-fire fix), so a future edit that
# recombines the two traps or drops the shred is caught.
if grep -qE 'report_shred_seed\(\)[[:space:]]*\{' "$SCRIPT_UNDER_TEST" \
  && awk '/report_shred_seed\(\)[[:space:]]*\{/,/^\}/' "$SCRIPT_UNDER_TEST" | grep -qF 'shred -u'; then
  echo "OK: [shred-trap-present] report_shred_seed() is defined and contains 'shred -u'." >&2
else
  echo "FAIL: [shred-trap-present] report_shred_seed() missing, or does not contain 'shred -u' -- the seed file's shred-on-any-exit guarantee may have regressed" >&2
  FAIL=1
fi
if grep -qE "^trap report_shred_seed EXIT\$" "$SCRIPT_UNDER_TEST"; then
  echo "OK: [shred-trap-present] 'trap report_shred_seed EXIT' is wired standalone." >&2
else
  echo "FAIL: [shred-trap-present] no standalone 'trap report_shred_seed EXIT' found" >&2
  FAIL=1
fi
if grep -qE "trap 'trap - EXIT; report_shred_seed;[^']*'[[:space:]]+HUP INT TERM" "$SCRIPT_UNDER_TEST"; then
  echo "OK: [shred-trap-present] HUP/INT/TERM disarms EXIT before re-invoking report_shred_seed (PR #870 double-fire fix intact)." >&2
else
  echo "FAIL: [shred-trap-present] HUP/INT/TERM trap does not disarm EXIT first -- the PR #870 double-fire defect may have regressed" >&2
  FAIL=1
fi

# 26. COLUMN-NAMES-PINNED-IN-SOURCE (FACT-13)
for col in "${REAL_COLUMN_NAMES[@]}"; do
  assert_grep "$SCRIPT_UNDER_TEST" "$col" "column-names-pinned-in-source:$col"
done

# 27. COLUMN-NAMES-IN-GENERATED-PAYLOAD -- reuses a fresh fresh-write
# scenario, capturing the ACTUAL runtime-generated remote-script body
# (php_update_fields()/php_field_map() output spliced in) rather than
# the static source, so a generator bug that produces wrong text even
# though the source table (EVENT_FLAGS) is correct would still be caught.
PAYLOAD_LOG="$WORK/write-payload.27"
POSTWRITE_COUNTER_27="$WORK/postwrite-counter.27"
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_27" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 FAKE_WRITE_PAYLOAD_LOG="$PAYLOAD_LOG" \
  run_case "apply: generated write payload carries every real column name" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -f "$PAYLOAD_LOG" ]]; then
  for col in "${REAL_COLUMN_NAMES[@]}"; do
    assert_grep "$PAYLOAD_LOG" "$col" "column-names-in-generated-payload:$col"
  done
else
  echo "FAIL: [column-names-in-generated-payload] $PAYLOAD_LOG was never written -- the write call did not happen as expected" >&2
  FAIL=1
fi

# 28. APPLY-SHORT-COLUMN-REGRESSION-FAILS -- models a hypothetical
# regression to short column names via Eloquent's own silent-drop
# behaviour (WRITE_OK still prints; the post-write re-read comes back
# UNCHANGED from the pre-write read, since FAKE_STATE_RAW_POSTWRITE is
# deliberately left unset here) -- the real script's own NEW post-write
# flag-readback check must refuse, not report false success.
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_SIMULATE_SHORT_COLUMN_NAMES=1 \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: post-write flags read back unchanged (simulated column-name regression) -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "post-write flag readback does not match the intended targets" "apply-short-column-regression-fails"

# 29. APPLY-WRITE-NO-DESTROYED-LINE-REFUSES
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_WRITE_NO_DESTROYED_LINE=1 \
  run_case "apply: WRITE_OK with no DESTROYED confirmation -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "printed no seed-destruction confirmation" "apply-write-no-destroyed-line"

# 30. APPLY-NULL-FLAG-FORCES-WRITE -- backup_failure NULL, hash + every
# other target flag already match -> write still happens (NULL != the
# false target -- fail closed, never an idempotency match).
POSTWRITE_COUNTER_30="$WORK/postwrite-counter.30"
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS_BACKUP_NULL" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_30" \
  FAKE_STORED_HASH="$VALID_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: hash + other flags match, but backup_failure reads NULL -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-null-flag-forces-write"

# 31. APPLY-POSTWRITE-NULL-FLAG-FAILS -- backup_failure reads back NULL
# even AFTER the write (the column never actually landed) -> the
# post-write flag-readback check must refuse, not accept NULL as
# close-enough to the false target.
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS_BACKUP_NULL" FAKE_STATE_CALL_COUNTER="$WORK/postwrite-counter.31" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: post-write backup_failure still NULL -- refuses" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "post-write flag readback does not match the intended targets" "apply-postwrite-null-flag-fails"

# 32. STATE-UNKNOWN-COLUMN -- backup_failure_discord_notifications (a
# TARGET-FALSE flag, Sec's own specific instruction -- a target-true
# flag would already refuse via the plain true/false comparison,
# masking whether this NEW array_key_exists() guard actually fired).
FAKE_STATE_RAW="FATAL_UNKNOWN_COLUMN_backup_failure_discord_notifications" \
  run_case "state: unknown column (target-false flag) refuses" 1 state "" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/out.txt" "backup_failure_discord_notifications" "state-unknown-column-names-it"

# 33. APPLY-UNKNOWN-COLUMN-REFUSES-BEFORE-WRITE -- same FATAL, via
# --apply's own pre-write idempotency read -> refuses, and the box is
# never asked to write (ssh.log carries no write call at all).
FAKE_STATE_RAW="FATAL_UNKNOWN_COLUMN_backup_failure_discord_notifications" \
  run_case "apply: unknown column on pre-write read -- refuses before any write" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "backup_failure_discord_notifications" "apply-unknown-column-names-it"
  assert_not_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-unknown-column-no-write-attempted"
fi

# 34. APPLY-PING-STALE-STILL-WRITES (run 19 fix)
POSTWRITE_COUNTER_34="$WORK/postwrite-counter.34"
FAKE_STATE_RAW="$RAW_ENABLED_TARGET_FLAGS_PING_STALE" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS" FAKE_STATE_CALL_COUNTER="$POSTWRITE_COUNTER_34" \
  FAKE_STORED_HASH="$VALID_HASH" FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: hash + every other flag match, but discord_ping_enabled still false -- writes anyway" 0 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
[[ -n "$CASE_LAST_DIR" ]] && assert_grep "$CASE_LAST_DIR/ssh.log" "env SEED_ENV_FILE=" "apply-ping-stale-writes"

# 35. APPLY-POSTWRITE-PING-ABSENT-FAILS
FAKE_STATE_RAW="$RAW_DISABLED" FAKE_STATE_RAW_POSTWRITE="$RAW_ENABLED_TARGET_FLAGS_PING_ABSENT" FAKE_STATE_CALL_COUNTER="$WORK/postwrite-counter.35" \
  FAKE_STORED_HASH_AFTER="$VALID_HASH" FAKE_TEST_STATUS=204 \
  run_case "apply: post-write answer omits discord_ping_enabled entirely -- refuses, names it" 1 apply "DISCORD_WEBHOOK_URL=$VALID_URL" || true
if [[ -n "$CASE_LAST_DIR" ]]; then
  assert_grep "$CASE_LAST_DIR/out.txt" "post-write flag readback does not match the intended targets" "apply-postwrite-ping-absent-fails"
  assert_grep "$CASE_LAST_DIR/out.txt" "discord_ping_enabled(expected=true,got=<unset>)" "apply-postwrite-ping-absent-names-it"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "" >&2
  echo "FAIL: one or more coolify-discord-notify.sh strike-proof scenarios did not behave as specified." >&2
  exit 1
fi

echo "OK: all coolify-discord-notify.sh strike-proofs passed."
exit 0
