#!/usr/bin/env bash
#
# fence-provision-strikes.sh -- offline strike-proof for scripts/provision.sh's
# OWN orchestration logic: step ordering, exit-code classification
# (0 VERIFIED / 3 SKIPPED / 4 MANUAL / else FAILED), --from/--only/--dry-run/
# --list, the .env operator-name preflight, and the ci-migrate keygen
# check-and-create. BACKLOG.md §7.36 item 76 (W-5).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- every per-step script
# (provision-vps.sh, deploy-app.sh, assign-app-domain.sh, ...) is replaced
# by tests/fixtures/ci/provision/fake-step.sh, a generic stand-in that
# returns a CANNED exit code and does nothing real. This proves
# provision.sh's OWN control flow is correct given whatever those scripts
# report; it is not, and cannot be, a substitute for actually running
# scripts/provision.sh against a real box.
#
# Scenarios:
#   1. HAPPY-PATH -- several consecutive scripted steps preflight and
#      apply 0, correctly stopping at the always-MANUAL cutover gate
#      (exit 1, not 0 -- see the scenario's own comment for why no
#      multi-step run can ever exit 0 against this registry).
#   2. SKIPPED-CONTINUES -- the smokes step's apply returns 3 -> recorded
#      SKIPPED, run continues to completion, exit 0.
#   3. MANUAL-STOPS -- discord's own fake reports 4 this run (BACKLOG item
#      74: scripts/coolify-discord-notify.sh is now a real scripted step,
#      so nothing in this registry hardcodes an unconditional 4 anymore
#      except the terminal `cutover` gate covered by scenario 1 -- this
#      scenario instead proves provision.sh's OWN exit-code-4-is-MANUAL
#      classification, independent of which real step ever produces it,
#      the same way scenario 2 injects a 3 to prove SKIPPED-continues) ->
#      provision.sh stops there, resume hint names discord, exit 1.
#   4. FAILED-STOPS -- a step's apply returns 1 -> provision.sh stops
#      there, resume hint names that step, exit 2; steps AFTER it never
#      run (their call-log entries absent).
#   5. DRY-RUN-NEVER-APPLIES -- --dry-run: every step's preflight runs,
#      but --apply is NEVER passed to anything (checked via the call log
#      -- zero "--apply" tokens anywhere in it).
#   6. FROM-SKIPS-EARLIER -- --from provision-resources: steps before it
#      never run at all (absent from the call log), it and after do.
#   7. ONLY-RUNS-EXACTLY-ONE -- --only etl-role: exactly one step's
#      scripts run (plus its own declared dependency-check call, per
#      scenario 7a-7c below), nothing before or after.
#   7a. DEPENDENCY-CHECK-REFUSES-PGRST-FLIP (Sec F-5, PR #849 review's own
#      named minimum) -- pgrst-gates' own live preflight reports a real
#      REFUSED finding -> --only pgrst-flip refuses BEFORE calling
#      coolify-env.sh at all -- the §6.9 VETO gate can no longer be
#      bypassed by jumping straight to the flip.
#   7b. DEPENDENCY-CHECK-REFUSES-DEPLOY-APP (Sec F-5's own named "milder"
#      example) -- mint-jwt's own preflight reports a finding -> --only
#      deploy-app refuses before calling deploy-app.sh.
#   7c. SKIP-DEPENDENCY-CHECK-OVERRIDES -- the same unmet precondition as
#      7a, with --skip-dependency-check passed -> proceeds, printing what
#      it is skipping rather than silently doing so.
#   8. LIST-NO-ENV-NEEDED -- --list works with NO .env present at all
#      (never reaches the .env check) and runs nothing.
#   9. ENV-MISSING-NAMES -- an .env missing operator-provided names ->
#      exit 3, message names the missing set.
#  10. UNKNOWN-STEP-KEY -- --from/--only naming a step not in the
#      registry -> exit 3.
#  11. KEYGEN-ABSENT-GENERATES -- ci-migrate keypair absent -> the fake
#      ssh-keygen on PATH is invoked and both files exist after.
#  12. KEYGEN-PRESENT-SKIPS -- ci-migrate keypair already present -> the
#      fake ssh-keygen is NEVER invoked (its own call-log stays empty).
#  13. COMPOUND-STEP-PROPAGATES -- the provision-resources step's SECOND
#      provision-worker.sh call fails -> the whole step fails, the run
#      stops there (never reaches 'secrets').
#  14. BOX_IP-REACHES-EVERY-SUB-SCRIPT-THAT-NEEDS-IT (D-1, live
#      --dry-run, 2026-09-20) -- a full --dry-run walkthrough: every
#      fake call logged under a name whose real script requires BOX_IP
#      via the environment shows a real value, never BOX_IP=<ABSENT>.
#      Two names (provision-migrator-app, migrator-scheduled-task) were
#      missing this entirely until this fix.
#  15. DRY-RUN-BLOCKED-BY-VS-GENUINE-FAILURE (D-2, live --dry-run,
#      2026-09-20) -- a combined full --dry-run: a step whose own
#      declared prerequisite ALSO failed this same run is classified
#      BLOCKED-BY <prereq>, not counted as a genuine failure; a step
#      whose prerequisite is satisfied but which independently fails IS
#      counted -> exit 3, never the old unconditional exit 0.
#  16. DRY-RUN-BLOCKED-BY-THROUGH-LENIENT-INTERMEDIATE (team-lead
#      follow-up on 15, live --dry-run, 2026-09-20) -- record-uuids.sh's
#      own preflight succeeds (VERIFIED) even though pfin-back-etl does
#      not exist, by design ("absent -> info, not failure"); a one-hop
#      BLOCKED-BY check falls through to misclassifying nonsecret-env/
#      etl-role/provider-sync-role as independent failures. Fixed to
#      walk one hop further, through record-uuids' own lenient status,
#      into provision-resources's live done-predicate.
#  17. STANDUP-LIVE-DONE-SKIPS-APPLY (team-lead follow-up, live
#      --dry-run, 2026-09-20) -- run_standup()'s own live_done_standup()
#      reports already-healthy -> standup.sh is never called at all,
#      "VERIFIED without applying" prints instead.
#  18. STANDUP-NOT-DONE-CALLS-STANDUP -- live_done_standup reports NOT
#      healthy -> falls through to calling standup.sh normally, proving
#      the fallback path (not just the new skip path) still works.
#  19. PGRST-FLIP-LIVE-DONE-SKIPS-APPLY (db-bootstrap-fix follow-up,
#      2026-09-21) -- coolify-env.sh's own preflight read already shows
#      PGRST_DB_SCHEMAS at the desired value -> live_done_pgrst_flip()
#      reports done, memoized across preflight+apply -> exactly ONE
#      "coolify-env" call for the whole run, never a PATCH or --deploy.
#  20. PGRST-FLIP-NOT-DONE-CALLS-APPLY -- not live-done -> falls through
#      to a real --apply --deploy call once the apply phase runs.
#  21. ETL-ROLE-ADOPT-BY-ROTATION (team-lead's own live measurement,
#      2026-09-21: pfin_etl/pfin_provider_sync already carry LOGIN+
#      password with no worker-resource store value yet) --
#      db-role-handoff.sh's own preflight reports EXACTLY the adoptable
#      INCONSISTENT shape (LOGIN+password, no store value) on both the
#      preflight-phase and apply-phase probes -> the third, real call
#      carries --apply --rotate, never a plain --apply handoff.
#  22. ETL-ROLE-NOT-ADOPTABLE-UNCHANGED -- a DIFFERENT INCONSISTENT shape
#      (store value present, role still NOLOGIN) never triggers the
#      adopt path -- stays a hard refusal via the plain call, same as
#      before this wrapper existed.
#  23. PGRST-FLIP-PROBE-READ-FAILS-NOT-TREATED-AS-DONE -- the live-done
#      probe's own coolify-env.sh call exits non-zero -> UNKNOWN, never
#      silently treated as done; falls through to the real call, which
#      fails for the same genuine reason.
#  24. PGRST-FLIP-STORE-MATCHES-CONTAINER-DOESNT (Sec C-1) -- the store
#      matches but the RUNNING container (pgrst-schemas-live-check.sh)
#      does not -> not done, falls through to a real --apply --deploy.
#  25. PGRST-FLIP-CONTAINER-CHECK-UNREACHABLE (Sec C-1) -- the store
#      matches but the container check itself cannot be attempted (rc=2)
#      -> UNKNOWN, not done, falls through to a real call.
#  26. DEPLOY-APP-USES-RESOLVED-VALUE-NOT-LITERAL-NAME (team-lead, run 4,
#      2026-09-21) -- `--only deploy-app`: the deploy-app.sh fake's own
#      calls.log entry for --require-network carries resolve-stack-
#      network.sh's OWN resolved output, never the literal string
#      "APP_STACK_NETWORK_NAME" -- and resolve-stack-network.sh's own
#      call counter is exactly 1 for the whole run, proving
#      resolve_stack_network_value() memoizes across the preflight AND
#      apply calls to run_deploy_app() (two calls to the step, one
#      resolution).
#  27. DEPLOY-WORKERS-RESOLVE-MEMOIZED-ACROSS-ALL-THREE-WORKERS --
#      `--only deploy-workers`: all three deploy-app.sh fake calls (etl,
#      provider-sync, pdf-render) carry the IDENTICAL resolved value on
#      --require-network, never a literal *_STACK_NETWORK_NAME, and
#      resolve-stack-network.sh's own call counter is exactly 1 for the
#      whole run (3 workers x 2 phases = 6 potential call sites, all
#      served by one memoized resolution).
#  27b. DEPLOY-WORKERS-POST-DEPLOY-VERIFY-FAILS-STOPS-THE-STEP (team-lead's
#      run-6 stop, item 10; backfilled into this list, previously
#      undocumented here despite existing in the script below) -- the
#      post-deploy store re-verify failing for pfin-back-etl stops the
#      whole step before provider-sync/pdf-render are ever reached.
#  27c. DEPLOY-WORKERS-CA1-CHECK-RUNS-ON-EVERY-WORKER (Sec's own
#      correction of req 4, run-10/step-16 review, 2026-09-21) --
#      verify-worker-ca1-clear.sh runs for ALL THREE workers
#      unconditionally, each with the <name> --service <svc> call
#      shape -- worker_has_admission_guard()'s result is now only an
#      INFORMATIONAL log line, never a skip condition (pdf-render has a
#      real HTTP listener + no code-level refusal, so "no guard" was
#      backwards for exactly the worker that needed the check most).
#  27d. DEPLOY-WORKERS-ADMISSION-GUARD-MISSING-COMPOSE-FILE-DIES -- a
#      worker's docker-compose.yaml absent entirely (not merely lacking
#      the override) hard-stops (die3, exit 3) rather than being treated
#      as "no admission guard" -- a missing file where one is expected is
#      still a bigger problem than the informational tag it would have
#      produced.
#  27e. DEPLOY-WORKERS-RESUME-PATH-CLEAR-INVOKED-BEFORE-DEPLOY (team-
#      lead's run-10 stop: a resume from/after deploy-workers never
#      revisits provision-resources' own fqdn/ports_exposes clear) --
#      fqdn reported SET on the pre-deploy read invokes provision-
#      worker.sh's --apply clear BEFORE that worker's own deploy-app.sh
#      --apply call, proven by call-log ORDER, not just presence.
#  27f. DEPLOY-WORKERS-RESUME-PATH-READ-FAILURE-PROPAGATES -- the
#      pre-deploy state-read itself failing fails CLOSED (propagates),
#      never silently deploys against an unknown state.
#  28. RESOLVE-STACK-NETWORK-FAILURE-BLOCKS-DEPLOY-APP -- resolve-stack-
#      network.sh itself fails (rc=1) -> run_deploy_app() propagates the
#      failure (exit 2, a genuine FAILED-STOPS outcome) and deploy-app.sh
#      is NEVER called -- a resolution failure must never fall through to
#      passing an empty or stale network value.
#  29-32. CUTOVER'S REAL HETZNER CHECK (BACKLOG.md item 90 follow-up,
#      F/CTO's live measurement that the incumbent pfindash.com box was
#      already torn down) -- run_cutover() no longer returns an
#      unconditional 4/MANUAL once --confirm-cutover is passed; it
#      lists the Hetzner project's servers and requires EXACTLY one,
#      named pfin-prod-1:
#        29.  ONE-SERVER-VERIFIED -- the ruled steady state -> exit 0.
#        29a. ONE-SERVER-WRONG-NAME-REFUSES -- count matches but the
#             name doesn't -> FAILED, never guesses this is fine.
#        30.  TWO-SERVERS-MANUAL -- more than one server -> MANUAL,
#             naming BOTH, never deletes anything (no delete branch
#             exists in this fixture's fake curl at all).
#        31.  ZERO-SERVERS-FAILED -- an empty project -> FAILED, never
#             silently treated as "incumbent gone, therefore fine".
#        32.  API-ERROR-FAILED -- the Hetzner call itself fails
#             (network/auth/transport) -> FAILED, never silently
#             treated as "no servers" or "verified".
#      Token-never-in-argv (Sec's PR #814 standard) is checked on every
#      one of these via the shared leak-log mechanism.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/provision"
FAKE_SCRIPTS_DIR="$FIXTURE_DIR/scripts"
PROVISION_SH="$REPO_ROOT/scripts/provision.sh"

[[ -d "$FAKE_SCRIPTS_DIR" ]] || { echo "FATAL: $FAKE_SCRIPTS_DIR missing" >&2; exit 2; }
[[ -f "$PROVISION_SH" ]] || { echo "FATAL: $PROVISION_SH not found" >&2; exit 2; }

# SENTINEL_PREFIX/SENTINEL_MID (Sec run-11-stop requirement 1) -- the
# LITERAL shape scripts/provision-worker.sh's --state prints and
# scripts/provision.sh's own worker_fqdn_clear_if_needed() greps for,
# pinned HERE ONCE so every fixture string in this fence (including
# run_case()'s own default baseline below) is built from these, never
# retyped -- see the SENTINEL-FORMAT-PINNED check further down (grep'd
# against the REAL, never the fixture, producer/consumer files) for why:
# a fixture that no longer matches what ships is exactly the failure
# class that caused run 11.
SENTINEL_PREFIX='current state: fqdn='
SENTINEL_MID=', ports_exposes='

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_SSH_KEYGEN_LOG:-}" ]]; then
  printf 'ssh-keygen %s\n' "$*" >> "$FAKE_SSH_KEYGEN_LOG"
fi
# Parse -f <path> and create <path> + <path>.pub, matching real ssh-keygen.
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-f" ]]; then
    mkdir -p "$(dirname "$arg")"
    printf 'fake-private-key\n' > "$arg"
    printf 'fake-public-key\n' > "$arg.pub"
  fi
  prev="$arg"
done
exit 0
EOF
chmod +x "$FAKE_BIN/ssh-keygen"

# Fake `curl` -- run_cutover()'s ONLY external call site (provision.sh
# itself never calls curl anywhere else; confirmed by grep before this
# fixture was written). Distinguishes the Hetzner servers-list endpoint
# by URL; anything else fails closed rather than silently no-op'ing, so
# an unexpected future curl call in provision.sh's own code cannot pass
# this fence by accident. Leak-check (Sec's "token never in argv"
# standard, PR #814 review) -- if $HETZNER_TOKEN_LEAK_VALUE appears
# ANYWHERE in this invocation's own argv, writes a sentinel to
# $FAKE_LEAK_LOG; every scenario reaching cutover asserts that file
# stays empty.
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ARGS="$*"
if [[ -n "${HETZNER_TOKEN_LEAK_VALUE:-}" ]] && printf '%s' "$ARGS" | grep -qF "$HETZNER_TOKEN_LEAK_VALUE"; then
  printf 'LEAK: HETZNER_API_TOKEN value found in curl argv: %s\n' "$ARGS" >> "${FAKE_LEAK_LOG:-/dev/null}"
fi
if [[ "$ARGS" == *"api.hetzner.cloud/v1/servers"* ]]; then
  if [[ "${FAKE_HETZNER_API_FAILS:-0}" == "1" ]]; then
    echo "curl: (7) Failed to connect to api.hetzner.cloud (simulated)" >&2
    exit 7
  fi
  # A literal JSON default embedded directly inside ${VAR:-...} mangles
  # under bash's own brace-matching (measured: the unescaped `}`
  # characters in the JSON confuse where the expansion itself ends) --
  # self-caught running this fence: the default came out as
  # `{"servers":[{"name":"pfin-prod-1"]}}`, missing a brace, which then
  # failed to parse as JSON. Computed as a plain variable first instead.
  DEFAULT_SERVERS_JSON='{"servers":[{"name":"pfin-prod-1"}]}'
  printf '%s' "${FAKE_HETZNER_SERVERS_JSON:-$DEFAULT_SERVERS_JSON}"
  exit 0
fi
echo "FAKE CURL (provision fence): unrecognised invocation: $ARGS" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/curl"

# 64-char, distinctive-not-generic (BACKLOG item 90 follow-up, cutover
# real-check): run_cutover() now validates HETZNER_API_TOKEN's SHAPE
# (64 chars, real Hetzner tokens' length) before ever calling curl, so
# a 1-char placeholder like the old "x" would make EVERY scenario that
# reaches cutover with --confirm-cutover fail closed on a token-shape
# mismatch it was never testing for. Distinctive (not just 64 x's) so
# the fake curl's own leak-check (below) can grep for it specifically
# in argv without matching some other placeholder's incidental "x"s.
HETZNER_TOKEN_LEAK_VALUE="hetznerleakcheckhetznerleakcheckhetznerleakcheckhetznerleakcheck"
FULL_ENV="HETZNER_API_TOKEN=$HETZNER_TOKEN_LEAK_VALUE
COOLIFY_ADMIN_EMAIL=x@example.com
COOLIFY_ADMIN_NAME=x
COOLIFY_ADMIN_PASSWORD=x
SMTP_PASS=x
PDF_WORKER_SIGNING_KEY=x
WORKER_ADMISSION_SHARED_SECRET=x
DISCORD_WEBHOOK_URL=x
FMP_API_KEY=x
BLS_API_KEY=x
PLAID_CLIENT_ID=x
PLAID_SECRET=x
SIMPLEFIN_TOKEN=x
PORKBUN_API_KEY=x
PORKBUN_SECRET_KEY=x
BOX_IP=127.0.0.1
"

FAIL=0

run_case() {
  # run_case <desc> <expect_exit> <env-dir-setup-fn> [extra provision.sh args...]
  local desc="$1" expect_exit="$2"; shift 2
  local extra_args=("$@")
  local case_dir="$WORK/case.$$.$RANDOM"
  mkdir -p "$case_dir"
  local call_log="$case_dir/calls.log"
  local keygen_log="$case_dir/keygen.log"
  local leak_log="$case_dir/leak.log"
  : > "$call_log"
  : > "$keygen_log"
  : > "$leak_log"
  printf '%s' "$FULL_ENV" > "$case_dir/.env"
  # CI_MIGRATE_SSH_PUBKEY points inside case_dir by default (absent unless the case pre-creates it).
  printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\n' "$case_dir" >> "$case_dir/.env"

  # worker_has_admission_guard() (provision.sh, CA-1 identity review,
  # run-9 stop 2026-09-21) reads $REPO_ROOT/<base-dir>/docker-compose.yaml
  # structurally -- REPO_ROOT is this case_dir, so every case gets its
  # own copy of the three workers' real admission-guard shape (provider-
  # sync HAS the serve-admission.js override; etl/pdf-render do NOT),
  # mirroring the actual tree exactly rather than inventing a fixture
  # shape. A scenario that wants to test the "no compose file at all"
  # die3 path removes one of these after run_case populates them (see
  # the ADMISSION-GUARD-DERIVATION scenario below).
  mkdir -p "$case_dir/workers/etl" "$case_dir/workers/provider-sync" "$case_dir/workers/pdf-render"
  printf 'services:\n  pfin-back-etl:\n    build: .\n' > "$case_dir/workers/etl/docker-compose.yaml"
  # CASE_OMIT_PROVIDER_SYNC_COMPOSE (set by a scenario BEFORE calling
  # run_case, unset/"0" otherwise) leaves provider-sync's compose file
  # missing entirely from the start -- deterministic, not a race against
  # provision.sh's own apply-phase timing (an earlier draft of this
  # fixture tried to delete the file mid-run in a background job; this
  # is the same property without a timing dependency).
  if [[ "${CASE_OMIT_PROVIDER_SYNC_COMPOSE:-0}" != "1" ]]; then
    printf 'services:\n  provider-sync:\n    build: .\n    command: ["node", "dist/cli/serve-admission.js"]\n' > "$case_dir/workers/provider-sync/docker-compose.yaml"
  fi
  printf 'services:\n  pdf-render:\n    build: .\n' > "$case_dir/workers/pdf-render/docker-compose.yaml"

  set +e
  # `env` throughout, not bash prefix-assignment syntax: a NAME=value word
  # produced by array expansion (${CASE_ENV[@]}) is not RECOGNIZED as a
  # prefix assignment by bash's parser (that classification is syntactic,
  # on the literal source token, before any expansion happens) -- it gets
  # treated as a plain command-name argument instead ("command not
  # found"). `env` accepts NAME=value as ordinary argv, sidestepping this.
  # bash 3.2 (macOS default, pre-4.4) also trips `set -u`'s "unbound
  # variable" on "${arr[@]}" for a TRULY EMPTY array -- the
  # ${arr[@]+"${arr[@]}"} form is the standard safe idiom for that.
  # team-lead's run-6 stop, item 10 -- run_deploy_workers() now calls
  # db-role-handoff.sh a SECOND time (post-deploy re-verify), grepping
  # its output for "VERIFIED". The generic fake below never prints that
  # unless told to, so every scenario defaults to a VERIFIED-shaped
  # stdout here; a scenario testing the NEW guard's own failure path
  # overrides FAKE_STDOUT_db_role_handoff via its own CASE_ENV entry,
  # which -- appearing later in this `env` invocation -- wins. (Naming
  # matches this fixture's own convention -- the fake computes its var
  # name from `basename "$0" .sh` verbatim, lowercase, dashes to
  # underscores; it does NOT uppercase, despite this file's own header
  # comment claiming it does.)
  #
  # Same default-baseline shape for FAKE_STDOUT_provision_worker
  # (run-11 stop fix, 2026-09-21): worker_fqdn_clear_if_needed() now
  # REQUIRES a parseable "current state: ..." line on every --state
  # call and REFUSES (never "no line -> assume clear") when one is
  # missing -- correct behavior for the real regression this closes,
  # but it means every scenario that exercises deploy-workers and does
  # NOT care about this mechanism needs a clean, already-cleared
  # default so it isn't dragged into asserting fqdn/ports_exposes
  # state it never set out to test. A scenario that DOES want to
  # exercise the clear-path overrides this default via CASE_ENV's own
  # FAKE_STDOUT_LIST_provision_worker (takes precedence -- see
  # fake-step.sh's own header), same override discipline as
  # FAKE_STDOUT_db_role_handoff above.
  env REPO_ROOT="$case_dir" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" \
    FAKE_CALL_LOG="$call_log" FAKE_COUNTER_DIR="$case_dir" FAKE_SSH_KEYGEN_LOG="$keygen_log" \
    FAKE_LEAK_LOG="$leak_log" HETZNER_TOKEN_LEAK_VALUE="$HETZNER_TOKEN_LEAK_VALUE" \
    FAKE_HETZNER_API_FAILS="${FAKE_HETZNER_API_FAILS:-0}" FAKE_HETZNER_SERVERS_JSON="${FAKE_HETZNER_SERVERS_JSON:-}" \
    FAKE_STDOUT_db_role_handoff="VERIFIED already handed off -- store and live role bind-checked, no-op." \
    FAKE_STDOUT_provision_worker="${SENTINEL_PREFIX}ABSENT${SENTINEL_MID}ABSENT" \
    ${CASE_ENV[@]+"${CASE_ENV[@]}"} \
    bash "$PROVISION_SH" ${extra_args[@]+"${extra_args[@]}"} > "$case_dir/out.txt" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$case_dir/out.txt" >&2
    echo "----- call log -----" >&2
    cat "$call_log" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  CASE_LAST_DIR="$case_dir"
  return 0
}

# 1. HAPPY-PATH -- dns -> ci-keypair -> github-ci -> deploy-on-success ->
# remaining-checks -> cutover, SIX CONSECUTIVE, fully-scripted steps (the
# registry's last five before cutover -- QA, BACKLOG.md §7.36 item 81
# moved `remaining-checks` to immediately before `cutover`, after
# `deploy-on-success`, so its own auth-login leg can reach the domain
# `dns` assigns; it was FOUR before that move -- PLUS cutover itself,
# now a real check per BACKLOG.md item 90's own follow-up: F/CTO
# measured live via the Hetzner API that the incumbent pfindash.com box
# was already torn down, so `run_cutover` no longer returns an
# unconditional 4/MANUAL once --confirm-cutover is passed -- it lists
# the Hetzner project's servers and VERIFIES exactly one, named
# `pfin-prod-1`. This registry CAN now complete past cutover with exit
# 0 -- the one-way-door property lives in the GATE (REFUSED without
# --confirm-cutover, unchanged below), not in cutover being
# permanently unsatisfiable once past it. The fake curl's own DEFAULT
# response (no CASE_ENV override) is a clean single `pfin-prod-1`
# server, so this happy-path scenario -- which cares about the
# REGISTRY WALK, not the Hetzner check's own predicates (scenarios
# 29-32 below cover those) -- reaches a genuine end-to-end VERIFIED.
# `remaining-checks` reads VERIFIED here because the generic
# fake-step.sh dispatcher's own default (no
# FAKE_RC_smoke_remaining_checks override in this scenario's CASE_ENV) is
# exit 0 -- this scenario is about the REGISTRY WALK, not
# smoke-remaining-checks.sh's own control flow, which
# fence-smoke-remaining-checks-strikes.sh covers on its own.
CASE_ENV=()
# Sec F-6 (PR #849 review): dns is now ALSO gated behind
# --confirm-cutover (the apex A repoint is the user-visible go-live
# switch) -- a happy-path run reaching dns->cutover must pass it, same
# as it always needed to for cutover's own gate.
run_case "happy-path (dns -> ci-keypair -> github-ci -> deploy-on-success -> remaining-checks -> cutover, all VERIFIED)" 0 --from dns --confirm-cutover || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  VERIFIED_COUNT="$(grep -c ': VERIFIED' "$CASE_LAST_DIR/out.txt" 2>/dev/null || echo 0)"
  [[ "$VERIFIED_COUNT" == "6" ]] || { echo "FAIL: [happy-path] expected 6 VERIFIED steps (5 + cutover), saw $VERIFIED_COUNT" >&2; FAIL=1; }
  grep -qF "cutover: the Hetzner project holds exactly one server (pfin-prod-1); the incumbent is gone" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [happy-path] cutover did not report its own VERIFIED line -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2; FAIL=1; }
  [[ -s "$CASE_LAST_DIR/leak.log" ]] && { echo "FAIL: [happy-path] the Hetzner token leaked into curl argv: $(cat "$CASE_LAST_DIR/leak.log")" >&2; FAIL=1; }
fi

# 6a. DNS-REFUSES-WITHOUT-CONFIRM-CUTOVER (Sec F-6, PR #849 review) --
#     dns alone, no --confirm-cutover -> refuses (MANUAL, exit 1),
#     before assign-app-domain.sh is ever called.
run_case "--only dns without --confirm-cutover refuses" 1 --only dns || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qi "REFUSED without --confirm-cutover" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [dns-no-confirm] did not name the missing --confirm-cutover flag" >&2; FAIL=1; }
  if grep -q "^assign-app-domain" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [dns-no-confirm] assign-app-domain.sh was called despite the missing --confirm-cutover flag" >&2
    FAIL=1
  fi
fi

# 6b. DNS-PROCEEDS-WITH-CONFIRM-CUTOVER -- same target, --confirm-cutover
#     passed -> proceeds normally (reaches assign-app-domain.sh).
run_case "--only dns with --confirm-cutover proceeds" 0 --only dns --confirm-cutover || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^assign-app-domain" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [dns-with-confirm] assign-app-domain.sh was never called despite --confirm-cutover" >&2; FAIL=1; }
fi

# 2. SKIPPED-CONTINUES -- the smokes step's own overall result is SKIPPED
# (its admission-endpoint sub-call returns 3, worst-of tracked) but that
# is NOT a failure -- selecting it alone must still exit 0.
CASE_ENV=(FAKE_RC_smoke_admission_endpoint=3)
run_case "skipped step continues, exit 0" 0 --only smokes || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -q "SKIPPED" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [skipped step continues] output does not mention SKIPPED" >&2
  FAIL=1
fi

# 3. MANUAL-STOPS -- discord's fake reports 4 this run (see the header
# comment above for why this is now an INJECTED code, not a hardcoded
# stub -- BACKLOG item 74, scripts/coolify-discord-notify.sh).
CASE_ENV=(FAKE_RC_coolify_discord_notify=4)
run_case "manual step (discord) stops the run, exit 1" 1 --only discord || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -q -- "--from discord" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [manual step] resume hint does not name discord" >&2
  FAIL=1
fi

# 4. FAILED-STOPS -- provision-vps.sh's apply fails
# shellcheck disable=SC2054  # intentional: ONE element, "0,1" is fake-step.sh's own comma-separated per-call RC list, not two array elements
CASE_ENV=(FAKE_RC_provision_vps=0,1)
run_case "a real failure stops the run, exit 2" 2 --only provision-vps || FAIL=1

# 5. DRY-RUN-NEVER-APPLIES
CASE_ENV=()
run_case "dry-run never applies anything" 0 --dry-run --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && grep -q -- "--apply" "$CASE_LAST_DIR/calls.log"; then
  echo "FAIL: [dry-run] call log shows an --apply invocation" >&2
  cat "$CASE_LAST_DIR/calls.log" >&2
  FAIL=1
fi

# 6. FROM-SKIPS-EARLIER -- --from provision-resources: provision-vps.sh
# must never appear in the call log. provision-resources (step 6) is
# preceded by db-bootstrap(3)/pre-cutover-gates(4), both MANUAL, but
# --from jumps straight past them without running them at all; the run
# then proceeds through every scripted step (7-16) and correctly stops at
# ca1-gate(17), the next MANUAL step, exit 1.
CASE_ENV=()
run_case "--from skips earlier steps" 1 --from provision-resources || true
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if grep -q "provision-vps" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--from provision-resources] provision-vps.sh (an earlier step) was called" >&2
    FAIL=1
  elif ! grep -q "provision-worker" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--from provision-resources] provision-worker.sh (the target step) was never called" >&2
    FAIL=1
  else
    echo "OK: [--from provision-resources] earlier steps skipped, target step ran." >&2
  fi
fi

# 7. ONLY-RUNS-EXACTLY-ONE
CASE_ENV=()
run_case "--only runs exactly one step" 0 --only etl-role || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  # grep -c prints a count either way; its own exit status (1 = zero
  # matches) is not an error here, so no `|| echo 0` fallback -- chaining
  # one would DOUBLE the captured output ("0" from grep, then another "0"
  # from the fallback) on the exact zero-matches case this checks for.
  # "db-bootstrap" is now ALSO expected (Sec F-5, PR #849 review): --only
  # etl-role's own declared STEP_REQUIRES prerequisite (db-bootstrap) is
  # live-rechecked once, in PREFLIGHT mode only, before the target step
  # runs -- a legitimate call the dependency gate itself makes, not a
  # stray extra step being executed. "provision-app"/"provision-worker"
  # are ALSO now expected (team-lead follow-up, live --dry-run,
  # 2026-09-20): etl-role's own STEP_REQUIRES was widened to
  # "db-bootstrap,provision-resources" (it genuinely needs the
  # pfin-back-etl resource to exist, not just the role) -- the same
  # dependency gate now ALSO live-rechecks provision-resources' own
  # preflight, which shells out to provision-app.sh + 3x
  # provision-worker.sh.
  set +e
  OTHER_CALLS="$(grep -vc "db-role-handoff\|db-bootstrap\|provision-app\|provision-worker\|record-coolify-uuids" "$CASE_LAST_DIR/calls.log" 2>/dev/null)"
  set -e
  if [[ "$OTHER_CALLS" != "0" ]]; then
    echo "FAIL: [--only] a non-target, non-dependency-check script was called" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
  # Prefix match (name + a following space) -- fake-step.sh's call-log
  # line is "<name> BOX_IP=<value> <args...>" (D-1, live --dry-run,
  # 2026-09-20), never bare "<name>" or "<name> " alone any more, so an
  # exact-line match would never fire regardless of dependency-check
  # correctness.
  if ! grep -q "^db-bootstrap " "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [--only] expected the dependency-check call to db-bootstrap (etl-role's own declared prerequisite) in the call log -- it may have been silently skipped" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7a. DEPENDENCY-CHECK-REFUSES-PGRST-FLIP (Sec F-5, PR #849 review's own
#     named minimum) -- pgrst-gates' own preflight reports rc=1 (a real
#     REFUSED finding, e.g. anon holds a grant) -> `--only pgrst-flip`
#     refuses BEFORE calling coolify-env.sh at all, never exposing `pfin`
#     on the Data API with the VETO gate unevaluated.
CASE_ENV=(FAKE_RC_pgrst_exposure_gates=1)
run_case "--only pgrst-flip without gates passing refuses" 3 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "pgrst-gates" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-dependency] did not name pgrst-gates as the unmet prerequisite" >&2; FAIL=1; }
  if grep -q "^coolify-env" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [pgrst-flip-dependency] coolify-env.sh was called despite the unmet prerequisite -- the flip was not actually prevented" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7b. DEPENDENCY-CHECK-REFUSES-DEPLOY-APP (Sec F-5, PR #849 review's own
#     named "milder" example) -- mint-jwt's own preflight reports rc=1 ->
#     `--only deploy-app` refuses before calling deploy-app.sh at all.
CASE_ENV=(FAKE_RC_mint_supabase_jwt_keys=1)
run_case "--only deploy-app with mint-jwt not done refuses" 3 --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "mint-jwt" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [deploy-app-dependency] did not name mint-jwt as the unmet prerequisite" >&2; FAIL=1; }
  if grep -q "^deploy-app" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [deploy-app-dependency] deploy-app.sh was called despite the unmet prerequisite" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 7c. SKIP-DEPENDENCY-CHECK-OVERRIDES -- the same unmet pgrst-gates
#     precondition, but with --skip-dependency-check passed -> proceeds
#     (reaches coolify-env.sh), printing what it skipped rather than
#     silently doing so.
CASE_ENV=(FAKE_RC_pgrst_exposure_gates=1)
run_case "--skip-dependency-check overrides the gate" 0 --only pgrst-flip --skip-dependency-check || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qi "SKIPPING dependency check" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [skip-dependency-check] did not print what it was skipping" >&2; FAIL=1; }
  grep -q "^coolify-env" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [skip-dependency-check] coolify-env.sh was never called -- the override did not actually let the step proceed" >&2; FAIL=1; }
fi
CASE_ENV=()

# 8. LIST-NO-ENV-NEEDED
NO_ENV_DIR="$WORK/no-env-case"
mkdir -p "$NO_ENV_DIR"
set +e
REPO_ROOT="$NO_ENV_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" bash "$PROVISION_SH" --list > "$NO_ENV_DIR/out.txt" 2>&1
LIST_RC=$?
set -e
if [[ "$LIST_RC" != "0" ]]; then
  echo "FAIL: [--list with no .env] expected exit 0, got $LIST_RC" >&2
  cat "$NO_ENV_DIR/out.txt" >&2
  FAIL=1
else
  echo "OK: [--list with no .env] exit 0 as expected." >&2
fi

# 9. ENV-MISSING-NAMES
MISSING_DIR="$WORK/missing-env-case"
mkdir -p "$MISSING_DIR"
printf 'HETZNER_API_TOKEN=x\n' > "$MISSING_DIR/.env"
set +e
REPO_ROOT="$MISSING_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" bash "$PROVISION_SH" > "$MISSING_DIR/out.txt" 2>&1
MISSING_RC=$?
set -e
if [[ "$MISSING_RC" != "3" ]]; then
  echo "FAIL: [missing .env names] expected exit 3, got $MISSING_RC" >&2
  cat "$MISSING_DIR/out.txt" >&2
  FAIL=1
else
  echo "OK: [missing .env names] exit 3 as expected." >&2
fi

# 10. UNKNOWN-STEP-KEY
CASE_ENV=()
run_case "unknown --from key refuses, exit 3" 3 --from bogus-step-name || FAIL=1

# 11. KEYGEN-ABSENT-GENERATES -- --only discord chosen as a convenient
# no-real-side-effect step to observe the keygen behavior in isolation;
# BACKLOG item 74 turned discord into a real scripted step, so its fake
# must be told to report MANUAL (4) here the same way scenario 3 does,
# or this scenario's own exit-1 expectation (below) would silently stop
# testing what it claims to.
CASE_ENV=(FAKE_RC_coolify_discord_notify=4)
run_case "keygen absent -> generated" 1 --only discord || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if [[ ! -s "$CASE_LAST_DIR/keygen.log" ]]; then
    echo "FAIL: [keygen absent] fake ssh-keygen was never invoked" >&2
    FAIL=1
  elif [[ ! -f "$CASE_LAST_DIR/ci_migrate.pub" || ! -f "${CASE_LAST_DIR}/ci_migrate" ]]; then
    echo "FAIL: [keygen absent] keypair files were not created" >&2
    FAIL=1
  else
    echo "OK: [keygen absent] fake ssh-keygen invoked, files created." >&2
  fi
fi

# 12. KEYGEN-PRESENT-SKIPS
PRESENT_DIR="$WORK/keygen-present-case"
mkdir -p "$PRESENT_DIR"
printf '%s' "$FULL_ENV" > "$PRESENT_DIR/.env"
printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\n' "$PRESENT_DIR" >> "$PRESENT_DIR/.env"
printf 'existing-priv\n' > "$PRESENT_DIR/ci_migrate"
printf 'existing-pub\n' > "$PRESENT_DIR/ci_migrate.pub"
: > "$PRESENT_DIR/keygen.log"
: > "$PRESENT_DIR/calls.log"
set +e
REPO_ROOT="$PRESENT_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" \
  FAKE_CALL_LOG="$PRESENT_DIR/calls.log" FAKE_COUNTER_DIR="$PRESENT_DIR" FAKE_SSH_KEYGEN_LOG="$PRESENT_DIR/keygen.log" \
  FAKE_RC_coolify_discord_notify=4 \
  bash "$PROVISION_SH" --only discord > "$PRESENT_DIR/out.txt" 2>&1
PRESENT_RC=$?
set -e
if [[ "$PRESENT_RC" != "1" ]]; then
  echo "FAIL: [keygen present] expected exit 1 (discord is MANUAL), got $PRESENT_RC" >&2
  cat "$PRESENT_DIR/out.txt" >&2
  FAIL=1
elif [[ -s "$PRESENT_DIR/keygen.log" ]]; then
  echo "FAIL: [keygen present] fake ssh-keygen was invoked even though the keypair already existed" >&2
  FAIL=1
else
  echo "OK: [keygen present] fake ssh-keygen never invoked." >&2
fi

# 13. COMPOUND-STEP-PROPAGATES -- provision-resources calls
# provision-worker.sh 3x (pfin-back-etl, pfin-pdf-render, pfin-provider-sync);
# the 2nd call (pfin-pdf-render) fails.
# shellcheck disable=SC2054  # intentional: ONE element, "0,1" is fake-step.sh's own comma-separated per-call RC list, not two array elements
CASE_ENV=(FAKE_RC_provision_worker=0,1)
run_case "compound step: 2nd sub-call failing stops the whole run" 2 --from provision-resources || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]] && grep -q "Step.*secrets --" "$CASE_LAST_DIR/out.txt" 2>/dev/null; then
  echo "FAIL: [compound propagation] the run reached the 'secrets' step despite 'provision-resources' failing" >&2
  FAIL=1
fi

# 14. BOX_IP-REACHES-EVERY-SUB-SCRIPT-THAT-NEEDS-IT (D-1, live --dry-run,
#     2026-09-20) -- a full --dry-run walkthrough of the WHOLE registry
#     (no --from/--only, so every step's preflight runs): every fake call
#     logged under a name whose REAL counterpart requires BOX_IP passed
#     via the environment (never defaulted, never self-read from .env --
#     coolify-env.sh, provision-migrator-app.sh, migrator-scheduled-
#     task.sh, provision-app.sh, provision-worker.sh, record-coolify-
#     uuids.sh, push-production-secrets.sh, mint-supabase-jwt-keys.sh,
#     db-role-handoff.sh, deploy-app.sh, every smoke-*.sh that reads it,
#     worker-scheduled-task.sh) shows a real value, never
#     BOX_IP=<ABSENT>. Two of these (provision-migrator-app,
#     migrator-scheduled-task) were missing the export ENTIRELY until
#     this fix -- caught on the real box, not by this fence (which had
#     no BOX_IP leg before this PR). Strike: drop `require_box_ip` from
#     one run_* function on a disposable copy of provision.sh -> that
#     name's own call-log line(s) show BOX_IP=<ABSENT> -> this scenario
#     goes RED.
CASE_ENV=()
run_case "BOX_IP reaches every sub-script that requires it" 0 --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  BOX_IP_REQUIRED_NAMES="coolify-env provision-migrator-app migrator-scheduled-task provision-app provision-worker record-coolify-uuids push-production-secrets mint-supabase-jwt-keys db-role-handoff deploy-app smoke-admission-endpoint smoke-etl-poll smoke-pdf-roundtrip smoke-pfin-exposure smoke-ca1-env-pattern smoke-remaining-checks worker-scheduled-task verify-worker-ca1-clear"
  CHECKED_ANY=0
  for n in $BOX_IP_REQUIRED_NAMES; do
    if grep -q "^$n " "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
      CHECKED_ANY=1
      if grep "^$n " "$CASE_LAST_DIR/calls.log" | grep -q "BOX_IP=<ABSENT>"; then
        echo "FAIL: [box-ip-reaches-every-sub-script] '$n' was called with BOX_IP absent from its own environment" >&2
        grep "^$n " "$CASE_LAST_DIR/calls.log" >&2
        FAIL=1
      fi
    fi
  done
  [[ "$CHECKED_ANY" -eq 1 ]] || { echo "FAIL: [box-ip-reaches-every-sub-script] none of the BOX_IP-required names were even called -- the call log is not what this scenario expected" >&2; FAIL=1; }
fi

# 15. DRY-RUN-BLOCKED-BY-VS-GENUINE-FAILURE (D-2, live --dry-run,
#     2026-09-20) -- a single combined full --dry-run: provision-app.sh's
#     fake fails (models "the box is only partially provisioned -- this
#     resource does not exist yet"), so provision-resources itself
#     legitimately reads "would likely fail" (its OWN declared
#     prerequisite, pgrst-flip, is satisfied -- this is an independent
#     failure, not a cascade). record-coolify-uuids.sh's fake is ALSO
#     forced to fail (models "can't resolve a uuid for a resource that
#     doesn't exist"), but record-uuids' own declared STEP_REQUIRES
#     prerequisite is provision-resources, which just failed -- so
#     record-uuids must be classified BLOCKED-BY provision-resources, NOT
#     counted as an independent "would likely fail". Separately,
#     smoke-ca1-env-pattern.sh's fake is forced to fail while its own
#     prerequisite (deploy-workers) reports VERIFIED (its own fake
#     defaults to 0, uninvolved in this scenario's failures) -- a truly
#     independent failure, must read "would likely fail". Exit code must
#     be 3 (at least one genuine "would likely fail" exists), never 0 --
#     the exact defect this fixes: the OLD version printed "would likely
#     fail" ten times over and still exited 0.
CASE_ENV=(FAKE_RC_provision_app=1 FAKE_RC_record_coolify_uuids=1 FAKE_RC_smoke_ca1_env_pattern=1)
run_case "dry-run distinguishes BLOCKED-BY from a genuine failure, exit 3" 3 --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^  provision-resources .*would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] provision-resources not reported as an independent 'would likely fail'" >&2; FAIL=1; }
  grep -q "^  record-uuids .*BLOCKED-BY provision-resources" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] record-uuids not reported as BLOCKED-BY provision-resources" >&2; FAIL=1; }
  grep -q "^  ca1-gate .*would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] ca1-gate (independent failure, prerequisite satisfied) not reported as 'would likely fail'" >&2; FAIL=1; }
  grep -qi "would likely fail" "$CASE_LAST_DIR/out.txt" > /dev/null # sanity, already covered above
  grep -q "FAIL: [0-9]* step(s) would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-vs-genuine] summary did not print a truthful 'would likely fail' count" >&2; FAIL=1; }
fi

# 16. DRY-RUN-BLOCKED-BY-THROUGH-LENIENT-INTERMEDIATE (team-lead follow-up
#     on scenario 15, live --dry-run, 2026-09-20) -- record-uuids.sh's
#     own preflight SUCCEEDS (rc=0, VERIFIED) even though pfin-back-etl
#     does not exist, by DESIGN ("absent -> info, not failure" -- its own
#     header). A one-hop BLOCKED-BY check (scenario 15's own mechanism,
#     as it existed before this fix) sees nonsecret-env's DIRECT
#     prerequisite (record-uuids) reporting VERIFIED and falls through to
#     misclassifying nonsecret-env as an independent "would likely
#     fail" -- the exact live defect this scenario reproduces and pins.
#     provision-app.sh/provision-worker.sh's own preflights (provision-
#     resources) are ALSO lenient (0 = "safe to create", not "already
#     exists") -- provision-resources itself reads VERIFIED too, so this
#     is not a single-hop miss, it is TWO lenient hops in a row.
#     record-coolify-uuids.sh's own STDOUT (not its exit code) is the
#     only place that already performs a live, strict-enough check for
#     free -- FAKE_STDOUT_record_coolify_uuids injects its exact "no
#     application named 'pfin-back-etl' found yet" line so
#     live_done_provision_resources() (provision.sh's own new live-check,
#     re-shelling out to the SAME script, memoized) has something real to
#     grep. nonsecret-env's OWN preflight fails independently (its 2nd
#     coolify-env.sh call, targeting pfin-back-etl, forced to rc=1) --
#     same for etl-role/provider-sync-role (db-role-handoff.sh forced to
#     rc=1, modeling its own STRICT "no Coolify application named" die()
#     for the SAME missing resource -- see db-role-handoff.sh:312).
#     etl-role/provider-sync-role's own STEP_REQUIRES was ALSO widened in
#     this fix (was "db-bootstrap" alone, missing the pfin-back-etl/
#     pfin-provider-sync dependency their own script strictly needs) --
#     this scenario is the reason.
#     Expected: ALL THREE (nonsecret-env, etl-role, provider-sync-role)
#     read BLOCKED-BY provision-resources, not "would likely fail" --
#     and because nothing in this scenario is an independent failure
#     (every non-VERIFIED step traces back to the one unmet
#     precondition), the overall dry run exits 0, not 3. Everything
#     downstream (secrets/mint-jwt/deploy-app/deploy-workers/scheduled-
#     tasks/smokes/ca1-gate) still reads BLOCKED-BY too, each naming its
#     own immediate unsatisfied prerequisite -- confirmed unchanged
#     ("via a different path", per team-lead's own note) by NOT
#     asserting those individually here; scenario 15 already covers that
#     shape (deploy-workers/ca1-gate BLOCKED-BY / would-likely-fail).
#     FAKE_STDOUT_coolify_env (db-bootstrap-fix follow-up, 2026-09-21):
#     pgrst-flip's own live_done_pgrst_flip() now probes "coolify-env"
#     ONCE before ever reaching the real call (see live_done_pgrst_flip's
#     own header) -- without this, that probe would consume the FIRST
#     slot of FAKE_RC_coolify_env's "0,1" cycle, pgrst-flip's own
#     (unrelated to this scenario) fallback call would consume the
#     SECOND, and nonsecret-env's three calls -- what "0,1" was actually
#     aimed at -- would shift by one position, breaking pgrst-flip itself
#     (misclassified "would likely fail") without changing what this
#     scenario is trying to prove. Printing the desired value on every
#     "coolify-env" call lets pgrst-flip's own probe see itself as
#     already-flipped and return VERIFIED without a second call at all --
#     restoring the exact call-count/index alignment this scenario's
#     "0,1" cycle already assumed. nonsecret-env's own calls ignore this
#     stdout (they only check exit codes), so it is a no-op there.
# shellcheck disable=SC2054  # intentional: ONE element, "0,1" is fake-step.sh's own comma-separated per-call RC list, not two array elements
CASE_ENV=(FAKE_RC_coolify_env=0,1 FAKE_RC_db_role_handoff=1 FAKE_STDOUT_record_coolify_uuids="no application named 'pfin-back-etl' found yet" FAKE_STDOUT_coolify_env="      PGRST_DB_SCHEMAS=public,graphql_public,pfin")
run_case "dry-run BLOCKED-BY walks through a lenient intermediate step to the real cause" 0 --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^  provision-resources .*VERIFIED (dry-run)" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-through-lenient] provision-resources itself not reported VERIFIED (dry-run) -- this scenario's own setup assumption broke" >&2; FAIL=1; }
  grep -q "^  record-uuids .*VERIFIED (dry-run)" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-through-lenient] record-uuids itself not reported VERIFIED (dry-run) -- this scenario's own setup assumption broke" >&2; FAIL=1; }
  grep -q "^  nonsecret-env .*BLOCKED-BY provision-resources" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-through-lenient] nonsecret-env not reported BLOCKED-BY provision-resources -- the one-hop check regressed or was never fixed" >&2; FAIL=1; }
  grep -q "^  etl-role .*BLOCKED-BY provision-resources" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-through-lenient] etl-role not reported BLOCKED-BY provision-resources" >&2; FAIL=1; }
  grep -q "^  provider-sync-role .*BLOCKED-BY provision-resources" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [blocked-by-through-lenient] provider-sync-role not reported BLOCKED-BY provision-resources" >&2; FAIL=1; }
  if grep -qE "^  (nonsecret-env|etl-role|provider-sync-role) .*would likely fail" "$CASE_LAST_DIR/out.txt"; then
    echo "FAIL: [blocked-by-through-lenient] at least one of nonsecret-env/etl-role/provider-sync-role was still misclassified as an independent 'would likely fail'" >&2
    FAIL=1
  fi
fi

# 17. STANDUP-LIVE-DONE-SKIPS-APPLY (team-lead follow-up, live --dry-run,
#     2026-09-20) -- run_standup()'s own live_done_standup() reports
#     already-healthy (provision-supabase-stack.sh --check-healthy would
#     exit 0) -> standup.sh is NEVER called, "VERIFIED without applying"
#     prints instead, in BOTH the preflight and apply invocations. This
#     is the whole point of the fix: a real re-run against an already-
#     healthy stack does not churn through standup's own (individually
#     idempotent but not free) project/secrets/mount steps at all.
CASE_ENV=(FAKE_RC_provision_supabase_stack=0)
run_case "standup: live-done skips standup.sh entirely" 0 --only standup || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "already provisioned and healthy -- VERIFIED without applying" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [standup-live-done] did not print the VERIFIED-without-applying line" >&2; FAIL=1; }
  if grep -q "^standup " "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [standup-live-done] standup.sh was called despite live_done_standup reporting healthy" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
  # Sec C-2 (PR #852 AMBER review): the OLD assertions above only proved
  # standup.sh was never called -- they did NOT pin that
  # live_done_standup() actually invokes provision-supabase-stack.sh with
  # the literal --check-healthy flag. Dropping that flag silently (e.g. a
  # future edit typos it, or calls the script bare) would make
  # provision-supabase-stack.sh's OWN bare preflight run instead -- which
  # exits 0 unconditionally, at line 205-ish, before even reaching
  # check_stack_already_healthy() -- turning standup into a PERMANENT
  # silent no-op regardless of real stack health. Pin both halves: the
  # flag is present, and --apply is never paired with it on the same call.
  CALL_LINE="$(grep '^provision-supabase-stack ' "$CASE_LAST_DIR/calls.log" 2>/dev/null || true)"
  if [[ -z "$CALL_LINE" ]] || ! grep -qE '^provision-supabase-stack .*--check-healthy' <<<"$CALL_LINE"; then
    echo "FAIL: [standup-live-done] provision-supabase-stack.sh was not called with --check-healthy -- live_done_standup()'s own argv is unpinned" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  elif grep -qE -- '--apply' <<<"$CALL_LINE"; then
    echo "FAIL: [standup-live-done] provision-supabase-stack.sh's --check-healthy call also carried --apply -- a read-only probe must never be paired with a mutating flag" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 18. STANDUP-NOT-DONE-CALLS-STANDUP -- live_done_standup reports NOT
#     healthy -> falls through to the pre-existing behavior, calling
#     standup.sh normally (proves the fallback path still works, not
#     just the new skip path).
CASE_ENV=(FAKE_RC_provision_supabase_stack=1)
run_case "standup: not live-done falls through to standup.sh" 0 --only standup || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^standup " "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [standup-not-done] standup.sh was never called" >&2; cat "$CASE_LAST_DIR/calls.log" >&2; FAIL=1; }
fi
CASE_ENV=()

# 19. LIVE-DONE-PROVISION-RESOURCES-UNKNOWN-RC (Sec F-3(i), PR #852 AMBER
#     review) -- provision-resources itself never runs this invocation
#     (--only etl-role, --skip-dependency-check so the jump-target's own
#     prerequisite preflight isn't run either), so
#     live_done_provision_resources() is consulted with NO recorded
#     status to fall back on. record-coolify-uuids.sh's fake is forced to
#     exit non-zero WITHOUT printing any "no application named ... found"
#     line (models it dying on a missing MIGRATOR_APP_NAME/
#     SUPABASE_STACK_APP_NAME app instead -- record-coolify-uuids.sh
#     strictly `die`s on those two, never `info`s -- see its own header).
#     etl-role's OWN preflight also fails independently (db-role-
#     handoff.sh forced to rc=1). The OLD version defaulted an unmatched
#     grep to PROVISION_RESOURCES_LIVE_DONE=1 ("done") regardless of rc --
#     which, mechanically, also reads as "not blocking" to
#     step_live_blocker, so this scenario cannot distinguish old from new
#     behavior by BLOCKED-BY-vs-would-likely-fail alone. What it DOES pin
#     is the new, explicit "UNKNOWN" log line -- proving the code took the
#     unknown-rc branch at all rather than silently falling into the
#     matched-or-done binary the old version had.
CASE_ENV=(FAKE_RC_record_coolify_uuids=1 FAKE_STDOUT_record_coolify_uuids="no application named 'pfin-migrator' found -- run scripts/provision-migrator-app.sh --apply first, or override MIGRATOR_APP_NAME" FAKE_RC_db_role_handoff=1)
run_case "live_done_provision_resources: unmatched non-zero rc is UNKNOWN, not done" 3 --only etl-role --skip-dependency-check --dry-run || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "record-coolify-uuids.sh exited non-zero (rc=1) without naming a missing resource -- provision-resources live state is UNKNOWN" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [live-done-unknown-rc] did not print the UNKNOWN-state line -- unmatched non-zero rc is being silently treated as done" >&2; cat "$CASE_LAST_DIR/out.txt" >&2; FAIL=1; }
  grep -q "^  etl-role .*would likely fail" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [live-done-unknown-rc] etl-role not reported as its own 'would likely fail'" >&2; FAIL=1; }
fi
CASE_ENV=()

# 20. LIVE-DONE-PROVISION-RESOURCES-SKIPS-ON-BOX-IP-UNSET (Sec F-3(ii),
#     PR #852 AMBER review) -- BOX_IP is absent from .env entirely (a
#     custom case dir, not the standard run_case harness's FULL_ENV, which
#     always bakes in BOX_IP=127.0.0.1). etl-role's own require_box_ip
#     gate fails on its own merits (rc=2) -- genuinely independent of
#     provision-resources. --only etl-role --skip-dependency-check so the
#     jump-target's own prerequisite preflight (which would ALSO fail
#     require_box_ip and abort the whole run at the dependency-check gate,
#     exit 3, before ever reaching live_done_provision_resources() at all)
#     is not run. The OLD version's require_box_ip failure inside the live
#     check itself set PROVISION_RESOURCES_LIVE_DONE=0 ("blocking") --
#     which WOULD have misattributed etl-role's own BOX_IP-unset failure
#     to "BLOCKED-BY provision-resources" instead of showing its own
#     genuine cause. Pin BOTH: the new skip-log line fires, AND etl-role
#     reads its own "would likely fail", never BLOCKED-BY.
BOXIP_UNSET_DIR="$WORK/boxip-unset-case"
mkdir -p "$BOXIP_UNSET_DIR"
printf '%s' "$FULL_ENV" | grep -v '^BOX_IP=' > "$BOXIP_UNSET_DIR/.env"
printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\n' "$BOXIP_UNSET_DIR" >> "$BOXIP_UNSET_DIR/.env"
: > "$BOXIP_UNSET_DIR/calls.log"
: > "$BOXIP_UNSET_DIR/keygen.log"
set +e
env REPO_ROOT="$BOXIP_UNSET_DIR" SCRIPTS="$FAKE_SCRIPTS_DIR" PATH="$FAKE_BIN:$PATH" \
  FAKE_CALL_LOG="$BOXIP_UNSET_DIR/calls.log" FAKE_COUNTER_DIR="$BOXIP_UNSET_DIR" FAKE_SSH_KEYGEN_LOG="$BOXIP_UNSET_DIR/keygen.log" \
  bash "$PROVISION_SH" --only etl-role --skip-dependency-check --dry-run > "$BOXIP_UNSET_DIR/out.txt" 2>&1
BOXIP_UNSET_RC=$?
set -e
if [[ "$BOXIP_UNSET_RC" != "3" ]]; then
  echo "FAIL: [live-done-boxip-unset] expected exit 3, got $BOXIP_UNSET_RC" >&2
  cat "$BOXIP_UNSET_DIR/out.txt" >&2
  FAIL=1
else
  echo "OK: [live-done-boxip-unset] exit 3 as expected." >&2
  grep -q "BOX_IP unset -- skipping the live provision-resources check entirely" "$BOXIP_UNSET_DIR/out.txt" || { echo "FAIL: [live-done-boxip-unset] did not print the skip-live-check line" >&2; cat "$BOXIP_UNSET_DIR/out.txt" >&2; FAIL=1; }
  grep -q "^  etl-role .*would likely fail" "$BOXIP_UNSET_DIR/out.txt" || { echo "FAIL: [live-done-boxip-unset] etl-role not reported as its own 'would likely fail'" >&2; cat "$BOXIP_UNSET_DIR/out.txt" >&2; FAIL=1; }
  if grep -q "^  etl-role .*BLOCKED-BY provision-resources" "$BOXIP_UNSET_DIR/out.txt"; then
    echo "FAIL: [live-done-boxip-unset] etl-role was misattributed as BLOCKED-BY provision-resources instead of its own genuine BOX_IP-unset cause" >&2
    FAIL=1
  fi
fi

# 19. PGRST-FLIP-LIVE-DONE-SKIPS-APPLY (db-bootstrap-fix follow-up,
#     2026-09-21) -- coolify-env.sh's own preflight read for pgrst-flip
#     already shows PGRST_DB_SCHEMAS at the desired value ->
#     live_done_pgrst_flip() reports done, memoized -> the WHOLE run
#     (preflight AND apply) makes exactly ONE "coolify-env" call, never a
#     PATCH, never --deploy -- proving a re-run of an already-flipped box
#     does not redeploy the stack for no reason.
CASE_ENV=(FAKE_STDOUT_coolify_env="      PGRST_DB_SCHEMAS=public,graphql_public,pfin")
run_case "pgrst-flip: live-done skips PATCH/deploy entirely" 0 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "already = public,graphql_public,pfin on pfin-supabase-stack -- VERIFIED without a PATCH or redeploy" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-live-done] did not print the VERIFIED-without-PATCH line" >&2; FAIL=1; }
  CALLN="$(grep -c "^coolify-env " "$CASE_LAST_DIR/calls.log" 2>/dev/null || echo 0)"
  if [[ "$CALLN" != "1" ]]; then
    echo "FAIL: [pgrst-flip-live-done] expected exactly 1 coolify-env call (the live-done probe, memoized across preflight+apply), got $CALLN" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
  if grep -q "^coolify-env .*--apply\|^coolify-env .*--deploy" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [pgrst-flip-live-done] coolify-env.sh was called with --apply or --deploy despite live_done_pgrst_flip reporting done" >&2
    FAIL=1
  fi
fi

# 20. PGRST-FLIP-NOT-DONE-CALLS-APPLY -- no FAKE_STDOUT match (the
#     default) -> live_done_pgrst_flip reports NOT done -> falls through
#     to the real call, WITH --apply --deploy once the apply phase runs,
#     proving the fallback path (not just the new skip path) still works.
CASE_ENV=()
run_case "pgrst-flip: not live-done falls through to a real --apply --deploy" 0 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "^coolify-env .*--apply --deploy" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [pgrst-flip-not-done] no coolify-env call carried --apply --deploy" >&2; cat "$CASE_LAST_DIR/calls.log" >&2; FAIL=1; }
fi

# 21. ETL-ROLE-ADOPT-BY-ROTATION (team-lead's own named live measurement,
#     2026-09-21: pfin_etl/pfin_provider_sync already carry LOGIN+password
#     from 2026-09-19 work, with no worker-resource store value for
#     either yet) -- db-role-handoff.sh's own preflight reports EXACTLY
#     the adoptable INCONSISTENT shape (rolcanlogin=true has_password=true
#     store_has_PFIN_DB_PASSWORD=false) on BOTH the preflight-phase probe and
#     the apply-phase's own re-probe (the live state does not change
#     between them -- nothing mutates during a probe) -> the THIRD call
#     is the real one, and it carries --apply --rotate, never a plain
#     --apply handoff.
CASE_ENV=(FAKE_RC_db_role_handoff=1,1,0 FAKE_STDOUT_db_role_handoff="FAIL  role 'pfin_etl' / 'pfin-back-etl' state is INCONSISTENT -- rolcanlogin=true has_password=true store_has_PFIN_DB_PASSWORD=false. Expected either ALL THREE false (fresh) or ALL THREE true (already handed off).")
run_case "etl-role: adopt-by-rotation shape re-invokes --apply --rotate" 0 --only etl-role || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "adopting by rotation: prior credential unrecoverable" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [etl-role-adopt] did not print the adopting-by-rotation line" >&2; FAIL=1; }
  CALLN="$(grep -c "^db-role-handoff " "$CASE_LAST_DIR/calls.log" 2>/dev/null || echo 0)"
  if [[ "$CALLN" != "3" ]]; then
    echo "FAIL: [etl-role-adopt] expected exactly 3 db-role-handoff calls (preflight probe, apply-phase probe, the real --rotate call), got $CALLN" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
  grep -q "^db-role-handoff .*pfin_etl --apply --rotate" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [etl-role-adopt] no db-role-handoff call carried '--apply --rotate'" >&2; cat "$CASE_LAST_DIR/calls.log" >&2; FAIL=1; }
  if grep -qE "^db-role-handoff BOX_IP=\S+ pfin_etl --apply$" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [etl-role-adopt] a plain '--apply' (no --rotate) handoff was invoked -- the adopt path must never fall through to a plain handoff on this shape" >&2
    FAIL=1
  fi
fi

# 22. ETL-ROLE-NOT-ADOPTABLE-UNCHANGED -- the default (no adoptable-shape
#     stdout) -- proves the adopt wrapper does not engage on an ordinary
#     state (fresh, already-done, or any OTHER mismatch): falls straight
#     through to a plain call, never --rotate, same as scenario 7's own
#     "--only runs exactly one step" already exercises for the happy
#     path -- this scenario pins the NEGATIVE case explicitly (a
#     mismatch shape that is NOT the one adoptable shape must still
#     refuse as INCONSISTENT via the plain call, not be silently adopted).
CASE_ENV=(FAKE_RC_db_role_handoff=1 FAKE_STDOUT_db_role_handoff="FAIL  role 'pfin_etl' / 'pfin-back-etl' state is INCONSISTENT -- rolcanlogin=false has_password=false store_has_PFIN_DB_PASSWORD=true. Expected either ALL THREE false (fresh) or ALL THREE true (already handed off).")
run_case "etl-role: a different mismatch shape is never adopted" 2 --only etl-role || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if grep -q "adopting by rotation" "$CASE_LAST_DIR/out.txt" 2>/dev/null; then
    echo "FAIL: [etl-role-not-adoptable] the adopt-by-rotation path fired on a non-matching INCONSISTENT shape" >&2
    FAIL=1
  fi
  if grep -q -- "--rotate" "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [etl-role-not-adoptable] db-role-handoff.sh was invoked with --rotate on a non-adoptable shape" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi

# 23. PGRST-FLIP-PROBE-READ-FAILS-NOT-TREATED-AS-DONE -- coolify-env.sh's
#     own preflight read (the live-done probe) exits non-zero (box
#     unreachable, API error, whatever) -> live_done_pgrst_flip() must
#     report UNKNOWN, never silently "done" -- falls through to the real
#     call, which fails identically and for the same genuine reason
#     (never masked as a false VERIFIED).
CASE_ENV=(FAKE_RC_coolify_env=1)
run_case "pgrst-flip: a failed live-done probe is UNKNOWN, not done" 2 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "pgrst-flip live state is UNKNOWN, not blocking" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-probe-fails] did not print the UNKNOWN-state line" >&2; cat "$CASE_LAST_DIR/out.txt" >&2; FAIL=1; }
  grep -q "already = public,graphql_public,pfin" "$CASE_LAST_DIR/out.txt" 2>/dev/null && { echo "FAIL: [pgrst-flip-probe-fails] falsely reported VERIFIED-without-PATCH despite a failed probe read" >&2; FAIL=1; }
fi

# 24. PGRST-FLIP-STORE-MATCHES-CONTAINER-DOESNT (Sec C-1, PR #854 review)
#     -- the store's own preflight read matches the desired value, but
#     pgrst-schemas-live-check.sh (the RUNNING container's own reported
#     value) does not -> NOT done (a store-correct-but-not-yet-
#     redeployed box must never report VERIFIED) -> falls through to the
#     real --apply --deploy call once the apply phase runs.
CASE_ENV=(FAKE_STDOUT_coolify_env="      PGRST_DB_SCHEMAS=public,graphql_public,pfin" FAKE_RC_pgrst_schemas_live_check=1)
run_case "pgrst-flip: store matches but running container does not -- not done" 0 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "store's PGRST_DB_SCHEMAS matches, but the RUNNING rest container serves a different value" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-container-mismatch] did not print the store-vs-container mismatch line" >&2; cat "$CASE_LAST_DIR/out.txt" >&2; FAIL=1; }
  grep -q "^coolify-env .*--apply --deploy" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [pgrst-flip-container-mismatch] no coolify-env call carried --apply --deploy despite the container not yet matching" >&2; cat "$CASE_LAST_DIR/calls.log" >&2; FAIL=1; }
fi

# 25. PGRST-FLIP-CONTAINER-CHECK-UNREACHABLE (Sec C-1, PR #854 review) --
#     the store matches, but pgrst-schemas-live-check.sh itself cannot
#     even attempt the read (rc=2, e.g. box unreachable) -> UNKNOWN, never
#     silently treated as done -> falls through to the real call.
CASE_ENV=(FAKE_STDOUT_coolify_env="      PGRST_DB_SCHEMAS=public,graphql_public,pfin" FAKE_RC_pgrst_schemas_live_check=2)
run_case "pgrst-flip: container check unreachable -- UNKNOWN, not done" 0 --only pgrst-flip || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -q "pgrst-schemas-live-check.sh could not even attempt the container read" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [pgrst-flip-container-unreachable] did not print the UNKNOWN-state line for the container check" >&2; cat "$CASE_LAST_DIR/out.txt" >&2; FAIL=1; }
  grep -q "^coolify-env .*--apply --deploy" "$CASE_LAST_DIR/calls.log" 2>/dev/null || { echo "FAIL: [pgrst-flip-container-unreachable] no coolify-env call carried --apply --deploy despite the container check being unreachable" >&2; cat "$CASE_LAST_DIR/calls.log" >&2; FAIL=1; }
fi

# 26. DEPLOY-APP-USES-RESOLVED-VALUE-NOT-LITERAL-NAME (team-lead, run 4,
#     2026-09-21) -- default env (mint-jwt's fake preflight already
#     passes) -> `--only deploy-app` reaches deploy-app.sh; its
#     --require-network argv carries resolve-stack-network.sh's own
#     resolved stdout, never the literal env-var NAME, and
#     resolve-stack-network.sh's own call counter is exactly 1 for the
#     whole run (called from both the preflight and apply phases of
#     run_deploy_app(), memoized down to one real resolution).
run_case "deploy-app: --require-network carries the resolved value, not a literal name" 0 --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  DEPLOY_APP_LINE="$(grep '^deploy-app ' "$CASE_LAST_DIR/calls.log" 2>/dev/null | head -1)"
  if [[ -z "$DEPLOY_APP_LINE" ]]; then
    echo "FAIL: [deploy-app-resolved-value] deploy-app.sh was never called" >&2
    FAIL=1
  elif echo "$DEPLOY_APP_LINE" | grep -qE -- '--require-network (APP_STACK_NETWORK_NAME|ETL_STACK_NETWORK_NAME|PROVIDER_SYNC_STACK_NETWORK_NAME|PDF_RENDER_STACK_NETWORK_NAME)( |$)'; then
    echo "FAIL: [deploy-app-resolved-value] --require-network carried a literal env-var NAME token, not a resolved value:" >&2
    echo "$DEPLOY_APP_LINE" >&2
    FAIL=1
  elif ! echo "$DEPLOY_APP_LINE" | grep -qF -- '--require-network FAKE resolve-stack-network'; then
    echo "FAIL: [deploy-app-resolved-value] --require-network did not carry resolve-stack-network.sh's own fake output -- resolve_stack_network_value() may not be wired at all:" >&2
    echo "$DEPLOY_APP_LINE" >&2
    FAIL=1
  fi
  RESOLVE_COUNTER_FILE="$CASE_LAST_DIR/.fake-step-counter.resolve-stack-network"
  if [[ ! -f "$RESOLVE_COUNTER_FILE" ]]; then
    echo "FAIL: [deploy-app-resolved-value] resolve-stack-network.sh was never called at all" >&2
    FAIL=1
  elif [[ "$(cat "$RESOLVE_COUNTER_FILE")" != "1" ]]; then
    echo "FAIL: [deploy-app-resolved-value] resolve-stack-network.sh was called $(cat "$RESOLVE_COUNTER_FILE") times across preflight+apply, expected exactly 1 (memoization broken)" >&2
    FAIL=1
  fi
fi

# 27. DEPLOY-WORKERS-RESOLVE-MEMOIZED-ACROSS-ALL-THREE-WORKERS --
#     `--only deploy-workers`: all three deploy-app.sh fake calls carry
#     the SAME resolved value, never a literal *_STACK_NETWORK_NAME, and
#     resolve-stack-network.sh's own call counter is exactly 1 for the
#     whole run (3 workers x 2 phases, one memoized resolution).
run_case "deploy-workers: all three workers share one resolved --require-network value" 0 --only deploy-workers || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  WORKER_LINES="$(grep '^deploy-app ' "$CASE_LAST_DIR/calls.log" 2>/dev/null || true)"
  WORKER_LINE_COUNT="$(echo "$WORKER_LINES" | grep -c . || true)"
  if [[ "$WORKER_LINE_COUNT" -lt 3 ]]; then
    echo "FAIL: [deploy-workers-resolved-value] expected calls for all 3 workers, found $WORKER_LINE_COUNT:" >&2
    echo "$WORKER_LINES" >&2
    FAIL=1
  fi
  if echo "$WORKER_LINES" | grep -qE -- '--require-network (APP_STACK_NETWORK_NAME|ETL_STACK_NETWORK_NAME|PROVIDER_SYNC_STACK_NETWORK_NAME|PDF_RENDER_STACK_NETWORK_NAME)( |$)'; then
    echo "FAIL: [deploy-workers-resolved-value] at least one worker's --require-network carried a literal env-var NAME token:" >&2
    echo "$WORKER_LINES" >&2
    FAIL=1
  fi
  RESOLVE_COUNTER_FILE="$CASE_LAST_DIR/.fake-step-counter.resolve-stack-network"
  if [[ ! -f "$RESOLVE_COUNTER_FILE" ]]; then
    echo "FAIL: [deploy-workers-resolved-value] resolve-stack-network.sh was never called at all" >&2
    FAIL=1
  elif [[ "$(cat "$RESOLVE_COUNTER_FILE")" != "1" ]]; then
    echo "FAIL: [deploy-workers-resolved-value] resolve-stack-network.sh was called $(cat "$RESOLVE_COUNTER_FILE") times across 3 workers x 2 phases, expected exactly 1 (memoization broken)" >&2
    FAIL=1
  fi
fi

# 27b. DEPLOY-WORKERS-POST-DEPLOY-VERIFY-FAILS-STOPS-THE-STEP (team-lead's
#      run-6 stop, item 10) -- pfin_etl's own worker deploy succeeds, but
#      the post-deploy re-verify (a second db-role-handoff.sh call, no
#      --apply) reports an INCONSISTENT state instead of VERIFIED -- the
#      step must fail here, never proceed to provider-sync/pdf-render's
#      own deploys with a silently-broken etl credential.
CASE_ENV=(FAKE_RC_db_role_handoff=1 FAKE_STDOUT_db_role_handoff="FAIL  role 'pfin_etl' / 'pfin-back-etl' state is INCONSISTENT(store≠role) -- the store's current PFIN_DB_PASSWORD does NOT authenticate as 'pfin_etl' against the live database.")
run_case "deploy-workers: post-deploy store re-verify fails, step fails" 2 --only deploy-workers || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  # 3 preflight-phase deploy-app calls (all three workers, read-only) +
  # 1 apply-phase call (pfin-back-etl only) -- the apply phase must stop
  # there, never reaching provider-sync's or pdf-render's own apply.
  WORKER_LINES="$(grep -c '^deploy-app ' "$CASE_LAST_DIR/calls.log" 2>/dev/null || echo 0)"
  if [[ "$WORKER_LINES" -ne 4 ]]; then
    echo "FAIL: [deploy-workers-post-verify-fails] expected exactly 4 deploy-app calls (3 preflight + pfin-back-etl's own apply, before the failed re-verify stops the loop), found $WORKER_LINES" >&2
    FAIL=1
  fi
  APPLY_LINES="$(grep -c '^deploy-app .*--apply' "$CASE_LAST_DIR/calls.log" 2>/dev/null || echo 0)"
  if [[ "$APPLY_LINES" -ne 1 ]]; then
    echo "FAIL: [deploy-workers-post-verify-fails] expected exactly 1 apply-phase deploy-app call (pfin-back-etl only), found $APPLY_LINES -- provider-sync/pdf-render must never be reached after etl's re-verify fails" >&2
    FAIL=1
  fi
fi
CASE_ENV=()

# 27c. DEPLOY-WORKERS-CA1-CHECK-RUNS-ON-EVERY-WORKER (Sec's own
#      correction of req 4, run-10/step-16 review, 2026-09-21):
#      verify-worker-ca1-clear.sh is called for ALL THREE workers
#      unconditionally, each with the <name> --service <svc> shape --
#      NOT gated on worker_has_admission_guard(). Its own result is now
#      only an INFORMATIONAL log line: provider-sync's (seeded WITH the
#      override) says so; etl/pdf-render's (seeded WITHOUT) say so too,
#      but the check still runs for both regardless -- the exact
#      reversal of the old derive-and-skip design, which Sec's own
#      review found backwards for pdf-render specifically (a real HTTP
#      listener with no code-level refusal is MORE exposed, not less).
run_case "deploy-workers: CA-1 check runs for every worker; guard-derivation is informational only" 0 --only deploy-workers || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  CA1_LINES="$(grep '^verify-worker-ca1-clear ' "$CASE_LAST_DIR/calls.log" 2>/dev/null || true)"
  CA1_COUNT="$(echo "$CA1_LINES" | grep -c . || true)"
  if [[ "$CA1_COUNT" -ne 3 ]]; then
    echo "FAIL: [ca1-every-worker] expected exactly 3 verify-worker-ca1-clear calls (all workers), found $CA1_COUNT:" >&2
    echo "$CA1_LINES" >&2
    FAIL=1
  fi
  for pair in "pfin-back-etl --service pfin-back-etl-monthly-report" "pfin-provider-sync --service provider-sync" "pfin-pdf-render --service pdf-render"; do
    echo "$CA1_LINES" | grep -qE -- "${pair}( |$)" || { echo "FAIL: [ca1-every-worker] missing/malformed call for: $pair" >&2; echo "$CA1_LINES" >&2; FAIL=1; }
  done
  grep -qE 'pfin-back-etl: no admission-guard command override' "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [ca1-every-worker] pfin-back-etl's informational tag not logged." >&2; FAIL=1; }
  grep -qE 'pfin-pdf-render: no admission-guard command override' "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [ca1-every-worker] pfin-pdf-render's informational tag not logged." >&2; FAIL=1; }
  grep -qE 'pfin-provider-sync: admission-guard command override declared' "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [ca1-every-worker] pfin-provider-sync's informational tag not logged." >&2; FAIL=1; }
fi

# 27d. DEPLOY-WORKERS-ADMISSION-GUARD-MISSING-COMPOSE-FILE-DIES -- a
#      worker's docker-compose.yaml is absent entirely (not merely
#      lacking the override) -- worker_has_admission_guard() must hard
#      stop (die3, exit 3) rather than silently treating "file missing"
#      the same as "override absent", EVEN THOUGH the tag is now purely
#      informational -- a missing compose file where one is expected is
#      still a bigger problem than the tag it would have produced.
#      CASE_OMIT_PROVIDER_SYNC_COMPOSE=1 makes run_case itself leave the
#      file out from the start -- deterministic, no timing dependency.
CASE_OMIT_PROVIDER_SYNC_COMPOSE=1
run_case "deploy-workers: missing compose file hard-stops (die3), never silently skips" 3 --only deploy-workers || FAIL=1
CASE_OMIT_PROVIDER_SYNC_COMPOSE=0
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if ! grep -qF "cannot derive the admission-guard informational tag" "$CASE_LAST_DIR/out.txt"; then
    echo "FAIL: [admission-guard-missing-compose] die3 did not name the derivation failure." >&2
    FAIL=1
  fi
fi

# 27e. DEPLOY-WORKERS-RESUME-PATH-CLEAR-INVOKED-BEFORE-DEPLOY (team-
#      lead's own run-10 stop: a resume starting at/after deploy-
#      workers never revisits provision-resources' own fqdn/
#      ports_exposes clear) -- fqdn reported SET on the pre-deploy
#      read invokes provision-worker.sh's existing --apply clear BEFORE
#      that worker's own deploy-app.sh --apply call. Proven by call-log
#      ORDER (line number), not just call presence -- presence alone
#      would not catch a clear invoked too late to matter.
#
#      Sec's run-11-stop requirement 2 (reachability leg): the state-
#      read is now `provision-worker.sh <name> --state`, called TWICE
#      per worker by worker_fqdn_clear_if_needed() -- once pre-clear
#      (must read SET to trigger the clear) and once post-clear (must
#      read ABSENT/EMPTY for the run to proceed, run-11's own fail-open
#      bug). FAKE_STDOUT_LIST_provision_worker (not the single-value
#      FAKE_STDOUT_provision_worker -- a fixture that reports the SAME
#      state on every call could never distinguish "the clear worked"
#      from "the clear silently no-op'd", which is exactly the class of
#      fixture defect run 11's real regression exposed) gives call 1
#      (state, pre-clear) = SET, call 2 (the --apply clear itself,
#      value irrelevant) = nothing, call 3 (state, post-clear) =
#      ABSENT/EMPTY -- repeating per worker, 3 workers x 3 calls = 9.
# SENTINEL-FORMAT-PINNED (Sec run-11-stop requirement 1): SENTINEL_PREFIX/
# SENTINEL_MID are defined once, near the top of this file (see that
# definition's own header) -- checked here against the REAL (never the
# fixture) producer and consumer files, so a future edit to either side
# that silently drifts the format reddens this fence instead of passing
# on a fixture that no longer matches what ships. This is the fix for
# exactly the failure class that caused run 11: this fence's own
# scenarios asserted against a format string nobody had checked against
# the real script's actual output.
#
# ⚠ ANCHORED ON THE CODE, NOT THE BARE LITERAL -- self-caught by
# inversion-testing THIS check: `grep -qF "$SENTINEL_PREFIX" <file>` alone
# is VACUOUS, because this file's own USAGE-header comment quotes the
# same literal ("...the PREFLIGHT-mode \"current state: fqdn=...\"
# line...") -- changing ONLY the two real `info "current state: ..."`
# producer lines to a different format left that stale comment behind,
# and a bare `grep -qF` on the literal alone still matched IT, missing
# the actual drift entirely. Anchoring on `info "current state: fqdn=$`
# (the producer's own code shape, dollar sign immediately after `=`,
# never how prose refers to it) and on the exact `grep -E '...'`
# consumer pattern closes that hole.
PRODUCER_ANCHOR='info "current state: fqdn=$'
CONSUMER_ANCHOR="grep -E 'current state: fqdn=(ABSENT|EMPTY|SET).*ports_exposes=(ABSENT|EMPTY|SET)'"
grep -qF "$PRODUCER_ANCHOR" "$REPO_ROOT/scripts/provision-worker.sh" \
  || { echo "FAIL: [sentinel-format-pinned] scripts/provision-worker.sh no longer contains the producer code shape '$PRODUCER_ANCHOR...' this fence's fixtures assume -- producer drift, update both." >&2; FAIL=1; }
grep -qF "$CONSUMER_ANCHOR" "$REPO_ROOT/scripts/provision.sh" \
  || { echo "FAIL: [sentinel-format-pinned] scripts/provision.sh no longer contains the consumer grep pattern '$CONSUMER_ANCHOR' -- consumer/producer drift." >&2; FAIL=1; }

SET_STATE="${SENTINEL_PREFIX}SET ('https://default-assigned.sslip.io')${SENTINEL_MID}ABSENT"
CLEARED_STATE="${SENTINEL_PREFIX}ABSENT${SENTINEL_MID}ABSENT"
CASE_ENV=(FAKE_STDOUT_LIST_provision_worker="$SET_STATE||$CLEARED_STATE|$SET_STATE||$CLEARED_STATE|$SET_STATE||$CLEARED_STATE")
run_case "deploy-workers: fqdn SET at deploy time invokes the clear before deploying, confirmed by re-read" 0 --only deploy-workers || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  for pair in pfin-back-etl pfin-provider-sync pfin-pdf-render; do
    # `|| true` on EVERY stage of these pipelines -- a zero-match grep
    # exits 1, and under this file's own `set -o pipefail` an
    # unguarded pipeline assignment aborts the WHOLE fence silently
    # (no FAIL line, just a bare non-zero exit) instead of producing a
    # clean assertion failure. Caught this in my own first draft by
    # deliberately breaking the target and finding the fence died
    # instead of reddening -- same "the instrument can't observe a
    # miss" class this repo's other fences already learned from.
    CLEAR_LN="$(grep -nE "^provision-worker .*${pair} --apply" "$CASE_LAST_DIR/calls.log" 2>/dev/null | head -1 | cut -d: -f1 || true)"
    DEPLOY_LN="$(grep -nE "^deploy-app .*${pair} .*--apply" "$CASE_LAST_DIR/calls.log" 2>/dev/null | head -1 | cut -d: -f1 || true)"
    REREAD_LN="$(grep -nE "^provision-worker .*${pair} --state" "$CASE_LAST_DIR/calls.log" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
    if [[ -z "$CLEAR_LN" ]]; then
      echo "FAIL: [resume-clear-before-deploy] no provision-worker --apply (clear) call found for $pair despite fqdn=SET." >&2
      FAIL=1
    elif [[ -z "$DEPLOY_LN" ]]; then
      echo "FAIL: [resume-clear-before-deploy] no deploy-app --apply call found for $pair." >&2
      FAIL=1
    elif [[ "$CLEAR_LN" -ge "$DEPLOY_LN" ]]; then
      echo "FAIL: [resume-clear-before-deploy] $pair's clear-apply call (calls.log line $CLEAR_LN) did not precede its deploy-app --apply call (line $DEPLOY_LN)." >&2
      FAIL=1
    elif [[ -z "$REREAD_LN" || "$REREAD_LN" -le "$CLEAR_LN" ]]; then
      echo "FAIL: [resume-clear-before-deploy] $pair has no --state re-read call AFTER its clear-apply call (clear at line $CLEAR_LN, last --state at ${REREAD_LN:-<none>}) -- the post-clear confirmation leg never ran." >&2
      FAIL=1
    fi
  done
fi

# 27f. DEPLOY-WORKERS-RESUME-PATH-READ-FAILURE-PROPAGATES -- the
#      pre-deploy fqdn/ports_exposes state-read itself fails (box
#      issue, API issue) -> fail CLOSED (propagate), never silently
#      proceed to deploy against an unknown state.
CASE_ENV=(FAKE_RC_provision_worker=1)
run_case "deploy-workers: pre-deploy state-read failure propagates, never silently deploys" 2 --only deploy-workers || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qF "state-read FAILED" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [resume-clear-read-fails] refusal did not name the state-read failure." >&2; FAIL=1; }
  # Preflight-phase deploy-app calls (no --apply) are expected and fine
  # -- the assertion is that no APPLY-phase deploy-app call happens
  # after the state-read fails, not that deploy-app is never invoked
  # at all (it already was, harmlessly, during the preceding preflight
  # phase every `--only <step>` runs before its own apply phase).
  grep -qE '^deploy-app .*--apply' "$CASE_LAST_DIR/calls.log" 2>/dev/null && { echo "FAIL: [resume-clear-read-fails] an APPLY-phase deploy-app call happened despite the state-read failure -- must never deploy against an unknown state." >&2; FAIL=1; }
fi

# 27g. DEPLOY-WORKERS-RESUME-PATH-CLEAR-DOES-NOT-TAKE-REFUSES (Sec
#      run-11-stop requirement 4): the clear is invoked but the POST-
#      clear re-read still shows a SET field (e.g. Coolify's clear
#      silently no-op'd) -- must REFUSE to deploy, never proceed on the
#      strength of having merely CALLED the clear. Every provision-
#      worker --state call reports SET, forever (no CLEARED entry in
#      the list) -- etl (the first worker in the loop) invokes the
#      clear, re-reads, still SET, refuses before its own deploy-app
#      --apply call ever fires.
CASE_ENV=(FAKE_STDOUT_LIST_provision_worker="$SET_STATE")
run_case "deploy-workers: clear invoked but re-read still SET refuses, never deploys" 2 --only deploy-workers || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qF "invoked the clear but the RE-READ still shows a SET field" "$CASE_LAST_DIR/out.txt" \
    || { echo "FAIL: [resume-clear-does-not-take] refusal did not name the unconfirmed clear." >&2; FAIL=1; }
  grep -qE '^deploy-app .*pfin-back-etl .*--apply' "$CASE_LAST_DIR/calls.log" 2>/dev/null \
    && { echo "FAIL: [resume-clear-does-not-take] an APPLY-phase deploy-app call happened for pfin-back-etl despite the clear never being confirmed." >&2; FAIL=1; }
fi

# 28. RESOLVE-STACK-NETWORK-FAILURE-BLOCKS-DEPLOY-APP -- resolve-stack-
#     network.sh itself fails -> run_deploy_app() must propagate the
#     failure rather than falling through with an empty/stale value;
#     deploy-app.sh is never reached.
CASE_ENV=(FAKE_RC_resolve_stack_network=1)
run_case "deploy-app: resolve-stack-network.sh failure blocks the call, never falls through" 2 --only deploy-app || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if grep -q '^deploy-app ' "$CASE_LAST_DIR/calls.log" 2>/dev/null; then
    echo "FAIL: [resolve-failure-blocks-deploy-app] deploy-app.sh was called despite resolve-stack-network.sh failing" >&2
    cat "$CASE_LAST_DIR/calls.log" >&2
    FAIL=1
  fi
fi
CASE_ENV=()

# --- 29-32: run_cutover()'s real Hetzner check (BACKLOG.md item 90
# follow-up, F/CTO's live measurement that the incumbent was already
# torn down) -- isolated via --only cutover --confirm-cutover so each
# scenario tests exactly one Hetzner-response shape. -----------------

# 29. CUTOVER-ONE-SERVER-VERIFIED -- the ruled steady state: exactly one
#     server, named pfin-prod-1 -> VERIFIED, exit 0.
run_case "cutover: exactly one server (pfin-prod-1) verifies" 0 --only cutover --confirm-cutover || FAIL=1
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  grep -qF "cutover: the Hetzner project holds exactly one server (pfin-prod-1); the incumbent is gone" "$CASE_LAST_DIR/out.txt" || { echo "FAIL: [cutover one server] did not print the expected VERIFIED line -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2; FAIL=1; }
  [[ -s "$CASE_LAST_DIR/leak.log" ]] && { echo "FAIL: [cutover one server] the Hetzner token leaked into curl argv: $(cat "$CASE_LAST_DIR/leak.log")" >&2; FAIL=1; }
fi

# 29a. CUTOVER-ONE-SERVER-WRONG-NAME-REFUSES -- exactly one server, but
#     NOT named pfin-prod-1 -- never guesses this is fine just because
#     the count matches; refuses (FAILED, exit 2), names the actual name.
CASE_ENV=(FAKE_HETZNER_SERVERS_JSON='{"servers":[{"name":"some-other-box"}]}')
run_case "cutover: one server with the wrong name refuses" 2 --only cutover --confirm-cutover || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -qF "it is named 'some-other-box', not the ruled name 'pfin-prod-1'" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [cutover wrong name] did not name the actual vs ruled server name -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2
  FAIL=1
fi

# 30. CUTOVER-TWO-SERVERS-MANUAL -- more than one server -- MANUAL
#     (exit 1), naming BOTH servers, NEVER deletes anything (no curl
#     DELETE call is even possible -- this fixture's fake curl has no
#     delete branch at all, so an accidental delete attempt would fail
#     closed with "unrecognised invocation", not silently succeed).
CASE_ENV=(FAKE_HETZNER_SERVERS_JSON='{"servers":[{"name":"pfin-prod-1"},{"name":"leftover-incumbent-box"}]}')
run_case "cutover: two servers is MANUAL, naming both" 1 --only cutover --confirm-cutover || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]]; then
  if ! grep -qF "pfin-prod-1,leftover-incumbent-box" "$CASE_LAST_DIR/out.txt"; then
    echo "FAIL: [cutover two servers] did not name both servers -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2
    FAIL=1
  fi
  if ! grep -qF "NEVER deletes anything" "$CASE_LAST_DIR/out.txt"; then
    echo "FAIL: [cutover two servers] did not state the never-deletes discipline -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2
    FAIL=1
  fi
fi

# 31. CUTOVER-ZERO-SERVERS-FAILED -- an empty project (e.g. everything
#     torn down, including the replacement) -- FAILED (exit 2), never
#     silently treated as "incumbent gone, therefore fine".
CASE_ENV=(FAKE_HETZNER_SERVERS_JSON='{"servers":[]}')
run_case "cutover: zero servers refuses (FAILED)" 2 --only cutover --confirm-cutover || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -qF "ZERO servers" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [cutover zero servers] did not name the zero-servers refusal -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2
  FAIL=1
fi

# 32. CUTOVER-API-ERROR-FAILED -- the Hetzner API call itself fails
#     (network/auth/transport) -- FAILED (exit 2), never silently
#     treated as "no servers" or "verified".
CASE_ENV=(FAKE_HETZNER_API_FAILS=1)
run_case "cutover: Hetzner API call failure refuses (FAILED)" 2 --only cutover --confirm-cutover || FAIL=1
CASE_ENV=()
if [[ -n "${CASE_LAST_DIR:-}" ]] && ! grep -qF "Hetzner API call failed" "$CASE_LAST_DIR/out.txt"; then
  echo "FAIL: [cutover API error] did not name the API-call failure -- captured output: $(cat "$CASE_LAST_DIR/out.txt")" >&2
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more provision.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision.sh strike-proofs passed."
exit 0
