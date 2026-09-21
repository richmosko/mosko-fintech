#!/usr/bin/env bash
#
# fence-verify-worker-ca1-clear-strikes.sh -- offline strike-proof for
# scripts/verify-worker-ca1-clear.sh, the die-level post-deploy CA-1
# container-env gate wired into provision.sh's run_deploy_workers()
# (Sec ruling, PR #862 review, option C). Runs entirely without a live
# box: a fake `ssh` PATH-shadows every remote call this script makes
# (reachability probe, `docker inspect`, `docker exec ... env`), same
# shape as this repo's other offline strike-proofs. The target script
# itself is never modified or made aware this exists.
#
# Scenarios:
#   1. CLEAN         -- container exists, its env carries no non-empty
#      COOLIFY_FQDN/COOLIFY_URL -> exit 0, "CA-1 clear, post-deploy,
#      confirmed".
#   2. ROUTE-SIGNAL-PRESENT (the finding this script exists to catch)
#      -- container exists, env carries a non-empty COOLIFY_FQDN ->
#      exit 1, names "CA-1 FINDING" and the offending var name(s).
#   3. CONTAINER-NOT-FOUND -- `docker inspect` on the named container
#      fails -> exit 2, names the container.
#   4. BOX-UNREACHABLE -- ssh's own reachability probe fails -> exit 2.
#   5. BOX-IP-MISSING  -- BOX_IP unset -> exit 2.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_SH="$REPO_ROOT/scripts/verify-worker-ca1-clear.sh"
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"

# Fake `ssh` -- the only remote surface this target script has.
#   plain reachability probe (`ssh ... true`) -- succeeds unless
#     $FAKE_UNREACHABLE=1.
#   `docker inspect <container>` -- succeeds (container "found") unless
#     $FAKE_CONTAINER_MISSING=1.
#   `docker exec <container> env | grep -E '...' || true` -- reports
#     $FAKE_ROUTE_SIGNAL verbatim (empty by default -- clean).
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LAST="\${@: -1}"
if [[ "\$LAST" == "true" ]]; then
  if [[ "\${FAKE_UNREACHABLE:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "\$LAST" == *"docker inspect"* ]]; then
  if [[ "\${FAKE_CONTAINER_MISSING:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi
if [[ "\$LAST" == *"docker exec"*"env"* ]]; then
  printf '%s' "\${FAKE_ROUTE_SIGNAL:-}"
  exit 0
fi
exit 0
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

# 1. CLEAN
CLEAN_OUT="$(run_scenario "clean: no route signal" 0 provider-sync)" || FAIL=1
if [[ -n "${CLEAN_OUT:-}" ]] && ! grep -qF "CA-1 clear, post-deploy, confirmed" <<<"$CLEAN_OUT"; then
  echo "FAIL: [clean] did not confirm CA-1 clear." >&2
  FAIL=1
fi

# 2. ROUTE-SIGNAL-PRESENT -- the finding.
SIGNAL_OUT="$(FAKE_ROUTE_SIGNAL='COOLIFY_FQDN=http://abc.1.2.3.4.sslip.io' \
  run_scenario "route-signal-present: refuses" 1 provider-sync)" || FAIL=1
if [[ -n "${SIGNAL_OUT:-}" ]] && ! grep -qF "CA-1 FINDING" <<<"$SIGNAL_OUT"; then
  echo "FAIL: [route-signal-present] refusal did not name CA-1 explicitly." >&2
  FAIL=1
fi
if [[ -n "${SIGNAL_OUT:-}" ]] && ! grep -qF "COOLIFY_FQDN" <<<"$SIGNAL_OUT"; then
  echo "FAIL: [route-signal-present] refusal did not name the offending var." >&2
  FAIL=1
fi

# 3. CONTAINER-NOT-FOUND
NOTFOUND_OUT="$(FAKE_CONTAINER_MISSING=1 \
  run_scenario "container-not-found: refuses" 2 provider-sync)" || FAIL=1
if [[ -n "${NOTFOUND_OUT:-}" ]] && ! grep -qF "not found" <<<"$NOTFOUND_OUT"; then
  echo "FAIL: [container-not-found] did not name the missing container." >&2
  FAIL=1
fi

# 4. BOX-UNREACHABLE
FAKE_UNREACHABLE=1 run_scenario "box-unreachable: refuses" 2 provider-sync >/dev/null || FAIL=1

# 5. BOX-IP-MISSING
set +e
AUTOMATION_KEY=/dev/null PATH="$FAKE_BIN:$PATH" bash "$TARGET_SH" provider-sync < /dev/null > "$WORK/out-noip.$$" 2>&1
NOIP_RC=$?
set -e
if [[ "$NOIP_RC" != 2 ]]; then
  echo "FAIL: [box-ip-missing] expected exit 2, got $NOIP_RC" >&2
  cat "$WORK/out-noip.$$" >&2
  FAIL=1
else
  echo "OK: [box-ip-missing] exit 2 as expected." >&2
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more verify-worker-ca1-clear.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all verify-worker-ca1-clear.sh strike-proofs passed."
exit 0
