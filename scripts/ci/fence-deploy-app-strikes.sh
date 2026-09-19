#!/usr/bin/env bash
#
# fence-deploy-app-strikes.sh -- offline strike-proof for
# scripts/deploy-app.sh's identity guard. Runs entirely without a live box
# or network: a fake `ssh` (this file) rewrites the `/root/.pfin` path
# deploy-app.sh's remote driver hardcodes to a throwaway temp dir, then
# runs that driver locally with tests/fixtures/ci/deploy-app/fake-curl
# standing in for curl (PATH-shadowed, canned Coolify-API-shaped
# responses -- deploy-app.sh itself is never modified or made aware this
# exists). Same strike shape as scripts/ci/fence-coolify-env-strikes.sh.
#
# Proves the ONE claim deploy-app.sh's header makes about its own safety:
#   1. MATCH -- a resolved application whose base_directory equals the
#      caller's --expect-base-directory proceeds through preflight AND
#      (in --apply) through a full deploy+poll to "finished".
#   2. MISMATCH -- a resolved application whose base_directory does NOT
#      match refuses (non-zero exit) in PREFLIGHT ONLY, before --apply is
#      even given -- proving the guard is not merely "checked, then
#      deployed anyway." A bare rc!=0 would be vacuous if the script
#      failed for some unrelated reason, so this also asserts the fake
#      curl log contains NO "/deploy" call in the mismatch case --
#      the deploy path must never even be attempted.
#   3. MISMATCH-WITH-APPLY -- same refusal holds when --apply IS given
#      (the guard fires before the deploy branch is reached at all, not
#      merely under the lighter preflight code path).
#
# Exit 0 only if all three scenarios behave exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/deploy-app"
DEPLOY_APP_SH="$REPO_ROOT/scripts/deploy-app.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$DEPLOY_APP_SH" ]] || { echo "FATAL: $DEPLOY_APP_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- deploy-app.sh's on-box health read shells out to
# `docker ps --filter name=<uuid> --filter status=running --format ...`
# on the box. Stand in with a canned single-row match so the strike
# exercises the full script, not just the guard + deploy halves.
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* && "$*" == *"status=running"* ]]; then
  echo -e "app-abc123def456ghi789jk01-000000000000\tUp 5 seconds"
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

# Same fake `ssh` shape as fence-coolify-env-strikes.sh -- see that file's
# header comment for the four call-shape rationale (plain probes, sshx()
# with a literal command, sshx() carrying an `env VAR=val ... bash -s`
# command string, and sshx_in()'s bare `bash -s`). deploy-app.sh uses all
# four (the reachability probes, the `env app_query=... bash -s` resolve
# call, and the plain `bash -s` deploy call).
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
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  local desc="$1" expect_exit="$2" mode="$3"; shift 3
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
    bash "$DEPLOY_APP_SH" "$@" < /dev/null > "$WORK/out.$$" 2>&1
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

  # Status line to STDERR, log path to STDOUT -- callers that capture this
  # function's output via $(...) (to inspect the log afterward) must get
  # ONLY the path on stdout, never mixed with the human-readable status.
  echo "OK: [$desc] exit $rc as expected, token absent from every logged curl argv." >&2
  echo "$log"
  return 0
}

FAIL=0

# 1. MATCH -- preflight passes (guard satisfied), no --apply given.
run_scenario "match: preflight passes" 0 match \
  pfin-app --expect-base-directory /api >/dev/null || FAIL=1

# 2. MATCH -- --apply drives a full deploy+poll to a running container.
run_scenario "match: --apply deploys clean" 0 match \
  pfin-app --expect-base-directory /api --apply >/dev/null || FAIL=1

# 3. MISMATCH -- preflight refuses, and the deploy endpoint is NEVER hit.
MISMATCH_LOG="$(run_scenario "mismatch: preflight refuses" 1 mismatch \
  pfin-app --expect-base-directory /api)" || FAIL=1
if [[ -n "${MISMATCH_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISMATCH_LOG" 2>/dev/null; then
  echo "FAIL: [mismatch: preflight refuses] the identity guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 4. MISMATCH-WITH-APPLY -- same refusal holds with --apply given; the
#    guard runs BEFORE the apply/deploy branch, not only in the lighter
#    preflight path.
MISMATCH_APPLY_LOG="$(run_scenario "mismatch: refuses even with --apply" 1 mismatch \
  pfin-app --expect-base-directory /api --apply)" || FAIL=1
if [[ -n "${MISMATCH_APPLY_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISMATCH_APPLY_LOG" 2>/dev/null; then
  echo "FAIL: [mismatch: refuses even with --apply] the identity guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more deploy-app.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all deploy-app.sh strike-proofs passed."
exit 0
