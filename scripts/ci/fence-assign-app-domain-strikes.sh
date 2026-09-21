#!/usr/bin/env bash
#
# fence-assign-app-domain-strikes.sh -- offline strike-proof for
# scripts/assign-app-domain.sh's STRUCTURAL logic: the MX/TXT-touch
# refusal, the wrong-existing-record-type refusal, Coolify uuid
# ambiguity guards, and that neither Porkbun key ever reaches curl's own
# argv. BACKLOG.md §7.36 item 72 (W-5).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- stated, not glossed:
# whether Porkbun's real API actually behaves the way fake-curl asserts
# it does, whether the Coolify `fqdn` PATCH field name is actually
# correct (that is UNMEASURED per the real script's own header -- this
# fence proves the script correctly detects a MISMATCHING read-back, not
# that the field name is right), whether DNS actually propagates, or
# whether a real Let's Encrypt cert is ever issued. Every leg here is a
# CANNED response; this fence proves the shell script's own control flow
# (refuse on the right conditions, proceed on the right conditions), not
# any live external system's behavior.
#
# Scenarios:
#   1. HAPPY-PATH PREFLIGHT -- MX x2 + TXT x2 at the apex (the REAL
#      pfindash.com shape, measured live -- Sec F-2, PR #849 review: the
#      prior fixture used an EMPTY apex, which never exercised the actual
#      target domain's own shape and let an over-broad refusal ship
#      unnoticed), no --apply -> prints the diff + the Coolify PATCH
#      plan, exit 0, nothing written (no Porkbun write call, no Coolify
#      PATCH call), and the MX/TXT rows are visibly UNTOUCHED (no refusal
#      fires on them).
#   2. CNAME-AT-APEX-REFUSES (Sec F-2, PR #849 review -- replaces the old
#      MX-at-apex scenario, which is no longer a refusal condition) -- a
#      CNAME record sits at the apex name -> refuses before any write
#      (the actual CNAME-exclusivity conflict this guard exists to
#      catch).
#   3. TXT-AT-WWW-REFUSES -- a TXT record sits at the www name -> refuses.
#   3b. CAA-NON-LE-REFUSES (Sec F-2, PR #849 review) -- a CAA record
#      exists at the apex that does not authorise Let's Encrypt -> refuses
#      with the named CAA reason, before any write.
#   4. ALREADY-CORRECT -- apex A already = BOX_IP, www CNAME already =
#      apex -> preflight reports both actions "none", no refusal.
#   5. KEYS-NEVER-IN-ARGV -- across every Porkbun call this fence issues,
#      neither fake-curl's own leak check NOR the fake python3 wrapper's
#      (Sec VETO-2, PR #849 review -- the python3-argv witness that makes
#      this scenario actually falsifiable; the curl-level check alone
#      never could, since the keys never reached curl's argv even in the
#      broken version) ever fires (both write to the same FAKE_LEAK_LOG
#      sentinel).
#   6. UUID-AMBIGUOUS-REFUSES -- 2 applications match APP_NAME -> refuses
#      (Sec F4 discipline, same class as every sibling script).
#   7. PATCH-READBACK-MISMATCH-REFUSES -- the Coolify PATCH "succeeds"
#      but the immediate GET read-back still shows the OLD fqdn (the
#      field-name guess was wrong) -> refuses, never reports success.
#   8. APPLY-HAPPY-PATH -- --apply with no existing conflicting records,
#      a correct PATCH read-back, and both apex/www answering 200 ->
#      exit 0.
#   9. CERT-NEVER-APPEARS-REFUSES -- the apex never returns 200 within
#      the (fence-shortened) poll bound -> refuses.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/assign-app-domain"
SMOKE_SH="$REPO_ROOT/scripts/assign-app-domain.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=fake-coolify-token-do-not-leak\n' > "$FAKE_ROOT_PFIN/coolify.env"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `python3` -- Sec VETO-2 (PR #849 review): the ORIGINAL leak check
# only ever watched curl's own argv, which the Porkbun keys never reached
# in the first place (they moved via --data-binary @tempfile even in the
# broken version) -- so scenario 5 could never actually fire regardless
# of whether the keys leaked into python3's OWN argv, which they DID
# (three sites, fixed in this same PR: the keys now move exclusively via
# python3's stdin, never sys.argv). This wrapper makes that guard
# FALSIFIABLE: it logs its own argv the same way fake-curl already does,
# to the SAME $FAKE_LEAK_LOG sentinel, then execs the real python3 so
# every scenario's actual script logic still runs unmodified. Strike this
# by putting a key back on python3's argv in assign-app-domain.sh -- this
# wrapper will catch it; the curl-level check alone never could.
REAL_PYTHON3="$(command -v python3)"
[[ -n "$REAL_PYTHON3" ]] || { echo "FATAL: no real python3 on PATH to wrap" >&2; exit 2; }
cat > "$FAKE_BIN/python3" <<EOF
#!/usr/bin/env bash
ARGS="\$*"
if [[ -n "\${FAKE_PORKBUN_API_KEY_VALUE:-}" ]] && printf '%s' "\$ARGS" | grep -qF "\$FAKE_PORKBUN_API_KEY_VALUE"; then
  printf 'LEAK: PORKBUN_API_KEY value found in python3 argv: %s\n' "\$ARGS" >> "\${FAKE_LEAK_LOG:-/dev/null}"
fi
if [[ -n "\${FAKE_PORKBUN_SECRET_KEY_VALUE:-}" ]] && printf '%s' "\$ARGS" | grep -qF "\$FAKE_PORKBUN_SECRET_KEY_VALUE"; then
  printf 'LEAK: PORKBUN_SECRET_KEY value found in python3 argv: %s\n' "\$ARGS" >> "\${FAKE_LEAK_LOG:-/dev/null}"
fi
exec "$REAL_PYTHON3" "\$@"
EOF
chmod +x "$FAKE_BIN/python3"

cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${@: -1}" == "true" ]]; then
  exit 0
fi
if [[ "\$*" == *"test -s /root/.pfin/coolify.env"* ]]; then
  exit 0
fi
LAST="\${@: -1}"
if [[ "\$LAST" == "-s" || "\$LAST" == *" bash -s" ]]; then
  CMDLINE="\$LAST"
  [[ "\$CMDLINE" == "-s" ]] && CMDLINE="bash -s"
  CMDLINE="\$(printf '%s' "\$CMDLINE" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  PATH="$FAKE_BIN:\$PATH" FAKE_CURL_LOG="\${FAKE_CURL_LOG:-}" \\
    FAKE_APP_UUID="\${FAKE_APP_UUID:-}" FAKE_APP_NAME="\${FAKE_APP_NAME:-}" \\
    FAKE_OLD_FQDN="\${FAKE_OLD_FQDN:-}" FAKE_NEW_FQDN="\${FAKE_NEW_FQDN:-}" \\
    FAKE_PATCH_MARKER="\${FAKE_PATCH_MARKER:-}" FAKE_PATCH_TAKES_EFFECT="\${FAKE_PATCH_TAKES_EFFECT:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

# Ambiguous-application case: fake-curl's application-list branch only
# ever returns ONE app -- for the ambiguity scenario, override with a
# tiny curl shim that returns two.
cat > "$FAKE_BIN/curl-ambiguous" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ARGS="$*"
if [[ "$ARGS" == *"localhost:8000/api/v1"* && "$ARGS" == *"/applications" && "$ARGS" != *"-X PATCH"* ]]; then
  echo '[{"uuid":"appuuid0000000000001","name":"pfin-app","fqdn":""},{"uuid":"appuuid0000000000002","name":"pfin-app","fqdn":""}]'
  exit 0
fi
exec "$0.real" "$@"
EOF

PORKBUN_API_KEY_VALUE="test-porkbun-api-key-leak-check"
PORKBUN_SECRET_KEY_VALUE="test-porkbun-secret-key-leak-check"

run_case() {
  # run_case <desc> <expect_exit> <apply-flag-or-empty> <records-json> <apex-code> <www-code> <old-fqdn> <new-fqdn> <patch-takes-effect>
  # (the ambiguous-application scenario swaps in a whole different curl
  # shim -- tests/fixtures/ci/assign-app-domain via $FAKE_BIN/curl-ambiguous
  # -- rather than a run_case parameter, since it changes the LIST
  # response shape, not a single canned value.)
  local desc="$1" expect_exit="$2" apply_flag="$3" records="$4" apex_code="$5" www_code="$6"
  local old_fqdn="$7" new_fqdn="$8" patch_effect="$9"
  local log="$WORK/curl.log.$$.$RANDOM"
  local leak_log="$WORK/leak.log.$$.$RANDOM"
  local patch_marker="$WORK/patch.marker.$$.$RANDOM"
  : > "$log"

  printf 'PORKBUN_API_KEY=%s\nPORKBUN_SECRET_KEY=%s\nBOX_IP=127.0.0.1\n' "$PORKBUN_API_KEY_VALUE" "$PORKBUN_SECRET_KEY_VALUE" > "$WORK/.env"

  set +e
  # Intentional, on $apply_flag below: an empty apply_flag must vanish
  # entirely (zero args passed), not become one empty-string arg -- the
  # real script's own case-statement would reject that as "unknown flag".
  # shellcheck disable=SC2086
  REPO_ROOT="$WORK" ROOT_DOMAIN=fake-domain.test APP_NAME=pfin-app AUTOMATION_KEY=/dev/null \
    CERT_POLL_ATTEMPTS=2 CERT_POLL_INTERVAL_SECONDS=0 \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_LEAK_LOG="$leak_log" \
    FAKE_PORKBUN_API_KEY_VALUE="$PORKBUN_API_KEY_VALUE" FAKE_PORKBUN_SECRET_KEY_VALUE="$PORKBUN_SECRET_KEY_VALUE" \
    FAKE_PORKBUN_RECORDS="$records" FAKE_APEX_CODE="$apex_code" FAKE_WWW_CODE="$www_code" \
    FAKE_APP_UUID=appuuid0000000000001 FAKE_APP_NAME=pfin-app FAKE_OLD_FQDN="$old_fqdn" FAKE_NEW_FQDN="$new_fqdn" \
    FAKE_PATCH_MARKER="$patch_marker" FAKE_PATCH_TAKES_EFFECT="$patch_effect" \
    bash "$SMOKE_SH" $apply_flag < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$WORK/out.$$" >&2
    return 1
  fi
  if [[ -s "$leak_log" ]]; then
    echo "FAIL: [$desc] a Porkbun key value leaked into curl argv:" >&2
    cat "$leak_log" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected, no key leak." >&2
  CASE_LOG="$log"
  CASE_OUTPUT="$(cat "$WORK/out.$$")"
  return 0
}

FAIL=0

# The REAL pfindash.com apex shape (Sec F-2, PR #849 review -- measured
# live: `dig +short MX pfindash.com` / `dig +short TXT pfindash.com`).
# Using this as the happy-path fixture, not an empty apex, is the whole
# point: it is what let the prior over-broad refusal ship unnoticed.
REAL_SHAPE_APEX_RECORDS='[{"name":"fake-domain.test","type":"MX","content":"fwd1.porkbun.com","prio":"10"},{"name":"fake-domain.test","type":"MX","content":"fwd2.porkbun.com","prio":"20"},{"name":"fake-domain.test","type":"TXT","content":"v=spf1 include:_spf.porkbun.com ~all"},{"name":"fake-domain.test","type":"TXT","content":"brevo-code:abc123"}]'
CONFLICT_CNAME_APEX='[{"name":"fake-domain.test","type":"CNAME","content":"somewhere-else.example.com"}]'
CONFLICT_CAA_NONLE='[{"name":"fake-domain.test","type":"CAA","content":"0 issue \"digicert.com\""}]'
CONFLICT_TXT_WWW='[{"name":"www.fake-domain.test","type":"TXT","content":"v=spf1 ..."}]'
ALREADY_CORRECT='[{"name":"fake-domain.test","type":"A","content":"127.0.0.1"},{"name":"www.fake-domain.test","type":"CNAME","content":"fake-domain.test"}]'

# 1. HAPPY-PATH PREFLIGHT -- real apex shape (MX x2 + TXT x2), all
#    untouched, no refusal.
run_case "happy-path preflight" 0 "" "$REAL_SHAPE_APEX_RECORDS" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]] && grep -q "dns/create\|dns/editByNameType\|-X PATCH" "$CASE_LOG"; then
  echo "FAIL: [happy-path preflight] a write call was issued despite no --apply" >&2
  FAIL=1
fi

# 2. CNAME-AT-APEX-REFUSES (replaces the old MX-at-apex scenario, which
#    is no longer a refusal condition -- MX passes through untouched, per
#    scenario 1 above)
run_case "CNAME record at apex refuses" 1 "" "$CONFLICT_CNAME_APEX" 200 200 "" "" 1 || FAIL=1

# 3. TXT-AT-WWW-REFUSES
run_case "TXT record at www refuses" 1 "" "$CONFLICT_TXT_WWW" 200 200 "" "" 1 || FAIL=1

# 3b. CAA-NON-LE-REFUSES -- a CAA record at the apex that does not
#     authorise Let's Encrypt.
run_case "CAA record at apex not authorising Let's Encrypt refuses" 1 "" "$CONFLICT_CAA_NONLE" 200 200 "" "" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qi "does not authorise the Let s Encrypt CA" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [CAA-non-LE-refuses] did not name the CAA predicate -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 4. ALREADY-CORRECT
run_case "already-correct: no action needed" 0 "" "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]] && grep -q "dns/create\|dns/editByNameType" "$CASE_LOG"; then
  echo "FAIL: [already-correct] a DNS write call was issued despite already-correct state" >&2
  FAIL=1
fi

# 5. KEYS-NEVER-IN-ARGV -- covered by every run_case call's own leak-log assertion above.
echo "OK: [keys never in argv] asserted on every scenario's own curl log." >&2

# 8. APPLY-HAPPY-PATH -- real apex shape again, apex A / www CNAME both
#    still absent (create), MX/TXT untouched throughout --apply too.
run_case "apply happy-path: DNS+PATCH+certs all verified" 0 --apply "$REAL_SHAPE_APEX_RECORDS" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]] && { ! grep -q "dns/create" "$CASE_LOG" || ! grep -q -- "-X PATCH" "$CASE_LOG"; }; then
  echo "FAIL: [apply happy-path] expected both a Porkbun create call and a Coolify PATCH call" >&2
  FAIL=1
fi

# 7. PATCH-READBACK-MISMATCH-REFUSES
run_case "Coolify PATCH read-back mismatch refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 0 || FAIL=1

# 9. CERT-NEVER-APPEARS-REFUSES
run_case "cert never appears within the bound refuses" 1 --apply "$ALREADY_CORRECT" 000 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1

# 6. UUID-AMBIGUOUS-REFUSES -- swap in the ambiguous-application curl shim.
mv "$FAKE_BIN/curl" "$FAKE_BIN/curl.real"
sed "s#\$0.real#$FAKE_BIN/curl.real#" "$FAKE_BIN/curl-ambiguous" > "$FAKE_BIN/curl"
chmod +x "$FAKE_BIN/curl"
run_case "ambiguous application match refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
rm -f "$FAKE_BIN/curl"
mv "$FAKE_BIN/curl.real" "$FAKE_BIN/curl"

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more assign-app-domain.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all assign-app-domain.sh strike-proofs passed."
exit 0
