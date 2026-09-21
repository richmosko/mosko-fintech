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
#   2f. ALREADY-HANDED-OFF-BIND-CHECK-STORE-EMPTY (team-lead, run-4, Item
#       4, 2026-09-21 -- remedies Sec's PR #852 F-1 existence-only finding)
#       -- the count-only preflight says the store carries a
#       PFIN_DB_PASSWORD row, but the bind-check's OWN dedicated value read
#       resolves to empty (a store/count inconsistency) -> refuses,
#       "INCONSISTENT(store", never a false VERIFIED.
#   2g. ALREADY-HANDED-OFF-BIND-CHECK-CONNECT-FAILS -- the store carries a
#       value, but connecting AS the role with it fails (the exact
#       half-completed-rotation residual F-1 named) -> refuses,
#       "INCONSISTENT(store", never the old existence-only VERIFIED.
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
#       would hit. Refuses -- exit 1, not the historical (pre-fix) exit 0.
#       **Ordering corrected (Sec C-1, PR #856 round 1):** leg C now
#       scrubs cleartext BEFORE checking for the missing prompt (F-2b's
#       actual requirement) -- since this fake's own trust-path output
#       realistically leaks the credential in the syntax-error echo (a
#       real Postgres error includes the offending token), the cleartext
#       scrub now fires FIRST on this exact shape. Asserts "cleartext
#       value appeared", not "no password prompt was observed" (the OLD
#       assertion this ordering change makes false).
#  13b. TRUST-PATH-NO-PROMPT-CLEAN (Sec C-1 follow-up) -- the SAME
#       trust-path bypass, but with a non-leaking syntax-error message,
#       isolating the missing-prompt guard from the cleartext scrub so it
#       still has its own independent strike.
#  13c. WRONG-CURRENT-USER-FRESH-HANDOFF (Sec C-1, PR #856 round 1) --
#       leg C's connect succeeds cleanly (prompt, no leak, exit 0) but
#       `current_user` echoes back a DIFFERENT role -> refuses. Proves the
#       exact-row match (this round's fix for the vacuous bare-substring
#       defect) is load-bearing on its own.
#  13d. WRONG-CURRENT-USER-BIND-CHECK (Sec C-1, PR #856 round 1) -- same
#       strike against the already-handed-off bind-check's own connect
#       (Item 4).
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

# Sec VETO-1 (PR #854 review) -- the per-site structural pin that used to
# live here (leg-B catalog verify) is now superseded by
# scripts/ci/fence-heredoc-stdin-drain.sh, a tree-wide structural fence
# over every scripts/*.sh (team-lead's own follow-up ruling: the pin must
# be tree-wide, not scoped to individual files) -- never two divergent
# implementations of the same source-literal check living in different
# fences. Run that fence, not a copy of it here.

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
  # team-lead follow-up, run-4 (Item 4, 2026-09-21): the NEW already-
  # handed-off bind-check's own leg-A read (`->first()`, echoing the
  # actual VALUE) is distinguished from the OLDER count-only preflight
  # read (`->count()`) by the presence of "->first()" in the tinker script
  # body -- checked BEFORE the count branch below, since both share the
  # "no hash(" property and would otherwise collide on the same branch.
  if [[ "$ARGS" == *"->first()"* && "$ARGS" != *"hash("* ]]; then
    # FAKE_BIND_CHECK_PW unset/empty models "store resolved to no value on
    # this specific read" (scenario 2f); a real-looking default keeps every
    # OTHER scenario's already-handed-off bind-check passing without
    # having to thread this var through explicitly.
    echo "${FAKE_BIND_CHECK_PW-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    exit 0
  fi
  # team-lead follow-up (live --dry-run, provision.sh sweep, 2026-09-20):
  # the OLDER preflight store-count check (a bare `->count()`, no hash
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
    #
    # team-lead's run-6 stop, item 1/4 -- the real script's preflight query
    # now returns "count|nonEmpty" (a compose-parse placeholder row reads
    # count=1, nonEmpty=0), so this fake matches that shape.
    # FAKE_STORE_NONEMPTY defaults to 1 (non-empty) so every EXISTING
    # scenario that only ever set FAKE_STORE_COUNT keeps its prior
    # true/false meaning unchanged; the new placeholder-row scenarios set
    # FAKE_STORE_NONEMPTY=0 explicitly alongside FAKE_STORE_COUNT=1.
    echo "${FAKE_STORE_COUNT-0}|${FAKE_STORE_NONEMPTY-1}"
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
  if [[ "${FAKE_READBACK_EMPTY:-0}" == "1" ]]; then
    # team-lead's run-6 stop, item 8 -- the row exists (count=1) but its
    # value is empty.
    echo "1|EMPTY|$USER_VAL"
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
  # Connect-as-the-role step. team-lead's own live measurement, run-5
  # (realrun5.clean.log), 2026-09-21, MEASURED on the production target:
  # psql 17.6 over -h db, non-tty, inside `docker compose exec -T`, prints
  # NO password-prompt text at all without `-W` -- it silently consumes
  # the piped first stdin line as the password and attempts auth with it.
  # `-W` forces a `Password: ` prompt regardless of tty/pipe state. This
  # fixture now models a REAL auth check (compare the piped line against
  # the known-correct value) rather than the old flag-only shape, because
  # the real script now runs a POSITIVE CONTROL (a deliberately WRONG
  # password) before the real connect, and a fixture that always
  # "succeeds" regardless of the piped password could never distinguish
  # the two calls or prove the control is load-bearing.
  SCRIPT_IN="$(cat)"
  FIRST_LINE="$(printf '%s\n' "$SCRIPT_IN" | head -1)"
  HAS_W=0
  [[ "$ARGS" == *"-W"* ]] && HAS_W=1
  if [[ -n "${FAKE_CONNECT_CALL_LOG:-}" ]]; then
    printf '%s\n' "$ARGS" >> "$FAKE_CONNECT_CALL_LOG"
  fi
  PROMPT_LINE=""
  [[ "$HAS_W" -eq 1 ]] && PROMPT_LINE="Password: "
  # The real credential comes from ONE of two sources depending on which
  # site called this: the fresh-handoff leg C generates $PW locally and
  # delivers it via SEED_FILE (readable here -- the leg-E readback hash
  # check already reads it the same way); the already-handed-off
  # bind-check reads it box-side via tinker, modeled by FAKE_BIND_CHECK_PW.
  if [[ -n "${SEED_FILE:-}" && -f "$SEED_FILE" ]]; then
    REAL_PW="$(cat "$SEED_FILE")"
  else
    REAL_PW="${FAKE_BIND_CHECK_PW:-}"
  fi

  # team-lead's run-6 stop, item 7 (fixture-fidelity, optional) -- this
  # bypass now applies to ANY connect attempt (control OR real), checked
  # BEFORE the password comparison below, since a systemic -W breakage
  # (the hazard this models) would affect every -h db call this process
  # makes, not just the one using the real credential. Previously gated
  # inside "REAL_PW matched" only, leaving the control probe on normal
  # processing in a "trust-path" scenario -- a state a real breakage
  # could never actually produce.
  if [[ "${FAKE_NO_PASSWORD_PROMPT:-0}" == "1" ]]; then
    # Sec VETO V-1 (PR #846 review) -- trust-path bypass: NO prompt text
    # at all EVEN WITH -W (the actual hazard: something suppresses the
    # prompt regardless), the cleartext first-stdin-line consumed as a
    # bogus SQL statement instead. Realistically leaks whatever was piped
    # into the syntax-error echo -- with scrub-before-prompt-check
    # ordering, the cleartext scrub now correctly fires FIRST on this
    # exact shape for the REAL connect (a STRONGER outcome); for the
    # CONTROL probe, its own exact-string auth-failure check never finds
    # it either, so both probes refuse. FAKE_NO_PASSWORD_PROMPT_CLEAN
    # below isolates the missing-prompt guard with a non-leaking variant.
    echo "psql:<stdin>:1: ERROR:  syntax error at or near \"$FIRST_LINE\""
    echo "LINE 1: $FIRST_LINE"
    echo " current_user "
    echo "--------------"
    echo " ${FAKE_ROLE_NAME:-pfin_etl}"
    exit 0
  fi
  if [[ "${FAKE_NO_PASSWORD_PROMPT_CLEAN:-0}" == "1" ]]; then
    echo "psql:<stdin>:1: ERROR:  syntax error at or near a piped credential (redacted by this fake, not by db-role-handoff.sh)"
    echo " current_user "
    echo "--------------"
    echo " ${FAKE_ROLE_NAME:-pfin_etl}"
    exit 0
  fi

  if [[ -n "$REAL_PW" && "$FIRST_LINE" == "$REAL_PW" ]]; then
    # The REAL credential was piped -- this is the real connect attempt
    # (whether or not a control call happened first).
    if [[ "${FAKE_WRONG_CURRENT_USER:-0}" == "1" ]]; then
      # Sec C-1 (PR #856 round 1) -- everything else about this connection
      # is normal (prompt prints, no cleartext leak, exit 0), but the row
      # psql prints back for `select current_user;` names a DIFFERENT
      # role. Proves the exact-row current_user match fires on its own.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo " current_user "
      echo "--------------"
      echo " postgres"
      exit 0
    fi
    if [[ "${FAKE_ECHO_PW_IN_CONNECT:-0}" == "1" ]]; then
      # Sec F-6 (PR #846 review) -- the prompt DOES print, but the
      # credential ALSO leaks into the output elsewhere.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "DEBUG (simulated transport bug): last line was $FIRST_LINE"
      echo " current_user "
      echo "--------------"
      echo " ${FAKE_ROLE_NAME:-pfin_etl}"
      exit 0
    fi
    if [[ "${FAKE_CONNECT_FAIL:-0}" == "1" ]]; then
      # A genuine password-authenticated connection failing for an
      # UNRELATED reason (DB unreachable after the prompt, etc).
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: connection failed" >&2
      exit 2
    fi
    [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
    echo " current_user "
    echo "--------------"
    echo " ${FAKE_ROLE_NAME:-pfin_etl}"
    exit 0
  else
    # Wrong/unknown password (the trust-path CONTROL's own deliberately-
    # wrong value, or REAL_PW unset). Real psql behavior: auth failure,
    # unless a dedicated override models the actual hazards the control
    # exists to catch.
    if [[ "${FAKE_ECHO_PW_IN_CONTROL:-0}" == "1" ]]; then
      # Sec F-1 (PR #858 review) -- the CONTROL's own scrub had no
      # scenario in this file either: striking it left the whole suite
      # green. Models a hypothetical transport/debug-print bug that
      # leaks the REAL credential into the control probe's own output
      # even though the control never sent it.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "DEBUG (simulated transport bug): real value was $REAL_PW"
      echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"${FAKE_ROLE_NAME:-pfin_etl}\"" >&2
      exit 2
    fi
    if [[ "${FAKE_CONTROL_SUCCEEDS:-0}" == "1" ]]; then
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo " current_user "
      echo "--------------"
      echo " ${FAKE_ROLE_NAME:-pfin_etl}"
      exit 0
    fi
    if [[ "${FAKE_CONTROL_WRONG_ERROR:-0}" == "1" ]]; then
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: could not translate host name \"db\" to address: Name or service not known" >&2
      exit 2
    fi
    if [[ "${FAKE_CONTROL_WRONG_ROLE_ERROR:-0}" == "1" ]]; then
      # team-lead's run-6 stop, item 5a -- a DIFFERENT role's own auth
      # failure text (e.g. a stale/misdirected connection), never
      # $FAKE_ROLE_NAME. Proves the role-specific string match is
      # load-bearing: a role-agnostic `grep -qF "password authentication
      # failed"` would have wrongly ACCEPTED this as proof.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"some_other_role\"" >&2
      exit 2
    fi
    [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
    echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"${FAKE_ROLE_NAME:-pfin_etl}\"" >&2
    exit 2
  fi
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
    FAKE_NO_PASSWORD_PROMPT="\$FAKE_NO_PASSWORD_PROMPT" FAKE_READBACK_HASH_MISMATCH="\$FAKE_READBACK_HASH_MISMATCH" FAKE_READBACK_EMPTY="\$FAKE_READBACK_EMPTY" \\
    FAKE_READBACK_USER="\$FAKE_READBACK_USER" FAKE_ECHO_PW_IN_CONNECT="\$FAKE_ECHO_PW_IN_CONNECT" \\
    FAKE_STORE_COUNT="\$FAKE_STORE_COUNT" FAKE_STORE_NONEMPTY="\$FAKE_STORE_NONEMPTY" FAKE_BIND_CHECK_PW="\$FAKE_BIND_CHECK_PW" \\
    FAKE_NO_PASSWORD_PROMPT_CLEAN="\$FAKE_NO_PASSWORD_PROMPT_CLEAN" FAKE_WRONG_CURRENT_USER="\$FAKE_WRONG_CURRENT_USER" \\
    FAKE_CONTROL_SUCCEEDS="\$FAKE_CONTROL_SUCCEEDS" FAKE_CONTROL_WRONG_ERROR="\$FAKE_CONTROL_WRONG_ERROR" \\
    FAKE_CONTROL_WRONG_ROLE_ERROR="\$FAKE_CONTROL_WRONG_ROLE_ERROR" FAKE_ECHO_PW_IN_CONTROL="\$FAKE_ECHO_PW_IN_CONTROL" \\
    FAKE_CONNECT_CALL_LOG="\$FAKE_CONNECT_CALL_LOG" \\
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
  # <bind_check_pw> (team-lead, run-4, Item 4, 2026-09-21): the already-
  # handed-off bind-check's OWN leg-A value read. Empty string models "the
  # store resolved to no value on this specific read" (scenario 2f);
  # unset/omitted defaults to a real-looking 64-char value so every other
  # scenario's bind-check (including connect-fail strikes via
  # <connect_fail>) passes through this read undisturbed.
  # <store_nonempty> (team-lead's run-6 stop, item 1/4, 2026-09-21): the
  # preflight's OWN non-emptiness answer for the store row (independent of
  # the bind-check's own separate read via <bind_check_pw> above) --
  # defaults to 1 (non-empty), matching every pre-existing scenario's own
  # assumption that a store_count=1 row carries a real value. Set to 0
  # alongside store_count=1 to model the compose-parse EMPTY PLACEHOLDER
  # row (team-lead's run-6 measurement: pfin-back-etl/pfin-provider-sync
  # each carried exactly one such row, value_len=0) -- STORE_HAS_PW must
  # then read false, the exact same as a genuinely fresh store.
  local desc="$1" expect_exit="$2" role="$3" apply_flag="$4" curl_mode="$5" \
        role_state="$6" verify_state="$7" connect_fail="$8" mismatch="$9" handoff_fail="${10}" echo_pw="${11}" readback_count="${12}" no_prompt="${13:-0}" hash_mismatch="${14:-0}" readback_user="${15:-}" echo_pw_in_connect="${16:-0}" store_count="${17-0}" bind_check_pw="${18-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" no_prompt_clean="${19:-0}" wrong_current_user="${20:-0}" control_succeeds="${21:-0}" control_wrong_error="${22:-0}" store_nonempty="${23:-1}" control_wrong_role_error="${24:-0}" echo_pw_in_control="${25:-0}" readback_empty="${26:-0}"
  local log="$WORK/curl.log.$$.$RANDOM"
  : > "$log"
  local resource_name="pfin-back-etl"
  [[ "$role" == "pfin_provider_sync" ]] && resource_name="pfin-provider-sync"
  # Sec/self-found bug (this file's own sibling, fence-db-bootstrap-
  # strikes.sh, hit the identical trap this round): `OUT="$(run_scenario
  # ...)"` forks a SUBSHELL -- an assignment made INSIDE this function
  # never survives back to the caller. Callers that need to inspect this
  # log after the call must pre-set CONNECT_CALL_LOG themselves before
  # invoking run_scenario (inherited INTO the subshell); this line only
  # supplies a default when they have not.
  CONNECT_CALL_LOG="${CONNECT_CALL_LOG:-$WORK/connect.log.$$.$RANDOM}"
  : > "$CONNECT_CALL_LOG"
  set +e
  BOX_IP=127.0.0.1 AUTOMATION_KEY=/dev/null REPO_ROOT="$REPO_ROOT" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" FAKE_RESOURCE_NAME="$resource_name" \
    FAKE_ROLE_STATE="$role_state" FAKE_VERIFY_STATE="$verify_state" FAKE_ROLE_NAME="$role" \
    FAKE_CONNECT_FAIL="$connect_fail" FAKE_MISMATCH="$mismatch" FAKE_HANDOFF_FAIL="$handoff_fail" \
    FAKE_ECHO_PASSWORD_IN_OUTPUT="$echo_pw" FAKE_READBACK_COUNT="$readback_count" \
    FAKE_NO_PASSWORD_PROMPT="$no_prompt" FAKE_READBACK_HASH_MISMATCH="$hash_mismatch" FAKE_READBACK_EMPTY="$readback_empty" \
    FAKE_READBACK_USER="$readback_user" FAKE_ECHO_PW_IN_CONNECT="$echo_pw_in_connect" \
    FAKE_STORE_COUNT="$store_count" FAKE_STORE_NONEMPTY="$store_nonempty" FAKE_BIND_CHECK_PW="$bind_check_pw" \
    FAKE_NO_PASSWORD_PROMPT_CLEAN="$no_prompt_clean" FAKE_WRONG_CURRENT_USER="$wrong_current_user" \
    FAKE_CONTROL_SUCCEEDS="$control_succeeds" FAKE_CONTROL_WRONG_ERROR="$control_wrong_error" \
    FAKE_CONTROL_WRONG_ROLE_ERROR="$control_wrong_role_error" FAKE_ECHO_PW_IN_CONTROL="$echo_pw_in_control" \
    FAKE_CONNECT_CALL_LOG="$CONNECT_CALL_LOG" \
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

assert_output_lacks() {
  local desc="$1" out="$2" needle="$3"
  if grep -qF "$needle" <<<"$out"; then
    echo "FAIL: [$desc] unexpectedly contained '$needle'." >&2
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
CONNECT_CALL_LOG="$WORK/connect-pin.2.$$"
: > "$CONNECT_CALL_LOG"
OUT2="$(run_scenario "already-handed-off: VERIFIED no-op" 0 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1)" || FAIL=1
assert_output_contains "already-handed-off" "${OUT2:-}" "already handed off" || FAIL=1
assert_output_contains "already-handed-off" "${OUT2:-}" "VERIFIED" || FAIL=1
# team-lead's queued Sec item 2 -- the control's own observed-fact OK
# line is load-bearing evidence: pin it so deleting it turns this RED.
assert_output_contains "already-handed-off" "${OUT2:-}" "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"pfin_etl\"'" || FAIL=1
# Sec F-1 (PR #852 AMBER review) remedied (team-lead, run-4, Item 4,
# 2026-09-21) -- this no-op path used to be existence-only; it now runs a
# real bind-check (read the store's current value, connect AS the role
# with it) before reporting VERIFIED. Pin the bind-check's own success
# line, not the old existence-only caveat text (removed).
assert_output_contains "already-handed-off" "${OUT2:-}" "bind-check confirmed" || FAIL=1
# team-lead's run-5 fix (2026-09-21) -- -W PINNED FROM THE LOGGED ARGV,
# not just inferred from behavior: every -h db call this scenario made
# (the trust-path control AND the real connect) must carry -W.
if [[ ! -s "$CONNECT_CALL_LOG" ]]; then
  echo "FAIL: [already-handed-off] no -h db connect calls were logged at all -- the -W pin has nothing to check." >&2
  FAIL=1
elif grep -qv -- '-W' "$CONNECT_CALL_LOG"; then
  echo "FAIL: [already-handed-off] at least one -h db connect call did not carry -W:" >&2
  grep -v -- '-W' "$CONNECT_CALL_LOG" >&2
  FAIL=1
fi
unset CONNECT_CALL_LOG

# 2f. ALREADY-HANDED-OFF-BIND-CHECK-RACE (team-lead's run-6 stop, item 3,
#     2026-09-21 -- reclassified from "store-empty" now that the
#     preflight itself checks non-emptiness, item 1 below) -- the
#     preflight says the store carries a NON-EMPTY row (store_count=1,
#     store_nonempty=1, the default), but the bind-check's own SEPARATE
#     read a moment later resolves empty -- a race between the two reads,
#     or the store changed mid-run. This must NOT be classified as
#     "does NOT authenticate" (it was never tried against a value at
#     all) -- refuses with the dedicated race message instead.
OUT2F="$(run_scenario "already-handed-off-bind-check: race refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "")" || FAIL=1
assert_output_contains "already-handed-off-bind-check-race" "${OUT2F:-}" "a race between the two reads" || FAIL=1
assert_output_lacks "already-handed-off-bind-check-race" "${OUT2F:-}" "does NOT authenticate" || FAIL=1

# 2h. PLACEHOLDER-ROW (team-lead's run-6 stop, item 1, 2026-09-21 --
#     MEASURED on the box: pfin-back-etl/pfin-provider-sync each carried
#     exactly one PFIN_DB_PASSWORD row, is_preview=false, value_len=0 --
#     an EMPTY PLACEHOLDER Coolify's compose parser creates from the
#     workers' `${PFIN_DB_PASSWORD:?}` interpolation, never a real push).
#     store_count=1 but store_nonempty=0 -- STORE_HAS_PW must read false,
#     the SAME as a genuinely fresh store, sending role_state=true|true
#     into the adopt-by-rotation shape (the "else" INCONSISTENT branch,
#     byte-matched by provision.sh's own handoff_adopt_check()) rather
#     than the (wrong) already-handed-off bind-check path.
OUT2H="$(run_scenario "placeholder-row: adopt-by-rotation shape" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "" 0 0 0 0 0)" || FAIL=1
assert_output_contains "placeholder-row" "${OUT2H:-}" "rolcanlogin=true has_password=true store_has_PFIN_DB_PASSWORD=false" || FAIL=1
assert_output_lacks "placeholder-row" "${OUT2H:-}" "does NOT authenticate" || FAIL=1

# 2i. PLACEHOLDER-ROW-ROTATE-SUCCEEDS -- the same placeholder shape, but
#     --apply --rotate (ROTATE only requires ROLCANLOGIN=true and does not
#     consult STORE_HAS_PW at all) -- proceeds through the plain
#     apply/rotate path unaffected by the placeholder, generating a fresh
#     credential and pushing it; leg E's own hash-bound readback (already
#     load-bearing, scenario 9/14) is what proves the placeholder row got
#     UPDATED to exactly one real row, never duplicated.
OUT2I="$(run_scenario "placeholder-row-rotate: succeeds via plain rotate path" 0 pfin_etl "--apply --rotate" clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "" 0 0 0 0 0)" || FAIL=1
assert_output_contains "placeholder-row-rotate" "${OUT2I:-}" "hash-bound to the generated credential confirmed" || FAIL=1

# 2g. ALREADY-HANDED-OFF-BIND-CHECK-CONNECT-FAILS -- the store carries a
#     real-looking value, but connecting AS the role with it fails --
#     the exact half-completed-rotation residual Sec's F-1 named.
OUT2G="$(run_scenario "already-handed-off-bind-check: connect-fails refuses" 1 pfin_etl --apply clean "true|true" "true|true" 1 0 0 0 "" 0 0 "" 0 1)" || FAIL=1
assert_output_contains "already-handed-off-bind-check-connect-fails" "${OUT2G:-}" "INCONSISTENT(store" || FAIL=1

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
CONNECT_CALL_LOG="$WORK/connect-pin.10.$$"
: > "$CONNECT_CALL_LOG"
OUT10="$(run_scenario "happy-path-initial: succeeds" 0 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "")" || FAIL=1
assert_output_contains "happy-path-initial" "${OUT10:-}" "hash-bound to the generated credential confirmed" || FAIL=1
assert_output_contains "happy-path-initial" "${OUT10:-}" "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"pfin_etl\"'" || FAIL=1
# -W PINNED FROM THE LOGGED ARGV (fresh-handoff leg C's own connect calls).
if [[ ! -s "$CONNECT_CALL_LOG" ]]; then
  echo "FAIL: [happy-path-initial] no -h db connect calls were logged at all -- the -W pin has nothing to check." >&2
  FAIL=1
elif grep -qv -- '-W' "$CONNECT_CALL_LOG"; then
  echo "FAIL: [happy-path-initial] at least one -h db connect call did not carry -W:" >&2
  grep -v -- '-W' "$CONNECT_CALL_LOG" >&2
  FAIL=1
fi
unset CONNECT_CALL_LOG

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
assert_output_contains "provider-sync happy-path-initial" "${OUT12:-}" "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"pfin_provider_sync\"'" || FAIL=1

# 13. TRUST-PATH-NO-PROMPT (Sec VETO V-1, PR #846 review; team-lead's
#     run-6 stop item 7 -- fixture-fidelity: the bypass now applies to
#     ANY connect attempt, control included) -- the CONTROL probe hits
#     this shape FIRST, before the real connect is ever attempted: its
#     own exact-string auth-failure check never finds it (a syntax
#     error, not "password authentication failed"), so the script
#     refuses at the control. Before the V-1 fix this scenario exited 0
#     (false OK).
OUT13="$(run_scenario "trust-path-no-prompt: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 1)" || FAIL=1
assert_output_contains "trust-path-no-prompt" "${OUT13:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 13b. TRUST-PATH-NO-PROMPT-CLEAN -- the same bypass via the non-leaking
#      variant, same control-refusal outcome; kept for its own
#      independent coverage of the FAKE_NO_PASSWORD_PROMPT_CLEAN path.
OUT13B="$(run_scenario "trust-path-no-prompt-clean: refuses at the control" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 1)" || FAIL=1
assert_output_contains "trust-path-no-prompt-clean" "${OUT13B:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 13c. WRONG-CURRENT-USER-FRESH-HANDOFF (Sec C-1, PR #856 round 1) -- leg
#      C's own connect (the fresh-handoff path): prompt prints normally,
#      no cleartext leak, exit 0, but `select current_user;` echoes back a
#      DIFFERENT role. Proves the exact-row current_user match -- the fix
#      for C-1's vacuous-substring defect -- fires independently, not
#      merely because the prompt/exit-code checks also would have (a bare
#      `grep -qF "$ROLE"` over the whole capture is already satisfied by
#      the "Password for user $ROLE:" prompt line itself).
OUT13C="$(run_scenario "wrong-current-user-fresh-handoff: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 1)" || FAIL=1
assert_output_contains "wrong-current-user-fresh-handoff" "${OUT13C:-}" "did not echo back 'pfin_etl' as its own output row" || FAIL=1

# 13d. WRONG-CURRENT-USER-BIND-CHECK (Sec C-1, PR #856 round 1) -- the
#      SAME strike against the already-handed-off bind-check's own
#      connect (Item 4, run-4) -- role already LOGIN+password, store
#      already carries a row, prompt/exit-code/cleartext all clean, but
#      current_user echoes back a different role.
OUT13D="$(run_scenario "wrong-current-user-bind-check: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 0 1)" || FAIL=1
assert_output_contains "wrong-current-user-bind-check" "${OUT13D:-}" "did not echo back 'pfin_etl' as its own output row" || FAIL=1

# 14. READBACK-HASH-MISMATCH (Sec F-2) -- exactly one production row exists,
#     but its value's truncated hash does NOT match the credential this run
#     generated (a stale/different secret already occupying the key) ->
#     refuses, proving the count-only check from #9 is not the only guard.
OUT14="$(run_scenario "readback-hash-mismatch: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 1)" || FAIL=1
assert_output_contains "readback-hash-mismatch" "${OUT14:-}" "DIFFERENT value than what was pushed" || FAIL=1

# 14b. READBACK-EMPTY (team-lead's run-6 stop, item 8) -- exactly one
#      production row exists, but its value is empty. This site is
#      already hash-bound and structurally immune (empty never hashes to
#      $EXPECTED_HASH); hardened anyway with the SAME predicate for a
#      clearer diagnostic than the generic hash-mismatch text.
OUT14B="$(run_scenario "readback-empty: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 0 0 0 1 0 0 1)" || FAIL=1
assert_output_contains "readback-empty" "${OUT14B:-}" "readback resolved to an empty value" || FAIL=1

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

# 18a. ALREADY-HANDED-OFF-CONTROL-SUCCEEDS (team-lead, run-5, 2026-09-21)
#      -- the trust-path control (a deliberately WRONG password) succeeds
#      instead of failing -- the exact hazard the control exists to
#      catch (a trust rule authenticating ANY password) -- refuses,
#      never proceeding to try the real credential.
OUT18A="$(run_scenario "already-handed-off-control-succeeds: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 0 0 1)" || FAIL=1
assert_output_contains "already-handed-off-control-succeeds" "${OUT18A:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18b. ALREADY-HANDED-OFF-CONTROL-WRONG-ERROR -- the control fails, but
#      not with "password authentication failed" -- refuses.
OUT18B="$(run_scenario "already-handed-off-control-wrong-error: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 0 0 0 1)" || FAIL=1
assert_output_contains "already-handed-off-control-wrong-error" "${OUT18B:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18c. LEG-C-CONTROL-SUCCEEDS -- same strike against the fresh-handoff
#      leg C.
OUT18C="$(run_scenario "leg-c-control-succeeds: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-succeeds" "${OUT18C:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18d. LEG-C-CONTROL-WRONG-ERROR -- same, non-auth-failure error shape.
OUT18D="$(run_scenario "leg-c-control-wrong-error: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-wrong-error" "${OUT18D:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18e. ALREADY-HANDED-OFF-CONTROL-WRONG-ROLE (team-lead's run-6 stop, item
#      5a, 2026-09-21) -- the control DOES fail with the exact text
#      "password authentication failed", but naming a DIFFERENT role than
#      the one being tested -- refuses. Proves the role-specific match is
#      load-bearing: a role-agnostic `grep -qF "password authentication
#      failed"` (the F-1b-class defect this tightening fixes) would have
#      wrongly ACCEPTED this as proof.
OUT18E="$(run_scenario "already-handed-off-control-wrong-role: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 0 0 0 0 1 1)" || FAIL=1
assert_output_contains "already-handed-off-control-wrong-role" "${OUT18E:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18f. LEG-C-CONTROL-WRONG-ROLE -- same strike against the fresh-handoff leg C.
OUT18F="$(run_scenario "leg-c-control-wrong-role: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 0 0 0 1 1)" || FAIL=1
assert_output_contains "leg-c-control-wrong-role" "${OUT18F:-}" "did not fail with the exact text 'password authentication failed for user \"pfin_etl\"'" || FAIL=1

# 18g. ALREADY-HANDED-OFF-CONTROL-CLEARTEXT-LEAK (Sec F-1, PR #858
#      review) -- the CONTROL's own scrub had no scenario in this file
#      either: striking it left the whole suite green. Models a
#      hypothetical transport/debug-print bug leaking the REAL credential
#      into the control probe's own output even though the control never
#      sent it.
OUT18G="$(run_scenario "already-handed-off-control-cleartext-leak: refuses" 1 pfin_etl --apply clean "true|true" "true|true" 0 0 0 0 "" 0 0 "" 0 1 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 0 0 0 0 1 0 1)" || FAIL=1
assert_output_contains "already-handed-off-control-cleartext-leak" "${OUT18G:-}" "cleartext value appeared in the trust-path control's own captured output" || FAIL=1
assert_output_lacks "already-handed-off-control-cleartext-leak" "${OUT18G:-}" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" || FAIL=1

# 18h. LEG-C-CONTROL-CLEARTEXT-LEAK -- same strike against the fresh-handoff leg C.
OUT18H="$(run_scenario "leg-c-control-cleartext-leak: refuses" 1 pfin_etl --apply clean "false|false" "true|true" 0 0 0 0 "" 0 0 "" 0 0 "" 0 0 0 0 1 0 1)" || FAIL=1
assert_output_contains "leg-c-control-cleartext-leak" "${OUT18H:-}" "cleartext value appeared in the trust-path control's own captured output" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more db-role-handoff.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all db-role-handoff.sh strike-proofs passed."
exit 0
