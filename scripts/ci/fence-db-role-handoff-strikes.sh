#!/usr/bin/env bash
#
# fence-db-role-handoff-strikes.sh -- offline strike-proof for
# scripts/db-role-handoff.sh. Runs entirely without a live box, network, or
# real Postgres: a fake `ssh` rewrites the `/root/.pfin` path the remote
# driver hardcodes to a throwaway temp dir, a fake `docker` stands in for
# every `docker compose ... exec -T db psql ...` call and the
# `docker exec coolify php artisan tinker --execute` readback, and
# tests/fixtures/ci/db-role-handoff/fake-curl stands in for curl
# (PATH-shadowed, canned Coolify-API-shaped responses).
# scripts/db-role-handoff.sh itself is never modified or made aware any of
# this exists. Same strike shape as scripts/ci/fence-provision-worker-
# strikes.sh.
#
# Scenarios (BACKLOG.md §7.36 item 68, W-2; Sec joint-review is mandatory
# on the PR this fence ships in, not on this fence's own design):
#   1. ROLE-MISSING     -- preflight reads 'ABSENT|ABSENT' -> refuses,
#      naming "does not exist", before --apply is even reached.
#   2. ALREADY-HANDED-OFF-VERIFIED-NO-OP (team-lead follow-up, live
#      --dry-run, provision.sh sweep, 2026-09-20 -- REPLACES the old
#      "already-login-no-rotate: refuses" scenario) -- role already
#      LOGIN+password set AND the worker resource's store already
#      carries PFIN_DB_PASSWORD -> VERIFIED, exit 0, no-op, even with
#      --apply and without --rotate. Restores provision.sh's "re-run =
#      no-op" contract for etl-role/provider-sync-role.
#   2b. MISMATCH-LOGIN-NO-STORE-VALUE -- role LOGIN+password set but the
#       store does NOT carry PFIN_DB_PASSWORD -> refuses, "INCONSISTENT"
#       -- the guard still fires on a genuinely broken state.
#   2c. MISMATCH-STORE-VALUE-NO-LOGIN -- store carries PFIN_DB_PASSWORD
#       but the role is not yet LOGIN -> refuses, "INCONSISTENT".
#   2d. AMBIGUOUS-STORE-STATE (Sec F-5, PR #852 AMBER review) -- the store
#       readback itself finds MORE than one matching row (store_count=2)
#       -> refuses, "refusing to trust an ambiguous store state".
#   2e. STORE-READ-FAILED (Sec N-3, PR #852 AMBER review round 2) -- the
#       tinker call produces NO output at all (crashed/unreachable) ->
#       refuses the same way, "refusing to trust an ambiguous store
#       state".
#   3. ROTATE-BUT-NOT-YET-LOGIN -- preflight reads 'false|false' and --rotate IS
#      passed -> refuses, naming "not yet LOGIN".
#   4. RESOURCE-ABSENT  -- the target Coolify resource does not exist ->
#      refuses BEFORE any credential is generated or any psql call is
#      made (structural precondition, not skippable).
#   5. CLEARTEXT-IN-OUTPUT -- the fake psql's handoff step ECHOES the
#      credential back (simulating a hypothetical psql/transport bug) ->
#      the script's own `grep -qF "$PW"` guard fires and refuses, proving
#      that guard is load-bearing, not decorative.
#   6. PASSWORD-MISMATCH -- the fake psql prints "Passwords didn't match."
#      (psql's own real exit-0-on-mismatch behaviour, measured locally
#      against a throwaway Postgres instance this PR) -> the script's own
#      mismatch-string guard fires and refuses, rather than trusting the
#      exit code alone.
#   7. CATALOG-VERIFY-MISMATCH -- step B's post-handoff read returns
#      anything other than 'true|true' -> refuses.
#   8. CONNECT-AS-ROLE-FAILS -- step C's TCP connect-as-the-role exits
#      non-zero -> refuses ("did not take effect end to end").
#   9. READBACK-COUNT-MISMATCH -- step E's hash-bound readback (Sec F-2,
#      PR #846 review) finds anything other than exactly ONE is_preview=
#      false 'PFIN_DB_PASSWORD' row on the target resource -> refuses,
#      never falling back to `->first()`'s silent pick.
#   10. HAPPY-PATH-INITIAL -- role absent LOGIN/password ('false|false'), resource
#       present, every downstream step succeeds -> exits 0, PATCH body
#       carries a 64-char PFIN_DB_PASSWORD, seed-file path never leaks the
#       token or the credential into $FAKE_CURL_LOG.
#   11. HAPPY-PATH-ROTATE -- role already LOGIN ('true|true'), --rotate passed
#       -> exits 0, the \password-only (no ALTER ROLE LOGIN line) script
#       shape is exercised.
#   12. PROVIDER-SYNC-HAPPY-PATH -- same shapes as #10, spot-checked
#       against the OTHER role, proving provider-sync's own resource name
#       resolves too.
#   13. TRUST-PATH-NO-PROMPT (Sec VETO V-1, PR #846 review) -- the fake
#       psql's step-C branch does NOT emit "Password for user" and instead
#       echoes stdin line 1 (the cleartext credential) back inside a
#       fabricated syntax-error message, matching the measured
#       127.0.0.1/32 `trust` pg_hba.conf rule
#       (supabase/migrations/055_pfin_etl_role.sql:277-282) that a
#       `-h localhost` connection from inside the db container itself
#       would hit. The script's own missing-prompt guard must fire and
#       refuse -- exit 1, not the historical (pre-fix) exit 0.
#   14. READBACK-HASH-MISMATCH (Sec F-2) -- exactly one production
#       PFIN_DB_PASSWORD row exists on the target resource, but its
#       truncated SHA-256 does not match the credential THIS run
#       generated -- refuses, proving the hash-binding check is a real,
#       independent guard and not decoration alongside #9's count check.
#   15. PFIN-DB-USER-MISMATCH-INITIAL (Sec F-4) -- PFIN_DB_USER on the
#       target resource does not yet equal the role being handed off (the
#       documented provider-sync pre-cutover shape) -- WARNS, does not
#       refuse, on a plain --apply run: exit 0.
#   16. PFIN-DB-USER-MISMATCH-ROTATE (Sec F-4) -- same mismatch, but under
#       --rotate, where PFIN_DB_USER should already match (rotate implies
#       the role is already LOGIN'd) -- refuses: exit 1.
#   17. CONNECT-CLEARTEXT-LEAK (Sec F-6) -- the connect-as-role prompt DOES
#       print (unlike #13's trust-path bypass) but the credential also
#       leaks elsewhere in the captured output -- refuses via the
#       CONNECT_OUT cleartext guard specifically, proven in isolation from
#       the missing-prompt guard.
#   18. STEP-C-STRUCTURAL-PIN (Sec F-7) -- a source-literal (not runtime)
#       assertion that db-role-handoff.sh's connect-as-role psql
#       invocation carries both `-v ON_ERROR_STOP=1` and `-h db` together,
#       standing in for two properties an offline fake cannot observe
#       behaviorally (ON_ERROR_STOP's exit-code effect) or observes only
#       incidentally (the hostname, pinned by the fake's own matcher).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/db-role-handoff"
DB_ROLE_HANDOFF_SH="$REPO_ROOT/scripts/db-role-handoff.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$DB_ROLE_HANDOFF_SH" ]] || { echo "FATAL: $DB_ROLE_HANDOFF_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- stands in for every `docker compose --project-name X
# exec -T db psql ...` call and the `docker exec coolify php artisan
# tinker --execute` readback. Distinguishes the FOUR distinct psql call
# shapes by their own argv content (no -tAc/-h at all -> the \password
# handoff reading its script from stdin; -tAc with 'coalesce((select
# rolcanlogin' -> preflight state; -tAc with 'rolcanlogin::text ||' ->
# catalog verify; -h db -> connect-as-the-role).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
ARGS="$*"

if [[ "$ARGS" == *"artisan tinker --execute"* ]]; then
  # team-lead follow-up (live --dry-run, provision.sh sweep, 2026-09-20):
  # the NEW preflight store-count check (a bare `->count()`, no hash
  # binding -- that only makes sense AFTER this run has generated a
  # credential) is distinguished from leg E's own readback (below) by the
  # ABSENCE of "hash(" in the tinker script body -- leg E's own query
  # always contains "hash('sha256'".
  if [[ "$ARGS" != *"hash("* ]]; then
    # Sec N-3 (PR #852 AMBER review round 2): `${FAKE_STORE_COUNT:-0}`
    # (with the colon) treats "set but empty" the SAME as "unset" --
    # scenario 2e below passes an EXPLICIT empty string to model the
    # tinker call itself producing no output (crashed/timed out, the
    # store-read-failed case db-role-handoff.sh:381's `*)` arm also
    # catches, far likelier in practice than two rows), which the colon
    # form would have silently defaulted back to "0" ("fresh"). No
    # colon -- only a genuinely OMITTED FAKE_STORE_COUNT defaults.
    echo "${FAKE_STORE_COUNT-0}"
    exit 0
  fi
  # F-2/F-4 (PR #846 review) -- the real readback is now
  # "count|truncated-hash|PFIN_DB_USER-value", not a bare length. SEED_FILE
  # is inherited as a real environment variable here (set via the calling
  # `env SEED_FILE=... bash -s` prefix in the remote session, and docker's
  # own child-process inherits its parent shell's env like any subprocess)
  # -- reading it and hashing its exact bytes the same way the real script
  # hashes $PW is what lets this fake prove the hash-binding guard, not
  # just the row-count guard, is load-bearing. FAKE_READBACK_USER defaults
  # to the role being handed off (the "already matches, no ordering
  # hazard" happy-path shape); set it to a different value to strike F-4's
  # ordering guard.
  USER_VAL="${FAKE_READBACK_USER:-${FAKE_ROLE_NAME:-pfin_etl}}"
  if [[ -n "${FAKE_READBACK_COUNT:-}" ]]; then
    echo "${FAKE_READBACK_COUNT}||$USER_VAL"
    exit 0
  fi
  if [[ -z "${SEED_FILE:-}" || ! -f "$SEED_FILE" ]]; then
    echo "FAKE DOCKER: readback called but SEED_FILE ('${SEED_FILE:-unset}') is not a real file" >&2
    exit 1
  fi
  ACTUAL_HASH="$(sha256sum "$SEED_FILE" | cut -c1-16)"
  if [[ "${FAKE_READBACK_HASH_MISMATCH:-0}" == "1" ]]; then
    echo "1|0000000000000000|$USER_VAL"
    exit 0
  fi
  echo "1|$ACTUAL_HASH|$USER_VAL"
  exit 0
fi

if [[ "$ARGS" == *"coalesce((select rolcanlogin"* ]]; then
  echo "${FAKE_ROLE_STATE:-false|false}"
  exit 0
fi

if [[ "$ARGS" == *"rolcanlogin::text ||"* ]]; then
  echo "${FAKE_VERIFY_STATE:-true|true}"
  exit 0
fi

if [[ "$ARGS" == *"-h db"* ]]; then
  # Connect-as-the-role step. SCRIPT_IN's first line is the password (or,
  # under FAKE_NO_PASSWORD_PROMPT, what a trust-path connection would
  # instead consume as a SQL statement); second line is the query.
  SCRIPT_IN="$(cat)"
  FIRST_LINE="$(printf '%s\n' "$SCRIPT_IN" | head -1)"
  if [[ "${FAKE_CONNECT_FAIL:-0}" == "1" ]]; then
    # Models a genuine password-authenticated connection that fails for an
    # UNRELATED reason (wrong password, DB unreachable after the prompt,
    # etc) -- distinct from scenario 13's trust-path bypass: the prompt
    # DOES appear here, so this exercises the exit-code guard specifically,
    # not the missing-prompt guard.
    echo "Password for user ${FAKE_ROLE_NAME:-pfin_etl}: "
    echo "psql: error: connection failed" >&2
    exit 2
  fi
  if [[ "${FAKE_NO_PASSWORD_PROMPT:-0}" == "1" ]]; then
    # Sec VETO V-1 (PR #846 review) -- simulates the measured `trust`-path
    # hazard: no password prompt at all, so the first stdin line (the
    # cleartext credential) is consumed as a SQL statement and echoed back
    # inside psql's own syntax-error text (the same shape a real
    # server-log capture via log_min_error_statement would carry). NO
    # "Password for user" line is printed. Historically (pre-fix) the
    # script still saw a current_user block and exited 0; this fake still
    # PRINTS that block, so the strike proves the missing-prompt guard is
    # what catches this, not a change in what psql itself reports. Sec F-6
    # (PR #846 review) -- CORRECTED comment: this scenario does NOT also
    # prove the separate cleartext-in-CONNECT_OUT guard, even though the
    # cleartext happens to appear in this fake's own output too -- the
    # missing-prompt guard runs first and exits before the cleartext grep
    # is ever reached (measured: deleting the cleartext grep alone leaves
    # this scenario, and the whole suite, green). The cleartext guard has
    # its OWN dedicated scenario below (FAKE_ECHO_PW_IN_CONNECT) where the
    # prompt DOES print, so the missing-prompt guard cannot absorb the
    # strike.
    echo "psql:<stdin>:1: ERROR:  syntax error at or near \"$FIRST_LINE\""
    echo "LINE 1: $FIRST_LINE"
    echo " current_user "
    echo "--------------"
    echo " ${FAKE_ROLE_NAME:-pfin_etl}"
    exit 0
  fi
  if [[ "${FAKE_ECHO_PW_IN_CONNECT:-0}" == "1" ]]; then
    # Sec F-6 (PR #846 review) -- the dedicated cleartext-guard scenario the
    # comment above now correctly says NO OTHER scenario provides: the
    # prompt DOES print (a normal, password-authenticated connection), but
    # the credential ALSO leaks into the output elsewhere -- a plausible
    # transport/echo bug on an otherwise-unremarkable connection, not a
    # trust-path bypass. With the prompt present, the missing-prompt guard
    # passes and cannot absorb this strike; only the CONNECT_OUT cleartext
    # grep can catch it.
    echo "Password for user ${FAKE_ROLE_NAME:-pfin_etl}: "
    echo "DEBUG (simulated transport bug): last line was $FIRST_LINE"
    echo " current_user "
    echo "--------------"
    echo " ${FAKE_ROLE_NAME:-pfin_etl}"
    exit 0
  fi
  echo "Password for user ${FAKE_ROLE_NAME:-pfin_etl}: "
  echo " current_user "
  echo "--------------"
  echo " ${FAKE_ROLE_NAME:-pfin_etl}"
  exit 0
fi

if [[ "$ARGS" == *"exec -T db psql"* && "$ARGS" != *"-tAc"* ]]; then
  # The \password handoff step -- reads its script from stdin (role name +
  # two password lines + optionally ALTER ROLE ... LOGIN;). A real psql
  # NEVER echoes the typed password back; this fake matches that unless
  # FAKE_ECHO_PASSWORD_IN_OUTPUT asks it to, on purpose, to strike the
  # calling script's own cleartext-in-output guard.
  SCRIPT_IN="$(cat)"
  ROLE_LINE="$(printf '%s\n' "$SCRIPT_IN" | head -1)"
  ROLE_NAME="${ROLE_LINE#\\password }"
  echo "Enter new password for user \"$ROLE_NAME\": "
  echo "Enter it again: "
  if [[ "${FAKE_MISMATCH:-0}" == "1" ]]; then
    echo "Passwords didn't match."
    exit 0
  fi
  if [[ "${FAKE_ECHO_PASSWORD_IN_OUTPUT:-0}" == "1" ]]; then
    # Deliberately misbehave -- echoes the SECOND line of the script
    # (one of the two password lines) back, simulating a hypothetical
    # transport bug. This is what scenario 5 strikes.
    printf '%s\n' "$SCRIPT_IN" | sed -n '2p'
  fi
  if [[ "${FAKE_HANDOFF_FAIL:-0}" == "1" ]]; then
    echo "psql: error: could not connect" >&2
    exit 1
  fi
  exit 0
fi

echo "FAKE DOCKER: unrecognised invocation: $ARGS" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

# Fake `ssh` -- same shape as fence-provision-worker-strikes.sh's own:
# rewrites /root/.pfin, forwards the FAKE_* env vars into the sub-shell so
# both fake-curl and fake-docker see them, PATH-shadows curl/docker for
# every nested invocation.
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
  # db-role-handoff.sh's own "env ... SEED_FILE=\"/root/.pfin/...\" bash -s"
  # prefix carries a /root/.pfin PATH VALUE inside an env-assignment, not
  # just inside the heredoc body -- rewrite CMDLINE itself too, or the
  # inner bash -s sees an env var pointing at a path that was never
  # actually written under the fake sandbox.
  CMDLINE="\$(printf '%s' "\$CMDLINE" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" \\
    FAKE_CURL_LOG="\$FAKE_CURL_LOG" FAKE_CURL_MODE="\$FAKE_CURL_MODE" FAKE_RESOURCE_NAME="\$FAKE_RESOURCE_NAME" \\
    FAKE_ROLE_STATE="\$FAKE_ROLE_STATE" FAKE_VERIFY_STATE="\$FAKE_VERIFY_STATE" FAKE_ROLE_NAME="\$FAKE_ROLE_NAME" \\
    FAKE_CONNECT_FAIL="\$FAKE_CONNECT_FAIL" FAKE_MISMATCH="\$FAKE_MISMATCH" FAKE_HANDOFF_FAIL="\$FAKE_HANDOFF_FAIL" \\
    FAKE_ECHO_PASSWORD_IN_OUTPUT="\$FAKE_ECHO_PASSWORD_IN_OUTPUT" FAKE_READBACK_COUNT="\$FAKE_READBACK_COUNT" \\
    FAKE_NO_PASSWORD_PROMPT="\$FAKE_NO_PASSWORD_PROMPT" FAKE_READBACK_HASH_MISMATCH="\$FAKE_READBACK_HASH_MISMATCH" \\
    FAKE_READBACK_USER="\$FAKE_READBACK_USER" FAKE_ECHO_PW_IN_CONNECT="\$FAKE_ECHO_PW_IN_CONNECT" \\
    FAKE_STORE_COUNT="\$FAKE_STORE_COUNT" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
# Plain command form (the seed-file write: printf PW piped into sshx
# "umask 077; mkdir -p /root/.pfin; cat > SEED_FILE") -- rewrite the path
# and run it, INHERITING this wrapper's own stdin so the piped seed
# content reaches the rewritten cat-redirect target.
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <role> <apply_flag> <curl_mode> <role_state> <verify_state> <connect_fail> <mismatch> <handoff_fail> <echo_pw> <readback_count> [no_prompt] [hash_mismatch] [readback_user] [echo_pw_in_connect] [store_count]
  # <readback_count>: empty string -> fake computes a REAL count=1 + hash
  # bound to the actual generated credential (happy path); a digit ->
  # forces that row-count, striking the count-mismatch guard.
  # <readback_user>: empty string -> fake reports PFIN_DB_USER == <role>
  # (no ordering hazard); a different role name -> strikes Sec F-4's
  # ordering guard.
  # <echo_pw_in_connect>: 1 -> the connect-as-role fake prints the prompt
  # normally AND also leaks the credential elsewhere in its output (Sec
  # F-6's dedicated cleartext-guard scenario).
  # <store_count> (team-lead follow-up, 2026-09-20): the NEW preflight
  # store-count check's own answer -- "does '$resource_name' already
  # carry a production PFIN_DB_PASSWORD row". Defaults to 0 (matches
  # every pre-existing "false|false" scenario's own fresh-state assumption,
  # unaffected by this parameter's addition); scenarios exercising the
  # already-handed-off / mismatched-state logic set it explicitly.
  local desc="$1" expect_exit="$2" role="$3" apply_flag="$4" curl_mode="$5" \
        role_state="$6" verify_state="$7" connect_fail="$8" mismatch="$9" handoff_fail="${10}" echo_pw="${11}" readback_count="${12}" no_prompt="${13:-0}" hash_mismatch="${14:-0}" readback_user="${15:-}" echo_pw_in_connect="${16:-0}" store_count="${17-0}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  local resource_name="pfin-back-etl"
  [[ "$role" == "pfin_provider_sync" ]] && resource_name="pfin-provider-sync"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" FAKE_RESOURCE_NAME="$resource_name" \
    FAKE_ROLE_STATE="$role_state" FAKE_VERIFY_STATE="$verify_state" FAKE_ROLE_NAME="$role" \
    FAKE_CONNECT_FAIL="$connect_fail" FAKE_MISMATCH="$mismatch" FAKE_HANDOFF_FAIL="$handoff_fail" \
    FAKE_ECHO_PASSWORD_IN_OUTPUT="$echo_pw" FAKE_READBACK_COUNT="$readback_count" \
    FAKE_NO_PASSWORD_PROMPT="$no_prompt" FAKE_READBACK_HASH_MISMATCH="$hash_mismatch" \
    FAKE_READBACK_USER="$readback_user" FAKE_ECHO_PW_IN_CONNECT="$echo_pw_in_connect" \
    FAKE_STORE_COUNT="$store_count" \
    bash "$DB_ROLE_HANDOFF_SH" "$role" $apply_flag < /dev/null > "$WORK/out.$$" 2>&1
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

# 1. ROLE-MISSING
OUT1="$(run_scenario "role-missing: refuses" 1 pfin_etl --apply clean "ABSENT|ABSENT" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "role-missing" "${OUT1:-}" "does not exist" || FAIL=1

# 2. ALREADY-HANDED-OFF-VERIFIED-NO-OP (team-lead follow-up, live
#    --dry-run, provision.sh sweep, 2026-09-20 -- REPLACES the OLD
#    "already-login-no-rotate: refuses" scenario, which tested exactly
#    the defect this fix closes). Role already LOGIN + password set
#    ('true|true') AND the worker resource already carries a production
#    PFIN_DB_PASSWORD row -> VERIFIED, exit 0, no-op -- even with --apply
#    passed, even without --rotate. This is what actually restores
#    provision.sh's "re-run = no-op" contract for etl-role/provider-
#    sync-role: the OLD unconditional refusal here broke a plain second
#    pass over an already-successfully-handed-off role, the exact same
#    class of defect provision-supabase-stack.sh's db-data-volume guard
#    had.
OUT2="$(run_scenario "already-handed-off: VERIFIED no-op" 0 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1)" || FAIL=1
assert_output_contains "already-handed-off" "${OUT2:-}" "already handed off" || FAIL=1
assert_output_contains "already-handed-off" "${OUT2:-}" "VERIFIED" || FAIL=1
# Sec F-1 (PR #852 AMBER review), option (a)+(c) -- this no-op path is
# existence-only (does not re-verify the store's value still matches
# Postgres's LIVE password); pin that the loud caveat actually prints on
# every no-op run, not just in the header comment.
assert_output_contains "already-handed-off" "${OUT2:-}" "existence-only check" || FAIL=1

# 2d. AMBIGUOUS-STORE-STATE (Sec F-5, PR #852 AMBER review) -- the store
#     readback itself finds MORE than one matching row (store_count=2), a
#     state the script already refuses to trust rather than guessing
#     which row is authoritative -- pins the message this repurposed
#     scenario 2 (and the OLD version's die() at line ~386) has always
#     had, but which no fence scenario exercised until now.
OUT2D="$(run_scenario "ambiguous-store-state: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 2)" || FAIL=1
assert_output_contains "ambiguous-store-state" "${OUT2D:-}" "refusing to trust an ambiguous store state" || FAIL=1

# 2e. STORE-READ-FAILED (Sec N-3, PR #852 AMBER review round 2) -- the
#     tinker call itself produces NO output (crashed, timed out, docker
#     unreachable) -- a case db-role-handoff.sh:381's `*)` arm ALSO
#     catches (STORE_COUNT is neither "0" nor "1"), and far likelier in
#     practice than 2d's two-rows case, but nothing in this fence
#     exercised it until now: the fake's own `${FAKE_STORE_COUNT:-0}`
#     (with the colon) silently defaulted an explicit empty string back
#     to "0" ("fresh"), masking exactly the scenario meant to prove the
#     refusal fires on this path too.
OUT2E="$(run_scenario "store-read-failed: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 "")" || FAIL=1
assert_output_contains "store-read-failed" "${OUT2E:-}" "refusing to trust an ambiguous store state" || FAIL=1

# 2b. MISMATCH-LOGIN-NO-STORE-VALUE (team-lead's own named strike --
#     "LOGIN but no store value") -- role already LOGIN + password set,
#     but the worker resource's store does NOT carry PFIN_DB_PASSWORD.
#     This is a genuinely broken state (the DB got a credential, but it
#     was never pushed, or was wiped, from the worker's own Coolify env)
#     -- refuses, naming "INCONSISTENT". The guard must still fire; this
#     is not a loosening, only the ALL-THREE-true and ALL-THREE-false
#     states are non-refusals now.
OUT2B="$(run_scenario "mismatch-login-no-store-value: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 0)" || FAIL=1
assert_output_contains "mismatch-login-no-store-value" "${OUT2B:-}" "INCONSISTENT" || FAIL=1

# 2c. MISMATCH-STORE-VALUE-NO-LOGIN (team-lead's own named strike --
#     "store value but NOLOGIN") -- the worker resource's store DOES
#     carry PFIN_DB_PASSWORD, but the role is not yet LOGIN/no password
#     set. A partial/inconsistent state (perhaps a prior run pushed to
#     Coolify but died before the DB ALTER) -- refuses rather than
#     silently minting ANOTHER credential over an already-populated
#     store.
OUT2C="$(run_scenario "mismatch-store-value-no-login: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 1)" || FAIL=1
assert_output_contains "mismatch-store-value-no-login" "${OUT2C:-}" "INCONSISTENT" || FAIL=1

# 3. ROTATE-BUT-NOT-YET-LOGIN
OUT3="$(run_scenario "rotate-but-not-yet-login: refuses" 1 pfin_etl "--apply --rotate" clean "false|false" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "rotate-but-not-yet-login" "${OUT3:-}" "not yet LOGIN" || FAIL=1

# 4. RESOURCE-ABSENT -- structural precondition, refuses before any psql call
OUT4="$(run_scenario "resource-absent: refuses" 1 pfin_etl --apply resource-absent "false|false" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "resource-absent" "${OUT4:-}" "no Coolify application named" || FAIL=1

# 5. CLEARTEXT-IN-OUTPUT
OUT5="$(run_scenario "cleartext-in-output: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 1 "")" || FAIL=1
assert_output_contains "cleartext-in-output" "${OUT5:-}" "cleartext value appeared" || FAIL=1

# 6. PASSWORD-MISMATCH
OUT6="$(run_scenario "password-mismatch: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 1 0 0 "")" || FAIL=1
assert_output_contains "password-mismatch" "${OUT6:-}" "confirmation mismatch" || FAIL=1

# 7. CATALOG-VERIFY-MISMATCH
OUT7="$(run_scenario "catalog-verify-mismatch: refuses" 1 pfin_etl --apply clean "false|false" "false|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "catalog-verify-mismatch" "${OUT7:-}" "expected 'true|true'" || FAIL=1

# 8. CONNECT-AS-ROLE-FAILS
OUT8="$(run_scenario "connect-as-role-fails: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 1 0 0 0 "")" || FAIL=1
assert_output_contains "connect-as-role-fails" "${OUT8:-}" "did not take effect end to end" || FAIL=1

# 9. READBACK-COUNT-MISMATCH (Sec F-2)
OUT9="$(run_scenario "readback-count-mismatch: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 0)" || FAIL=1
assert_output_contains "readback-count-mismatch" "${OUT9:-}" "expected exactly 1" || FAIL=1

# 10. HAPPY-PATH-INITIAL
OUT10="$(run_scenario "happy-path-initial: succeeds" 0 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "happy-path-initial" "${OUT10:-}" "hash-bound to the generated credential confirmed" || FAIL=1

# 11. HAPPY-PATH-ROTATE
OUT11="$(run_scenario "happy-path-rotate: succeeds" 0 pfin_etl "--apply --rotate" clean "true|true" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "happy-path-rotate" "${OUT11:-}" "hash-bound to the generated credential confirmed" || FAIL=1
if [[ -n "${OUT11:-}" ]] && ! grep -qF "ROTATE" <<<"$OUT11"; then
  echo "FAIL: [happy-path-rotate] plan did not print the ROTATE mode line -- the rotate branch may not have actually fired." >&2
  FAIL=1
fi

# 12. Same shapes for the OTHER role, spot-check (provider-sync's own resource name resolves)
OUT12="$(run_scenario "provider-sync happy-path-initial: succeeds" 0 pfin_provider_sync --apply clean "false|false" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "provider-sync happy-path-initial" "${OUT12:-}" "hash-bound to the generated credential confirmed" || FAIL=1

# 13. TRUST-PATH-NO-PROMPT (Sec VETO V-1, PR #846 review) -- paired golden
#     test: the fake psql's step-C branch does NOT emit "Password for
#     user" and instead echoes the piped credential back inside a
#     fabricated syntax-error message (the measured 127.0.0.1/32 `trust`
#     rule shape). Before the V-1 fix this scenario exited 0 (false OK);
#     the new missing-prompt guard must now refuse it -- exit 1.
OUT13="$(run_scenario "trust-path-no-prompt: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 1)" || FAIL=1
assert_output_contains "trust-path-no-prompt" "${OUT13:-}" "no password prompt was observed" || FAIL=1

# 14. READBACK-HASH-MISMATCH (Sec F-2) -- exactly one production row exists,
#     but its value's truncated hash does NOT match the credential this run
#     generated (a stale/different secret already occupying the key) ->
#     refuses, proving the count-only check from #9 is not the only guard.
OUT14="$(run_scenario "readback-hash-mismatch: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 1)" || FAIL=1
assert_output_contains "readback-hash-mismatch" "${OUT14:-}" "DIFFERENT value than what was pushed" || FAIL=1

# 15. PFIN-DB-USER-MISMATCH-INITIAL (Sec F-4) -- provider-sync's own
#     documented pre-cutover state (PFIN_DB_USER=authenticator while
#     handing off pfin_provider_sync) -- a NON-fatal warning, not a
#     refusal, since this is the expected, documented staging flow
#     (docs/deployment-runbook.md §7.2). Must still exit 0.
OUT15="$(run_scenario "pfin-db-user-mismatch-initial: warns, succeeds" 0 pfin_provider_sync --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 authenticator)" || FAIL=1
assert_output_contains "pfin-db-user-mismatch-initial" "${OUT15:-}" "EXPECTED mid-cutover staging state" || FAIL=1

# 16. PFIN-DB-USER-MISMATCH-ROTATE (Sec F-4) -- --rotate implies the role
#     is already LOGIN'd and PFIN_DB_USER should already match; a mismatch
#     here means a credential is being rotated for a role the resource
#     isn't even wired to use -- refuses.
OUT16="$(run_scenario "pfin-db-user-mismatch-rotate: refuses" 1 pfin_etl "--apply --rotate" clean "true|true" "true|true" 0 0 0 0 "" 0 0 authenticator)" || FAIL=1
assert_output_contains "pfin-db-user-mismatch-rotate" "${OUT16:-}" "refusing to rotate a credential for a role the resource is not configured to use" || FAIL=1

# 17. CONNECT-CLEARTEXT-LEAK (Sec F-6, PR #846 review) -- dedicated strike
#     for the CONNECT_OUT cleartext guard specifically. The prompt DOES
#     print (a normal, password-authenticated connection -- distinct from
#     scenario 13's trust-path bypass), so the missing-prompt guard passes
#     and cannot absorb this strike; only the CONNECT_OUT `grep -qF "$PW"`
#     guard can catch a plausible transport/echo bug leaking the
#     credential elsewhere in an otherwise-normal connection's output.
OUT17="$(run_scenario "connect-cleartext-leak: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 1)" || FAIL=1
assert_output_contains "connect-cleartext-leak" "${OUT17:-}" "the credential's cleartext value appeared in the connect-as-role step's own captured output" || FAIL=1

# 18. STEP-C-STRUCTURAL-PIN (Sec F-7, PR #846 review) -- a source-literal
#     assertion, not a runtime scenario: an offline fake psql cannot model
#     psql's own exit-code semantics under `-v ON_ERROR_STOP=1` without
#     simply being told the answer (FAKE_CONNECT_FAIL sets an exit code
#     directly, exercising the RC guard, not ON_ERROR_STOP's effect), and
#     without this check `-h db` is pinned only INCIDENTALLY by the fake's
#     own `*"-h db"*` matcher -- a future fixture refactor broadening that
#     matcher would silently unpin the hostname with no test going red.
#     This converts both into STATED properties: the step-C invocation
#     line in the real script must carry both flags, verbatim, together.
if ! grep -qE 'psql[^"'"'"']*-v ON_ERROR_STOP=1[^"'"'"']*-h db' "$DB_ROLE_HANDOFF_SH"; then
  echo "FAIL: [step-c-structural-pin] $DB_ROLE_HANDOFF_SH's connect-as-role invocation no longer carries both '-v ON_ERROR_STOP=1' and '-h db' on the same psql call -- the offline fake cannot observe either property behaviorally, so this source-literal pin is the only thing standing between a silent regression and a false green." >&2
  FAIL=1
else
  echo "OK: [step-c-structural-pin] $DB_ROLE_HANDOFF_SH's connect-as-role invocation carries both '-v ON_ERROR_STOP=1' and '-h db'." >&2
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more db-role-handoff.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all db-role-handoff.sh strike-proofs passed."
exit 0
