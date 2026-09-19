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
# Proves the FOUR claims deploy-app.sh's header makes about its own safety
# (the identity guard, the --require-env names-only presence guard, the
# --require-network-with cross-application guard, and the ambiguous-
# running-container refusal) -- eight scenarios in total (N4, PR #833 Sec
# joint review: this comment previously said "three", there are now
# eight; keep this count current, it is read, not decorative):
#   1. MATCH -- a resolved application whose base_directory equals the
#      caller's --expect-base-directory proceeds through preflight AND
#      (in --apply) through a full deploy+poll to "finished".
#   1b. AMBIGUOUS -- 2 RUNNING containers match the app uuid (Sec F4) --
#      must refuse, never silently `head -1` a stale/pre-deploy container.
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
#   4. REQUIRE-ENV-MATCH -- all required names present -> passes.
#   5. REQUIRE-ENV-MISSING -- one required name absent -> refuses, same
#      before-any-/deploy-call proof as scenarios 2/3.
#   6. NETWORK-MATCH (Sec F3) -- both applications share environment_id
#      and connect_to_docker_network=true on both -> passes.
#   7. NETWORK-DIFF-ENV -- different environment_id -> refuses.
#   8. NETWORK-OFF -- connect_to_docker_network=false on the OTHER side
#      -> refuses, naming which side.
#
# Exit 0 only if every scenario behaves exactly as specified above.

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
# $FAKE_DOCKER_CONTAINERS controls how many RUNNING rows `docker ps`
# reports -- default 1 (the normal case); "2" exercises Sec's F4 fix
# (ambiguous match must refuse, never silently pick one via `head -1`).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* && "$*" == *"status=running"* ]]; then
  echo -e "app-abc123def456ghi789jk01-000000000000\tUp 5 seconds\t2026-09-19 12:00:00"
  if [[ "${FAKE_DOCKER_CONTAINERS:-1}" == "2" ]]; then
    echo -e "app-abc123def456ghi789jk01-111111111111\tUp 2 seconds\t2026-09-19 12:05:00"
  fi
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

# 2a. AMBIGUOUS -- two RUNNING containers match the app uuid (the
#     Coolify-redeploy overlap window, Sec F4). Must refuse, never
#     silently pick one via `head -1` / a bare non-empty check.
FAKE_DOCKER_CONTAINERS=2 run_scenario "ambiguous: 2 running containers refuses" 1 match \
  pfin-app --expect-base-directory /api --apply >/dev/null || FAIL=1

# 2b. MATCH + --require-env, all three present -- preflight passes.
run_scenario "match: --require-env passes when all names present" 0 match \
  pfin-app --expect-base-directory /api \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY >/dev/null || FAIL=1

# 2c. MISSING-ENV -- base_directory matches, but one required name is
#     absent from the env store -- must refuse BEFORE any /deploy call,
#     same vacuous-refusal check as the identity-guard scenarios below.
MISSING_ENV_LOG="$(run_scenario "missing-env: --require-env refuses" 1 missing-env \
  pfin-app --expect-base-directory /api \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY)" || FAIL=1
if [[ -n "${MISSING_ENV_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISSING_ENV_LOG" 2>/dev/null; then
  echo "FAIL: [missing-env: --require-env refuses] the required-env guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 2d. MISSING-ENV-WITH-APPLY -- same refusal holds with --apply given.
MISSING_ENV_APPLY_LOG="$(run_scenario "missing-env: --require-env refuses even with --apply" 1 missing-env \
  pfin-app --expect-base-directory /api --apply \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY)" || FAIL=1
if [[ -n "${MISSING_ENV_APPLY_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISSING_ENV_APPLY_LOG" 2>/dev/null; then
  echo "FAIL: [missing-env: --require-env refuses even with --apply] the required-env guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

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

# 5. NETWORK-MATCH -- both apps share environment_id and
#    connect_to_docker_network=true on both -- --require-network-with
#    must pass.
run_scenario "network-match: --require-network-with passes" 0 network-match \
  pfin-app --expect-base-directory /api --require-network-with pfin-stack >/dev/null || FAIL=1

# 6. NETWORK-DIFF-ENV -- different environment_id -- must refuse BEFORE
#    any /deploy call.
NETWORK_DIFF_LOG="$(run_scenario "network-diff-env: --require-network-with refuses" 1 network-diff-env \
  pfin-app --expect-base-directory /api --require-network-with pfin-stack --apply)" || FAIL=1
if [[ -n "${NETWORK_DIFF_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$NETWORK_DIFF_LOG" 2>/dev/null; then
  echo "FAIL: [network-diff-env: --require-network-with refuses] the network guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 7. NETWORK-OFF -- same environment_id, but the OTHER app has
#    connect_to_docker_network=false -- must refuse BEFORE any /deploy
#    call, naming the failing side.
NETWORK_OFF_LOG="$(run_scenario "network-off: --require-network-with refuses" 1 network-off \
  pfin-app --expect-base-directory /api --require-network-with pfin-stack --apply)" || FAIL=1
if [[ -n "${NETWORK_OFF_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$NETWORK_OFF_LOG" 2>/dev/null; then
  echo "FAIL: [network-off: --require-network-with refuses] the network guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more deploy-app.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all deploy-app.sh strike-proofs passed."
exit 0
