#!/usr/bin/env bash
#
# fence-no-source-credential-files — box-side config-file read-mechanism
# fence (Sec spec, PR #778 C-1 + the 2026-09-16 token-file incident ruling).
#
# WHY THIS EXISTS. Incident, 2026-09-16: `migrator-orchestrate.sh` read its
# box-resident config via `set -a; source "$CONF_FILE"; source "$TOKEN_FILE";
# set +a`. `source` is not a data read; it is CODE EXECUTION. The box's
# actual token file held a bare value with no `NAME=` prefix (a stale write
# predating the current mint format) — bash tried to run the token as a
# command, and bash's OWN error message echoed it to F/CTO's terminal and
# the team-lead transcript. No `echo`/`printf` in the script printed it; the
# interpreter did, which is exactly why no no-echo discipline in the script
# could have prevented it, and exactly why the fix is the READ MECHANISM,
# not a leak-check downstream of it. Fixed in the same incident's PR
# (`fix/migrator-token-file-contract`, #778): both config files are now read
# via `grep -m1 '^NAME=' | cut -d= -f2-`, never `source`d. This fence is the
# mechanical guarantee that fix doesn't rot and the same class doesn't
# reappear anywhere else under `scripts/`.
#
# CATCH CRITERION — two leading-command shapes, either one is a violation:
#   (1) A line whose first non-whitespace token is `source` or a bare `.`
#       (the POSIX synonym), followed by an argument — i.e. ANY sourcing of
#       ANY file, anywhere in scripts/**/*.sh. Scoped this bluntly on
#       purpose: every current config read in this tree already uses the
#       grep-based contract (read_kv/read_env_var), so there is zero
#       legitimate use of `source`/`.` in this directory today. A future
#       genuine need gets a NAMED, reviewed exemption in
#       scripts/ci/fence-no-source-allowlist.txt (see below) — never a
#       silent carve-out in this fence's own pattern.
#   (2) File content piped straight into `eval` (via a `cat` substitution
#       or the `<file` redirection form inside `$( )`) — the same execute-
#       the-content shape as `source`, with an extra step. Not currently
#       present anywhere in this tree.
#   This fence does NOT try to distinguish "sourcing a box-resident
#   credential path" from "sourcing anything else" — Sec's incident review
#   measured that the vulnerable calls (`source "$CONF_FILE"` /
#   `source "$TOKEN_FILE"`) never named `/etc/pfin/` or `.env` as LITERAL
#   TEXT on the source line itself; the path lived in a variable. A fence
#   that pattern-matched on literal path text would have missed the actual
#   incident. Banning the read MECHANISM catches every current and future
#   credential-path instance regardless of how the path is spelled.
#
# ALLOWLIST. `scripts/ci/fence-no-source-allowlist.txt`, one `path:line`
# per exempted hit, each with a `#` comment on the line above stating WHY
# the sourced file cannot hold a credential. Empty today (there is no
# legitimate exemption yet) — an empty file, not an absent one, so the
# fence can tell "no allowlist" from "allowlist not yet created."
#
# ⚠ BLUNT, LINE-LEVEL, GREP-BASED — DELIBERATELY, matching this repo's
# existing fence convention (fence-tinker-no-echo.sh's own header makes the
# same choice for the same reason). A comment describing the OLD `source`
# mechanism trips this exactly as code would; the fix in both is the same:
# reword the comment so it does not read as an invocation, don't exempt it.
#
# Usage:
#   bash fence-no-source-credential-files.sh <scope-dir>
#
#   <scope-dir>   Directory to scan (e.g. scripts/, or a golden-fixture dir
#                 for inversion-mode). Only *.sh files under it are scanned.
#
# Exit codes:
#   0   — scope clean (zero violations, after the allowlist is subtracted).
#   1   — one or more violations found. A statement about the CODE.
#   2   — argument / environment error (bad scope path). The scan did not run.
#
set -euo pipefail

SCOPE="${1:-}"
if [ -z "$SCOPE" ]; then
  echo "FATAL: missing scope argument." >&2
  echo "Usage: bash $(basename "$0") <scope-dir>" >&2
  exit 2
fi
if [ ! -d "$SCOPE" ]; then
  echo "FATAL: scope is not a directory: $SCOPE" >&2
  exit 2
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOWLIST="$SELF_DIR/fence-no-source-allowlist.txt"
[ -f "$ALLOWLIST" ] || {
  echo "FATAL: allowlist file missing: $ALLOWLIST -- this fence requires an explicit (even if empty) allowlist file to distinguish 'no exemptions' from 'exemption file not created'. Failing closed." >&2
  exit 2
}

# `|| true` so an empty grep result (the pass case) doesn't trip -e.
SOURCE_HITS=$(grep -rnE '^[[:space:]]*(source|\.)[[:space:]]+\S' "$SCOPE" --include='*.sh' 2>/dev/null || true)
EVAL_HITS=$(grep -rnE 'eval[[:space:]]+"?\$\((cat |<)' "$SCOPE" --include='*.sh' 2>/dev/null || true)
ALL_HITS="$(printf '%s\n%s\n' "$SOURCE_HITS" "$EVAL_HITS" | grep -v '^$' || true)"

# Subtract allowlisted path:line entries (format: "path/to/file.sh:LINE:...
# " lines emitted by grep -n already carry "path:line:" as a prefix, so a
# literal-string match against each allowlist entry is exact, not fuzzy).
if [ -s "$ALLOWLIST" ]; then
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    case "$entry" in \#*) continue ;; esac
    ALL_HITS="$(printf '%s\n' "$ALL_HITS" | grep -vF "$entry" || true)"
  done < "$ALLOWLIST"
fi

if [ -n "$ALL_HITS" ]; then
  echo "VIOLATION: box-side file content read via source/./eval instead of the grep-based contract:" >&2
  echo "$ALL_HITS" | sed 's/^/  /' >&2
  echo "" >&2
  echo "no-source-credential-files fence: scope $SCOPE failed. Failing closed." >&2
  echo "" >&2
  echo "source/./eval EXECUTE file content as shell commands. This is how the" >&2
  echo "2026-09-16 migrator-token disclosure happened: a malformed box file" >&2
  echo "was sourced and bash's own interpreter echoed the value it tried (and" >&2
  echo "failed) to run as a command -- no echo/printf in the script did it." >&2
  echo "Fix: read the expected NAME with 'grep -m1 \"^NAME=\" file | cut -d= -f2-'" >&2
  echo "(see scripts/migrator-orchestrate.sh's read_kv() for the pattern), never" >&2
  echo "source the file. If this hit is a genuine, reviewed exemption, add it to" >&2
  echo "$ALLOWLIST with a comment naming why the sourced file cannot hold a" >&2
  echo "credential -- never widen this fence's own pattern to carve it out." >&2
  exit 1
fi

echo "no-source-credential-files fence: scope $SCOPE clean (zero source/./eval-of-file-content violations)."
exit 0
