#!/usr/bin/env bash
#
# fence-smoke-ca1-env-pattern-strikes.sh -- offline strike-proof for
# scripts/smoke-ca1-env-pattern.sh. Runs entirely without a live box: a
# fake `ssh` rewrites /root/.pfin and PATH-shadows curl/docker for every
# nested invocation (same shape as fence-db-role-handoff-strikes.sh /
# fence-pgrst-exposure-gates-strikes.sh), a fake `docker` stands in for
# the compose ps / inspect / exec-env / exec-node calls, and
# tests/fixtures/ci/smoke-ca1-env-pattern/fake-curl stands in for the
# Coolify application lookup. scripts/smoke-ca1-env-pattern.sh itself is
# never modified or made aware any of this exists.
#
# Scenarios (BACKLOG.md §7.36 item 79, W-5; Sec F-7 corrected the AC's
# inversion mid-session -- this fence proves the CORRECTED direction):
#   1. HAPPY-PATH          -- every pinned route-signal name that IS
#      injected is matched by a pattern -> exit 0, "no pattern gap
#      found".
#   2. UNMATCHED-FINDING (THE inversion this script exists to catch) --
#      one pinned name IS injected but matched by NO pattern -> refuses,
#      naming "the exact inversion this check exists to catch" and the
#      offending name.
#   3. NONE-INJECTED (Subject B, benign) -- none of the pinned reference
#      names are actually injected on this deploy -> exit 0, "nothing to
#      cross-check" -- proves a benign zero-match is NOT reported as a
#      finding (the inverted, pre-fix AC would have treated this as the
#      failure case).
#   4. AMBIGUOUS-CONTAINERS -- two running containers match the compose
#      service -> refuses, "AMBIGUOUS".
#   5. NO-RUNNING-CONTAINER -- zero running containers -> FAILED (exit
#      2), "no running container found".
#   6. RESOURCE-ABSENT     -- the provider-sync app does not resolve ->
#      refuses. ⚠ MEASURED exit 1, not the header's documented 2 -- same
#      `set -e`-on-assignment shape as fence-pgrst-exposure-gates-
#      strikes.sh's own resource-absent finding (pre-existing across the
#      repo, flagged there, not re-litigated here).
#   7. NODE-IMPORT-FAILED  -- the container's own dynamic import() fails
#      (e.g. the compiled path moved) -> FAILED (exit 2), "Node
#      cross-check itself failed".
#   8. BOX-IP-MISSING      -- BOX_IP unset (this script takes it directly
#      from the env, unlike pgrst-exposure-gates.sh's .env-file read) ->
#      FAILED (exit 2), "BOX_IP is required, not defaulted".
#   9. BOX-UNREACHABLE     -- ssh's own reachability probe fails ->
#      FAILED (exit 2).
#  10. UNKNOWN-FLAG         -- an unrecognised argument (Sec F-3, PR #849
#      review -- previously silently ignored via `*) : ;;`; every sibling
#      script exits 2) -> FAILED (exit 2), "unknown flag".
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- Sec F-3 (PR #849
# review): the target script's own pinned ROUTE_SIGNAL_REFERENCE list is
# DERIVED FROM the same PUBLIC_ROUTE_ENV_MATCHERS families it is checked
# against, so scenario 2's "unmatched finding" is only reachable here
# because this fence's fake docker is TOLD which names to report
# unmatched (FAKE_UNMATCHED_NAMES) -- it proves the SCRIPT's own control
# flow correctly refuses when told of an inversion, never that the
# pinned list reflects a real Coolify deploy's actual env surface (it
# cannot, offline). BACKLOG §7.36 item 80 books the live measurement that
# would close that gap; this fence is unaffected by it either way, since
# it never touches the real pinned list's content, only the script's
# reaction to whatever names claim to be unmatched.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-ca1-env-pattern"
TARGET_SH="$REPO_ROOT/scripts/smoke-ca1-env-pattern.sh"

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

# Fake `docker` -- four distinct call shapes, distinguished by argv
# content: `compose ... ps -q <service>` (running-container id list),
# `inspect --format ...` (per-id running/created probe), `exec <cid> env`
# (injected-name enumeration), `exec <cid> node -e ...` (the pinned-name
# cross-check against the container's own compiled matcher set).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
ARGS="$*"

if [[ "$ARGS" == *"compose"* && "$ARGS" == *"ps -q"* ]]; then
  printf '%b' "${FAKE_PS_IDS:-fakecid1}"
  exit 0
fi

if [[ "$ARGS" == *"inspect"* && "$ARGS" == *"--format"* ]]; then
  # Real command: `docker inspect --format '{{.State.Running}}\t{{.Id}}\t{{.Created}}' <id>`.
  CID="${@: -1}"
  RUNNING="${FAKE_RUNNING:-true}"
  printf '%s\t%s\t2026-09-20T00:00:00Z\n' "$RUNNING" "$CID"
  exit 0
fi

if [[ "$ARGS" == *"exec"* && "$ARGS" == *"node -e"* ]]; then
  if [[ "${FAKE_NODE_IMPORT_FAIL:-0}" == "1" ]]; then
    echo "IMPORT_FAILED: Cannot find module '/app/dist/http/admissionGuard.js'" >&2
    exit 2
  fi
  for name in SERVICE_FQDN_APP SERVICE_URL_APP COOLIFY_URL COOLIFY_FQDN ADMISSION_PUBLIC_URL; do
    case " $ARGS " in
      *" $name "*)
        if [[ " ${FAKE_UNMATCHED_NAMES:-} " == *" $name "* ]]; then
          printf '%s\t0\n' "$name"
        else
          printf '%s\t1\n' "$name"
        fi
        ;;
    esac
  done
  exit 0
fi

if [[ "$ARGS" == *"exec"* ]]; then
  # `docker exec <cid> env` -- injected-name enumeration, piped through
  # `cut -d= -f1` by the caller, so a bare NAME=value line is enough.
  for name in ${FAKE_INJECTED_NAMES:-SERVICE_FQDN_APP COOLIFY_URL SOME_OTHER_VAR}; do
    printf '%s=x\n' "$name"
  done
  exit 0
fi

echo "FAKE DOCKER: unrecognised invocation: $ARGS" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

# Fake `ssh` -- same shape as the sibling fences' own.
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
    FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" \\
  FAKE_PS_IDS="\$FAKE_PS_IDS" FAKE_RUNNING="\$FAKE_RUNNING" FAKE_INJECTED_NAMES="\$FAKE_INJECTED_NAMES" \\
  FAKE_UNMATCHED_NAMES="\$FAKE_UNMATCHED_NAMES" FAKE_NODE_IMPORT_FAIL="\$FAKE_NODE_IMPORT_FAIL" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <box_ip> <curl_mode> <box_unreachable> <ps_ids> <running> <injected_names> <unmatched_names> <node_import_fail> [extra_flag]
  local desc="$1" expect_exit="$2" box_ip="$3" curl_mode="$4" box_unreachable="$5" \
        ps_ids="$6" running="$7" injected_names="$8" unmatched_names="$9" node_import_fail="${10}" extra_flag="${11:-}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  # shellcheck disable=SC2086
  BOX_IP="$box_ip" AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" FAKE_BOX_UNREACHABLE="$box_unreachable" \
    FAKE_PS_IDS="$ps_ids" FAKE_RUNNING="$running" FAKE_INJECTED_NAMES="$injected_names" \
    FAKE_UNMATCHED_NAMES="$unmatched_names" FAKE_NODE_IMPORT_FAIL="$node_import_fail" \
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

# 1. HAPPY-PATH -- all 5 pinned names injected, all matched
ALL5="SERVICE_FQDN_APP SERVICE_URL_APP COOLIFY_URL COOLIFY_FQDN ADMISSION_PUBLIC_URL"
OUT1="$(run_scenario "happy-path: all injected, all matched" 0 127.0.0.1 clean 0 fakecid1 true "$ALL5" "" 0)" || FAIL=1
assert_output_contains "happy-path" "${OUT1:-}" "no pattern gap found" || FAIL=1

# 2. UNMATCHED-FINDING -- one injected pinned name, matched by nothing
OUT2="$(run_scenario "unmatched-finding: refuses (the inversion)" 1 127.0.0.1 clean 0 fakecid1 true "$ALL5" "COOLIFY_FQDN" 0)" || FAIL=1
assert_output_contains "unmatched-finding" "${OUT2:-}" "the exact inversion this check exists to catch" || FAIL=1
assert_output_contains "unmatched-finding" "${OUT2:-}" "COOLIFY_FQDN" || FAIL=1

# 3. NONE-INJECTED -- Subject B, benign
OUT3="$(run_scenario "none-injected: trivially clean" 0 127.0.0.1 clean 0 fakecid1 true "SOME_UNRELATED_VAR" "" 0)" || FAIL=1
assert_output_contains "none-injected" "${OUT3:-}" "nothing to cross-check" || FAIL=1

# 4. AMBIGUOUS-CONTAINERS -- two running containers
OUT4="$(run_scenario "ambiguous-containers: refuses" 1 127.0.0.1 clean 0 "fakecid1\nfakecid2" true "$ALL5" "" 0)" || FAIL=1
assert_output_contains "ambiguous-containers" "${OUT4:-}" "AMBIGUOUS" || FAIL=1

# 5. NO-RUNNING-CONTAINER
OUT5="$(run_scenario "no-running-container: FAILED (exit 2)" 2 127.0.0.1 clean 0 fakecid1 false "$ALL5" "" 0)" || FAIL=1
assert_output_contains "no-running-container" "${OUT5:-}" "no running container found" || FAIL=1

# 6. RESOURCE-ABSENT (measured exit 1, not the header's documented 2 --
#    same `set -e`-on-assignment shape as fence-pgrst-exposure-gates-
#    strikes.sh's own finding)
OUT6="$(run_scenario "resource-absent: refuses" 1 127.0.0.1 resource-absent 0 fakecid1 true "$ALL5" "" 0)" || FAIL=1
assert_output_contains "resource-absent" "${OUT6:-}" "expected exactly one application matching" || FAIL=1

# 7. NODE-IMPORT-FAILED
OUT7="$(run_scenario "node-import-failed: FAILED (exit 2)" 2 127.0.0.1 clean 0 fakecid1 true "$ALL5" "" 1)" || FAIL=1
assert_output_contains "node-import-failed" "${OUT7:-}" "Node cross-check itself failed" || FAIL=1

# 8. BOX-IP-MISSING
OUT8="$(run_scenario "box-ip-missing: FAILED (exit 2)" 2 "" clean 0 fakecid1 true "$ALL5" "" 0)" || FAIL=1
assert_output_contains "box-ip-missing" "${OUT8:-}" "BOX_IP is required, not defaulted" || FAIL=1

# 9. BOX-UNREACHABLE
OUT9="$(run_scenario "box-unreachable: FAILED (exit 2)" 2 127.0.0.1 clean 1 fakecid1 true "$ALL5" "" 0)" || FAIL=1
assert_output_contains "box-unreachable" "${OUT9:-}" "not reachable over SSH" || FAIL=1

# 10. UNKNOWN-FLAG (Sec F-3, PR #849 review -- was previously silently
#     ignored via `*) : ;;`; every sibling script exits 2)
OUT10="$(run_scenario "unknown-flag: rejected" 2 127.0.0.1 clean 0 fakecid1 true "$ALL5" "" 0 --bogus)" || FAIL=1
assert_output_contains "unknown-flag" "${OUT10:-}" "unknown flag" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-ca1-env-pattern.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-ca1-env-pattern.sh strike-proofs passed."
exit 0
