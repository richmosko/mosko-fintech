#!/usr/bin/env bash
#
# fence-coolify-env-strikes.sh -- offline strike-proofs for
# scripts/coolify-env.sh. Runs entirely without a live box or network:
# a fake `ssh` (this file) rewrites the `/root/.pfin` paths coolify-env.sh's
# remote driver hardcodes to a throwaway temp dir, then runs that driver
# locally with tests/fixtures/ci/coolify-env/fake-curl standing in for
# curl (PATH-shadowed, canned Coolify-API-shaped responses -- coolify-env.sh
# itself is never modified or made aware this exists).
#
# Proves THREE things coolify-env.sh's own header claims, each as a real
# strike (not merely "the code looks right"):
#   1. `set` refuses a secrets-manifest.yml-declared name, even one that
#      would otherwise resolve through the SET_ALLOWLIST/manifest check --
#      no ssh/curl call happens at all (checked: the log file stays empty).
#   2. `set --apply` FAILS when the on-box byte-exact read-back disagrees
#      with what was just written (fake-curl's `mismatch` mode) -- proves
#      the read-back assertion is load-bearing, not decorative.
#   3. `delete --apply` FAILS when the on-box absence read-back still
#      shows the target key present after a DELETE call (fake-curl's
#      `blanked` mode -- the "blanked, not deleted" shape
#      docs/deployment-runbook.md §6.8 step 10 names) -- proves the
#      absence assertion is checked BY NAME, not inferred from the DELETE
#      call's own reported success.
#
# Each scenario ALSO asserts the fake Coolify API token string never
# appears in any fake-curl invocation's own argv (captured verbatim to a
# log file) -- the mechanism claim (`-K <tempfile>`, never `-H` on argv)
# checked by measurement, not by re-reading the script and agreeing with
# itself.
#
# Also proves (Sec F-5, PR #846 review) that `set`'s value-shape
# constraints on PFIN_DB_USER (one of the three DB roles this repo mints)
# and ADMISSION_PROBE_PUBLIC_URLS (bare comma-separated https:// FQDNs,
# echoed verbatim into Discord alerts) are load-bearing, not decorative --
# each accepts its documented valid shapes and refuses every invalid one.
#
# Exit 0 only if every scenario behaves exactly as specified above. Any
# other outcome (wrong exit code, OR the token leaking into a logged argv)
# fails closed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/coolify-env"
COOLIFY_ENV_SH="$REPO_ROOT/scripts/coolify-env.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$COOLIFY_ENV_SH" ]] || { echo "FATAL: $COOLIFY_ENV_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

# The fake `ssh`: intercepts every sshx()/sshx_in() call coolify-env.sh
# makes. For the plain reachability probes it just succeeds. For `bash -s`
# (sshx_in) calls, it reads the captured remote script off stdin, rewrites
# the ONE hardcoded absolute path prefix (/root/.pfin -> our throwaway
# fakebox dir) so the script's own token-read and curl-config-path lines
# resolve inside $WORK instead of requiring real root, then executes the
# rewritten script locally with fake-curl shadowing the real curl.
FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
# The fixture file is named `fake-curl` (a readable name in
# tests/fixtures/ci/coolify-env/) but PATH-shadowing requires the actual
# command name `curl` -- symlink it under that name in OUR throwaway bin
# dir, never renaming the fixture itself.
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"
# Four distinct call shapes coolify-env.sh's sshx()/sshx_in() produce,
# all of which this fake `ssh` must handle DIFFERENTLY, not dispatch to
# one blanket "read stdin as a script" path (an earlier draft of this
# fixture did that and silently no-op'd the seed-file write below,
# producing a false PASS for the wrong reason -- caught by an inversion
# strike against this fixture itself before landing):
#   1. `ssh ... root@host true`                          -- probe, exit 0
#   2. `ssh ... root@host 'test -s .../coolify.env'`      -- probe, exit 0
#   3. `ssh ... root@host "<command string>" [< stdin]`   -- sshx(): the
#      LAST argv element IS the command to run; stdin (if any) is DATA to
#      pipe through it (coolify-env.sh's own seed-file write), never a
#      script to execute on its own.
#   4. `ssh ... root@host bash -s <<HEREDOC`               -- sshx_in():
#      stdin IS the remote script.
#   4b. `ssh ... root@host "env VAR=val bash -s" <<HEREDOC` -- sshx()
#      carrying an `env NAME=val ... bash -s` command string (Sec, PR
#      #825 review, F4's env-argv fix): stdin is STILL the remote
#      script, but the env assignments must take effect first, exactly
#      as the REAL remote login shell would apply them. `bash -c
#      "$CMDLINE" <<< "$REWRITTEN"` re-parses the command string as real
#      shell syntax (so a %q-escaped value survives intact) rather than
#      this mock's own naive word-splitting on it.
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *" true" ]]; then
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
bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  local desc="$1" expect_exit="$2" mode="$3"; shift 3
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$mode" \
    bash "$COOLIFY_ENV_SH" "$@" < /dev/null > "$WORK/out.$$" 2>&1
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

  echo "OK: [$desc] exit $rc as expected, token absent from every logged curl argv."
  return 0
}

FAIL=0

# 1. `set` refuses a manifest-declared secret name -- no ssh/curl call at
#    all should happen (checked implicitly: this scenario's log stays
#    empty because the die() fires before sshx is ever invoked).
run_scenario "set refuses manifest secret name" 1 ok \
  set abc123def456ghi789jk01 SUPABASE_SERVICE_ROLE_KEY=x || FAIL=1

# 2. `set --apply` fails on a byte-exact read-back mismatch.
run_scenario "set --apply fails on read-back mismatch" 1 mismatch \
  set abc123def456ghi789jk01 PGRST_DB_SCHEMAS=public,graphql_public,pfin --apply || FAIL=1

# 3. `delete --apply` fails when the post-delete read-back still shows the
#    key present (blanked, not deleted).
run_scenario "delete --apply fails on blanked-not-deleted read-back" 1 blanked \
  delete abc123def456ghi789jk01 MIGRATOR_DB_USER --apply || FAIL=1

# 4. The manifest refusal is SEPARATE from the allowlist, and scenario 1
#    does NOT reach it (the allowlist die() fires first). Strike it on
#    its own: copy the real script, WIDEN SET_ALLOWLIST to admit a
#    manifest-declared name, and assert it is STILL refused. Without
#    this leg the belt-and-braces check has no watcher -- measured
#    (Sec, PR #825 review, F1): deleting the manifest block entirely
#    leaves scenarios 1-3 green.
WIDENED="$WORK/coolify-env.widened.sh"
sed 's/^SET_ALLOWLIST=(\(.*\))$/SET_ALLOWLIST=(\1 SUPABASE_SERVICE_ROLE_KEY)/' \
  "$COOLIFY_ENV_SH" > "$WIDENED"
grep -qE '^SET_ALLOWLIST=\(.*SUPABASE_SERVICE_ROLE_KEY' "$WIDENED" \
  || { echo "FATAL: SET_ALLOWLIST widening did not apply -- has the array line moved or been reformatted? (A bare grep for the NAME is vacuous here: coolify-env.sh carries SUPABASE_SERVICE_ROLE_KEY in its own secrets-manifest positive-control anchor, so anchor the check to the ARRAY LINE.)" >&2; exit 2; }
COOLIFY_ENV_SH_SAVED="$COOLIFY_ENV_SH"
COOLIFY_ENV_SH="$WIDENED"
run_scenario "manifest refusal holds even with a WIDENED SET_ALLOWLIST" 1 ok \
  set abc123def456ghi789jk01 SUPABASE_SERVICE_ROLE_KEY=x || FAIL=1
COOLIFY_ENV_SH="$COOLIFY_ENV_SH_SAVED"

# 5. BACKLOG.md §7.36 item 68 (W-2): the six new SET_ALLOWLIST additions
#    (PFIN_DB_HOST / PFIN_DB_PORT / PFIN_DB_NAME / PFIN_DB_USER / PLAID_ENV
#    / ADMISSION_PROBE_PUBLIC_URLS) must each (a) actually be present in
#    the committed SET_ALLOWLIST array and (b) NOT collide with a
#    secrets-manifest.yml-declared name -- the exact risk class this
#    script's own header warns about ("if a name that is genuinely secret
#    is ever proposed for SET_ALLOWLIST, that is the wrong fix"). Each
#    name is struck by running a real preflight `set` call (no --apply)
#    against it -- if either condition were false, the manifest-refusal
#    die() (scenario 1's own mechanism) would fire and this would exit 1
#    naming the offending name, not 0.
# F-5 (PR #846 review) added value-shape constraints on PFIN_DB_USER and
# ADMISSION_PROBE_PUBLIC_URLS specifically -- the placeholder 'x' value
# this loop used for every OTHER name no longer clears their own shape
# check, so each gets a value that actually satisfies it here. A case
# statement, not an associative array -- coolify-env.sh's own header
# (line ~236) documents why: the OPERATOR's own /bin/bash is stock macOS
# 3.2, no `declare -A`, and this fence follows the same discipline even
# though it is CI-only today.
valid_value_for() {
  case "$1" in
    PFIN_DB_USER) echo "pfin_etl" ;;
    ADMISSION_PROBE_PUBLIC_URLS) echo "https://example.com" ;;
    *) echo "x" ;;
  esac
}
for NEW_NAME in PFIN_DB_HOST PFIN_DB_PORT PFIN_DB_NAME PFIN_DB_USER PLAID_ENV ADMISSION_PROBE_PUBLIC_URLS; do
  run_scenario "new allowlist name '$NEW_NAME' resolves (present + non-manifest)" 0 ok \
    set abc123def456ghi789jk01 "${NEW_NAME}=$(valid_value_for "$NEW_NAME")" || FAIL=1
done

# 6. F-5 (PR #846 review) -- PFIN_DB_USER value-shape guard. Only the
#    three DB roles this repo mints are accepted; anything else refuses,
#    even though the NAME itself is allowlisted.
run_scenario "PFIN_DB_USER value-shape: refuses a non-role value" 1 ok \
  set abc123def456ghi789jk01 PFIN_DB_USER=postgres || FAIL=1

# 7. F-5 -- PFIN_DB_USER accepts each of the three minted roles (not just
#    the one scenario 5 happens to use).
for VALID_ROLE in pfin_etl pfin_provider_sync authenticator; do
  run_scenario "PFIN_DB_USER value-shape: accepts '$VALID_ROLE'" 0 ok \
    set abc123def456ghi789jk01 "PFIN_DB_USER=${VALID_ROLE}" || FAIL=1
done

# 8. F-5 -- ADMISSION_PROBE_PUBLIC_URLS value-shape guard. Userinfo,
#    query-strings, and non-https schemes must all refuse -- this is the
#    exact exfil/credential-embedding shape the guard exists to close off.
for BAD_URL in "http://example.com" "https://user:pass@example.com" "https://example.com/?x=1" "https://example.com,not-a-url"; do
  run_scenario "ADMISSION_PROBE_PUBLIC_URLS value-shape: refuses '$BAD_URL'" 1 ok \
    set abc123def456ghi789jk01 "ADMISSION_PROBE_PUBLIC_URLS=${BAD_URL}" || FAIL=1
done

# 9. F-5 -- ADMISSION_PROBE_PUBLIC_URLS accepts the documented
#    comma-separated multi-FQDN shape, not just a single URL.
run_scenario "ADMISSION_PROBE_PUBLIC_URLS value-shape: accepts multi-FQDN" 0 ok \
  set abc123def456ghi789jk01 "ADMISSION_PROBE_PUBLIC_URLS=https://a.example.com,https://b.example.com" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more coolify-env.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all coolify-env.sh strike-proofs passed."
exit 0
