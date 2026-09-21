#!/usr/bin/env bash
#
# fence-supabase-stack-healthy-check-strikes.sh -- offline strike-proof for
# scripts/provision-supabase-stack.sh's check_stack_already_healthy()
# function and its own db-data-volume three-way dispatcher (team-lead
# follow-up, live --dry-run, 2026-09-20 -- a stack provisioned 2026-09-09,
# fully healthy, hit the OLD unconditional "volume exists -> refuse" guard
# on a plain re-run, breaking provision.sh's own re-run = no-op contract).
#
# 🔒 SECURITY-SENSITIVE -- Sec joint-review mandatory: this is a CONTROL
# CHANGE to a poisoned-volume safety guard, not a new feature. The guard
# still exists and still refuses whenever health cannot be confirmed; this
# fence is the golden-test proof that the new "healthy" branch is neither
# too loose (must still refuse when any of the four probes fails) nor
# unreachable (must actually skip the deploy when genuinely healthy).
#
# ⚠ EXTRACTION, NOT DUPLICATION -- this fence does NOT re-run the whole
# 1200+-line target script (which would require faking Coolify project/
# environment/application resolution, secret minting, and mount
# materialization -- none of that is what changed here). It extracts the
# REAL check_stack_already_healthy() function (now defined early, right
# after jqp(), so --check-healthy can call it before any of that
# resolution logic runs) AND the real db-data-volume dispatcher (still in
# its original, deep --apply-path location) VERBATIM from the live
# script, between two marker-comment pairs (`FENCE-EXTRACT-FUNC-BEGIN/
# -END` and `FENCE-EXTRACT-DISPATCH-BEGIN/-END`), concatenated -- byte-
# for-byte what ships, never a hand-copied stand-in that could silently
# drift from the real logic. If either marker pair is moved or removed,
# this fence FAILS CLOSED (extraction produces nothing / a suspiciously
# short block) rather than silently testing stale text. --check-healthy
# itself is NOT exercised end to end here (that would need the same
# faked project/environment/application preflight this fence otherwise
# avoids) -- a structural pin below only proves the wiring exists.
#
# `sshx` is a plain bash FUNCTION here (not a PATH-shadowed binary --
# the extracted snippet is sourced directly into a controlled subshell,
# never invoked as its own process), matching each of the four probes'
# own distinctive embedded-command text.
#
# Scenarios:
#   1. NO-VOLUME-DEPLOYS -- no db-data volume at all -> NEED_DEPLOY=1, no
#      die -- the ordinary first-deploy path, unaffected by this change.
#   2. HEALTHY-VOLUME-SKIPS-DEPLOY -- volume exists, all four probes pass
#      -> NEED_DEPLOY=0, no die -- "already provisioned and healthy,
#      nothing to deploy". The live defect this fixes.
#   3. UNHEALTHY-VOLUME-REFUSES (team-lead's own named strike) -- volume
#      exists, the init-marker probe (4/4) reports the four roles have NO
#      password set (the exact "bogus mount" signature) -> die, naming
#      "NOT confirmed healthy". The guard must still fire -- this branch
#      is not a loosening.
#   4. CONTAINERS-NOT-ALL-HEALTHY -- probe (1/4) alone fails (5/7) -> die,
#      isolated from the other three probes (all of which would pass).
#   5. GATEWAY-NOT-200 -- probe (2/4) alone fails -> die, isolated.
#   6. WRONG-PG-VERSION -- probe (3/4) alone fails -> die, isolated.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_SH="$REPO_ROOT/scripts/provision-supabase-stack.sh"
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Two extractions, concatenated: check_stack_already_healthy() now lives
# EARLY in the target script (right after jqp(), before the main
# Preflight step -- so the --check-healthy flag can call it without
# running project/environment/application creation logic) and the
# db-data-volume dispatcher that calls it stays in its ORIGINAL location,
# deep in the --apply path. Both are extracted VERBATIM, byte-for-byte
# what ships, never hand-duplicated.
EXTRACT="$WORK/extracted.sh"
{
  sed -n '/# FENCE-EXTRACT-FUNC-BEGIN: check-stack-already-healthy-func/,/# FENCE-EXTRACT-FUNC-END: check-stack-already-healthy-func/p' "$TARGET_SH"
  sed -n '/# FENCE-EXTRACT-DISPATCH-BEGIN: check-stack-already-healthy-dispatch/,/# FENCE-EXTRACT-DISPATCH-END: check-stack-already-healthy-dispatch/p' "$TARGET_SH"
} | grep -v '^# FENCE-EXTRACT-\(FUNC\|DISPATCH\)-\(BEGIN\|END\)' > "$EXTRACT"
LINES="$(wc -l < "$EXTRACT" | tr -d ' ')"
if [[ ! -s "$EXTRACT" || "$LINES" -lt 30 ]]; then
  echo "FATAL: extraction from $TARGET_SH produced $LINES line(s) -- the FENCE-EXTRACT-FUNC/-DISPATCH markers may have moved or been removed. Failing closed rather than testing stale/empty text." >&2
  exit 2
fi
bash -n "$EXTRACT" || { echo "FATAL: extracted block does not parse as valid bash" >&2; exit 2; }

# Structural pin: --check-healthy must actually call the extracted
# function, not a divergent re-implementation (not exercised end to end
# above -- that flag's own early-exit path would need the full BOX_IP/
# SSH-reachability/project-environment-application preflight faked too,
# out of scope for this narrow fence; this pin at least proves the wiring
# exists).
if ! grep -qE 'CHECK_HEALTHY -eq 1.*check_stack_already_healthy|check_stack_already_healthy' "$TARGET_SH"; then
  echo "FATAL: --check-healthy's own block no longer appears to call check_stack_already_healthy() -- structural pin failed" >&2
  exit 2
fi
if ! grep -q -- '--check-healthy) CHECK_HEALTHY=1' "$TARGET_SH"; then
  echo "FATAL: --check-healthy flag is no longer parsed -- structural pin failed" >&2
  exit 2
fi

FAIL=0

# run_case <desc> <expect_rc> <expect_need_deploy-or-empty> <containers> <gw_status> <pgver> <init_state> <volume_exists>
#
# ⚠ The fake `sshx()` below reads FAKE_-prefixed variable names, never
# bare names like `containers`/`gw_status`/`pgver`/`init_state` --
# check_stack_already_healthy() (the sourced, real function) declares
# its OWN `local containers`/`gw_status`/`pgver`/`init_state` internally,
# and bash resolves an unset-local name by walking the ACTIVE CALL
# STACK, not lexical/definition-time scope: since that function sits
# BETWEEN this harness and sshx() on the real call stack once sourced
# and invoked, a same-named local there would shadow this harness's own
# variable of the same name -- caught by a strike against this fence
# ITSELF during development (every scenario read 0 containers regardless
# of what was configured, traced to exactly this collision). Prefixing
# these config variables avoids the collision outright rather than
# relying on bash's scoping rules never changing shape again.
run_case() {
  local desc="$1" expect_rc="$2" expect_need_deploy="$3" FAKE_CONTAINERS="$4" FAKE_GW_STATUS="$5" FAKE_PGVER="$6" FAKE_INIT_STATE="$7" FAKE_VOLUME_EXISTS="$8"
  local out="$WORK/out.$$.$RANDOM"
  set +e
  (
    set -euo pipefail
    # APP_UUID and every function below are consumed by the dynamically-
    # sourced $EXTRACT file, invisible to shellcheck's static analysis --
    # both findings are false positives inherent to this fence's own
    # "extract and source the real code" technique, not unused code.
    # shellcheck disable=SC2034
    APP_UUID="test-stack-uuid-1234"
    # shellcheck disable=SC2329
    ok()   { printf '  ok  %s\n' "$*"; }
    # shellcheck disable=SC2329
    info() { printf '      %s\n' "$*"; }
    # shellcheck disable=SC2329
    die()  { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
    # shellcheck disable=SC2329
    step() { printf '\n=== %s ===\n' "$*"; }
    # shellcheck disable=SC2329
    sshx() {
      local cmd="$1"
      case "$cmd" in
        *"docker volume ls -q --filter name="*)
          # `if` not `&&` -- a bare `[[ ... ]] && echo` whose condition is
          # FALSE makes the WHOLE case-arm's (and so sshx()'s own) exit
          # status 1, which kills the real script's own
          # `EXISTING_DB_VOLUME="$(sshx ...)"` assignment under `set -e`
          # before it ever reads the (correctly empty) result -- caught by
          # a strike against this fence ITSELF (the no-volume-deploys
          # scenario failed with no output at all, not the expected
          # "safe to deploy" line).
          if [[ "$FAKE_VOLUME_EXISTS" == "1" ]]; then echo "fake-db-data-volume-id"; fi
          ;;
        *"filter 'health=healthy'"*)
          local fi=0
          while [[ $fi -lt $FAKE_CONTAINERS ]]; do echo "container$fi"; fi=$((fi + 1)); done
          ;;
        *"exec -T supavisor curl"*)
          printf '%s' "$FAKE_GW_STATUS"
          ;;
        *"show server_version;"*)
          printf '%s' "$FAKE_PGVER"
          ;;
        *"pg_authid"*)
          printf '%s\n' "$FAKE_INIT_STATE"
          ;;
        *)
          echo "FAKE sshx: unrecognised command in this fence's own harness: $cmd" >&2
          return 1
          ;;
      esac
    }
    # shellcheck source=/dev/null
    source "$EXTRACT"
    echo "RESULT_NEED_DEPLOY=$NEED_DEPLOY"
  ) > "$out" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" != "$expect_rc" ]]; then
    echo "FAIL: [$desc] expected exit $expect_rc, got $rc" >&2
    cat "$out" >&2
    FAIL=1
    return 1
  fi
  if [[ -n "$expect_need_deploy" ]] && ! grep -q "^RESULT_NEED_DEPLOY=$expect_need_deploy$" "$out"; then
    echo "FAIL: [$desc] expected NEED_DEPLOY=$expect_need_deploy, not found in output" >&2
    cat "$out" >&2
    FAIL=1
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  cat "$out"
  return 0
}

HEALTHY_ROLES="authenticator:true
pgbouncer:true
supabase_auth_admin:true
supabase_functions_admin:true"
UNHEALTHY_ROLES="authenticator:false
pgbouncer:false
supabase_auth_admin:false
supabase_functions_admin:false"

# 1. NO-VOLUME-DEPLOYS
OUT1="$(run_case "no-volume-deploys" 0 1 7 200 17 "$HEALTHY_ROLES" 0)" || FAIL=1
if [[ -n "${OUT1:-}" ]]; then
  echo "$OUT1" | grep -q "no pre-existing db-data volume -- safe to deploy" || { echo "FAIL: [no-volume-deploys] did not print the safe-to-deploy line" >&2; FAIL=1; }
fi

# 2. HEALTHY-VOLUME-SKIPS-DEPLOY -- the live defect this fixes
OUT2="$(run_case "healthy-volume-skips-deploy" 0 0 7 200 17 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT2:-}" ]]; then
  echo "$OUT2" | grep -q "stack already provisioned and healthy -- nothing to deploy" || { echo "FAIL: [healthy-volume-skips-deploy] did not print the already-healthy line" >&2; FAIL=1; }
fi

# 3. UNHEALTHY-VOLUME-REFUSES (team-lead's own named strike) -- the four
#    role-password markers absent, the exact "bogus mount" signature.
OUT3="$(run_case "unhealthy-volume-refuses" 1 "" 7 200 17 "$UNHEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT3:-}" ]]; then
  echo "$OUT3" | grep -q "NOT confirmed healthy" || { echo "FAIL: [unhealthy-volume-refuses] die() message did not name 'NOT confirmed healthy'" >&2; FAIL=1; }
  echo "$OUT3" | grep -q "FAILED at (4/4)" || { echo "FAIL: [unhealthy-volume-refuses] did not isolate the failure to probe (4/4)" >&2; FAIL=1; }
fi

# 4. CONTAINERS-NOT-ALL-HEALTHY -- probe (1/4) alone fails.
OUT4="$(run_case "containers-not-all-healthy" 1 "" 5 200 17 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT4:-}" ]]; then
  echo "$OUT4" | grep -q "FAILED at (1/4)" || { echo "FAIL: [containers-not-all-healthy] did not isolate the failure to probe (1/4)" >&2; FAIL=1; }
fi

# 5. GATEWAY-NOT-200 -- probe (2/4) alone fails.
OUT5="$(run_case "gateway-not-200" 1 "" 7 503 17 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT5:-}" ]]; then
  echo "$OUT5" | grep -q "FAILED at (2/4)" || { echo "FAIL: [gateway-not-200] did not isolate the failure to probe (2/4)" >&2; FAIL=1; }
fi

# 6. WRONG-PG-VERSION -- probe (3/4) alone fails.
OUT6="$(run_case "wrong-pg-version" 1 "" 7 200 15 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT6:-}" ]]; then
  echo "$OUT6" | grep -q "FAILED at (3/4)" || { echo "FAIL: [wrong-pg-version] did not isolate the failure to probe (3/4)" >&2; FAIL=1; }
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more check_stack_already_healthy()/db-data-volume-dispatcher strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision-supabase-stack.sh healthy-check strike-proofs passed."
exit 0
