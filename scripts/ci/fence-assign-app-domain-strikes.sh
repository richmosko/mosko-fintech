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
# it does; whether `docker_compose_domains`'s ELEMENT SHAPE (schema-
# documented, COOLIFY-FACT-06, never independently confirmed by a live
# element-carrying PATCH before PR #866) actually takes effect on the
# real box; whether DNS actually propagates; or whether a real Let's
# Encrypt cert is ever issued. Every leg here is a CANNED response; this
# fence proves the shell script's own control flow (refuse on the right
# conditions, proceed on the right conditions), not any live external
# system's behavior. See scripts/COOLIFY-API-MEASURED.md for what IS
# live-measured vs schema-documented vs still unmeasured.
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
#   7. PATCH-READBACK-MISMATCH-REFUSES -- the docker_compose_domains
#      PATCH "succeeds" (200) but the immediate GET read-back does not
#      contain the target domain -> refuses, never reports success.
#   8. APPLY-HAPPY-PATH -- --apply with no existing conflicting records,
#      a correct PATCH read-back, and both apex/www answering 200 ->
#      exit 0.
#   9. CERT-NEVER-APPEARS-REFUSES -- the apex never returns 200 within
#      the (fence-shortened) poll bound -> refuses.
#   21b/21c. DOCKER-COMPOSE-DOMAINS-EXACT-SET (Sec F-4, PR #866 review)
#      -- the read-back containing an EXTRA domain beyond the intended
#      two, or a SUPERSTRING near-miss ("notfake-domain.test" contains
#      "fake-domain.test") -> both refuse; a plain CONTAINS($ROOT_DOMAIN)
#      check would have passed both silently.
#   25/26/27/28. POST-ASSIGNMENT-ENV-READ FAIL-CLOSED (Sec F-3, PR #866
#      review) -- 'docker ps' itself failing, 2+ containers matching the
#      name filter (never the old `head -1` first-of-several guess),
#      'docker exec ... env' itself failing, and 'docker ps' returning a
#      non-container-id-shaped value, must each be reported as a READ
#      FAILURE / ambiguity / shape refusal, never collapsed into the same
#      wording as a genuinely empty result -- the prior
#      `2>/dev/null || true` shape printed a false-positive "MEASURED ...
#      CONTROL GAP" fact for a read that never happened. This section
#      stays informational (exit code unaffected in all four cases); only
#      the WORDING is asserted.
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
    FAKE_APP_BASE_DIR="\${FAKE_APP_BASE_DIR:-}" FAKE_APP_BUILD_PACK="\${FAKE_APP_BUILD_PACK:-}" \\
    FAKE_APP_PORTS="\${FAKE_APP_PORTS:-}" FAKE_NEW_PORTS="\${FAKE_NEW_PORTS:-}" \\
    FAKE_PORTS_PATCH_MARKER="\${FAKE_PORTS_PATCH_MARKER:-}" FAKE_PORTS_PATCH_TAKES_EFFECT="\${FAKE_PORTS_PATCH_TAKES_EFFECT:-}" \\
    FAKE_OLD_COMPOSE_DOMAINS="\${FAKE_OLD_COMPOSE_DOMAINS:-}" FAKE_NEW_COMPOSE_DOMAINS="\${FAKE_NEW_COMPOSE_DOMAINS:-}" \\
    FAKE_COMPOSE_DOMAINS_PATCH_MARKER="\${FAKE_COMPOSE_DOMAINS_PATCH_MARKER:-}" FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT="\${FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT:-}" \\
    FAKE_COMPOSE_DOMAINS_PATCH_STATUS="\${FAKE_COMPOSE_DOMAINS_PATCH_STATUS:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_APP_CID="\${FAKE_APP_CID:-}" FAKE_APP_ENV_LINES="\${FAKE_APP_ENV_LINES:-}" \\
  FAKE_DOCKER_PS_FAILS="\${FAKE_DOCKER_PS_FAILS:-}" FAKE_DOCKER_EXEC_FAILS="\${FAKE_DOCKER_EXEC_FAILS:-}" \\
  bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

# Fake `docker` -- post-assignment container-env read (team-lead ask,
# PR #866 review), informational only in the real script. `$FAKE_APP_CID`
# controls whether a container is reported running for the app (empty =
# none, the common not-yet-redeployed case; multiple newline-separated
# ids = ambiguous); `$FAKE_APP_ENV_LINES` (newline-separated `NAME=value`
# pairs) is what `docker exec ... env` reports -- the real script's own
# `grep -oE` + `cut -d= -f1` narrow this to names only, so this fixture
# does not need to pre-filter. `$FAKE_DOCKER_PS_FAILS=1`/
# `$FAKE_DOCKER_EXEC_FAILS=1` (Sec F-3, PR #866 review) model the ssh/
# docker call itself failing -- distinct from "ran fine, found nothing" --
# so the real script's read-failure-vs-empty-result distinction is
# actually falsifiable.
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"ps --filter"* && "$*" == *"status=running"* ]]; then
  if [[ "${FAKE_DOCKER_PS_FAILS:-0}" == "1" ]]; then
    echo "Cannot connect to the Docker daemon (simulated)" >&2
    exit 1
  fi
  printf '%s' "${FAKE_APP_CID:-}"
  exit 0
fi
if [[ "$*" == *"exec"* && "$*" == *" env"* ]]; then
  if [[ "${FAKE_DOCKER_EXEC_FAILS:-0}" == "1" ]]; then
    echo "Error: No such container (simulated)" >&2
    exit 1
  fi
  printf '%s\n' "${FAKE_APP_ENV_LINES:-}"
  exit 0
fi
echo "FAKE DOCKER: unrecognised invocation: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

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

# seed_default_app_compose -- writes $WORK/api/docker-compose.yaml with
# the REAL production expose:3000 shape (matching api/docker-compose.yaml
# in this repo) so every scenario's TARGET GUARD + expose-port read
# resolve cleanly against REPO_ROOT="$WORK" (run_case's own override) by
# default. Called once per run_case (idempotent overwrite) rather than
# once globally, so a ports_exposes/TARGET-GUARD scenario that swaps in
# ITS OWN synthetic compose (via FAKE_APP_BASE_DIR pointing at a
# different scratch subdirectory this function also seeds) never leaves
# a stale file for the NEXT scenario to accidentally read.
seed_default_app_compose() {
  mkdir -p "$WORK/api"
  if [[ -n "${CASE_APP_COMPOSE_CONTENT:-}" ]]; then
    printf '%s' "$CASE_APP_COMPOSE_CONTENT" > "$WORK/api/docker-compose.yaml"
  else
    printf 'services:\n  app:\n    expose:\n      - "3000"\n' > "$WORK/api/docker-compose.yaml"
  fi
}

run_case() {
  # run_case <desc> <expect_exit> <apply-flag-or-empty> <records-json> <apex-code> <www-code> <old-fqdn> <new-fqdn> <patch-takes-effect>
  # (the ambiguous-application scenario swaps in a whole different curl
  # shim -- tests/fixtures/ci/assign-app-domain via $FAKE_BIN/curl-ambiguous
  # -- rather than a run_case parameter, since it changes the LIST
  # response shape, not a single canned value.)
  #
  # REPO_ROOT="$WORK" below means the real script's TARGET GUARD reads
  # "$WORK/${base_directory}/docker-compose.yaml" -- NOT this repo's own
  # tree. seed_default_app_compose (called once, before the first
  # run_case) writes $WORK/api/docker-compose.yaml with the REAL
  # expose:3000 shape, so every EXISTING scenario below (none of which
  # know about the ports_exposes preflight) resolves it cleanly and sees
  # ports_exposes already matching (CASE_ENV's own FAKE_APP_PORTS default
  # is 3000, below) -- no surprise PATCH call, no assertion breakage.
  # Ports_exposes-specific scenarios further down override FAKE_APP_PORTS
  # and/or FAKE_APP_BASE_DIR via CASE_ENV explicitly.
  local desc="$1" expect_exit="$2" apply_flag="$3" records="$4" apex_code="$5" www_code="$6"
  local old_fqdn="$7" new_fqdn="$8" patch_effect="$9"
  seed_default_app_compose
  local log="$WORK/curl.log.$$.$RANDOM"
  local leak_log="$WORK/leak.log.$$.$RANDOM"
  local ports_patch_marker="$WORK/ports-patch.marker.$$.$RANDOM"
  local compose_domains_patch_marker="$WORK/compose-domains-patch.marker.$$.$RANDOM"
  : > "$log"

  printf 'PORKBUN_API_KEY=%s\nPORKBUN_SECRET_KEY=%s\nBOX_IP=127.0.0.1\n' "$PORKBUN_API_KEY_VALUE" "$PORKBUN_SECRET_KEY_VALUE" > "$WORK/.env"

  set +e
  # Intentional, on $apply_flag below: an empty apply_flag must vanish
  # entirely (zero args passed), not become one empty-string arg -- the
  # real script's own case-statement would reject that as "unknown flag".
  #
  # $old_fqdn/$new_fqdn double as the docker_compose_domains defaults
  # (PR #866 review, mechanism switched from `fqdn` to
  # `docker_compose_domains` -- see assign-app-domain.sh's own header):
  # every EXISTING scenario already passes exactly the domain-string
  # shape docker_compose_domains needs, so FAKE_OLD_COMPOSE_DOMAINS/
  # FAKE_NEW_COMPOSE_DOMAINS default to them unchanged -- no scenario
  # below needed to change its call shape for the mechanism switch.
  # FAKE_OLD_FQDN/FAKE_NEW_FQDN still get set too (the app-level `fqdn`
  # read is now purely INFORMATIONAL in the real script, never a gate).
  # shellcheck disable=SC2086
  REPO_ROOT="$WORK" ROOT_DOMAIN=fake-domain.test APP_NAME=pfin-app AUTOMATION_KEY=/dev/null \
    CERT_POLL_ATTEMPTS=2 CERT_POLL_INTERVAL_SECONDS=0 \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_LEAK_LOG="$leak_log" \
    FAKE_PORKBUN_API_KEY_VALUE="$PORKBUN_API_KEY_VALUE" FAKE_PORKBUN_SECRET_KEY_VALUE="$PORKBUN_SECRET_KEY_VALUE" \
    FAKE_PORKBUN_RECORDS="$records" FAKE_APEX_CODE="$apex_code" FAKE_WWW_CODE="$www_code" \
    FAKE_APP_UUID=appuuid0000000000001 FAKE_APP_NAME=pfin-app FAKE_OLD_FQDN="$old_fqdn" FAKE_NEW_FQDN="$new_fqdn" \
    FAKE_APP_BASE_DIR="${FAKE_APP_BASE_DIR:-/api}" FAKE_APP_BUILD_PACK="${FAKE_APP_BUILD_PACK:-dockercompose}" \
    FAKE_APP_PORTS="${FAKE_APP_PORTS:-3000}" FAKE_NEW_PORTS="${FAKE_NEW_PORTS:-3000}" \
    FAKE_PORTS_PATCH_MARKER="$ports_patch_marker" FAKE_PORTS_PATCH_TAKES_EFFECT="${FAKE_PORTS_PATCH_TAKES_EFFECT:-1}" \
    FAKE_OLD_COMPOSE_DOMAINS="${FAKE_OLD_COMPOSE_DOMAINS:-$old_fqdn}" FAKE_NEW_COMPOSE_DOMAINS="${FAKE_NEW_COMPOSE_DOMAINS:-$new_fqdn}" \
    FAKE_COMPOSE_DOMAINS_PATCH_MARKER="$compose_domains_patch_marker" \
    FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT="${FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT:-$patch_effect}" \
    FAKE_COMPOSE_DOMAINS_PATCH_STATUS="${FAKE_COMPOSE_DOMAINS_PATCH_STATUS:-200}" \
    FAKE_APP_CID="${FAKE_APP_CID:-}" FAKE_APP_ENV_LINES="${FAKE_APP_ENV_LINES:-}" \
    FAKE_DOCKER_PS_FAILS="${FAKE_DOCKER_PS_FAILS:-0}" FAKE_DOCKER_EXEC_FAILS="${FAKE_DOCKER_EXEC_FAILS:-0}" \
    bash "$SMOKE_SH" $apply_flag < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e
  CASE_PORTS_PATCH_MARKER="$ports_patch_marker"
  CASE_COMPOSE_DOMAINS_PATCH_MARKER="$compose_domains_patch_marker"

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

# --- ports_exposes preflight + TARGET GUARD (Sec ask, joint review --
# fix/pdf-render-chromium-pin-and-resume-clear) --------------------------
# All scenarios below reuse ALREADY_CORRECT for DNS (no DNS-refusal noise)
# so each isolates ONE ports_exposes/TARGET-GUARD predicate. Overrides are
# plain FAKE_* shell variables, unset immediately after each run_case --
# NOT the CASE_ENV array idiom used elsewhere: macOS's bash 3.2 (measured
# here) recognises an env-assignment prefix (`VAR=val cmd`) only when the
# VAR=val token is LITERAL at parse time; a word produced by expanding
# "${arr[@]}" is never lexically "VAR=val" even when the array element
# looks like one at runtime, so it silently becomes the COMMAND WORD
# instead of an assignment (`FAKE_APP_PORTS=80: command not found`,
# caught live by actually running this fence, not by reading it).
# run_case's own env-prefix already reads each of these outer vars via
# "${FAKE_APP_PORTS:-3000}"-style fallbacks, so a plain `FAKE_APP_PORTS=80`
# set before the call (and `unset` after) is sufficient and portable.
# CASE_APP_COMPOSE_CONTENT is unaffected -- it is read directly by
# seed_default_app_compose() inside this fence process, never passed
# through the run_case env-prefix list.

# 11. PORTS-MISMATCH-SHOWN-IN-PREFLIGHT-NO-PATCH -- Coolify reports 80,
#     the compose says 3000; preflight (no --apply) must show the diff and
#     issue NO PATCH of any kind.
FAKE_APP_PORTS=80
run_case "ports_exposes mismatch shown in preflight, no PATCH issued" 0 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
unset FAKE_APP_PORTS
if [[ -n "${CASE_LOG:-}" ]] && grep -q -- "-X PATCH" "$CASE_LOG"; then
  echo "FAIL: [ports mismatch preflight] a PATCH call was issued despite no --apply" >&2
  FAIL=1
fi
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "80 -> 3000" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [ports mismatch preflight] did not show the 80 -> 3000 diff -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 12. PORTS-ALREADY-CORRECT-APPLY-NO-PATCH -- apply mode, ports already
#     3000 -- must issue no ports_exposes PATCH (the fqdn PATCH still
#     fires unconditionally; only the ports leg is under test here).
run_case "ports_exposes already correct in apply mode issues no ports PATCH" 0 --apply "$ALREADY_CORRECT" 200 200 "https://fake-domain.test,https://www.fake-domain.test" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -f "${CASE_PORTS_PATCH_MARKER:-/nonexistent}" ]]; then
  echo "FAIL: [ports already correct apply] a ports_exposes PATCH was issued despite no mismatch" >&2
  FAIL=1
fi

# 13. PORTS-MISMATCH-APPLY-PATCHES-BEFORE-FQDN -- proves ORDER: the
#     ports_exposes PATCH must land before the domain (docker_compose_domains) PATCH, since
#     Coolify's router needs the right in-container port wired before a
#     domain routes traffic at it.
FAKE_APP_PORTS=80 FAKE_NEW_PORTS=3000 FAKE_PORTS_PATCH_TAKES_EFFECT=1
run_case "ports_exposes mismatch in apply mode PATCHes before the docker_compose_domains PATCH" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_PORTS FAKE_NEW_PORTS FAKE_PORTS_PATCH_TAKES_EFFECT
if [[ ! -f "${CASE_PORTS_PATCH_MARKER:-/nonexistent}" ]]; then
  echo "FAIL: [ports mismatch apply ordering] no ports_exposes PATCH was issued" >&2
  FAIL=1
elif [[ -n "${CASE_LOG:-}" ]]; then
  PORTS_LN="$(grep -n '^COOLIFY-PATCH-PORTS$' "$CASE_LOG" | head -1 | cut -d: -f1 || true)"
  DOMAINS_LN="$(grep -n '^COOLIFY-PATCH-COMPOSE-DOMAINS$' "$CASE_LOG" | head -1 | cut -d: -f1 || true)"
  if [[ -z "$PORTS_LN" || -z "$DOMAINS_LN" || "$PORTS_LN" -ge "$DOMAINS_LN" ]]; then
    echo "FAIL: [ports mismatch apply ordering] expected COOLIFY-PATCH-PORTS (line $PORTS_LN) before COOLIFY-PATCH-COMPOSE-DOMAINS (line $DOMAINS_LN)" >&2
    FAIL=1
  fi
fi

# 14. PORTS-PATCH-READBACK-MISMATCH-REFUSES -- the PATCH's own read-back
#     shows the write didn't take -- must refuse (exit 1), matching the
#     existing fqdn read-back-mismatch predicate's shape.
FAKE_APP_PORTS=80 FAKE_NEW_PORTS=3000 FAKE_PORTS_PATCH_TAKES_EFFECT=0
run_case "ports_exposes PATCH read-back mismatch refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_PORTS FAKE_NEW_PORTS FAKE_PORTS_PATCH_TAKES_EFFECT

# 15. TARGET-GUARD-WRONG-BASE-DIR-REFUSES
FAKE_APP_BASE_DIR=/nonexistent-app-dir
run_case "TARGET GUARD refuses on wrong base_directory" 2 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
unset FAKE_APP_BASE_DIR
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "TARGET GUARD FAILED (CA-1)" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [TARGET GUARD wrong base_directory] did not name CA-1 -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 16. TARGET-GUARD-WRONG-BUILD-PACK-REFUSES
FAKE_APP_BUILD_PACK=dockerfile
run_case "TARGET GUARD refuses on wrong build_pack" 2 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
unset FAKE_APP_BUILD_PACK
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "build_pack='dockerfile'" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [TARGET GUARD wrong build_pack] did not name the live build_pack -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 17. TARGET-GUARD-ADMISSION-SHAPE-REFUSES -- identity matches (/api,
#     dockercompose) but the compose itself declares a serve-admission
#     command override, the WORKER shape -- isolates the NEGATIVE check
#     from the POSITIVE identity check above.
CASE_APP_COMPOSE_CONTENT=$'services:\n  app:\n    command: ["node", "dist/cli/serve-admission.js"]\n    expose:\n      - "3000"\n'
run_case "TARGET GUARD refuses on admission-guard shape present" 2 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
CASE_APP_COMPOSE_CONTENT=""
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "declares a serve-admission command override" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [TARGET GUARD admission shape] did not name the serve-admission predicate -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 18. EXPOSE-ZERO-ENTRIES-REFUSES
CASE_APP_COMPOSE_CONTENT=$'services:\n  app:\n    image: foo\n'
run_case "expose: zero entries refuses" 2 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
CASE_APP_COMPOSE_CONTENT=""
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "found 0" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [expose zero entries] did not report found 0 -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 19. EXPOSE-MULTIPLE-ENTRIES-REFUSES -- never "the first of several".
CASE_APP_COMPOSE_CONTENT=$'services:\n  app:\n    expose:\n      - "3000"\n      - "4000"\n'
run_case "expose: multiple entries refuses (never the first of several)" 2 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
CASE_APP_COMPOSE_CONTENT=""
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "found 2" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [expose multiple entries] did not report found 2 -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 20. EXPOSE-COMMENT-STRIPPED-POSITIVE-CONTROL -- comments interleaved
#     around AND inside the expose: block; the parser must still find the
#     real port (team-lead's explicit ask: prove it, don't assume it).
CASE_APP_COMPOSE_CONTENT=$'# top-of-file comment\nservices:\n  app:\n    expose:  # trailing comment on the key itself\n      # a comment line inside the block\n      - "3000"  # inline comment after the value\n'
run_case "expose: comment-stripped positive control finds the real port" 0 "" "$ALREADY_CORRECT" 200 200 "" "" 1 || FAIL=1
CASE_APP_COMPOSE_CONTENT=""
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -q "compose declares expose: 3000" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [expose comment-stripped] parser did not find port 3000 through the comments -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# --- docker_compose_domains mechanism-specific scenarios (Sec merge
# condition, PR #866 review) -------------------------------------------

# 21. DOCKER-COMPOSE-DOMAINS-PATCH-422-DISTINCT-MESSAGE -- a 422 on the
#     write itself must be named DISTINCTLY from a read-back mismatch
#     (team-lead's explicit ask) -- naming the field, the build_pack,
#     and pointing at scripts/COOLIFY-API-MEASURED.md, never worded as
#     "the field name guess was wrong" (that framing described the
#     RETIRED fqdn mechanism, not this one).
FAKE_COMPOSE_DOMAINS_PATCH_STATUS=422
run_case "docker_compose_domains PATCH 422 refuses with a distinct message" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_COMPOSE_DOMAINS_PATCH_STATUS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "HTTP 422" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [compose-domains 422] did not name HTTP 422 -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "build_pack=dockercompose" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [compose-domains 422] did not name the build_pack -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "read-back shows" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [compose-domains 422] used read-back-mismatch wording for a write-level 422 -- these are distinct failure classes, must not share a message." >&2
    FAIL=1
  fi
fi

# 21b. DOCKER-COMPOSE-DOMAINS-EXTRA-DOMAIN-REFUSES (Sec F-4, PR #866
#     review) -- the read-back contains BOTH intended domains AND an
#     extra one a containment check would have missed entirely.
FAKE_NEW_COMPOSE_DOMAINS="https://fake-domain.test,https://www.fake-domain.test,https://evil-extra.test"
run_case "docker_compose_domains read-back with an extra domain refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_NEW_COMPOSE_DOMAINS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "does not exactly equal the intended set" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [compose-domains extra domain] did not name the exact-set mismatch -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "evil-extra.test" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [compose-domains extra domain] did not name the extra domain -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 21c. DOCKER-COMPOSE-DOMAINS-SUPERSTRING-NEAR-MISS-REFUSES (Sec F-4,
#     PR #866 review) -- the read-back's first entry is a SUPERSTRING of
#     the intended root domain ("notfake-domain.test" contains
#     "fake-domain.test") -- a containment check would have passed this.
FAKE_NEW_COMPOSE_DOMAINS="https://notfake-domain.test,https://www.fake-domain.test"
run_case "docker_compose_domains read-back superstring near-miss refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_NEW_COMPOSE_DOMAINS
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "does not exactly equal the intended set" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [compose-domains superstring near-miss] did not name the exact-set mismatch -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 22. POST-ASSIGNMENT-ENV-READ-NOT-APPLICABLE -- no container running yet
#     for the app (the common not-yet-redeployed case, default
#     FAKE_APP_CID empty) -- informational, never blocks the exit code.
run_case "post-assignment env read: no running container, not applicable" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "container-env read not applicable" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-assignment env read: no container] did not report inapplicability -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 23. POST-ASSIGNMENT-ENV-READ-NAMES-FOUND -- a running container reports
#     SERVICE_FQDN_*/COOLIFY_FQDN names -- printed as a MEASURED line,
#     names only (never a value, matching this repo's names-only
#     discipline for env-store contents elsewhere).
FAKE_APP_CID=abc123def456
FAKE_APP_ENV_LINES=$'COOLIFY_FQDN=http://abc.sslip.io\nSERVICE_FQDN_APP=https://fake-domain.test'
run_case "post-assignment env read: names found, reported MEASURED" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID FAKE_APP_ENV_LINES
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "MEASURED" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-assignment env read: names found] did not print a MEASURED line -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "COOLIFY_FQDN" <<<"$CASE_OUTPUT" || ! grep -qF "SERVICE_FQDN_APP" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-assignment env read: names found] did not name both env vars found -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 24. POST-ASSIGNMENT-ENV-READ-NO-NAMES-CONTROL-GAP -- a running
#     container injects NONE of the watched names -- reported as a
#     CONTROL GAP to investigate, never silently passed over as success.
FAKE_APP_CID=abc123def789
FAKE_APP_ENV_LINES=""
run_case "post-assignment env read: no names found, reported as a control gap" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID FAKE_APP_ENV_LINES
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "CONTROL GAP" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-assignment env read: no names] did not name the control gap -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25. POST-ASSIGNMENT-ENV-READ-DOCKER-PS-FAILS (Sec F-3, PR #866 review)
#     -- 'docker ps' itself fails (transport/daemon error) -- must be
#     reported as a READ FAILURE, never collapsed into the same "no
#     container" / "MEASURED ... NONE" wording as a genuinely empty
#     result. exit code is UNCHANGED (still informational, never a hard
#     gate) -- only the WORDING is under test here.
FAKE_DOCKER_PS_FAILS=1
run_case "post-assignment env read: docker ps fails, reported as a read failure" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_DOCKER_PS_FAILS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "READ FAILURE" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [docker ps fails] did not name the read failure -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qE "injects (NONE of|:)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [docker ps fails] printed an env-injection measurement despite the read itself failing -- a failed read is not a measurement of anything." >&2
    FAIL=1
  fi
fi

# 26. POST-ASSIGNMENT-ENV-READ-AMBIGUOUS-CONTAINERS (Sec F-3, PR #866
#     review) -- 2 running containers match the name filter -- never
#     silently pick the first (the old `head -1` pattern); reported as
#     ambiguous, no docker exec issued.
FAKE_APP_CID=$'abc123def456\nabc123def789'
run_case "post-assignment env read: ambiguous containers, never guesses" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "ambiguous" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [ambiguous containers] did not name the ambiguity -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qE "injects (NONE of|:)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [ambiguous containers] printed an env-injection measurement despite never resolving which container is authoritative." >&2
    FAIL=1
  fi
fi

# 27. POST-ASSIGNMENT-ENV-READ-DOCKER-EXEC-FAILS (Sec F-3, PR #866
#     review) -- a container IS resolved, but 'docker exec ... env'
#     itself fails -- must be reported as a READ FAILURE, never as a
#     "MEASURED ... injects NONE" / CONTROL GAP (the false-positive shape
#     this finding named specifically).
FAKE_APP_CID=abc123def456
FAKE_DOCKER_EXEC_FAILS=1
run_case "post-assignment env read: docker exec fails, reported as a read failure" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID FAKE_DOCKER_EXEC_FAILS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "READ FAILURE" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [docker exec fails] did not name the read failure -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "that is a CONTROL GAP to report" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [docker exec fails] reported a CONTROL GAP for a read that never actually happened -- this is exactly the false positive Sec's F-3 named." >&2
    FAIL=1
  fi
fi

# 28. POST-ASSIGNMENT-ENV-READ-NON-HEX-CID-REFUSES (Sec F-3 follow-up,
#     PR #866 re-review) -- 'docker ps' returns a value that resolves
#     (rc=0, single match) but is NOT container-id-shaped -- refuses to
#     interpolate it into a remote docker exec command, never guessing
#     it's safe just because it came from docker ps today.
FAKE_APP_CID='not-a-valid-container-id!'
run_case "post-assignment env read: non-hex CID refuses before docker exec" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "non-container-id-shaped" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [non-hex CID] did not name the shape refusal -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qE "injects (NONE of|:)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [non-hex CID] printed an env-injection measurement despite refusing the shape check -- docker exec must never have run." >&2
    FAIL=1
  fi
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more assign-app-domain.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all assign-app-domain.sh strike-proofs passed."
exit 0
