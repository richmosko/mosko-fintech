#!/usr/bin/env bash
#
# fence-provision-worker-strikes.sh -- offline strike-proof for
# scripts/provision-worker.sh's delete-if-empty-shell guard, its
# unknown-resource-name refusal, and (CA-1, run-8 stop, 2026-09-21) its
# default-domain-clear step. Copies scripts/ci/fence-provision-app-
# strikes.sh's own scenario shapes 1-7 verbatim (same fake ssh/docker,
# same tests/fixtures/ci/provision-worker/fake-curl shape), then adds
# scenarios 8-9a below (CA-1 domain-clear: ports_exposes success/
# failure, fqdn's measured-no-clear-path stop), then the unknown-name
# refusal -- this script's own new surface, renumbered as the CA-1
# scenarios were inserted ahead of it. Runs entirely without a live box
# or network.
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
#   8. CA1-PORTS-CLEAR-SUCCEEDS (mechanism confirmed live, team-lead,
#      2026-09-21) -- ports_exposes carries Coolify's default "80", fqdn
#      already clear -- the ports_exposes PATCH (the ONLY field this
#      script writes -- MEASURED: fqdn has no public-API clear path for
#      a dockercompose app, see provision-worker.sh's own header) clears
#      it, read-back confirms -- apply succeeds. Run once (pfin-
#      provider-sync only), not per-resource -- the logic is generic,
#      already proven table-driven by scenarios 1-7's own loop.
#   9. CA1-PORTS-PATCH-DOES-NOT-TAKE (defensive) -- the ports_exposes
#      PATCH 200s but the value never actually changes -- the read-back
#      must catch this and refuse, naming the still-present value.
#   9a. CA1-FQDN-TINKER-CLEAR-SUCCEEDS (Sec-ruled mechanism, PR #862
#      review) -- fqdn AND ports_exposes both SET (the true run-8
#      shape): ports_exposes clears via the API PATCH first, then the
#      tinker write clears fqdn end to end (write -> CLEARED echo ->
#      API read-back confirms) -- apply succeeds.
#   9b. CA1-FQDN-TINKER-DOES-NOT-REPORT-CLEARED -- the tinker write's
#      own echo comes back STILL_SET -- refuses immediately, naming
#      what was actually returned.
#   9c. CA1-FQDN-API-DRIFT-AFTER-CLEARED -- the tinker write reports
#      CLEARED but the immediate API read-back still shows fqdn SET --
#      refuses with a message distinct from 9b's (the write's own
#      self-report is not the same fact as the API agreeing with it).
#   9d. CA1-FQDN-CLEARED-STALE-CONTAINER-WARNS (Sec option C) -- fqdn
#      clears successfully, but a container already running for this
#      resource still carries the pre-clear COOLIFY_FQDN -- WARNS
#      (never dies, never silent) naming the exposure window, and still
#      exits 0 (expected/not-yet-redeployed state, not a failure of
#      this step -- the die-level assertion on this lives in
#      run_deploy_workers, post-deploy, see
#      scripts/verify-worker-ca1-clear.sh).
#   10a. STATE-PROVABLY-READ-ONLY (Sec run-11-stop requirement 3,
#      2026-09-21) -- --state against a resource with fqdn AND
#      ports_exposes both SET still exits 0 and reports both correctly,
#      even under fakes that fail closed on ANY non-GET curl call and
#      ANY non-api ssh command (docker ps/images, stack-network lookup,
#      tinker) -- "two GETs, zero writes" proven for THIS run, not
#      merely read off the code.
#   10b. STATE-ABSENT-RESOURCE-DIES -- --state against a resource that
#      was never created refuses (exit 1), never fabricates a state.
#   10. UNKNOWN-NAME    -- this script's OWN new surface, not present in
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
# CA-1 fqdn tinker write (Sec-ruled mechanism, PR #862 review). Reports
# CLEARED and touches $FAKE_FQDN_CLEAR_MARKER (a SEPARATE marker file
# from ports_exposes's own $FAKE_CLEAR_MARKER -- these are two
# independent mechanisms, API PATCH vs tinker write, and must not share
# a marker) unless $FAKE_TINKER_BROKEN=1 simulates the write not taking.
if [[ "$*" == *"tinker --execute"* && "$*" == *"fqdn = null"* ]]; then
  if [[ "${FAKE_TINKER_BROKEN:-0}" == "1" ]]; then
    echo "STILL_SET"
  else
    [[ -n "${FAKE_FQDN_CLEAR_MARKER:-}" ]] && touch "$FAKE_FQDN_CLEAR_MARKER" 2>/dev/null
    echo "CLEARED"
  fi
  exit 0
fi
# Running-container resolution for the post-tinker-write WARNING path
# (Sec option C) -- $FAKE_EXISTING_CID controls whether a container is
# reported as currently running (empty = none, the common no-container-
# yet case).
if [[ "$*" == *"ps --filter"* && "$*" == *"status=running"* && "$*" == *"--format"*"{{.ID}}"* ]]; then
  printf '%s' "${FAKE_EXISTING_CID:-}"
  exit 0
fi
# `docker exec <cid> env | grep ...` -- the stale-route-signal read for
# the same WARNING path. $FAKE_STALE_ROUTE_SIGNAL (empty by default --
# clean) is whatever the grep would have found on the box.
if [[ "$*" == *"exec"* && "$*" == *" env"* ]]; then
  printf '%s' "${FAKE_STALE_ROUTE_SIGNAL:-}"
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

# Same fake `ssh` shape as fence-provision-app-strikes.sh's own -- rewrites
# the /root/.pfin path, forwards FAKE_RESOURCE_NAME/FAKE_NETWORK_VAR (and,
# CA-1, FAKE_DEFAULT_FQDN/FAKE_DEFAULT_PORTS_EXPOSES/FAKE_CLEAR_MARKER/
# FAKE_CLEAR_BROKEN) through to the sub-shell so fake-curl sees them too.
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
    FAKE_DEFAULT_FQDN="\${FAKE_DEFAULT_FQDN:-}" FAKE_DEFAULT_PORTS_EXPOSES="\${FAKE_DEFAULT_PORTS_EXPOSES:-}" \\
    FAKE_CLEAR_MARKER="\${FAKE_CLEAR_MARKER:-}" FAKE_CLEAR_BROKEN="\${FAKE_CLEAR_BROKEN:-0}" \\
    FAKE_FQDN_CLEAR_MARKER="\${FAKE_FQDN_CLEAR_MARKER:-}" FAKE_FAIL_ON_WRITE="\${FAKE_FAIL_ON_WRITE:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
if [[ -n "\${FAKE_FAIL_ON_ANY_DOCKER_CALL:-}" ]]; then
  # --state provably-read-only proof, docker half (Sec run-11-stop
  # requirement 3): --state never resolves the stack network, never
  # runs the delete-guard's docker ps/images reads, never execs a
  # tinker write -- ALL of those go through this non-api-helper ssh
  # branch, so refusing here too (not just fake-curl's writes) proves
  # --state touches NEITHER surface, not just that it avoids POSTs.
  echo "FAKE ssh: a non-api command ran under FAKE_FAIL_ON_ANY_DOCKER_CALL -- --state must never reach docker/tinker at all" >&2
  exit 97
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_CONTAINER_COUNT="\$FAKE_CONTAINER_COUNT" FAKE_IMAGE_COUNT="\$FAKE_IMAGE_COUNT" \\
  FAKE_DOCKER_PS_FAIL="\${FAKE_DOCKER_PS_FAIL:-0}" FAKE_DOCKER_IMAGES_FAIL="\${FAKE_DOCKER_IMAGES_FAIL:-0}" \\
  FAKE_TINKER_BROKEN="\${FAKE_TINKER_BROKEN:-0}" FAKE_FQDN_CLEAR_MARKER="\${FAKE_FQDN_CLEAR_MARKER:-}" \\
  FAKE_EXISTING_CID="\${FAKE_EXISTING_CID:-}" FAKE_STALE_ROUTE_SIGNAL="\${FAKE_STALE_ROUTE_SIGNAL:-}" \\
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
  # CA-1 (run-8 stop, 2026-09-21): the fake-curl fixture's default GET
  # .../applications/<uuid> carries no fqdn/ports_exposes at all
  # ($FAKE_DEFAULT_FQDN/$FAKE_DEFAULT_PORTS_EXPOSES unset in this call),
  # so create-happy's own success ALSO exercises the "already clear,
  # nothing to do" branch of the new domain-clear step -- assert it
  # explicitly rather than only incidentally passing through it.
  if [[ -n "${CREATEHAPPY_OUT:-}" ]] && ! grep -qF "nothing to clear" <<<"$CREATEHAPPY_OUT"; then
    echo "FAIL: [$RESOURCE: create-happy] did not report the domain-clear step's 'nothing to clear' branch -- the CA-1 step may not be running at all." >&2
    FAIL=1
  fi
done

# 8. CA1-PORTS-CLEAR-SUCCEEDS (mechanism confirmed live, team-lead,
#    2026-09-21) -- ports_exposes carries Coolify's default "80", fqdn
#    already ABSENT/EMPTY (e.g. a resource that never had a domain
#    assigned in the first place) -- the ports_exposes PATCH clears it,
#    read-back confirms, apply succeeds. Only pfin-provider-sync run
#    here -- this logic is generic across the table, not resource-
#    specific (already proven generic by the shared network-var/
#    create-happy loop above); testing it three times would be the same
#    assertion three times, not new coverage.
CA1_MARKER="$WORK/ca1-clear-marker.$$"
rm -f "$CA1_MARKER"
CA1_CLEAR_OUT="$(FAKE_DEFAULT_PORTS_EXPOSES='80' FAKE_CLEAR_MARKER="$CA1_MARKER" \
  run_scenario "CA-1: ports_exposes default cleared, fqdn already clear, apply succeeds" 0 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: ports_exposes cleared" "${CA1_CLEAR_OUT:-}" "ports_exposes cleared via PATCH and byte-exact read-back verified not SET" || FAIL=1
assert_output_contains "CA-1: ports_exposes cleared" "${CA1_CLEAR_OUT:-}" "fqdn already EMPTY — nothing to clear" || FAIL=1
rm -f "$CA1_MARKER"

# 9. CA1-PORTS-PATCH-DOES-NOT-TAKE (defensive, not live-observed) -- the
#    ports_exposes PATCH 200s but the value never actually changes
#    ($FAKE_CLEAR_BROKEN=1) -- the read-back must catch this and refuse,
#    naming the still-present value. Never "probably fine."
CA1_BROKEN_OUT="$(FAKE_DEFAULT_PORTS_EXPOSES='80' FAKE_CLEAR_MARKER="$WORK/ca1-broken-marker.$$" FAKE_CLEAR_BROKEN=1 \
  run_scenario "CA-1: ports_exposes PATCH does not take, refuses" 1 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: ports_exposes PATCH does not take" "${CA1_BROKEN_OUT:-}" "measured working on provider-sync" || FAIL=1
if [[ -n "${CA1_BROKEN_OUT:-}" ]] && ! grep -qF "ports_exposes SET ('80')" <<<"$CA1_BROKEN_OUT"; then
  echo "FAIL: [CA-1: ports_exposes PATCH does not take] the refusal did not name the actual still-present ports_exposes value." >&2
  FAIL=1
fi

# 9a. CA1-FQDN-TINKER-CLEAR-SUCCEEDS (Sec-ruled mechanism, PR #862
#    review) -- fqdn AND ports_exposes both SET (the true run-8 default-
#    create shape): ports_exposes clears via the API PATCH first, then
#    the tinker write clears fqdn, reports CLEARED, and the API
#    read-back confirms -- apply succeeds end to end.
CA1_TINKER_OUT="$(FAKE_DEFAULT_FQDN='http://abc123.1.2.3.4.sslip.io' FAKE_DEFAULT_PORTS_EXPOSES='80' \
  FAKE_CLEAR_MARKER="$WORK/ca1-ports-marker.$$" FAKE_FQDN_CLEAR_MARKER="$WORK/ca1-fqdn-marker.$$" \
  run_scenario "CA-1: fqdn tinker-clear succeeds, ports_exposes cleared first" 0 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: fqdn tinker-clear succeeds" "${CA1_TINKER_OUT:-}" "ports_exposes cleared via PATCH and byte-exact read-back verified not SET" || FAIL=1
assert_output_contains "CA-1: fqdn tinker-clear succeeds" "${CA1_TINKER_OUT:-}" "fqdn cleared via tinker write and API read-back verified" || FAIL=1

# 9b. CA1-FQDN-TINKER-DOES-NOT-REPORT-CLEARED -- the tinker write's own
#    echo comes back STILL_SET (the model-layer write failed, or
#    firstOrFail() found no matching record) -- refuses immediately,
#    naming what was actually returned. Never treated as a soft warning.
CA1_TINKER_BROKEN_OUT="$(FAKE_DEFAULT_FQDN='http://abc123.1.2.3.4.sslip.io' FAKE_TINKER_BROKEN=1 \
  run_scenario "CA-1: fqdn tinker write does not report CLEARED, refuses" 1 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: fqdn tinker write does not report CLEARED" "${CA1_TINKER_BROKEN_OUT:-}" "did not report CLEARED" || FAIL=1

# 9c. CA1-FQDN-API-DRIFT-AFTER-CLEARED -- the tinker write DOES report
#    CLEARED, but the immediate API read-back still shows fqdn SET (a
#    cache, or DB/API drift) -- refuses, distinct message from 9b's
#    (the write's own self-report is not the same fact as the API
#    agreeing with it).
CA1_DRIFT_OUT="$(FAKE_DEFAULT_FQDN='http://abc123.1.2.3.4.sslip.io' FAKE_FQDN_CLEAR_MARKER="$WORK/nonexistent-dir-$$/marker" \
  run_scenario "CA-1: fqdn tinker reports CLEARED but API read-back still SET, refuses" 1 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: fqdn API drift" "${CA1_DRIFT_OUT:-}" "API/DB drift" || FAIL=1

# 9d. CA1-FQDN-CLEARED-STALE-CONTAINER-WARNS (Sec option C) -- fqdn
#    clears successfully, but a container is ALREADY running for this
#    resource carrying the pre-clear COOLIFY_FQDN -- must WARN (not
#    die, not silently pass) naming the exposure window, and the script
#    must still exit 0 (this is expected/not-yet-redeployed state, not
#    a failure of THIS step).
CA1_STALE_OUT="$(FAKE_DEFAULT_FQDN='http://abc123.1.2.3.4.sslip.io' FAKE_FQDN_CLEAR_MARKER="$WORK/ca1-fqdn-marker2.$$" \
  FAKE_EXISTING_CID='cid-stale-1' FAKE_STALE_ROUTE_SIGNAL='COOLIFY_FQDN=http://abc123.1.2.3.4.sslip.io' \
  run_scenario "CA-1: fqdn cleared, stale container warns, still succeeds" 0 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --apply)" || FAIL=1
assert_output_contains "CA-1: stale container warns" "${CA1_STALE_OUT:-}" "WARN" || FAIL=1
assert_output_contains "CA-1: stale container warns" "${CA1_STALE_OUT:-}" "still running with a non-empty route signal" || FAIL=1

# 10a. STATE-PROVABLY-READ-ONLY (Sec run-11-stop requirement 3): --state
#    against a resource that HAS a domain assigned (fqdn AND
#    ports_exposes both SET, the true default-create shape) must still
#    exit 0 and report the SET state correctly, even under fakes that
#    fail closed on ANY non-GET curl call (POST/PATCH/DELETE) and on
#    ANY non-api ssh command at all (the delete-guard's docker ps/
#    images reads, the stack-network lookup, a tinker write) --
#    together, "two GETs, zero writes" becomes a falsifiable claim about
#    THIS invocation, not just a description of what the code happens
#    to do today. Run against "clean" mode (the resource already
#    exists, resolved to OLD_APP_UUID) since --state dies on an absent
#    resource -- there is nothing to report state FOR.
STATE_READONLY_OUT="$(FAKE_FAIL_ON_WRITE=1 FAKE_FAIL_ON_ANY_DOCKER_CALL=1 \
  FAKE_DEFAULT_FQDN='http://abc123.1.2.3.4.sslip.io' FAKE_DEFAULT_PORTS_EXPOSES='80' \
  run_scenario "STATE: --state is provably read-only (fails closed on ANY write/docker call)" 0 clean 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --state)" || FAIL=1
assert_output_contains "STATE: provably read-only" "${STATE_READONLY_OUT:-}" "current state: fqdn=SET" || FAIL=1
assert_output_contains "STATE: provably read-only" "${STATE_READONLY_OUT:-}" "ports_exposes=SET" || FAIL=1

# 10b. STATE-ABSENT-RESOURCE-DIES -- --state against a resource that does
#    not exist at all must refuse (exit 1, this script's own `die()`),
#    never report a fabricated "ABSENT" state for something that was
#    never created. "absent" mode -> fake-curl's GET /applications
#    returns only the Supabase-stack app, never $RESOURCE_NAME.
STATE_ABSENT_OUT="$(run_scenario "STATE: absent resource dies, never fabricates a state" 1 absent 0 0 pfin-provider-sync PROVIDER_SYNC_STACK_NETWORK_NAME --state)" || FAIL=1
assert_output_contains "STATE: absent resource dies" "${STATE_ABSENT_OUT:-}" "does not exist" || FAIL=1

# 10. UNKNOWN-NAME -- refuses BEFORE any SSH/API call. No fake ssh/curl on
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

echo "OK: all provision-worker.sh strike-proofs passed (3 resources x 7 scenarios + CA-1 ports-clear-succeeds + CA-1 ports-patch-does-not-take + CA-1 fqdn-tinker-clear-succeeds + CA-1 fqdn-tinker-not-cleared + CA-1 fqdn-api-drift + CA-1 stale-container-warns + --state provably-read-only + --state absent-resource-dies + unknown-name refusal)."
exit 0
