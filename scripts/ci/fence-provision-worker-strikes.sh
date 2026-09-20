#!/usr/bin/env bash
#
# fence-provision-worker-strikes.sh -- offline strike-proof for
# scripts/provision-worker.sh's delete-if-empty-shell guard and its
# unknown-resource-name refusal. Copies scripts/ci/fence-provision-app-
# strikes.sh's own scenario shapes 1-7 verbatim (same fake ssh/docker,
# same tests/fixtures/ci/provision-worker/fake-curl shape) and adds scenario
# 8 (unknown resource-name refusal, this script's own new surface). Runs
# entirely without a live box or network.
#
# Scenarios 1-7 run against EACH of the three known resource names
# (pfin-back-etl / pfin-pdf-render / pfin-provider-sync) in a loop, so the
# table-driven dispatch in provision-worker.sh is exercised for all three,
# not just one:
#   1. ALL-ZERO       -- zero containers, zero images, zero env names ->
#      preflight proceeds to its own "PREFLIGHT ONLY" exit 0.
#   2. CONTAINERS      -- `docker ps -a` matches the uuid once -> refuses
#      naming "containers".
#   3. IMAGES          -- `docker images` matches the uuid once -> refuses
#      naming "images".
#   4. ENV             -- env-store carries one name -> refuses naming
#      "env" ("env-store names"), names only, never leaking the value.
#   5. PS-READ-FAILS   -- the `docker ps -a` SSH read itself fails -> must
#      refuse naming "containers=unknown", NOT silently read as 0.
#   6. IMAGES-READ-FAILS -- same shape as 5, for `docker images`.
#   7. CREATE-HAPPY    -- resource genuinely ABSENT -> `--apply` skips the
#      delete leg, resolves SERVER_UUID, POSTs a create body fake-curl
#      validates for every required key, completes through the resource's
#      OWN uniquely-named network var's set-and-readback with a byte-exact
#      match -> exits 0, output names "application created".
#   8. UNKNOWN-NAME    -- this script's OWN new surface, not present in
#      provision-app.sh (which has no resource-name argument at all):
#      `provision-worker.sh some-other-name` must refuse with exit 2 BEFORE
#      any SSH/API call is attempted -- proven by running it with BOX_IP
#      pointed at an address `ssh`/`curl` are never invoked against (no
#      fake ssh/curl on PATH at all for this scenario) and asserting the
#      refusal message, not a network-timeout failure.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/provision-worker"
PROVISION_WORKER_SH="$REPO_ROOT/scripts/provision-worker.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$PROVISION_WORKER_SH" ]] || { echo "FATAL: $PROVISION_WORKER_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- identical shape to fence-provision-app-strikes.sh's own
# (see that file's header for the full call-shape rationale). The uuid it
# matches against is the fixed OLD_APP_UUID both fake-curl fixtures share.
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
    echo "worker-${OLD_APP_UUID}-container-$i"
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
    echo "worker-${OLD_APP_UUID}-image-$i"
    i=$((i + 1))
  done
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

# Same fake `ssh` shape as fence-provision-app-strikes.sh's own -- rewrites
# the /root/.pfin path, forwards FAKE_RESOURCE_NAME/FAKE_NETWORK_VAR through
# to the sub-shell so fake-curl sees them too.
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
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
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" \\
    FAKE_RESOURCE_NAME="\$FAKE_RESOURCE_NAME" FAKE_NETWORK_VAR="\$FAKE_NETWORK_VAR" \\
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
  local desc="$1" expect_exit="$2" mode="$3" containers="$4" images="$5" resource="$6" netvar="$7" apply="${8:-}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  if [[ -n "$apply" ]]; then
    BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
      PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
      FAKE_CONTAINER_COUNT="$containers" FAKE_IMAGE_COUNT="$images" \
      FAKE_RESOURCE_NAME="$resource" FAKE_NETWORK_VAR="$netvar" \
      bash "$PROVISION_WORKER_SH" "$resource" "$apply" < /dev/null > "$WORK/out.$$" 2>&1
  else
    BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
      PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
      FAKE_CONTAINER_COUNT="$containers" FAKE_IMAGE_COUNT="$images" \
      FAKE_RESOURCE_NAME="$resource" FAKE_NETWORK_VAR="$netvar" \
      bash "$PROVISION_WORKER_SH" "$resource" < /dev/null > "$WORK/out.$$" 2>&1
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

# Table of the three known resources, mirroring provision-worker.sh's own
# case statement -- kept here as data, not re-derived from the script
# itself (a strike-proof that reads its own target's table would not catch
# a defect IN that table).
RESOURCES=(
  "pfin-back-etl:ETL_STACK_NETWORK_NAME"
  "pfin-pdf-render:PDF_RENDER_STACK_NETWORK_NAME"
  "pfin-provider-sync:PROVIDER_SYNC_STACK_NETWORK_NAME"
)

for entry in "${RESOURCES[@]}"; do
  RESOURCE="${entry%%:*}"
  NETVAR="${entry#*:}"

  ALLZERO_OUT="$(run_scenario "$RESOURCE: all-zero, preflight proceeds" 0 clean 0 0 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: all-zero" "${ALLZERO_OUT:-}" "PREFLIGHT ONLY" || FAIL=1

  CONTAINERS_OUT="$(run_scenario "$RESOURCE: containers=1, refuses" 1 clean 1 0 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: containers=1" "${CONTAINERS_OUT:-}" "containers=1" || FAIL=1

  IMAGES_OUT="$(run_scenario "$RESOURCE: images=1, refuses" 1 clean 0 1 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: images=1" "${IMAGES_OUT:-}" "images=1" || FAIL=1

  ENV_OUT="$(run_scenario "$RESOURCE: env=1, refuses" 1 env-nonzero 0 0 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: env=1" "${ENV_OUT:-}" "env-store names=1" || FAIL=1
  if [[ -n "${ENV_OUT:-}" ]] && grep -qF "SOME_NAME" <<<"$ENV_OUT"; then
    echo "FAIL: [$RESOURCE: env=1] the refusal leaked an env-store VALUE/NAME beyond the count -- names-only discipline broken." >&2
    FAIL=1
  fi

  PSREADFAIL_OUT="$(FAKE_DOCKER_PS_FAIL=1 run_scenario "$RESOURCE: ps-read-fails, refuses unknown" 1 clean 0 0 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: ps-read-fails" "${PSREADFAIL_OUT:-}" "containers=unknown" || FAIL=1

  IMAGESREADFAIL_OUT="$(FAKE_DOCKER_IMAGES_FAIL=1 run_scenario "$RESOURCE: images-read-fails, refuses unknown" 1 clean 0 0 "$RESOURCE" "$NETVAR")" || FAIL=1
  assert_output_contains "$RESOURCE: images-read-fails" "${IMAGESREADFAIL_OUT:-}" "images=unknown" || FAIL=1

  CREATEHAPPY_OUT="$(run_scenario "$RESOURCE: create-happy, absent, apply succeeds" 0 absent 0 0 "$RESOURCE" "$NETVAR" --apply)" || FAIL=1
  assert_output_contains "$RESOURCE: create-happy" "${CREATEHAPPY_OUT:-}" "application created" || FAIL=1
  if [[ -n "${CREATEHAPPY_OUT:-}" ]] && ! grep -qF "does not exist" <<<"$CREATEHAPPY_OUT"; then
    echo "FAIL: [$RESOURCE: create-happy] never printed the 'does not exist -- will be created fresh' preflight line -- the ABSENT branch may not have actually fired." >&2
    FAIL=1
  fi
  if [[ -n "${CREATEHAPPY_OUT:-}" ]] && ! grep -qF "$NETVAR set and byte-exact read-back verified" <<<"$CREATEHAPPY_OUT"; then
    echo "FAIL: [$RESOURCE: create-happy] did not confirm $NETVAR's own byte-exact readback -- the per-resource network-var name may not actually be wired through." >&2
    FAIL=1
  fi
done

# 8. UNKNOWN-NAME -- refuses BEFORE any SSH/API call. No fake ssh/curl on
#    PATH at all for this scenario: if the script somehow reached a network
#    call, the REAL ssh/curl on this runner would either hang or fail with
#    a connection error, not the expected structural refusal -- proving the
#    refusal happens at argument-validation time, not merely "eventually".
UNKNOWN_LOG="$WORK/unknown.$$"
set +e
BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
  bash "$PROVISION_WORKER_SH" pfin-does-not-exist < /dev/null > "$UNKNOWN_LOG" 2>&1
UNKNOWN_RC=$?
set -e
if [[ "$UNKNOWN_RC" != "2" ]]; then
  echo "FAIL: [unknown-name refusal] expected exit 2, got $UNKNOWN_RC" >&2
  cat "$UNKNOWN_LOG" >&2
  FAIL=1
else
  if ! grep -qF "unrecognised resource-name" "$UNKNOWN_LOG"; then
    echo "FAIL: [unknown-name refusal] exited 2 but did not name the refusal -- failing closed on the wrong message." >&2
    FAIL=1
  else
    echo "OK: [unknown-name refusal] exit 2, refused before any SSH/API call." >&2
  fi
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more provision-worker.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision-worker.sh strike-proofs passed (3 resources x 7 scenarios + unknown-name refusal)."
exit 0
