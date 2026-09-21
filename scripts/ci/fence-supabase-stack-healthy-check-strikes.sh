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
# `sshx` is a plain bash FUNCTION here (not a PATH-shadowed binary),
# `export -f`'d into a genuinely SEPARATE `bash` invocation of the
# extracted snippet -- never `source`d (fence-no-source-credential-
# files.sh, this repo's own box-side config-file read-mechanism fence,
# bans `source`/`.` of ANY file under scripts/**/*.sh, unconditionally,
# by design; an earlier draft of this fence used `source "$EXTRACT"` and
# was caught by that fence, correctly -- the mechanism ban is blunt on
# purpose and this fence does not get a carve-out). Matches each of the
# five probes' own distinctive text -- probe (2/5) on its remote block's
# own /auth/v1/health line, the other four on their embedded command text.
#
# Scenarios:
#   1. NO-VOLUME-DEPLOYS -- no db-data volume at all -> NEED_DEPLOY=1, no
#      die -- the ordinary first-deploy path, unaffected by this change.
#   2. HEALTHY-VOLUME-SKIPS-DEPLOY -- volume exists, all five probes pass
#      -> NEED_DEPLOY=0, no die -- "already provisioned and healthy,
#      nothing to deploy". The live defect this fixes.
#   3. UNHEALTHY-VOLUME-REFUSES (team-lead's own named strike) -- volume
#      exists, the init-marker probe (4/5) reports the four roles have NO
#      password set (the exact "bogus mount" signature) -> die, naming
#      "NOT confirmed healthy". The guard must still fire -- this branch
#      is not a loosening.
#   4. CONTAINERS-NOT-ALL-HEALTHY -- probe (1/5) alone fails (5/7) -> die,
#      isolated from the other four probes (all of which would pass).
#   5a-5d. GATEWAY-TWO-PART-PROBE (team-lead's 2026-09-21 live
#      measurement) -- probe (2/5) is now two calls (no-key expect 401,
#      anon-key expect 200); 5a = no-key wrongly 200 (key-auth not
#      enforced), 5b = with-key wrongly 401 (key doesn't authenticate),
#      5c = both calls 000 (connection failure), 5d = ANON_KEY
#      unreadable from the store. Scenario 2 covers the PASS case.
#   6. WRONG-PG-VERSION -- probe (3/5) alone fails -> die, isolated.
#   7. PARTIAL-INIT-STATE-ONE-ROLE (Sec C-1, PR #852 AMBER review) -- a
#      SINGLE matching role row -> die, naming "FAILED at (4/5)" and the
#      actual row count -- cardinality itself is part of the proof, not
#      just non-empty presence.
#   8. JWT-SECRET-UNSET (Sec F-2, PR #852 AMBER review) -- probe (5/5)
#      alone fails (app.settings.jwt_secret unset) -> die, isolated from
#      the other four probes (all of which would pass).
#   9-11. PROBE-5-FAIL-OPEN (Sec C-4, PR #852 AMBER review round 2) -- the
#      ORIGINAL probe 5 (refuse only on one literal error string) was
#      fail-open on every OTHER non-canonical answer -- empty output, a
#      different error string, and the GUC explicitly set to the empty
#      string all must refuse identically under the new positive-token
#      check, not just the one string scenario 8 alone would catch.
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

# Structural pin (Sec C-3, PR #852 AMBER review; corrected under Sec C-5
# round 2): the ORIGINAL pin (`grep -qE 'check_stack_already_healthy'`
# against the whole file) was vacuous -- the function's own DEFINITION
# always matches. The round-1 replacement (`grep -qzoE 'if \[\[
# \$CHECK_HEALTHY -eq 1 \]\]; then(.|\n)*?check_stack_already_healthy'`)
# was ALSO vacuous, for a different reason Sec caught and I did not:
# `(.|\n)*?` is not a lazy quantifier in POSIX/GNU ERE (ERE has no lazy
# quantifier at all) -- `X*?` parses as `(X*)?`, i.e. plain `X*`. The
# pattern actually read "the --check-healthy `if` line, then ANYTHING,
# then the token check_stack_already_healthy ANYWHERE LATER IN THE
# FILE" -- and the db-data-volume dispatcher further down always
# supplies that token, so deleting ONLY the call inside the
# --check-healthy block (leaving the `if` wrapper and the later
# dispatcher both intact) still passed. Fixed by extracting the
# --check-healthy dispatch block BY RANGE (its own `if`/`fi` anchors,
# bash's own extraction primitive, not a regex trying to bound a match)
# and requiring the call WITHIN that extracted text specifically -- the
# later dispatcher's own identical call can no longer satisfy it, and an
# empty extraction (the block itself removed, or its anchors reworded)
# fails closed on its own, independent of the call-presence check.
CHECK_BLOCK="$(sed -n '/^if \[\[ \$CHECK_HEALTHY -eq 1 \]\]; then$/,/^fi$/p' "$TARGET_SH")"
if [[ -z "$CHECK_BLOCK" ]]; then
  echo "FATAL: the --check-healthy dispatch block was not found by its own range anchors -- structural pin failed" >&2
  exit 2
fi
if ! printf '%s\n' "$CHECK_BLOCK" | grep -q 'check_stack_already_healthy'; then
  echo "FATAL: --check-healthy's own dispatch block no longer calls check_stack_already_healthy() -- structural pin failed" >&2
  exit 2
fi
if ! grep -q -- '--apply and --check-healthy are mutually exclusive' "$TARGET_SH"; then
  echo "FATAL: the --apply/--check-healthy mutual-exclusion message is gone or reworded -- structural pin failed" >&2
  exit 2
fi
if ! grep -q -- '--check-healthy) CHECK_HEALTHY=1' "$TARGET_SH"; then
  echo "FATAL: --check-healthy flag is no longer parsed -- structural pin failed" >&2
  exit 2
fi

# Sec C-3 (PR #853): the remote gateway-probe block's sentinel line and
# this fence's fake answer are TWO COPIES of one wire format. Strike-
# measured 2026-09-20: changing ONLY the remote printf (NOKEY= ->
# NOKEYSTATUS=) left this fence GREEN, while the real parser's three
# `grep -oE ... | cut` reads would all come back empty -> gw_nokey empty
# -> "expected 401, got <none>" -> refuse. That is precisely the
# false-negative this PR fixes, reintroduced under a green fence. One
# constant, pinned against the shipping script and used by the fake.
GW_SENTINEL_FMT='ANON_KEY_PRESENT=%s NOKEY=%s WITHKEY=%s'
export GW_SENTINEL_FMT
if ! grep -Fq -- "printf '$GW_SENTINEL_FMT" "$TARGET_SH"; then
  echo "FATAL: the remote gateway-probe sentinel format in $TARGET_SH no longer matches this fence's fake ('$GW_SENTINEL_FMT') -- the fake would answer in a format the real parser cannot read, and this fence would stay green. Failing closed." >&2
  exit 2
fi

# Sec C-4 (PR #853): this fence's fake DRAINS the remote gateway-probe
# heredoc and answers from FAKE_GW_* -- correct as a fake, but it means
# NOTHING here can observe that block's internals. Three of its
# properties are security- or correctness-load-bearing and were each
# strike-measured GREEN when removed (2026-09-20), so they get
# structural pins instead:
#   (a) the with-key call actually supplies the anon key -- without it
#       the "with-key half" asserts nothing at all;
#   (b) the key itself never crosses the ssh channel back -- only the
#       ANON_KEY_PRESENT boolean and the two status codes may;
#   (c) BOTH gateway curls read stdin from /dev/null -- a curl without
#       it consumes the remaining bytes of the outer heredoc, silently
#       skipping every line after it (the exact 2026-09-11 defect (2a)
#       in mint-supabase-jwt-keys.sh's own --verify-live header).
if ! grep -Fq -- '-H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"' "$EXTRACT"; then
  echo "FATAL: the gateway with-key probe no longer supplies the anon apikey -- the (2/5) with-key half would assert nothing. Failing closed." >&2
  exit 2
fi
if grep -nE '^[[:space:]]*(echo|printf)[^#]*\$ANON_KEY' "$EXTRACT" | grep -vqF 'ANON_KEY_PRESENT=%s'; then
  echo "FATAL: the remote gateway-probe block appears to echo the anon key itself -- ANON_KEY must never cross the ssh channel back; only the ANON_KEY_PRESENT boolean and the two HTTP status codes may. Failing closed." >&2
  exit 2
fi
GW_CURL_STDIN="$(grep -c 'http://api-gw:8000/auth/v1/health </dev/null' "$EXTRACT" || true)"
if [[ "$GW_CURL_STDIN" != "2" ]]; then
  echo "FATAL: expected exactly 2 gateway curls reading stdin from /dev/null in the remote probe block, found $GW_CURL_STDIN -- a curl without </dev/null eats the outer heredoc. Failing closed." >&2
  exit 2
fi

FAIL=0

# run_case <desc> <expect_rc> <expect_need_deploy-or-empty> <containers> <gw_status> <pgver> <init_state> <volume_exists> [jwt_setting]
#
# [jwt_setting] (Sec F-2, PR #852 AMBER review) defaults to a healthy,
# non-error value when omitted, so scenarios 1-7 (none of which need probe
# (5/5) to fail) are unaffected by its addition -- only scenario 8 passes
# it explicitly.
#
# ⚠ The fake `sshx()` below reads FAKE_-prefixed variable names, never
# bare names like `containers`/`gw_status`/`pgver`/`init_state` --
# check_stack_already_healthy() (the real, extracted function) declares
# its OWN `local containers`/`gw_status`/`pgver`/`init_state` internally.
# An earlier draft of this fence used `source "$EXTRACT"` (since replaced
# -- see the header) and those bare names collided: bash resolves an
# unset-local name by walking the ACTIVE CALL STACK, not lexical/
# definition-time scope, so the sourced function's own local shadowed
# this harness's variable of the same name -- caught by a strike against
# this fence ITSELF (every scenario read 0 containers regardless of what
# was configured). The FAKE_ prefix makes the collision impossible by
# construction (no shared name to shadow), independent of which
# execution mechanism is used -- kept even after switching away from
# `source` since it costs nothing and remains the more robust habit.
# Fakes below are plain top-level functions, `export -f`'d so a genuinely
# SEPARATE `bash "$combined"` process (never `source`d -- see the header)
# inherits them. Each redefinition per run_case call is intentional and
# harmless (the LATEST FAKE_* values, exported as plain env vars just
# before the child process starts, are what that invocation's `sshx()`
# reads -- there is no cross-call state to worry about).
ok()   { printf '  ok  %s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
die()  { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
step() { printf '\n=== %s ===\n' "$*"; }
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
    *"bash -s"*)
      # team-lead's live measurement, 2026-09-21: probe (2/5) is now a
      # two-part TINKER-KEY-READ-then-TWO-CURLS remote script (same
      # heredoc + `env APP_UUID=... bash -s` shape this file's own
      # NEED_MINT/`db-role-handoff.sh` idiom uses elsewhere -- see this
      # fake's own header note on why a genuinely separate `bash
      # "$combined"` process, never `source`, matters here too). The
      # heredoc BODY arrives on this function's own stdin (bash's normal
      # behavior for a function called with a `<<` redirect) -- drained,
      # not parsed: this fake's answer is entirely FAKE_GW_*-driven, the
      # same "canned answer, not a reimplementation" contract every other
      # arm here already follows.
      #
      # Sec C-5 (PR #853): the drained body is also the ONLY thing that
      # distinguishes this remote block from any other `env ... bash -s`
      # call. The OLD pattern matched probe (2/5)'s own distinctive
      # `exec -T supavisor curl` text; `bash -s` alone does not, and this
      # file already has a SECOND `env ... bash -s` call (~line 807),
      # outside the extracted range today but one marker move from
      # silently landing here instead of on the fail-closed `*)` arm.
      local body; body="$(cat)"
      case "$body" in
        *"http://api-gw:8000/auth/v1/health"*) ;;
        *) echo "FAKE sshx: a 'bash -s' remote block reached this fence's gateway arm but does not probe /auth/v1/health -- refusing to hand it a canned gateway answer: $cmd" >&2; return 1 ;;
      esac
      local anon_present=1
      [[ "${FAKE_GW_ANON_PRESENT:-1}" == "0" ]] && anon_present=0
      # Sec C-3 (PR #853): GW_SENTINEL_FMT is exported above and pinned
      # against the shipping script -- the fake's answer and the real
      # parser's read must be two copies of the SAME wire format, or a
      # drift here (or there) makes this fence green while the real
      # parser reads empty fields and refuses a healthy stack.
      # GW_SENTINEL_FMT is the pinned format, deliberately passed as printf's format arg.
      # shellcheck disable=SC2059
      printf "$GW_SENTINEL_FMT\n" "$anon_present" "${FAKE_GW_NOKEY:-401}" "${FAKE_GW_WITHKEY:-200}"
      ;;
    *"show server_version;"*)
      printf '%s' "$FAKE_PGVER"
      ;;
    *"pg_authid"*)
      printf '%s\n' "$FAKE_INIT_STATE"
      ;;
    *"app.settings.jwt_secret"*)
      # Sec C-4 (PR #852 AMBER review round 2): the real script's probe
      # (5/5) is now `select current_setting('app.settings.jwt_secret',
      # true) <> '';` -- a positive boolean token ('t'/'f'), never the
      # secret's own value or an error-string match. Default (see
      # run_case) is 't' (healthy); scenarios 8/9/10/11 override it to
      # exercise every non-canonical answer, not just the one string the
      # OLD version's fake modeled.
      printf '%s' "$FAKE_JWT_SETTING"
      ;;
    *)
      echo "FAKE sshx: unrecognised command in this fence's own harness: $cmd" >&2
      return 1
      ;;
  esac
}
export -f ok info die step sshx

run_case() {
  # $5 is FAKE_GW_NOKEY (team-lead's 2026-09-21 fix: probe 2 is now
  # two-part; $5 keeps its historical slot but now means the NO-KEY
  # call's expected status, default healthy value flipped 200 -> 401).
  # $10/$11 (new): FAKE_GW_WITHKEY (default 200), FAKE_GW_ANON_PRESENT
  # (default 1) -- both no-colon defaults (see the $9/jwt_setting comment
  # above for why: an explicit empty-string override must survive, not
  # get silently defaulted back).
  local desc="$1" expect_rc="$2" expect_need_deploy="$3" FAKE_CONTAINERS="$4" FAKE_GW_NOKEY="$5" FAKE_PGVER="$6" FAKE_INIT_STATE="$7" FAKE_VOLUME_EXISTS="$8"
  # `${9-t}`, no colon -- scenario 9 (probe5-empty-output) passes an
  # EXPLICIT empty string as the 9th positional arg to model psql dying /
  # the container being gone, which must be distinguished from the arg
  # being OMITTED entirely (every scenario 1-7 call, which should default
  # to the healthy 't'). `${9:-t}` (with the colon) treats "set but
  # empty" the SAME as "unset" and would have silently defaulted
  # scenario 9's empty string back to 't' -- caught by this fence's own
  # strike (scenario 9 first went green when it should have gone red,
  # with the captured output showing "present: 't'" instead of
  # "present: '<none>'").
  local FAKE_JWT_SETTING="${9-t}"
  local FAKE_GW_WITHKEY="${10-200}" FAKE_GW_ANON_PRESENT="${11-1}"
  local out="$WORK/out.$$.$RANDOM"
  local combined="$WORK/combined.$$.$RANDOM.sh"
  # The extracted block is APPENDED to, never sourced from -- this file is
  # executed directly as `bash "$combined"`, a genuinely separate process,
  # with a driver line of THIS fence's own appended after it so
  # NEED_DEPLOY (set inside the extracted code) is still visible to print
  # from the SAME process before it exits. Sec F-4 (PR #852 AMBER review):
  # `set -euo pipefail` is prepended so $combined runs under the SAME
  # shell options as the real script (whose own top-of-file `set -euo
  # pipefail` this extraction otherwise loses) -- an earlier draft ran
  # extracted code more permissively than production ever does.
  { printf 'set -euo pipefail\n'; cat "$EXTRACT"; printf 'echo "RESULT_NEED_DEPLOY=$NEED_DEPLOY"\n'; } > "$combined"
  set +e
  APP_UUID="test-stack-uuid-1234" \
    FAKE_CONTAINERS="$FAKE_CONTAINERS" FAKE_GW_NOKEY="$FAKE_GW_NOKEY" FAKE_PGVER="$FAKE_PGVER" \
    FAKE_INIT_STATE="$FAKE_INIT_STATE" FAKE_VOLUME_EXISTS="$FAKE_VOLUME_EXISTS" \
    FAKE_JWT_SETTING="$FAKE_JWT_SETTING" \
    FAKE_GW_WITHKEY="$FAKE_GW_WITHKEY" FAKE_GW_ANON_PRESENT="$FAKE_GW_ANON_PRESENT" \
    bash "$combined" > "$out" 2>&1
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
OUT1="$(run_case "no-volume-deploys" 0 1 7 401 17 "$HEALTHY_ROLES" 0)" || FAIL=1
if [[ -n "${OUT1:-}" ]]; then
  echo "$OUT1" | grep -q "no pre-existing db-data volume -- safe to deploy" || { echo "FAIL: [no-volume-deploys] did not print the safe-to-deploy line" >&2; FAIL=1; }
fi

# 2. HEALTHY-VOLUME-SKIPS-DEPLOY -- the live defect this fixes
OUT2="$(run_case "healthy-volume-skips-deploy" 0 0 7 401 17 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT2:-}" ]]; then
  echo "$OUT2" | grep -q "stack already provisioned and healthy -- nothing to deploy" || { echo "FAIL: [healthy-volume-skips-deploy] did not print the already-healthy line" >&2; FAIL=1; }
fi

# 3. UNHEALTHY-VOLUME-REFUSES (team-lead's own named strike) -- the four
#    role-password markers absent, the exact "bogus mount" signature.
OUT3="$(run_case "unhealthy-volume-refuses" 1 "" 7 401 17 "$UNHEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT3:-}" ]]; then
  echo "$OUT3" | grep -q "NOT confirmed healthy" || { echo "FAIL: [unhealthy-volume-refuses] die() message did not name 'NOT confirmed healthy'" >&2; FAIL=1; }
  echo "$OUT3" | grep -q "FAILED at (4/5)" || { echo "FAIL: [unhealthy-volume-refuses] did not isolate the failure to probe (4/5)" >&2; FAIL=1; }
fi

# 4. CONTAINERS-NOT-ALL-HEALTHY -- probe (1/5) alone fails.
OUT4="$(run_case "containers-not-all-healthy" 1 "" 5 401 17 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT4:-}" ]]; then
  echo "$OUT4" | grep -q "FAILED at (1/5)" || { echo "FAIL: [containers-not-all-healthy] did not isolate the failure to probe (1/5)" >&2; FAIL=1; }
fi

# 5a/5b/5c. GATEWAY-TWO-PART-PROBE (team-lead's own 2026-09-21 live
#    measurement -- see provision-supabase-stack.sh's own comment) --
#    probe (2/5) is now two calls, and either call answering the WRONG
#    status must refuse, isolated from the other four probes. Scenario 2
#    (healthy-volume-skips-deploy) already covers the PASS case
#    (401, 200); these three cover the three ways it can fail:
#      5a. no-key answers 200 instead of 401 -- key-auth is NOT enforced
#          on this route (the exact live-box measurement's inverse).
#      5b. no-key correctly 401, but the anon apikey ALSO answers 401 --
#          the key itself does not authenticate.
#      5c. both calls answer 000 -- a connection failure (curl's own
#          %{http_code} for "never connected"), not a key-auth question
#          at all, but must refuse identically to the other two.
OUT5A="$(run_case "gateway-nokey-not-401" 1 "" 7 200 17 "$HEALTHY_ROLES" 1 "t" 200 1)" || FAIL=1
if [[ -n "${OUT5A:-}" ]]; then
  echo "$OUT5A" | grep -q "FAILED at (2/5, no-key half)" || { echo "FAIL: [gateway-nokey-not-401] did not isolate the failure to probe (2/5, no-key half)" >&2; FAIL=1; }
  # Sec F-1 (PR #853): a 200-without-a-key answer is a SECURITY finding
  # (key-auth not enforced), not a health blip -- the message must say so
  # explicitly, or the attractive repair is to relax the 401 expectation,
  # which re-opens an unauthenticated gateway.
  echo "$OUT5A" | grep -q "key-auth is not being enforced" || { echo "FAIL: [gateway-nokey-not-401] did not name the unkeyed 200 as a security finding" >&2; FAIL=1; }
fi
OUT5B="$(run_case "gateway-withkey-not-200" 1 "" 7 401 17 "$HEALTHY_ROLES" 1 "t" 401 1)" || FAIL=1
if [[ -n "${OUT5B:-}" ]]; then
  echo "$OUT5B" | grep -q "FAILED at (2/5, with-key half)" || { echo "FAIL: [gateway-withkey-not-200] did not isolate the failure to probe (2/5, with-key half)" >&2; FAIL=1; }
fi
OUT5C="$(run_case "gateway-connection-failure" 1 "" 7 000 17 "$HEALTHY_ROLES" 1 "t" 000 1)" || FAIL=1
if [[ -n "${OUT5C:-}" ]]; then
  echo "$OUT5C" | grep -q "FAILED at (2/5, no-key half)" || { echo "FAIL: [gateway-connection-failure] did not refuse on the (2/5) probe" >&2; FAIL=1; }
fi
# 5d. GATEWAY-ANON-KEY-UNREADABLE -- no-key correctly 401, but ANON_KEY
#     could not be read back from the Coolify store at all (tinker
#     crashed, or the store genuinely has no ANON_KEY row) -- refuses,
#     naming the with-key half specifically, distinct from 5b's "wrong
#     status" refusal.
OUT5D="$(run_case "gateway-anon-key-unreadable" 1 "" 7 401 17 "$HEALTHY_ROLES" 1 "t" 200 0)" || FAIL=1
if [[ -n "${OUT5D:-}" ]]; then
  echo "$OUT5D" | grep -q "FAILED at (2/5, with-key half): could not read ANON_KEY" || { echo "FAIL: [gateway-anon-key-unreadable] did not isolate the failure to the missing ANON_KEY" >&2; FAIL=1; }
fi

# 6. WRONG-PG-VERSION -- probe (3/5) alone fails.
OUT6="$(run_case "wrong-pg-version" 1 "" 7 401 15 "$HEALTHY_ROLES" 1)" || FAIL=1
if [[ -n "${OUT6:-}" ]]; then
  echo "$OUT6" | grep -q "FAILED at (3/5)" || { echo "FAIL: [wrong-pg-version] did not isolate the failure to probe (3/5)" >&2; FAIL=1; }
fi

# 7. PARTIAL-INIT-STATE-ONE-ROLE (Sec C-1, PR #852 AMBER review) -- the
#    OLD guard only checked "is init_state non-empty" -- a SINGLE
#    matching role row passed silently (Sec struck it: a partial or
#    foreign-volume init that only happens to define 'authenticator'
#    would read as healthy). Now the row COUNT itself is part of the
#    proof: exactly one role line present -> refuses, naming "FAILED at
#    (4/5)" and the actual count (1, not the expected 4).
OUT7="$(run_case "partial-init-state-one-role" 1 "" 7 401 17 "authenticator:true" 1)" || FAIL=1
if [[ -n "${OUT7:-}" ]]; then
  echo "$OUT7" | grep -q "FAILED at (4/5)" || { echo "FAIL: [partial-init-state-one-role] did not isolate the failure to probe (4/5)" >&2; FAIL=1; }
  echo "$OUT7" | grep -q "expected 4 role rows, got 1" || { echo "FAIL: [partial-init-state-one-role] did not name the actual row count" >&2; FAIL=1; }
fi

# 8. JWT-SECRET-UNSET (Sec F-2, PR #852 AMBER review; updated under Sec
#    C-4 round 2) -- probe (5/5) alone fails: all four role passwords
#    set, but current_setting('app.settings.jwt_secret', true) returns
#    NULL for a genuinely unset GUC -> the fake's positive-token check
#    ('t'/anything-else) refuses, isolated from the other four probes
#    (all of which would pass).
OUT8="$(run_case "jwt-secret-unset" 1 "" 7 401 17 "$HEALTHY_ROLES" 1 "f")" || FAIL=1
if [[ -n "${OUT8:-}" ]]; then
  echo "$OUT8" | grep -q "FAILED at (5/5)" || { echo "FAIL: [jwt-secret-unset] did not isolate the failure to probe (5/5)" >&2; FAIL=1; }
  echo "$OUT8" | grep -q "app.settings.jwt_secret is unset" || { echo "FAIL: [jwt-secret-unset] did not name jwt_secret as the cause" >&2; FAIL=1; }
fi

# 9/10/11. PROBE-5-FAIL-OPEN (Sec C-4, PR #852 AMBER review round 2) -- an
#    unset GUC is not the only way probe 5 can be unsatisfiable. The
#    ORIGINAL version here (refuse only on the literal "unrecognized
#    configuration parameter" error string) was fail-open on every OTHER
#    non-canonical answer -- struck three ways by Sec, all green when
#    they should have been red: empty output (psql died / container
#    gone), a DIFFERENT error string (db unreachable), and the GUC
#    explicitly set to the empty string. The new positive-token check
#    ('t'/anything-else) must refuse identically on all three.
OUT9="$(run_case  "probe5-empty-output"      1 "" 7 401 17 "$HEALTHY_ROLES" 1 "")" || FAIL=1
OUT10="$(run_case "probe5-psql-error"        1 "" 7 401 17 "$HEALTHY_ROLES" 1 "psql: error: connection to server on socket failed")" || FAIL=1
OUT11="$(run_case "probe5-guc-empty-string"  1 "" 7 401 17 "$HEALTHY_ROLES" 1 "f")" || FAIL=1
for O in "${OUT9:-}" "${OUT10:-}" "${OUT11:-}"; do
  [[ -n "$O" ]] && { echo "$O" | grep -q "FAILED at (5/5)" || { echo "FAIL: [probe5-fail-open] a non-canonical probe-5 answer did not refuse at (5/5)" >&2; FAIL=1; }; }
done

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more check_stack_already_healthy()/db-data-volume-dispatcher strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all provision-supabase-stack.sh healthy-check strike-proofs passed."
exit 0
