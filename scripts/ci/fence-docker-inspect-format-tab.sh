#!/usr/bin/env bash
#
# fence-docker-inspect-format-tab.sh -- tree-wide structural fence for the
# #841-class defect (run-7 stop, team-lead's own brief, 2026-09-21;
# widened to the general class, Sec F-1, PR #860 review): inside a Go
# template, a backslash escape sequence in the format string's LITERAL
# TEXT never expands -- it passes through as the two literal characters
# backslash + the letter. Only a string-literal ACTION -- `{{"\t"}}`,
# `{{"\n"}}`, `{{"\r"}}` -- expands to the real control character. A downstream
# `awk -F'\t'`/`cut -f`/line-split against that output then never finds
# the delimiter it expects, and a `$1=="true"` (or similar) test, or a
# per-line loop, silently never matches / never iterates.
#
# MEASURED live (run 7, realrun7.clean.log, team-lead's own box read;
# re-measured locally this PR, \t, \n AND \r, via a real container and
# `od -c` for unambiguous byte inspection -- Sec's own independent
# measurement agrees on \t/\n; \r measured this round per team-lead's
# own queued-item request to cover the full class, not just \t/\n):
#   docker inspect --format '{{.State.Running}}\t{{.Id}}'
#     -> literal bytes: t r u e \ t 4 6 4 6 ...          (backslash, t)
#   docker inspect --format '{{.State.Running}}{{"\t"}}{{.Id}}'
#     -> t r u e <TAB> 4 6 4 6 ...                        (real tab)
#   docker inspect --format '{{.State.Running}}\n{{.Id}}'
#     -> literal bytes: t r u e \ n 4 6 4 6 ...          (backslash, n)
#   docker inspect --format '{{.State.Running}}{{"\n"}}{{.Id}}'
#     -> t r u e <LF> 4 6 4 6 ...                         (real newline)
#   docker inspect --format '{{.State.Running}}\r{{.Id}}'
#     -> literal bytes: t r u e \ r 1 1 6 1 ...           (backslash, r)
#   docker inspect --format '{{.State.Running}}{{"\r"}}{{.Id}}'
#     -> t r u e <CR> 1 1 6 1 ...                          (real CR byte)
# scripts/smoke-pfin-exposure.sh:177's bare-\t form printed the literal
# bytes `true\t2f1e...` against a container that was genuinely Up,
# restarts=0 -- the smoke died "no running container found" on a fully
# successful deploy. The SAME class of defect this repo already found
# and fixed once for \t (PR #841, scripts/deploy-app.sh:441, and every
# scripts/smoke-*.sh sibling except this one) -- this fence exists so a
# future instance, of any of these escapes, is caught by CI rather than
# by a human reading a run log.
#
# SCOPED TO \t, \n AND \r -- THE THREE MEASURED HERE -- NOT a general
# "any backslash escape" claim (e.g. \\, \", \a, \b, \f, \v are not
# covered; extend ESCAPES below and re-measure before relying on this
# fence for one of those). No live \n or \r instance exists in this
# tree as of this fence's own addition (swept, see CATCH CRITERION) --
# migrator-cutover-verify.sh:156's own leg 9 already uses the CORRECT
# `{{println .}}` idiom for its own per-line need.
#
# SCOPE -- `docker inspect ... --format '...'` specifically. Deliberately
# NOT `docker ps`/`docker images`/`docker compose ... ps ... --format`:
# team-lead's own measurement (this brief) confirms Docker's `ps`/
# `images` formatter PRE-PROCESSES these escapes into real control
# characters before printing (`docker inspect` does not -- it hands the
# format string straight to Go's text/template engine with no such
# pre-processing). Every `docker ps --format '...\t...'` site in this
# tree (scripts/deploy-app.sh:451, scripts/smoke-pfin-exposure.sh:186,
# and others) is therefore CORRECT as written and must stay green --
# this fence does not touch them; matching on the literal substring
# "docker inspect" is what keeps them out of scope structurally, not a
# separate allowlist that could drift.
#
# CATCH CRITERION -- for every `docker inspect` invocation in
# `scripts/*.sh` (top-level only, matching fence-heredoc-stdin-drain.sh's
# own scope note) that carries a `--format '<template>'`: after removing
# every well-formed `{{"\t"}}`/`{{"\n"}}`/`{{"\r"}}` action (both the
# plain and the bash-double-quote-escaped `{{\"\\t\"}}`/`{{\"\\n\"}}`/
# `{{\"\\r\"}}` source forms this tree's own sshx() convention
# produces), a literal `\t`, `\n` or `\r` remaining anywhere in the
# template is a violation. Positive-controlled during development: a
# scratch copy of scripts/smoke-pfin-exposure.sh with line 177 reverted
# to the pre-fix bare-`\t` form reddens this fence (and only this
# fence's finding for that file); a scratch `\r` violation (dropped in,
# then removed) reddens at the right line, and the correct `{{"\r"}}`
# form does not false-positive; every scripts/*.sh file as committed is
# clean at all three escapes.
#
# Structural / source-literal, same convention as fence-heredoc-stdin-
# drain.sh and fence-boolean-cast-pairing.sh -- parses the tree's own
# scripts/*.sh text and executes nothing.
#
# Exit 0 only if zero violations found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FATAL: $SCRIPTS_DIR missing" >&2; exit 2; }

PY_TMP="$(mktemp)"
trap 'rm -f "$PY_TMP"' EXIT
cat > "$PY_TMP" <<'PYEOF'
import re, sys, os

# `docker inspect` ... `--format '<template>'`, template captured
# non-greedily up to the next single quote. Deliberately requires the
# literal substring "docker inspect" on the same line as "--format" --
# this is what keeps every docker ps/images/compose-ps --format site
# structurally out of scope (see this fence's own header).
CALL = re.compile(r"docker inspect(?:(?!--format).)*--format '([^']*)'")
COMMENT_LINE = re.compile(r'^\s*#')

# Sec F-1 (PR #860 review) + team-lead's own queued follow-up: widened
# from \t alone to every MEASURED escape in this class. Each entry:
# (escape char as it appears bare in the template text, the two
# well-formed string-literal-action source forms that legitimately
# produce it).
ESCAPES = [
    ('t', ['{{\\"\\\\t\\"}}', '{{"\\t"}}']),
    ('n', ['{{\\"\\\\n\\"}}', '{{"\\n"}}']),
    ('r', ['{{\\"\\\\r\\"}}', '{{"\\r"}}']),
]

def scan_file(path):
    with open(path) as f:
        lines = f.readlines()
    findings = []
    for i, raw in enumerate(lines):
        line = raw.rstrip('\n')
        if COMMENT_LINE.match(line):
            continue
        for m in CALL.finditer(line):
            template = m.group(1)
            for esc_char, good_forms in ESCAPES:
                stripped = template
                for good in good_forms:
                    stripped = stripped.replace(good, '')
                if '\\' + esc_char in stripped:
                    findings.append((i + 1, esc_char, line.strip()))
    return findings

root = sys.argv[1]
any_findings = False
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    for lineno, esc_char, text in scan_file(path):
        any_findings = True
        print(f"{path}:{lineno}: 'docker inspect --format' template carries a literal \\\\{esc_char} outside a {{\"\\\\{esc_char}\"}} string-literal action -- it will never expand to a real control character (the #841 defect class) -- {text}")
sys.exit(1 if any_findings else 0)
PYEOF

if FINDINGS="$(python3 "$PY_TMP" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [docker-inspect-format-tab-treewide] one or more 'docker inspect --format' templates carry a literal, never-expanding backslash escape (\\t, \\n, or \\r; the #841 defect class, run-7 stop). Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [docker-inspect-format-tab-treewide] zero 'docker inspect --format' templates carry a bare, never-expanding \\t, \\n, or \\r in any scripts/*.sh."
exit 0
