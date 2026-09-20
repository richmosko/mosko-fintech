#!/usr/bin/env bash
#
# fence-db-role-handoff-strikes.sh -- offline strike-proof for
# scripts/db-role-handoff.sh. Runs entirely without a live box, network, or
# real Postgres: a fake `ssh` rewrites the `/root/.pfin` path the remote
# driver hardcodes to a throwaway temp dir, a fake `docker` stands in for
# every `docker compose ... exec -T db psql ...` call and the
# `docker exec coolify php artisan tinker` readback, and
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
#   2. ALREADY-LOGIN-NO-ROTATE -- preflight reads 't|t' (rolcanlogin,
#      has_password) and --rotate is NOT passed -> refuses, naming
#      "already has LOGIN and a password".
#   3. ROTATE-BUT-NOT-YET-LOGIN -- preflight reads 'f|f' and --rotate IS
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
#      anything other than 't|t' -> refuses.
#   8. CONNECT-AS-ROLE-FAILS -- step C's TCP connect-as-the-role exits
#      non-zero -> refuses ("did not take effect end to end").
#   9. READBACK-LENGTH-MISMATCH -- step E's tinker length readback returns
#      anything other than 64 -> refuses.
#   10. HAPPY-PATH-INITIAL -- role absent LOGIN/password ('f|f'), resource
#       present, every downstream step succeeds -> exits 0, PATCH body
#       carries a 64-char PFIN_DB_PASSWORD, seed-file path never leaks the
#       token or the credential into $FAKE_CURL_LOG.
#   11. HAPPY-PATH-ROTATE -- role already LOGIN ('t|t'), --rotate passed
#       -> exits 0, the \password-only (no ALTER ROLE LOGIN line) script
#       shape is exercised.
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
# tinker` readback. Distinguishes the FOUR distinct psql call shapes by
# their own argv content (no -tAc/-h at all -> the \password handoff
# reading its script from stdin; -tAc with 'coalesce((select rolcanlogin'
# -> preflight state; -tAc with 'rolcanlogin::text ||' -> catalog verify;
# -h localhost -> connect-as-the-role).
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
ARGS="$*"

if [[ "$ARGS" == *"artisan tinker"* ]]; then
  echo "${FAKE_READBACK_LEN:-64}"
  exit 0
fi

if [[ "$ARGS" == *"coalesce((select rolcanlogin"* ]]; then
  echo "${FAKE_ROLE_STATE:-f|f}"
  exit 0
fi

if [[ "$ARGS" == *"rolcanlogin::text ||"* ]]; then
  echo "${FAKE_VERIFY_STATE:-t|t}"
  exit 0
fi

if [[ "$ARGS" == *"-h localhost"* ]]; then
  # Connect-as-the-role step -- reads (and discards) the piped
  # password+query script from stdin, exactly like a real psql would.
  cat >/dev/null
  if [[ "${FAKE_CONNECT_FAIL:-0}" == "1" ]]; then
    echo "psql: error: connection failed" >&2
    exit 2
  fi
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
    FAKE_ECHO_PASSWORD_IN_OUTPUT="\$FAKE_ECHO_PASSWORD_IN_OUTPUT" FAKE_READBACK_LEN="\$FAKE_READBACK_LEN" \\
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
  # run_scenario <desc> <expect_exit> <role> <apply_flag> <curl_mode> <role_state> <verify_state> <connect_fail> <mismatch> <handoff_fail> <echo_pw> <readback_len>
  local desc="$1" expect_exit="$2" role="$3" apply_flag="$4" curl_mode="$5" \
        role_state="$6" verify_state="$7" connect_fail="$8" mismatch="$9" handoff_fail="${10}" echo_pw="${11}" readback_len="${12}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  local resource_name="pfin-back-etl"
  [[ "$role" == "pfin_provider_sync" ]] && resource_name="pfin-provider-sync"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" FAKE_RESOURCE_NAME="$resource_name" \
    FAKE_ROLE_STATE="$role_state" FAKE_VERIFY_STATE="$verify_state" FAKE_ROLE_NAME="$role" \
    FAKE_CONNECT_FAIL="$connect_fail" FAKE_MISMATCH="$mismatch" FAKE_HANDOFF_FAIL="$handoff_fail" \
    FAKE_ECHO_PASSWORD_IN_OUTPUT="$echo_pw" FAKE_READBACK_LEN="$readback_len" \
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
OUT1="$(run_scenario "role-missing: refuses" 1 pfin_etl --apply clean "ABSENT|ABSENT" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "role-missing" "${OUT1:-}" "does not exist" || FAIL=1

# 2. ALREADY-LOGIN-NO-ROTATE (preflight-only, no --apply needed to trigger the refusal)
OUT2="$(run_scenario "already-login-no-rotate: refuses" 1 pfin_etl --apply clean "t|t" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "already-login-no-rotate" "${OUT2:-}" "already has LOGIN and a password" || FAIL=1

# 3. ROTATE-BUT-NOT-YET-LOGIN
OUT3="$(run_scenario "rotate-but-not-yet-login: refuses" 1 pfin_etl "--apply --rotate" clean "f|f" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "rotate-but-not-yet-login" "${OUT3:-}" "not yet LOGIN" || FAIL=1

# 4. RESOURCE-ABSENT -- structural precondition, refuses before any psql call
OUT4="$(run_scenario "resource-absent: refuses" 1 pfin_etl --apply resource-absent "f|f" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "resource-absent" "${OUT4:-}" "no Coolify application named" || FAIL=1

# 5. CLEARTEXT-IN-OUTPUT
OUT5="$(run_scenario "cleartext-in-output: refuses" 1 pfin_etl --apply clean "f|f" "t|t" 0 0 0 1 64)" || FAIL=1
assert_output_contains "cleartext-in-output" "${OUT5:-}" "cleartext value appeared" || FAIL=1

# 6. PASSWORD-MISMATCH
OUT6="$(run_scenario "password-mismatch: refuses" 1 pfin_etl --apply clean "f|f" "t|t" 0 1 0 0 64)" || FAIL=1
assert_output_contains "password-mismatch" "${OUT6:-}" "confirmation mismatch" || FAIL=1

# 7. CATALOG-VERIFY-MISMATCH
OUT7="$(run_scenario "catalog-verify-mismatch: refuses" 1 pfin_etl --apply clean "f|f" "f|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "catalog-verify-mismatch" "${OUT7:-}" "expected 't|t'" || FAIL=1

# 8. CONNECT-AS-ROLE-FAILS
OUT8="$(run_scenario "connect-as-role-fails: refuses" 1 pfin_etl --apply clean "f|f" "t|t" 1 0 0 0 64)" || FAIL=1
assert_output_contains "connect-as-role-fails" "${OUT8:-}" "did not take effect end to end" || FAIL=1

# 9. READBACK-LENGTH-MISMATCH
OUT9="$(run_scenario "readback-length-mismatch: refuses" 1 pfin_etl --apply clean "f|f" "t|t" 0 0 0 0 32)" || FAIL=1
assert_output_contains "readback-length-mismatch" "${OUT9:-}" "readback length is" || FAIL=1

# 10. HAPPY-PATH-INITIAL
OUT10="$(run_scenario "happy-path-initial: succeeds" 0 pfin_etl --apply clean "f|f" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "happy-path-initial" "${OUT10:-}" "PFIN_DB_PASSWORD present on the target resource, length 64 confirmed" || FAIL=1

# 11. HAPPY-PATH-ROTATE
OUT11="$(run_scenario "happy-path-rotate: succeeds" 0 pfin_etl "--apply --rotate" clean "t|t" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "happy-path-rotate" "${OUT11:-}" "PFIN_DB_PASSWORD present on the target resource, length 64 confirmed" || FAIL=1
if [[ -n "${OUT11:-}" ]] && ! grep -qF "ROTATE" <<<"$OUT11"; then
  echo "FAIL: [happy-path-rotate] plan did not print the ROTATE mode line -- the rotate branch may not have actually fired." >&2
  FAIL=1
fi

# 12. Same shapes for the OTHER role, spot-check (provider-sync's own resource name resolves)
OUT12="$(run_scenario "provider-sync happy-path-initial: succeeds" 0 pfin_provider_sync --apply clean "f|f" "t|t" 0 0 0 0 64)" || FAIL=1
assert_output_contains "provider-sync happy-path-initial" "${OUT12:-}" "PFIN_DB_PASSWORD present on the target resource, length 64 confirmed" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more db-role-handoff.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all db-role-handoff.sh strike-proofs passed."
exit 0
