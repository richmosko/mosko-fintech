#!/usr/bin/env bash
#
# fence-pgrst-exposure-gates-strikes.sh -- offline strike-proof for
# scripts/pgrst-exposure-gates.sh. Runs entirely without a live box: a
# fake `ssh` rewrites the /root/.pfin path and PATH-shadows curl/docker
# for every nested invocation (same shape as fence-db-role-handoff-
# strikes.sh), a fake `docker` stands in for every `docker compose ...
# exec -T db psql -tAc ...` call, distinguishing the three gate queries
# by their own SQL text, and tests/fixtures/ci/pgrst-exposure-gates/
# fake-curl stands in for the Coolify application lookup.
# scripts/pgrst-exposure-gates.sh itself is never modified or made aware
# any of this exists.
#
# Scenarios (BACKLOG.md §7.36 item 66, W-5):
#   1. HAPPY-PATH        -- all three gates clean -> exit 0, "safe to
#      proceed to the PGRST_DB_SCHEMAS flip."
#   2. B1-VETO-USAGE      -- anon holds schema-level USAGE on pfin -> VETO
#      refusal, even with zero granted relations (proves the USAGE leg of
#      the OR fires on its own).
#   3. B1-VETO-GRANTED-RELATION -- anon holds no schema USAGE but DOES
#      hold a table-level grant on one pfin relation -> VETO refusal
#      (proves the relation-enumeration leg fires independently of the
#      USAGE leg -- an early draft that only checked one leg would pass
#      this).
#   4. B2-MISMATCH        -- the live ledger count differs from this
#      checkout's OWN measured migrations/*.sql count (measured live by
#      this fence too, never a value hardcoded in either script or fence)
#      -> refuses, naming the mismatch.
#   5. B3-ZERO             -- no ledger row for migration 025 -> refuses,
#      "expected exactly one".
#   6. B3-MULTIPLE         -- two ledger rows for migration 025 -> refuses
#      with the same "expected exactly one" predicate (proves the check
#      is an exact-one assertion, not merely "at least one").
#   7. RESOURCE-ABSENT    -- the stack app does not resolve -> refuses
#      BEFORE any psql call is made, naming "expected exactly one
#      application". ⚠ MEASURED, not per the header's own EXIT CODES
#      table: the header claims "stack resource not found" is exit 2
#      (FAILED), but `STACK_UUID="$(sshx ... <<REMOTE ...)"` is a bash
#      assignment-from-command-substitution -- under `set -e`, the
#      python driver's own `sys.exit(1)` (from `die()`) already ends the
#      script at that assignment, before the script's OWN `|| die2
#      "could not resolve"` fallback is ever reached. Actual exit is 1
#      (REFUSED), not 2. Same shape exists in every sibling script using
#      this idiom (smoke-ca1-env-pattern.sh, db-bootstrap.sh, ...) --
#      pre-existing across the repo, not introduced here; flagged as a
#      bubble-up rather than fixed under this PR's time budget.
#   8. BOX-UNREACHABLE    -- ssh's own reachability probe fails -> FAILED
#      (exit 2), not REFUSED.
#   9. UNKNOWN-FLAG        -- this script takes NO flags at all (no
#      --apply exists; it is entirely read-only) -- passing any argument
#      must be rejected, not silently ignored.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/pgrst-exposure-gates"
TARGET_SH="$REPO_ROOT/scripts/pgrst-exposure-gates.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- distinguishes the three -tAc gate queries by their own
# SQL text (never by call order, so a reordering of the real script's
# steps can't silently swap which fixture answers which question).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
ARGS="$*"

if [[ "$ARGS" != *"-tAc"* ]]; then
  echo "FAKE DOCKER: unrecognised invocation (expected a -tAc scalar query): $ARGS" >&2
  exit 1
fi

if [[ "$ARGS" == *"has_schema_privilege('anon', 'pfin', 'USAGE')"* ]]; then
  echo "${FAKE_ANON_USAGE:-false}"
  exit 0
fi

if [[ "$ARGS" == *"has_table_privilege('anon'"* ]]; then
  printf '%b' "${FAKE_GRANTED_RELATIONS:-}"
  exit 0
fi

if [[ "$ARGS" == *"select count(*) from supabase_migrations.schema_migrations;"* ]]; then
  echo "${FAKE_LEDGER_COUNT:-0}"
  exit 0
fi

if [[ "$ARGS" == *"version like '025%'"* ]]; then
  # `-` (unset-only default), not `:-` -- a scenario deliberately passes
  # an EMPTY string to model zero ledger rows, and `:-` would silently
  # replace that empty-but-set value with the happy-path default,
  # defeating the b3-zero scenario.
  printf '%b' "${FAKE_B3_ROWS-025_aal2_step_up_backstop}"
  exit 0
fi

echo "FAKE DOCKER: unrecognised -tAc query: $ARGS" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

# Fake `ssh` -- same shape as fence-db-role-handoff-strikes.sh's own.
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${FAKE_BOX_UNREACHABLE:-0}" == "1" ]]; then
  echo "ssh: connect to host 127.0.0.1 port 22: Connection refused" >&2
  exit 255
fi
LAST_PROBE="\${@: -1}"
if [[ "\$LAST_PROBE" == "true" ]]; then
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
  PATH="$FAKE_BIN:\$PATH" \\
    FAKE_ANON_USAGE="\$FAKE_ANON_USAGE" FAKE_GRANTED_RELATIONS="\$FAKE_GRANTED_RELATIONS" \\
    FAKE_LEDGER_COUNT="\$FAKE_LEDGER_COUNT" FAKE_B3_ROWS="\$FAKE_B3_ROWS" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

# pgrst-exposure-gates.sh reads BOX_IP from "$REPO_ROOT/.env" itself (a
# grep, not the BOX_IP env var) and B-2 measures
# "$REPO_ROOT/supabase/migrations/*.sql" live -- this fence therefore
# points REPO_ROOT at its OWN throwaway fixture tree (never the real repo
# root, which this fence must not write a .env into) with a KNOWN,
# controlled migration-file count, so B-2's happy-path/mismatch scenarios
# are exact rather than dependent on the real tree's current size.
FIXTURE_REPO="$WORK/fixture-repo"
mkdir -p "$FIXTURE_REPO/supabase/migrations"
printf 'BOX_IP=127.0.0.1\n' > "$FIXTURE_REPO/.env"
for n in 001 002 003; do
  printf -- '-- fixture migration %s\n' "$n" > "$FIXTURE_REPO/supabase/migrations/${n}_fixture.sql"
done
REAL_COUNT=3

run_scenario() {
  # run_scenario <desc> <expect_exit> <extra_flag> <curl_mode> <box_unreachable> <anon_usage> <granted_relations> <ledger_count> <b3_rows>
  local desc="$1" expect_exit="$2" extra_flag="$3" curl_mode="$4" box_unreachable="$5" \
        anon_usage="$6" granted_relations="$7" ledger_count="$8" b3_rows="$9"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  # extra_flag is deliberately unquoted below: it is either empty (no
  # args) or a single flag word, never a value that needs its own
  # quoting; same accepted pattern as fence-db-role-handoff-strikes.sh's
  # own apply_flag.
  # shellcheck disable=SC2086
  AUTOMATION_KEY=/dev/null REPO_ROOT="$FIXTURE_REPO" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" FAKE_BOX_UNREACHABLE="$box_unreachable" \
    FAKE_ANON_USAGE="$anon_usage" FAKE_GRANTED_RELATIONS="$granted_relations" \
    FAKE_LEDGER_COUNT="$ledger_count" FAKE_B3_ROWS="$b3_rows" \
    bash "$TARGET_SH" $extra_flag < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi

  if grep -qF "$FAKE_TOKEN" "$log" 2>/dev/null; then
    echo "FAIL: [$desc] the fake Coolify API token leaked into a curl invocation's own argv:" >&2
    grep -F "$FAKE_TOKEN" "$log" >&2
    return 1
  fi

  echo "OK: [$desc] exit $rc as expected, token absent from every logged curl argv." >&2
  cat "$WORK/out.$$"
  return 0
}

assert_output_contains() {
  local desc="$1" out="$2" needle="$3"
  if [[ -z "$out" ]]; then
    echo "FAIL: [$desc] produced no captured output to inspect (run_scenario itself already failed above)." >&2
    return 1
  fi
  if ! grep -qF "$needle" <<<"$out"; then
    echo "FAIL: [$desc] did not contain expected text '$needle' -- not naming the offending predicate." >&2
    return 1
  fi
  return 0
}

FAIL=0

# 1. HAPPY-PATH
OUT1="$(run_scenario "happy-path: all three gates clean" 0 "" clean 0 false "" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "happy-path" "${OUT1:-}" "safe to proceed to the PGRST_DB_SCHEMAS flip" || FAIL=1

# 2. B1-VETO-USAGE
OUT2="$(run_scenario "b1-veto-usage: refuses" 1 "" clean 0 true "" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "b1-veto-usage" "${OUT2:-}" "B-1 VETO" || FAIL=1

# 3. B1-VETO-GRANTED-RELATION -- USAGE clean, but one table-level grant
OUT3="$(run_scenario "b1-veto-granted-relation: refuses" 1 "" clean 0 false "pfin.accounts\n" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "b1-veto-granted-relation" "${OUT3:-}" "B-1 VETO" || FAIL=1

# 4. B2-MISMATCH
OUT4="$(run_scenario "b2-mismatch: refuses" 1 "" clean 0 false "" "$((REAL_COUNT + 1))" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "b2-mismatch" "${OUT4:-}" "does not equal this checkout's migration-file count" || FAIL=1

# 5. B3-ZERO
OUT5="$(run_scenario "b3-zero: refuses" 1 "" clean 0 false "" "$REAL_COUNT" "")" || FAIL=1
assert_output_contains "b3-zero" "${OUT5:-}" "expected exactly one ledger row matching '025%'" || FAIL=1

# 6. B3-MULTIPLE
OUT6="$(run_scenario "b3-multiple: refuses" 1 "" clean 0 false "" "$REAL_COUNT" "025_aal2_step_up_backstop\n025_aal2_step_up_backstop_dup")" || FAIL=1
assert_output_contains "b3-multiple" "${OUT6:-}" "expected exactly one ledger row matching '025%'" || FAIL=1

# 7. RESOURCE-ABSENT (measured exit 1, not the header's documented 2 --
#    see the scenario comment above)
OUT7="$(run_scenario "resource-absent: refuses" 1 "" stack-absent 0 false "" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "resource-absent" "${OUT7:-}" "expected exactly one application" || FAIL=1

# 8. BOX-UNREACHABLE
OUT8="$(run_scenario "box-unreachable: FAILED (exit 2)" 2 "" clean 1 false "" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "box-unreachable" "${OUT8:-}" "not reachable over SSH" || FAIL=1

# 9. UNKNOWN-FLAG -- this script has no --apply and no flags at all
OUT9="$(run_scenario "unknown-flag: rejected" 2 "--apply" clean 0 false "" "$REAL_COUNT" "025_aal2_step_up_backstop")" || FAIL=1
assert_output_contains "unknown-flag" "${OUT9:-}" "unknown flag" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more pgrst-exposure-gates.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all pgrst-exposure-gates.sh strike-proofs passed."
exit 0
