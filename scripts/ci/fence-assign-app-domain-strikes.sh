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
#   25-25p. POST-REDEPLOY CONTAINER-ENV READ + SSLIP PROBE, REQUIRED GATE
#      (team-lead run-21 fix follow-up + Sec's redeploy-addenda review,
#      2026-09-22) -- the real script now ALWAYS triggers a Coolify
#      redeploy (POST /deploy?uuid=, same shape deploy-app.sh already
#      uses) after a successful docker_compose_domains PATCH, waits on a
#      NAMED, fail-closed timeout (DEPLOY_POLL_ATTEMPTS x
#      DEPLOY_POLL_INTERVAL_SECONDS -- refuses, never falls through, on
#      expiry or an explicit status=failed), then reads the NEW
#      container's env -- this is now a REQUIRED gate (die()/exit 1),
#      never the old informational skip: a fresh container must exist,
#      differ from the id captured BEFORE the redeploy (never identified
#      by "most recent"/start time -- a plain id inequality, since
#      AMBIGUOUS below already refuses whenever either side has more
#      than one candidate), and be INDEPENDENTLY confirmed
#      State.Running=true via `docker inspect` (never trusting `docker ps
#      --filter status=running` alone -- Coolify injects env at
#      container START, not creation). Prints VALUES (not just names)
#      for exactly COOLIFY_FQDN/COOLIFY_URL/SERVICE_FQDN_* (Sec's narrow,
#      named relaxation of this repo's names-only env-store discipline --
#      see this script's own header). Finally re-takes the off-box sslip
#      reachability probe AFTER the redeploy, with a nonexistent-host
#      control, reporting a divergence as a FINDING, never a failure.
#      FAKE_APP_CID models the pre-redeploy container (default empty);
#      FAKE_APP_CID_POST models the post-redeploy one (run_case's own
#      default: a valid-hex id distinct from the empty pre-deploy
#      default, so every EXISTING apply-success scenario above, none of
#      which know about this gate, passes it cleanly without
#      per-scenario changes):
#        25.  no running container post-redeploy refuses.
#        25b. 2+ containers matching the name filter post-redeploy
#             refuses (never the old `head -1` first-of-several guess).
#        25c. 'docker ps' itself failing post-redeploy refuses.
#        25d. 'docker exec ... env' itself failing refuses.
#        25e. 'docker ps' returning a non-container-id-shaped value
#             refuses, before ever reaching docker exec.
#        25f. the post-redeploy id is IDENTICAL to the pre-redeploy id
#             (redeploy "finished" but never actually replaced the
#             container) refuses, naming BOTH ids, never prints MEASURED.
#        25g. 'docker inspect' reports State.Running=false for an
#             otherwise-resolved container refuses -- the ps filter
#             alone is not trusted.
#        25h. VALUES (not just names) are printed for exactly the three
#             relaxed families; anything else in the container's env (a
#             deliberate secret-bearing distractor var) never appears in
#             the captured output at all.
#        25i. none of the three watched families are injected --
#             reported as a CONTROL GAP to investigate, never silently
#             passed over.
#        25j. the deployment status poll never reaches "finished" within
#             its bound -- fails closed, never falls through to the env
#             read (Sec's explicit ask: this is a NAMED timeout, not an
#             unbounded wait).
#        25k. a positive control against the apply-happy-path scenario's
#             own curl.log -- the deploy POST and the deployments-poll
#             GET must actually have been issued, not just assumed from
#             the exit code.
#        25l. the sslip host answers DIFFERENTLY from the
#             nonexistent-host control -- printed as a FINDING, never a
#             failure or a refusal.
#        25m. inversion of 25l -- sslip host matches the control -- no
#             FINDING line, and an explicit MEASURED-clean line instead
#             (Sec F-1: the positive result must be as greppable as the
#             FINDING, never silent).
#        25n. SSLIP-PROBE-CONTROL-UNREACHABLE-NOT-MEASURED (Sec F-1,
#             PR #878 review, corrected after df89cf9f: curl writes
#             http_code=000 on a failed transfer, never nothing) -- the
#             nonexistent-host control returns 000 on both schemes --
#             must print NOT MEASURED, never a FINDING or a
#             MEASURED-clean line: an unperformed probe is not the same
#             as a clean one, and "000 equals 000" would otherwise be a
#             false all-clear.
#        25o. SSLIP-PROBE-MACHINE-FULLY-UNREACHABLE-NOT-MEASURED -- the
#             real-world defect Sec's re-review caught: BOTH the sslip
#             host and the control return 000 (this machine cannot
#             reach the box at all) -- the equal-comparison branch that
#             was the actual false all-clear, not just the control side.
#        25p. SSLIP-PROBE-CONTROL-EMPTY-OUTPUT-NOT-MEASURED --
#             build-independence coverage: a curl build producing
#             genuinely empty stdout on total failure is ALSO NOT
#             MEASURED, not just the 000 shape.
#   29/30. WWW-AS-A (live dns fix, 2026-09-22 -- www.pfindash.com already
#      existed as an A record, not a CNAME, and this script only ever
#      looked for a CNAME) -- a mismatched www A edits in place to box_ip
#      (never a CNAME create alongside it, the exact conflict a live
#      Porkbun 400 measured); an already-correct www A issues no write.
#   31. WWW-AAAA-NOW-REFUSES -- AAAA at www used to pass through
#      unexamined (the OLD allowed-set was {A,AAAA,CNAME}); now refuses
#      by name, since this script writes neither AAAA nor IPv6 anywhere.
#   32. PORKBUN-WRITE-NON-2XX-SURFACES-MESSAGE (the second live defect,
#      same measurement pass) -- `curl -fsS` discarded the response body
#      on a non-2xx, so the operator only ever saw a bare curl transport
#      error, never Porkbun own `message` field explaining why -> the
#      status-preserving rewrite must name BOTH the HTTP status and
#      Porkbun own message text.
#   33/34. WILDCARD-A WARN -- a `*.{domain}` A record pointing somewhere
#      other than box_ip prints a READ-ONLY warning (never a refusal,
#      never a write -- an F/CTO cutover decision); already matching
#      prints nothing.
#   35-39. docker_compose_domains READ-BACK SHAPE (run-21 live defect,
#      2026-09-22, COOLIFY-FACT-15 -- the field reads back as a JSON
#      STRING whose content is a JSON OBJECT keyed by compose service
#      name, not a flat comma-separated list; the fixture now models
#      that measured shape by default, not the flat-list shape the
#      original fence wrongly assumed):
#        35. one of the two intended domains missing from the live set
#            refuses, naming it.
#        36. the read-back object has no "app" key at all refuses,
#            naming which service keys WERE present.
#        37. the read-back carries "app" PLUS an unexpected second
#            service key refuses, naming the extra key -- never guesses
#            which one is authoritative.
#        38. the read-back in the PATCH's own array shape (instead of
#            the measured object-string shape) still passes -- tolerance
#            for a future API change, not a measured fact.
#        39. COOLIFY-FACT-15's own exact measured bytes (extracted LIVE
#            from COOLIFY-API-MEASURED.md, zero retyped copies), fed
#            verbatim through the real parser -- proves the parser
#            handles the ACTUAL production bytes that broke run 21, not
#            just a synthetic approximation of their shape.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/assign-app-domain"
SMOKE_SH="$REPO_ROOT/scripts/assign-app-domain.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

# COOLIFY-FACT-15's own exact measured docker_compose_domains bytes,
# extracted LIVE from scripts/COOLIFY-API-MEASURED.md (zero retyped
# copies -- team-lead: pin it in the fence by grep -F against FACT-15).
# Used to feed the real script's parser the ACTUAL production bytes
# Coolify returned, not a synthetic approximation of them.
COOLIFY_API_MEASURED_MD="$REPO_ROOT/scripts/COOLIFY-API-MEASURED.md"
[[ -f "$COOLIFY_API_MEASURED_MD" ]] || { echo "FATAL: $COOLIFY_API_MEASURED_MD not found -- cannot extract FACT-15's measured bytes" >&2; exit 2; }
FACT15_RAW="$(awk '
  /^## COOLIFY-FACT-15/ { infact = 1 }
  infact && /^[[:space:]]*```$/ { fence++; next }
  infact && fence == 1 { print }
  infact && fence >= 2 { exit }
' "$COOLIFY_API_MEASURED_MD" | sed -E 's/^[[:space:]]*//')"
[[ -n "$FACT15_RAW" ]] || { echo "FATAL: extracted an empty string for FACT-15's measured bytes -- COOLIFY-API-MEASURED.md's FACT-15 fenced block shape changed; fix the extractor above, do not silently proceed with an empty pin" >&2; exit 2; }

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
    FAKE_COMPOSE_DOMAINS_READBACK_SHAPE="\${FAKE_COMPOSE_DOMAINS_READBACK_SHAPE:-}" \\
    FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE="\${FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE:-}" \\
    FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE="\${FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE:-}" \\
    FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE="\${FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE:-}" \\
    FAKE_DEPLOY_TRIGGERED_MARKER="\${FAKE_DEPLOY_TRIGGERED_MARKER:-}" FAKE_DEPLOY_STATUS="\${FAKE_DEPLOY_STATUS:-}" \\
    bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
PATH="$FAKE_BIN:\$PATH" FAKE_APP_CID="\${FAKE_APP_CID:-}" FAKE_APP_ENV_LINES="\${FAKE_APP_ENV_LINES:-}" \\
  FAKE_DOCKER_PS_FAILS="\${FAKE_DOCKER_PS_FAILS:-}" FAKE_DOCKER_EXEC_FAILS="\${FAKE_DOCKER_EXEC_FAILS:-}" \\
  FAKE_DEPLOY_TRIGGERED_MARKER="\${FAKE_DEPLOY_TRIGGERED_MARKER:-}" FAKE_APP_CID_POST="\${FAKE_APP_CID_POST:-}" \\
  FAKE_DOCKER_INSPECT_RUNNING="\${FAKE_DOCKER_INSPECT_RUNNING:-}" FAKE_DOCKER_INSPECT_FAILS="\${FAKE_DOCKER_INSPECT_FAILS:-}" \\
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
  # FAKE_DEPLOY_TRIGGERED_MARKER (run-21 fix follow-up) -- fake-curl
  # touches this file when the fake POST /deploy?uuid= fires; once it
  # exists, this fixture reports FAKE_APP_CID_POST (the post-redeploy
  # container id) instead of FAKE_APP_CID (pre-redeploy) -- same
  # marker-file idiom the PATCH-marker checks above already use, so a
  # scenario can distinguish "docker ps called before the redeploy" from
  # "called after" across separate, stateless fake-ssh invocations.
  if [[ -n "${FAKE_DEPLOY_TRIGGERED_MARKER:-}" && -f "$FAKE_DEPLOY_TRIGGERED_MARKER" ]]; then
    printf '%s' "${FAKE_APP_CID_POST:-${FAKE_APP_CID:-}}"
  else
    printf '%s' "${FAKE_APP_CID:-}"
  fi
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
# 'docker inspect --format {{.State.Running}} <cid>' -- Sec ask (redeploy
# addenda requirement 4): a second, independent confirmation the
# resolved post-redeploy container is genuinely running, not just
# resolved via 'docker ps --filter status=running'. Defaults to "true"
# so every EXISTING scenario (none of which know about this check)
# passes it unchanged.
if [[ "$*" == *"inspect --format"* && "$*" == *"State.Running"* ]]; then
  if [[ "${FAKE_DOCKER_INSPECT_FAILS:-0}" == "1" ]]; then
    echo "Error: No such object (simulated)" >&2
    exit 1
  fi
  printf '%s' "${FAKE_DOCKER_INSPECT_RUNNING:-true}"
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
  local deploy_triggered_marker="$WORK/deploy-triggered.marker.$$.$RANDOM"
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
    DEPLOY_POLL_ATTEMPTS=2 DEPLOY_POLL_INTERVAL_SECONDS=0 \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_LEAK_LOG="$leak_log" \
    FAKE_PORKBUN_API_KEY_VALUE="$PORKBUN_API_KEY_VALUE" FAKE_PORKBUN_SECRET_KEY_VALUE="$PORKBUN_SECRET_KEY_VALUE" \
    FAKE_PORKBUN_RECORDS="$records" FAKE_APEX_CODE="$apex_code" FAKE_WWW_CODE="$www_code" \
    FAKE_PORKBUN_WRITE_HTTP_STATUS="${FAKE_PORKBUN_WRITE_HTTP_STATUS:-}" FAKE_PORKBUN_WRITE_ERROR_MESSAGE="${FAKE_PORKBUN_WRITE_ERROR_MESSAGE:-}" \
    FAKE_APP_UUID=appuuid0000000000001 FAKE_APP_NAME=pfin-app FAKE_OLD_FQDN="$old_fqdn" FAKE_NEW_FQDN="$new_fqdn" \
    FAKE_APP_BASE_DIR="${FAKE_APP_BASE_DIR:-/api}" FAKE_APP_BUILD_PACK="${FAKE_APP_BUILD_PACK:-dockercompose}" \
    FAKE_APP_PORTS="${FAKE_APP_PORTS:-3000}" FAKE_NEW_PORTS="${FAKE_NEW_PORTS:-3000}" \
    FAKE_PORTS_PATCH_MARKER="$ports_patch_marker" FAKE_PORTS_PATCH_TAKES_EFFECT="${FAKE_PORTS_PATCH_TAKES_EFFECT:-1}" \
    FAKE_OLD_COMPOSE_DOMAINS="${FAKE_OLD_COMPOSE_DOMAINS:-$old_fqdn}" FAKE_NEW_COMPOSE_DOMAINS="${FAKE_NEW_COMPOSE_DOMAINS:-$new_fqdn}" \
    FAKE_COMPOSE_DOMAINS_PATCH_MARKER="$compose_domains_patch_marker" \
    FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT="${FAKE_COMPOSE_DOMAINS_PATCH_TAKES_EFFECT:-$patch_effect}" \
    FAKE_COMPOSE_DOMAINS_PATCH_STATUS="${FAKE_COMPOSE_DOMAINS_PATCH_STATUS:-200}" \
    FAKE_COMPOSE_DOMAINS_READBACK_SHAPE="${FAKE_COMPOSE_DOMAINS_READBACK_SHAPE:-}" \
    FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE="${FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE:-}" \
    FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE="${FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE:-}" \
    FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE="${FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE:-}" \
    FAKE_APP_CID="${FAKE_APP_CID:-}" FAKE_APP_ENV_LINES="${FAKE_APP_ENV_LINES:-}" \
    FAKE_DOCKER_PS_FAILS="${FAKE_DOCKER_PS_FAILS:-0}" FAKE_DOCKER_EXEC_FAILS="${FAKE_DOCKER_EXEC_FAILS:-0}" \
    FAKE_DOCKER_INSPECT_RUNNING="${FAKE_DOCKER_INSPECT_RUNNING:-true}" FAKE_DOCKER_INSPECT_FAILS="${FAKE_DOCKER_INSPECT_FAILS:-0}" \
    FAKE_APP_CID_POST="${FAKE_APP_CID_POST-deadbeef0001}" \
    FAKE_DEPLOY_TRIGGERED_MARKER="$deploy_triggered_marker" FAKE_DEPLOY_STATUS="${FAKE_DEPLOY_STATUS:-finished}" \
    FAKE_APEX_SSL_VERIFY="${FAKE_APEX_SSL_VERIFY:-0}" FAKE_WWW_SSL_VERIFY="${FAKE_WWW_SSL_VERIFY:-0}" \
    FAKE_SSLIP_HTTP_CODE="${FAKE_SSLIP_HTTP_CODE:-}" FAKE_SSLIP_HTTPS_CODE="${FAKE_SSLIP_HTTPS_CODE:-}" \
    FAKE_CONTROL_HTTP_CODE="${FAKE_CONTROL_HTTP_CODE:-}" FAKE_CONTROL_HTTPS_CODE="${FAKE_CONTROL_HTTPS_CODE:-}" \
    FAKE_CONTROL_UNREACHABLE="${FAKE_CONTROL_UNREACHABLE:-0}" FAKE_CONTROL_EMPTY="${FAKE_CONTROL_EMPTY:-0}" \
    FAKE_SSLIP_UNREACHABLE="${FAKE_SSLIP_UNREACHABLE:-0}" \
    bash "$SMOKE_SH" $apply_flag < /dev/null > "$WORK/out.$$" 2>&1
  local rc=$?
  set -e
  CASE_PORTS_PATCH_MARKER="$ports_patch_marker"
  CASE_COMPOSE_DOMAINS_PATCH_MARKER="$compose_domains_patch_marker"
  CASE_DEPLOY_TRIGGERED_MARKER="$deploy_triggered_marker"

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

# 25. POST-REDEPLOY-NO-RUNNING-CONTAINER-REFUSES -- the redeploy reports
#     finished but no container is running afterward -- a HARD refusal
#     now, not the old informational skip.
FAKE_APP_CID_POST=""
run_case "post-redeploy env read: no running container refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID_POST
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "found NO running container" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: no container] did not name the refusal -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25b. POST-REDEPLOY-AMBIGUOUS-CONTAINERS-REFUSES -- 2 containers match
#     the name filter after the redeploy -- never silently pick the
#     first (the old `head -1` pattern), same discipline as every
#     sibling script.
FAKE_APP_CID_POST=$'abc123def456
abc123def789'
run_case "post-redeploy env read: ambiguous containers refuse" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID_POST
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "AMBIGUOUS" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: ambiguous] did not name the ambiguity -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25c. POST-REDEPLOY-DOCKER-PS-FAILS-REFUSES -- 'docker ps' itself fails
#     (transport/daemon error) on the post-redeploy check.
FAKE_DOCKER_PS_FAILS=1
run_case "post-redeploy env read: docker ps fails refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_DOCKER_PS_FAILS
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "'docker ps' itself failed" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: docker ps fails] did not name the read failure -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25d. POST-REDEPLOY-DOCKER-EXEC-FAILS-REFUSES -- a container IS
#     resolved and confirmed running, but 'docker exec ... env' itself
#     fails.
FAKE_DOCKER_EXEC_FAILS=1
run_case "post-redeploy env read: docker exec fails refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_DOCKER_EXEC_FAILS
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "env' rc=" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: docker exec fails] did not name the read failure -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25e. POST-REDEPLOY-NON-HEX-CID-REFUSES -- 'docker ps' resolves to
#     exactly one value but it is NOT container-id-shaped -- refuses
#     before ever interpolating it into a remote docker exec command.
FAKE_APP_CID_POST='not-a-valid-container-id!'
run_case "post-redeploy env read: non-hex CID refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID_POST
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "non-container-id-shaped" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: non-hex CID] did not name the shape refusal -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25f. POST-REDEPLOY-IDENTICAL-TO-PRE-DEPLOY-CID-REFUSES (Sec redeploy
#     addenda, requirement 1: set-difference on ids, naming BOTH on a
#     match, never "most recent"/start time) -- the redeploy reports
#     finished but the "new" container id equals the pre-redeploy one.
FAKE_APP_CID=abc123def456
FAKE_APP_CID_POST=abc123def456
run_case "post-redeploy env read: identical to pre-deploy CID refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_CID FAKE_APP_CID_POST
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "IDENTICAL to the pre-redeploy container id (abc123def456)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: same CID] did not name BOTH ids in the refusal -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qE "injects (NONE of|:)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: same CID] printed an env-injection measurement despite refusing -- a read of the OLD container is a READ-OF-THE-WRONG-THING, not a measurement." >&2
    FAIL=1
  fi
fi

# 25g. POST-REDEPLOY-DOCKER-INSPECT-NOT-RUNNING-REFUSES (Sec redeploy
#     addenda, requirement 4) -- 'docker ps --filter status=running'
#     resolved a single container, but the independent 'docker inspect'
#     confirmation reports State.Running=false -- refuses, never trusts
#     the ps filter alone.
FAKE_DOCKER_INSPECT_RUNNING="false"
run_case "post-redeploy env read: docker inspect not-running refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_DOCKER_INSPECT_RUNNING
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "State.Running=false, not true" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: not running] did not name the State.Running refusal -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qE "injects (NONE of|:)" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: not running] printed an env-injection measurement despite refusing -- docker exec must never have run." >&2
    FAIL=1
  fi
fi

# 25h. POST-REDEPLOY-VALUES-FOR-THE-THREE-FAMILIES-ONLY (Sec relaxation)
#     -- COOLIFY_FQDN/COOLIFY_URL/SERVICE_FQDN_* print their VALUES, not
#     just their names; a deliberate secret-bearing distractor var
#     outside those three families must never appear in the captured
#     output at all.
FAKE_APP_ENV_LINES=$'COOLIFY_FQDN=http://abc.1.2.3.4.sslip.io
COOLIFY_URL=http://abc.1.2.3.4.sslip.io
SERVICE_FQDN_APP=https://fake-domain.test
DATABASE_URL=postgres://fake-user:fake-super-secret-value@127.0.0.1/fake'
run_case "post-redeploy env read: values printed for the three families only" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_ENV_LINES
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "COOLIFY_FQDN=http://abc.1.2.3.4.sslip.io" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: values] did not print COOLIFY_FQDN's VALUE -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "SERVICE_FQDN_APP=https://fake-domain.test" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: values] did not print SERVICE_FQDN_APP's VALUE -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "fake-super-secret-value" <<<"$CASE_OUTPUT" || grep -qF "DATABASE_URL" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [post-redeploy: values] a non-relaxed env var leaked into the captured output -- names-only discipline still applies to everything outside the three named families." >&2
    FAIL=1
  fi
fi

# 25i. POST-REDEPLOY-NO-WATCHED-NAMES-CONTROL-GAP -- a resolved,
#     confirmed-running, differing container injects none of the three
#     watched families -- reported as a CONTROL GAP to investigate,
#     never silently passed over as success.
FAKE_APP_ENV_LINES=""
run_case "post-redeploy env read: no watched names found, reported as a control gap" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APP_ENV_LINES
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "CONTROL GAP" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [post-redeploy: no watched names] did not name the control gap -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 25j. DEPLOY-WAIT-TIMEOUT-FAILS-CLOSED (Sec redeploy addenda,
#     requirement 3) -- the deployment never reaches status=finished
#     within DEPLOY_POLL_ATTEMPTS x DEPLOY_POLL_INTERVAL_SECONDS
#     (run_case hardcodes 2x0s so this redens fast) -- must refuse,
#     never fall through to the container-env read below it.
FAKE_DEPLOY_STATUS="in_progress"
run_case "deploy wait: never reaches finished within the bound refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_DEPLOY_STATUS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "did not reach status=finished within" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [deploy wait timeout] did not name the bounded-timeout refusal -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "Post-redeploy container-env read" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [deploy wait timeout] fell through to the post-redeploy env-read step despite the deploy never finishing." >&2
    FAIL=1
  fi
fi

# 25k. REDEPLOY-ACTUALLY-FIRES -- positive control: the deploy POST and
#     the deployments-poll GET must actually have been issued, not just
#     assumed from the exit code.
run_case "redeploy actually fires: POST /deploy + deployments-poll GET both issued" 0 --apply "$REAL_SHAPE_APEX_RECORDS" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]]; then
  if ! grep -qF "COOLIFY-DEPLOY-TRIGGERED" "$CASE_LOG"; then
    echo "FAIL: [redeploy positive control] no POST /deploy?uuid= call was issued -- captured log: $(cat "$CASE_LOG")" >&2
    FAIL=1
  fi
  if ! grep -q "/deployments/" "$CASE_LOG"; then
    echo "FAIL: [redeploy positive control] no deployments-poll GET was issued -- captured log: $(cat "$CASE_LOG")" >&2
    FAIL=1
  fi
fi

# --- sslip reachability probe, post-redeploy, with a nonexistent-host
# control (Sec redeploy addenda, requirement 2) ------------------------
SSLIP_APP_HOST_FQDN="http://sslipprobe0000000001.127.0.0.1.sslip.io"

# 25l. SSLIP-PROBE-FINDING-ON-DIVERGENCE -- the app's own sslip host
#     answers DIFFERENTLY from the nonexistent-host control -- an
#     unintended second route -- printed as a FINDING, never a failure.
FAKE_SSLIP_HTTP_CODE=200
FAKE_SSLIP_HTTPS_CODE=200
run_case "sslip probe: divergence from the nonexistent-host control prints a FINDING" 0 --apply "$ALREADY_CORRECT" 200 200 "$SSLIP_APP_HOST_FQDN" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_SSLIP_HTTP_CODE FAKE_SSLIP_HTTPS_CODE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "FINDING:" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe divergence] did not print a FINDING despite the sslip host answering differently from the control -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "sslipprobe0000000001" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe divergence] did not name the sslip host it probed -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 25m. SSLIP-PROBE-NO-FINDING-WHEN-MATCHING -- inversion of 25l: the
#     sslip host and the control agree (both default to 404) -- no
#     FINDING line, and an explicit MEASURED-clean line instead (Sec
#     F-1: the positive result must be as greppable as the FINDING).
run_case "sslip probe: matching the control prints no FINDING" 0 --apply "$ALREADY_CORRECT" 200 200 "$SSLIP_APP_HOST_FQDN" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if grep -qF "FINDING:" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe no divergence] printed a FINDING despite the sslip host matching the control -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "sslip reachability probe MEASURED: the sslip host answered identically" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe no divergence] did not print an explicit MEASURED-clean line -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 25n. SSLIP-PROBE-CONTROL-UNREACHABLE-NOT-MEASURED (Sec F-1, PR #878
#     review -- CORRECTED after df89cf9f: Sec's own re-measurement
#     showed curl writes http_code=000 on a failed transfer, never
#     nothing, so this is the PRIMARY shape, not the empty one the
#     first fix wrongly assumed) -- the control returns 000 on BOTH
#     schemes -- must print NOT MEASURED, never a FINDING or a
#     MEASURED-clean line -- "000 equals 000" would otherwise be a
#     false all-clear, not a clean result.
FAKE_CONTROL_UNREACHABLE=1
run_case "sslip probe: unreachable control (000) prints NOT MEASURED, never a false all-clear" 0 --apply "$ALREADY_CORRECT" 200 200 "$SSLIP_APP_HOST_FQDN" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_CONTROL_UNREACHABLE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "sslip reachability probe NOT MEASURED" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe control unreachable] did not print the NOT MEASURED refusal -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "FINDING:" <<<"$CASE_OUTPUT" || grep -qF "sslip reachability probe MEASURED:" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe control unreachable] printed a FINDING or a MEASURED-clean line despite the control never having responded -- an unperformed probe is not a clean one." >&2
    FAIL=1
  fi
fi

# 25o. SSLIP-PROBE-MACHINE-FULLY-UNREACHABLE-NOT-MEASURED -- the actual
#     real-world defect Sec named: THIS machine cannot reach the box at
#     all, so BOTH the sslip host AND the control return 000 (the old,
#     wrongly-specified guard only ever struck the control side, never
#     reaching the equal-comparison branch that was the real defect --
#     the subject and control comparing EQUAL at 000/000). Must still
#     print NOT MEASURED, never a false MEASURED-clean.
FAKE_CONTROL_UNREACHABLE=1
FAKE_SSLIP_UNREACHABLE=1
run_case "sslip probe: machine fully unreachable (both sides 000) prints NOT MEASURED" 0 --apply "$ALREADY_CORRECT" 200 200 "$SSLIP_APP_HOST_FQDN" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_CONTROL_UNREACHABLE FAKE_SSLIP_UNREACHABLE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "sslip reachability probe NOT MEASURED" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe machine unreachable] did not print the NOT MEASURED refusal despite both sides returning 000 -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if grep -qF "sslip reachability probe MEASURED:" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [sslip probe machine unreachable] printed a false MEASURED-clean line for 000==000 -- this is the exact defect Sec's re-review caught." >&2
    FAIL=1
  fi
fi

# 25p. SSLIP-PROBE-CONTROL-EMPTY-OUTPUT-NOT-MEASURED -- build-
#     independence coverage (Sec's own explicit ask): a curl build that
#     genuinely produces no stdout at all on total failure (rather than
#     000) must ALSO be treated as NOT MEASURED, not just the 000 shape.
FAKE_CONTROL_EMPTY=1
run_case "sslip probe: control with genuinely empty output also prints NOT MEASURED" 0 --apply "$ALREADY_CORRECT" 200 200 "$SSLIP_APP_HOST_FQDN" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_CONTROL_EMPTY
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "sslip reachability probe NOT MEASURED" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [sslip probe control empty output] did not print the NOT MEASURED refusal for a genuinely empty control response -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# --- www-as-A / Porkbun status-preserving / wildcard-WARN scenarios
# (2026-09-22 live dns fix -- see this script own header + this file own
# header for the measurement that found this) -------------------------

# 29. WWW-AS-A-EDITS-IN-PLACE -- apex already correct (isolates the www
#     leg), www exists as an A record NOT equal to box_ip -- must issue
#     an editByNameType/A/www call, never a CNAME create (the exact
#     conflict a live Porkbun 400 measured), and must report the
#     CNAME-not-created explanation.
WWW_AS_A_MISMATCH='[{"name":"fake-domain.test","type":"A","content":"127.0.0.1"},{"name":"www.fake-domain.test","type":"A","content":"9.9.9.9"}]'
run_case "www exists as A record, mismatched -- edits in place to box_ip" 0 --apply "$WWW_AS_A_MISMATCH" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]]; then
  if ! grep -qF "dns/editByNameType/fake-domain.test/A/www" "$CASE_LOG"; then
    echo "FAIL: [www-as-A edit] expected an editByNameType/A/www call -- captured log: $(cat "$CASE_LOG")" >&2
    FAIL=1
  fi
  if grep -qF "dns/create/fake-domain.test" "$CASE_LOG"; then
    echo "FAIL: [www-as-A edit] a CNAME create call was issued despite an A record already existing at www" >&2
    FAIL=1
  fi
fi
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "CNAME not created because an A record exists" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [www-as-A edit] did not report the CNAME-not-created explanation -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 30. WWW-AS-A-ALREADY-CORRECT-NO-WRITE -- the A record already equals
#     box_ip -- must issue NO write of any kind for www (real idempotency,
#     the same discipline scenario 4/11 already apply to the CNAME case).
WWW_AS_A_CORRECT='[{"name":"fake-domain.test","type":"A","content":"127.0.0.1"},{"name":"www.fake-domain.test","type":"A","content":"127.0.0.1"}]'
run_case "www exists as A record, already = box_ip -- no write" 0 --apply "$WWW_AS_A_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_LOG:-}" ]] && grep -qE "dns/editByNameType/fake-domain\.test/A/www|dns/create/fake-domain\.test" "$CASE_LOG"; then
  echo "FAIL: [www-as-A already correct] a DNS write call was issued despite www A already matching box_ip" >&2
  FAIL=1
fi
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "www A already -> box -- nothing to change" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [www-as-A already correct] did not print the expected already-correct wording -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 31. WWW-AAAA-NOW-REFUSES -- AAAA at www used to pass through
#     unexamined (the OLD allowed-set was {A,AAAA,CNAME}); now refuses,
#     by name, same as any other unexpected type (this script writes
#     neither AAAA nor IPv6 anywhere).
WWW_AAAA_REFUSES='[{"name":"www.fake-domain.test","type":"AAAA","content":"::1"}]'
run_case "AAAA at www now refuses (no longer a passed-through type)" 1 "" "$WWW_AAAA_REFUSES" 200 200 "" "" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "AAAA" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [www AAAA refuses] did not name AAAA in the refusal -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 32. PORKBUN-WRITE-NON-2XX-SURFACES-MESSAGE -- the live defect measured
#     2026-09-22: `curl -fsS` discarded the response BODY on a non-2xx,
#     so the operator only ever saw a bare curl transport error, never
#     Porkbun own `message` field explaining WHY. Empty records ->
#     apex create is the first Porkbun write attempted -> forced 400 ->
#     must name BOTH the HTTP status AND Porkbun own message text.
FAKE_PORKBUN_WRITE_HTTP_STATUS=400
FAKE_PORKBUN_WRITE_ERROR_MESSAGE="fake: record with that name and type already exists"
run_case "Porkbun write non-2xx surfaces the real message, not a bare transport error" 1 --apply '[]' 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_PORKBUN_WRITE_HTTP_STATUS FAKE_PORKBUN_WRITE_ERROR_MESSAGE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "HTTP 400" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [porkbun non-2xx message] did not name HTTP 400 -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "record with that name and type already exists" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [porkbun non-2xx message] did not surface Porkbun own message field -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 32b. PORKBUN-KEY-ECHOED-IN-ERROR-IS-REDACTED (Sec F-1, PR #877 review)
#     -- models Porkbun echoing the SUBMITTED request back on a
#     validation error (an undocumented-but-real shape some APIs use,
#     exactly the case the raw-text fallbacks exist for) -- the fake key
#     value must NEVER reach the captured output, but the refusal must
#     still fire and still be useful (a <redacted> marker in its place).
FAKE_PORKBUN_WRITE_HTTP_STATUS=400
# No embedded double-quote characters here, deliberately -- fake-curl
# splices this straight into a JSON string value via plain printf (no
# JSON-escaping of its own); a literal `"` here would break the JSON,
# which would then be caught by json.loads()'s OWN except branch
# instead of the status>=300 branch this scenario means to exercise --
# self-caught mid-session: my first draft embedded a fake JSON snippet
# with literal quotes, which silently exercised the WRONG code path
# (still scrubbed there too, so the scenario still passed, but not for
# the reason its own name claimed) and made a subsequent inversion test
# fail to redden. Plain key=value text both avoids the JSON-breaking
# characters and is itself a realistic echo shape.
FAKE_PORKBUN_WRITE_ERROR_MESSAGE="fake: rejected request; submitted apikey=$PORKBUN_API_KEY_VALUE secretapikey=$PORKBUN_SECRET_KEY_VALUE"
run_case "Porkbun key echoed in an error message is redacted, never printed" 1 --apply '[]' 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_PORKBUN_WRITE_HTTP_STATUS FAKE_PORKBUN_WRITE_ERROR_MESSAGE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if grep -qF "$PORKBUN_API_KEY_VALUE" <<<"$CASE_OUTPUT" || grep -qF "$PORKBUN_SECRET_KEY_VALUE" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [porkbun key echoed] a Porkbun key value leaked into the captured output via an echoed error message -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "<redacted>" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [porkbun key echoed] scrub() did not leave a <redacted> marker -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 33. WILDCARD-A-MISMATCH-WARNS -- a wildcard A record pointing
#     somewhere other than box_ip -- READ-ONLY warn (never a refusal,
#     never a write); preflight mode so a stray write call would be
#     unambiguous.
WILDCARD_MISMATCH='[{"name":"fake-domain.test","type":"A","content":"127.0.0.1"},{"name":"www.fake-domain.test","type":"CNAME","content":"fake-domain.test"},{"name":"*.fake-domain.test","type":"A","content":"8.8.8.8"}]'
run_case "wildcard A pointing elsewhere warns, never refuses or writes" 0 "" "$WILDCARD_MISMATCH" 200 200 "" "" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "wildcard A" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [wildcard warn] did not print the wildcard warning -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "8.8.8.8" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [wildcard warn] did not name the mismatched IP -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi
if [[ -n "${CASE_LOG:-}" ]] && grep -qE "dns/create|dns/editByNameType" "$CASE_LOG"; then
  echo "FAIL: [wildcard warn] a DNS write call was issued despite preflight mode and an already-correct apex/www" >&2
  FAIL=1
fi

# 34. WILDCARD-A-MATCH-NO-WARN -- inversion of 33: wildcard already
#     matches box_ip -- no warning printed.
WILDCARD_MATCH='[{"name":"fake-domain.test","type":"A","content":"127.0.0.1"},{"name":"www.fake-domain.test","type":"CNAME","content":"fake-domain.test"},{"name":"*.fake-domain.test","type":"A","content":"127.0.0.1"}]'
run_case "wildcard A matching box_ip prints no warning" 0 "" "$WILDCARD_MATCH" 200 200 "" "" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && grep -qF "wildcard A" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [wildcard no-warn] printed a wildcard warning despite it already matching box_ip -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# --- docker_compose_domains read-back shape scenarios (run-21 live
# defect, 2026-09-22 -- COOLIFY-FACT-15) -------------------------------
# The fixture now models the MEASURED object-string shape by default
# (see build_compose_domains_field() in fake-curl); every scenario
# above that reaches this PATCH already exercises that default shape
# implicitly (21/21b/21c/apply-happy-path). These scenarios isolate the
# NEW predicates specifically.

# 35. DOMAIN-MISSING-ONE-REFUSES -- the live set carries only ONE of the
#     two intended domains (the apex, not www) -- must refuse, naming
#     the missing one, never treat a partial match as close enough.
FAKE_NEW_COMPOSE_DOMAINS="https://fake-domain.test"
run_case "docker_compose_domains read-back missing one intended domain refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_NEW_COMPOSE_DOMAINS
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "does not exactly equal the intended set" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain missing one] did not name the exact-set mismatch -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "www.fake-domain.test" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain missing one] did not name the missing domain -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 36. DOMAIN-SERVICE-ABSENT-REFUSES -- the read-back object is keyed
#     under a DIFFERENT service name, never "app" -- must refuse by
#     name (team-lead item 1: refuse if the app key is absent).
FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE="otherservice"
run_case "docker_compose_domains read-back missing the app service key refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_COMPOSE_DOMAINS_SERVICE_NAME_OVERRIDE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "no 'app' service key" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain service absent] did not name the absent service key -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "otherservice" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain service absent] did not name which services WERE present -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 37. DOMAIN-SERVICE-EXTRA-REFUSES -- the read-back carries "app" PLUS
#     an unexpected second service key -- must refuse, naming it, never
#     guess which one is authoritative (team-lead item 1: refuse if a
#     second service key appears).
FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE="etl"
run_case "docker_compose_domains read-back with an unexpected extra service key refuses" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_COMPOSE_DOMAINS_EXTRA_SERVICE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "unexpected extra service key" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain service extra] did not name the unexpected-extra predicate -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "etl" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [domain service extra] did not name the extra service key -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 38. DOMAIN-ARRAY-FORM-ALSO-PASSES -- the read-back uses the PATCH's
#     OWN array shape instead of the measured object-string shape
#     (team-lead: "the API might change") -- must still succeed, proving
#     the tolerance, not just the measured-shape path.
FAKE_COMPOSE_DOMAINS_READBACK_SHAPE="array"
run_case "docker_compose_domains read-back in array form also passes" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_COMPOSE_DOMAINS_READBACK_SHAPE

# 39. DOMAIN-FACT15-EXACT-BYTES-PARSED -- FACT-15's own exact measured
#     bytes (extracted live above, zero retyped copies), fed VERBATIM
#     through the real parser via FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE.
#     ROOT_DOMAIN here is fake-domain.test (this fence own fixed test
#     domain), not pfindash.com, so this CANNOT match the intended set
#     -- the point is proving the PARSE succeeds against the real
#     measured production bytes (reaching DOMAIN_SET_MISMATCH, never
#     DOMAIN_READBACK_UNPARSEABLE/DOMAIN_SERVICE_ABSENT) and that the
#     reported "extra" domains are the CORRECTLY PARSED pfindash.com
#     set, not the raw JSON blob treated as one nonsense domain (the
#     original run-21 defect, reproduced here against the literal bytes
#     that broke it live).
FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE="$FACT15_RAW"
run_case "FACT-15's exact measured bytes parse correctly (mismatch on domain identity, not on parse failure)" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_COMPOSE_DOMAINS_RAW_OVERRIDE
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if ! grep -qF "does not exactly equal the intended set" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [FACT-15 exact bytes] did not reach the exact-set mismatch path -- parse likely failed structurally instead. Captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
  if ! grep -qF "https://pfindash.com,https://www.pfindash.com" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [FACT-15 exact bytes] the reported extra-domains set was not the correctly-parsed pfindash.com set from FACT-15's own bytes -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# --- cert-poll / www-serves correctness (run-22 live cutover fix,
# team-lead; predicate CORRECTED per Sec review -- this is the script's
# ONLY TLS assertion) -----------------------------------------------
# domain_serves_result()/poll_domain_serves() replace the old bare
# `== "200"` check, which could never pass once the app started
# redirecting an unauthenticated '/' to '/login'. Sec's ruling: a bare
# "2xx/3xx" accept is looser than it needs to be (a redirect chain
# could point off-host; a single-request 3xx accept only verifies the
# FIRST hop's cert). Corrected shape: `-L --max-redirs 5` follows the
# chain to its real final state; require BOTH a final 2xx AND
# ssl_verify_result==0 -- ssl_verify_result reads 0 on a TRANSPORT
# FAILURE too (no verification attempted), so it is only meaningful
# paired with a real 2xx, confirmed via a REAL positive control against
# expired.badssl.com (ssl_verify_result=10, refused) and a genuine DNS
# failure (code=000, ssl_verify_result=0 -- caught only because the
# code check is required too) before this fixture was written.
# FAKE_APEX_SSL_VERIFY/FAKE_WWW_SSL_VERIFY default to "0" (verified),
# so every EXISTING apply-success scenario above (a plain
# FAKE_APEX_CODE=200) is unaffected.
#   40. CERT-POLL-VERIFIED-2XX-SUCCEEDS -- the explicit positive pair:
#       a final 2xx AND ssl_verify_result==0 -- succeeds.
#   41. CERT-POLL-SSL-VERIFY-NONZERO-WITH-2XX-REFUSES -- a 200 whose
#       TLS verification did NOT succeed -- a bare status code is not
#       "cert issued and trusted"; the bound exhausts and refuses.
#   42. CERT-POLL-TRANSPORT-FAILURE-000-REFUSES-DESPITE-VERIFY-ZERO --
#       Sec's explicitly-named case: a transport failure (code=000)
#       with ssl_verify_result defaulting to 0 (matching curl's real
#       behavior on a connection failure) must NOT be treated as
#       served -- ssl_verify_result==0 alone is never proof of a valid
#       cert; the bound exhausts and refuses.
#   43. WWW-SERVES-VERIFIED-2XX-SUCCEEDS -- symmetry check: the SAME
#       domain_serves_result()/poll_domain_serves() logic governs the
#       www leg, not a separate bare-200 check.

# 40. CERT-POLL-VERIFIED-2XX-SUCCEEDS
run_case "cert poll: a final 2xx over a verified cert succeeds" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "https://fake-domain.test/ answers over a verified TLS cert after following redirects (final http 200)" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [cert poll verified 2xx] did not print the expected success line -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 41. CERT-POLL-SSL-VERIFY-NONZERO-WITH-2XX-REFUSES -- apex_code/
#     www_code are run_case's OWN positional args 5/6; FAKE_APEX_
#     SSL_VERIFY is a NEW field (not part of the original 9-positional
#     shape), set as an outer var.
FAKE_APEX_SSL_VERIFY=5
run_case "cert poll: a 200 with ssl_verify_result != 0 never counts as served" 1 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
unset FAKE_APEX_SSL_VERIFY
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "ssl_verify_result=5" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [cert poll ssl_verify nonzero] did not name the unverified TLS state -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

# 42. CERT-POLL-TRANSPORT-FAILURE-000-REFUSES-DESPITE-VERIFY-ZERO (Sec's
#     explicit ask) -- FAKE_APEX_SSL_VERIFY left at its default "0"
#     (matching curl's real on-transport-failure behavior) with
#     apex_code=000 -- must still refuse, proving ssl_verify_result==0
#     alone is never sufficient.
run_case "cert poll: transport failure (000) refuses despite ssl_verify_result=0" 1 --apply "$ALREADY_CORRECT" 000 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]]; then
  if grep -qF "answers over a verified TLS cert" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [cert poll transport failure] printed a success line despite a transport failure -- ssl_verify_result=0 on a connection failure is not proof of a valid cert." >&2
    FAIL=1
  fi
  if ! grep -qF "http 000, ssl_verify_result=0" <<<"$CASE_OUTPUT"; then
    echo "FAIL: [cert poll transport failure] did not print the (code, ssl_verify_result) pair while polling -- captured output: $CASE_OUTPUT" >&2
    FAIL=1
  fi
fi

# 43. WWW-SERVES-VERIFIED-2XX-SUCCEEDS -- symmetry: the SAME logic
#     governs the www leg (apex left at its plain-200 default).
run_case "www serves: a final 2xx over a verified cert succeeds" 0 --apply "$ALREADY_CORRECT" 200 200 "" "https://fake-domain.test,https://www.fake-domain.test" 1 || FAIL=1
if [[ -n "${CASE_OUTPUT:-}" ]] && ! grep -qF "https://www.fake-domain.test/ answers over a verified TLS cert after following redirects (final http 200)" <<<"$CASE_OUTPUT"; then
  echo "FAIL: [www serves verified 2xx] did not print the expected success line -- captured output: $CASE_OUTPUT" >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more assign-app-domain.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all assign-app-domain.sh strike-proofs passed."
exit 0
