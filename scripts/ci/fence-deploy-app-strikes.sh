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
# Proves the claims deploy-app.sh's header makes about its own safety --
# the identity guard (base_directory AND build_pack), the --require-env
# names-only presence guard, the ambiguous-running-container refusal
# (BOTH container-resolution mechanisms), and the post-deploy network-
# attachment / hostname-resolve checks that replaced the earlier
# --require-network-with guard (F/CTO topology ruling 2026-09-19, Open
# Flags #12 -- `pfin-app` becomes a `dockercompose` resource with an
# `external:` network, making a pre-deploy declared-settings check
# irrelevant; the new checks verify the DEPLOYED reality instead). Keep
# this count current, it is read, not decorative (N4, PR #833 Sec joint
# review) -- sixteen scenarios in total:
#   1. MATCH -- a resolved application whose base_directory AND
#      build_pack equal the caller's --expect-* flags proceeds through
#      preflight AND (in --apply) through a full deploy+poll to
#      "finished".
#   2. AMBIGUOUS (non-compose) -- 2 RUNNING containers match the app uuid
#      (Sec F4) -- must refuse, never silently `head -1` a stale/pre-
#      deploy container.
#   3. REQUIRE-ENV-MATCH -- all required names present -> passes.
#   4. MISSING-ENV -- one required name absent -> refuses BEFORE any
#      /deploy call.
#   5. MISSING-ENV-WITH-APPLY -- same refusal holds with --apply given.
#   5a. PLACEHOLDER-ENV -- MEASURED (team-lead, 2026-09-20): all three
#      required names PRESENT, but one carries a Coolify compose-parse
#      placeholder value (the `:?message` text a fresh dockercompose
#      app's env store is pre-populated with) -- refuses on the VALUE-
#      SHAPE check, BEFORE any /deploy call, via a code path distinct
#      from scenario 4/5's absent-key path.
#   6. MISMATCH (base_directory) -- refuses in PREFLIGHT ONLY, before
#      --apply is even given -- proving the guard is not merely "checked,
#      then deployed anyway." Also asserts the fake curl log contains NO
#      "/deploy" call -- the deploy path must never even be attempted.
#   7. MISMATCH-WITH-APPLY -- same refusal holds when --apply IS given.
#   8. BUILD-PACK-MISMATCH -- --expect-build-pack given, live build_pack
#      disagrees -> refuses BEFORE any /deploy call.
#   9. COMPOSE-RESOLUTION-MATCH -- --compose-service given, exactly one
#      RUNNING container resolves via `docker compose ... ps -q` -> the
#      on-box health read passes.
#   10. COMPOSE-RESOLUTION-AMBIGUOUS -- --compose-service given, 2
#      RUNNING containers resolve -> refuses, same F4 discipline applied
#      to the compose-ps mechanism.
#   11. NETWORK-ATTACHMENT-FAIL -- --require-network given, the resolved
#      container is NOT attached to the named network -> refuses,
#      post-deploy.
#   12. RESOLVE-HOST-FAIL -- --resolve-host given, `getent hosts` fails
#      inside the container -> refuses, post-deploy.
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

# Fake `docker` -- stands in for BOTH container-resolution mechanisms
# deploy-app.sh supports, plus the post-deploy network/resolve probes.
#   plain `docker ps --filter name=... --filter status=running ...` --
#     the non-compose resolution path. $FAKE_DOCKER_CONTAINERS controls
#     row count (default 1; "2" exercises Sec's F4 ambiguous-match fix).
#   `docker compose --project-name <uuid> ps -q <service>` -- the
#     compose-pack resolution path. $FAKE_DOCKER_COMPOSE_CONTAINERS
#     controls row count (default 1; "2" exercises the SAME F4 fix on
#     this mechanism).
#   `docker inspect --format '...State.Running...' <id>` -- reports every
#     id it's given as RUNNING (the xargs/awk pipeline in deploy-app.sh
#     filters on this field; canned true here since the compose-ps mock
#     above already only returns the ids meant to look running).
#   `docker inspect --format '...NetworkSettings.Networks...' <container>`
#     -- $FAKE_DOCKER_NETWORKS selects which network name(s) are reported
#     (default "stack-net"; "none" reports only "bridge", exercising the
#     network-attachment guard's refusal).
#   `docker exec <container> getent hosts <hostname>` -- $FAKE_DOCKER_RESOLVE
#     selects success ("ok", default) or failure ("fail", exit 2, no
#     output), exercising the hostname-resolve guard's refusal.
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ps"* && "$*" == *"status=running"* ]]; then
  echo -e "app-abc123def456ghi789jk01-000000000000\tUp 5 seconds\t2026-09-19 12:00:00"
  if [[ "${FAKE_DOCKER_CONTAINERS:-1}" == "2" ]]; then
    echo -e "app-abc123def456ghi789jk01-111111111111\tUp 2 seconds\t2026-09-19 12:05:00"
  fi
  exit 0
fi
if [[ "$*" == "compose "*"ps -q"* ]]; then
  echo "cid1"
  if [[ "${FAKE_DOCKER_COMPOSE_CONTAINERS:-1}" == "2" ]]; then
    echo "cid2"
  fi
  exit 0
fi
if [[ "$*" == *"inspect"* && "$*" == *"State.Running"* ]]; then
  cid="${*: -1}"
  # D-1 (PR #841, F/CTO-relayed 2026-09-20): real docker/Go templates
  # only expand a string-literal ACTION -- {{"\t"}} -- into a real tab; a
  # bare \t in the format's literal text passes through as two literal
  # characters (backslash, t), unexpanded. This fixture used to emit a
  # REAL tab unconditionally, regardless of which format string
  # deploy-app.sh passed -- which meant this fence stayed green even
  # while the live script shipped the pre-fix format and broke on the
  # real box. Fixed: inspect the actual --format argument and reproduce
  # each shape faithfully, so this fence can fail on the pre-fix string.
  fmt=""
  prev=""
  for a in "$@"; do
    if [[ "$prev" == "--format" ]]; then fmt="$a"; fi
    prev="$a"
  done
  if [[ "$fmt" == *'{{"\t"}}'* ]]; then
    printf 'true\t%s\t2026-09-19T12:00:00Z\n' "$cid"
  else
    printf 'true\\t%s\\t2026-09-19T12:00:00Z\n' "$cid"
  fi
  exit 0
fi
if [[ "$*" == *"inspect"* && "$*" == *"NetworkSettings.Networks"* ]]; then
  if [[ "${FAKE_DOCKER_NETWORKS:-attached}" == "attached" ]]; then
    echo "stack-net"
  else
    echo "bridge"
  fi
  exit 0
fi
if [[ "$*" == *"exec"* && "$*" == *"getent hosts"* ]]; then
  if [[ "${FAKE_DOCKER_RESOLVE:-ok}" == "ok" ]]; then
    echo "10.0.0.5   api-gw"
    exit 0
  else
    exit 2
  fi
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
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose >/dev/null || FAIL=1

# 1a. MATCH -- --apply drives a full deploy+poll to a running container.
run_scenario "match: --apply deploys clean" 0 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --apply >/dev/null || FAIL=1

# 2. AMBIGUOUS (non-compose) -- two RUNNING containers match the app uuid
#    (the Coolify-redeploy overlap window, Sec F4). Must refuse, never
#    silently pick one via `head -1` / a bare non-empty check.
FAKE_DOCKER_CONTAINERS=2 run_scenario "ambiguous (non-compose): 2 running containers refuses" 1 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --apply >/dev/null || FAIL=1

# 3. MATCH + --require-env, all three present -- preflight passes.
run_scenario "match: --require-env passes when all names present" 0 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY >/dev/null || FAIL=1
# D-2 (PR #841, F/CTO-relayed 2026-09-20): this --require-env guard runs
# its python check inside an UNQUOTED <<REMOTE heredoc in deploy-app.sh;
# a backtick or dollar-brace reference anywhere in that heredoc body
# (even inside a comment, even inside the nested quoted <<'PYEOF' block)
# is expanded by the LOCAL shell before anything is sent remotely. The
# live incident: a `:?message`/`${VAR}` markdown-styled comment there
# corrupted this exact scenario's own stderr with "command not found"
# and "unbound variable" while the guard itself still reported PRESENT
# and exited 0 -- a silently-corrupted PASS, not a caught failure. Assert
# the captured output is clean of both symptoms.
if grep -qE 'command not found|unbound variable' "$WORK/out.$$" 2>/dev/null; then
  echo "FAIL: [match: --require-env passes when all names present] D-2 regression -- local heredoc parse corruption leaked into output:" >&2
  cat "$WORK/out.$$" >&2
  FAIL=1
fi

# 4. MISSING-ENV -- base_directory/build_pack match, but one required
#    name is absent from the env store -- must refuse BEFORE any
#    /deploy call.
MISSING_ENV_LOG="$(run_scenario "missing-env: --require-env refuses" 1 missing-env \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY)" || FAIL=1
if [[ -n "${MISSING_ENV_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISSING_ENV_LOG" 2>/dev/null; then
  echo "FAIL: [missing-env: --require-env refuses] the required-env guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 5. MISSING-ENV-WITH-APPLY -- same refusal holds with --apply given.
MISSING_ENV_APPLY_LOG="$(run_scenario "missing-env: --require-env refuses even with --apply" 1 missing-env \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --apply \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY)" || FAIL=1
if [[ -n "${MISSING_ENV_APPLY_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISSING_ENV_APPLY_LOG" 2>/dev/null; then
  echo "FAIL: [missing-env: --require-env refuses even with --apply] the required-env guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 5a. PLACEHOLDER-ENV -- MEASURED (team-lead, 2026-09-20): all three
#    required names are PRESENT (unlike scenario 4/5's MISSING key), but
#    one carries a Coolify compose-parse placeholder value (the literal
#    `:?message` text a fresh dockercompose app's env store gets pre-
#    populated with) -- must refuse on the VALUE-SHAPE check, BEFORE any
#    /deploy call, distinguishing "absent" from "present but a
#    placeholder" via two different code paths in the guard.
PLACEHOLDER_ENV_LOG="$(run_scenario "placeholder-env: --require-env refuses on a compose-parse placeholder value" 1 placeholder-env \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose \
  --require-env PUBLIC_SUPABASE_URL,PUBLIC_SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY)" || FAIL=1
if [[ -n "${PLACEHOLDER_ENV_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$PLACEHOLDER_ENV_LOG" 2>/dev/null; then
  echo "FAIL: [placeholder-env: --require-env refuses on a compose-parse placeholder value] the required-env guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 6. MISMATCH (base_directory) -- preflight refuses, and the deploy
#    endpoint is NEVER hit.
MISMATCH_LOG="$(run_scenario "mismatch: preflight refuses" 1 mismatch \
  pfin-app --expect-base-directory /api)" || FAIL=1
if [[ -n "${MISMATCH_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISMATCH_LOG" 2>/dev/null; then
  echo "FAIL: [mismatch: preflight refuses] the identity guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 7. MISMATCH-WITH-APPLY -- same refusal holds with --apply given; the
#    guard runs BEFORE the apply/deploy branch, not only in the lighter
#    preflight path.
MISMATCH_APPLY_LOG="$(run_scenario "mismatch: refuses even with --apply" 1 mismatch \
  pfin-app --expect-base-directory /api --apply)" || FAIL=1
if [[ -n "${MISMATCH_APPLY_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$MISMATCH_APPLY_LOG" 2>/dev/null; then
  echo "FAIL: [mismatch: refuses even with --apply] the identity guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 8. BUILD-PACK-MISMATCH -- base_directory matches, but the live
#    build_pack disagrees with --expect-build-pack -- must refuse
#    BEFORE any /deploy call.
BUILDPACK_LOG="$(run_scenario "build-pack-mismatch: preflight refuses" 1 build-pack-mismatch \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose)" || FAIL=1
if [[ -n "${BUILDPACK_LOG:-}" ]] && grep -qF '/deploy?uuid=' "$BUILDPACK_LOG" 2>/dev/null; then
  echo "FAIL: [build-pack-mismatch: preflight refuses] the build-pack guard did NOT prevent a /deploy call -- vacuous refusal." >&2
  FAIL=1
fi

# 9. COMPOSE-RESOLUTION-MATCH -- --compose-service given, exactly one
#    RUNNING container resolves via `docker compose ... ps -q` -- the
#    on-box health read passes.
run_scenario "compose-resolution: single container passes" 0 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --apply >/dev/null || FAIL=1

# 10. COMPOSE-RESOLUTION-AMBIGUOUS -- --compose-service given, 2 RUNNING
#    containers resolve -- refuses, same F4 discipline applied to the
#    compose-ps mechanism (distinct code path from scenario 2's plain
#    `docker ps` mechanism -- both must be struck independently).
FAKE_DOCKER_COMPOSE_CONTAINERS=2 run_scenario "compose-resolution: ambiguous (2 containers) refuses" 1 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --apply >/dev/null || FAIL=1

# 10a. NETWORK-ATTACHMENT-PASS -- positive control: --require-network
#    given, the resolved container IS attached -- must pass, not just
#    "the failure case correctly fails."
run_scenario "network-attachment: attached passes" 0 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --require-network stack-net --apply >/dev/null || FAIL=1

# 10b. RESOLVE-HOST-PASS -- positive control: --resolve-host given,
#    `getent hosts` succeeds -- must pass.
run_scenario "resolve-host: getent success passes" 0 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --resolve-host api-gw --apply >/dev/null || FAIL=1

# 11. NETWORK-ATTACHMENT-FAIL -- --require-network given, the resolved
#    container is NOT attached to the named network -- post-deploy
#    refusal (this check cannot run pre-deploy; there is no running
#    container to inspect yet).
FAKE_DOCKER_NETWORKS=none run_scenario "network-attachment: not attached refuses" 1 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --require-network stack-net --apply >/dev/null || FAIL=1

# 12. RESOLVE-HOST-FAIL -- --resolve-host given, `getent hosts` fails
#    inside the container -- post-deploy refusal.
FAKE_DOCKER_RESOLVE=fail run_scenario "resolve-host: getent failure refuses" 1 match \
  pfin-app --expect-base-directory /api --expect-build-pack dockercompose --compose-service app --resolve-host api-gw --apply >/dev/null || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more deploy-app.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all deploy-app.sh strike-proofs passed."
exit 0
