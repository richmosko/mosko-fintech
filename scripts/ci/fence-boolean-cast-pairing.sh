#!/usr/bin/env bash
#
# fence-boolean-cast-pairing.sh -- tree-wide structural fence for the
# predicate bug this whole PR (#854) exists to fix, generalized to a
# PAIRING rather than a literal (Sec VETO-2 review, team-lead's own
# ruling): a psql read's `::text` cast-ness determines which vocabulary a
# real answer comes back in, and the two must never be crossed.
#
#   select <boolexpr>::text        -> "true" / "false" (the CAST form)
#   select <boolexpr>  (no cast)   -> "t" / "f"         (psql's own
#                                      native boolean rendering)
#
# Measured against a live Postgres both ways (this review and the
# earlier rounds of this same PR) -- never assumed. A `::text`-cast read
# compared against `"t"`/`"f"` (WHOLE OR IN PART -- `"t|t"`/`"true|true"`
# compound comparisons are the SAME defect and are detected the same
# way, Sec C-3), or an UNCAST read compared against `"true"`/`"false"`,
# can never match a real answer -- the exact defect already found and
# fixed four times over in this one PR (db-bootstrap.sh x2,
# db-role-handoff.sh, pgrst-exposure-gates.sh's B-1 VETO trigger).
#
# ⚠ WHY THIS IS A PAIRING FENCE, NOT A LITERAL SWEEP -- Sec's own
# explicit warning, load-bearing: `provision-supabase-stack.sh`'s
# `JWT_PRESENT` reads `select current_setting(...) <> '';` with NO cast
# at all, and is CORRECTLY compared against `"t"`. A blind `t` -> `true`
# find-and-replace across the tree would silently break that probe. This
# fence instead correlates each `[[ "$VAR" == "t"/"f"/"true"/"false" ]]`
# comparison with the NEAREST PRECEDING assignment to that same `$VAR`
# from a psql-shaped read (directly, via `psql_scalar`/`psql_admin`, or
# via `read_gate`), and flags only a MISMATCHED pairing:
#   cast read     + compared to "t"/"f"         -> FLAG
#   uncast read   + compared to "true"/"false"  -> FLAG
#   cast read     + compared to "true"/"false"  -> fine
#   uncast read   + compared to "t"/"f"         -> fine
#
# This is a heuristic correlation (nearest-preceding-assignment within a
# bounded lookback, cast-ness determined by scanning a bounded window
# forward from that assignment for `::text`), not a full shell parser --
# deliberately, matching this repo's own "structural, source-literal,
# never executes anything" fence convention (fence-heredoc-stdin-drain.sh
# is the sibling example). Positive-controlled against both known-correct
# pairings (STORE_HAS_PW, bash-`case`-assigned, never psql-read at all --
# excluded structurally since its assignment mentions neither "psql" nor
# "read_gate"; JWT_PRESENT, uncast, correctly compared to "t") and the
# one known-defective pairing (pgrst-exposure-gates.sh's former
# ANON_USAGE == "t", fixed in this same PR) before being trusted.
#
# SCOPE -- every `scripts/*.sh` (top-level only, matching
# fence-heredoc-stdin-drain.sh's own scope note).
#
# ⚠ KNOWN RESIDUALS, NOT ATTEMPTED HERE (Sec C-3 review: stated, not
# silently assumed covered by the "four times over" claim above) --
# this fence only sees `[[ "$VAR" (==|!=) "<literal>" ]]` comparisons:
#   - `[[ "$VAR" =~ <regex> ]]` comparisons are invisible to it --
#     db-bootstrap.sh's own MIGRATOR_STATE guard
#     (`=~ ^(true|false)\|(true|false)$`) is a real in-tree instance this
#     fence does not see (it happens to be CORRECT, not a live defect --
#     stated as a scope gap, not a finding).
#   - `case "$VAR" in true) ...` forms are likewise invisible.
#   - Cross-file comparisons (one script's own die()-message text
#     byte-matched by a DIFFERENT script's grep, e.g. provision.sh's
#     `handoff_adopt_check()` against db-role-handoff.sh's own message --
#     Sec F-2, already handled by hand in this PR) are out of scope for a
#     single-file scanner.
#
# Exit 0 only if zero mismatched pairings found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FATAL: $SCRIPTS_DIR missing" >&2; exit 2; }

# Written to a real temp file first, not nested inside `$(...)` --
# fence-heredoc-stdin-drain.sh's own header explains the bash 3.2 parser
# limitation this sidesteps; same discipline here.
PY_TMP="$(mktemp)"
trap 'rm -f "$PY_TMP"' EXIT
cat > "$PY_TMP" <<'PYEOF'
import re, sys, os

# Sec C-3 (PR #854 review): widened two ways from the original
# `"\$(\w+)"\s*(==|!=)\s*"(t|f|true|false)"`:
# (1) the literal alternation had no pipe-joined form, so it was BLIND to
#     the compound `"t|t"`/`"true|true"` comparisons -- the exact shape
#     of the ORIGINAL predicate bug this whole PR fixes (db-bootstrap.sh
#     leg B, db-role-handoff.sh leg B, db-bootstrap.sh's own
#     MIGRATOR_STATE=="t|t" check) -- caught strike-testing all four of
#     this PR's own fixed sites, not just the one (pgrst-exposure-
#     gates.sh) the original regex happened to see.
# (2) `\$(\w+)` didn't match the braced `${VAR}` form.
TOK = r'(?:t|f|true|false)'
COMPARE_LINE = re.compile(r'"\$\{?(\w+)\}?"\s*(==|!=)\s*"(' + TOK + r'(?:\|' + TOK + r')*)"')
COMMENT_LINE = re.compile(r'^\s*#')

VAR_REF = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?')

def resolve_cast(lines, var, start_idx, n, visited):
    # Nearest preceding assignment to `var`, bounded lookback. If that
    # assignment is not itself psql-shaped but DERIVES from another bash
    # variable (found while testing: VERIFY_TRIMMED="$(printf '%s'
    # "$VERIFY" | tr -d ' \n')" is a second-stage transform of $VERIFY,
    # the ACTUAL psql call two lines earlier -- a bare "not psql-shaped,
    # give up" here made this fence blind to db-bootstrap.sh's and
    # db-role-handoff.sh's own leg-B checks, exactly the sites this PR's
    # predicate fix targets), recurse into that referenced variable's own
    # nearest preceding assignment instead of giving up. `visited` bounds
    # the recursion against a reference cycle.
    if var in visited:
        return None
    visited = visited | {var}
    for j in range(start_idx, max(-1, start_idx - 200), -1):
        aline = lines[j].rstrip('\n')
        if re.match(r'^\s*(local\s+)?' + re.escape(var) + r'=', aline):
            lowered = aline.lower()
            if 'psql' in lowered or 'read_gate' in lowered:
                window_text = "".join(lines[j:min(n, j + 40)])
                return '::text' in window_text
            for ref in VAR_REF.findall(aline):
                if ref == var:
                    continue
                result = resolve_cast(lines, ref, j - 1, n, visited)
                if result is not None:
                    return result
            return None
    return None

def scan_file(path):
    with open(path) as f:
        lines = f.readlines()
    findings = []
    n = len(lines)
    for i, raw in enumerate(lines):
        line = raw.rstrip('\n')
        if COMMENT_LINE.match(line):
            continue
        for m in COMPARE_LINE.finditer(line):
            var, op, lit = m.groups()
            cast = resolve_cast(lines, var, i, n, set())
            if cast is None:
                continue
            # `lit` may be a single token or a `|`-joined compound (the
            # "t|t" shape) -- classify by whether ANY part is abbreviated
            # or full-word, since a mixed literal like "true|t" is wrong
            # on whichever half doesn't match the read's own cast-ness.
            parts = lit.split('|')
            abbrev = any(p in ('t', 'f') for p in parts)
            full = any(p in ('true', 'false') for p in parts)
            if cast and abbrev:
                findings.append((i + 1, line.strip(), 'a ::text-cast read compared against the abbreviated "t"/"f" form (in whole or in part, e.g. "t|t") -- can never match a real "true"/"false" answer'))
            elif not cast and full:
                findings.append((i + 1, line.strip(), 'an UNCAST read compared against the full-word "true"/"false" form (in whole or in part) -- can never match psql\'s own "t"/"f" rendering'))
    return findings

root = sys.argv[1]
any_findings = False
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    for lineno, text, why in scan_file(path):
        any_findings = True
        print(f"{path}:{lineno}: {why} -- {text}")
sys.exit(1 if any_findings else 0)
PYEOF

if FINDINGS="$(python3 "$PY_TMP" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [boolean-cast-pairing-treewide] one or more psql boolean reads are compared against the WRONG vocabulary for their own cast-ness (Sec VETO-2, PR #854). Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [boolean-cast-pairing-treewide] zero mismatched cast/comparison pairings found in any scripts/*.sh."
exit 0
