#!/usr/bin/env bash
#
# fence-docker-inspect-format-tab.sh -- tree-wide structural fence for the
# #841-class defect (run-7 stop, team-lead's own brief, 2026-09-21):
# inside a Go template, `\t` in the format string's LITERAL TEXT never
# expands -- it passes through as the two literal characters backslash,
# t. Only a string-literal ACTION, `{{"\t"}}`, expands to a real tab. A
# downstream `awk -F'\t'`/`cut -f` split against that output then never
# finds the delimiter it expects, and a `$1=="true"` (or similar) test
# silently never matches.
#
# MEASURED live (run 7, realrun7.clean.log, team-lead's own box read):
# scripts/smoke-pfin-exposure.sh:177's `docker inspect --format
# '{{.State.Running}}\t{{.Id}}\t{{.Created}}'` printed the literal bytes
# `true\t2f1e...` (confirmed via `cat -A` -- no ^I anywhere) against a
# container that was genuinely Up, restarts=0 -- the smoke died "no
# running container found" on a fully successful deploy. The SAME class
# of defect this repo already found and fixed once (PR #841,
# scripts/deploy-app.sh:441, and every scripts/smoke-*.sh sibling except
# this one) -- this fence exists so the THIRD instance is the last one
# found by a human reading a run log rather than by CI.
#
# SCOPE -- `docker inspect ... --format '...'` specifically. Deliberately
# NOT `docker ps`/`docker images`/`docker compose ... ps ... --format`:
# team-lead's own measurement (this brief) confirms Docker's `ps`/
# `images` formatter PRE-PROCESSES `\t` into a real tab before printing
# (`docker inspect` does not -- it hands the format string straight to
# Go's text/template engine with no such pre-processing). Every
# `docker ps --format '...\t...'` site in this tree (scripts/deploy-
# app.sh:451, scripts/smoke-pfin-exposure.sh:186, and others) is
# therefore CORRECT as written and must stay green -- this fence does
# not touch them; matching on the literal substring "docker inspect" is
# what keeps them out of scope structurally, not a separate allowlist
# that could drift.
#
# CATCH CRITERION -- for every `docker inspect` invocation in
# `scripts/*.sh` (top-level only, matching fence-heredoc-stdin-drain.sh's
# own scope note) that carries a `--format '<template>'`: after removing
# every well-formed `{{"\t"}}` action (both the plain and the bash-
# double-quote-escaped `{{\"\\t\"}}` source forms this tree's own sshx()
# convention produces), a literal `\t` remaining anywhere in the
# template is a violation. Positive-controlled during development: a
# scratch copy of scripts/smoke-pfin-exposure.sh with line 177 reverted
# to the pre-fix bare-`\t` form reddens this fence (and only this
# fence's finding for that file); the same scratch copy re-fixed, and
# every other scripts/*.sh file as committed, is clean.
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

# Both source forms a `--format '...'` template can carry a well-formed
# string-literal tab action in, in this tree: the bash-double-quote-
# escaped form sshx()'s own "..." wrapping produces (`{{\"\\t\"}}`), and
# the plain form (`{{"\t"}}`) for a call not inside a double-quoted
# wrapper.
GOOD_FORMS = ['{{\\"\\\\t\\"}}', '{{"\\t"}}']

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
            stripped = template
            for good in GOOD_FORMS:
                stripped = stripped.replace(good, '')
            if '\\t' in stripped:
                findings.append((i + 1, line.strip()))
    return findings

root = sys.argv[1]
any_findings = False
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    for lineno, text in scan_file(path):
        any_findings = True
        print(f"{path}:{lineno}: 'docker inspect --format' template carries a literal \\\\t outside a {{\"\\\\t\"}} string-literal action -- it will never expand to a real tab (the #841 defect class) -- {text}")
sys.exit(1 if any_findings else 0)
PYEOF

if FINDINGS="$(python3 "$PY_TMP" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [docker-inspect-format-tab-treewide] one or more 'docker inspect --format' templates carry a literal, never-expanding \\t (the #841 defect class, run-7 stop). Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [docker-inspect-format-tab-treewide] zero 'docker inspect --format' templates carry a bare, never-expanding \\t in any scripts/*.sh."
exit 0
