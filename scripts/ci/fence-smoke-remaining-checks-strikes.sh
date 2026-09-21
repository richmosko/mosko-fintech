#!/usr/bin/env bash
#
# fence-smoke-remaining-checks-strikes.sh -- offline strike-proof for
# scripts/smoke-remaining-checks.sh (BACKLOG.md §7.36 item 81: CA-7/TZ-1/
# RLS-isolation/auth-login, docs/deployment-runbook.md §4.1 + archive
# §10). Runs entirely without a live box: a fake `ssh` rewrites the
# `/root/.pfin` path the script's remote driver hardcodes, then runs it
# locally with tests/fixtures/ci/smoke-remaining-checks/{fake-ssh,fake-
# docker,fake-curl,fake-nc} standing in for the real things --
# scripts/smoke-remaining-checks.sh itself is never modified or made
# aware this exists. Same strike shape as
# scripts/ci/fence-smoke-admission-endpoint-strikes.sh.
#
# Scenarios (one guard struck alone per scenario -- exactly one RED):
#    1. HAPPY-PATH -- every leg's happy-path fixture, domain assigned ->
#       overall MANUAL (exit 4): the email-confirmation round-trip is a
#       permanent ceiling once a domain exists, even when every
#       automatable sub-check passes -- this is the SPEC, not a partial
#       pass.
#    2. NO-DOMAIN -- sibling app carries no fqdn -> auth-login SKIPPED,
#       no other leg affected -> overall SKIPPED (exit 3).
#    3. CA7-N1-OPEN -- a negative-control port (5432) answers OPEN from
#       the operator's own machine -> CA-7 FAILED -> overall FAILED.
#    4. CA7-DOMAIN-ASSIGNED -- the Supabase stack app carries a live
#       fqdn -> CA-7 FAILED.
#    5. CA7-POSITIVE-GW-DOWN -- the sibling-container positive control's
#       api-gw probe returns "000" -> CA-7 FAILED (CA-4-shape network-
#       attachment failure).
#    6. CA7-POSITIVE-SUPAVISOR-DOWN -- the positive control's TCP connect
#       to supavisor is not OPEN -> CA-7 FAILED.
#    7. CA7-AMBIGUOUS -- 2 running containers match the sibling's compose
#       service -> CA-7 FAILED, never silently picking one (Sec F4).
#    8. TZ1-DRIFT -- the TZ-1 query returns a non-empty row (a role
#       carries a TimeZone override) -> TZ-1 FAILED.
#    9. RLS-DISABLED -- a discovered users_id table has
#       relrowsecurity=false -> RLS FAILED.
#   10. RLS-ANON-GRANT -- anon holds SELECT on a discovered table -> RLS
#       FAILED.
#   11. RLS-ZERO-CONTEXT-NONZERO -- a session with no JWT context
#       established sees >0 rows on a discovered table -> RLS FAILED (the
#       live isolation bypass this leg exists to catch).
#   12. RLS-BYPASSRLS-FALSE -- service_role does not carry BYPASSRLS ->
#       RLS FAILED.
#   13. RLS-EMPTY-ENUMERATION -- the users_id-table discovery query
#       returns zero rows -> RLS FAILED (invariance-is-blindness guard --
#       an empty result must never read as "0 tables, vacuously fine").
#   14. AUTH-LOGIN-WRONG-STATUS -- GET /login does not return 200 ->
#       auth-login FAILED.
#   15. AUTH-SIGNUP-WRONG-STATUS -- POST /signup (missing password) does
#       not return 400 -> auth-login FAILED.
#   16. AUTH-RESEND-KEY-ABSENT -- GOTRUE_SMTP_PASS is absent on the auth
#       container -> NOT a failure (informational only) -> auth-login
#       still MANUAL (every other automatable sub-check passed and the
#       email round-trip remains the permanent ceiling regardless of
#       whether Resend itself is even configured yet).
#   17. AUTH-LOGIN-CURL-EMPTY -- the GET /login probe produces no output
#       at all (local curl missing/broken, or a DNS/TLS-level failure) ->
#       auth-login FAILED with the explicit precondition message, never
#       silently compared as if empty were a real status code (same V-1
#       discipline scripts/smoke-admission-endpoint.sh's own N1/N2 guards
#       already established).
#   18. TZ1-EXTRACTION-FAILS-CLOSED -- self-strike, not a fixture
#       scenario: scripts/ci/check-tz-sweep-identical.py's own
#       extract_runbook() (which scripts/smoke-remaining-checks.sh
#       imports as a module, never retyping the query) is proven to fail
#       closed on a missing/corrupted runbook anchor, and the calling
#       script's own set+e/rc guard is proven to propagate that as TZ-1
#       FAILED -- verified by hand against a throwaway REPO_ROOT with a
#       deliberately anchor-less docs/deployment-runbook.md, NOT wired
#       into this fence's fixture loop (this fence's REPO_ROOT is fixed
#       to the real repo throughout, matching every sibling fence's own
#       convention of proving control-flow against real, unmangled
#       source files -- see this item's own self-strike note in the
#       handoff for the exact throwaway-tree reproduction).
#
# Exit 0 only if every scenario behaves exactly as specified above.
#
# LIVE-ONLY LEGS -- this fence proves the script's own control-flow
# (which verdict/exit code each response shape drives) entirely offline.
# It does NOT and CANNOT prove, and never claims to prove: that TZ-1's
# extracted query text is what a real deployment's own `db` container
# actually returns; that the ports it probes are genuinely closed on a
# real box; that the RLS catalog shape it asserts against actually holds
# in production; or that Resend's real API answers 200 for a real send.
# Those are proven only when scripts/smoke-remaining-checks.sh itself
# runs against a live box (docs/deployment-runbook.md Part 3,
# `remaining-checks`).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/smoke-remaining-checks"
SMOKE_SH="$REPO_ROOT/scripts/smoke-remaining-checks.sh"

[[ -x "$FIXTURE_DIR/fake-ssh" ]] || { echo "FATAL: $FIXTURE_DIR/fake-ssh missing or not executable" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-docker" ]] || { echo "FATAL: $FIXTURE_DIR/fake-docker missing or not executable" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -x "$FIXTURE_DIR/fake-nc" ]] || { echo "FATAL: $FIXTURE_DIR/fake-nc missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=fake-coolify-token-do-not-leak\n' > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-ssh" "$FAKE_BIN/ssh"
ln -s "$FIXTURE_DIR/fake-docker" "$FAKE_BIN/docker"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"
ln -s "$FIXTURE_DIR/fake-nc" "$FAKE_BIN/nc"

# The happy-path RLS fixture set -- shared as the baseline every scenario
# starts from, overridden per-scenario below. Two tables, RLS on, one
# policy each, anon holds no grant, service_role BYPASSRLS. FAKE_ZERO_CTX
# is the combined privileged-baseline + zero-context format Sec's F-1
# correction (PR #869 review) requires: "PRIV|table|count" /
# "AUTH|table|count" pairs per table -- privileged count >0 with
# authenticated count 0 is what PROVES isolation (an all-empty set would
# only be INCONCLUSIVE, see scenario 18).
HAPPY_RLS_ENUM='account|true|1|false
account_users|true|1|false'
HAPPY_ZERO_CTX='PRIV|account|5
AUTH|account|0
PRIV|account_users|3
AUTH|account_users|0'

LAST_OUT="$WORK/last_out"

run_scenario() {
  # run_scenario <desc> <expect_exit> [FAKE_VAR=value ...]
  # Leaves the captured output at $LAST_OUT for scenarios that need a
  # content assertion beyond the exit code (see scenario 18).
  local desc="$1" expect_exit="$2"
  shift 2
  set +e
  env REPO_ROOT="$REPO_ROOT" FAKE_ROOT_PFIN="$FAKE_ROOT_PFIN" FAKE_BIN="$FAKE_BIN" \
    BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null \
    FAKE_STACK_FQDN="" FAKE_SIBLING_FQDN="app.example.com" \
    FAKE_NC_OPEN="" FAKE_CONTAINERS="1" \
    FAKE_TZ1_ROWS="" \
    FAKE_RLS_ENUM="$HAPPY_RLS_ENUM" FAKE_ZERO_CTX="$HAPPY_ZERO_CTX" FAKE_BYPASSRLS="true" \
    FAKE_CA7_GW="200" FAKE_CA7_P1="OPEN" FAKE_CA7_P2="OPEN" \
    FAKE_LOGIN_STATUS="200" FAKE_SIGNUP_STATUS="400" FAKE_RESEND_OUT="RESEND_STATUS_200" \
    "$@" \
    PATH="$FAKE_BIN:$PATH" bash "$SMOKE_SH" < /dev/null > "$LAST_OUT" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$LAST_OUT" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  return 0
}

FAIL=0

# 1. HAPPY-PATH -- domain assigned, every automatable check passes ->
#    MANUAL (exit 4) is the correct, non-degraded outcome, not a partial
#    failure -- see this file's own header.
run_scenario "happy-path (domain assigned -> MANUAL ceiling)" 4 || FAIL=1

# 2. NO-DOMAIN
run_scenario "no domain assigned: auth-login SKIPPED, overall SKIPPED" 3 \
  FAKE_SIBLING_FQDN="" || FAIL=1

# 3. CA7-N1-OPEN
run_scenario "CA-7 N1 port 5432 open: refuses" 1 \
  FAKE_NC_OPEN="5432" || FAIL=1

# 4. CA7-DOMAIN-ASSIGNED
run_scenario "CA-7 Domain assigned to the stack app: refuses" 1 \
  FAKE_STACK_FQDN="stack.example.com" || FAIL=1

# 5. CA7-POSITIVE-GW-DOWN
run_scenario "CA-7 positive control api-gw unreachable: refuses" 1 \
  FAKE_CA7_GW="000" || FAIL=1

# 6. CA7-POSITIVE-SUPAVISOR-DOWN
run_scenario "CA-7 positive control supavisor:5432 not OPEN: refuses" 1 \
  FAKE_CA7_P1="ERROR" || FAIL=1

# 7. CA7-AMBIGUOUS
run_scenario "CA-7 ambiguous: 2 running sibling containers refuses" 1 \
  FAKE_CONTAINERS="2" || FAIL=1

# 8. TZ1-DRIFT
run_scenario "TZ-1 drift: a role carries a TimeZone override: refuses" 1 \
  FAKE_TZ1_ROWS="authenticator|postgres|TimeZone=Asia/Tokyo" || FAIL=1

# 9. RLS-DISABLED
run_scenario "RLS disabled on a discovered table: refuses" 1 \
  FAKE_RLS_ENUM="account|false|1|false" || FAIL=1

# 10. RLS-ANON-GRANT
run_scenario "anon holds SELECT on a discovered table: refuses" 1 \
  FAKE_RLS_ENUM="account|true|1|true" || FAIL=1

# 11. RLS-ZERO-CONTEXT-NONZERO
run_scenario "zero-JWT-context session sees >0 rows: refuses" 1 \
  FAKE_ZERO_CTX="PRIV|account|5
AUTH|account|3
PRIV|account_users|3
AUTH|account_users|0" || FAIL=1

# 12. RLS-BYPASSRLS-FALSE
run_scenario "service_role.rolbypassrls=false: refuses" 1 \
  FAKE_BYPASSRLS="false" || FAIL=1

# 13. RLS-EMPTY-ENUMERATION
run_scenario "empty users_id-table enumeration: refuses (invariance-is-blindness guard)" 1 \
  FAKE_RLS_ENUM="" || FAIL=1

# 14. AUTH-LOGIN-WRONG-STATUS
run_scenario "GET /login wrong status: refuses" 1 \
  FAKE_LOGIN_STATUS="500" || FAIL=1

# 15. AUTH-SIGNUP-WRONG-STATUS
run_scenario "POST /signup (missing password) wrong status: refuses" 1 \
  FAKE_SIGNUP_STATUS="200" || FAIL=1

# 16. AUTH-RESEND-KEY-ABSENT
run_scenario "Resend key absent: informational only, still MANUAL" 4 \
  FAKE_RESEND_OUT="RESEND_KEY_ABSENT" || FAIL=1

# 17. AUTH-LOGIN-CURL-EMPTY
run_scenario "GET /login produces no output at all: precondition, refuses (never a status-code comparison)" 1 \
  FAKE_LOGIN_STATUS="EMPTY" || FAIL=1

# 18. RLS-ALL-TABLES-EMPTY -- Sec F-1 (PR #869 review), the fix itself:
# every discovered table's PRIVILEGED count is 0 too (not just the
# authenticated one) -- nothing exists to be isolated, so this must NOT
# report VERIFIED (that would be the exact vacuous-pass Sec's finding
# named: indistinguishable from RLS being switched off entirely on an
# empty table). Combined with no domain assigned (auth-login SKIPPED,
# not MANUAL) so the overall exit code is driven by RLS's own SKIPPED,
# not masked by auth-login's MANUAL ceiling -- and the RLS summary line
# itself is asserted via $LAST_OUT, not inferred from the aggregate exit
# code alone (exit 3 alone cannot distinguish "RLS SKIPPED" from
# "auth-login SKIPPED with RLS VERIFIED" -- both would read exit 3).
run_scenario "RLS: every discovered table has zero real rows -- SKIPPED (isolation unproven, not proven absent), not VERIFIED" 3 \
  FAKE_SIBLING_FQDN="" \
  FAKE_ZERO_CTX="PRIV|account|0
AUTH|account|0
PRIV|account_users|0
AUTH|account_users|0" || FAIL=1
if grep -qE '^  RLS:[[:space:]]+SKIPPED' "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-ALL-TABLES-EMPTY] RLS leg itself reports SKIPPED in the summary table." >&2
else
  echo "FAIL: [RLS-ALL-TABLES-EMPTY] RLS leg did not report SKIPPED in the summary table -- exit code alone does not prove this scenario struck the intended guard." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more smoke-remaining-checks.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all smoke-remaining-checks.sh strike-proofs passed."
exit 0
