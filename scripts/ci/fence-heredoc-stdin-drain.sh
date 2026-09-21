#!/usr/bin/env bash
#
# fence-heredoc-stdin-drain.sh -- tree-wide structural fence for a
# defect class Sec found live in PR #854 (VETO-1), then team-lead widened
# to a repo-wide requirement: a `docker compose exec` (any form, with or
# without `-T`) or an interactive `docker exec ... -i`/`-it`, invoked
# inside a "remote block" -- a heredoc body fed to `bash -s`/`sh -s` over
# this repo's own `sshx()`-over-ssh convention -- ATTACHES and DRAINS
# stdin. Measured (this review, against a real local container):
#
#   bash -s <<'REMOTE'
#   echo before
#   docker exec -i <cid> true
#   echo after     # <-- never printed; the exec above ate this heredoc's
#   REMOTE         #     remaining bytes, bash hit EOF, exited 0
#
# vs. a PLAIN `docker exec <cid> <cmd>` with neither `-i` nor `-it`,
# which does NOT attach stdin (measured the same way: the trailing echo
# printed fine) -- not flagged here, it is not the risk class.
#
# Without a redirect (`</dev/null`, `<<<`, or the call opening its OWN
# nested heredoc -- an explicit stdin source), EVERY LATER LINE in that
# remote block silently never executes while the caller still reports
# success. Two live instances (db-bootstrap.sh's leg-B catalog verify and
# its Phase 2 `supabase db push` completion check) are confirmed against
# team-lead's own 2026-09-21 run (realrun3.log): the "== B." banner
# prints, then neither leg B's own OK/FATAL line nor leg C's/E's banners
# ever appear, yet the outer script still printed its own success line.
#
# WHY A FENCE, NOT JUST A FIX -- this PR's own three found-and-fixed
# instances plus two more found by widening the scan to the whole `bash
# -s`/`sh -s` heredoc-open pattern (db-bootstrap.sh's own psql_admin()
# helper, pgrst-exposure-gates.sh's identical psql_scalar()) prove this
# defect recurs by construction (copy-pasted helper shape, easy to miss)
# and is invisible to every existing fence in this repo -- they all fake
# `ssh`/`docker`, so no heredoc ever reaches a REAL docker that would
# actually drain anything. This is a purely STRUCTURAL (source-literal)
# check: it parses the scripts' own text for the shape, never executes
# them.
#
# SCOPE -- every `scripts/*.sh` (top-level only; `scripts/ci/*.sh` fences
# never open a real remote heredoc against a real docker, so they are out
# of scope for this specific risk class).
#
# WHAT THIS DOES NOT CATCH -- a remote script delivered by piping a whole
# FILE into `ssh ... < some-file.sh` (scripts/provision-vps.sh's own
# migrator-orchestrate.sh dispatch is one such case) is a cross-file
# concern this single-file scanner cannot see; not attempted here. A
# `psql`/`python3` invocation reading ITS OWN script from inherited stdin
# (never seen in this codebase outside the `python3 - ... <<'PYEOF'`
# LOCAL command-substitution shape, which is not a "remote block" in the
# sense this fence checks) is likewise out of scope -- flagged as a
# residual, not silently assumed absent.
#
# Exit 0 only if zero findings across the whole scan.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"

[[ -d "$SCRIPTS_DIR" ]] || { echo "FATAL: $SCRIPTS_DIR missing" >&2; exit 2; }

# The scanner is written to a real temp file first (a PLAIN heredoc, not
# one nested inside a `$(...)` command substitution) and then invoked as
# an ordinary command -- bash 3.2 (the operator's own shell, per this
# repo's convention) has a documented parser limitation where a heredoc
# nested directly inside `$(...)` can misparse on certain quote/escape
# sequences inside the heredoc body (measured while building this file:
# `bad substitution: no closing ')'`\ against this exact script, with the
# heredoc body unchanged apart from where it lived). Writing to a file
# first sidesteps that entirely and is bash-3.2/bash-5 portable either
# way.
PY_TMP="$(mktemp)"
trap 'rm -f "$PY_TMP"' EXIT
cat > "$PY_TMP" <<'PYEOF'
import re, sys, os

# Sec F-1 (PR #854 review): widened from `bash -s`/`sh -s` alone --
# `sshx_in() { ssh ... bash -s; }` (this repo's own second SSH-wrapper
# convention, defined identically in ~15 sibling scripts) opens the exact
# same "fed to bash -s over ssh" remote block via `sshx_in <<REMOTE`,
# with neither literal "bash" nor "-s" anywhere on that line -- a genuine
# blind spot Sec's own independent review caught first. Also matches a
# bare `sshx <<DELIM` or a raw nested `ssh ... <<DELIM` for the same
# reason, even though neither appears in this codebase today.
REMOTE_BLOCK_OPEN = re.compile(
    r'\b(bash|sh)\s+-s\b.*<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\2'
    r'|\bsshx_in\b[^\n]*<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\4'
    r'|(?<![\w.-])(sshx|ssh)\b[^\n]*<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\7'
)
HEREDOC_OPEN_ANY = re.compile(r'<<-?\s*([\'"]?)([A-Za-z_][A-Za-z0-9_]*)\1')
# `docker compose ... exec` in ANY form (with or without -T -- compose's
# own default, sans -T, still attaches stdin, -T only suppresses pty
# allocation) OR a plain `docker exec` invocation that explicitly passes
# -i/-it (interactive, attaches stdin by design). A bare `docker exec
# <container> <cmd>` with neither flag does NOT attach stdin (measured
# locally this review) -- deliberately excluded.
DOCKER_RISK = re.compile(
    r'\bdocker\s+compose\b[^\n|]*?\bexec\b'
    r'|\bdocker\s+exec\b[^\n]*\s-i\b'
)
NESTED_SSH = re.compile(r'(?<![\w.-])ssh\s')
SAFE_MARKERS = ['</dev/null', '<<<']
COMMENT_LINE = re.compile(r'^\s*#')

def scan_file(path):
    findings = []
    with open(path) as f:
        lines = f.readlines()
    n = len(lines)
    i = 0
    remote_stack = []
    generic_stack = []
    while i < n:
        raw = lines[i].rstrip('\n')
        stripped = raw.strip()
        if generic_stack and stripped == generic_stack[-1]:
            generic_stack.pop()
            if remote_stack and stripped == remote_stack[-1]:
                remote_stack.pop()
            i += 1
            continue
        in_remote = bool(remote_stack) and generic_stack and generic_stack[-1] == remote_stack[-1]
        if in_remote and len(generic_stack) == len(remote_stack) and not COMMENT_LINE.match(raw):
            m_risk = DOCKER_RISK.search(raw) or NESTED_SSH.search(raw)
            if m_risk:
                # Lookahead window widened to 6 lines (found while
                # building this fence: mint-supabase-jwt-keys.sh's own
                # supavisor probe call carries its redirect 3 lines below
                # the exec line itself -- `-o /dev/null` on an
                # intermediate curl-flag line is NOT a stdin redirect and
                # correctly does not satisfy SAFE_MARKERS, which requires
                # the LEADING `<`).
                window = [raw] + [lines[j].rstrip('\n') for j in range(i + 1, min(i + 7, n))]
                safe = any(any(m in w for m in SAFE_MARKERS) for w in window)
                if not safe and HEREDOC_OPEN_ANY.search(raw):
                    safe = True  # opens its own nested heredoc -- explicit stdin source
                # A `|` on THIS line, before the risky invocation's own
                # start, is an explicit piped stdin source (found while
                # widening this fence: migrator-cutover-verify.sh's leg
                # 11 does `printf '%s' "$OLDPW" | docker exec -i "$CID"
                # sh -c '...'` -- the exec's stdin is the printf's own
                # output, not the surrounding heredoc's remaining bytes).
                # Same exclusion Sec's own independent awk classifier
                # applied (`cmd ~ /\|[[:space:]]*docker/`).
                if not safe and '|' in raw[:m_risk.start()]:
                    safe = True
                if not safe:
                    findings.append((i + 1, raw.strip()))
        # A comment line mentioning `<<EOF`-shaped text as PROSE (this
        # file's own header, describing an example, is exactly this
        # case) must never be tracked as a real heredoc-open -- doing so
        # pushes a delimiter that is never legitimately closed (the
        # comment's own "EOF" is prose, not a line-anchored closer),
        # permanently desynchronizing generic_stack from remote_stack for
        # the REST of the file and silently blinding every later
        # in-remote check (found while building this fence: it produced
        # a false clean pass on a struck db-role-handoff.sh).
        if not COMMENT_LINE.match(raw):
            m_remote = REMOTE_BLOCK_OPEN.search(raw)
            m_any = HEREDOC_OPEN_ANY.search(raw)
            if m_any:
                generic_stack.append(m_any.group(2))
                if m_remote:
                    # Use m_any's own delimiter capture, not one of
                    # REMOTE_BLOCK_OPEN's several alternation branches
                    # (each has its delimiter in a different numbered
                    # group) -- it is the SAME heredoc-open on the SAME
                    # line either way, so m_any.group(2) is always right.
                    remote_stack.append(m_any.group(2))
        i += 1
    return findings

root = sys.argv[1]
any_findings = False
for fn in sorted(os.listdir(root)):
    path = os.path.join(root, fn)
    if not (os.path.isfile(path) and fn.endswith('.sh')):
        continue
    for lineno, text in scan_file(path):
        any_findings = True
        print(f"{path}:{lineno}: {text}")
sys.exit(1 if any_findings else 0)
PYEOF

# `if VAR=$(cmd); then rc=0; else rc=$?; fi` deliberately, not a bare
# assignment -- under this file's own `set -e`, a bare `FINDINGS="$(...)"`
# whose command exits non-zero (the whole point of this scanner, on a
# real finding) would abort THIS SCRIPT at the assignment, before RC=$?
# or the FAIL block below ever run -- the exact class of bug this same
# PR's own provision.sh fix (live_done_pgrst_flip/handoff_adopt_check)
# already had to correct once.
if FINDINGS="$(python3 "$PY_TMP" "$SCRIPTS_DIR")"; then
  RC=0
else
  RC=$?
fi

if [[ $RC -ne 0 ]]; then
  echo "FAIL: [heredoc-stdin-drain-treewide] one or more docker-exec/nested-ssh calls inside a bash -s / sh -s remote heredoc have no stdin redirect -- each will silently drain the rest of its heredoc and skip every later line while the caller still reports success (Sec VETO-1, PR #854). Offending site(s):" >&2
  printf '%s\n' "$FINDINGS" >&2
  exit 1
fi

echo "OK: [heredoc-stdin-drain-treewide] zero unredirected docker-exec/nested-ssh calls found inside any scripts/*.sh remote (bash -s / sh -s) heredoc."
exit 0
