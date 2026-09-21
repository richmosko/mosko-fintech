#!/usr/bin/env bash
#
# fence-smoke-pdf-roundtrip-strikes.sh -- offline strike-proof for
# scripts/smoke-pdf-roundtrip.sh's STRUCTURAL logic: container
# resolution and the status/magic-bytes decision. BACKLOG.md §7.36
# item 68 (W-3).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- the `docker exec ...
# node -e ...` leg is CANNED here, not re-executed: this fence never
# mints a real JWT, never opens a real HTTP connection to a pdf-render
# worker, and never invokes headless Chromium. The JWT-construction
# logic itself (HS256, claims shape, base64url encoding) was validated
# OFFLINE BY HAND this same PR -- `node -e` against the exact snippet
# embedded in scripts/smoke-pdf-roundtrip.sh, confirming the signature
# self-verifies and both JWT segments decode to the expected shape (see
# that script's own header for the claims this mirrors from
# api/src/lib/server/pdf/renderClient.ts). This fence proves the SHELL
# script's own control flow is correct; the real network round trip is
# live-only.
#
# Scenarios:
#   1. HAPPY-PATH -- 200, PDF_MAGIC_OK -> exit 0.
#   2. NO-SIGNING-KEY -- the sibling container's own env lacks
#      PDF_WORKER_SIGNING_KEY -> refuses.
#   3. WRONG-STATUS -- a non-200 response (e.g. 401, the worker's own
#      auth rejection) -> refuses.
#   4. WRONG-MAGIC -- 200 but the body does not start with %PDF ->
#      refuses (a 200 with a non-PDF body is not a pass).
#   5. AMBIGUOUS -- 2 running containers match the compose service ->
#      refuses, never silently picking one (Sec F4 discipline).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-pdf-roundtrip"
SMOKE_SH="$REPO_ROOT/scripts/smoke-pdf-roundtrip.sh"

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
PATH="$FAKE_BIN:\$PATH" FAKE_STATUS="\${FAKE_STATUS:-}" FAKE_MAGIC="\${FAKE_MAGIC:-}" \\
  FAKE_BYTES="\${FAKE_BYTES:-}" FAKE_CONTAINERS="\${FAKE_CONTAINERS:-}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <status> <magic> <containers>
  local desc="$1" expect_exit="$2" status="$3" magic="$4" containers="$5"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$WORK/curl.log.$$.$RANDOM" \
    FAKE_STATUS="$status" FAKE_MAGIC="$magic" FAKE_BYTES="1234" FAKE_CONTAINERS="$containers" \
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

run_scenario "happy-path" 0 200 PDF_MAGIC_OK 1 || FAIL=1
run_scenario "no signing key: refuses" 1 000 NO_SIGNING_KEY 1 || FAIL=1
run_scenario "wrong status (401): refuses" 1 401 PDF_MAGIC_MISSING 1 || FAIL=1
run_scenario "wrong magic (200, not PDF): refuses" 1 200 PDF_MAGIC_MISSING 1 || FAIL=1
run_scenario "ambiguous: 2 running containers refuses" 1 200 PDF_MAGIC_OK 2 || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-pdf-roundtrip.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-pdf-roundtrip.sh strike-proofs passed."
exit 0
