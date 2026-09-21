#!/usr/bin/env bash
#
# fence-github-ci-setup-strikes.sh -- offline strike-proof for
# scripts/github-ci-setup.sh's STRUCTURAL logic: precondition refusals
# (gh not authenticated, private key file absent), the variable
# read-back check, and the environment-reviewer read-back check (the
# Sec-ruled gate this script's whole job is to ensure exists).
# BACKLOG.md §7.36 item 73 (W-5).
#
# ⚠ WHAT THIS FENCE DOES NOT, AND CANNOT, PROVE -- stated, not glossed:
# whether the REAL GitHub API actually accepts this request shape for
# creating/updating a required-reviewer rule, whether `gh`'s own flags
# (--json, --jq, --body, --input) behave as documented, or whether the
# real CI_MIGRATE_SSH_PRIVATE_KEY secret this proves gets SET is the
# right key. tests/fixtures/ci/github-ci-setup/fake-gh returns CANNED
# responses; this fence proves the shell script's own control flow, not
# any live GitHub behavior.
#
# Scenarios:
#   1. HAPPY-PATH PREFLIGHT -- gh authenticated, repo resolves, nothing
#      written (no secret/variable/environment write call issued).
#   2. NOT-AUTHENTICATED-FAILS -- gh auth status fails -> precondition,
#      exit 2, before any other call.
#   3. PRIVATE-KEY-ABSENT-FAILS -- the derived private-key path does not
#      exist -> precondition, exit 2.
#   4. APPLY-HAPPY-PATH -- --apply: secret set, variable set (read-back
#      matches), environment PUT (read-back shows the reviewer) -> exit 0.
#   5. VARIABLE-READBACK-MISMATCH-REFUSES -- `gh variable set` "succeeds"
#      but the immediate read-back does not show the new value -> refuses.
#   6. ENV-READBACK-NO-REVIEWER-REFUSES -- the environment PUT "succeeds"
#      but the immediate read-back shows NO reviewer named -> refuses,
#      never reports success on an ungated environment.
#   7. EXISTING-DIFFERENT-REVIEWER-STILL-SUCCEEDS -- the environment
#      already has a DIFFERENT reviewer before this run -> this script
#      still succeeds (it adds/confirms the current user, never removes
#      an existing reviewer) as long as the post-PUT read-back shows the
#      current user named. Sec F-4b (PR #849 review) -- ALSO asserts the
#      pre-existing reviewer is STILL present in the final state, not
#      just that the script exits 0 (a naive single-element PUT would
#      also exit 0 while silently dropping it; confirmed by inversion
#      test this PR: reverting to that shape flips this scenario red).
#
# Exit 0 only if every scenario behaves exactly as specified above.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/ci/github-ci-setup"
SMOKE_SH="$REPO_ROOT/scripts/github-ci-setup.sh"

[[ -x "$FIXTURE_DIR/fake-gh" ]] || { echo "FATAL: $FIXTURE_DIR/fake-gh missing or not executable" >&2; exit 2; }
[[ -f "$SMOKE_SH" ]] || { echo "FATAL: $SMOKE_SH not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAKE_BIN="$WORK/bin"
mkdir -p "$FAKE_BIN"
ln -s "$FIXTURE_DIR/fake-gh" "$FAKE_BIN/gh"

run_case() {
  # run_case <desc> <expect_exit> <apply-flag-or-empty> <keypair-present:0|1> <gh_auth_rc> <env_exists:0|1> <env_reviewer_login-or-empty> <var_set_takes_effect:0|1> <env_put_takes_effect:0|1>
  local desc="$1" expect_exit="$2" apply_flag="$3" keypair_present="$4" gh_auth_rc="$5"
  local env_exists="$6" env_reviewer_login="$7" var_set_effect="$8" env_put_effect="$9"
  local case_dir="$WORK/case.$$.$RANDOM"
  local state_dir="$case_dir/state"
  mkdir -p "$case_dir" "$state_dir"
  printf 'CI_MIGRATE_SSH_PUBKEY=%s/ci_migrate.pub\nBOX_IP=127.0.0.1\n' "$case_dir" > "$case_dir/.env"
  if [[ "$keypair_present" == "1" ]]; then
    printf 'priv\n' > "$case_dir/ci_migrate"
  fi

  set +e
  # Intentional, on $apply_flag below: an empty apply_flag must vanish
  # entirely (zero args passed), not become one empty-string arg -- the
  # real script's own case-statement would reject that as "unknown flag".
  # shellcheck disable=SC2086
  REPO_ROOT="$case_dir" PATH="$FAKE_BIN:$PATH" FAKE_STATE_DIR="$state_dir" \
    FAKE_GH_AUTH_RC="$gh_auth_rc" FAKE_REPO_SLUG="owner/repo" \
    FAKE_REVIEWER_LOGIN="current-user" FAKE_REVIEWER_ID="999" \
    FAKE_SECRET_PRESENT=0 FAKE_VAR_INITIAL="1.2.3.4" \
    FAKE_ENV_EXISTS="$env_exists" FAKE_ENV_REVIEWER_LOGIN="$env_reviewer_login" \
    FAKE_VAR_SET_TAKES_EFFECT="$var_set_effect" FAKE_ENV_PUT_TAKES_EFFECT="$env_put_effect" \
    ENVIRONMENT_NAME="production-migrator" \
    bash "$SMOKE_SH" $apply_flag < /dev/null > "$case_dir/out.txt" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" != "$expect_exit" ]]; then
    echo "FAIL: [$desc] expected exit $expect_exit, got $rc" >&2
    echo "----- captured output -----" >&2
    cat "$case_dir/out.txt" >&2
    return 1
  fi
  echo "OK: [$desc] exit $rc as expected." >&2
  CASE_STATE_DIR="$state_dir"
  return 0
}

FAIL=0

# 1. HAPPY-PATH PREFLIGHT
run_case "happy-path preflight" 0 "" 1 0 0 "" 1 1 || FAIL=1
if [[ -n "${CASE_STATE_DIR:-}" ]] && [[ -f "$CASE_STATE_DIR/secret_set_called" || -f "$CASE_STATE_DIR/env_exists" ]]; then
  echo "FAIL: [happy-path preflight] a write call was issued despite no --apply" >&2
  FAIL=1
fi

# 2. NOT-AUTHENTICATED-FAILS
run_case "gh not authenticated fails, exit 2" 2 "" 1 1 0 "" 1 1 || FAIL=1

# 3. PRIVATE-KEY-ABSENT-FAILS
run_case "private key file absent fails, exit 2" 2 "" 0 0 0 "" 1 1 || FAIL=1

# 4. APPLY-HAPPY-PATH
run_case "apply happy-path: exit 0" 0 --apply 1 0 0 "" 1 1 || FAIL=1
if [[ -n "${CASE_STATE_DIR:-}" ]]; then
  [[ -f "$CASE_STATE_DIR/secret_set_called" ]] || { echo "FAIL: [apply happy-path] secret set was never called" >&2; FAIL=1; }
  [[ -f "$CASE_STATE_DIR/env_exists" ]] || { echo "FAIL: [apply happy-path] environment PUT was never called" >&2; FAIL=1; }
fi

# 5. VARIABLE-READBACK-MISMATCH-REFUSES
run_case "variable read-back mismatch refuses" 1 --apply 1 0 0 "" 0 1 || FAIL=1

# 6. ENV-READBACK-NO-REVIEWER-REFUSES
run_case "environment read-back shows no reviewer, refuses" 1 --apply 1 0 0 "" 1 0 || FAIL=1

# 7. EXISTING-DIFFERENT-REVIEWER-STILL-SUCCEEDS -- Sec F-4b (PR #849
#    review): assert the PRE-EXISTING reviewer actually SURVIVES the PUT
#    (is still present in the final state), not just that the script
#    exits 0 -- a naive single-element PUT would also exit 0 here (the
#    current user WOULD be added successfully) while silently dropping
#    "someone-else", and only this state-file assertion would catch that.
run_case "existing different reviewer does not block success" 0 --apply 1 0 1 "someone-else" 1 1 || FAIL=1
if [[ -n "${CASE_STATE_DIR:-}" ]]; then
  if [[ ! -f "$CASE_STATE_DIR/env_reviewers.json" ]]; then
    echo "FAIL: [existing-different-reviewer] no env_reviewers.json state was written -- the PUT never landed" >&2
    FAIL=1
  elif ! grep -q '"id": *777\|"id":777' "$CASE_STATE_DIR/env_reviewers.json"; then
    echo "FAIL: [existing-different-reviewer] the pre-existing reviewer (id 777, 'someone-else') did NOT survive the PUT -- final state: $(cat "$CASE_STATE_DIR/env_reviewers.json")" >&2
    FAIL=1
  elif ! grep -q '"id": *999\|"id":999' "$CASE_STATE_DIR/env_reviewers.json"; then
    echo "FAIL: [existing-different-reviewer] the current user (id 999) was never added -- final state: $(cat "$CASE_STATE_DIR/env_reviewers.json")" >&2
    FAIL=1
  else
    echo "OK: [existing-different-reviewer] both the pre-existing reviewer (777) and the current user (999) survive in the final PUT body." >&2
  fi
fi

if [[ $FAIL -ne 0 ]]; then
  echo "" >&2
  echo "FATAL: one or more github-ci-setup.sh strike-proofs did not behave as specified -- failing closed." >&2
  exit 1
fi

echo "OK: all github-ci-setup.sh strike-proofs passed."
exit 0
