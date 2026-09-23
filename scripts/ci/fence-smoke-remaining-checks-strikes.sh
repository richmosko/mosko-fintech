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
#   15. AUTH-SIGNUP-WRONG-STATUS -- POST /signup (missing password)
#       returns a status that is neither 400 nor a 200 SvelteKit
#       action-failure envelope (real-run 25 (2026-09-22) note: 200 is no
#       longer inherently wrong -- see 26/27/28 below -- this scenario
#       now uses a genuinely unexpected status, 500) -> auth-login
#       FAILED.
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
#   -- real-run 23 (2026-09-22) additions: auth-login host-derivation
#      (docker_compose_domains vs fqdn, COOLIFY-FACT-05/06/15 shape) and
#      RLS's DENY-ALL classification (RLS_DENY_ALL_EXPECTED) --
#
#   19. AUTH-HOST-FROM-COMPOSE-DOMAINS -- the happy-path default now
#       sources the auth host from docker_compose_domains (the FACT-15
#       measured object-string shape, byte-pinned below via grep -F, not
#       hand-retyped) rather than the Coolify-assigned sslip.io fqdn --
#       content-asserted (host + source both named in the output), not
#       just exit-code-asserted.
#   20. AUTH-HOST-FQDN-FALLBACK -- docker_compose_domains absent/empty ->
#       falls back to fqdn, source printed as "fqdn", and the (deliberately
#       SCHEMED, sslip.io-shaped) fqdn fixture value is stripped down to a
#       bare host -- proving the fallback path strips a scheme too, not
#       only the docker_compose_domains path (real-run 23's actual defect
#       was building "https://" + an ALREADY-schemed fqdn verbatim).
#   21. AUTH-HOST-SCHEME-PREFIX -- the derived host still carries a scheme
#       after stripping one (a doubly-schemed domain value) -- refuses
#       (FAILED), never silently builds a malformed doubly-schemed URL.
#   14-content. AUTH-LOGIN-WRONG-STATUS is extended with a content
#       assertion: the FAILED leg's own message must reach $LAST_OUT, not
#       only the Summary table -- this is the exact real-run-23 regression
#       (a FAILED leg printed nothing before Summary).
#   22. RLS-DENY-ALL-ALLOWLISTED -- a discovered table with RLS on, 0
#       policies, anon zero-grant, authenticated zero table-grant, zero
#       column-level grants, privileged count >0, and its name IN
#       RLS_DENY_ALL_EXPECTED -- reported as a distinct DENY-ALL/
#       ALLOWLISTED line, NOT a failure. real-run 25 fix (2026-09-22),
#       amended by Sec's own 2026-09-22 ruling: this scenario's audit_log
#       fixture simulates the REAL grant-level refusal (SQLSTATE 42501 --
#       see this file's own header for the measured defect this
#       replaced) alongside two ordinary policy-scoped tables (account/
#       account_users) in the SAME run -- content-asserted to prove the
#       per-table read mechanism does NOT abort a sibling table's read
#       when one table is refused ("a batched read that aborts the whole
#       batch on the first refusal must not exist"): the summary line's
#       own PROVEN/DENY-ALL/policy counts are checked, not just the
#       aggregate exit code. Per Sec's ruling, the refusal itself is
#       reported as `row read: REFUSED at grant level`, NEVER "proven" or
#       "DENIED" -- the verdict rests on the STRUCTURAL conjunction
#       alone, which the refused read does not change up or down.
#   22b/22c/22d. RLS-DENY-ALL-ALLOWLISTED-{COLGRANT,AUTHTBL,ANONCOL}-LEAK
#       -- Sec's four privilege columns (F-1, round-2 review, PR #880):
#       the SAME allowlisted table with an otherwise-clean row
#       observation but authenticated column-level SELECT (22b),
#       authenticated table-level SELECT (22c), or anon column-level
#       SELECT (22d) -- all three must still refuse; the mechanism, not
#       just the row read, is what's being verified. Anon's table-level
#       grant is covered by the pre-existing anon-grant check (scenario
#       10), unconditional on every table, not only DENY-ALL candidates.
#   23. RLS-DENY-ALL-UNLISTED -- same shape, but the table's name is NOT
#       in RLS_DENY_ALL_EXPECTED -- RLS FAILED in the ENUMERATION loop
#       itself (never rescued by a behavioral read), naming the table
#       and the allowlist gap explicitly.
#   24. RLS-ALLOWLISTED-WITH-POLICIES -- a table IN RLS_DENY_ALL_EXPECTED
#       that now carries >=1 real policy -- POLICY-SCOPED (not DENY-ALL
#       any more), reported as an INFO line, not a failure.
#
#   -- real-run 27 (2026-09-22) additions: RLS HYBRID-table classification
#      (a select policy admitting `users_id IS NULL` to every
#      authenticated caller, e.g. `pfin.asset`), and the Resend probe
#      moved off the auth container's own missing node/curl --
#
#   34. RLS-HYBRID-VERIFIED -- a HYBRID table's global rows (users_id
#       NULL) ARE visible and zero tenant (non-NULL users_id) rows are
#       visible -- CORRECT isolation, not a bypass; counted toward
#       PROVEN_COUNT via its own HYBRID_COUNT bucket, content-asserted in
#       the summary line's breakdown.
#   35. RLS-HYBRID-BYPASS -- a row with a NON-NULL users_id IS visible to
#       a session with no tenant identity -- a REAL bypass, FAILED,
#       explicitly distinguished in its own message from the by-design
#       global-row exposure.
#   31. AUTH-RESEND-AUTH-CONTAINER-NOT-FOUND -- zero running containers
#       match the stack's own `auth` compose service -> FAILED.
#   32. AUTH-RESEND-AUTH-CONTAINER-AMBIGUOUS -- two running containers
#       match `auth` -> FAILED, same Sec F4 discipline as every other
#       container lookup in this script.
#   33. AUTH-RESEND-CONN-ERROR -- the key IS present and the sibling
#       container is found, but the HTTPS POST itself fails -> FAILED.
#   16 (retargeted). AUTH-RESEND-KEY-ABSENT -- the key-absence decision
#       now lives INSIDE resend_probe()'s own remote script
#       (FAKE_AUTH_ENV_LINES), checked before ever touching the sibling
#       container -- FAKE_RESEND_OUT no longer drives this scenario.
#
#   -- real-run 25 (2026-09-22) additions: RLS's authenticated read is
#      now ONE psql invocation PER TABLE (a batched UNION ALL aborted
#      every table's read the instant ONE table hit a grant-level
#      refusal -- MEASURED live: `permission denied for table audit_log`
#      on a table with no grant to `authenticated` at all), and the
#      auth-login signup check now recognises SvelteKit's real HTTP-200
#      action-failure envelope instead of only a plain HTTP 400. Sec's
#      own 2026-09-22 ruling then amended the RLS classification further
#      (detect the refusal by SQLSTATE 42501, not message text; a
#      refusal is NEVER isolation proven by itself) --
#
#   25. RLS-AUTH-OTHER-ERROR -- a table's per-table authenticated read
#       fails with an error OTHER than SQLSTATE 42501 -- a precondition
#       failure scoped to THAT ONE table (INCONCLUSIVE for it, per Sec's
#       ruling -- never FAILED, never aborting any other table's read,
#       never misclassified as a grant-level refusal). The OTHER
#       discovered table in this scenario still proves isolation
#       normally, so the LEG itself stays VERIFIED and the overall run
#       reaches its usual MANUAL ceiling -- content-asserted, since exit
#       code alone can't distinguish "one table inconclusive, leg still
#       verified" from "leg failed".
#   29. RLS-DENY-ALL-CONTRADICTION -- an ALLOWLISTED (DENY-ALL) table's
#       authenticated read SUCCEEDS and returns 0 (not refused). Sec
#       ruling (PR #881 review, round 2, 2026-09-22 -- corrects this
#       scenario's OWN first draft, which had credited this as PROVEN):
#       Postgres checks table ACL BEFORE RLS, so a genuinely zero-grant
#       table CANNOT return a row count -- a success there means one of
#       the two measurements (the structural grant check, or this row
#       read) is WRONG, and we don't know which. CONTRADICTION,
#       INCONCLUSIVE regardless of the privileged baseline, NEVER
#       PROVEN, with its own WARN naming the contradiction explicitly.
#   30. RLS-REFUSED-POLICY-SCOPED -- a POLICY-SCOPED table (>=1 real
#       policy, NOT in RLS_DENY_ALL_EXPECTED) hits a SQLSTATE-42501
#       refusal on its authenticated read -- unlike the DENY-ALL
#       allowlist, this table's grant absence was never independently
#       verified structurally, so the refusal has no structural fallback
#       to rest on: INCONCLUSIVE, never PROVEN, never FAILED from the
#       permission error alone (this was Sec's F-1 finding).
#
#   -- Sec's PR #881 review, round 2 (2026-09-22), also required: the
#      summary line's INCONCLUSIVE count now breaks down its four
#      distinct causes by name (empty / refused-at-grant-on-a-policy-
#      table / unreadable / contradiction) rather than asserting "empty,
#      nothing to isolate" for all of them -- scenarios 25/29/30 above
#      and 22's own sibling-not-aborted assertion all content-assert the
#      exact breakdown line, not just the PROVEN/INCONCLUSIVE totals.
#   26. AUTH-SIGNUP-ENVELOPE-SUCCESS -- POST /signup (missing password)
#       returns HTTP 200 with a SvelteKit action-SUCCESS envelope
#       (type=success) -- auth-login FAILED (this would mean an account
#       WAS created from a malformed body).
#   27. AUTH-SIGNUP-PLAIN-400 -- POST /signup (missing password) returns
#       a bare HTTP 400 with no JSON envelope at all -- still accepted as
#       proof validation rejected the request (either shape proves the
#       same thing).
#   28. AUTH-SIGNUP-CSRF-403 -- POST /signup (missing password) returns
#       HTTP 403 -- auth-login FAILED, the message explicitly naming the
#       CSRF guard (this leg cannot prove Zod .strict() fired when the
#       CSRF guard rejected the request first).
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
# policy each, anon holds no grant, service_role BYPASSRLS.
# real-run 25 fix (2026-09-22): the privileged-baseline read
# ($FAKE_PRIV, "PRIV|table|count" lines) and the authenticated read
# ($FAKE_AUTH_TABLE_RESULTS, "table|MODE|value" lines, MODE one of
# OK/DENIED/ERROR -- see fake-docker's own header) are now SEPARATE
# fixtures, one psql invocation per table for the latter -- see this
# file's own header for the measured defect this replaced (a batched
# UNION ALL aborting every table's read on the first grant-level
# refusal). Privileged count >0 with authenticated count 0 is what
# PROVES isolation (an all-empty set would only be INCONCLUSIVE, see
# scenario 18). FAKE_RLS_ENUM rows are 8 fields (table|rls|polcount|
# anon-table-sel|authenticated-table-sel|anon-col-sel|
# authenticated-col-sel|hybrid) -- Sec F-1, round-2 review, PR #880: the
# middle four privilege columns only matter for a 0-policy allowlisted
# (DENY-ALL) table, but every row carries them for fixture-format
# consistency. The 8th (hybrid) column is a real-run 27 addition
# (2026-09-22) -- see psql_admin_auth_read_hybrid()'s own header in
# scripts/smoke-remaining-checks.sh; "false" for every ordinary table.
HAPPY_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false'
HAPPY_PRIV='PRIV|account|5
PRIV|account_users|3'
HAPPY_AUTH='account|OK|0
account_users|OK|0'

# COOLIFY-FACT-15's own measured docker_compose_domains read-back sample,
# pinned by grep -F against scripts/COOLIFY-API-MEASURED.md's recorded
# bytes -- never hand-retyped as a second, driftable copy (the fact this
# repo's own COOLIFY-API-MEASURED.md header exists to prevent). Fails
# closed if that fact ever moves or is reworded.
FACT15_LITERAL='{"app":{"domain":"https://pfindash.com,https://www.pfindash.com"}}'
grep -qF "$FACT15_LITERAL" "$REPO_ROOT/scripts/COOLIFY-API-MEASURED.md" \
  || { echo "FATAL: COOLIFY-FACT-15's measured docker_compose_domains sample is no longer present verbatim in scripts/COOLIFY-API-MEASURED.md -- has that fact moved, been reworded, or the domain changed? Update this fence's fixture pin to match." >&2; exit 2; }

# The measured SvelteKit signup-action-failure envelope (real-run 25,
# 2026-09-22), pinned by grep -F against scripts/smoke-remaining-checks.sh's
# own header -- never hand-retyped as a second, driftable copy. Used BOTH
# to confirm the pin holds AND as the actual happy-path fixture body (one
# bash literal, two uses -- the FACT15_LITERAL precedent above).
ENVELOPE_LITERAL='{"type":"failure","status":400,"data":"[{\"errors\":1,\"email\":5},{\"password\":2,...},\"Invalid input: expected string, received undefined\",...]"}'
grep -qF "$ENVELOPE_LITERAL" "$SMOKE_SH" \
  || { echo "FATAL: the measured SvelteKit signup-action-failure envelope is no longer present verbatim in scripts/smoke-remaining-checks.sh's own header -- has the app's validation response shape changed? Update this fence's fixture pin to match." >&2; exit 2; }

# The measured psql VERBOSE grant-level refusal (local dev stack,
# 2026-09-22, table audit_log), pinned by grep -F against
# scripts/smoke-remaining-checks.sh's own header (psql_admin_auth_read()'s
# own docstring) -- never hand-retyped as a second, driftable copy. Sec's
# own 2026-09-22 ruling: detect the refusal by SQLSTATE 42501, not message
# text -- this is the exact line that carries it.
REFUSAL_LITERAL='ERROR:  42501: permission denied for table audit_log'
grep -qF "$REFUSAL_LITERAL" "$SMOKE_SH" \
  || { echo "FATAL: the measured psql VERBOSE grant-level-refusal line is no longer present verbatim in scripts/smoke-remaining-checks.sh's own header -- has the SQLSTATE or error wording changed? Update this fence's fixture pin to match." >&2; exit 2; }

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
    FAKE_STACK_FQDN="" \
    FAKE_SIBLING_FQDN="http://siblinguuid0000001.203.0.113.5.sslip.io" \
    FAKE_SIBLING_COMPOSE_DOMAINS="$FACT15_LITERAL" \
    FAKE_NC_OPEN="" FAKE_CONTAINERS="1" \
    FAKE_TZ1_ROWS="" \
    FAKE_RLS_ENUM="$HAPPY_RLS_ENUM" FAKE_PRIV="$HAPPY_PRIV" FAKE_AUTH_TABLE_RESULTS="$HAPPY_AUTH" FAKE_BYPASSRLS="true" \
    FAKE_CA7_GW="200" FAKE_CA7_P1="OPEN" FAKE_CA7_P2="OPEN" \
    FAKE_LOGIN_STATUS="200" \
    FAKE_SIGNUP_STATUS="200" FAKE_SIGNUP_CTYPE="application/json" FAKE_SIGNUP_BODY="$ENVELOPE_LITERAL" \
    FAKE_AUTH_CONTAINERS="1" \
    FAKE_AUTH_ENV_LINES="GOTRUE_SMTP_PASS=fake-resend-key-do-not-leak
GOTRUE_SMTP_ADMIN_EMAIL=onboarding@resend.dev" \
    FAKE_RESEND_OUT="RESEND_STATUS_200" \
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

# 19. AUTH-HOST-FROM-COMPOSE-DOMAINS -- same happy-path run above: the
#     auth host must come from docker_compose_domains ('pfindash.com',
#     the FACT-15 sample's first sorted domain for the 'app' service),
#     never the Coolify-assigned sslip.io fqdn -- content-asserted, exit
#     code alone cannot distinguish "used the right source" from
#     "happened to pass anyway".
if grep -qF "using host 'pfindash.com' (source: docker_compose_domains)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-HOST-FROM-COMPOSE-DOMAINS] host+source line present." >&2
else
  echo "FAIL: [AUTH-HOST-FROM-COMPOSE-DOMAINS] expected host/source line not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 20. AUTH-HOST-FQDN-FALLBACK -- docker_compose_domains absent/empty ->
#     falls back to fqdn, source printed as "fqdn"; the fqdn fixture
#     value is deliberately SCHEMED (sslip.io-shaped, like a real
#     Coolify-assigned default) -- proving the fallback path strips a
#     scheme too, not only the docker_compose_domains path (real-run
#     23's actual defect: building "https://" + an ALREADY-schemed fqdn
#     verbatim).
run_scenario "no compose-domains: falls back to fqdn (scheme stripped), source printed" 4 \
  FAKE_SIBLING_COMPOSE_DOMAINS="" || FAIL=1
if grep -qF "using host 'siblinguuid0000001.203.0.113.5.sslip.io' (source: fqdn)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-HOST-FQDN-FALLBACK] host+source line present, scheme stripped." >&2
else
  echo "FAIL: [AUTH-HOST-FQDN-FALLBACK] expected host/source line not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 21. AUTH-HOST-SCHEME-PREFIX -- the derived host still carries a scheme
#     after stripping one (a doubly-schemed domain value) -- refuses
#     (FAILED), never silently builds a malformed doubly-schemed URL.
run_scenario "derived host still schemed after stripping: refuses" 1 \
  FAKE_SIBLING_COMPOSE_DOMAINS='{"app":{"domain":"https://https://pfindash.com"}}' || FAIL=1
if grep -qF "host derivation refused" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-HOST-SCHEME-PREFIX] refusal message present." >&2
else
  echo "FAIL: [AUTH-HOST-SCHEME-PREFIX] refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 2. NO-DOMAIN -- neither source yields a host.
run_scenario "no domain assigned: auth-login SKIPPED, overall SKIPPED" 3 \
  FAKE_SIBLING_FQDN="" FAKE_SIBLING_COMPOSE_DOMAINS="" || FAIL=1

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
  FAKE_RLS_ENUM="account|false|1|false|false|false|false|false" || FAIL=1

# 10. RLS-ANON-GRANT
run_scenario "anon holds SELECT on a discovered table: refuses" 1 \
  FAKE_RLS_ENUM="account|true|1|true|false|false|false|false" || FAIL=1

# 11. RLS-ZERO-CONTEXT-NONZERO
run_scenario "zero-JWT-context session sees >0 rows: refuses" 1 \
  FAKE_AUTH_TABLE_RESULTS="account|OK|3
account_users|OK|0" || FAIL=1

# 12. RLS-BYPASSRLS-FALSE
run_scenario "service_role.rolbypassrls=false: refuses" 1 \
  FAKE_BYPASSRLS="false" || FAIL=1

# 13. RLS-EMPTY-ENUMERATION
run_scenario "empty users_id-table enumeration: refuses (invariance-is-blindness guard)" 1 \
  FAKE_RLS_ENUM="" || FAIL=1

# 14. AUTH-LOGIN-WRONG-STATUS -- also the FAILED-message-prints
#     regression check: real-run 23 hit a FAILED leg that printed
#     NOTHING before the Summary table -- content-asserted, not just
#     exit-code-asserted (exit 1 alone cannot distinguish "message
#     reached output" from "silently swallowed").
run_scenario "GET /login wrong status: refuses, and prints its own message" 1 \
  FAKE_LOGIN_STATUS="500" || FAIL=1
if grep -qF "auth login:" "$LAST_OUT" 2>/dev/null && grep -qF "HTTP 500" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-LOGIN-WRONG-STATUS] FAILED leg printed its own message (not just the Summary table)." >&2
else
  echo "FAIL: [AUTH-LOGIN-WRONG-STATUS] FAILED leg's own message did not reach output -- this is the exact real-run-23 regression." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 15. AUTH-SIGNUP-WRONG-STATUS -- real-run 25 fix: 200 is no longer
#     inherently wrong (see 26/27/28 below), so this scenario now uses a
#     genuinely unexpected status.
run_scenario "POST /signup (missing password) wrong status: refuses" 1 \
  FAKE_SIGNUP_STATUS="500" || FAIL=1

# 26. AUTH-SIGNUP-ENVELOPE-SUCCESS -- a 200 response with a SvelteKit
#     action-SUCCESS envelope means an account WAS created -- FAILED.
run_scenario "POST /signup (missing password) returns a SUCCESS envelope: refuses" 1 \
  FAKE_SIGNUP_BODY='{"type":"success","status":200,"data":null}' || FAIL=1
if grep -qF "action-SUCCESS envelope" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-SIGNUP-ENVELOPE-SUCCESS] success-envelope refusal message present." >&2
else
  echo "FAIL: [AUTH-SIGNUP-ENVELOPE-SUCCESS] expected success-envelope refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 27. AUTH-SIGNUP-PLAIN-400 -- a bare HTTP 400 with no JSON envelope at
#     all is still accepted -- either shape proves the same thing.
run_scenario "POST /signup (missing password) plain HTTP 400, no envelope: ok" 4 \
  FAKE_SIGNUP_STATUS="400" || FAIL=1
if grep -qF "HTTP 400 (validation rejected" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-SIGNUP-PLAIN-400] plain-400 acceptance message present." >&2
else
  echo "FAIL: [AUTH-SIGNUP-PLAIN-400] expected plain-400 acceptance message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 28. AUTH-SIGNUP-CSRF-403 -- a 403 means the CSRF guard rejected the
#     request before validation ever ran -- FAILED, naming CSRF.
run_scenario "POST /signup (missing password) returns 403: refuses, naming CSRF" 1 \
  FAKE_SIGNUP_STATUS="403" || FAIL=1
if grep -qF "CSRF guard" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-SIGNUP-CSRF-403] CSRF-naming refusal message present." >&2
else
  echo "FAIL: [AUTH-SIGNUP-CSRF-403] expected CSRF-naming refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 16. AUTH-RESEND-KEY-ABSENT -- real-run 27 fix: the key-absence decision
#     is now made INSIDE resend_probe()'s own remote script (via
#     FAKE_AUTH_ENV_LINES, checked BEFORE ever touching the sibling
#     container), not via FAKE_RESEND_OUT any more.
run_scenario "Resend key absent: informational only, still MANUAL" 4 \
  FAKE_AUTH_ENV_LINES="" || FAIL=1

# 31. AUTH-RESEND-AUTH-CONTAINER-NOT-FOUND -- real-run 27 addition: zero
#     running containers match the stack's own `auth` compose service ->
#     resend_probe() reports RESEND_AUTH_CONTAINER_NOT_FOUND -> auth-login
#     FAILED via the generic "unexpected RESEND_OUT" branch.
run_scenario "Resend: zero running auth containers: refuses" 1 \
  FAKE_AUTH_CONTAINERS="0" || FAIL=1
if grep -qF "RESEND_AUTH_CONTAINER_NOT_FOUND" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-RESEND-AUTH-CONTAINER-NOT-FOUND] refusal names the missing auth container." >&2
else
  echo "FAIL: [AUTH-RESEND-AUTH-CONTAINER-NOT-FOUND] expected RESEND_AUTH_CONTAINER_NOT_FOUND not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 32. AUTH-RESEND-AUTH-CONTAINER-AMBIGUOUS -- two running containers match
#     the `auth` compose service -> resend_probe() refuses to guess which
#     one, same Sec F4 discipline every other container lookup in this
#     script already applies.
run_scenario "Resend: two running auth containers (ambiguous): refuses" 1 \
  FAKE_AUTH_CONTAINERS="2" || FAIL=1
if grep -qF "RESEND_AUTH_CONTAINER_AMBIGUOUS" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-RESEND-AUTH-CONTAINER-AMBIGUOUS] refusal names the ambiguity." >&2
else
  echo "FAIL: [AUTH-RESEND-AUTH-CONTAINER-AMBIGUOUS] expected RESEND_AUTH_CONTAINER_AMBIGUOUS not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 33. AUTH-RESEND-CONN-ERROR -- the key IS present (unlike scenario 16)
#     and the sibling container is found, but the HTTPS POST itself fails
#     -- FAILED via the generic "unexpected RESEND_OUT" branch, proving
#     that branch is still reachable now that the happy path takes a
#     different code path (RESEND_STATUS_200) than key-absence.
run_scenario "Resend: connection error from the sibling container: refuses" 1 \
  FAKE_RESEND_OUT="RESEND_CONN_ERROR" || FAIL=1
if grep -qF "Resend send-acceptance probe -> RESEND_CONN_ERROR" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [AUTH-RESEND-CONN-ERROR] refusal names the connection error." >&2
else
  echo "FAIL: [AUTH-RESEND-CONN-ERROR] expected RESEND_CONN_ERROR refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

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
  FAKE_SIBLING_FQDN="" FAKE_SIBLING_COMPOSE_DOMAINS="" \
  FAKE_PRIV="PRIV|account|0
PRIV|account_users|0" \
  FAKE_AUTH_TABLE_RESULTS="account|OK|0
account_users|OK|0" || FAIL=1
if grep -qE '^  RLS:[[:space:]]+SKIPPED' "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-ALL-TABLES-EMPTY] RLS leg itself reports SKIPPED in the summary table." >&2
else
  echo "FAIL: [RLS-ALL-TABLES-EMPTY] RLS leg did not report SKIPPED in the summary table -- exit code alone does not prove this scenario struck the intended guard." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 22. RLS-DENY-ALL-ALLOWLISTED -- a discovered table with RLS on, 0
#     policies, anon zero-grant, authenticated zero table-grant, zero
#     column-level grants, privileged count >0, authenticated count 0,
#     name IN RLS_DENY_ALL_EXPECTED -- reported as a distinct
#     DENY-ALL/ALLOWLISTED line, NOT a failure (overall stays MANUAL,
#     same ceiling as the happy path -- this table contributes to
#     PROVEN_COUNT via the default-deny mechanism, not a policy). Sec's
#     four privilege columns (F-1, round-2 review, PR #880) must all
#     read clean or this scenario itself would wrongly FAIL.
DENY_ALL_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
audit_log|true|0|false|false|false|false|false'
DENY_ALL_PRIV='PRIV|account|5
PRIV|account_users|3
PRIV|audit_log|7'
# real-run 25 fix: audit_log's authenticated read is DENIED at the grant
# level (the real, measured behavior for a table with NO grant at all),
# not a policy-based "OK|0" read -- see this file's own header.
DENY_ALL_AUTH='account|OK|0
account_users|OK|0
audit_log|DENIED|'
run_scenario "RLS DENY-ALL table on the allowlist: not a failure" 4 \
  FAKE_RLS_ENUM="$DENY_ALL_RLS_ENUM" FAKE_PRIV="$DENY_ALL_PRIV" FAKE_AUTH_TABLE_RESULTS="$DENY_ALL_AUTH" || FAIL=1
if grep -qF "DENY-ALL: pfin.audit_log" "$LAST_OUT" 2>/dev/null \
  && grep -qF "ALLOWLISTED" "$LAST_OUT" 2>/dev/null \
  && grep -qF "row read: REFUSED at grant level" "$LAST_OUT" 2>/dev/null \
  && ! grep -qF "proven" "$LAST_OUT" 2>/dev/null \
  && ! grep -qi "DENIED" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-ALLOWLISTED] DENY-ALL/ALLOWLISTED/REFUSED-at-grant-level line present, never 'proven'/'DENIED'." >&2
else
  echo "FAIL: [RLS-DENY-ALL-ALLOWLISTED] expected DENY-ALL/ALLOWLISTED/REFUSED-at-grant-level line not found (or 'proven'/'DENIED' leaked into output -- Sec's word-choice ruling)." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi
# Sibling-not-aborted proof: audit_log's REFUSED read must not abort
# account/account_users' own reads in the SAME run ("a batched read
# that aborts the whole batch on the first refusal must not exist") --
# content-asserted against the summary line's own counts, not just the
# aggregate exit code (3 PROVEN: 1 via DENY-ALL, 2 via >=1 policy; 0
# INCONCLUSIVE, all four breakdown buckets at 0).
if grep -qF "3 table(s) PROVEN isolated (1 via allowlisted DENY-ALL, 0 via HYBRID global-row demonstration, 2 via >=1 policy), 0 table(s) INCONCLUSIVE (0 empty -- nothing to isolate, 0 refused-at-grant on a policy-scoped table -- policy never exercised, 0 unreadable -- an unexpected error, 0 contradiction -- a zero-grant table's read unexpectedly succeeded)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-ALLOWLISTED] sibling tables' reads were NOT aborted by audit_log's denial." >&2
else
  echo "FAIL: [RLS-DENY-ALL-ALLOWLISTED] sibling-not-aborted proof failed -- expected PROVEN-count summary line not found (a batch-wide abort would have surfaced as a precondition FAILED instead)." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 25. RLS-AUTH-OTHER-ERROR -- a table's authenticated read fails with an
#     error OTHER than SQLSTATE 42501 -- Sec ruling: INCONCLUSIVE for
#     THAT table alone, never FAILED, never a grant-level refusal. The
#     OTHER discovered table (account_users) still proves isolation
#     normally, so the LEG stays VERIFIED and the run reaches its usual
#     MANUAL ceiling -- exit 4, not 1 (content-asserted: exit code alone
#     can't tell "one table inconclusive, leg still verified" from "leg
#     failed").
run_scenario "RLS: authenticated read hits an unexpected (non-42501) error: leg still verified, that table INCONCLUSIVE" 4 \
  FAKE_AUTH_TABLE_RESULTS="account|ERROR|relation \"pfin.account\" does not exist
account_users|OK|0" || FAIL=1
if grep -qF "the authenticated row-count read failed with an unexpected error" "$LAST_OUT" 2>/dev/null \
  && grep -qF "INCONCLUSIVE for this table only" "$LAST_OUT" 2>/dev/null \
  && ! grep -qF "row read: REFUSED at grant level" "$LAST_OUT" 2>/dev/null \
  && grep -qE '^  RLS:[[:space:]]+VERIFIED' "$LAST_OUT" 2>/dev/null \
  && grep -qF "1 table(s) PROVEN isolated (0 via allowlisted DENY-ALL, 0 via HYBRID global-row demonstration, 1 via >=1 policy), 1 table(s) INCONCLUSIVE (0 empty -- nothing to isolate, 0 refused-at-grant on a policy-scoped table -- policy never exercised, 1 unreadable -- an unexpected error, 0 contradiction -- a zero-grant table's read unexpectedly succeeded)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-AUTH-OTHER-ERROR] unexpected-error precondition message present, scoped to that table, never misclassified as a grant-level refusal, leg still VERIFIED, breakdown attributes it to 'unreadable' specifically (Sec: the summary must name what actually happened)." >&2
else
  echo "FAIL: [RLS-AUTH-OTHER-ERROR] expected unexpected-error precondition message not found, or leg was not VERIFIED, or it was wrongly classified as a grant-level refusal, or the breakdown line is wrong." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 29. RLS-DENY-ALL-CONTRADICTION -- an ALLOWLISTED table's read SUCCEEDS
#     (not refused) and returns 0 -- Sec ruling (PR #881 review, round 2):
#     Postgres checks table ACL before RLS, so a genuinely zero-grant
#     table CANNOT return a row count -- a success there means one of
#     the two measurements (the structural grant check, or this row
#     read) is wrong, and crediting PROVEN would rest a proof on
#     self-inconsistent evidence. CONTRADICTION, INCONCLUSIVE regardless
#     of the privileged baseline, NEVER PROVEN, with its own WARN.
run_scenario "RLS: allowlisted table's read SUCCEEDS with 0 (not refused): CONTRADICTION, INCONCLUSIVE, WARNs" 4 \
  FAKE_RLS_ENUM="$DENY_ALL_RLS_ENUM" FAKE_PRIV="$DENY_ALL_PRIV" \
  FAKE_AUTH_TABLE_RESULTS="account|OK|0
account_users|OK|0
audit_log|OK|0" || FAIL=1
if grep -qF "CONTRADICTION" "$LAST_OUT" 2>/dev/null \
  && grep -qF "is NOT counted as proven until that is resolved" "$LAST_OUT" 2>/dev/null \
  && grep -qF "2 table(s) PROVEN isolated (0 via allowlisted DENY-ALL, 0 via HYBRID global-row demonstration, 2 via >=1 policy), 1 table(s) INCONCLUSIVE (0 empty -- nothing to isolate, 0 refused-at-grant on a policy-scoped table -- policy never exercised, 0 unreadable -- an unexpected error, 1 contradiction -- a zero-grant table's read unexpectedly succeeded)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-CONTRADICTION] CONTRADICTION WARN present, correctly INCONCLUSIVE and NOT counted as PROVEN (nor as via-DENY-ALL)." >&2
else
  echo "FAIL: [RLS-DENY-ALL-CONTRADICTION] expected CONTRADICTION WARN and/or correct PROVEN/INCONCLUSIVE breakdown line not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 30. RLS-REFUSED-POLICY-SCOPED -- a POLICY-SCOPED table (NOT in
#     RLS_DENY_ALL_EXPECTED) hits a 42501 refusal -- no structural
#     fallback to rest on: INCONCLUSIVE, never PROVEN, never FAILED.
run_scenario "RLS: policy-scoped table's read is REFUSED at grant level: INCONCLUSIVE, not proven, not failed" 4 \
  FAKE_AUTH_TABLE_RESULTS="account|DENIED|
account_users|OK|0" || FAIL=1
if grep -qF "row read: REFUSED at grant level on a POLICY-SCOPED table" "$LAST_OUT" 2>/dev/null \
  && grep -qF "1 table(s) PROVEN isolated (0 via allowlisted DENY-ALL, 0 via HYBRID global-row demonstration, 1 via >=1 policy), 1 table(s) INCONCLUSIVE (0 empty -- nothing to isolate, 1 refused-at-grant on a policy-scoped table -- policy never exercised, 0 unreadable -- an unexpected error, 0 contradiction -- a zero-grant table's read unexpectedly succeeded)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-REFUSED-POLICY-SCOPED] POLICY-SCOPED refusal correctly INCONCLUSIVE, never PROVEN/FAILED from the permission error alone." >&2
else
  echo "FAIL: [RLS-REFUSED-POLICY-SCOPED] expected POLICY-SCOPED-refusal INCONCLUSIVE line and/or PROVEN-count line not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 22b/22c/22d all carry FULL PRIV/AUTH data for audit_log (matching
# DENY_ALL_PRIV/DENY_ALL_AUTH's own rows), even though the shipped code
# never reaches the per-table read block once the enumeration loop FAILS
# a table -- a self-strike against just one of the three grant-check
# `if`s (disabling it alone) would otherwise let audit_log survive
# enumeration and reach the per-table read block anyway, where a default
# (2-table) $FAKE_AUTH_TABLE_RESULTS with no audit_log row would fail it
# for an UNRELATED reason ("no FAKE_AUTH_TABLE_RESULTS row for table") --
# a coincidental, wrong-reason red that masks whether the specific grant
# check under test is the thing actually catching it. Full data here
# means each scenario's pass/fail is driven ONLY by its own named check.

# 22b. RLS-DENY-ALL-ALLOWLISTED-COLGRANT-LEAK -- a column-level grant to
#      authenticated exists (has_any_column_privilege) -- Sec's added
#      conjunction column must catch this even though the table-level
#      grant and the row-visibility read are both clean (the exact risk
#      this leg exists for: 026_mfa_recovery_code.sql:222's own
#      column-scoped grants pattern, misapplied to the wrong role).
run_scenario "RLS DENY-ALL allowlisted table with a column-level grant leak: refuses" 1 \
  FAKE_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
audit_log|true|0|false|false|false|true|false' \
  FAKE_PRIV="$DENY_ALL_PRIV" FAKE_AUTH_TABLE_RESULTS="$DENY_ALL_AUTH" || FAIL=1
if grep -qF "pfin.audit_log: DENY-ALL-allowlisted but authenticated holds a column-level SELECT grant" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-ALLOWLISTED-COLGRANT-LEAK] column-grant conjunction leg caught it." >&2
else
  echo "FAIL: [RLS-DENY-ALL-ALLOWLISTED-COLGRANT-LEAK] expected column-grant refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 22c. RLS-DENY-ALL-ALLOWLISTED-AUTHTBL-LEAK -- same, but authenticated
#      holds table-level SELECT -- Sec's added conjunction column must
#      catch this even though anon's own table-level grant (checked
#      separately, unaffected) and both column-level grants are clean.
run_scenario "RLS DENY-ALL allowlisted table with authenticated table-level SELECT: refuses" 1 \
  FAKE_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
audit_log|true|0|false|true|false|false|false' \
  FAKE_PRIV="$DENY_ALL_PRIV" FAKE_AUTH_TABLE_RESULTS="$DENY_ALL_AUTH" || FAIL=1
if grep -qF "pfin.audit_log: DENY-ALL-allowlisted but authenticated holds table-level SELECT" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-ALLOWLISTED-AUTHTBL-LEAK] authenticated-table-grant conjunction leg caught it." >&2
else
  echo "FAIL: [RLS-DENY-ALL-ALLOWLISTED-AUTHTBL-LEAK] expected authenticated-table-grant refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 22d. RLS-DENY-ALL-ALLOWLISTED-ANONCOL-LEAK -- same, but anon (not
#      authenticated) holds a column-level SELECT grant -- the fourth of
#      Sec's four privilege columns; every one gets its own scenario so
#      no single column's check can be silently absent.
run_scenario "RLS DENY-ALL allowlisted table with anon column-level SELECT: refuses" 1 \
  FAKE_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
audit_log|true|0|false|false|true|false|false' \
  FAKE_PRIV="$DENY_ALL_PRIV" FAKE_AUTH_TABLE_RESULTS="$DENY_ALL_AUTH" || FAIL=1
if grep -qF "pfin.audit_log: DENY-ALL-allowlisted but anon holds a column-level SELECT grant" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-ALLOWLISTED-ANONCOL-LEAK] anon column-grant conjunction leg caught it." >&2
else
  echo "FAIL: [RLS-DENY-ALL-ALLOWLISTED-ANONCOL-LEAK] expected anon column-grant refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 23. RLS-DENY-ALL-UNLISTED -- same shape, but the table's name is NOT
#     in RLS_DENY_ALL_EXPECTED -- RLS FAILED in the ENUMERATION loop
#     itself (Sec requirement 2: never rescued by any behavioral read),
#     naming the table and the allowlist gap explicitly.
DENY_ALL_UNLISTED_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
planning_target|true|0|false|false|false|false|false'
DENY_ALL_UNLISTED_PRIV='PRIV|account|5
PRIV|account_users|3
PRIV|planning_target|2'
DENY_ALL_UNLISTED_AUTH='account|OK|0
account_users|OK|0
planning_target|OK|0'
run_scenario "RLS DENY-ALL table NOT on the allowlist: refuses" 1 \
  FAKE_RLS_ENUM="$DENY_ALL_UNLISTED_RLS_ENUM" FAKE_PRIV="$DENY_ALL_UNLISTED_PRIV" FAKE_AUTH_TABLE_RESULTS="$DENY_ALL_UNLISTED_AUTH" || FAIL=1
if grep -qF "pfin.planning_target: 0 policies in pg_policies and NOT in RLS_DENY_ALL_EXPECTED" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-DENY-ALL-UNLISTED] refusal names the table and the allowlist gap." >&2
else
  echo "FAIL: [RLS-DENY-ALL-UNLISTED] expected refusal message not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 24. RLS-ALLOWLISTED-WITH-POLICIES -- a table IN RLS_DENY_ALL_EXPECTED
#     that now carries >=1 real policy -- POLICY-SCOPED (not DENY-ALL any
#     more), reported as an INFO line, not a failure. Grant columns are
#     irrelevant on a policy-scoped table (never checked) -- authtbl=true
#     here on purpose, proving that.
ALLOWLISTED_WITH_POLICY_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
audit_log|true|1|false|true|false|false|false'
ALLOWLISTED_WITH_POLICY_PRIV='PRIV|account|5
PRIV|account_users|3
PRIV|audit_log|4'
ALLOWLISTED_WITH_POLICY_AUTH='account|OK|0
account_users|OK|0
audit_log|OK|0'
run_scenario "RLS: allowlisted table now has a policy: INFO, not a failure" 4 \
  FAKE_RLS_ENUM="$ALLOWLISTED_WITH_POLICY_RLS_ENUM" FAKE_PRIV="$ALLOWLISTED_WITH_POLICY_PRIV" FAKE_AUTH_TABLE_RESULTS="$ALLOWLISTED_WITH_POLICY_AUTH" || FAIL=1
if grep -qF "in RLS_DENY_ALL_EXPECTED but carries 1 polic" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-ALLOWLISTED-WITH-POLICIES] INFO line present, no failure." >&2
else
  echo "FAIL: [RLS-ALLOWLISTED-WITH-POLICIES] expected INFO line not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 34/35. RLS-HYBRID-* -- real-run 27 additions: a HYBRID table (a
#        SELECT/ALL policy admitting `users_id IS NULL` to every
#        authenticated caller, discovered from pg_policies.qual, never a
#        hand list). `asset`'s own FAKE_AUTH_TABLE_RESULTS row is
#        deliberately ABSENT -- proves the hybrid table is routed to
#        psql_admin_auth_read_hybrid() and never reaches the ordinary
#        per-table read at all; if it did, fake-docker's own "no
#        FAKE_AUTH_TABLE_RESULTS row for table 'asset'" precondition
#        error would fire instead, a wrong-reason red exactly like the
#        22b/22c/22d self-strike note above already guards against.
HYBRID_RLS_ENUM='account|true|1|false|false|false|false|false
account_users|true|1|false|false|false|false|false
asset|true|1|false|true|false|true|true'
HYBRID_PRIV='PRIV|account|5
PRIV|account_users|3
PRIV|asset|7'
HYBRID_AUTH='account|OK|0
account_users|OK|0'

# 34. RLS-HYBRID-VERIFIED -- the global rows (users_id NULL) ARE visible
#     (7 of them) and zero tenant (non-NULL users_id) rows are visible --
#     this is CORRECT isolation for a hybrid table, not a bypass. Counted
#     toward PROVEN_COUNT via its own HYBRID_COUNT bucket.
run_scenario "RLS HYBRID table: global rows visible, 0 tenant rows: PROVEN, not a failure" 4 \
  FAKE_RLS_ENUM="$HYBRID_RLS_ENUM" FAKE_PRIV="$HYBRID_PRIV" FAKE_AUTH_TABLE_RESULTS="$HYBRID_AUTH" \
  FAKE_AUTH_HYBRID_RESULTS="asset|OK|0|7" || FAIL=1
if grep -qF "HYBRID: pfin.asset -- 7 global rows visible (users_id NULL), 0 tenant rows visible" "$LAST_OUT" 2>/dev/null \
  && grep -qF "3 table(s) PROVEN isolated (0 via allowlisted DENY-ALL, 1 via HYBRID global-row demonstration, 2 via >=1 policy)" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-HYBRID-VERIFIED] HYBRID demonstration line + correct PROVEN breakdown present." >&2
else
  echo "FAIL: [RLS-HYBRID-VERIFIED] expected HYBRID demonstration line and/or PROVEN breakdown not found." >&2
  cat "$LAST_OUT" >&2
  FAIL=1
fi

# 35. RLS-HYBRID-BYPASS -- a row with a NON-NULL users_id is visible to a
#     session with no tenant identity established -- a REAL bypass, not
#     the by-design global-row exposure -- FAILED regardless of the
#     global-row count.
run_scenario "RLS HYBRID table: a tenant row is visible: refuses (real bypass)" 1 \
  FAKE_RLS_ENUM="$HYBRID_RLS_ENUM" FAKE_PRIV="$HYBRID_PRIV" FAKE_AUTH_TABLE_RESULTS="$HYBRID_AUTH" \
  FAKE_AUTH_HYBRID_RESULTS="asset|OK|2|9" || FAIL=1
if grep -qF "pfin.asset: HYBRID table -- 2 row(s) with a NON-NULL users_id visible to a session with NO tenant identity established" "$LAST_OUT" 2>/dev/null \
  && grep -qF "not the by-design global-row exposure" "$LAST_OUT" 2>/dev/null; then
  echo "OK: [RLS-HYBRID-BYPASS] real-bypass refusal message present, correctly distinguished from the by-design global-row exposure." >&2
else
  echo "FAIL: [RLS-HYBRID-BYPASS] expected HYBRID-bypass refusal message not found." >&2
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
