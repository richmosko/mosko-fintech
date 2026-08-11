#!/bin/sh
# =============================================================================
# verify-shared-path-guard.sh — proof matrix for the shared-path commit guard
# in .husky/pre-commit. DevOps-owned. Added 2026-08-11.
#
# WHAT IT PROVES
#   The guard must distinguish six states. Passing only the permit cases proves
#   nothing: a guard that never fires passes all of them.
#
#     (c) shared checkout, on 'main'          -> PERMIT
#     (a) shared checkout, on a feature branch-> REFUSE   <- the load-bearing case
#     (d) same as (a) + escape hatch          -> PERMIT
#     (e) shared checkout, detached HEAD      -> REFUSE
#     (b) linked worktree, feature branch     -> PERMIT
#     (NEG CONTROL) same as (a), hook disarmed-> PERMIT
#
#   The negative control is the clause that tests the INSTRUMENT rather than the
#   guard: if (a) still refuses with the hook disarmed, then (a)'s refusal was
#   never attributable to the guard and the whole matrix is vacuous.
#
# HOW TO RUN  (safe: operates only on a scratch repo under /tmp)
#     sh scripts/verify-shared-path-guard.sh .husky/pre-commit
#   Exits 0 only if all six states are distinguished correctly.
#
# ⚠ NOT WIRED INTO CI. Two different watchers are in play here and they must not
#   be conflated — one is untestable in CI, the other is merely unwired:
#
#     (i) "Is the fence ARMED in this checkout?" — NOT CI-testable, and a job
#         claiming to test it would be theater. core.hooksPath is local git
#         config, NOT repo content; CI runs in a fresh clone where it is unset by
#         definition. Such a job could only assert that .husky/pre-commit EXISTS
#         — and that file was tracked on main from 2026-06-28 through six weeks
#         of this entire hook set being inert. It would have been GREEN for every
#         one of those weeks. A check that cannot fail on a real violation is
#         worse than no check: it reads as coverage. Do not add it.
#
#    (ii) "Does the guard LOGIC still distinguish the six states?" — this IS
#         testable. This harness is hermetic: it builds its own scratch repo and
#         sets its own core.hooksPath, so it does not depend on the ambient
#         config CI lacks. Run against a guard-less pre-commit it fails 2/6, so
#         it can fail on a real violation.
#
#   (ii) is nonetheless NOT wired as of 2026-08-11 — it would add a required
#   context, which needs its own F/CTO ratify. The honest consequence: the guard
#   has NO automated watcher today. Nothing re-runs this on change and a
#   discriminator regression would land silently. Run it by hand after ANY edit
#   to the guard block.
#
# WHY THE PRECONDITION ASSERTION EXISTS (do not remove it)
#   Two earlier versions of this harness reported confident verdicts about
#   states they never reached:
#     1. Arming the hook before the seed commit let the guard refuse the setup
#        itself; every later case ran against a repo with no 'main'.
#     2. Using ONE feature branch for both contexts meant the shared checkout
#        could not switch to it (already checked out in the worktree), so three
#        cases silently ran on 'main' and printed OK.
#   Both printed passing lines. The fix is general: a case that cannot confirm
#   it is in the state it claims to test must refuse to render a verdict rather
#   than report a pass. That is what try()'s PRECONDITION block does.
# =============================================================================
set -u

HOOKSRC="${1:-.husky/pre-commit}"
[ -f "$HOOKSRC" ] || { echo "usage: sh $0 <path-to-.husky/pre-commit>"; exit 2; }
HOOKSRC=$(cd "$(dirname "$HOOKSRC")" && pwd)/$(basename "$HOOKSRC")

ROOT=/tmp/mosko-guard-verify
rm -rf "$ROOT"; mkdir -p "$ROOT"
SHARED="$ROOT/shared"; WT="$ROOT/worktrees/agent"; HOOKS="$ROOT/hooks"
mkdir -p "$SHARED" "$HOOKS"
cp "$HOOKSRC" "$HOOKS/pre-commit"; chmod +x "$HOOKS/pre-commit"

# --- setup. The hook is armed only AFTER setup completes (see note above). ----
git init -q -b main "$SHARED"
git -C "$SHARED" config user.email guard@test.local
git -C "$SHARED" config user.name guard-test
echo seed > "$SHARED/f.txt"
git -C "$SHARED" add f.txt
git -C "$SHARED" commit -q -m seed
git -C "$SHARED" branch feature/shared      # shared-checkout cases
git -C "$SHARED" branch feature/wt          # worktree case (must be DISTINCT)
git -C "$SHARED" worktree add -q "$WT" feature/wt

git -C "$SHARED" rev-parse --verify -q main >/dev/null        || { echo "SETUP FAILED: no main";           exit 2; }
git -C "$SHARED" rev-parse --verify -q feature/shared >/dev/null || { echo "SETUP FAILED: no feature/shared"; exit 2; }
[ -d "$WT" ]                                                  || { echo "SETUP FAILED: no worktree";       exit 2; }
echo "setup OK — main + feature/shared + feature/wt + worktree present; hook not yet armed"
git -C "$SHARED" config core.hooksPath "$HOOKS"
echo

pass=0; fail=0
# try <label> <PERMIT|REFUSE> <path> <want_branch|__detached__> [ENV=VAL]
try() {
  label="$1"; expect="$2"; p="$3"; want="$4"; envv="${5:-}"
  got=$(git -C "$p" symbolic-ref --short -q HEAD || echo "__detached__")
  if [ "$got" != "$want" ]; then
    echo "[BAD ] $label"
    echo "         PRECONDITION FAILED: wanted '$want', repo is on '$got'."
    echo "         No verdict rendered — this case never reached the state it tests."
    fail=$((fail+1)); echo; return
  fi
  printf 'probe\n' >> "$p/f.txt"
  git -C "$p" add f.txt >/dev/null 2>&1
  if [ -n "$envv" ]; then out=$(cd "$p" && env "$envv" git commit -m t 2>&1); rc=$?
  else                    out=$(cd "$p" && git commit -m t 2>&1); rc=$?; fi
  [ $rc -eq 0 ] && actual=PERMIT || actual=REFUSE
  if [ "$actual" = "$expect" ]; then v="OK  "; pass=$((pass+1)); else v="BAD "; fail=$((fail+1)); fi
  echo "[$v] $label"
  echo "         context=$got  expected=$expect  actual=$actual  (git exit $rc)"
  [ "$actual" = "REFUSE" ] && echo "$out" | grep -E 'REFUSED' | sed 's/^/           | /'
  [ "$actual" = "PERMIT" ] && { echo "$out" | grep -E 'BYPASSED' | sed 's/^/           | /'; git -C "$p" reset -q --hard HEAD~1; }
  echo
}

echo "========== SHARED-PATH COMMIT GUARD — PROOF MATRIX =========="
echo "hook under test : $HOOKSRC"
echo

echo "--- (c) shared checkout on 'main' -> PERMIT ---"
try "shared + main" PERMIT "$SHARED" main

echo "--- (a) shared checkout on feature branch -> REFUSE   [load-bearing] ---"
git -C "$SHARED" checkout -q feature/shared
try "shared + feature/shared" REFUSE "$SHARED" feature/shared

echo "--- (d) escape hatch, same state as (a) -> PERMIT ---"
try "shared + feature/shared + MOSKO_ALLOW_SHARED_COMMIT=1" PERMIT "$SHARED" feature/shared MOSKO_ALLOW_SHARED_COMMIT=1

echo "--- (e) shared checkout DETACHED -> REFUSE ---"
git -C "$SHARED" checkout -q --detach
try "shared + detached HEAD" REFUSE "$SHARED" __detached__

echo "--- (b) LINKED WORKTREE on feature branch -> PERMIT ---"
try "worktree + feature/wt" PERMIT "$WT" feature/wt

echo "--- (NEG CONTROL) identical to (a), hook DISARMED -> PERMIT ---"
echo "     If this REFUSES, (a)'s refusal was not attributable to the guard."
git -C "$SHARED" checkout -q feature/shared
git -C "$SHARED" config --unset core.hooksPath
try "shared + feature/shared, HOOK DISARMED" PERMIT "$SHARED" feature/shared

echo "============================================================"
echo "pass=$pass fail=$fail"
if [ $fail -eq 0 ]; then
  echo "RESULT: guard distinguishes all six states correctly."
  rm -rf "$ROOT"; exit 0
else
  echo "RESULT: MATRIX FAILED — scratch repo left at $ROOT for inspection."
  exit 1
fi
