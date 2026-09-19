#!/usr/bin/env bash
#
# fence-smoke-pfin-exposure-strikes.sh -- offline strike-proof for
# scripts/smoke-pfin-exposure.sh's mode classification. Runs entirely
# without a live box: a fake `ssh` rewrites the `/root/.pfin` path the
# script's remote driver hardcodes, then runs it locally with
# tests/fixtures/ci/smoke-pfin-exposure/fake-curl (app resolution) and
# fake-docker (the smoke request's canned output) standing in for the
# real thing -- scripts/smoke-pfin-exposure.sh itself is never modified
# or made aware this exists. Same strike shape as
# scripts/ci/fence-coolify-env-strikes.sh / fence-deploy-app-strikes.sh.
#
# Proves the asymmetric-mode claim scripts/smoke-pfin-exposure.sh's own
# header makes: the two modes (anon-bearer default vs. --jwt) do NOT
# accept each other's success shape.
#   1. anon-pass       (401/42501, no --jwt)        -> exit 0
#   2. anon-fail-200   (200, no --jwt)               -> exit 1 (security
#      anomaly, NOT a pass just because it superficially "succeeded")
#   3. anon-fail-pgrst106 (406/PGRST106, no --jwt)   -> exit 1
#   4. anon-fail-3f000 (401/3F000, no --jwt)         -> exit 1
#   5. jwt-pass        (200, --jwt given)            -> exit 0
#   6. jwt-fail         (401/42501, --jwt given)      -> exit 1 (a 401 that
#      would PASS in anon mode must NOT pass in jwt mode)
#
# Exit 0 only if all six scenarios behave exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-pfin-exposure"
SMOKE_SH="$REPO_ROOT/scripts/smoke-pfin-exposure.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-docker" ]] || { echo "FATAL: $FIXTURE_DIR/fake-docker missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"
ln -s "$FIXTURE_DIR/fake-docker" "$FAKE_BIN/docker"

# Same fake `ssh` shape as the sibling strike fences.
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
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_DOCKER_MODE="\$FAKE_DOCKER_MODE" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_DOCKER_MODE="\$FAKE_DOCKER_MODE" bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  local desc="$1" expect_exit="$2" docker_mode="$3"; shift 3
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_DOCKER_MODE="$docker_mode" \
    bash "$SMOKE_SH" "$@" < /dev/null > "$WORK/out.$$" 2>&1
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
  return 0
}

FAIL=0

run_scenario "anon mode: 401/42501 passes"            0 anon-pass         pfin-app || FAIL=1
run_scenario "anon mode: 200 is a security-anomaly FAIL, not a pass" 1 anon-fail-200      pfin-app || FAIL=1
run_scenario "anon mode: PGRST106 fails"               1 anon-fail-pgrst106 pfin-app || FAIL=1
run_scenario "anon mode: 3F000 fails"                  1 anon-fail-3f000    pfin-app || FAIL=1
run_scenario "jwt mode: 200 passes"                    0 jwt-pass          pfin-app --jwt fake-user-jwt || FAIL=1
run_scenario "jwt mode: 401/42501 (would pass in anon mode) FAILS here" 1 jwt-fail pfin-app --jwt fake-user-jwt || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-pfin-exposure.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-pfin-exposure.sh strike-proofs passed."
exit 0
