#!/usr/bin/env bash
#
# fence-provision-app-strikes.sh -- offline strike-proof for
# scripts/provision-app.sh's delete-if-empty-shell guard (the
# "REFUSING TO DELETE" branch, step "Preflight — existing 'pfin-app'
# resource"). Runs entirely without a live box or network: a fake `ssh`
# (this file generates it) rewrites the `/root/.pfin` path
# provision-app.sh's remote driver hardcodes to a throwaway temp dir, a
# fake `docker` stands in for the on-box `docker ps -a`/`docker images`/
# `docker inspect`/`docker compose` reads, and
# tests/fixtures/ci/provision-app/fake-curl stands in for curl (PATH-
# shadowed, canned Coolify-API-shaped responses -- provision-app.sh
# itself is never modified or made aware this exists). Same strike shape
# as scripts/ci/fence-deploy-app-strikes.sh.
#
# WHY THIS FENCE EXISTS
#   MEASURED (team-lead, 2026-09-20): provision-app.sh's original
#   delete-guard read `GET /applications/<uuid>/deployments` -- 404 on
#   this Coolify (4.3.18). `GET /deployments?uuid=<uuid>` was also ruled
#   out: it returned 200 [] for `pfin-migrator` despite that resource
#   having FOUR completed deployments the same day, because it lists
#   only in-flight/queued deployments, not history. The guard now reads
#   three on-box/API predicates instead: `docker ps -a` (any container
#   ever created for the uuid), `docker images` (any image ever built
#   for it), and the env-store name count. This fence proves each of the
#   three refuses independently, naming the offending predicate, and
#   that all-zero proceeds past the guard (into PREFLIGHT's own "nothing
#   was deleted" exit 0, not into a live DELETE).
#
# Scenarios 1-6 run preflight-only (no --apply) -- the delete-guard read
# happens during preflight, before --apply's own DELETE/POST branches.
# Scenario 7 (added for the live 422 finding below) exercises the
# CREATE path under --apply, so this fence's fixture now also covers
# /servers, /applications/public, /envs/bulk, and
# scripts/ci/check-source-commit-in-build.sh (a real, separately-
# strikeable script, run as-is -- not faked). Seven scenarios:
#   1. ALL-ZERO       -- zero containers, zero images, zero env names ->
#      preflight proceeds to its own "PREFLIGHT ONLY" exit 0 (delete
#      would be attempted under --apply, but is never reached here).
#   2. CONTAINERS      -- `docker ps -a` matches the uuid once -> refuses
#      naming "containers", before any other predicate is even reached.
#   3. IMAGES          -- `docker images` matches the uuid once (zero
#      containers) -> refuses naming "images".
#   4. ENV             -- env-store carries one name (zero containers,
#      zero images) -> refuses naming "env" ("env-store names").
#   5. PS-READ-FAILS   -- Sec F-1 (PR #836 review): the `docker ps -a`
#      SSH read itself fails (daemon down / not on PATH / permission
#      error), never reaching grep at all -> must refuse naming
#      "containers=unknown", NOT silently read as containers=0. Strike-
#      verifies the fail-closed fix: reverting F-1 (restoring the old
#      `| grep -c ... || true` remote-pipeline shape) makes this scenario
#      wrongly report containers=0 and proceed -- this scenario is what
#      catches that regression.
#   6. IMAGES-READ-FAILS -- same shape as 5, for the `docker images` SSH
#      read -> refuses naming "images=unknown".
#   7. CREATE-HAPPY   -- Live finding (team-lead, 2026-09-20, stage A
#      step 1 --apply): `POST /applications/public` 422'd with
#      `{"errors":{"project_uuid":["This field is required."]}}` --
#      provision-app.sh's create body omitted `project_uuid` entirely.
#      `pfin-app` is genuinely ABSENT on the real box now (the delete leg
#      from PR #836 succeeded before the create leg 422'd). `--apply`
#      against a fixture with the stack app only (no pfin-app entry) must
#      skip the delete leg, resolve `SERVER_UUID`, and POST a create body
#      fake-curl validates against Coolify's OWN required-key set
#      (`project_uuid`, `environment_uuid`, `server_uuid`,
#      `git_repository`, `git_branch`, `build_pack`, `name`,
#      `base_directory`, `docker_compose_location`) -- 422ing with
#      Coolify's exact error shape naming the first missing key,
#      UNCONDITIONALLY, regardless of `$FAKE_CURL_MODE`. This scenario is
#      the create-body watcher: it passes because the fix adds
#      `project_uuid`, and strike-verifies by running a scratch copy of
#      provision-app.sh with `project_uuid` stripped back out of
#      `CREATE_BODY` against this exact scenario -- confirmed locally to
#      422 before this commit, not merely asserted here (see this PR's
#      hand-off for the recorded strike-verify run).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/provision-app"
PROVISION_APP_SH="$REPO_ROOT/scripts/provision-app.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$PROVISION_APP_SH" ]] || { echo "FATAL: $PROVISION_APP_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- stands in for every on-box docker read
# provision-app.sh's sshx() calls make. Since Sec F-1 (PR #836 review),
# provision-app.sh sends the BARE `docker ps -a --format ...` / `docker
# images --format ...` command over ssh and greps the captured output
# LOCALLY (never a remote `| grep -c ... || true` pipeline) so that a
# failed docker read surfaces as a failed ssh command, not as an empty
# grep match:
#   `docker compose --project-name <stack-uuid> ps -q meta` +
#   `docker inspect --format '...NetworkSettings.Networks...' <cid>` --
#     the stack-network lookup every preflight run makes BEFORE ever
#     reaching the delete-guard; always reports exactly one network
#     ("stack-net") so every scenario gets past this step identically.
#   `docker ps -a --format '{{.Names}}'` -- exits 1 with no output if
#     $FAKE_DOCKER_PS_FAIL is set (scenario 5); otherwise prints
#     $FAKE_CONTAINER_COUNT container names containing the fixed
#     old-app uuid (default 0).
#   `docker images --format '{{.Repository}}'` -- exits 1 with no output
#     if $FAKE_DOCKER_IMAGES_FAIL is set (scenario 6); otherwise prints
#     $FAKE_IMAGE_COUNT image repository names containing the same uuid
#     (default 0).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
OLD_APP_UUID="dddd4444eeee5555ffff6666"
if [[ "$*" == *"compose "*"ps -q meta"* ]]; then
  echo "netcid1"
  exit 0
fi
if [[ "$*" == *"inspect"* && "$*" == *"NetworkSettings.Networks"* ]]; then
  echo "stack-net"
  exit 0
fi
if [[ "$*" == *"ps -a --format"* ]]; then
  if [[ "${FAKE_DOCKER_PS_FAIL:-0}" == "1" ]]; then
    echo "docker: Cannot connect to the Docker daemon" >&2
    exit 1
  fi
  n="${FAKE_CONTAINER_COUNT:-0}"
  i=0
  while [[ "$i" -lt "$n" ]]; do
    echo "pfin-app-${OLD_APP_UUID}-container-$i"
    i=$((i + 1))
  done
  exit 0
fi
if [[ "$*" == *"images --format"* ]]; then
  if [[ "${FAKE_DOCKER_IMAGES_FAIL:-0}" == "1" ]]; then
    echo "docker: Cannot connect to the Docker daemon" >&2
    exit 1
  fi
  n="${FAKE_IMAGE_COUNT:-0}"
  i=0
  while [[ "$i" -lt "$n" ]]; do
    echo "pfin-app-${OLD_APP_UUID}-image-$i"
    i=$((i + 1))
  done
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

# Same fake `ssh` shape as fence-deploy-app-strikes.sh -- see that file's
# header comment for the call-shape rationale (plain probes, sshx() with
# a literal command string, sshx() carrying an `env VAR=val ... bash -s`
# command string). provision-app.sh uses all three (the reachability/
# coolify.env probes, the api() helper's `env method=... bash -s` calls,
# and the plain on-box docker commands).
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LAST_PROBE="\${@: -1}"
# Exact-match on the LAST arg, not a suffix match on "\$*" -- deploy-app.sh's
# sibling fence matches "*\" true\"", which would misfire here: provision-
# app.sh's own on-box reads end in "|| true" (belt-and-braces on grep -c's
# exit code), which ALSO ends in " true" as a substring. An exact-equality
# check on the bare reachability probe ("sshx true") avoids that collision.
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
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_CONTAINER_COUNT="\$FAKE_CONTAINER_COUNT" FAKE_IMAGE_COUNT="\$FAKE_IMAGE_COUNT" \\
  FAKE_DOCKER_PS_FAIL="\${FAKE_DOCKER_PS_FAIL:-0}" FAKE_DOCKER_IMAGES_FAIL="\${FAKE_DOCKER_IMAGES_FAIL:-0}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  local desc="$1" expect_exit="$2" mode="$3" containers="$4" images="$5" apply="${6:-}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  if [[ -n "$apply" ]]; then
    BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
      PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
      FAKE_CONTAINER_COUNT="$containers" FAKE_IMAGE_COUNT="$images" \
      bash "$PROVISION_APP_SH" "$apply" < /dev/null > "$WORK/out.$$" 2>&1
  else
    BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
      PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
      FAKE_CONTAINER_COUNT="$containers" FAKE_IMAGE_COUNT="$images" \
      bash "$PROVISION_APP_SH" < /dev/null > "$WORK/out.$$" 2>&1
  fi
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

FAIL=0

# Sec F-3 (PR #836 review): a captured-output check written as
# `[[ -n "$X_OUT" ]] && ! grep -q ... ` PASSES SILENTLY when $X_OUT is
# empty (run_scenario already failed and returned nothing) -- the `-n`
# guard was meant to avoid a spurious grep-on-empty-string failure, but
# it also let a genuinely missing capture through unflagged. Route every
# assertion through this helper instead: empty output is its own named
# failure, never silently skipped.
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

# 1. ALL-ZERO -- proceeds past the guard into preflight's own "nothing
#    was deleted, nothing was created" exit 0.
ALLZERO_OUT="$(run_scenario "all-zero: preflight proceeds" 0 clean 0 0)" || FAIL=1
assert_output_contains "all-zero: preflight proceeds" "${ALLZERO_OUT:-}" "PREFLIGHT ONLY" || FAIL=1

# 2. CONTAINERS -- one container matches the uuid -> refuses naming
#    "containers", before the image/env predicates are even reached.
CONTAINERS_OUT="$(run_scenario "containers=1: refuses naming containers" 1 clean 1 0)" || FAIL=1
assert_output_contains "containers=1: refuses naming containers" "${CONTAINERS_OUT:-}" "containers=1" || FAIL=1

# 3. IMAGES -- zero containers, one image matches the uuid -> refuses
#    naming "images".
IMAGES_OUT="$(run_scenario "images=1: refuses naming images" 1 clean 0 1)" || FAIL=1
assert_output_contains "images=1: refuses naming images" "${IMAGES_OUT:-}" "images=1" || FAIL=1

# 4. ENV -- zero containers, zero images, one env-store name -> refuses
#    naming "env" (env-store names), names only -- never an env value.
ENV_OUT="$(run_scenario "env=1: refuses naming env" 1 env-nonzero 0 0)" || FAIL=1
assert_output_contains "env=1: refuses naming env" "${ENV_OUT:-}" "env-store names=1" || FAIL=1
if [[ -n "${ENV_OUT:-}" ]] && grep -qF "SOME_NAME" <<<"$ENV_OUT"; then
  echo "FAIL: [env=1: refuses naming env] the refusal leaked an env-store VALUE/NAME beyond the count -- names-only discipline broken." >&2
  FAIL=1
fi

# 5. PS-READ-FAILS -- Sec F-1 strike: the `docker ps -a` SSH read itself
#    fails (never reaching grep) -> refuses naming "containers=unknown".
#    Zero images, zero env names, so ONLY the ps-read failure can be
#    the reason for the refusal.
PSREADFAIL_OUT="$(FAKE_DOCKER_PS_FAIL=1 run_scenario "ps-read-fails: refuses naming containers=unknown" 1 clean 0 0)" || FAIL=1
assert_output_contains "ps-read-fails: refuses naming containers=unknown" "${PSREADFAIL_OUT:-}" "containers=unknown" || FAIL=1

# 6. IMAGES-READ-FAILS -- same shape as 5, for the `docker images` SSH
#    read -> refuses naming "images=unknown". Zero containers (the ps
#    read succeeds and returns none), zero env names, so ONLY the
#    images-read failure can be the reason for the refusal.
IMAGESREADFAIL_OUT="$(FAKE_DOCKER_IMAGES_FAIL=1 run_scenario "images-read-fails: refuses naming images=unknown" 1 clean 0 0)" || FAIL=1
assert_output_contains "images-read-fails: refuses naming images=unknown" "${IMAGESREADFAIL_OUT:-}" "images=unknown" || FAIL=1

# 7. CREATE-HAPPY -- Live finding, 2026-09-20 (team-lead, stage A step 1
#    --apply): `pfin-app` is genuinely ABSENT on the real box right now
#    (the delete leg from PR #836 succeeded, the create leg 422'd and
#    was never retried into existence) -- this IS the state the script
#    runs against next. `--apply` against fake-curl's "absent" mode (the
#    stack app only, no pfin-app entry at all) must: skip the delete leg
#    entirely (DELETE_NEEDED=0, no docker ps -a/images calls fired --
#    nothing to guard), resolve a real SERVER_UUID, POST a create body
#    fake-curl validates for every required key (this is what exercises
#    the create-body watcher -- see this file's own header and the
#    fake-curl fixture's header for the strike-verify done on this
#    predicate: reverting the project_uuid fix on a scratch copy of
#    provision-app.sh and re-running this exact scenario 422s, confirmed
#    locally before this commit, not merely asserted here), and complete
#    through the APP_STACK_NETWORK_NAME set-and-readback with a byte-
#    exact match -> exits 0, output names "application created".
CREATEHAPPY_OUT="$(run_scenario "create-happy: pfin-app absent, apply succeeds" 0 absent 0 0 --apply)" || FAIL=1
assert_output_contains "create-happy: pfin-app absent, apply succeeds" "${CREATEHAPPY_OUT:-}" "application created" || FAIL=1
if [[ -n "${CREATEHAPPY_OUT:-}" ]] && ! grep -qF "does not exist" <<<"$CREATEHAPPY_OUT"; then
  echo "FAIL: [create-happy: pfin-app absent, apply succeeds] never printed the 'does not exist -- will be created fresh' preflight line -- the ABSENT branch may not have actually fired (a false pass through the wrong code path)." >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more provision-app.sh delete-guard strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision-app.sh delete-guard strike-proofs passed."
exit 0
