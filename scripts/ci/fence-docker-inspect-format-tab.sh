#!/usr/bin/env bash
#
# fence-docker-inspect-format-tab.sh -- tree-wide structural fence for the
# #841-class defect (run-7 stop, team-lead's own brief, 2026-09-21;
# generalized to the full class, Sec option 2, PR #861 review): inside a
# Go template, a backslash escape sequence sitting in the format string's
# LITERAL TEXT (i.e. outside any `{{...}}` action) never expands -- Go's
# text/template engine copies literal text through byte-for-byte with NO
# escape processing at all. It passes through as the two literal
# characters backslash + the following character. Only a string-literal
# ACTION -- `{{"\t"}}`, `{{"\n"}}`, `{{"\r"}}`, ... -- evaluates as an
# actual Go string literal, which DOES process escapes, and expands to
# the real control character. A downstream `awk -F'\t'`/`cut -f`/
# line-split against that output then never finds the delimiter it
# expects, and a `$1=="true"` (or similar) test, or a per-line loop,
# silently never matches / never iterates.
#
# MEASURED live (run 7, realrun7.clean.log, team-lead's own box read;
# re-measured independently across two review rounds -- this repo's own
# DevOps and Sec each measured \t/\n/\r separately via a real container
# and `od -c` for unambiguous byte inspection, and agree):
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
# future instance, of ANY escape sequence in this class, is caught by CI
# rather than by a human reading a run log.
#
# PR #861 review history: originally shipped \t-only (the one instance
# encountered). Sec's F-1 widened it to an explicit \t/\n/\r allowlist
# -- three characters, individually measured. Sec then flagged (their
# own #854 C-3 lesson, restated): an enumerated allowlist is *still* a
# fence built for the instances encountered, not the class it names --
# \v, \f, \a, \b would each need their own measure-and-add round. Sec's
# own measurement of the underlying mechanism settles it: Go's
# text/template literal-text copy path has NO escape processing at all,
# full stop -- there is no character for which a bare backslash-escape
# in literal text expands, so a general "flag any literal `\<char>`
# outside an action" rule is the actual invariant, not an approximation
# of one. This fence therefore no longer enumerates escape characters
# (see CATCH CRITERION) -- it strips every `{{...}}` action from the
# template (an action's *contents* are Go expression/string-literal
# syntax, evaluated by the Go template engine, not raw literal text) and
# flags any backslash-plus-alphanumeric remaining in what's left over.
# Sec tree-swept this rule against the tree as it stood at PR #861
# review time: 13 `docker inspect --format` sites, zero false positives.
# The tradeoff, stated plainly: a genuinely-intended literal backslash
# followed by a letter/digit in a docker-inspect format string's literal
# text would also flag. That fails closed (the fix is trivial -- use the
# `{{"\\"}}`-style action form) and is the same shape as this fence's own
# `docker inspect`-vs-`docker ps` scoping choice: prefer a rule that
# can't rot over one that has to be kept in sync by hand.
#
# No live instance of ANY bare escape exists in this tree as of this
# fence's own addition (swept, see CATCH CRITERION) --
# migrator-cutover-verify.sh:156's own leg 9 already uses the CORRECT
# `{{println .}}` idiom for its own per-line need (an action, not
# literal text -- passes through untouched).
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
# own scope note) that carries a `--format '<template>'`: strip every
# `{{...}}` action from the template (non-nested match, `{{` to the
# nearest following `}}` -- these templates never nest braces); whatever
# text remains is, by construction, literal text Go copies through
# unprocessed. A backslash immediately followed by a letter or digit
# anywhere in that leftover literal text is a violation -- it is an
# escape sequence that will never expand. Positive-controlled during
# development: a scratch copy of scripts/smoke-pfin-exposure.sh with
# line 177 reverted to the pre-fix bare-`\t` form reddens this fence
# (and only this fence's finding for that file); scratch `\n` and `\r`
# violations (dropped in, then removed) each redden at the right line;
# the correct `{{"\t"}}`/`{{"\n"}}`/`{{"\r"}}` forms -- both the plain
# and the bash-double-quote-escaped `{{\"\\t\"}}`-style source forms
# this tree's own sshx() convention produces -- do not false-positive;
# every scripts/*.sh file as committed, including
# migrator-cutover-verify.sh's `{{println .}}` idiom, is clean.
#
# DOUBLE-QUOTED TEMPLATE COVERAGE (Sec #861 F-1 follow-up; ratified
# 2026-09-21) -- verified by scratch-file strike, not committed as a
# permanent fixture (matching this fence's own established convention:
# no sibling fence-*-strikes.sh exists for it, or for fence-heredoc-
# stdin-drain.sh / fence-boolean-cast-pairing.sh, the two siblings this
# fence's own header already cites as sharing its structural/source-
# literal shape). A scratch `scripts/*.sh` file containing
# `sshx "docker inspect --format \"{{.State.Running}}\t{{.Id}}\" $CID"`
# (the sshx-nested, once-escaped double-quote shape Sec's finding named
# as the natural place one would appear) reddens at that exact line,
# naming the bare backslash-t; the correct nested form,
# `sshx "docker inspect --format \"{{.State.Running}}{{\"\t\"}}{{.Id}}\" $CID"`,
# does not false-positive. A bare, non-nested `--format "..."` (no sshx
# wrapper) is also covered and behaves identically to the single-quoted
# case. NOT handled, deliberately (no live instance, no realistic call
# shape found for it): a second level of escaping from being nested two
# sshx/heredoc layers deep -- add a fourth CALL alternative the same way
# if that shape ever appears.
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

# `docker inspect` ... `--format '<template>'` OR `--format "<template>"`
# (bare or once-escaped) -- Sec's #861 F-1 follow-up (PR #861 review;
# ratified 2026-09-21): the single-quote-only form missed a double-
# quoted template entirely (no live instance measured, but the natural
# place to write one is inside an outer `sshx "..."` bash string, where
# interpolating a shell variable into the format argument forces double
# quotes -- and that outer wrapper forces the format argument's own
# quotes to be escaped once, `\"..\"`, not left bare). Three
# alternatives: single-quoted, bare double-quoted (a top-level, non-
# nested `--format "..."`), and once-escaped double-quoted (the sshx-
# nested `--format \"..\"` shape). All three tolerate an embedded escaped
# quote inside the template's own content without ending the match early
# -- needed because a Go template action written as `{{"\t"}}` becomes
# `{{\"\t\"}}` once its own quotes share the same single level of
# backslash-escaping as the format argument's outer delimiters (bash's
# `\"` rule doesn't distinguish "this quote is a delimiter" from "this
# quote is content" -- both are just one backslash before one doublequote
# -- so the content pattern must accept `\"` freely and rely on the
# template body never containing a stray, non-quote-paired backslash
# right before the true closing delimiter, which the greedy repetition +
# backtracking on the mandatory trailing delimiter guarantees). NOT
# handled, and deliberately so (no live instance, no realistic call
# shape found for it): a SECOND level of escaping from being nested two
# sshx/heredoc layers deep -- if that shape appears, this fence needs a
# fourth alternative, added the same way. Deliberately requires the
# literal substring "docker inspect" on the same line as "--format" --
# this is what keeps every docker ps/images/compose-ps --format site
# structurally out of scope (see this fence's own header).
CALL = re.compile(r"docker inspect(?:(?!--format).)*--format (?:'([^']*)'|\"((?:[^\"\\]|\\.)*)\"|\\\"((?:[^\"\\]|\\.)*)\\\")")
COMMENT_LINE = re.compile(r'^\s*#')

# Sec option 2 (PR #861 review): a Go template action -- `{{...}}` --
# is expression/string-literal syntax the template engine evaluates;
# only ITS contents can process an escape. Everything outside an action
# is literal text, copied through byte-for-byte with zero escape
# processing, unconditionally. Stripping every action therefore isolates
# exactly the text where a `\<char>` can never expand -- no allowlist of
# specific escape characters to keep in sync as new ones turn up.
ACTION = re.compile(r'\{\{.*?\}\}')
LITERAL_ESCAPE = re.compile(r'\\([A-Za-z0-9])')

def scan_file(path):
    with open(path) as f:
        lines = f.readlines()
    findings = []
    for i, raw in enumerate(lines):
        line = raw.rstrip('\n')
        if COMMENT_LINE.match(line):
            continue
        for m in CALL.finditer(line):
            template = next(g for g in m.groups() if g is not None)
            literal_only = ACTION.sub('', template)
            for esc in LITERAL_ESCAPE.finditer(literal_only):
                findings.append((i + 1, esc.group(1), line.strip()))
    return findings

root = sys.argv[1]
any_findings = False
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    for lineno, esc_char, text in scan_file(path):
        any_findings = True
        print(f"{path}:{lineno}: 'docker inspect --format' template carries a literal backslash-{esc_char} in its LITERAL TEXT (outside any {{...}} action) -- it will never expand to a real control character (the #841 defect class) -- {text}")
sys.exit(1 if any_findings else 0)
PYEOF

if FINDINGS="$(python3 "$PY_TMP" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [docker-inspect-format-tab-treewide] one or more 'docker inspect --format' templates carry a literal, never-expanding backslash escape in their literal text (the #841 defect class, run-7 stop). Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [docker-inspect-format-tab-treewide] zero 'docker inspect --format' templates carry a bare, never-expanding backslash escape outside a {{...}} action in any scripts/*.sh."
exit 0
