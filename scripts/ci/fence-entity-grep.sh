#!/usr/bin/env bash
#
# Entity-grep fence — HTML-entity-obscured §/# characters in the doc artifacts
#
# Problem this catches: docs/PRD/index.html, docs/SECURITY/index.html, and
# docs/ARCH/index.html are HTML — a literal "§" or "#" in prose can legally be
# written as the HTML entity &sect; or &#35; and render identically in a
# browser. But an ordinary `grep '§10'` or `grep 'mod #'` over the source file
# is byte-literal: it silently misses any line that used the entity form. This
# project runs standing §10-ledger and "Lock N mod #M" greps as a discipline
# (see CLAUDE.md / DECISIONS.md ADR-011 Decision 4) — a sweep that cannot see
# one of its own lines is a blind spot, not a formatting quirk.
#
# Catch criterion: the literal strings `&sect;` and `&#35;` MUST NOT appear
# anywhere in the target file. Both are load-bearing-content-free — §/#/&num;
# used correctly render identically in HTML — so a clean scan requires zero
# hits, not a suppressed count.
#
# Explicitly NOT catching: `&nbsp;` — out of scope by design (F/CTO-ruled).
# &nbsp; is load-bearing typography (keeps figures like "8 ARM vCores / 16 GB"
# from breaking across a line-wrap) and must not be fenced or stripped. Do NOT
# extend this fence's pattern set to include it.
#
# Fails closed on its own dependency: this fence uses only `grep`/`bash`
# builtins (no external parser). A missing or unreadable target file is
# treated as a violation of the same severity as a caught entity — it does
# NOT silently pass.
#
# Usage:
#   bash fence-entity-grep.sh <file> [file ...]
#
# Exit codes:
#   0   — every target file clean (no &sect; / &#35; occurrences).
#   1   — one or more target files carry &sect; and/or &#35; (fail-closed).
#   2   — argument error, OR a target file is missing/unreadable (fail-closed;
#         an unscannable target proves nothing, so it is never reported clean).
#

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "FATAL: no target file(s) given." >&2
  echo "Usage: bash $(basename "$0") <file> [file ...]" >&2
  exit 2
fi

VIOLATIONS=0

for TARGET in "$@"; do
  if [ ! -f "$TARGET" ] || [ ! -r "$TARGET" ]; then
    echo "FATAL: target file missing or unreadable: $TARGET" >&2
    echo "       An unscannable target is never reported clean — failing closed." >&2
    exit 2
  fi

  # Fixed-string match (-F): &sect; / &#35; are literal strings, not patterns.
  HITS=$(grep -noF -e '&sect;' -e '&#35;' "$TARGET" 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    echo "VIOLATION: entity-obscured §/# in $TARGET:" >&2
    echo "$HITS" | sed "s|^|  $TARGET:|" >&2
    HIT_COUNT=$(echo "$HITS" | wc -l | tr -d ' ')
    VIOLATIONS=$((VIOLATIONS + HIT_COUNT))
  fi
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "" >&2
  echo "entity-grep fence: $VIOLATIONS occurrence(s) of &sect;/&#35; found. Failing closed." >&2
  echo "Use the literal character (§ or #) instead — it renders identically in HTML" >&2
  echo "and stays visible to a plain-text grep. (&nbsp; is explicitly out of scope" >&2
  echo "for this fence — do not touch it.)" >&2
  exit 1
fi

echo "entity-grep fence: clean — no &sect;/&#35; in: $*"
exit 0
