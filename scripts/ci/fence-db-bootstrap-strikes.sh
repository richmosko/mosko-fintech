#!/usr/bin/env bash
#
# fence-db-bootstrap-strikes.sh -- offline strike-proof for
# scripts/db-bootstrap.sh. Runs entirely without a live box, network, or
# real Postgres: a fake `ssh` rewrites /root/.pfin and PATH-shadows
# curl/docker for every nested invocation (same shape as
# fence-db-role-handoff-strikes.sh), a fake `docker` stands in for every
# `docker compose ... exec -T db psql ...` / `exec -T migrator sh -c
# 'supabase db push ...'` / `docker exec coolify php artisan tinker --execute=...`
# call, distinguishing the many shapes by their OWN argv flags and stdin
# content (never call order), and tests/fixtures/ci/db-bootstrap/fake-curl
# resolves both the stack and migrator applications. A throwaway
# REPO_ROOT fixture tree (never the real repo) supplies roles.sql /
# auth-grants.sql / post-step-vault-view.sql / two of the five
# role-comment migration files -- the other three (116/117/119) are
# DELIBERATELY absent, exercising the real script's own "skip absent
# file" branch rather than assuming it works. scripts/db-bootstrap.sh
# itself is never modified or made aware any of this exists.
#
# Scenarios (BACKLOG.md §7.36 item 75, W-5; 🔒 SECURITY-SENSITIVE --
# Sec joint-review mandatory on the PR this fence ships in):
#   1. ALREADY-BOOTSTRAPPED-CLEAN -- bootstrap_complete=true, ownership
#      census clean -> exit 0, "VERIFIED, nothing to do", AND no Phase
#      1/2/3 file-apply step ever ran (this fence asserts the ABSENCE of
#      "roles.sql applied" in the captured output -- a script that
#      re-applied everything on an already-bootstrapped box would still
#      exit 0 here without this check).
#   2. ALREADY-BOOTSTRAPPED-CENSUS-BAD -- bootstrap_complete=true but the
#      ownership census is dirty -> refuses, "the pfin_owner sweep broke
#      somewhere" (proves this script does NOT treat bootstrap_complete
#      alone as sufficient evidence).
#  2a. ALREADY-BOOTSTRAPPED-STORE-ABSENT (team-lead, run-4 follow-up,
#      2026-09-21 -- remedies Sec's PR #854 "falsified verification
#      record" finding: the census alone, scenario 1's own check, said
#      nothing about the migrator credential actually working) -- census
#      clean, but pfin-migrator's env store holds no MIGRATOR_DB_PASSWORD
#      -> FAILED (exit 2), "credential/store drift", never a false
#      VERIFIED.
#  2b. ALREADY-BOOTSTRAPPED-LEG-C-FAILS -- census clean, store holds a
#      credential, but connecting AS migrator with it fails outright ->
#      refuses (exit 1), "store and the live role have drifted apart" --
#      proves this path's own leg C is load-bearing, not decorative.
#  2c. ALREADY-BOOTSTRAPPED-LEG-E-DIVERGES -- census clean, leg C connects
#      fine, but the store's re-read value no longer hash-matches what
#      leg C just used (a rotation racing this very check) -> refuses
#      (exit 1), "changed between leg A's read and leg C's connect
#      attempt".
#   3. PARTIAL-STATE -- migrator already has LOGIN+password but
#      bootstrap_complete=false -> refuses, "PARTIAL bootstrap state" (proves
#      the script refuses to GUESS a repair rather than re-running
#      Phase 1 destructively over a half-done box).
#   4. PREFLIGHT-NO-APPLY -- fresh box, no --apply -> exit 0, "re-run
#      with --apply" (read-only preflight, no phase runs).
#   5. PHASE1-ROLES-FAIL -- roles.sql's own psql call fails -> refuses,
#      "supabase/roles.sql failed".
#   6. STORE-EMPTY-REFUSES (Sec VETO-1 r2, PR #849 review -- PATH A: read,
#      don't mint) -- pfin-migrator's env store holds no
#      MIGRATOR_DB_PASSWORD -> FAILED (exit 2, a precondition, not a
#      REFUSED finding), naming "run scripts/provision-migrator-app.sh
#      first". This is the whole point of PATH A: db-bootstrap no longer
#      mints its own credential, so an absent store value is a genuine
#      precondition gap, not something this script can paper over.
#   7. CREDENTIAL-MISMATCH -- the piped \password step's confirmation
#      mismatches -> refuses, "confirmation mismatch" (same guard shape
#      as db-role-handoff.sh's own, reused here).
#   8. CREDENTIAL-CLEARTEXT-LEAK -- the fake psql echoes the credential
#      back -> refuses, "cleartext value appeared" (proves the guard is
#      load-bearing, not decorative, inside db-bootstrap.sh's OWN copy of
#      the mechanism, not just db-role-handoff.sh's).
#  8b. LEG-A-NONZERO-WITH-CLEARTEXT-LEAK (Sec F-2b, PR #849 r3 review) --
#      psql exits NON-ZERO (the trust-path-not-consumed hazard -- the
#      piped PW lines parsed as SQL instead of consumed by \password,
#      turned into a failing exit by -v ON_ERROR_STOP=1) AND the
#      credential appears in that SAME captured output -> refuses via the
#      cleartext scrub, which must run BEFORE the RC-failure branch ever
#      prints the captured output raw. The old guard order (RC check,
#      print raw, THEN scrub) disclosed the 64-char credential on stderr
#      on exactly this failure -- a real defect found at r3 review, not a
#      hypothetical. This scenario's own assertion checks BOTH that the
#      refusal happens AND that the credential's own value never appears
#      anywhere in the captured output -- scenario 8 alone (exit-0 leak)
#      does not exercise the RC!=0 branch at all.
#   9. LEG-B-CATALOG-VERIFY-MISMATCH -- leg A "succeeds" but the fresh
#      post-handoff catalog re-read does not show true|true -> refuses.
#  10. LEG-C-CONNECT-FAIL -- connect AS migrator fails outright (prompt
#      DOES appear) -> refuses, "did not take effect end to end".
#  11. LEG-C-TRUST-PATH-NO-PROMPT -- the exact db-role-handoff.sh V-1
#      hazard, re-proven inside db-bootstrap.sh's OWN copy of the
#      mechanism: no password prompt observed -> refuses regardless of
#      exit code.
#  12. LEG-C-CLEARTEXT-LEAK-IN-CONNECT -- the prompt DOES print but the
#      credential also leaks elsewhere in the connect step's own output
#      -> refuses (proven in isolation from the missing-prompt guard).
#  13. LEG-C-WRONG-CURRENT-USER (Sec F-1b, PR #849 r2 review) -- the
#      connection succeeds, the prompt DOES print, no cleartext leak, but
#      `select current_user;` echoes back a DIFFERENT role -> refuses.
#      Proves the current_user check is load-bearing on its own, not a
#      substring match already satisfied by the prompt line itself (the
#      r1 form -- `grep -qF "migrator"` over the WHOLE capture -- could
#      never fail independently, since "Password for user migrator: "
#      already contains the literal string "migrator"; fixed to an
#      anchored, whitespace-tolerant EXACT-row match).
#  14. LEG-E-READBACK-COUNT-MISMATCH -- the store's MIGRATOR_DB_PASSWORD
#      resolves to zero (or >1) production rows on the sanity re-read ->
#      refuses, "expected exactly 1".
#  15. LEG-E-READBACK-DIVERGE (Sec VETO-1 r2's own named scenario) -- the
#      store's CURRENT value (re-read fresh) no longer hash-matches the
#      value the migrator role was just set to (leg A's own read) ->
#      refuses. Models a concurrent rotation landing between leg A's read
#      and this point -- the role would otherwise be silently set to a
#      value the NEXT deploy's PROD_DB_URL will not actually carry.
#  16. PHASE2-PUSH-FAILS -- `supabase db push` exits non-zero -> refuses,
#      "supabase db push exited".
#  17. PHASE2-NO-COMPLETION-LINE -- exit 0 but the CLI's own "Finished
#      supabase db push" line is absent -> refuses, "incomplete run, not
#      a pass" (proves exit-code alone is not trusted).
#  18. PHASE2-CENSUS-BAD-AFTER-PUSH -- the ownership census is dirty
#      immediately after the push -> refuses, "broke somewhere in the
#      apply", before Phase 3 ever runs.
#  19. PHASE2-BOOTSTRAP-NOT-COMPLETE-AFTER-PUSH -- migration 118 did not
#      actually land -> refuses, "did not actually land 118".
#  20. PHASE3-VAULT-VIEW-FAILS -- post-step-vault-view.sql's own exit
#      signals failure -> refuses, "post-step-vault-view.sql failed"
#      (this script does not re-implement that file's own assertion --
#      a non-zero exit IS the signal; exercised as a source-literal pin,
#      see the comment at that scenario for why).
#  21. HAPPY-PATH-FULL-APPLY -- fresh box, --apply, every phase succeeds
#      -> exit 0, "migrator: LOGIN + password set from pfin-migrator's
#      own existing MIGRATOR_DB_PASSWORD", legs A/B/C/E all pass together
#      (leg A's read and leg E's re-read both resolve to the SAME fixed
#      store value, via the fake's own FAKE_STORE_PW, so a genuine
#      divergence -- scenario 15 -- is provably distinct from this path),
#      AND the three deliberately-absent role-comment files (116/117/119)
#      are each reported "not present in supabase/migrations/ --
#      skipping" rather than silently omitted or fatally missing.
#  22. RESOURCE-ABSENT -- the migrator app does not resolve -> refuses.
#      ⚠ MEASURED exit 1, not the header's documented 2 -- same
#      `set -e`-on-assignment shape as fence-pgrst-exposure-gates-
#      strikes.sh's own finding (pre-existing across the repo).
#  23. UNKNOWN-FLAG -- an unrecognised argument -> FAILED (exit 2),
#      "unknown flag".
#  24. STRUCTURAL-WORKTREE-GUARD-PIN -- a source-literal assertion, not a
#      runtime scenario: this fence ALWAYS pre-sets REPO_ROOT (every
#      scenario above does), which bypasses db-bootstrap.sh's own
#      worktree-refusal block entirely by construction -- the header's
#      central security claim ("REFUSES TO RUN OUTSIDE AN OPERATOR SSH
#      SESSION, STRUCTURALLY") is therefore NOT behaviorally exercised by
#      any scenario here. This pin asserts the guard's source text still
#      exists, so a future edit that silently deletes it does not pass
#      this fence by omission.
#
# 25-29. FAIL-OPEN SWEEP (team-lead's live --from standup finding,
#      2026-09-21) -- the OLD bootstrap_complete read used
#      `2>/dev/null || echo 'f'`: a FAILED read was silently converted
#      into the specific answer "not bootstrapped", and this script then
#      proceeded to a full re-apply against an already-bootstrapped,
#      live database. Every gating read now goes through a shared
#      read_gate() helper; these five scenarios prove BOTH failure modes
#      (the read itself fails; the read succeeds but returns
#      unparseable output) refuse, exit 2, "cannot determine ... state",
#      never a guessed answer -- on bootstrap_complete, migrator
#      credential state, and the ownership census reads.
#  25. BOOTSTRAP-READ-FAILS -- refuses, "could not read
#      bootstrap_complete".
#  26. BOOTSTRAP-READ-GARBAGE -- refuses, "unparseable output".
#  27. MIGRATOR-STATE-READ-GARBAGE -- refuses, "unparseable output".
#  28. CENSUS-READ-GARBAGE (bootstrap_complete=true branch) -- refuses,
#      "unparseable output".
#  29. MIGRATOR-STATE-READ-FAILS -- refuses, "could not read migrator
#      credential state".
#
# 11b, 21a-21d, plus -W-pin checks on scenarios 1 and 21 (team-lead, run-5
# realrun5.clean.log, 2026-09-21) -- MEASURED on the production target:
# psql 17.6 over -h db, non-tty, prints NO password prompt at all without
# `-W` (it silently consumes the piped first line as the password); `-W`
# forces one (`Password: `). Every prompt-observed guard in this file was
# fail-closed on a premise that could never be true in production. Fixed
# both connect-as-migrator sites: `-W` added, the prompt assertion accepts
# `Password:`/`Password for user`, a POSITIVE CONTROL (a deliberately
# WRONG password) must fail with "password authentication failed" BEFORE
# the real credential is tried, and every FATAL in these legs now prints
# the (already scrub-cleared) captured output.
#  11b. LEG-C-TRUST-PATH-NO-PROMPT-CLEAN -- same shape as 11 with a
#       non-leaking syntax error, isolating the missing-prompt guard
#       (11's own realistic fixture leaks $PW, so the cleartext scrub now
#       fires first there -- a stronger, not weaker, outcome).
#  21a. ALREADY-BOOTSTRAPPED-CONTROL-SUCCEEDS -- the trust-path control
#       succeeds instead of failing (a trust rule authenticating ANY
#       password) -- refuses, never tries the real credential.
#  21b. ALREADY-BOOTSTRAPPED-CONTROL-WRONG-ERROR -- the control fails,
#       but not with "password authentication failed" -- refuses, never
#       treated as sufficient proof.
#  21c/21d. Same two strikes against Phase-1's own leg C.
#  -W is additionally PINNED FROM THE LOGGED ARGV on scenarios 1 and 21
#  (both real connect-as-migrator sites) -- deleting -W from the real
#  script must turn this RED even if no behavioral assertion noticed.
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/db-bootstrap"
TARGET_SH="$REPO_ROOT/scripts/db-bootstrap.sh"

[[ -x "$FIXTURE_DIR/fake-curl" ]] || { echo "FATAL: $FIXTURE_DIR/fake-curl missing or not executable" >&2; exit 2; }
[[ -f "$TARGET_SH" ]] || { echo "FATAL: $TARGET_SH not found" >&2; exit 2; }

if ! grep -qF '/.claude/worktrees/' "$TARGET_SH"; then
  echo "FAIL: [structural-worktree-guard-pin] $TARGET_SH no longer carries its own worktree-refusal guard text -- this fence always pre-sets REPO_ROOT and so cannot exercise that guard behaviorally; the source-literal pin is the only thing standing between a silent regression and a false green." >&2
  exit 1
else
  echo "OK: [structural-worktree-guard-pin] $TARGET_SH still carries its own worktree-refusal guard text." >&2
fi

# Sec VETO-1 (PR #854 review) -- the two per-site structural pins that
# used to live here (leg-B catalog verify, Phase 2 db push) are now
# superseded by scripts/ci/fence-heredoc-stdin-drain.sh, a tree-wide
# structural fence over every scripts/*.sh (team-lead's own follow-up
# ruling: the pin must be tree-wide, not scoped to individual files) --
# never two divergent implementations of the same source-literal check
# living in different fences. Run that fence, not a copy of it here.

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_TOKEN="fake-coolify-token-$(date +%s)-do-not-leak"
FAKE_ROOT_PFIN="$WORK/fakebox/root/pfin"
mkdir -p "$FAKE_ROOT_PFIN"
printf 'COOLIFY_API_TOKEN=%s\n' "$FAKE_TOKEN" > "$FAKE_ROOT_PFIN/coolify.env"

# A fixed, valid-shaped (64 hex-lookalike chars) "store" credential value
# -- the happy-path fixture leg A reads and leg E re-reads, proving BOTH
# resolve to the SAME value on a clean run (as distinct from scenario 15,
# where leg E's re-read is forced to diverge).
FIXED_STORE_PW="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Throwaway REPO_ROOT fixture tree -- never the real repo. Deliberately
# omits 116/117/119's role-comment files to exercise the real script's
# own "skip absent file" branch under HAPPY-PATH-FULL-APPLY.
FIXTURE_REPO="$WORK/fixture-repo"
mkdir -p "$FIXTURE_REPO/supabase/migrations"
printf 'BOX_IP=127.0.0.1\n' > "$FIXTURE_REPO/.env"
printf -- '-- FIXTURE_ROLES_SQL_MARKER\ncreate role fixture_role;\n' > "$FIXTURE_REPO/supabase/roles.sql"
printf -- '-- FIXTURE_AUTH_GRANTS_MARKER\ngrant usage on schema auth to fixture_role;\n' > "$FIXTURE_REPO/supabase/auth-grants.sql"
printf -- '-- FIXTURE_VAULT_VIEW_MARKER\ncreate view pfin.decrypted_source_credential as select 1;\n' > "$FIXTURE_REPO/supabase/post-step-vault-view.sql"
printf -- '-- FIXTURE_055_MARKER\ncomment on role pfin_etl is '"'"'fixture'"'"';\n' > "$FIXTURE_REPO/supabase/migrations/055_pfin_etl_role.sql"
printf -- '-- FIXTURE_118_MARKER\ncomment on role migrator is '"'"'fixture'"'"';\n' > "$FIXTURE_REPO/supabase/migrations/118_migrator_role.sql"

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-curl" "$FAKE_BIN/curl"

# Fake `docker` -- distinguishes every call shape by its OWN argv flags
# and stdin content, never by call order.
cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
ARGS="$*"

# psql_admin() scalar reads (-tAc), including leg B's catalog verify.
if [[ "$ARGS" == *"-tAc"* ]]; then
  if [[ "$ARGS" == *"pg_catalog.pg_authid"* ]]; then
    if [[ "${FAKE_MIGRATOR_STATE_READ_FAIL:-0}" == "1" ]]; then
      echo "psql: error: connection to server on socket failed" >&2
      exit 1
    fi
    # No colon -- an explicit empty override (role-absent, a VALID
    # state, distinct from "unset -> use the compiled-in default") must
    # survive, not get silently defaulted back (the same class of bug
    # caught twice already in PR #852's own fences this session).
    echo "${FAKE_MIGRATOR_STATE-false|false}"
    exit 0
  fi
  if [[ "$ARGS" == *"from pg_authid where rolname='migrator'"* ]]; then
    echo "${FAKE_LEG_B_STATE-true|true}"
    exit 0
  fi
  if [[ "$ARGS" == *"version = '118'"* ]]; then
    # Distinguishes the PREFLIGHT read (before Phase 2 has run) from the
    # POST-PUSH verify read (after it has) via a marker file the push
    # branch below touches on its own successful completion -- a single
    # static FAKE_BOOTSTRAP_COMPLETE value cannot model "false before
    # the push, true after" (the actual HAPPY-PATH shape) on its own.
    if [[ "${FAKE_BOOTSTRAP_READ_FAIL:-0}" == "1" ]]; then
      echo "psql: error: connection to server on socket failed" >&2
      exit 1
    fi
    if [[ -n "${FAKE_MARKER_FILE:-}" && -f "${FAKE_MARKER_FILE:-}" ]]; then
      echo "${FAKE_POST_PUSH_BOOTSTRAP-true}"
    else
      echo "${FAKE_BOOTSTRAP_COMPLETE-false}"
    fi
    exit 0
  fi
  if [[ "$ARGS" == *"pg_get_userbyid(c.relowner)"* ]]; then
    echo "${FAKE_CENSUS_BAD-0}"
    exit 0
  fi
  echo "FAKE DOCKER: unrecognised -tAc query: $ARGS" >&2
  exit 1
fi

# Leg C -- connect AS migrator (-h db). team-lead's own live measurement,
# run-5 (realrun5.clean.log), 2026-09-21, MEASURED on the production
# target: psql 17.6 over -h db, non-tty, inside `docker compose exec -T`,
# prints NO password-prompt text at all without `-W` -- it silently
# consumes the piped first stdin line as the password and attempts auth
# with it. `-W` forces a `Password: ` prompt regardless of tty/pipe state.
# This fixture now models a REAL auth check (compare the piped line
# against the known-correct value) rather than the old flag-only shape,
# because the real script now runs a POSITIVE CONTROL (a deliberately
# WRONG password) before the real connect, and a fixture that always
# "succeeds" regardless of the piped password could never distinguish the
# two calls or prove the control is load-bearing.
if [[ "$ARGS" == *"-h db"* ]]; then
  SCRIPT_IN="$(cat)"
  FIRST_LINE="$(printf '%s\n' "$SCRIPT_IN" | head -1)"
  HAS_W=0
  [[ "$ARGS" == *"-W"* ]] && HAS_W=1
  if [[ -n "${FAKE_CONNECT_CALL_LOG:-}" ]]; then
    printf '%s\n' "$ARGS" >> "$FAKE_CONNECT_CALL_LOG"
  fi
  PROMPT_LINE=""
  [[ "$HAS_W" -eq 1 ]] && PROMPT_LINE="Password: "
  REAL_PW="${FAKE_STORE_PW:-}"

  # team-lead's run-6 stop, item 7 (fixture-fidelity, optional) -- this
  # bypass now applies to ANY connect attempt (control OR real), checked
  # BEFORE the password comparison below, because if -W were somehow
  # silently non-functional (the hazard this models), that would be a
  # systemic breakage affecting every -h db call this process makes, not
  # something that differs between the control's wrong password and the
  # real credential. Previously gated inside "REAL_PW matched" only,
  # which meant the control probe in a "trust-path" scenario still saw
  # normal processing -- an inconsistent state a real breakage could
  # never actually produce.
  if [[ "${FAKE_NO_PASSWORD_PROMPT:-0}" == "1" ]]; then
    # Same shape as db-role-handoff.sh's own struck scenario: NO prompt
    # text at all EVEN WITH -W, the cleartext first-stdin-line consumed
    # as a bogus SQL statement instead. This realistically leaks
    # whatever was piped into the syntax-error echo (a real Postgres
    # error includes the offending token) -- with the scrub-before-
    # prompt-check ordering, the cleartext scrub now correctly fires
    # FIRST on this exact shape for the REAL connect (a STRONGER
    # outcome); for the CONTROL probe, the control's own exact-string
    # auth-failure check never finds it either, so both probes refuse.
    # FAKE_NO_PASSWORD_PROMPT_CLEAN below isolates the missing-prompt
    # guard with a non-leaking variant, same fix as db-role-handoff.sh's
    # own scenario 13/13b split (Sec C-1, PR #856).
    echo "psql:<stdin>:1: ERROR:  syntax error at or near \"$FIRST_LINE\""
    echo " current_user "
    echo "--------------"
    echo " migrator"
    exit 0
  fi
  if [[ "${FAKE_NO_PASSWORD_PROMPT_CLEAN:-0}" == "1" ]]; then
    echo "psql:<stdin>:1: ERROR:  syntax error at or near a piped credential (redacted by this fake, not by db-bootstrap.sh)"
    echo " current_user "
    echo "--------------"
    echo " migrator"
    exit 0
  fi

  if [[ -n "$REAL_PW" && "$FIRST_LINE" == "$REAL_PW" ]]; then
    # The REAL credential was piped -- this is the real connect attempt
    # (whether or not a control call happened first).
    if [[ "${FAKE_ECHO_PW_IN_CONNECT:-0}" == "1" ]]; then
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "DEBUG (simulated transport bug): last line was $FIRST_LINE"
      echo " current_user "
      echo "--------------"
      echo " migrator"
      exit 0
    fi
    if [[ "${FAKE_WRONG_CURRENT_USER:-0}" == "1" ]]; then
      # Sec F-1b (PR #849 r2 review) -- everything else about this
      # connection is normal (prompt prints, no cleartext leak, exit 0),
      # but the row psql prints back for `select current_user;` names a
      # DIFFERENT role. Proves the current_user check fires on its own,
      # not merely because the (absent, here) missing-prompt guard also
      # would have.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo " current_user "
      echo "--------------"
      echo " postgres"
      exit 0
    fi
    if [[ "${FAKE_CONNECT_FAIL:-0}" == "1" ]]; then
      # A genuine password-authenticated connection failing for an
      # UNRELATED reason (DB unreachable after the prompt, etc) --
      # distinct from a wrong-password failure below.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: connection failed" >&2
      exit 2
    fi
    [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
    echo " current_user "
    echo "--------------"
    echo " migrator"
    exit 0
  else
    # Wrong/unknown password (the trust-path CONTROL's own deliberately-
    # wrong value, or REAL_PW unset). Real psql behavior: auth failure,
    # unless a dedicated override models the actual hazards the control
    # exists to catch.
    if [[ "${FAKE_ECHO_PW_IN_CONTROL:-0}" == "1" ]]; then
      # Sec F-1 (PR #858 review) -- the CONTROL's own scrub
      # (`grep -qF -- "$PW"` against $CONTROL_OUT) had no scenario:
      # striking it left the whole suite green. Models a hypothetical
      # transport/debug-print bug that leaks the REAL credential into the
      # control probe's own output even though the control never sent it
      # -- the control's own scrub is what has to catch this, since the
      # control's exact-string auth-failure check alone would not.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "DEBUG (simulated transport bug): real value was $REAL_PW"
      echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"migrator\"" >&2
      exit 2
    fi
    if [[ "${FAKE_CONTROL_SUCCEEDS:-0}" == "1" ]]; then
      # The hazard the control exists to catch: a trust rule authenticates
      # ANY password, including a wrong one.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo " current_user "
      echo "--------------"
      echo " migrator"
      exit 0
    fi
    if [[ "${FAKE_CONTROL_WRONG_ERROR:-0}" == "1" ]]; then
      # Fails, but NOT with "password authentication failed" -- some
      # other error (DNS, compose, protocol) the control must also treat
      # as inconclusive, never as "good enough" proof of password auth.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: could not translate host name \"db\" to address: Name or service not known" >&2
      exit 2
    fi
    if [[ "${FAKE_CONTROL_WRONG_ROLE_ERROR:-0}" == "1" ]]; then
      # team-lead's run-6 stop, item 5a -- a DIFFERENT role's own auth
      # failure text, never "migrator". Proves the role-specific string
      # match is load-bearing: a role-agnostic `grep -qF "password
      # authentication failed"` would have wrongly ACCEPTED this.
      [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
      echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"some_other_role\"" >&2
      exit 2
    fi
    [[ -n "$PROMPT_LINE" ]] && echo "$PROMPT_LINE"
    echo "psql: error: connection to server at \"db\" (10.0.0.5), port 5432 failed: FATAL:  password authentication failed for user \"migrator\"" >&2
    exit 2
  fi
fi

# Phase 2 -- supabase db push, inside the migrator container
if [[ "$ARGS" == *"exec -T migrator sh -c"* ]]; then
  if [[ "${FAKE_PUSH_FAIL:-0}" == "1" ]]; then
    echo "supabase db push: error: connection refused" >&2
    exit 1
  fi
  echo "Applying migration 118_migrator_role.sql..."
  if [[ "${FAKE_PUSH_NO_COMPLETION_LINE:-0}" != "1" ]]; then
    echo "Finished supabase db push"
  fi
  [[ -n "${FAKE_MARKER_FILE:-}" ]] && touch "$FAKE_MARKER_FILE" 2>/dev/null
  exit 0
fi

# Leg A / Leg E -- both go through `docker exec coolify php artisan
# tinker --execute=...` against MIGRATOR_DB_PASSWORD. Sec F-3 (PR #859
# review) -- routed on an explicit `/* probe:<name> */` marker the real
# script's own tinker string carries, never on which Eloquent accessor
# or expression it happens to use (that discriminator is incidental and
# has already broken once elsewhere in this repo when a new read's shape
# collided with an existing one) -- production is free to change HOW a
# probe computes its answer without silently retargeting this fake.
if [[ "$ARGS" == *"tinker --execute"* && "$ARGS" == *"MIGRATOR_DB_PASSWORD"* ]]; then
  if [[ "$ARGS" == *"probe:readback-hash"* ]]; then
    # Leg E: sanity re-read (count|hash).
    if [[ -n "${FAKE_READBACK_COUNT:-}" ]]; then
      echo "${FAKE_READBACK_COUNT}"
      exit 0
    fi
    if [[ "${FAKE_READBACK_DIVERGE:-0}" == "1" ]]; then
      echo "1|0000000000000000"
      exit 0
    fi
    if [[ "${FAKE_READBACK_EMPTY:-0}" == "1" ]]; then
      # team-lead's run-6 stop, item 8 -- the row exists (count=1) but its
      # value is empty (an empty compose-parse placeholder, or the store
      # went empty between leg A's read and now).
      echo "1|EMPTY"
      exit 0
    fi
    if [[ -n "${FAKE_STORE_PW:-}" ]]; then
      HASH="$(printf '%s' "$FAKE_STORE_PW" | sha256sum | cut -c1-16)"
      echo "1|$HASH"
    else
      echo "0"
    fi
    exit 0
  elif [[ "$ARGS" == *"probe:migrator-value"* ]]; then
    # Leg A: initial read -- echo the raw store value (empty string
    # models "store holds no MIGRATOR_DB_PASSWORD").
    printf '%s' "${FAKE_STORE_PW:-}"
    exit 0
  else
    echo "FAKE DOCKER: unrecognized tinker probe -- no /* probe:<name> */ marker matched. ARGS: $ARGS" >&2
    exit 1
  fi
fi

# Everything else sharing "-v ON_ERROR_STOP=1 -U supabase_admin -d
# postgres" (no -tAc, no -h db) -- leg A's \password script, roles.sql,
# auth-grants.sql, role-comment files, post-step-vault-view.sql, and the
# engine-backstop REVOKEs. All distinguished by their OWN stdin content,
# read via psql_admin_file() (a local file piped over ssh's stdin) or a
# literal nested heredoc (leg A, the REVOKEs) -- never by call order.
if [[ "$ARGS" == *"-v ON_ERROR_STOP=1"* ]]; then
  SCRIPT_IN="$(cat)"
  if printf '%s' "$SCRIPT_IN" | grep -qF '\password migrator'; then
    echo 'Enter new password for user "migrator": '
    echo "Enter it again: "
    if [[ "${FAKE_LEG_A_RC_LEAK:-0}" == "1" ]]; then
      # Sec F-2b (PR #849 r3 review) -- models the exact trust-path-not-
      # consumed hazard: \password's two piped PW lines get parsed as SQL
      # instead of consumed as password input, producing a syntax error
      # whose message embeds the raw credential, with a non-zero exit
      # (-v ON_ERROR_STOP=1, Sec F-1). This is the case that proved the
      # OLD guard order (RC check first, printing $OUT raw, THEN the
      # scrub) disclosed the credential on a real failure.
      PW_LINE="$(printf '%s\n' "$SCRIPT_IN" | sed -n '2p')"
      echo "psql:<stdin>:1: ERROR:  syntax error at or near \"$PW_LINE\""
      exit 3
    fi
    if [[ "${FAKE_MISMATCH:-0}" == "1" ]]; then
      echo "Passwords didn't match."
      exit 0
    fi
    if [[ "${FAKE_ECHO_PASSWORD_IN_OUTPUT:-0}" == "1" ]]; then
      printf '%s\n' "$SCRIPT_IN" | sed -n '2p'
    fi
    exit 0
  fi
  if printf '%s' "$SCRIPT_IN" | grep -qF "revoke create on schema pfin from migrator"; then
    if [[ "${FAKE_REVOKE_FAIL:-0}" == "1" ]]; then echo "psql: error: revoke failed" >&2; exit 1; fi
    exit 0
  fi
  if printf '%s' "$SCRIPT_IN" | grep -qF "FIXTURE_ROLES_SQL_MARKER"; then
    if [[ "${FAKE_ROLES_FAIL:-0}" == "1" ]]; then echo "psql: error: roles.sql failed" >&2; exit 1; fi
    echo "CREATE ROLE"
    exit 0
  fi
  if printf '%s' "$SCRIPT_IN" | grep -qF "FIXTURE_AUTH_GRANTS_MARKER"; then
    if [[ "${FAKE_AUTH_GRANTS_FAIL:-0}" == "1" ]]; then echo "psql: error: auth-grants.sql failed" >&2; exit 1; fi
    echo "GRANT"
    exit 0
  fi
  if printf '%s' "$SCRIPT_IN" | grep -qF "FIXTURE_VAULT_VIEW_MARKER"; then
    if [[ "${FAKE_VAULT_VIEW_FAIL:-0}" == "1" ]]; then echo "psql: error: post-step-vault-view.sql failed" >&2; exit 1; fi
    echo "CREATE VIEW"
    exit 0
  fi
  if printf '%s' "$SCRIPT_IN" | grep -qE "FIXTURE_(055|118)_MARKER"; then
    if [[ "${FAKE_ROLE_COMMENT_FAIL:-0}" == "1" ]]; then echo "psql: error: role-comment file failed" >&2; exit 1; fi
    echo "COMMENT"
    exit 0
  fi
  echo "FAKE DOCKER: -v ON_ERROR_STOP=1 call with unrecognised stdin content" >&2
  exit 1
fi

echo "FAKE DOCKER: unrecognised invocation: $ARGS" >&2
exit 1
EOF
chmod +x "$FAKE_BIN/docker"

# Fake `ssh` -- same shape as the sibling fences' own; forwards every
# FAKE_* var in BOTH the bash -s branch and the plain-command branch
# (db-bootstrap.sh's psql_admin_file() calls docker directly from the
# PLAIN-command branch, via a local file redirected onto ssh's own
# stdin).
cat > "$FAKE_BIN/ssh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${FAKE_BOX_UNREACHABLE:-0}" == "1" ]]; then
  echo "ssh: connect to host 127.0.0.1 port 22: Connection refused" >&2
  exit 255
fi
LAST_PROBE="\${@: -1}"
if [[ "\$LAST_PROBE" == "true" ]]; then
  exit 0
fi
if [[ "\$*" == *"test -s /root/.pfin/coolify.env"* ]]; then
  exit 0
fi
FAKE_VARS=(FAKE_CURL_LOG FAKE_CURL_MODE FAKE_MIGRATOR_STATE FAKE_BOOTSTRAP_COMPLETE FAKE_CENSUS_BAD \\
  FAKE_PUSH_FAIL FAKE_PUSH_NO_COMPLETION_LINE FAKE_MISMATCH FAKE_ECHO_PASSWORD_IN_OUTPUT FAKE_REVOKE_FAIL \\
  FAKE_ROLES_FAIL FAKE_AUTH_GRANTS_FAIL FAKE_VAULT_VIEW_FAIL FAKE_ROLE_COMMENT_FAIL \\
  FAKE_MARKER_FILE FAKE_POST_PUSH_BOOTSTRAP FAKE_LEG_B_STATE FAKE_CONNECT_FAIL FAKE_NO_PASSWORD_PROMPT \\
  FAKE_ECHO_PW_IN_CONNECT FAKE_WRONG_CURRENT_USER FAKE_READBACK_COUNT FAKE_READBACK_DIVERGE FAKE_READBACK_EMPTY FAKE_STORE_PW \
  FAKE_LEG_A_RC_LEAK FAKE_BOOTSTRAP_READ_FAIL FAKE_MIGRATOR_STATE_READ_FAIL \
  FAKE_CONTROL_SUCCEEDS FAKE_CONTROL_WRONG_ERROR FAKE_CONTROL_WRONG_ROLE_ERROR FAKE_ECHO_PW_IN_CONTROL FAKE_CONNECT_CALL_LOG FAKE_NO_PASSWORD_PROMPT_CLEAN)
FORWARD=()
for v in "\${FAKE_VARS[@]}"; do
  FORWARD+=("\$v=\${!v:-}")
done
LAST="\${@: -1}"
if [[ "\$LAST" == "-s" || "\$LAST" == *" bash -s" ]]; then
  CMDLINE="\$LAST"
  [[ "\$CMDLINE" == "-s" ]] && CMDLINE="bash -s"
  CMDLINE="\$(printf '%s' "\$CMDLINE" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  REWRITTEN="\$(sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
  env PATH="$FAKE_BIN:\$PATH" "\${FORWARD[@]}" bash -c "\$CMDLINE" <<< "\$REWRITTEN"
  exit \$?
fi
CMD="\${@: -1}"
CMD_REWRITTEN="\$(printf '%s' "\$CMD" | sed 's#/root/\.pfin#$FAKE_ROOT_PFIN#g')"
env PATH="$FAKE_BIN:\$PATH" "\${FORWARD[@]}" bash -c "\$CMD_REWRITTEN"
EOF
chmod +x "$FAKE_BIN/ssh"

run_scenario() {
  # run_scenario <desc> <expect_exit> <extra_flag> <curl_mode> <migrator_state> <bootstrap_complete> <census_bad> <push_fail> <push_no_completion> <mismatch> <echo_pw> <roles_fail> <vault_view_fail> <post_push_bootstrap> <leg_b_state> <connect_fail> <no_password_prompt> <echo_pw_in_connect> <wrong_current_user> <readback_count> <readback_diverge> <store_pw> <leg_a_rc_leak> [bootstrap_read_fail] [migrator_state_read_fail] [control_succeeds] [control_wrong_error]
  local desc="$1" expect_exit="$2" extra_flag="$3" curl_mode="$4" migrator_state="$5" bootstrap_complete="$6" \
        census_bad="$7" push_fail="$8" push_no_completion="$9" mismatch="${10}" echo_pw="${11}" roles_fail="${12}" \
        vault_view_fail="${13}" post_push_bootstrap="${14}" leg_b_state="${15}" connect_fail="${16}" \
        no_password_prompt="${17}" echo_pw_in_connect="${18}" wrong_current_user="${19}" readback_count="${20}" \
        readback_diverge="${21}" store_pw="${22}" leg_a_rc_leak="${23}" bootstrap_read_fail="${24:-0}" \
        migrator_state_read_fail="${25:-0}" control_succeeds="${26:-0}" control_wrong_error="${27:-0}" no_password_prompt_clean="${28:-0}" control_wrong_role_error="${29:-0}" echo_pw_in_control="${30:-0}" readback_empty="${31:-0}"
  local log="$WORK/curl.log.$$.$RANDOM"
  local marker="$WORK/push_marker.$$.$RANDOM"
  # Sec/self-found bug: `OUT="$(run_scenario ...)"` forks a SUBSHELL --
  # an assignment made HERE would never survive back to the caller. Callers
  # that need to inspect this log after the call must pre-set
  # CONNECT_CALL_LOG themselves before invoking run_scenario (inherited
  # INTO the subshell, so this line only supplies a default when they
  # have not).
  CONNECT_CALL_LOG="${CONNECT_CALL_LOG:-$WORK/connect.log.$$.$RANDOM}"
  : > "$log"
  : > "$CONNECT_CALL_LOG"
  set +e
  # shellcheck disable=SC2086
  AUTOMATION_KEY=/dev/null REPO_ROOT="$FIXTURE_REPO" \
    PATH="$FAKE_BIN:$PATH" FAKE_CURL_LOG="$log" FAKE_CURL_MODE="$curl_mode" \
    FAKE_MIGRATOR_STATE="$migrator_state" FAKE_BOOTSTRAP_COMPLETE="$bootstrap_complete" FAKE_CENSUS_BAD="$census_bad" \
    FAKE_PUSH_FAIL="$push_fail" FAKE_PUSH_NO_COMPLETION_LINE="$push_no_completion" \
    FAKE_MISMATCH="$mismatch" FAKE_ECHO_PASSWORD_IN_OUTPUT="$echo_pw" \
    FAKE_ROLES_FAIL="$roles_fail" FAKE_VAULT_VIEW_FAIL="$vault_view_fail" \
    FAKE_MARKER_FILE="$marker" FAKE_POST_PUSH_BOOTSTRAP="$post_push_bootstrap" \
    FAKE_LEG_B_STATE="$leg_b_state" FAKE_CONNECT_FAIL="$connect_fail" FAKE_NO_PASSWORD_PROMPT="$no_password_prompt" \
    FAKE_ECHO_PW_IN_CONNECT="$echo_pw_in_connect" FAKE_WRONG_CURRENT_USER="$wrong_current_user" \
    FAKE_READBACK_COUNT="$readback_count" FAKE_READBACK_DIVERGE="$readback_diverge" FAKE_READBACK_EMPTY="$readback_empty" FAKE_STORE_PW="$store_pw" \
    FAKE_LEG_A_RC_LEAK="$leg_a_rc_leak" \
    FAKE_BOOTSTRAP_READ_FAIL="$bootstrap_read_fail" FAKE_MIGRATOR_STATE_READ_FAIL="$migrator_state_read_fail" \
    FAKE_CONTROL_SUCCEEDS="$control_succeeds" FAKE_CONTROL_WRONG_ERROR="$control_wrong_error" \
    FAKE_CONTROL_WRONG_ROLE_ERROR="$control_wrong_role_error" FAKE_ECHO_PW_IN_CONTROL="$echo_pw_in_control" \
    FAKE_NO_PASSWORD_PROMPT_CLEAN="$no_password_prompt_clean" \
    FAKE_CONNECT_CALL_LOG="$CONNECT_CALL_LOG" \
    bash "$TARGET_SH" $extra_flag < /dev/null > "$WORK/out.$$" 2>&1
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
    echo "FAIL: [$desc] unexpectedly contained '$needle' -- a phase step ran that should have been skipped as a no-op." >&2
    return 1
  fi
  return 0
}

FAIL=0

# 1. ALREADY-BOOTSTRAPPED-CLEAN
CONNECT_CALL_LOG="$WORK/connect-pin.1.$$"
: > "$CONNECT_CALL_LOG"
OUT1="$(run_scenario "already-bootstrapped-clean: no-op VERIFIED" 0 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "already-bootstrapped-clean" "${OUT1:-}" "VERIFIED, nothing to do" || FAIL=1
assert_output_lacks "already-bootstrapped-clean" "${OUT1:-}" "roles.sql applied" || FAIL=1
# team-lead's queued Sec item 2 -- the control's own observed-fact OK
# line is load-bearing evidence (not decoration): pin it on a happy path
# so deleting it from the real script turns this scenario RED.
assert_output_contains "already-bootstrapped-clean" "${OUT1:-}" "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"migrator\"'" || FAIL=1
# team-lead's run-5 fix (2026-09-21) -- -W PINNED FROM THE LOGGED ARGV,
# not just inferred from behavior: every -h db call this scenario made
# (the trust-path control AND the real connect) must carry -W. Deleting
# -W from the real script must turn this RED even if some other
# behavioral assertion happened not to notice.
if [[ ! -s "$CONNECT_CALL_LOG" ]]; then
  echo "FAIL: [already-bootstrapped-clean] no -h db connect calls were logged at all -- the -W pin has nothing to check." >&2
  FAIL=1
elif grep -qv -- '-W' "$CONNECT_CALL_LOG"; then
  echo "FAIL: [already-bootstrapped-clean] at least one -h db connect call did not carry -W:" >&2
  grep -v -- '-W' "$CONNECT_CALL_LOG" >&2
  FAIL=1
fi
unset CONNECT_CALL_LOG

# 2. ALREADY-BOOTSTRAPPED-CENSUS-BAD
OUT2="$(run_scenario "already-bootstrapped-census-bad: refuses" 1 "" clean "false|false" true 1 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "already-bootstrapped-census-bad" "${OUT2:-}" "the pfin_owner sweep broke somewhere" || FAIL=1

# 2a. ALREADY-BOOTSTRAPPED-STORE-ABSENT -- store_pw="" models "no
#     MIGRATOR_DB_PASSWORD (is_preview=false) on pfin-migrator".
OUT2A="$(run_scenario "already-bootstrapped-store-absent: FAILED (exit 2)" 2 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "" 0)" || FAIL=1
assert_output_contains "already-bootstrapped-store-absent" "${OUT2A:-}" "credential/store drift" || FAIL=1

# 2b. ALREADY-BOOTSTRAPPED-LEG-C-FAILS
OUT2B="$(run_scenario "already-bootstrapped-leg-c-fails: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 1 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "already-bootstrapped-leg-c-fails" "${OUT2B:-}" "store and the live role have drifted apart" || FAIL=1

# 2c. ALREADY-BOOTSTRAPPED-LEG-E-DIVERGES
OUT2C="$(run_scenario "already-bootstrapped-leg-e-diverges: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 1 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "already-bootstrapped-leg-e-diverges" "${OUT2C:-}" "changed between leg A's read and leg C's connect attempt" || FAIL=1

# 2c2. ALREADY-BOOTSTRAPPED-LEG-E-EMPTY (team-lead's run-6 stop, item 8) --
#      the re-read finds the row (count=1) but its value is empty --
#      pins the hardened, honest message instead of folding into the
#      generic hash-mismatch text (this site was already hash-bound and
#      structurally immune; this is a diagnostic-clarity hardening, not a
#      closed exploit).
OUT2C2="$(run_scenario "already-bootstrapped-leg-e-empty: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "already-bootstrapped-leg-e-empty" "${OUT2C2:-}" "re-read resolved to an empty value" || FAIL=1

# 3. PARTIAL-STATE
OUT3="$(run_scenario "partial-state: refuses" 1 "" clean "true|true" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "partial-state" "${OUT3:-}" "PARTIAL bootstrap state" || FAIL=1

# 4. PREFLIGHT-NO-APPLY
OUT4="$(run_scenario "preflight-no-apply: exit 0, no phases run" 0 "" clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "preflight-no-apply" "${OUT4:-}" "re-run with --apply" || FAIL=1

# 5. PHASE1-ROLES-FAIL
OUT5="$(run_scenario "phase1-roles-fail: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 1 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "phase1-roles-fail" "${OUT5:-}" "supabase/roles.sql failed" || FAIL=1

# 6. STORE-EMPTY-REFUSES (Sec VETO-1 r2 -- PATH A precondition)
OUT6="$(run_scenario "store-empty: FAILED (exit 2)" 2 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "" 0)" || FAIL=1
assert_output_contains "store-empty" "${OUT6:-}" "run scripts/provision-migrator-app.sh first" || FAIL=1

# 7. CREDENTIAL-MISMATCH
OUT7="$(run_scenario "credential-mismatch: refuses" 1 --apply clean "false|false" false 0 0 0 1 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "credential-mismatch" "${OUT7:-}" "confirmation mismatch" || FAIL=1

# 8. CREDENTIAL-CLEARTEXT-LEAK
OUT8="$(run_scenario "credential-cleartext-leak: refuses" 1 --apply clean "false|false" false 0 0 0 0 1 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "credential-cleartext-leak" "${OUT8:-}" "cleartext value appeared" || FAIL=1

# 8b. LEG-A-NONZERO-WITH-CLEARTEXT-LEAK (Sec F-2b, PR #849 r3 review) --
#     psql exits NON-ZERO (the trust-path-not-consumed hazard: \password's
#     two piped PW lines parsed as SQL instead, and -v ON_ERROR_STOP=1,
#     Sec F-1, turns that into a failing exit) AND the credential appears
#     in that SAME captured output. Must refuse via the cleartext scrub --
#     and the scrub must run BEFORE the RC-failure branch ever prints $OUT
#     raw. Distinct from scenario 8, which only proves the scrub on an
#     exit-0 psql; this is the exact branch the OLD guard order (RC check
#     first, print $OUT raw, THEN scrub) left completely unscrubbed --
#     the assert_output_lacks below fails on that old order, since the
#     "psql handoff script exited $RC: $OUT" message would carry the raw
#     credential.
OUT8B="$(run_scenario "leg-a-nonzero-with-cleartext-leak: refuses via the scrub, never prints the value" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 1)" || FAIL=1
assert_output_contains "leg-a-nonzero-with-cleartext-leak" "${OUT8B:-}" "cleartext value appeared in psql's own captured output" || FAIL=1
assert_output_lacks "leg-a-nonzero-with-cleartext-leak" "${OUT8B:-}" "$FIXED_STORE_PW" || FAIL=1

# 9. LEG-B-CATALOG-VERIFY-MISMATCH
OUT9="$(run_scenario "leg-b-catalog-verify-mismatch: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "false|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-b-catalog-verify-mismatch" "${OUT9:-}" "post-handoff catalog verify expected 'true|true'" || FAIL=1

# 10. LEG-C-CONNECT-FAIL
OUT10="$(run_scenario "leg-c-connect-fail: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 1 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-c-connect-fail" "${OUT10:-}" "did not take effect end to end" || FAIL=1

# 11. LEG-C-TRUST-PATH-NO-PROMPT (team-lead's run-6 stop, item 7 --
#     fixture-fidelity: the bypass now applies to ANY connect attempt,
#     control included, matching that a real -W breakage would be
#     systemic, not selective) -- the CONTROL probe hits this shape
#     FIRST, before the real connect is ever attempted: its own
#     exact-string auth-failure check never finds it (the output is a
#     syntax error, not "password authentication failed"), so the
#     script refuses at the control -- same message as the dedicated
#     leg-c-trust-path scenario (#21c), now reached via a different
#     fixture path (a "-W silently broken" hazard, not "the box is
#     genuinely on a trust rule"), proving both hazards converge on the
#     same, correct refusal.
OUT11="$(run_scenario "leg-c-trust-path-no-prompt: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 1 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-c-trust-path-no-prompt" "${OUT11:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 11b. LEG-C-TRUST-PATH-NO-PROMPT-CLEAN -- the same bypass, same
#      control-refusal outcome (the "clean" non-leaking variant no
#      longer isolates a different guard now that the control sees the
#      bypass first regardless of leak-shape; kept for its own
#      independent coverage of the FAKE_NO_PASSWORD_PROMPT_CLEAN path).
OUT11B="$(run_scenario "leg-c-trust-path-no-prompt-clean: refuses at the control" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-trust-path-no-prompt-clean" "${OUT11B:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 12. LEG-C-CLEARTEXT-LEAK-IN-CONNECT
OUT12="$(run_scenario "leg-c-cleartext-leak-in-connect: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 1 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-c-cleartext-leak-in-connect" "${OUT12:-}" "cleartext value appeared in the connect-as-migrator step" || FAIL=1

# 13. LEG-C-WRONG-CURRENT-USER (Sec F-1b, PR #849 r2 review)
OUT13="$(run_scenario "leg-c-wrong-current-user: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 1 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-c-wrong-current-user" "${OUT13:-}" "current_user did not echo back 'migrator'" || FAIL=1

# 14. LEG-E-READBACK-COUNT-MISMATCH
OUT14="$(run_scenario "leg-e-readback-count-mismatch: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 0 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-e-readback-count-mismatch" "${OUT14:-}" "expected exactly 1" || FAIL=1

# 15. LEG-E-READBACK-DIVERGE (Sec VETO-1 r2's own named scenario)
OUT15="$(run_scenario "leg-e-readback-diverge: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 1 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "leg-e-readback-diverge" "${OUT15:-}" "no longer hash-matches" || FAIL=1

# 15b. LEG-E-READBACK-EMPTY -- same hardening at Phase-1's own leg E.
OUT15B="$(run_scenario "leg-e-readback-empty: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "leg-e-readback-empty" "${OUT15B:-}" "readback resolved to an empty value" || FAIL=1

# 16. PHASE2-PUSH-FAILS
OUT16="$(run_scenario "phase2-push-fails: refuses" 1 --apply clean "false|false" false 0 1 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "phase2-push-fails" "${OUT16:-}" "supabase db push exited" || FAIL=1

# 17. PHASE2-NO-COMPLETION-LINE
OUT17="$(run_scenario "phase2-no-completion-line: refuses" 1 --apply clean "false|false" false 0 0 1 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "phase2-no-completion-line" "${OUT17:-}" "incomplete run, not a pass" || FAIL=1

# 18. PHASE2-CENSUS-BAD-AFTER-PUSH
OUT18="$(run_scenario "phase2-census-bad-after-push: refuses" 1 --apply clean "false|false" false 1 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "phase2-census-bad-after-push" "${OUT18:-}" "broke somewhere in the apply" || FAIL=1

# 19. PHASE2-BOOTSTRAP-NOT-COMPLETE-AFTER-PUSH -- census clean but the
#     118 ledger row still absent after a "successful" push.
OUT19="$(run_scenario "phase2-bootstrap-not-complete-after-push: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 false "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "phase2-bootstrap-not-complete-after-push" "${OUT19:-}" "did not actually land 118" || FAIL=1

# 20. PHASE3-VAULT-VIEW-FAILS -- everything up to Phase 2 verify passes;
#     need BOOTSTRAP_COMPLETE to read true on the POST-push read but
#     false on preflight. FAKE_BOOTSTRAP_COMPLETE is static per-run, so
#     instead force it "true" throughout (the fixture never actually
#     distinguishes pre/post-push reads) -- preflight sees "true" and
#     would take the ALREADY-BOOTSTRAPPED branch instead of reaching
#     Phase 1 at all. Route around this by using
#     FAKE_MIGRATOR_STATE="true|true" WITHOUT bootstrap_complete=true on
#     preflight is the PARTIAL-STATE branch (scenario 3) -- so Phase 3
#     in isolation cannot be reached through the CLI's own preflight
#     gate with a single static fixture value. Exercised instead as a
#     source-literal pin: the real script's Phase 3 call site itself.
# The single-quoted pattern below is a LITERAL grep needle (matching
# db-bootstrap.sh's own source text, "$REPO_ROOT" included verbatim),
# not a string meant to expand here.
# shellcheck disable=SC2016
if grep -qF 'psql_admin_file "$REPO_ROOT/supabase/post-step-vault-view.sql" || die "supabase/post-step-vault-view.sql failed' "$TARGET_SH"; then
  echo "OK: [phase3-vault-view-fail-path: source pin] $TARGET_SH's Phase 3 call still wraps post-step-vault-view.sql in a || die guard naming it by name." >&2
else
  echo "FAIL: [phase3-vault-view-fail-path] $TARGET_SH no longer wraps its Phase 3 call in a || die guard naming 'post-step-vault-view.sql failed' -- this fence cannot reach Phase 3 through the CLI alone (preflight's bootstrap_complete gate is static per fixture run, see the comment above), so this source-literal pin is the only thing standing between a silently-removed Phase 3 guard and a false green." >&2
  FAIL=1
fi

# 21. HAPPY-PATH-FULL-APPLY -- legs A/B/C/E all pass together; leg A's
#     read and leg E's re-read both resolve to FIXED_STORE_PW.
CONNECT_CALL_LOG="$WORK/connect-pin.21.$$"
: > "$CONNECT_CALL_LOG"
OUT21="$(run_scenario "happy-path-full-apply: succeeds, absent role-comment files skipped" 0 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "happy-path-full-apply" "${OUT21:-}" "Phase 1 -> 2 -> 3 complete" || FAIL=1
assert_output_contains "happy-path-full-apply" "${OUT21:-}" "migrator: LOGIN + password set from pfin-migrator's own existing MIGRATOR_DB_PASSWORD" || FAIL=1
assert_output_contains "happy-path-full-apply" "${OUT21:-}" "OK: trust-path control: a deliberately WRONG password was refused with 'password authentication failed for user \"migrator\"'" || FAIL=1
for f in 116_pfin_provider_sync_role 117_pfin_etl_role_comment_c1_reattribution 119_migrator_role_comment_amendment3_recitation; do
  assert_output_contains "happy-path-full-apply (skip $f)" "${OUT21:-}" "$f.sql not present in supabase/migrations/ -- skipping" || FAIL=1
done
# -W PINNED FROM THE LOGGED ARGV (Phase-1 leg C's own connect calls).
if [[ ! -s "$CONNECT_CALL_LOG" ]]; then
  echo "FAIL: [happy-path-full-apply] no -h db connect calls were logged at all -- the -W pin has nothing to check." >&2
  FAIL=1
elif grep -qv -- '-W' "$CONNECT_CALL_LOG"; then
  echo "FAIL: [happy-path-full-apply] at least one -h db connect call did not carry -W:" >&2
  grep -v -- '-W' "$CONNECT_CALL_LOG" >&2
  FAIL=1
fi
unset CONNECT_CALL_LOG

# 21a. ALREADY-BOOTSTRAPPED-CONTROL-SUCCEEDS (team-lead, run-5, 2026-09-21)
#      -- the trust-path control (a deliberately WRONG password) succeeds
#      instead of failing -- the exact hazard the control exists to
#      catch (a trust rule authenticating ANY password) -- refuses,
#      never proceeding to try the real credential.
OUT21A="$(run_scenario "already-bootstrapped-control-succeeds: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 1)" || FAIL=1
assert_output_contains "already-bootstrapped-control-succeeds" "${OUT21A:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21b. ALREADY-BOOTSTRAPPED-CONTROL-WRONG-ERROR -- the control fails, but
#      not with "password authentication failed" (DNS/compose/protocol
#      error) -- refuses, never treated as "good enough" proof.
OUT21B="$(run_scenario "already-bootstrapped-control-wrong-error: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 1)" || FAIL=1
assert_output_contains "already-bootstrapped-control-wrong-error" "${OUT21B:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21b2. ALREADY-BOOTSTRAPPED-CONTROL-WRONG-ROLE (team-lead's run-6 stop,
#       item 5a, 2026-09-21) -- the control DOES fail with the exact text
#       "password authentication failed", but naming a DIFFERENT role --
#       refuses. Proves the role-specific match is load-bearing: a
#       role-agnostic grep would have wrongly ACCEPTED this.
OUT21B2="$(run_scenario "already-bootstrapped-control-wrong-role: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "already-bootstrapped-control-wrong-role" "${OUT21B2:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21b3. ALREADY-BOOTSTRAPPED-CONTROL-CLEARTEXT-LEAK (Sec F-1, PR #858
#       review) -- the CONTROL's own scrub (`grep -qF -- "$PW"` against
#       $CONTROL_OUT) had NO scenario: striking it left the whole suite
#       green. Models a hypothetical transport/debug-print bug that
#       leaks the REAL credential into the control probe's own output
#       even though the control never sent it -- the control's own scrub
#       is what has to catch this; its exact-string auth-failure check
#       alone would not (this fake's control probe still fails with the
#       right role-qualified text).
OUT21B3="$(run_scenario "already-bootstrapped-control-cleartext-leak: refuses" 1 "" clean "false|false" true 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "already-bootstrapped-control-cleartext-leak" "${OUT21B3:-}" "cleartext value appeared in the trust-path control's own captured output" || FAIL=1
assert_output_lacks "already-bootstrapped-control-cleartext-leak" "${OUT21B3:-}" "$FIXED_STORE_PW" || FAIL=1

# 21c. LEG-C-CONTROL-SUCCEEDS -- same strike against Phase-1's own leg C.
OUT21C="$(run_scenario "leg-c-control-succeeds: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-succeeds" "${OUT21C:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21d. LEG-C-CONTROL-WRONG-ERROR -- same, non-auth-failure error shape.
OUT21D="$(run_scenario "leg-c-control-wrong-error: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-wrong-error" "${OUT21D:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21d2. LEG-C-CONTROL-WRONG-ROLE -- same strike against Phase-1's own leg C.
OUT21D2="$(run_scenario "leg-c-control-wrong-role: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-wrong-role" "${OUT21D2:-}" "did not fail with the exact text 'password authentication failed for user \"migrator\"'" || FAIL=1

# 21d3. LEG-C-CONTROL-CLEARTEXT-LEAK -- same strike against Phase-1's own leg C.
OUT21D3="$(run_scenario "leg-c-control-cleartext-leak: refuses" 1 --apply clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0 0 0 0 0 1)" || FAIL=1
assert_output_contains "leg-c-control-cleartext-leak" "${OUT21D3:-}" "cleartext value appeared in the trust-path control's own captured output" || FAIL=1
assert_output_lacks "leg-c-control-cleartext-leak" "${OUT21D3:-}" "$FIXED_STORE_PW" || FAIL=1

# 22. RESOURCE-ABSENT (measured exit 1, not the header's documented 2 --
#     see the note in the header comment above)
OUT22="$(run_scenario "resource-absent: refuses" 1 --apply migrator-absent "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "resource-absent" "${OUT22:-}" "expected exactly one application named" || FAIL=1

# 23. UNKNOWN-FLAG
OUT23="$(run_scenario "unknown-flag: rejected" 2 --bogus clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0)" || FAIL=1
assert_output_contains "unknown-flag" "${OUT23:-}" "unknown flag" || FAIL=1

# 25-29. FAIL-OPEN SWEEP (team-lead's live --from standup finding,
#    2026-09-21) -- the OLD bootstrap_complete read used
#    `2>/dev/null || echo 'f'`: a FAILED read was silently converted
#    into the specific answer "not bootstrapped", which this script then
#    trusted and proceeded to a full re-apply against an already-
#    bootstrapped, live database. Every gating read in this file now
#    goes through the shared read_gate() helper -- these five scenarios
#    prove BOTH failure modes (the read itself fails; the read succeeds
#    but returns unparseable output) refuse (exit 2, "cannot determine
#    ... state"), never fall through to a specific guessed answer, on
#    the two reads team-lead named explicitly (bootstrap_complete,
#    migrator credential state) plus the ownership census read.
#  25. BOOTSTRAP-READ-FAILS -- the bootstrap_complete preflight read
#      itself fails (psql/ssh error, rc!=0) -> refuses, "could not read
#      bootstrap_complete".
OUT25="$(run_scenario "bootstrap-read-fails: refuses" 2 "" clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 1 0)" || FAIL=1
assert_output_contains "bootstrap-read-fails" "${OUT25:-}" "could not read bootstrap_complete" || FAIL=1

#  26. BOOTSTRAP-READ-GARBAGE -- the read succeeds (rc=0) but returns
#      neither "true" nor "false" -> refuses, "unparseable output",
#      never silently treated as either state.
OUT26="$(run_scenario "bootstrap-read-garbage: refuses" 2 "" clean "false|false" maybe 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0)" || FAIL=1
assert_output_contains "bootstrap-read-garbage" "${OUT26:-}" "bootstrap_complete read returned unparseable output" || FAIL=1

#  27. MIGRATOR-STATE-READ-GARBAGE -- the migrator credential state read
#      succeeds but returns neither empty (role absent) nor a
#      'true|false'-shaped pair -> refuses, "unparseable output".
OUT27="$(run_scenario "migrator-state-read-garbage: refuses" 2 "" clean garbage false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0)" || FAIL=1
assert_output_contains "migrator-state-read-garbage" "${OUT27:-}" "migrator credential state read returned unparseable output" || FAIL=1

#  28. CENSUS-READ-GARBAGE -- bootstrap_complete=true (the
#      ALREADY-BOOTSTRAPPED branch), but the ownership census read
#      returns non-numeric output -> refuses, "unparseable output",
#      never treated as census_bad=0 (a false VERIFIED).
OUT28="$(run_scenario "census-read-garbage: refuses" 2 "" clean "false|false" true notanumber 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 0)" || FAIL=1
assert_output_contains "census-read-garbage" "${OUT28:-}" "ownership census read returned unparseable output" || FAIL=1

#  29. MIGRATOR-STATE-READ-FAILS -- the migrator credential state read
#      itself fails (psql/ssh error, rc!=0) -> refuses, "could not read
#      migrator credential state".
OUT29="$(run_scenario "migrator-state-read-fails: refuses" 2 "" clean "false|false" false 0 0 0 0 0 0 0 true "true|true" 0 0 0 0 "" 0 "$FIXED_STORE_PW" 0 0 1)" || FAIL=1
assert_output_contains "migrator-state-read-fails" "${OUT29:-}" "could not read migrator credential state" || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more db-bootstrap.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all db-bootstrap.sh strike-proofs passed."
exit 0
