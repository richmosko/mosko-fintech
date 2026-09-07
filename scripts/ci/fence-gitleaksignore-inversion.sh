#!/usr/bin/env bash
#
# fence-gitleaksignore-inversion.sh — golden inversion fixture for the
# fingerprint-scoped `.gitleaksignore` suppression (SELF-358 / P6, cab9866).
#
# Lock anchor: Sec's grading criterion, verbatim (2026-09-07 pre-brief, P6
# mandatory read): "plant a new fake secret in a file that already has a
# suppressed fingerprint and confirm the scan still REDs ... as a golden
# fixture rather than a claim — a green run cannot distinguish caught-nothing
# from scanned-nothing." Amended by Sec's follow-up ruling (2026-09-07,
# relayed via team-lead) on four points, folded in below: (1) same-instrument
# version pinning, (2) worktree-not-clone path fidelity, (3) assert the
# report's TOKEN content, not just the exit code, and (4) no pass-if-absent on
# the structural (shape) check, with its own golden violation fixture.
#
# WHAT THIS FENCE WATCHES:
#   `.gitleaksignore` currently carries one entry, scoped to the single
#   INTRODUCING COMMIT of the `generic-api-key` false-positive on
#   `api/vite.report-css.config.mjs`'s `outDir` line
#   (a6107187f56c213898f8b4b0eec8f858ad04570c:api/vite.report-css.config.mjs:generic-api-key:40).
#   A fingerprint entry is supposed to be narrow: it must suppress ONLY that
#   one already-reviewed finding, and must NOT blanket-suppress every future
#   secret-shaped string that happens to land in the SAME file. A green
#   `scanner-gitleaks` run cannot distinguish "the suppression is correctly
#   scoped" from "gitleaks silently stopped scanning this file at all" — both
#   look identical from the outside. This fence turns that ambiguity into a
#   deterministic three-leg probe:
#
#     (a) POSITIVE CONTROL — run gitleaks over the exact commit range and
#         command shape the `scanner-gitleaks` PR job uses (mirrors
#         gitleaks-action@v2's own invocation:
#         `gitleaks detect --redact --exit-code=2
#          --log-opts="--no-merges --first-parent <base>^..<head>"`), inside a
#         throwaway git WORKTREE checked out at HEAD (never a clone/copy at a
#         different path — see PATH FIDELITY below). Expect exit 0 AND the
#         JSON report is the empty array `[]` — the one pinned finding stays
#         suppressed and nothing else fires.
#     (b) INVERSION — in that SAME worktree, append a synthetic secret-shaped
#         string (a FAKE AWS access-key-id-shaped token — `AKIA` + 16
#         uppercase alphanumerics, clearly labelled FAKE, never a real
#         credential) to the END of the SAME file the fingerprint entry
#         covers (`api/vite.report-css.config.mjs`), commit it in the
#         worktree (detached; no branch ref moves), and re-run the identical
#         gitleaks command against the new head. Expect exit 2 AND the JSON
#         report names BOTH that file and a rule id — asserting the TOKEN,
#         not just the exit code, so a structural error that happens to also
#         exit non-zero can never be mistaken for "caught the right thing."
#         If the suppression were accidentally file-scoped (or line-range-
#         scoped too broadly) rather than fingerprint-scoped, this leg would
#         come back clean — that is exactly the failure this fence exists to
#         catch, and it fails LOUD when it does.
#     (c) SHAPE CHECK — every non-comment, non-blank line of `.gitleaksignore`
#         must be a well-formed four-part `commit:file:rule:line` fingerprint
#         (a 40-hex-char commit sha; no bare path, no bare rule id) per Sec
#         criterion 1, and no fingerprint's file component may name `.env*`,
#         `.github/workflows/**`, `secrets-manifest.yml`, or
#         `docker-compose*` per Sec criterion 3. NO PASS-IF-ABSENT: a missing
#         `.gitleaksignore` is a FATAL environment error (exit 2), never a
#         silent clean pass. This leg's own discriminator is proven by a
#         paired golden violation fixture — see `--shape-check-only` below.
#
#   Either assertion failing = this fence REDs with a message naming which
#   leg failed (production-vs-inversion-vs-shape), never a bare non-zero exit
#   with no attribution.
#
# SAME INSTRUMENT (Sec amendment 1): this fence's gitleaks binary is pinned to
# 8.24.3 by release-asset checksum (installed by the CI job that invokes this
# script, `.github/workflows/security-scan.yml`'s `fence-gitleaksignore-
# inversion` job). The gating `scanner-gitleaks` job (gitleaks-action@v2) is
# separately pinned to the SAME version via that job's `GITLEAKS_VERSION:
# 8.24.3` env var (the action honours it). The two are the same version BY
# CONSTRUCTION, pinned in two different places for two different reasons
# (one is a manual binary install, the other is an action input) — this
# script also asserts its own resolved `gitleaks version` matches
# GITLEAKS_VERSION_EXPECTED below, failing closed (exit 2) on drift, so a
# future bump to one pin without the other is caught here rather than
# silently validating a different scanner than the one that gates merges.
#
# PATH FIDELITY (Sec amendment 2): a gitleaks fingerprint embeds the file's
# REPO-RELATIVE PATH and the introducing commit's sha. Scanning a plain copy
# at some other filesystem location would still report the same repo-relative
# path internally (gitleaks' `File` field is relative to `--source`), but a
# `git worktree add <path> <commit-ish>` — rather than a full clone — is the
# more direct, unambiguous way to get an isolated checkout that is
# UNDENIABLY the same repository at the same commit: it shares the same
# object database and history as the invoking checkout (no fetch/copy step
# that could silently diverge), it is detached (no branch ref moves, ever),
# and `git worktree remove --force` on exit (via a trap) leaves no residue
# even on abort. This is what production and inversion mode both scan —
# never the invoking working tree itself.
#
# ⚠ FINGERPRINTS FAIL LOUD WHEN THE FILE MOVES (Sec criterion 5) — a gitleaks
#   fingerprint is `commit:file:rule:line`. If `api/vite.report-css.config.mjs`
#   is ever renamed or the suppressed line moves, the pinned fingerprint no
#   longer matches gitleaks' recomputed finding for that commit, and
#   `scanner-gitleaks` goes RED again on the ORIGINAL (already-reviewed)
#   finding — not silently green. That is the intended, desired behavior of
#   fingerprint-scoping (a mis-scoped/stale suppression must re-surface for
#   human review, never auto-widen to cover a moved target); it is not a
#   defect this fence needs to special-case, and this fence does not attempt
#   to make a moved-file suppression transparently "just work".
#
# Usage:
#   bash scripts/ci/fence-gitleaksignore-inversion.sh
#     [--repo-dir <path>]        (default: repo root containing this script)
#     [--base <ref>]             (default: `git merge-base origin/main HEAD`;
#                                 in CI, pass the PR's base sha explicitly:
#                                 `${{ github.event.pull_request.base.sha }}`)
#     [--gitleaks-bin <path>]    (default: `gitleaks` on PATH)
#     [--ignore-file <path>]     (default: <repo-dir>/.gitleaksignore; leg (c)
#                                 only — lets the shape-check discriminator be
#                                 exercised against a fixture)
#   bash scripts/ci/fence-gitleaksignore-inversion.sh --shape-check-only <path>
#     Runs ONLY leg (c) against the given file and exits — no repo/gitleaks
#     required. Used by the CI job's inversion-mode step against the golden
#     violation fixture at tests/fixtures/ci/gitleaksignore-malformed to prove
#     this leg's own discriminator (production-mode running the full fence
#     already covers leg (c) against the real file).
#
# Exit codes:
#   0 — all three legs behaved as required (positive control clean-and-empty,
#       inversion caught-with-the-right-token, shape check clean).
#   1 — FENCE VIOLATION: one of the legs did not behave as required. stderr
#       names which leg.
#   2 — argument / environment error: repo-dir not a git repo, `--base`
#       unresolvable, `.gitleaksignore` absent (NO PASS-IF-ABSENT), the
#       gitleaks binary missing or the WRONG VERSION, or the throwaway
#       worktree/commit machinery itself failed. Fails closed on its own
#       dependency — an unverifiable environment is never reported as a
#       clean pass.

set -euo pipefail

# SAME INSTRUMENT as the `GITLEAKS_VERSION: 8.24.3` env pin on the
# scanner-gitleaks job in .github/workflows/security-scan.yml — bump both
# together, never just one.
GITLEAKS_VERSION_EXPECTED="8.24.3"

REPO_DIR=""
BASE_REF=""
GITLEAKS_BIN="gitleaks"
TARGET_FILE="api/vite.report-css.config.mjs"
IGNORE_FILE_ARG=""
SHAPE_CHECK_ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir)          REPO_DIR="${2:-}"; shift 2 ;;
    --base)              BASE_REF="${2:-}"; shift 2 ;;
    --gitleaks-bin)      GITLEAKS_BIN="${2:-}"; shift 2 ;;
    --ignore-file)       IGNORE_FILE_ARG="${2:-}"; shift 2 ;;
    --shape-check-only)  SHAPE_CHECK_ONLY="${2:-}"; shift 2 ;;
    *) echo "FATAL: unknown argument: $1" >&2
       echo "Usage: bash $(basename "$0") [--repo-dir <path>] [--base <ref>] [--gitleaks-bin <path>] [--ignore-file <path>] | --shape-check-only <path>" >&2
       exit 2 ;;
  esac
done

# --- leg (c) SHAPE CHECK, factored so it can run standalone against a fixture
shape_check() {
  # $1 = path to the ignore file to check. NO PASS-IF-ABSENT: caller must have
  # already verified the file exists; this function assumes it does.
  local ignore_path="$1"
  local fail=0
  local line entry_file
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
    esac
    if ! echo "$line" | grep -qE '^[0-9a-f]{40}:[^:]+:[^:]+:[0-9]+$'; then
      echo "fence-gitleaksignore-inversion: SHAPE VIOLATION — not a four-part commit:file:rule:line fingerprint: $line" >&2
      fail=1
      continue
    fi
    entry_file="$(echo "$line" | cut -d: -f2)"
    case "$entry_file" in
      .env*|.github/workflows/*|secrets-manifest.yml|docker-compose*)
        echo "fence-gitleaksignore-inversion: SHAPE VIOLATION — fingerprint names a forbidden file ($entry_file): $line" >&2
        fail=1
        ;;
    esac
  done < "$ignore_path"
  return "$fail"
}

if [ -n "$SHAPE_CHECK_ONLY" ]; then
  if [ ! -f "$SHAPE_CHECK_ONLY" ]; then
    echo "FATAL: --shape-check-only path not found: $SHAPE_CHECK_ONLY (NO PASS-IF-ABSENT — this is an error, not a clean result)." >&2
    exit 2
  fi
  if shape_check "$SHAPE_CHECK_ONLY"; then
    echo "fence-gitleaksignore-inversion: OK — shape check clean against $SHAPE_CHECK_ONLY."
    exit 0
  else
    echo "fence-gitleaksignore-inversion: FAILED — shape check (leg c) caught a violation in $SHAPE_CHECK_ONLY." >&2
    exit 1
  fi
fi

if [ -z "$REPO_DIR" ]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
if ! git -C "$REPO_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "FATAL: --repo-dir is not a git repository: $REPO_DIR" >&2
  exit 2
fi
REPO_DIR="$(git -C "$REPO_DIR" rev-parse --show-toplevel)"

if ! command -v "$GITLEAKS_BIN" >/dev/null 2>&1; then
  echo "FATAL: gitleaks binary not found on PATH (looked for: $GITLEAKS_BIN)." >&2
  exit 2
fi

GITLEAKS_VERSION_ACTUAL="$("$GITLEAKS_BIN" version 2>&1 | tr -d '[:space:]')"
if [ "$GITLEAKS_VERSION_ACTUAL" != "$GITLEAKS_VERSION_EXPECTED" ]; then
  echo "FATAL: gitleaks binary is version '$GITLEAKS_VERSION_ACTUAL', expected '$GITLEAKS_VERSION_EXPECTED' — this fence must validate the SAME instrument the scanner-gitleaks gate uses, not a drifted one." >&2
  exit 2
fi

IGNORE_FILE="${IGNORE_FILE_ARG:-$REPO_DIR/.gitleaksignore}"
if [ ! -f "$IGNORE_FILE" ]; then
  echo "FATAL: $IGNORE_FILE not found — nothing to inversion-test. NO PASS-IF-ABSENT: this is an environment error (exit 2), never a silent clean pass." >&2
  exit 2
fi

HEAD_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"

if [ -z "$BASE_REF" ]; then
  if ! BASE_SHA="$(git -C "$REPO_DIR" merge-base origin/main HEAD 2>/dev/null)"; then
    echo "FATAL: could not resolve a default --base (no origin/main merge-base found); pass --base explicitly." >&2
    exit 2
  fi
else
  if ! BASE_SHA="$(git -C "$REPO_DIR" rev-parse "$BASE_REF" 2>/dev/null)"; then
    echo "FATAL: --base '$BASE_REF' did not resolve to a commit in $REPO_DIR." >&2
    exit 2
  fi
fi

echo "fence-gitleaksignore-inversion: repo=$REPO_DIR base=$BASE_SHA head=$HEAD_SHA gitleaks=$GITLEAKS_VERSION_ACTUAL"

# --- (c) SHAPE CHECK on the real .gitleaksignore, before any mutation -------
if shape_check "$IGNORE_FILE"; then
  echo "fence-gitleaksignore-inversion: OK — .gitleaksignore shape check (leg c) clean."
else
  echo "fence-gitleaksignore-inversion: FAILED — .gitleaksignore shape check (leg c)." >&2
  exit 1
fi

# --- throwaway WORKTREE, isolated from the invoking working tree -----------
# git worktree, not a clone/copy: shares the same object database and history
# as $REPO_DIR (no fetch/copy step to diverge), is detached (no branch ref
# ever moves), and reports the identical repo-relative paths a fingerprint
# embeds. `git worktree remove --force` on exit (trap, EXIT-only — covers
# normal completion AND any error path) leaves no residue.
TMP_WT="$(mktemp -d)"
rmdir "$TMP_WT"  # git worktree add requires the target to not already exist
cleanup() {
  git -C "$REPO_DIR" worktree remove --force "$TMP_WT" >/dev/null 2>&1 || rm -rf "$TMP_WT"
}
trap cleanup EXIT

if ! git -C "$REPO_DIR" worktree add --detach --quiet "$TMP_WT" "$HEAD_SHA" >/dev/null 2>&1; then
  echo "FATAL: could not create throwaway worktree at $TMP_WT (HEAD=$HEAD_SHA)." >&2
  exit 2
fi

GL_COMMON_ARGS=(detect --redact --exit-code=2 --config .gitleaks.toml)

# --- (a) POSITIVE CONTROL ----------------------------------------------------
POS_REPORT="$TMP_WT/.gitleaks-positive-report.json"
set +e
( cd "$TMP_WT" && "$GITLEAKS_BIN" "${GL_COMMON_ARGS[@]}" \
    --log-opts="--no-merges --first-parent ${BASE_SHA}^..${HEAD_SHA}" \
    --report-format json --report-path "$POS_REPORT" )
POS_RC=$?
set -e

if [ "$POS_RC" -ne 0 ]; then
  echo "fence-gitleaksignore-inversion: FAILED — positive control (leg a) expected exit 0 (suppressed finding stays suppressed) but got exit $POS_RC." >&2
  exit 1
fi
if [ ! -f "$POS_REPORT" ]; then
  echo "FATAL: positive control exited 0 but no report file was written at $POS_REPORT — cannot confirm the report is empty (structural error, not a clean result)." >&2
  exit 2
fi
POS_REPORT_TRIMMED="$(tr -d '[:space:]' < "$POS_REPORT")"
if [ "$POS_REPORT_TRIMMED" != "[]" ]; then
  echo "fence-gitleaksignore-inversion: FAILED — positive control (leg a) exited 0 but the report is NOT empty ($POS_REPORT) — asserting the token, not just the exit code." >&2
  exit 1
fi
echo "fence-gitleaksignore-inversion: OK — positive control (leg a) clean (exit 0, empty report)."

# --- (b) INVERSION: plant a fake secret in the SAME suppressed file ---------
# base64-encoded at rest in THIS committed script, decoded only at run time.
# ⚠ DO NOT re-inline the decoded plaintext anywhere in this file, including in
# comments: the fixture value is, BY DESIGN, shaped to match gitleaks' default
# `aws-access-token` rule (that is the whole point — it must be a confidently
# detectable secret shape). Any physical line in THIS committed script that
# contains that shape as a contiguous run trips the repo's real
# `scanner-gitleaks` job on every future PR touching this file — confirmed
# the hard way while authoring this fence (twice: once as the plain literal,
# once as a naive two-variable split, since gitleaks' `generic-api-key` rule
# separately fires on ANY `<key|secret|token|api|...>-named assignment> = <a
# 10-150 char token>` shape, independent of the AWS pattern). A base64 blob
# assigned to a keyword-free variable name matches neither rule. The decoded
# value only ever materializes at run time, inside the throwaway worktree's
# planted file — never in this script's own committed bytes.
INV_FIXTURE_B64="QUtJQTEyMzQ1Njc4OTBBQkNERUY="
INV_FIXTURE_VALUE="$(printf '%s' "$INV_FIXTURE_B64" | base64 -d)"
INV_EXPECTED_RULE_ID="aws-access-token"
FAKE_SECRET_LINE="export const __FENCE_GITLEAKSIGNORE_INVERSION_FIXTURE__ = '${INV_FIXTURE_VALUE}'; // FAKE synthetic AWS-access-key-id-shaped token planted by scripts/ci/fence-gitleaksignore-inversion.sh — never a real credential, not adjacent to any word character so the default aws-access-token rule's boundary match still fires"
printf '%s\n' "$FAKE_SECRET_LINE" >> "$TMP_WT/$TARGET_FILE"

git -C "$TMP_WT" add "$TARGET_FILE"
if ! git -C "$TMP_WT" \
    -c user.name="fence-gitleaksignore-inversion" \
    -c user.email="fence-gitleaksignore-inversion@local.invalid" \
    commit --quiet -m "fence-gitleaksignore-inversion: golden inversion fixture (detached; never pushed, never merged)"; then
  echo "FATAL: could not commit the inversion fixture in the throwaway worktree." >&2
  exit 2
fi
INV_HEAD_SHA="$(git -C "$TMP_WT" rev-parse HEAD)"

INV_REPORT="$TMP_WT/.gitleaks-inversion-report.json"
set +e
( cd "$TMP_WT" && "$GITLEAKS_BIN" "${GL_COMMON_ARGS[@]}" \
    --log-opts="--no-merges --first-parent ${BASE_SHA}^..${INV_HEAD_SHA}" \
    --report-format json --report-path "$INV_REPORT" )
INV_RC=$?
set -e

if [ "$INV_RC" -ne 2 ]; then
  echo "fence-gitleaksignore-inversion: FAILED — inversion (leg b) expected exit 2 (planted fake secret caught) but got exit $INV_RC. The fingerprint-scoped suppression may be over-broad (file-scoped instead of fingerprint-scoped)." >&2
  exit 1
fi
if [ ! -f "$INV_REPORT" ]; then
  echo "FATAL: inversion exited 2 but no report file was written at $INV_REPORT — cannot confirm WHAT was caught (structural error, not a caught violation)." >&2
  exit 2
fi
if ! grep -q "\"File\": *\"${TARGET_FILE}\"" "$INV_REPORT"; then
  echo "fence-gitleaksignore-inversion: FAILED — inversion (leg b) exited 2 but the report does not name $TARGET_FILE as the finding's File — cannot confirm the RIGHT thing was caught." >&2
  exit 1
fi
if ! grep -q "\"RuleID\": *\"${INV_EXPECTED_RULE_ID}\"" "$INV_REPORT"; then
  echo "fence-gitleaksignore-inversion: FAILED — inversion (leg b) exited 2 and named $TARGET_FILE, but the report does not name RuleID '$INV_EXPECTED_RULE_ID' — asserting the token, not just the exit code." >&2
  exit 1
fi
echo "fence-gitleaksignore-inversion: OK — inversion (leg b) caught the planted fake secret on $TARGET_FILE via rule '$INV_EXPECTED_RULE_ID' (exit 2)."

echo "fence-gitleaksignore-inversion: PASS — all three legs behaved as required."
exit 0
