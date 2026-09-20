#!/usr/bin/env bash
#
# fence-smoke-admission-endpoint-strikes.sh -- offline strike-proof for
# scripts/smoke-admission-endpoint.sh (CA-2 negative + positive controls,
# docs/deployment-runbook.md §10). Runs entirely without a live box: a
# fake `ssh` rewrites the `/root/.pfin` path the script's remote driver
# hardcodes, then runs it locally with
# tests/fixtures/ci/smoke-admission-endpoint/fake-curl and fake-docker
# standing in for the real thing -- scripts/smoke-admission-endpoint.sh
# itself is never modified or made aware this exists. Same strike shape
# as scripts/ci/fence-smoke-pfin-exposure-strikes.sh.
#
# Scenarios (BACKLOG.md §7.36 item 68, W-3):
#   1. HAPPY-PATH -- N1/N2 both 000, no fqdn, P1=200/P2=401/P3=400,
#      secret present -> exit 0.
#   2. N1-EXPOSED -- the operator-machine probe gets a real HTTP response
#      (not 000) -> refuses (a real exposure, not a known-failure shape).
#   3. N2-EXPOSED -- the box-host probe gets a real HTTP response ->
#      refuses.
#   4. DOMAIN-ASSIGNED -- provider-sync carries a live fqdn -> refuses.
#   5. P1-WRONG -- healthz does not return 200 from a sibling container ->
#      refuses (CA-4 network-attachment failure shape).
#   6. P2-WRONG -- the no-secret request does not 401 -> refuses (auth
#      gate not failing closed).
#   7. P3-WRONG -- the with-secret request does not 400 -> refuses.
#   8. SECRET-ABSENT -- the sibling container's own env lacks
#      WORKER_ADMISSION_SHARED_SECRET -> refuses (P3's assertion would be
#      meaningless without it).
#   9. AMBIGUOUS -- 2 running containers match the sibling's compose
#      service -> refuses, never silently picking one (Sec F4 discipline,
#      same class as every sibling smoke/deploy script).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-admission-endpoint"
SMOKE_SH="$REPO_ROOT/scripts/smoke-admission-endpoint.sh"

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

# Same fake `ssh` shape as the sibling strike fences. The PLAIN-COMMAND
# branch (used for the N2 box-host curl probe AND the docker
# compose/inspect/exec pipeline) sets FAKE_SSH_CONTEXT=1 so fake-curl can
# tell "the operator's own direct N1 probe" (never touches this branch)
# apart from "a probe issued from inside a remote sshx call" (N2) --
# EVERY command that reaches this branch is, from the real script's
# perspective, running ON THE BOX.
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
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_PS_NAME="\${FAKE_PS_NAME:-}" \\
    FAKE_SIBLING_NAME="\${FAKE_SIBLING_NAME:-}" FAKE_FQDN="\${FAKE_FQDN:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_SSH_CONTEXT=1 FAKE_N2_CODE="\${FAKE_N2_CODE:-}" \\
  FAKE_CONTAINERS="\${FAKE_CONTAINERS:-}" FAKE_P1="\${FAKE_P1:-}" FAKE_P2="\${FAKE_P2:-}" FAKE_P3="\${FAKE_P3:-}" \\
  FAKE_SECRET_STATE="\${FAKE_SECRET_STATE:-}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <n1> <n2> <fqdn> <p1> <p2> <p3> <secret_state> <containers>
  local desc="$1" expect_exit="$2" n1="$3" n2="$4" fqdn="$5" p1="$6" p2="$7" p3="$8" secret_state="$9" containers="${10}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" \
    FAKE_N1_CODE="$n1" FAKE_N2_CODE="$n2" FAKE_FQDN="$fqdn" \
    FAKE_P1="$p1" FAKE_P2="$p2" FAKE_P3="$p3" FAKE_SECRET_STATE="$secret_state" \
    FAKE_CONTAINERS="$containers" \
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

# 1. HAPPY-PATH
run_scenario "happy-path" 0 000 000 "" 200 401 400 SECRET_PRESENT 1 || FAIL=1

# 2. N1-EXPOSED
run_scenario "N1 exposed: refuses" 1 200 000 "" 200 401 400 SECRET_PRESENT 1 || FAIL=1

# 3. N2-EXPOSED
run_scenario "N2 exposed: refuses" 1 000 200 "" 200 401 400 SECRET_PRESENT 1 || FAIL=1

# 4. DOMAIN-ASSIGNED
run_scenario "Domain assigned: refuses" 1 000 000 "psuuid00.1.2.3.4.sslip.io" 200 401 400 SECRET_PRESENT 1 || FAIL=1

# 5. P1-WRONG
run_scenario "P1 (healthz) wrong: refuses" 1 000 000 "" 502 401 400 SECRET_PRESENT 1 || FAIL=1

# 6. P2-WRONG
run_scenario "P2 (no-secret) wrong: refuses" 1 000 000 "" 200 200 400 SECRET_PRESENT 1 || FAIL=1

# 7. P3-WRONG
run_scenario "P3 (with-secret) wrong: refuses" 1 000 000 "" 200 401 401 SECRET_PRESENT 1 || FAIL=1

# 8. SECRET-ABSENT
run_scenario "secret absent on sibling: refuses" 1 000 000 "" 200 401 400 SECRET_ABSENT 1 || FAIL=1

# 9. AMBIGUOUS
run_scenario "ambiguous: 2 running containers refuses" 1 000 000 "" 200 401 400 SECRET_PRESENT 2 || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-admission-endpoint.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-admission-endpoint.sh strike-proofs passed."
exit 0
