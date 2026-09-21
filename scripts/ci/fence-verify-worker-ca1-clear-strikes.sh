#!/usr/bin/env bash
#
# fence-verify-worker-ca1-clear-strikes.sh -- offline strike-proof for
# scripts/verify-worker-ca1-clear.sh, the die-level post-deploy CA-1
# container-env gate wired into provision.sh's run_deploy_workers()
# (Sec ruling, PR #862 review, option C). REWRITTEN (CA-1 identity
# review, run-9 stop 2026-09-21) after the ORIGINAL version of both the
# target script and this fence modeled a literal <container-name>
# lookup -- run 9 measured that Coolify names the real container
# `<service>-<uuid>-<timestamp>`, not the bare compose service name, so
# the live script died "container not found" on a deploy that had
# actually succeeded, and this fence stayed green through that bug
# because its OWN fixture modeled the same wrong assumption ("fixture
# restates the lie"). The target script now COPIES deploy-app.sh's WHOLE
# resolution mechanism (name/uuid -> Coolify application uuid, THEN
# `docker compose --project-name <uuid> ps -q <service>` -> the one
# RUNNING container, refusing on zero or more than one match); this
# fence now drives that same two-stage resolution via a fake `ssh`
# (rewrites the /root/.pfin path, PATH-shadows curl + docker, same shape
# as fence-deploy-app-strikes.sh) and
# tests/fixtures/ci/verify-worker-ca1-clear/fake-curl for the Coolify API
# leg. Runs entirely without a live box; the target script itself is
# never modified or made aware this exists.
#
# Scenarios:
#   1. CLEAN -- resolves an application by NAME, then its ONE running
#      container (id in the real `<service>-<uuid>-<timestamp>` shape,
#      Sec req 2's POSITIVE leg -- team-lead's own measured example:
#      provider-sync-hmjeuhdaolhw8tlz3qi6lopi-194853542981), whose env
#      carries no non-empty COOLIFY_FQDN/COOLIFY_URL -> exit 0.
#   2. ROUTE-SIGNAL-PRESENT (Sec req 3: strike-prove the check CAN
#      catch a real finding, not just that a green run exists) --
#      same resolution succeeds, but the container's env carries a
#      non-empty COOLIFY_FQDN -> exit 1, names "CA-1 FINDING" and the
#      offending var.
#   3. RESOURCE-NOT-FOUND (Sec req 2's NEGATIVE leg) -- the queried
#      name matches ZERO Coolify applications -- models a caller
#      passing the bare compose SERVICE name as if it were the
#      application's Coolify NAME (the shape of the original bug's own
#      wrong assumption) -> exit 2, "found 0".
#   4. RESOURCE-AMBIGUOUS -- the queried name matches TWO applications
#      -> exit 2, "found 2", never silently picking one.
#   5. NO-RUNNING-CONTAINER -- application resolves, but `docker
#      compose ... ps -q <service>` returns nothing running -> exit 2,
#      "no running container found".
#   6. AMBIGUOUS-CONTAINERS -- TWO running containers match the compose
#      service -> exit 2, "AMBIGUOUS", "never... the first of several"
#      (Sec's own phrase, req 1) named in the refusal text.
#   7. MISSING-SERVICE-FLAG -- --service omitted entirely -> exit 2,
#      names --service as required, before any network call.
#   8. BOX-UNREACHABLE -- ssh's own reachability probe fails -> exit 2.
#   9. BOX-IP-MISSING -- BOX_IP unset -> exit 2.
#  10. STAGE-3-READ-FAILS (Sec F-1, CA-1 identity review -- the merge
#      condition this rewrite exists to close) -- resolution succeeds
#      (stages 1+2), but `docker exec <container> env` ITSELF fails on
#      the box (container died between resolution and this check, a
#      docker daemon hiccup, a transient ssh drop) -> MUST exit non-zero
#      and MUST NOT print "CA-1 clear... confirmed" -- the exact
#      fail-open the OLD `2>/dev/null || true` form let through
#      (a failed read and a clean "no match" both came back empty).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_SH="$REPO_ROOT/scripts/verify-worker-ca1-clear.sh"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/verify-worker-ca1-clear"
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "fake-token-do-not-leak" > "$FAKE_ROOT_PFIN/coolify.env"

# The real container-id shape team-lead measured on the box, run 9:
# `provider-sync-<uuid>-<timestamp>`. Used as the DEFAULT id the fake
# compose-ps/inspect chain resolves to, so the CLEAN scenario proves
# resolution succeeds against exactly this shape, not a bare literal
# service name (Sec req 2's positive leg).
REAL_SHAPE_CID="provider-sync-hmjeuhdaolhw8tlz3qi6lopi-194853542981"

# Fake `docker` -- the compose-resolution mechanism COPIED from
# deploy-app.sh (see that script's own fake docker in
# fence-deploy-app-strikes.sh for the precedent this mirrors).
#   `docker compose --project-name <uuid> ps -q <service>` -- prints
#     $FAKE_COMPOSE_CIDS (space-separated container ids; default the
#     one real-shaped id above; "" for zero/none-running, two ids for
#     the ambiguous scenario).
#   `docker inspect --format '...State.Running...' <id>` -- reports
#     every id it's given as RUNNING (same as fence-deploy-app-
#     strikes.sh's own fake: the compose-ps mock above only returns ids
#     meant to look running).
#   `docker exec <id> env | grep -E '...' || true` -- prints
#     $FAKE_ROUTE_SIGNAL verbatim (empty by default -- clean).
cat > "$FAKE_BIN/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == "compose "*"ps -q"* ]]; then
  for cid in \${FAKE_COMPOSE_CIDS-$REAL_SHAPE_CID}; do
    echo "\$cid"
  done
  exit 0
fi
if [[ "\$*" == *"inspect"* && "\$*" == *"State.Running"* ]]; then
  cid="\${*: -1}"
  printf 'true\t%s\t2026-09-21T19:48:53Z\n' "\$cid"
  exit 0
fi
if [[ "\$*" == *"exec"* && "\$*" == *" env"* ]]; then
  if [[ "\${FAKE_EXEC_ENV_FAILS:-0}" == "1" ]]; then
    echo "Error response from daemon: Container \$2 is not running" >&2
    exit 1
  fi
  printf '%s' "\${FAKE_ROUTE_SIGNAL:-}"
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker"

# Same fake `ssh` shape as fence-deploy-app-strikes.sh -- rewrites the
# /root/.pfin path this repo's scripts hardcode to this fixture's own
# throwaway temp dir, then PATH-shadows curl+docker for whatever runs
# inside the remote `bash -s` stream.
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# Exact-match on the LAST arg, never a "\$*" substring check -- a
# substring check for the bare "ssh ... true" reachability probe also
# matches any unrelated command ENDING in "|| true" (this script's own
# exec-env check does: "docker exec \\\$CONTAINER env | grep ... || true"),
# which would silently short-circuit that call to the reachable/no-op
# branch and never invoke docker at all -- the exact bug class this
# repo's own fence-provision-worker-strikes.sh fake ssh was fixed for
# once already (a different fake ssh, same failure shape). Caught here
# by re-deriving from first principles rather than copying fence-deploy-
# app-strikes.sh's substring form verbatim (that fence's own commands
# never happen to end in "|| true", so it never needed this fix).
LAST="\${@: -1}"
if [[ "\$LAST" == "true" ]]; then
  if [[ "\${FAKE_UNREACHABLE:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "\$*" == *"test -s /root/.pfin/coolify.env"* ]]; then
  exit 0
fi
if [[ "\$LAST" == "-s" || "\$LAST" == *" bash -s" ]]; then
  CMDLINE="\$LAST"
  [[ "\$CMDLINE" == "-s" ]] && CMDLINE="bash -s"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\${FAKE_CURL_LOG:-}" FAKE_CURL_MODE="\${FAKE_CURL_MODE:-}" \\
    FAKE_APP_NAME="\${FAKE_APP_NAME:-}" FAKE_APP_UUID="\${FAKE_APP_UUID:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_COMPOSE_CIDS="\${FAKE_COMPOSE_CIDS-$REAL_SHAPE_CID}" FAKE_ROUTE_SIGNAL="\${FAKE_ROUTE_SIGNAL:-}" \\
  FAKE_EXEC_ENV_FAILS="\${FAKE_EXEC_ENV_FAILS:-0}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  local desc="$1" expect_exit="$2"; shift 2
  set +e
  BOX_IP="${BOX_IP_OVERRIDE:-127.0.0.1}" AUTOMATION_KEY=/dev/null \
    PATH="$FAKE_BIN:$PATH" \
    bash "$TARGET_SH" "$@" < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  cat "$WORK/out.$$"
  return 0
}

FAIL=0

# 1. CLEAN -- positive leg, real <service>-<uuid>-<ts> shape.
CLEAN_OUT="$(run_scenario "clean: resolves real-shaped container, no route signal" 0 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${CLEAN_OUT:-}" ]]; then
  grep -qF "CA-1 clear, post-deploy, confirmed" <<<"$CLEAN_OUT" || { echo "FAIL: [clean] did not confirm CA-1 clear." >&2; FAIL=1; }
  grep -qF "$REAL_SHAPE_CID" <<<"$CLEAN_OUT" || { echo "FAIL: [clean] resolved container id was not the real-shaped one -- resolution did not run, or ran against a fallback." >&2; FAIL=1; }
fi

# 2. ROUTE-SIGNAL-PRESENT -- the finding this script exists to catch (Sec req 3).
SIGNAL_OUT="$(FAKE_ROUTE_SIGNAL='COOLIFY_FQDN=http://abc.1.2.3.4.sslip.io' \
  run_scenario "route-signal-present: refuses, names CA-1" 1 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${SIGNAL_OUT:-}" ]]; then
  grep -qF "CA-1 FINDING" <<<"$SIGNAL_OUT" || { echo "FAIL: [route-signal-present] refusal did not name CA-1 explicitly." >&2; FAIL=1; }
  grep -qF "COOLIFY_FQDN" <<<"$SIGNAL_OUT" || { echo "FAIL: [route-signal-present] refusal did not name the offending var." >&2; FAIL=1; }
fi

# 3. RESOURCE-NOT-FOUND -- negative leg (Sec req 2): the literal
#    compose-service-name-as-if-it-were-the-app-name shape resolves to
#    ZERO applications.
NOTFOUND_OUT="$(FAKE_CURL_MODE=no-match \
  run_scenario "resource-not-found: literal-name lookup refused" 2 provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${NOTFOUND_OUT:-}" ]] && ! grep -qF "found 0" <<<"$NOTFOUND_OUT"; then
  echo "FAIL: [resource-not-found] refusal did not name the zero-match count." >&2
  FAIL=1
fi

# 4. RESOURCE-AMBIGUOUS
AMBIG_APP_OUT="$(FAKE_CURL_MODE=ambiguous \
  run_scenario "resource-ambiguous: two applications match, refuses" 2 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${AMBIG_APP_OUT:-}" ]] && ! grep -qF "found 2" <<<"$AMBIG_APP_OUT"; then
  echo "FAIL: [resource-ambiguous] refusal did not name the two-match count." >&2
  FAIL=1
fi

# 5. NO-RUNNING-CONTAINER
NORUN_OUT="$(FAKE_COMPOSE_CIDS="" \
  run_scenario "no-running-container: refuses" 2 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${NORUN_OUT:-}" ]] && ! grep -qF "no running container found" <<<"$NORUN_OUT"; then
  echo "FAIL: [no-running-container] refusal did not name the missing container." >&2
  FAIL=1
fi

# 6. AMBIGUOUS-CONTAINERS -- Sec's own phrase, req 1: "never take the first of several".
AMBIG_CID_OUT="$(FAKE_COMPOSE_CIDS="$REAL_SHAPE_CID provider-sync-hmjeuhdaolhw8tlz3qi6lopi-999999999999" \
  run_scenario "ambiguous-containers: refuses, never picks one" 2 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${AMBIG_CID_OUT:-}" ]]; then
  grep -qF "AMBIGUOUS" <<<"$AMBIG_CID_OUT" || { echo "FAIL: [ambiguous-containers] refusal did not say AMBIGUOUS." >&2; FAIL=1; }
  grep -qF "never 'the first of several'" <<<"$AMBIG_CID_OUT" || { echo "FAIL: [ambiguous-containers] refusal did not echo Sec's own 'never the first of several' phrasing." >&2; FAIL=1; }
fi

# 7. MISSING-SERVICE-FLAG -- new precondition specific to the rewritten CLI shape.
run_scenario "missing-service-flag: refuses before any network call" 2 pfin-provider-sync >/dev/null || FAIL=1

# 8. BOX-UNREACHABLE
FAKE_UNREACHABLE=1 run_scenario "box-unreachable: refuses" 2 pfin-provider-sync --service provider-sync >/dev/null || FAIL=1

# 9. BOX-IP-MISSING
set +e
AUTOMATION_KEY=/dev/null PATH="$FAKE_BIN:$PATH" bash "$TARGET_SH" pfin-provider-sync --service provider-sync < /dev/null > "$WORK/out-noip.$$" 2>&1
NOIP_RC=$?
set -e
if [[ "$NOIP_RC" != 2 ]]; then
  echo "FAIL: [box-ip-missing] expected exit 2, got $NOIP_RC" >&2
  cat "$WORK/out-noip.$$" >&2
  FAIL=1
else
  echo "OK: [box-ip-missing] exit 2 as expected." >&2
fi

# 10. STAGE-3-READ-FAILS -- Sec F-1, the merge condition this rewrite
#     exists to close. Resolution succeeds; `docker exec ... env`
#     itself fails on the box -- must NOT be treated the same as a
#     clean "no match" (the OLD `2>/dev/null || true` form's fail-open).
READFAIL_OUT="$(FAKE_EXEC_ENV_FAILS=1 \
  run_scenario "stage-3-read-fails: refuses, never prints the clear message" 2 pfin-provider-sync --service provider-sync)" || FAIL=1
if [[ -n "${READFAIL_OUT:-}" ]]; then
  grep -qF "READ FAILURE" <<<"$READFAIL_OUT" || { echo "FAIL: [stage-3-read-fails] refusal did not name it as a read failure." >&2; FAIL=1; }
  grep -qF "CA-1 clear" <<<"$READFAIL_OUT" && { echo "FAIL: [stage-3-read-fails] the fail-open message ('CA-1 clear') is STILL present alongside the refusal -- this is exactly the property F-1 exists to remove." >&2; FAIL=1; }
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more verify-worker-ca1-clear.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all verify-worker-ca1-clear.sh strike-proofs passed."
exit 0
